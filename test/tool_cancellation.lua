-- Cancellation settles waiting callers without closing native continuations.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Tool cancellation")
local check, case = suite.check, suite.case

case("Stop releases a tool batch and prevents queued tools from starting", function()
	local f = F.new(); f.tools({})
	f.env.require("runtime/config").set("agent.toolConcurrency", 1)
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	local resumed, effects, queued, events, results = false, 0, 0, 0, nil
	session.events:connect(function(event) if event.kind == "tool:progress" then events = events + 1 end end)
	assert(f.registry.register({ name = "fixture_wait", risk = "write", timeout = 60, run = function(_, ctx)
		f.h.sched.wait(5); resumed = true
		ctx.progress("late progress")
		if not ctx.aborted() then effects = effects + 1 end
		return "late result"
	end }))
	assert(f.registry.register({ name = "fixture_queued", risk = "write", run = function() queued = queued + 1 end }))
	f.h.sched.spawn(function()
		results = f.registry.runAll({ { id = "one", name = "fixture_wait" }, { id = "two", name = "fixture_queued" } }, session.toolContext())
	end)
	f.h.sched.advance(0.1); session.abort(); f.h.sched.advance(0.1)
	check("Stop settles the batch before its native call returns", results and #results == 2 and not resumed)
	check("cancellation is reported without a timeout or claimed rollback", results[1].error == "aborted"
		and results[1].text:find("may still be running", 1, true) and not results[1].ok)
	check("queued calls never execute", queued == 0 and results[2].error == "aborted")
	-- Simulate another turn clearing the user's Stop flag while the native waiter lives.
	session.abortFlag, session.toolEpoch = false, {}
	f.h.sched.advance(5)
	check("native continuation resumes safely with no new effects or events", resumed and effects == 0 and events == 0)
	check("late completion cannot replace the returned cancellation", results[1].error == "aborted")
	f.healthy(); f.close()
end)

case("revoked tools stay cancelled after permission is restored", function()
	local f = F.new(); f.tools({})
	local permissions = f.env.require("agent/permissions")
	local effects, resumed, result = 0, false, nil
	assert(f.registry.register({ name = "fixture_wait", risk = "write", timeout = 60, run = function(_, ctx)
		f.h.sched.wait(5); resumed = true
		if not ctx.aborted() then effects = effects + 1 end
		return "late result"
	end }))
	f.h.sched.spawn(function() result = f.registry.dispatch({ name = "fixture_wait" }, {}) end)
	f.h.sched.advance(0.1); permissions.setRule("fixture_wait", "deny"); f.h.sched.advance(0.1)
	check("revocation releases the waiter promptly", result and result.error == "aborted" and not resumed)
	permissions.setRule("fixture_wait", "allow"); f.h.sched.advance(5)
	check("restoring permission cannot revive the old invocation", resumed and effects == 0)
	f.healthy(); f.close()
end)

case("invalid dynamic timeouts fall back to a finite deadline", function()
	for _, invalid in ipairs({ 0 / 0, math.huge, -1, 0, "invalid" }) do
		local f = F.new(); f.tools({})
		f.env.require("runtime/config").set("agent.toolTimeout", 0.1)
		local result, resumed
		assert(f.registry.register({ name = "fixture_wait", risk = "read", timeout = function() return invalid end,
			run = function() f.h.sched.wait(1); resumed = true; return "late" end }))
		f.h.sched.spawn(function() result = f.registry.dispatch({ name = "fixture_wait" }, {}) end)
		f.h.sched.advance(0.2)
		check("invalid deadline expires at the configured fallback", result and result.error == "timeout" and not resumed
			and result.text:find("0.1s", 1, true))
		f.h.sched.advance(1)
		check("timed-out native continuation remains resumable", resumed and result.error == "timeout")
		f.healthy(); f.close()
	end
end)

case("completed and throwing handlers keep their ordinary results", function()
	local f = F.new(); f.tools({})
	assert(f.registry.register({ name = "fixture_done", risk = "read", run = function() return "Complete" end }))
	assert(f.registry.register({ name = "fixture_error", risk = "read", run = function() error("fixture failure") end }))
	local done, failed = f.dispatch("fixture_done"), f.dispatch("fixture_error")
	check("immediate success is preserved", done.ok and done.text == "Complete")
	check("handler errors remain errors", not failed.ok and failed.error == "error" and failed.text:find("fixture failure", 1, true))
	f.healthy(); f.close()
end)

suite.finish()
