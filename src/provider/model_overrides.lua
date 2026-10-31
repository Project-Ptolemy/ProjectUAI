-- Validated manual capability claims shared by both model surfaces.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local modelId = env.require("provider/model_id")
	local M = { maxContext = 10000000 }
	local function save(model, path, value)
		local id, why = modelId.parse(model)
		if not id then return false, why end
		local problem = config.accessProblem()
		if problem then return false, problem end
		local map = util.copy(config.get(path, {}) or {})
		map[id:lower()] = value
		config.set(path, map)
		return true
	end
	function M.context(model, text)
		if text == nil or util.trim(tostring(text)) == "" then return save(model, "agent.forceContext", nil) end
		local value = tonumber(text)
		if not value or value ~= value or value < 1 or value > M.maxContext then return false, "Enter a token count from 1 to 10,000,000, or leave it empty for the documented value." end
		return save(model, "agent.forceContext", math.floor(value))
	end
	function M.reasoning(model, enabled)
		if type(enabled) ~= "boolean" then return false, "Choose whether reasoning support is enabled." end
		return save(model, "agent.forceReasoning", enabled and true or nil)
	end
	function M.sampling(model, mode)
		if mode ~= "auto" and mode ~= "send" and mode ~= "omit" then return false, "Unknown temperature policy" end
		local value
		if mode ~= "auto" then value = mode == "send" end
		return save(model, "agent.forceSampling", value)
	end
	return M
end
