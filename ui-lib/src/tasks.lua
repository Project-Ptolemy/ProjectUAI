return function(env)
	local C = env.require("core")
	local M = {}
	function M.Delay(window, seconds, callback)
		assert(window.Alive, "Window is destroyed")
		assert(C.finite(seconds) and seconds >= 0 and seconds <= 3600, "Delay must be between 0 and 3600 seconds")
		assert(type(callback) == "function", "Delay callback must be a function")
		return window._scope:Delay(seconds, function() C.call(window, callback) end)
	end
	function M.Debounce(window, seconds, callback)
		assert(window.Alive, "Window is destroyed")
		assert(C.finite(seconds) and seconds >= 0 and seconds <= 3600, "Debounce must be between 0 and 3600 seconds")
		assert(type(callback) == "function", "Debounce callback must be a function")
		local cancel, args, size
		local function stop()
			if cancel then cancel(); cancel = nil end
			args, size = nil, nil
		end
		window:Give(stop)
		local function schedule(...)
			if not window.Alive then return false end
			stop()
			args, size = { ... }, select("#", ...)
			cancel = window._scope:Delay(seconds, function()
				local latest, count = args, size
				cancel, args, size = nil, nil, nil
				C.call(window, callback, (table.unpack or unpack)(latest, 1, count))
			end)
			return true
		end
		return schedule, stop
	end
	return M
end
