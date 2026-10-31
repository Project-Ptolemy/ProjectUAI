-- One temperature policy for all request protocols and both model pickers.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local registry = env.require("provider/registry")
	local traits = env.require("provider/traits")
	local M = {}
	-- Draft tests and routed snapshots learn locally. A saved record loses its
	-- authority when an editor replaces it or the user removes the provider.
	function M.owner(record)
		local registered = registry.get(record.id) == record
		return function() return not registered or registry.get(record.id) == record end
	end
	function M.state(record, model)
		model = tostring(model or (record and record.model) or ""):lower()
		local supported = traits.of(model, record).sampling
		local override = (config.get("agent.forceSampling", {}) or {})[model]
		if type(override) == "boolean" then
			return { allowed = override, source = "manual", override = override and "send" or "omit", supported = supported }
		end
		if supported == false then return { allowed = false, source = "documented", override = "auto", supported = false } end
		if record and tostring(record.model or ""):lower() == model and (record.repairScope == nil or record.repairScope == registry.compatibilityKey(record)) then
			for _, repair in ipairs(record.repairs or {}) do
				if repair == "temperature" then return { allowed = false, source = "learned", override = "auto", supported = supported } end
			end
		end
		return { allowed = true, source = supported == true and "documented" or "default", override = "auto", supported = supported }
	end
	function M.set(model, value)
		return env.require("provider/model_overrides").sampling(model, value)
	end
	function M.apply(record, request, body, options)
		request, options = request or {}, options or {}
		local state = M.state(record)
		if not state.allowed then
			body.temperature, body.top_p, body.top_k, body.topP, body.topK = nil, nil, nil, nil, nil
			return body
		end
		local value = body.temperature
		if value == nil then value = request.temperature end
		if value == nil and (not options.defaultOmit or state.override == "send") then value = config.get("agent.temperature", 0.4) end
		body.temperature = type(value) == "number" and value == value and math.abs(value) < math.huge and value or nil
		return body
	end
	function M.isRejection(message)
		local text = tostring(message or ""):lower()
		if not text:find("temperature", 1, true) then return false end
		for _, phrase in ipairs({ "not supported", "unsupported", "does not support", "not allowed", "not permitted", "unknown", "unrecognized", "not accept", "not configurable" }) do
			if text:find(phrase, 1, true) then return true end
		end
		return text:find("only", 1, true) ~= nil and text:find("default", 1, true) ~= nil
	end
	function M.repair(record, body, response, message, scope, owns)
		if not response or response.terminal or (response.status ~= 400 and response.status ~= 422)
			or body.temperature == nil or not M.isRejection(message) or registry.compatibilityKey(record) ~= scope
			or (owns and not owns()) then return false end
		body.temperature = nil
		if record.repairScope ~= nil and record.repairScope ~= scope then record.repairs = {} end
		record.repairScope = scope
		local repairs = util.copy(record.repairs or {})
		for _, value in ipairs(repairs) do if value == "temperature" then return true end end
		repairs[#repairs + 1] = "temperature"; record.repairs = repairs
		if registry.get(record.id) == record then registry.save(record, { force = true }) end
		return true
	end
	return M
end
