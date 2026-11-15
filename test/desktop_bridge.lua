package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function info(token, instance)
	return { product = "project-uai-desktop", protocol = 1, port = 28791, token = token or ("a"):rep(64), instance = instance or "desktop-one" }
end
local function setup(value)
	local h = envMock.new()
	local state = { discovery = value, probes = 0, delay = 0, auth = {} }
	h.http.desktop = function(req)
		state.probes = state.probes + 1
		check("discovery uses bounded native POST", req.method == "POST" and req.headers["X-UAI-Discovery"] == "1" and req.body == "{}")
		return { StatusCode = state.discovery and 200 or 404, Body = json.encode(state.discovery or {}), delay = state.delay }
	end
	h.http.handler = function(req)
		if req.url:find("/api/agent/", 1, true) then
			state.auth[#state.auth + 1] = { url = req.url, token = req.headers.Authorization }
			if req.body then
				local input = json.decode(req.body)
				if input and input.state then state.snapshot = input.state end
			end
			return { StatusCode = 200, Body = req.url:find("inbox", 1, true) and '{"commands":[]}' or '{}' }
		end
		return { StatusCode = 404, Body = '{}' }
	end
	local app = assert(h.boot()); require("password_fixture")(h, app)
	h.settle(1)
	return h, app, state
end

local function pinInference(label)
	local owner
	return function(spec)
		local authorization = spec.headers and spec.headers.Authorization
		if spec.method == "POST" then
			local input = json.decode(spec.body)
			assert(type(input) == "table" and type(input.id) == "string" and input.id ~= "", label .. ": submission needs an exact request ID")
			owner = owner or { id = input.id, url = spec.url, authorization = authorization }
			assert(owner.url == "http://127.0.0.1:28791/api/inference" and owner.authorization == "Bearer " .. ("a"):rep(64), label .. ": submission must use the verified desktop")
			assert(input.id == owner.id and spec.url == owner.url and authorization == owner.authorization, label .. ": submission changed request ownership")
			return owner.id
		end
		assert(owner and (spec.method == "GET" or spec.method == "DELETE"), label .. ": receipt needs an accepted request")
		assert(spec.url == owner.url .. "/" .. owner.id and authorization == owner.authorization, label .. ": receipt or cancellation changed request ID, endpoint or token")
		return owner.id
	end
end

for _, profile in ipairs({
	{ name = "touch with synthetic mouse", touch = true, mouse = true, keyboard = false, platform = "Windows", handheld = true },
	{ name = "Android with attached keyboard", touch = true, mouse = true, keyboard = true, platform = "Android", handheld = true },
	{ name = "touchscreen desktop", touch = true, mouse = true, keyboard = true, platform = "Windows", handheld = false },
	{ name = "pointer desktop", touch = false, mouse = true, keyboard = true, platform = "Windows", handheld = false },
}) do
	local h, probes = envMock.new(), 0
	local input = h.services.UserInputService
	input.TouchEnabled, input.MouseEnabled, input.KeyboardEnabled = profile.touch, profile.mouse, profile.keyboard
	input.GetPlatform = function() return { Name = profile.platform } end
	h.http.desktop = function()
		probes = probes + 1
		return { StatusCode = 200, Body = json.encode(info()) }
	end
	h.http.handler = function(req)
		return { StatusCode = 200, Body = req.url:find("inbox", 1, true) and '{"commands":[]}' or '{}' }
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(6)
	check(profile.name .. " uses runtime device identity", app.env.require("runtime/device").isHandheld() == profile.handheld)
	check(profile.name .. " applies correct desktop discovery policy", profile.handheld and probes == 0 and not app.bridge.running
		or not profile.handheld and probes > 0 and app.bridge.running)
	app.destroy(); h.settle(1)
	check(profile.name .. " discovery cleanup is clean", #h.errors() == 0)
end

do
	local h, app, state = setup(info())
	check("desktop is discovered at boot", app.bridge.running and app.bridge.status().source == "desktop")
	check("connection configuration contains no manual fields", app.config.get("bridge.enabled") == nil and app.config.get("bridge.port") == nil and app.config.get("bridge.token") == nil)
	check("bridge uses discovered token and dedicated port", #state.auth > 0 and state.auth[1].token == "Bearer " .. ("a"):rep(64) and state.auth[1].url:find(":28791/", 1, true))
	app.env.require("agent/usage").record({ prompt_tokens = 20, completion_tokens = 5 }, "unpriced-fixture", nil, { baseUrl = "https://unpriced.fixture/v1" })
	h.settle(2)
	check("browser snapshot preserves unknown cost separately from zero", state.snapshot and state.snapshot.usage.unpriced == 1 and state.snapshot.usage.cost == 0)
	app.config.saveNow()
	check("ephemeral credentials are absent from saved config", not json.encode(app.config.data):find(("a"):rep(64), 1, true))
	state.discovery = info(("b"):rep(64), "desktop-two")
	h.settle(6)
	check("restart refreshes credentials automatically", app.env.require("net/bridge_connection").get().token == ("b"):rep(64))
	check("restarted commands use new credentials", state.auth[#state.auth].token == "Bearer " .. ("b"):rep(64))
	app.config.set("bridge.autoDiscover", false)
	h.settle(1)
	local probes = state.probes
	h.settle(8)
	check("opt-out stops discovery and disconnects", state.probes == probes and not app.bridge.running)
	app.config.set("bridge.autoDiscover", true)
	h.settle(1)
	check("opt-in reconnects without script reload", app.bridge.running)
	app.bridge.stop()
	probes = state.probes
	h.settle(6)
	check("explicit stop suspends discovery", state.probes == probes and not app.bridge.running)
	app.bridge.sync(); h.settle(1)
	check("explicit reconnect resumes discovery", app.bridge.running)
	app.destroy(); probes = state.probes; h.settle(8)
	check("unload ends discovery", state.probes == probes)
	local legacy = assert(json.decode(h.files["UAI/config.json"]))
	legacy.bridge.enabled, legacy.bridge.port, legacy.bridge.token = true, 8792, "retired-manual-token"
	legacy.bridge.autoDiscover = true
	h.files["UAI/config.json"] = json.encode(legacy)
	local restored = assert(h.boot()); require("password_fixture")(h, restored); h.settle(1)
	check("legacy manual values are stripped during a cold load", restored.config.get("bridge.enabled") == nil
		and restored.config.get("bridge.port") == nil and restored.config.get("bridge.token") == nil)
	check("legacy manual enable cannot suppress desktop discovery", restored.bridge.running and restored.bridge.status().source == "desktop"
		and restored.env.require("net/bridge_connection").get().token == ("b"):rep(64))
	restored.app.show("cowork"); h.settle(0.3)
	check("Cowork exposes automatic discovery and connection actions", h.byName("AutoDiscoverDesktop")
		and h.byName("Reconnect") and h.byName("DisconnectCowork"))
	check("Cowork has no manual setup or credential controls", not h.byName("BridgePort") and not h.byName("BridgeToken")
		and not h.byName("DownloadBridge") and not h.byName("CopyBridgeStart") and not h.byName("CopyBridgeUrl"))
	h.click(assert(h.byName("DisconnectCowork"))); probes = state.probes; h.settle(5)
	check("native Disconnect suspends discovery without changing opt-in", not restored.bridge.running and state.probes == probes
		and restored.config.get("bridge.autoDiscover") == true)
	h.click(assert(h.byName("Reconnect"))); h.settle(1)
	check("native Reconnect obtains desktop credentials again", restored.bridge.running and state.probes > probes)
	restored.destroy(); h.settle(1)
	check("automatic-only native controls release cleanly", #h.errors() == 0)
end

do
	local h, app, state = setup(nil)
	check("app may be started after script", not app.bridge.running)
	for _, bad in ipairs({ { product = "other", protocol = 1, port = 28791, token = ("a"):rep(64), instance = "x" },
		{ product = "project-uai-desktop", protocol = 2, port = 28791, token = ("a"):rep(64), instance = "x" },
		{ product = "project-uai-desktop", protocol = 1, port = 8790, token = ("a"):rep(64), instance = "x" },
		{ product = "project-uai-desktop", protocol = 1, port = 28791, token = "bad", instance = "x" } }) do
		state.discovery = bad; h.settle(5)
		check("invalid discovery response cannot attach", not app.bridge.running)
	end
	state.discovery = info(); h.settle(5)
	check("late desktop start connects", app.bridge.running)
	check("manual token configuration is retired", app.config.set("bridge.token", "manual-token") == nil)
	check("manual port configuration is retired", app.config.set("bridge.port", 8792) == nil)
	check("manual enabled configuration is retired", app.config.set("bridge.enabled", true) == nil)
	h.settle(1)
	local probes = state.probes; h.settle(5)
	check("retired manual configuration cannot interrupt discovery", app.bridge.status().source == "desktop" and state.probes > probes)
	check("only discovered credentials reach the dedicated endpoint", state.auth[#state.auth].url:find(":28791/", 1, true)
		and state.auth[#state.auth].token == "Bearer " .. ("a"):rep(64))
	app.destroy()
end

do
	local h, app, state = setup(nil)
	state.discovery, state.delay = info(), 1
	app.config.set("bridge.autoDiscover", true)
	h.settle(0.3)
	app.config.set("bridge.autoDiscover", false)
	h.settle(2)
	check("late discovery after opt-out cannot attach", not app.bridge.running)
	app.config.set("bridge.autoDiscover", true); h.settle(0.3)
	app.destroy(); h.settle(3)
	check("late discovery after unload cannot attach", not app.bridge.running)
end

do
	local h, app = setup(info())
	local result, calls = nil, 0
	h.sandbox.task.spawn(function()
		result = app.env.require("net/relay").request({ url = "https://provider.invalid/v1", body = "{}", sessionId = "test" }, {}, function(spec)
			check("relay uses effective desktop credentials", spec.url:find(":28791/", 1, true) and spec.headers.Authorization == "Bearer " .. ("a"):rep(64))
			if spec.url:find("/api/hello", 1, true) then return { ok = true, body = '{"protocol":2,"instance":"desktop-one"}' } end
			if spec.method == "POST" then
				local body = json.decode(spec.body); calls = calls + 1
				return { ok = true, body = json.encode({ id = body.id, state = "running" }) }
			end
			return { ok = true, body = json.encode({ id = spec.url:match("/api/inference/(.+)$"), state = "completed", status = 200, body = "answer" }) }
		end)
	end)
	h.settle(3)
	check("web inference works without saved manual enable/token", result and result.body == "answer" and calls == 1)
	app.destroy()
end

for _, failure in ipairs({ "refused", "timeout", "malformed" }) do
	local h, app, state = setup(info())
	local result, problem, submissions, deletes, ready = nil, nil, 0, 0, false
	local pinned = pinInference(failure)
	local connection, transport = app.env.require("net/bridge_connection"), app.env.require("net/transport")
	h.sandbox.task.spawn(function()
		result, problem = app.env.require("net/relay").request({ url = "https://provider.invalid/v1", body = "{}" }, {}, function(spec)
			if spec.url:find("/api/hello", 1, true) then return { ok = true, body = '{"protocol":2,"instance":"desktop-one"}' } end
			local id = pinned(spec)
			if spec.method == "DELETE" then deletes = deletes + 1; return { ok = true, body = "{}" } end
			if spec.method == "POST" then submissions = submissions + 1 end
			return { ok = true, body = json.encode({ id = id, state = ready and "completed" or "running", status = 200, body = ready and "kept answer" or nil }) }
		end)
	end)
	h.settle(0.2)
	check(failure .. " fixture owns one accepted inference", submissions == 1)
	state.discovery = failure == "malformed" and { product = "other", protocol = 1 } or failure == "timeout" and info() or nil
	state.delay = failure == "timeout" and 3 or 0
	h.settle(9)
	check(failure .. " discovery pauses new bridge admission", not connection.enabled() and transport.endpoint() == nil)
	check(failure .. " discovery retains only the accepted endpoint", connection.get(true).token == ("a"):rep(64)
		and transport.endpoint("cowork").instance == "desktop-one")
	check(failure .. " discovery cannot pretend the user pressed Stop", result == nil and problem == nil and deletes == 0 and submissions == 1)
	ready = true; h.settle(2)
	check(failure .. " discovery preserves the original answer without replay", result and result.body == "kept answer" and problem == nil and submissions == 1 and deletes == 0)
	state.discovery, state.delay = info(), 0; h.settle(7)
	check(failure .. " discovery recovers new admission automatically", connection.enabled() and app.bridge.online and transport.endpoint().target == "cowork")
	app.destroy(); h.settle(1)
	check(failure .. " discovery cleanup releases callbacks", #h.errors() == 0)
end

for _, profile in ipairs({
	{ name = "keyboard loss", mouse = true, keyboard = false },
	{ name = "pointer loss", mouse = false, keyboard = true },
}) do
	local h, app = setup(info())
	local input = h.services.UserInputService
	input.TouchEnabled = true
	local result, problem, submissions, deletes, ready = nil, nil, 0, 0, false
	local pinned = pinInference(profile.name)
	local connection, transport = app.env.require("net/bridge_connection"), app.env.require("net/transport")
	h.sandbox.task.spawn(function()
		result, problem = app.env.require("net/relay").request({ url = "https://provider.invalid/v1", body = "{}" }, {}, function(spec)
			if spec.url:find("/api/hello", 1, true) then return { ok = true, body = '{"protocol":2,"instance":"desktop-one"}' } end
			local id = pinned(spec)
			if spec.method == "DELETE" then deletes = deletes + 1; return { ok = true, body = "{}" } end
			if spec.method == "POST" then submissions = submissions + 1 end
			return { ok = true, body = json.encode({ id = id, state = ready and "completed" or "running", status = 200, body = ready and "pinned answer" or nil }) }
		end)
	end)
	h.settle(0.2)
	check(profile.name .. " fixture owns one accepted desktop inference", submissions == 1 and connection.enabled())
	input.MouseEnabled, input.KeyboardEnabled = profile.mouse, profile.keyboard
	h.settle(5)
	check(profile.name .. " gates new handheld discovery and admission", app.env.require("runtime/device").isHandheld()
		and not connection.enabled() and transport.endpoint() == nil)
	check(profile.name .. " preserves accepted desktop identity", connection.get(true).token == ("a"):rep(64)
		and transport.endpoint("cowork").instance == "desktop-one")
	check(profile.name .. " cannot cancel the accepted job", result == nil and problem == nil and submissions == 1 and deletes == 0)
	ready = true; h.settle(2)
	check(profile.name .. " returns the original answer without replay", result and result.body == "pinned answer" and problem == nil and submissions == 1 and deletes == 0)
	app.destroy(); h.settle(1)
	check(profile.name .. " cleanup is clean", #h.errors() == 0)
end

for _, change in ipairs({ "token", "instance", "opt-out", "stop" }) do
	local h, app, state = setup(info())
	local result, problem, submissions, deletes = nil, nil, 0, 0
	local pinned = pinInference(change)
	h.sandbox.task.spawn(function()
		result, problem = app.env.require("net/relay").request({ url = "https://provider.invalid/v1", body = "{}" }, {}, function(spec)
			if spec.url:find("/api/hello", 1, true) then return { ok = true, body = '{"protocol":2,"instance":"desktop-one"}' } end
			local id = pinned(spec)
			if spec.method == "DELETE" then deletes = deletes + 1; return { ok = true, body = "{}" } end
			if spec.method == "POST" then submissions = submissions + 1 end
			return { ok = true, body = json.encode({ id = id, state = "running" }) }
		end)
	end)
	h.settle(0.2); state.discovery = nil; h.settle(5)
	check(change .. " fixture remains accepted through failed discovery", submissions == 1 and deletes == 0 and problem == nil)
	if change == "token" then state.discovery = info(("b"):rep(64))
	elseif change == "instance" then state.discovery = info(nil, "desktop-two")
	elseif change == "opt-out" then app.config.set("bridge.autoDiscover", false)
	else app.bridge.stop() end
	h.settle(7)
	check(change .. " still invalidates accepted ownership exactly once", result == nil and problem == "aborted" and submissions == 1 and deletes == 1)
	app.destroy(); h.settle(1)
	check(change .. " cancellation cleanup is clean", #h.errors() == 0)
end
print(string.format("%d desktop bridge checks passed", passed))
