-- Focused source-level background delegation, report paging and prompt contracts.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Subagent tools")
local case, check = suite.case, suite.check

local function setup()
	local f = F.new()
	f.tools({ "agentself" })
	local parent = f.env.require("agent/session").create({ title = "Parent fixture" })
	local agents = f.env.require("agent/subagent")
	f.loaded["agent/loop"] = { run = function(child, text)
		child.emit("tool:call", { id = "read", name = "file_read" })
		child.emit("tool:progress", { id = "read", text = "Inspecting delegated source" })
		f.h.sched.wait(1)
		child.emit("tool:result", { id = "read", text = "Read complete" })
		return "Report for " .. text
	end }
	return f, agents, parent, parent.toolContext()
end

case("background dispatch leaves the parent free to work and collect the report later", function()
	local f, agents, parent, ctx = setup()
	local at = f.h.sched.now
	local launch = f.dispatch("dispatch_agent", { task = "Inspect a separate file" }, ctx, 0)
	local record = assert(agents.get(launch.data and launch.data.id))
	check("dispatch returns an id before its child finishes", launch.ok and launch.data.background and f.h.sched.now == at
		and record.status == "running" and record.report == nil)
	local own = f.dispatch("todo_write", { items = { { text = "Review the main file", status = "active" } } }, ctx, 0)
	check("the parent can perform useful work while its child is active", own.ok and parent.todos[1].text == "Review the main file" and record.status == "running")
	local progress = f.dispatch("agent_status", { id = record.id }, ctx, 0)
	check("status supplies scoped current progress without a report", progress.ok and not progress.data.complete
		and progress.text:find("Inspecting delegated source", 1, true) and record.collectedRun == nil)
	local report = f.dispatch("agent_status", { id = record.id, wait_seconds = 5 }, ctx, 1.5)
	check("bounded waiting returns early with the completed report", report.ok and report.data.complete and report.data.waited <= 1.25
		and report.text:find("Report for Inspect a separate file", 1, true) and report.data.collected
		and record.collectedRun == record.runs)
	f.healthy(); f.close()
end)

case("follow-ups default to background while explicit blocking compatibility remains", function()
	local f, agents, parent, ctx = setup()
	local launch = f.dispatch("dispatch_agent", { task = "First task" }, ctx, 0)
	local record = assert(agents.get(launch.data.id))
	f.h.sched.advance(1.1)
	f.loaded["agent/loop"].run = function(nextChild, text)
		f.h.sched.wait(1)
		return "Report for " .. text
	end
	local second = f.dispatch("dispatch_agent", { task = "A second task" }, ctx, 0)
	local available = f.dispatch("agent_status", { wait_seconds = 30 }, ctx, 0)
	check("unread completed reports return without waiting on another worker", available.ok and available.data.waited == 0
		and available.data.live == 1 and agents.get(second.data.id).status == "running")
	f.dispatch("agent_status", { id = record.id }, ctx, 0)
	local child, at = record.session, f.h.sched.now
	local follow = f.dispatch("agent_followup", { agent = record.id, message = "Read another file" }, ctx, 0)
	check("a follow-up returns immediately and reuses the same session", follow.ok and follow.data.background and follow.data.id == record.id
		and f.h.sched.now == at and record.session == child and record.status == "running" and record.collectedRun == nil)
	f.h.sched.advance(1.1)
	local blocked = f.dispatch("agent_followup", { agent = record.id, message = "Final detail", background = false }, ctx, 1.2)
	check("background false retains the blocking written-report result", blocked.ok and blocked.text:find("Report for Final detail", 1, true)
		and record.status == "done" and not record.background)
	local direct = f.dispatch("dispatch_agent", { task = "Explicit blocking task", background = false }, ctx, 1.2)
	check("explicit blocking dispatch also returns its full report", direct.ok and direct.text:find("Report for Explicit blocking task", 1, true))
	check("only blocking mode uses the long child timeout", f.registry.get("dispatch_agent").timeout({}) == 10
		and f.registry.get("dispatch_agent").timeout({ background = false }) == agents.toolTimeout())
	f.healthy(); f.close()
end)

case("reports remain exact and paginated inside small tool budgets", function()
	local f, agents, parent, ctx = setup()
	local original = string.rep("line \226\128\148 exact whitespace\n", 110)
	f.loaded["agent/loop"].run = function() return original end
	local launch = f.dispatch("dispatch_agent", { task = "Long report" }, ctx, 0)
	local record = assert(agents.get(launch.data.id))
	f.env.require("runtime/config").set("agent.resultCap", 700)
	local listing = f.dispatch("agent_status", {}, ctx, 0)
	check("listing completed agents does not copy or acknowledge their reports", listing.ok and listing.data.total == 1 and listing.data.live == 0
		and not listing.text:find("exact whitespace", 1, true) and record.collectedRun == nil)
	local skipped = f.dispatch("agent_status", { id = record.id, offset = #original + 1 }, ctx, 0)
	check("skipping to eof cannot claim an unread report was collected", skipped.ok and skipped.data.eof and not skipped.data.collected and record.collectedRun == nil)
	local offset, pieces, pages = 1, {}, 0
	repeat
		local result = f.dispatch("agent_status", { id = record.id, offset = offset, limit = 6000 }, ctx, 0)
		check("report pages remain within budget without registry truncation", result.ok and #result.text <= 700 and not result.truncated)
		pieces[#pieces + 1] = result.text:match("^[^\n]*\n(.*)$")
		pages = pages + 1
		if pages == 1 then
			local epoch = record.runEpoch
			f.loaded["agent/loop"].run = function() return "Later report" end
			for index = 1, 6 do
				local later = f.dispatch("dispatch_agent", { task = "Later task " .. index }, ctx, 0)
				f.dispatch("agent_status", { id = later.data.id }, ctx, 0)
			end
			check("report identity survives child context expiry between pages", record.session == nil
				and record.runEpoch == epoch and record.parent == parent)
		end
		offset = result.data.nextOffset
		if offset then check("partial reads do not acknowledge completion", record.collectedRun == nil) end
	until not offset
	check("all UTF-8 bytes and line endings are available before collection", pages > 1 and table.concat(pieces) == original and record.collectedRun == record.runs)
	f.healthy(); f.close()
end)

case("status ownership, admission cancellation and bounded polling stay independent", function()
	local f, agents, parent, ctx = setup()
	f.loaded["agent/loop"].run = function(child)
		while not child.aborted() do f.h.sched.wait(0.25) end
		return "Stopped"
	end
	local launch = f.dispatch("dispatch_agent", { task = "Long-running fixture" }, ctx, 0)
	local record = assert(agents.get(launch.data.id))
	local other = f.env.require("agent/session").create({ title = "Other fixture" })
	local foreign = f.dispatch("agent_status", { id = record.id }, other.toolContext(), 0)
	local listing = f.dispatch("agent_status", {}, other.toolContext(), 0)
	check("other conversations cannot inspect a child's progress", not foreign.ok and listing.ok and listing.data.total == 0)
	local before = #agents.records
	local cancelled = { session = parent, aborted = function() return true end }
	local rejected = f.dispatch("dispatch_agent", { task = "Must not start" }, cancelled, 0)
	check("an aborted caller cannot launch work", not rejected.ok and #agents.records == before)
	local deadline = f.dispatch("agent_status", { id = record.id, wait_seconds = 1 }, ctx, 1.1)
	check("a bounded wait reports ongoing work without stopping it", deadline.ok and not deadline.data.complete and deadline.data.waited >= 1
		and deadline.data.waited <= 1.25 and record.status == "running")
	local stopWait = false
	f.h.sched.delay(0.4, function() stopWait = true end)
	local waitingCtx = { session = parent, aborted = function() return stopWait end }
	local interrupted = f.dispatch("agent_status", { id = record.id, wait_seconds = 30 }, waitingCtx, 0.75)
	check("cancelling a status wait promptly returns without cancelling its child", not interrupted.ok and interrupted.text:find("aborted", 1, true)
		and record.status == "running" and not record.session.abortFlag)
	agents.stop(record.id); f.h.sched.advance(0.3)
	f.healthy(); f.close()
end)

case("main and child prompts require independent work, periodic checks and collected reports", function()
	local f, agents, parent = setup()
	local prompt = f.env.require("agent/prompt")
	for _, text in ipairs({ prompt.build({ session = parent }), prompt.subagent("Inspect source") }) do
		check("delegation reserves parent work and checks periodically", text:find("Reserve useful independent work for yourself", 1, true)
			and text:find("every 2-3 work batches or about 15-30 seconds", 1, true))
		check("polling is bounded and completion requires report collection", text:find("Do not tight-poll", 1, true)
			and text:find("wait_seconds=15-30", 1, true) and text:find("Follow nextOffset with offset until eof", 1, true))
		check("concurrent edits and stale reports are explicitly avoided", text:find("Do not edit the same file", 1, true)
			and text:find("required delegated work is still running or unread", 1, true))
	end
	f.healthy(); f.close()
end)

suite.finish()
