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
print(string.format("%d desktop bridge checks passed", passed))
