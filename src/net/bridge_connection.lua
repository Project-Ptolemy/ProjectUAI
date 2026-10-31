-- Shared effective connection. Desktop credentials never enter saved settings.
return function(env)
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local caps = env.require("runtime/caps")
	local http = env.require("net/http")
	local util = env.require("runtime/util")
	local signal = env.require("runtime/signal")
	local M = { PORT = 28791, changed = signal.new("bridge connection") }
	local alive, started, paused = true, false, false
	local desktop, epoch, nextProbe = nil, 0, 0
	local function phone()
		local ok, value = pcall(function() return env.uis.TouchEnabled == true and env.uis.MouseEnabled ~= true end)
		return ok and value
	end

	local function automatic()
		return alive and not paused and config.get("bridge.autoDiscover", true) == true
			and config.get("bridge.enabled", false) ~= true and not phone()
	end

	function M.get()
		if config.get("bridge.enabled", false) == true then
			return { enabled = alive and not paused, source = "manual", port = config.get("bridge.port", 8790),
				token = tostring(config.get("bridge.token", "")) }
		end
		if automatic() and desktop then
			return { enabled = true, source = "desktop", port = M.PORT, token = desktop.token, instance = desktop.instance }
		end
		return { enabled = false, source = "none", port = M.PORT, token = "" }
	end

	function M.enabled() return M.get().enabled end
	function M.searching() return not config.accessProblem() and automatic() and caps.has("http") end

	local function accept(value)
		return type(value) == "table" and value.product == "project-uai-desktop" and value.protocol == 1
			and value.port == M.PORT and type(value.token) == "string" and #value.token == 64
			and value.token:match("^[a-f0-9]+$") ~= nil and type(value.instance) == "string"
			and #value.instance > 0 and #value.instance <= 128
	end

	function M.startDiscovery()
		if config.accessProblem() or started or not alive or not caps.has("http") then return end
		started = true
		clock.spawn(function()
			while alive do
				if not config.accessProblem() and automatic() and clock.ms() >= nextProbe then
					local mine = epoch
					local response, err = http.request({ url = "http://127.0.0.1:" .. M.PORT .. "/api/desktop/discover",
						method = "POST", body = "{}", headers = { ["X-UAI-Discovery"] = "1" },
						identity = "none", silent = true, timeout = 2, waitForSlot = true,
						aborted = function() return config.accessProblem() ~= nil or not automatic() or epoch ~= mine end })
					if not config.accessProblem() and alive and automatic() and mine == epoch then
						local capacity = not response and tostring(err or ""):find("capacity:", 1, true)
						local value = response and response.ok and #response.body <= 1024 and util.decode(response.body)
						if capacity then value = desktop elseif not accept(value) then value = nil end
						local changed = (desktop == nil) ~= (value == nil)
							or (desktop and value and (desktop.token ~= value.token or desktop.instance ~= value.instance))
						desktop = value
						nextProbe = clock.ms() + 4000
						if changed then M.changed:fire() end
					end
				end
				clock.wait(0.25)
			end
		end)
	end

	function M.pause()
		paused, desktop, epoch = true, nil, epoch + 1
		M.changed:fire()
	end

	function M.resume()
		if config.accessProblem() then return end
		local changed = paused
		paused, nextProbe, epoch = false, 0, epoch + 1
		M.startDiscovery()
		if changed then M.changed:fire() end
	end

	dispose.add(config.changed:connect(function(path)
		if path ~= nil and path ~= "bridge" and path ~= "bridge.enabled" and path ~= "bridge.port"
			and path ~= "bridge.token" and path ~= "bridge.autoDiscover" then return end
		epoch, nextProbe, desktop, paused = epoch + 1, 0, nil, false
		M.changed:fire()
	end), "bridge connection settings")
	dispose.add(function()
		alive, desktop, epoch = false, nil, epoch + 1
	end, "desktop discovery")
	return M
end
