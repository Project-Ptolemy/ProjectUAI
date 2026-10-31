-- Normalizes optional helper capabilities from either local transport.
return function(env)
	local capability = env.require("net/capability")
	local M = {}
	local states = { standby = true, disabled = true, starting = true, downloading = true,
		ready = true, rotating = true, limited = true, failed = true }
	function M.read(value)
		return capability.read(value, states, { ready = true, rotating = true })
	end
	return M
end
