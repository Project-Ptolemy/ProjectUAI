-- Real dispatch/rate waits with isolated connection-check ownership.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Connection test lifetime")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new()
	f.config, f.providers = f.env.require("runtime/config"), f.env.require("provider/registry")
	f.record = f.providers.blank("ollama")
	f.record.model, f.record.models = "connection-fixture", { "connection-fixture" }
	assert(f.providers.save(f.record))
	f.tests = f.env.require("provider/connection_test")
	f.loaded["agent/session"] = { current = function() return f.session end }
	f.session = { busy = true, abortFlag = false, status = "Unrelated conversation working" }
	f.commands = f.env.require("net/bridge_commands")
	f.h.http.handler = function(entry)
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "OK" }, finish_reason = "stop" } } }) }
	end
	function f.consume()
		assert(f.run(function() return f.env.require("provider/chat").complete(f.record,
			{ messages = { { role = "user", content = "First attempt" } }, attempts = 1 }) end))
	end
	function f.finish() f.healthy(); f.close() end
	return f
end

case("asynchronous tests publish bounded detached state and leave chat alone", function()
	local f = fixture()
	local reply = f.h.http.handler
	f.h.http.handler = function(entry)
		local response = reply(entry)
		response.delay = 0.15
		return response
	end
	local started = f.commands.run({ type = "provider:test", id = f.record.id, testId = "test-one" })
	check("a browser gets its owned id immediately", started.id == "test-one" and started.state == "running")
	f.h.sched.advance(0.3)
	local finished = f.tests.state(f.record.id)
	check("the actual inference test completes", finished.state == "succeeded" and finished.text == "Connected: OK" and f.h.http.requestCount == 1)
	check("testing cannot change chat ownership or status", f.session.busy and not f.session.abortFlag and f.session.status == "Unrelated conversation working")
	finished.state, finished.text = "waiting", "modified copy"
	check("callers cannot corrupt the retained check", f.tests.state(f.record.id).state == "succeeded" and f.tests.state(f.record.id).text == "Connected: OK")
	local replay = f.commands.run({ type = "provider:test", id = f.record.id, testId = "test-one" })
	f.h.sched.advance(0.1)
	check("same completed id cannot dispatch again", replay.state == "succeeded" and f.h.http.requestCount == 1)
	f.finish()
end)

case("Cancel test releases a rate waiter without sending or stopping chat", function()
	local f = fixture(); assert(f.config.set("agent.requestsPerMinute", 1)); f.consume()
	assert(f.commands.run({ type = "provider:test", id = f.record.id, testId = "waiting-one" }))
	f.h.sched.advance(0.3)
	check("rate admission exposes its own waiting state", f.tests.state(f.record.id).state == "waiting" and f.h.http.requestCount == 1)
	local wrong = f.commands.run({ type = "provider:test:cancel", id = f.record.id, testId = "other-id" })
	check("another identity cannot cancel the check", not wrong.cancelled and f.tests.state(f.record.id).state == "waiting")
	local repeated = f.commands.run({ type = "provider:test", id = f.record.id, testId = "waiting-one" })
	check("same running id observes existing work", repeated.state == "waiting")
	local duplicate = pcall(f.commands.run, { type = "provider:test", id = f.record.id, testId = "duplicate" })
	check("a second current check cannot start", not duplicate and f.h.http.requestCount == 1)
	assert(f.commands.run({ type = "provider:test:cancel", id = f.record.id, testId = "waiting-one" }).cancelled)
	f.h.sched.advance(0.3)
	local state = f.env.require("runtime/inference_rate").state()
	check("cancellation settles and frees admission without another attempt", f.tests.state(f.record.id).state == "cancelled"
		and state.queued == 0 and state.held == 0 and state.tracked == 1 and f.h.http.requestCount == 1)
	check("main chat keeps working", f.session.busy and not f.session.abortFlag)
	check("late cancellation is idempotent", not f.commands.run({ type = "provider:test:cancel", id = f.record.id, testId = "waiting-one" }).cancelled)
	f.finish()
end)

case("connection replacement invalidates a pending check and no stale success appears", function()
	local f = fixture(); assert(f.config.set("agent.requestsPerMinute", 1)); f.consume()
	assert(f.tests.start(f.record, "replaced")); f.h.sched.advance(0.2)
	local edited = f.env.require("runtime/util").deepCopy(f.record)
	edited.baseUrl = "http://localhost:4321/v1"
	assert(f.providers.save(edited)); f.h.sched.advance(0.3)
	check("old connection authority cancels its waiting test", f.tests.state(edited.id).state == "cancelled" and f.h.http.requestCount == 1)
	check("no queued permit survives replacement", f.env.require("runtime/inference_rate").state().queued == 0)
	f.finish()
end)

case("browser ownership changes cancel native Game checks while probe health does not", function()
	local f = fixture(); assert(f.config.set("agent.requestsPerMinute", 1)); f.consume()
	local owner = { enabled = true, token = "synthetic-owner", instance = "desktop-one", port = 28791 }
	local healthy = true
	f.loaded["net/bridge_connection"] = {
		get = function(retain) return retain and owner or { enabled = healthy } end,
		enabled = function() return healthy end,
	}
	assert(f.tests.start(f.record, "game-owner")); f.h.sched.advance(0.2)
	healthy = false; f.h.sched.advance(0.2)
	check("a failed desktop probe retains the authenticated test owner", f.tests.state(f.record.id).state == "waiting" and f.h.http.requestCount == 1)
	owner = { enabled = true, token = "synthetic-next-owner", instance = "desktop-two", port = 28791 }
	f.h.sched.advance(0.3)
	check("a replacement browser owner cancels even native Game admission", f.tests.state(f.record.id).state == "cancelled"
		and f.env.require("runtime/inference_rate").state().queued == 0 and f.h.http.requestCount == 1)
	f.finish()
end)

case("cancellation remains available after a vault challenge without a conversation", function()
	local f = fixture(); assert(f.config.set("agent.requestsPerMinute", 1)); f.consume()
	assert(f.tests.start(f.record, "vault-wait")); f.h.sched.advance(0.2)
	f.config.requireVault(); f.session = nil
	local result = f.commands.run({ type = "provider:test:cancel", id = f.record.id, testId = "vault-wait" })
	check("locked storage cannot trap cancellation behind chat admission", result.cancelled == true)
	f.h.sched.advance(0.3)
	check("vault challenge sends no test inference", f.tests.state(f.record.id).state == "cancelled" and f.h.http.requestCount == 1)
	f.finish()
end)

case("unload cancels owned waits and invalid identities allocate nothing", function()
	local f = fixture(); assert(f.config.set("agent.requestsPerMinute", 1)); f.consume()
	for _, id in ipairs({ "", "bad id", string.rep("x", 129), "bad\0id" }) do
		check("invalid check identity is rejected", not f.tests.start(f.record, id))
	end
	assert(f.tests.start(f.record, "unload-wait")); f.h.sched.advance(0.2)
	f.close(); f.h.sched.advance(0.3)
	check("disposed tests cannot resume or retain public state", f.tests.state(f.record.id) == nil and f.h.http.requestCount == 1)
	check("disposed service rejects new work", not f.tests.start(f.record, "after-unload"))
	f.healthy()
end)

case("legacy synchronous test still returns its connection result", function()
	local f = fixture()
	local result = f.run(function() return f.commands.run({ type = "provider:test", id = f.record.id }) end)
	check("old browser command shape remains compatible", result.text == "Connected: OK" and type(result.ms) == "number" and f.h.http.requestCount == 1)
	f.finish()
end)

case("a scheduling failure releases test ownership and captured credentials", function()
	local f = fixture()
	local clock = f.env.require("runtime/clock"); local spawn, abandoned = clock.spawn
	clock.spawn = function(worker) abandoned = worker; error("synthetic scheduling failure", 0) end
	local started, problem = f.tests.start(f.record, "unscheduled")
	clock.spawn = spawn
	check("the browser receives a bounded startup failure", started == nil and problem == "Connection test could not start"
		and f.tests.state(f.record.id).state == "failed")
	abandoned(); f.h.sched.advance(0.3)
	check("a failed scheduler's retained callback cannot dispatch", f.h.http.requestCount == 0)
	assert(f.tests.start(f.record, "after-scheduler")); f.h.sched.advance(0.3)
	check("another test can acquire the released ownership", f.tests.state(f.record.id).state == "succeeded" and f.h.http.requestCount == 1)
	f.finish()
end)

suite.finish()
