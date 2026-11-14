-- Test-only desktop discovery. Credentials never enter production configuration.
local json = require("json")
local M = { PORT = 28791 }
local function options(value)
	value = value or {}
	local token = value.token or ("a"):rep(64)
	assert(type(token) == "string" and #token == 64 and token:match("^[a-f0-9]+$"), "fixture desktop token must use 64 hexadecimal characters")
	return { token = token, instance = value.instance or "automatic-fixture", online = value.online ~= false,
		delay = value.delay or 0, probes = 0 }
end
function M.install(h, value)
	local state = options(value)
	h.http.desktop = function()
		state.probes = state.probes + 1
		return { StatusCode = state.online and 200 or 404, delay = state.delay,
			Body = json.encode(state.online and { product = "project-uai-desktop", protocol = 1,
				port = M.PORT, token = state.token, instance = state.instance } or {}) }
	end
	return state
end
function M.connect(h, app, value)
	local state = M.install(h, value)
	app.config.set("bridge.autoDiscover", true, { transient = true })
	app.bridge.sync()
	h.settle(0.5)
	return state
end
-- Protocol/UI tests may inject a connection without testing desktop discovery,
-- including a synthetic phone Cowork route. Production never offers this path.
function M.inject(env, value)
	local state = options(value)
	local config = env.require("runtime/config")
	local connection = env.require("net/bridge_connection")
	local pause, resume = connection.pause, connection.resume
	local alive, active = true, true
	config.set("bridge.autoDiscover", false, { transient = true })
	connection.get = function()
		if alive and active and state.online then return { enabled = true, source = "desktop", port = M.PORT,
			token = state.token, instance = state.instance } end
		return { enabled = false, source = "none", port = M.PORT, token = "" }
	end
	connection.searching, connection.startDiscovery = function() return false end, function() end
	connection.pause = function() active = false; pause() end
	connection.resume = function()
		if config.accessProblem() or not alive then return end
		active = true; resume(); connection.changed:fire()
	end
	env.require("runtime/dispose").add(function() alive, active = false, false; state.token = "" end, "injected bridge fixture")
	return state
end
return M
