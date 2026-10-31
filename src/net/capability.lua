-- Supported local capability metadata, with bounded display text and state.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	function M.read(value, states, availableStates)
		if type(value) ~= "table" or value.schema ~= 1 then return nil end
		local state = type(value.state) == "string" and states[value.state] and value.state or "unavailable"
		local enabled = value.enabled == true
		availableStates = availableStates or { ready = true }
		if not enabled and availableStates[state] then state = "disabled" end
		return { enabled = enabled, available = enabled and value.available == true and availableStates[state] == true,
			state = state, message = util.truncate(type(value.message) == "string" and util.trim(value.message) or "", 400),
			version = type(value.version) == "string" and util.truncate(value.version, 80) or nil }
	end
	return M
end
