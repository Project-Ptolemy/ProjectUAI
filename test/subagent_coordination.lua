-- Parent turn coordination against real source tools and synthetic providers.
-- Run from the repository root: luajit test/subagent_coordination.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Subagent coordination")
local case, check = suite.case, suite.check

local function fixture()
	local f = F.new()
	f.tools({ "agentself" })
	f.sessions, f.children = f.env.require("agent/session"), f.env.require("agent/subagent")
	local providers = f.env.require("provider/registry")
	local provider = { id = "fixture", label = "Fixture", model = "fixture-model" }
	providers.active = function() return provider end
	providers.chain = function() return { provider } end
	f.env.require("agent/prompt").subagent = function(task) return "Complete this fixture task: " .. task end
	f.env.require("runtime/config").set("agent.compaction", false)
	f.env.require("runtime/config").set("agent.repeatLimit", 3)
	f.parent = assert(f.sessions.newThread())
	f.parent.systemPrompt = "Fixture parent instructions"
	f.util = f.env.require("runtime/util")
	function f.call(name, args, id)
		return { id = id or (name .. "-call"), type = "function", ["function"] = { name = name, arguments = f.util.encode(args) } }
	end
	function f.response(content, calls)
		return { content = content or "", reasoning = "", toolCalls = calls or {}, finish = "stop" }
	end
	function f.provider(fn) f.env.require("provider/chat").complete = fn end
	function f.worker(request, seconds)
		local deadline = f.h.sched.now + seconds
		while f.h.sched.now < deadline do
			if request.aborted() then return nil, "aborted" end
			f.h.sched.wait(math.min(0.1, deadline - f.h.sched.now))
		end
		return f.response("The child verified the delegated result.")
	end
	return f
end

local function hasMessage(messages, needle, role)
	for _, message in ipairs(messages) do
		if (not role or message.role == role) and tostring(message.content):find(needle, 1, true) then return true end
	end
	return false
end

local function hasReminder(messages, needle)
	for _, message in ipairs(messages) do
		if message.role == "user" and message.internal == true and tostring(message.content):find(needle, 1, true) then return true end
	end
	return false
end

case("parent works independently and collects reports before its final answer", function()
	local f = fixture()
	local mainRequests, ownWork, firstWorkAt, childFinishedAt = 0, 0, nil, nil
	f.registry.register({ name = "fixture_work", group = "meta", risk = "read", description = "Independent fixture work",
		parameters = { type = "object", properties = {}, required = {} },
		run = function()
			ownWork = ownWork + 1
			firstWorkAt = firstWorkAt or f.h.sched.now
			f.h.sched.wait(ownWork == 1 and 0.1 or 2.2)
			return "Independent work " .. ownWork .. " completed."
		end })
	f.provider(function(_, request)
		if request.session.headless then
			local result = f.worker(request, 2)
			childFinishedAt = f.h.sched.now
			return result
		end
		mainRequests = mainRequests + 1
		if mainRequests == 1 then return f.response("Delegating the check.", { f.call("dispatch_agent", { task = "Check delegated source" }) }) end
		if mainRequests == 2 then
			check("dispatch returns its id while its child is still outstanding", #f.children.pending(f.parent) == 1
				and hasMessage(request.messages, f.children.records[1].id, "tool"))
			return f.response("I will complete the independent part.", { f.call("fixture_work", {}, "own-first") })
		end
		if mainRequests == 3 then return f.response("Premature answer while the child is running.") end
		if mainRequests == 4 then
			check("the next request receives an internal delegation reminder", hasReminder(request.messages, "[UAI delegation status]"))
			return f.response("Continuing the remaining independent work.", { f.call("fixture_work", {}, "own-second") })
		end
		if mainRequests == 5 then
			check("an uncollected completed report remains pending", f.children.records[1].status == "done" and #f.children.pending(f.parent) == 1)
			return f.response("Premature answer before reading the report.")
		end
		if mainRequests == 6 then
			check("completed reports are included in the coordination guard", hasReminder(request.messages, "report not collected"))
			return f.response("Collecting the verification.", { f.call("agent_status", { id = f.children.records[1].id, wait_seconds = 1 }) })
		end
		check("the final request contains the collected child report", mainRequests == 7
			and hasMessage(request.messages, "The child verified the delegated result.", "tool") and #f.children.pending(f.parent) == 0)
		return f.response("Completed both parts and incorporated the child's verification.")
	end)
	local reply
	assert(f.parent.send("Complete both parts", function(value) reply = value end))
	f.h.sched.advance(3)
	check("the parent performs real work before the child finishes", ownWork == 2 and firstWorkAt < childFinishedAt)
	check("the parent finishes after collection without stopping a completed child", not f.parent.busy and reply
		and f.children.records[1].status == "done" and not f.children.records[1].stopRequested)
	local premature, finals, users = 0, 0, 0
	for _, event in ipairs(f.parent.log) do
		if event.kind == "assistant:text" then
			if event.final then finals = finals + 1 end
			if event.text:find("Premature answer", 1, true) then premature = premature + 1; check("premature prose remains nonfinal", not event.final) end
		elseif event.kind == "user" then users = users + 1 end
	end
	check("only the collected answer is final and reminders are not user turns", premature == 2 and finals == 1 and users == 1)
	local dropped, filled = f.parent.ctx.repair()
	check("coordination preserves valid tool-result pairs", dropped == 0 and filled == 0)
	f.healthy(); f.close()
end)

case("bounded status waits remain callable beyond the repeat limit", function()
	local f = fixture()
	local mainRequests, polls = 0, 0
	f.provider(function(_, request)
		if request.session.headless then return f.worker(request, 4.5) end
		mainRequests = mainRequests + 1
		if mainRequests == 1 then return f.response("", { f.call("dispatch_agent", { task = "Slow bounded check" }) }) end
		local record = f.children.records[1]
		if record.collectedRun ~= nil and record.collectedRun == (record.runs or 0) then return f.response("The slow check is collected.") end
		polls = polls + 1
		return f.response("", { f.call("agent_status", { id = record.id, wait_seconds = 1 }, "poll-" .. polls) })
	end)
	assert(f.parent.send("Wait when independent work is exhausted")); f.h.sched.advance(6)
	check("multiple bounded waits collect the result", polls >= 4 and not f.parent.busy and #f.children.pending(f.parent) == 0)
	check("legitimate waiting does not trip repeat detection", not hasMessage(f.parent.ctx.messages, "This exact call has already been made"))
	f.healthy(); f.close()
end)

case("zero-wait status polling still hits the normal repeat guard", function()
	local f = fixture(); local requests = 0
	f.provider(function()
		requests = requests + 1
		if requests <= 3 then return f.response("", { f.call("agent_status", { wait_seconds = 0 }, "immediate-" .. requests) }) end
		return f.response("Stopped repetitive immediate polling.")
	end)
	assert(f.parent.send("Inspect idle workers")); f.h.sched.advance(0.1)
	check("immediate polls retain repetition protection", not f.parent.busy
		and hasMessage(f.parent.ctx.messages, "This exact call has already been made 3"))
	f.healthy(); f.close()
end)

case("Stop reaches an active parent's children before the parent settles", function()
	local f = fixture(); local requests = 0
	f.provider(function(_, request)
		if request.session.headless then return f.worker(request, 10) end
		requests = requests + 1
		if requests == 1 then return f.response("", { f.call("dispatch_agent", { task = "Cancellable check" }) }) end
		while not request.aborted() do f.h.sched.wait(0.1) end
		return nil, "aborted"
	end)
	assert(f.parent.send("Work until stopped")); f.h.sched.advance(0.1)
	local child = f.children.records[1]
	check("parent and child are active before Stop", f.parent.busy and child.status == "running")
	check("Stop immediately reaches owned children", f.parent.abort() and child.stopRequested and child.session.aborted())
	f.h.sched.advance(0.3)
	check("cooperative cancellation settles both workers", not f.parent.busy and child.status == "stopped" and f.children.live == 0)
	f.healthy(); f.close()
end)

case("an idle parent's Stop cancels only its own background children", function()
	local f = fixture()
	f.provider(function(_, request) return f.worker(request, 10) end)
	local other = assert(f.sessions.newThread())
	local owned = assert(f.children.start({ parent = f.parent, task = "Owned idle child" }))
	local unrelated = assert(f.children.start({ parent = other, task = "Other parent's child" }))
	f.h.sched.advance(0.1)
	check("idle Stop reports the child work it cancelled", not f.parent.busy and f.parent.abort() and owned.stopRequested)
	check("another conversation's child remains active", not unrelated.stopRequested and not unrelated.session.aborted())
	f.h.sched.advance(0.3)
	check("the owned worker observes cancellation", owned.status == "stopped" and unrelated.status == "running")
	f.healthy(); f.close(); f.h.sched.advance(0.3)
	check("unload also settles the unrelated background child", unrelated.status == "stopped" and f.children.live == 0)
end)

for _, ending in ipairs({ "provider failure", "internal failure", "step limit", "time limit" }) do
	case("terminal " .. ending .. " stops uncollected children before onDone", function()
		local f = fixture(); local requests, settledWithStop = 0, false
		if ending == "step limit" then f.parent.maxTurns = 2 end
		if ending == "time limit" then f.parent.budgetSeconds = 0.05 end
		f.provider(function(_, request)
			if request.session.headless then return f.worker(request, 10) end
			requests = requests + 1
			if requests == 1 then return f.response("", { f.call("dispatch_agent", { task = "Child of terminal parent" }) }) end
			if ending == "provider failure" then return nil, "fixture refused the request", { terminal = true } end
			if ending == "internal failure" then error("fixture parent failure") end
			if ending == "time limit" then f.h.sched.wait(0.1) end
			return f.response("Incomplete parent result.")
		end)
		assert(f.parent.send("Stop children if this turn cannot finish", function()
			settledWithStop = not f.parent.busy and f.children.records[1].stopRequested == true
		end))
		f.h.sched.advance(0.5)
		check("terminal settlement stops children before notifying its caller", settledWithStop
			and f.children.records[1].status == "stopped" and f.children.live == 0)
		check("terminal exits release pending coordination ownership", #f.children.pending(f.parent) == 0)
		for _, event in ipairs(f.parent.log) do
			if event.kind == "assistant:text" then check("unfinished prose is never final", not event.final) end
		end
		f.healthy(); f.close()
	end)
end

suite.finish()
