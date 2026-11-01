-- Provider setup gates real session admission before transcript or attachment work.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider admission")
local case, check = suite.case, suite.check
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end
local function fixture()
	local f = F.new(); f.tools({ "fs" })
	f.config, f.providers = f.env.require("runtime/config"), f.env.require("provider/registry")
	f.config.set("agent.fallback", false)
	f.config.set("agent.compaction", false)
	f.sessions = f.env.require("agent/session")
	f.session = assert(f.sessions.newThread({ id = "provider-admission", ephemeral = true }))
	f.requests, f.users = 0, 0
	f.session.events:connect(function(event) if event.kind == "user" then f.users = f.users + 1 end end)
	f.loaded["provider/chat"] = {
		contextOverflow = function() return false end,
		complete = function()
			f.requests = f.requests + 1
			if f.responseDelay then f.h.sched.wait(f.responseDelay) end
			return { content = "Complete", reasoning = "", toolCalls = {}, finish = "stop" }
		end,
	}
	function f.add(enabled)
		local record = f.providers.blank("custom")
		record.label, record.baseUrl, record.apiKey = "Admission fixture", "https://admission.fixture/v1", "fixture-key"
		record.model, record.models, record.enabled = "fixture-model", { "fixture-model" }, enabled ~= false
		assert(f.providers.save(record)); return record
	end
	function f.done() f.healthy(); f.close() end
	return f
end

case("empty setup rejects short and file-backed input without mutating the conversation", function()
	local f, callbacks, saves = fixture(), 0, 0
	local store = f.env.require("runtime/attachments")
	store.save = function() saves = saves + 1; return nil, "Unexpected attachment write" end
	for _, text in ipairs({ "Hello", string.rep("long input\n", 1000) }) do
		local accepted, why = f.session.send(text, function() callbacks = callbacks + 1 end)
		check("missing provider returns an actionable refusal", not accepted and has(why, "Set up a provider before sending messages")
			and has(why, "Open Providers") and has(why, "click Save"))
	end
	f.h.sched.advance(0.2)
	check("no failed user messages, queue, title or worker are created", f.users == 0 and f.requests == 0 and callbacks == 0
		and saves == 0 and f.session.queueSnapshot().count == 0 and #f.session.log == 0
		and #f.session.ctx.messages == 0 and f.session.title == "New chat" and f.session.turns == 0 and not f.session.busy)
	f.add()
	check("saving setup permits the same draft to be sent", f.session.send("Hello"))
	f.h.sched.advance(0.2)
	check("the retried message is sent exactly once", f.users == 1 and f.requests == 1 and not f.session.busy)
	f.done()
end)

case("admission matches disabled selections and the configured fallback chain", function()
	local f = fixture()
	local disabled = f.add(false)
	check("disabled providers ask users to enable one", has(f.providers.admissionProblem(), "turn on Enabled")
		and not f.session.send("Disabled"))
	local enabled = f.add()
	assert(f.providers.setActive(disabled.id))
	check("fallback off asks users to select an enabled provider", has(f.providers.admissionProblem(), "Use this provider")
		and not f.session.send("Disabled selection"))
	f.config.set("agent.fallback", true)
	enabled.health = { cooldownUntil = f.env.require("runtime/clock").ms() + 60000 }
	check("an enabled fallback remains admissible even while cooling", f.providers.admissionProblem() == nil and f.session.send("Use fallback"))
	f.h.sched.advance(0.2)
	check("fallback preserves ordinary inference", f.users == 1 and f.requests == 1)
	enabled.keyPaused = { true }
	check("saved credential policy remains a request concern", f.providers.admissionProblem() == nil)
	f.done()
end)

case("restored messages remain held until an enabled provider can resume them", function()
	local f = fixture()
	assert(f.session.restoreQueue({ version = 1, items = { { id = "restored", state = "queued", text = "Held draft", files = {}, images = {} } } }))
	local accepted, why = f.session.resumeQueue()
	check("missing provider rejects Resume without releasing the saved queue", not accepted and has(why, "Set up a provider")
		and f.session.queueSnapshot().held and f.session.queueSnapshot().count == 1 and f.users == 0 and f.requests == 0)
	f.add()
	check("saving a provider does not silently resume old input", f.session.queueSnapshot().held and f.requests == 0)
	check("explicit Resume succeeds after setup", f.session.resumeQueue())
	f.h.sched.advance(0.2)
	check("restored input is sent once after explicit Resume", f.users == 1 and f.requests == 1 and f.session.queueSnapshot().count == 0)
	f.done()
end)

case("provider removal during attachment preparation rejects the pending admission", function()
	local f, result = fixture(), nil
	f.add()
	local store = f.env.require("runtime/attachments")
	local save = store.save
	store.save = function(text, name, aborted) f.h.sched.wait(0.2); return save(text, name, aborted) end
	f.h.sched.spawn(function() result = { f.session.send(string.rep("pending source\n", 1000)) } end)
	check("attachment preparation owns an uncommitted reservation", f.session.preparing and not f.session.busy)
	f.config.set("providers.list", {})
	f.h.sched.advance(0.5)
	check("yielded preparation rechecks provider setup before committing", result and result[1] == false and has(result[2], "Set up a provider")
		and not f.session.preparing and f.session.queueSnapshot().count == 0 and f.session.title == "New chat")
	check("unconfigured pending input never enters history or inference", f.users == 0 and f.requests == 0 and #f.session.ctx.messages == 0)
	f.done()
end)

case("provider removal preserves the accepted response and holds pending follow-ups", function()
	local f, completed, followups = fixture(), 0, 0
	f.add(); f.responseDelay = 0.2
	assert(f.session.send("Accepted", function() completed = completed + 1 end))
	assert(f.session.send("Earlier follow-up", function() followups = followups + 1 end))
	f.config.set("providers.list", {})
	check("new follow-ups cannot be admitted after provider removal", not f.session.send("Unconfigured follow-up"))
	f.h.sched.advance(0.5)
	local queue = f.session.queueSnapshot()
	check("already accepted inference finishes under its original owner", completed == 1 and f.requests == 1 and f.users == 1 and not f.session.busy)
	check("unapplied follow-ups remain held without phantom user messages", followups == 0 and queue.held and queue.count == 1
		and queue.items[1].text == "Earlier follow-up" and has(queue.reason, "Set up a provider"))
	f.done()
end)

suite.finish()
