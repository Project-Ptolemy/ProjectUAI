-- Focused native MCP ownership, dispatch, permissions and cancellation checks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local desktop = require("automatic_bridge_fixture")
local suite = F.suite("MCP bridge")
local check, case = suite.check, suite.case
local function setup()
	local f = F.new(); f.tools({})
	f.sessions = f.env.require("agent/session")
	f.active = assert(f.sessions.newThread({ title = "My chat" }))
	f.mcp = f.env.require("net/mcp")
	function f.call(id, tool, arguments, owner)
		return f.mcp.run({ type = "mcp:call", mcpSessionId = owner or "harness-one", callId = id,
			name = tool, arguments = arguments, clientName = "Fixture harness" })
	end
	return f
end

case("external tools keep native dispatch and a separate ephemeral conversation", function()
	local f = setup(); local calls, owner = 0
	f.registry.register({ name = "fixture_echo", risk = "read",
		parameters = { type = "object", properties = { text = { type = "string" } }, required = { "text" } },
		run = function(args, ctx) calls = calls + 1; owner = ctx.session; return { text = args.text, data = { seen = true } } end })
	local result = f.run(function() return f.call("call-one", "fixture_echo", { text = "Hello" }) end)
	check("ordinary tool result and structured data reach the harness", result.ok and result.text:find("Hello", 1, true) and result.data.seen)
	check("harness cannot change the active conversation", f.sessions.current() == f.active and owner ~= f.active)
	check("MCP conversation is ephemeral and visible for inspection", owner.ephemeral and f.sessions.get(owner.id) == owner and not owner.busy)
	local again = f.run(function() return f.call("call-one", "fixture_echo", { text = "Hello" }) end)
	check("duplicate delivery does not repeat tool effects", calls == 1 and again == result)
	local ok = pcall(function() f.call("call-one", "fixture_echo", { text = "Changed" }) end)
	check("call identity cannot be reused for different arguments", not ok and calls == 1)
	local bad = f.run(function() return f.call("bad-schema", "fixture_echo", {}) end)
	check("schema validation remains authoritative", not bad.ok and bad.error == "invalid arguments" and calls == 1)
	f.mcp.clear(); check("closing MCP preserves the original chat", f.sessions.current() == f.active and f.sessions.get(owner.id) == nil)
	f.healthy(); f.close()
end)

case("cancelling one concurrent call leaves other harness work alive", function()
	local f = setup(); local results, effects, resumed = {}, {}, {}
	f.registry.register({ name = "fixture_wait", risk = "read", timeout = 30,
		parameters = { type = "object", properties = { label = { type = "string" } } },
		run = function(args, ctx)
			f.h.sched.wait(2); resumed[args.label] = true
			if not ctx.aborted() then effects[args.label] = true end
			return args.label
		end })
	for _, id in ipairs({ "one", "two" }) do
		f.h.sched.spawn(function() results[id] = f.call(id, "fixture_wait", { label = id }) end)
	end
	f.h.sched.advance(0.1)
	f.mcp.run({ type = "mcp:cancel", mcpSessionId = "harness-one", callId = "one" })
	f.h.sched.advance(0.2)
	check("cancel settles only its own waiter", results.one and results.one.error == "aborted" and results.two == nil)
	f.h.sched.advance(2)
	check("other call succeeds without reviving cancelled effects", results.two.ok and effects.two and not effects.one and resumed.one)
	check("cancel never stops active chat", not f.active.abortFlag)
	f.mcp.clear(); f.healthy(); f.close()
end)

case("permissions and group revocation apply to external harnesses", function()
	local f = setup(); local effects, result = 0
	local permissions = f.env.require("agent/permissions")
	permissions.setMode("ask")
	f.registry.register({ name = "fixture_write", group = "mcpfixture", risk = "write", run = function() effects = effects + 1; return "Written" end })
	f.h.sched.spawn(function() result = f.call("write-one", "fixture_write", {}) end)
	f.h.sched.advance(0.1)
	local _, pending = next(permissions.pending)
	check("MCP prompts name their isolated conversation", pending and pending.session ~= f.active and effects == 0 and result == nil)
	pending.resolve(true, false); f.h.sched.advance(0.2)
	check("explicit approval releases the normal dispatcher", result.ok and effects == 1)
	permissions.setMode("readonly")
	local denied = f.run(function() return f.call("write-two", "fixture_write", {}) end)
	check("read-only denies writes", not denied.ok and effects == 1)
	permissions.setRule("fixture_write", "allow")
	f.registry.setGroupEnabled("mcpfixture", false)
	local disabled = f.run(function() return f.call("write-three", "fixture_write", {}) end)
	check("group disable wins over an allow rule", not disabled.ok and effects == 1)
	f.mcp.clear(); f.healthy(); f.close()
end)

case("close and pre-dispatch cancellation cannot revive queued calls", function()
	local f = setup(); local effects, result = 0
	f.registry.register({ name = "fixture_effect", risk = "write", run = function() effects = effects + 1; return "Written" end })
	f.mcp.run({ type = "mcp:cancel", mcpSessionId = "harness-one", callId = "early" })
	local cancelled = f.run(function() return f.call("early", "fixture_effect", {}) end)
	check("cancel before session creation prevents effects", not cancelled.ok and effects == 0 and #f.sessions.list() == 1)
	f.mcp.close("closed-harness")
	local ok = pcall(function() f.call("late", "fixture_effect", {}, "closed-harness") end)
	check("closed session cannot be recreated by a late call", not ok and effects == 0)
	f.env.require("agent/permissions").setMode("ask")
	f.h.sched.spawn(function() result = f.call("waiting", "fixture_effect", {}) end)
	f.h.sched.advance(0.1); f.mcp.clear(); f.h.sched.advance(0.2)
	check("bridge shutdown settles pending approvals", result and not result.ok and effects == 0 and next(f.env.require("agent/permissions").pending) == nil)
	check("shutdown removes all external conversations", #f.sessions.list() == 1)
	f.healthy(); f.close()
end)

case("connection-scoped work survives successive requests until Stop or close", function()
	local f = setup(); local context
	f.registry.register({ name = "fixture_context", risk = "read", run = function(_, ctx) context = context or ctx; return "Ready" end })
	f.run(function() return f.call("first", "fixture_context", {}) end)
	f.run(function() return f.call("next", "fixture_context", {}) end)
	check("another request does not invalidate owned background work", context and not context.aborted())
	context.session.busy = true; context.session.abort(); context.session.busy = false
	f.run(function() return f.call("after-stop", "fixture_context", {}) end)
	check("new request never revives pre-Stop work", context.aborted())
	f.mcp.clear(); f.healthy(); f.close()
end)

case("receipt eviction retains identities and cannot repeat old effects", function()
	local f = setup(); local calls = 0
	f.registry.register({ name = "fixture_large", risk = "read", run = function() calls = calls + 1; return "Ready" end })
	local arguments = { input = string.rep("x", 200000) }
	for i = 1, 12 do f.run(function() return f.call("large-" .. i, "fixture_large", arguments) end) end
	local ok, why = pcall(function() return f.call("large-1", "fixture_large", arguments) end)
	check("byte budget evicts before the count limit", not ok and tostring(why):find("receipt expired", 1, true))
	check("expired identity cannot become another execution", calls == 12)
	f.mcp.clear(); f.healthy(); f.close()
end)

case("harness calls cannot overlap a user preparing an attachment", function()
	local f = setup(); local owner, calls = nil, 0
	f.registry.register({ name = "fixture_owner", risk = "read", run = function(_, ctx) owner = ctx.session; calls = calls + 1; return "Ready" end })
	f.run(function() return f.call("first", "fixture_owner", {}) end)
	owner.preparing = {}
	local ok = pcall(function() f.call("during-preparation", "fixture_owner", {}) end)
	check("attachment preparation keeps exclusive conversation admission", not ok and calls == 1)
	owner.preparing = nil; f.mcp.clear(); f.healthy(); f.close()
end)

case("desktop worker replacement refreshes state and closes old MCP work", function()
	local envMock, json = require("env"), require("json")
	local h = envMock.new()
	local instance, snapshots, latest = "worker-one", 0, nil
	h.http.handler = function(req)
		if req.url:find("/api/hello", 1, true) then
			return { StatusCode = 200, Body = json.encode({ protocol = 2, instance = instance, capabilities = {} }) }
		elseif req.url:find("/api/agent/inbox", 1, true) then
			return { StatusCode = 200, Body = '{"commands":[]}', delay = 0.1 }
		elseif req.url:find("/api/agent/events", 1, true) then
			local value = json.decode(req.body)
			if value.snapshot then snapshots = snapshots + 1 end
			if value.state then latest = value.state end
		end
		return { StatusCode = 204, Body = "" }
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.2)
	local discovery = desktop.connect(h, app, { instance = "worker-one" })
	h.settle(1.5)
	local sessions = app.env.require("agent/session")
	local active, owner = sessions.current()
	app.env.require("agent/registry").register({ name = "fixture_mcp", risk = "read", run = function(_, ctx) owner = ctx.session; return "Ready" end })
	h.sandbox.task.spawn(function()
		app.env.require("net/mcp").run({ type = "mcp:call", mcpSessionId = "previous-worker", callId = "first", name = "fixture_mcp" })
	end)
	h.settle(0.3)
	check("worker fixture started isolated MCP session", owner and sessions.get(owner.id) == owner)
	local before = snapshots
	instance = "worker-two"; h.settle(5)
	check("same-token worker replacement closes external ownership", sessions.get(owner.id) == nil)
	check("fresh worker receives snapshot and full capabilities", snapshots > before and latest and latest.mcp.schema == 1)
	check("replacement preserves active conversation and in-memory desktop credentials", sessions.current() == active
		and app.env.require("net/bridge_connection").get().token == discovery.token and app.config.get("bridge.token") == nil)
	app.destroy(); h.settle(0.2); check("worker replacement releases callbacks cleanly", #h.errors() == 0)
end)

suite.finish()
