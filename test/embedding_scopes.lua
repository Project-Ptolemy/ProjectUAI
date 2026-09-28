-- SDK resource ownership, host extension validation and tool revocation.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local luau = require("luau")
local passed, failed = 0, 0
local function check(label, value) assert(value, label); passed = passed + 1 end
local function scenario(name, fn)
	local ok, err = pcall(fn)
	if ok then print("  ok   " .. name)
	else failed = failed + 1; print("  FAIL " .. name .. ": " .. tostring(err)) end
end

local function fixture()
	local h = envMock.new()
	local env = { services = h.services, hs = h.services.HttpService, plr = h.localPlayer,
		info = { folder = "UAI", version = "test" }, context = {} }
	local loaded = {}
	function env.require(id)
		if loaded[id] then return loaded[id] end
		local file = assert(io.open("src/" .. id .. ".lua", "rb"))
		local source = file:read("*a"); file:close()
		local fn = assert(luau.load(source, id)); setfenv(fn, h.sandbox)
		loaded[id] = fn()(env)
		return loaded[id]
	end
	local registry = env.require("agent/registry")
	registry.loaded = true
	local handle = { alive = true, env = env, tools = registry }
	local scopes = env.require("embedding/scope")
	local ctx = { session = {}, aborted = function() return false end }
	env.require("runtime/config").set("permissions.mode", "full")
	local function dispatch(name, args, context)
		local result
		h.sched.spawn(function()
			result = registry.dispatch({ id = "host-call", name = name, arguments = h.json.encode(args or {}) }, context or ctx)
		end)
		return function() return result end
	end
	return h, env, handle, scopes, dispatch, ctx
end

local function tool(name, run)
	return { name = name or "host_test", group = "host", risk = "read", description = "Inspect a host fixture.",
		parameters = { type = "object", properties = { count = { type = "integer", minimum = 1 } }, required = {} },
		run = run or function() return "ready" end }
end

scenario("scope IDs, early release and reverse cleanup have explicit lifetimes", function()
	local _, env, handle, scopes = fixture()
	local dispose = env.require("runtime/dispose")
	local before = dispose.count()
	local scope = assert(scopes.create(handle, "host-panel"))
	check("scope identity and one disposer are published", scope.alive and scope.id == "host-panel" and dispose.count() == before + 1)
	local duplicate, why = scopes.create(handle, "host-panel")
	check("duplicate scope IDs are refused with a reason", not duplicate and type(why) == "string" and scope.alive)
	check("invalid IDs are refused", scopes.create(handle, " ") == nil and scopes.create(handle, 4) == nil)
	local order = {}
	local release = assert(scope.give(function() order[#order + 1] = "early" end))
	check("early cleanup executes once", release() and not release() and #order == 1)
	scope.give(function() order[#order + 1] = "first" end)
	scope.give(function() order[#order + 1] = "second"; error("cleanup fixture") end)
	check("destroy isolates cleanup errors and counts remaining entries", scope.destroy() == 2 and table.concat(order, ",") == "early,second,first")
	check("destroy removes the runtime disposer", dispose.count() == before and #dispose.entries == before)
	check("destroy is idempotent", scope.destroy() == 0 and not scope.alive)
	local late = 0
	local rejected, reason = scope.give(function() late = late + 1 end)
	check("late resources are cleaned immediately", rejected == nil and type(reason) == "string" and late == 1)
	local replacement = assert(scopes.create(handle, "host-panel"))
	check("destroyed IDs can be reused", replacement ~= scope and replacement.alive)
	handle.alive = false
	dispose.drain()
	check("client cleanup destroys scopes and rejects new ones", not replacement.alive and scopes.create(handle, "late") == nil)
end)

scenario("signals and hooks release callbacks and contain host errors", function()
	local h, env, handle, scopes = fixture()
	local scope = assert(scopes.create(handle, "observers"))
	local signal = env.require("runtime/signal").new("host")
	local hooks = env.require("agent/hooks")
	local total = 0
	scope.connect(signal, function(value) total = total + value end)
	scope.connect(signal, function() error("observer fixture") end)
	signal:fire(2)
	check("subscriber errors do not escape", total == 2 and signal:count() == 2)
	local native = require("instance").newSignal("host-native")
	local nativeOff = assert(scope.connect(native, function(value) total = total + value end))
	native:Fire(3)
	check("native signal connections are supported", total == 5)
	check("native disconnection is idempotent", nativeOff() and not nativeOff())
	native:Fire(9)
	local off = assert(scope.hook("preTool", function() total = total + 1; return false end))
	local entry = hooks.handlers.preTool[1]
	check("scope hooks retain veto behavior", hooks.run("preTool", {}) == false and total == 6)
	check("hook release physically removes the callback", off() and entry.fn == nil and #hooks.handlers.preTool == 0)
	check("invalid signal/hook inputs return errors", scope.connect({}, function() end) == nil and scope.hook("missing", function() end) == nil
		and scope.hook("preTool", 1) == nil and scope.hook("preTool", function() end, { order = "first" }) == nil)
	scope.destroy()
	signal:fire(10)
	check("destroy removes subscriptions without a later callback", signal:count() == 0 and #signal.handlers == 0 and total == 6)
	check("scope operations after destroy are refused", scope.connect(signal, function() end) == nil and scope.hook("preTool", function() end) == nil)
end)

scenario("hook mutations during dispatch preserve membership and registration order", function()
	local _, env = fixture()
	local hooks, order = env.require("agent/hooks"), {}
	local first, second
	first = hooks.register("onEvent", function()
		order[#order + 1] = "first"
		first(); second()
		hooks.register("onEvent", function() order[#order + 1] = "new" end, { order = -1 })
	end)
	second = hooks.register("onEvent", function() order[#order + 1] = "removed" end)
	hooks.register("onEvent", function() order[#order + 1] = "last" end)
	hooks.run("onEvent", {})
	check("removed hooks skip and newly registered hooks wait", table.concat(order, ",") == "first,last" and hooks.count("onEvent") == 2)
	hooks.run("onEvent", {})
	check("next run uses the new ordered membership", table.concat(order, ",") == "first,last,new,last" and #hooks.handlers.onEvent == 2)
end)

scenario("scoped tools copy definitions and reject malformed extension data", function()
	local h, env, handle, scopes, dispatch = fixture()
	local scope = assert(scopes.create(handle, "tools"))
	local definition = tool()
	definition.needs = {}
	local ok, release = scope.registerTool(definition)
	check("valid host tools are registered", ok and type(release) == "function")
	local stored = handle.tools.get("host_test")
	definition.name, definition.description, definition.risk = "changed", "changed", "danger"
	definition.parameters.properties.count.minimum = 99
	definition.needs[1] = "missing"
	definition.run = function() error("changed") end
	check("the stored definition is detached", stored ~= definition and stored.description ~= "changed" and stored.risk == "read"
		and stored.parameters.properties.count.minimum == 1 and #stored.needs == 0)
	local result = dispatch("host_test", { count = 2 })
	h.sched.advance(0.2)
	check("caller mutation cannot alter dispatched behavior", result().ok and result().text == "ready")
	local duplicate, why = scope.registerTool(tool())
	check("duplicate registration is refused without replacing", not duplicate and type(why) == "string" and handle.tools.get("host_test") == stored)
	local malformed = {
		{ "name", 1 }, { "name", "has spaces" }, { "group", {} }, { "risk", "safe" }, { "description", false },
		{ "run", true }, { "prepare", "run" }, { "timeout", -1 }, { "needs", { "ok", false } }, { "parameters", true },
		{ "parameters", { type = "object", required = "count" } },
		{ "parameters", { type = "object", properties = { count = { type = "number", minimum = "one" } } } },
	}
	for _, item in ipairs(malformed) do
		local bad = tool("bad_tool"); bad[item[1]] = item[2]
		local accepted, reason = scope.registerTool(bad)
		check("malformed " .. item[1] .. " returns a reason", not accepted and type(reason) == "string" and not handle.tools.get("bad_tool"))
	end
	local cyclic = tool("cycle"); cyclic.parameters.loop = cyclic.parameters
	check("cyclic schemas are rejected", scope.registerTool(cyclic) == false)
	check("tool release removes schema and registry ordering", release() and not release() and handle.tools.get("host_test") == nil and #handle.tools.list() == 0)
	check("invalid plain registry names are also refused", not handle.tools.register({ name = {}, run = function() end }))
	scope.destroy()
	check("closed scope cannot register tools", scope.registerTool(tool()) == false)
	check("fixture scheduler is clean", #h.sched.errors == 0)
end)

scenario("scope cleanup cannot remove another owner's tool replacement", function()
	local _, _, handle, scopes = fixture()
	local first = assert(scopes.create(handle, "first"))
	assert(first.registerTool(tool()))
	local registered = handle.tools.get("host_test")
	check("unregister checks expected identity", not handle.tools.unregister("host_test", tool()) and handle.tools.get("host_test") == registered)
	assert(handle.tools.unregister("host_test", registered))
	local second = assert(scopes.create(handle, "second"))
	assert(second.registerTool(tool()))
	local replacement = handle.tools.get("host_test")
	first.destroy()
	check("old scope leaves replacement ownership intact", handle.tools.get("host_test") == replacement)
	second.destroy()
	check("replacement owner removes its own registration", handle.tools.get("host_test") == nil)
end)

scenario("unregistration settles approvals without executing stale tools", function()
	local h, env, handle, scopes, dispatch = fixture()
	env.require("runtime/config").set("permissions.mode", "ask")
	local scope = assert(scopes.create(handle, "approval"))
	local calls, prompt = 0, nil
	local definition = tool("host_write", function() calls = calls + 1; return "changed" end)
	definition.risk = "write"
	assert(scope.registerTool(definition))
	local result = dispatch("host_write", {}, { session = {}, aborted = function() return false end,
		emit = function(kind, payload) if kind == "permission:ask" then prompt = payload end end })
	h.sched.advance(0.05)
	local permissions = env.require("agent/permissions")
	check("write waits on a real pending approval", prompt and permissions.pendingCount() == 1 and result() == nil)
	scope.destroy()
	check("revocation immediately clears its pending approval", permissions.pendingCount() == 0)
	prompt.resolve(true, true)
	h.sched.advance(0.2)
	check("late approval cannot execute or persist an allow rule", result() and not result().ok and result().error == "tool unregistered"
		and calls == 0 and permissions.ruleFor("host_write") == nil)
	check("revocation has no scheduler errors", #h.sched.errors == 0)
end)

scenario("revocation reaches cooperative handlers and same-definition re-registration", function()
	local h, _, handle, _, dispatch = fixture()
	local aborted, writes = false, 0
	local definition = tool("host_wait", function(_, ctx)
		h.sched.wait(0.15)
		aborted = ctx.aborted()
		if aborted then return { ok = false, text = "host work stopped" } end
		writes = writes + 1
		return "changed"
	end)
	assert(handle.tools.register(definition))
	local result = dispatch("host_wait")
	h.sched.advance(0.05)
	assert(handle.tools.unregister("host_wait", definition))
	assert(handle.tools.register(definition))
	h.sched.advance(0.25)
	check("same-table replacement cannot revive the old handler", aborted and writes == 0 and result() and not result().ok)
	local nextResult = dispatch("host_wait")
	h.sched.advance(0.25)
	check("new dispatch can use the new registration", nextResult() and nextResult().ok and writes == 1)
end)

scenario("revocation during hooks and timeout resolution checks before invocation", function()
	local h, env, handle, _, dispatch = fixture()
	local calls = 0
	local hooked = tool("host_hooked", function() calls = calls + 1 end)
	assert(handle.tools.register(hooked))
	local off = env.require("agent/hooks").register("preTool", function(payload) handle.tools.unregister(payload.tool.name, payload.tool) end)
	local hookResult = dispatch("host_hooked")
	h.sched.advance(0.2)
	check("hook-time revocation prevents execution", hookResult() and not hookResult().ok and calls == 0)
	off()
	local timed = tool("host_timed", function() calls = calls + 1 end)
	timed.timeout = function() handle.tools.unregister("host_timed", timed); return 1 end
	assert(handle.tools.register(timed))
	local timeoutResult = dispatch("host_timed")
	h.sched.advance(0.2)
	check("timeout callbacks cannot run a revoked definition", timeoutResult() and not timeoutResult().ok and calls == 0)
	check("dispatch guards have no scheduler errors", #h.sched.errors == 0)
end)

print(string.format("Embedding scopes: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
