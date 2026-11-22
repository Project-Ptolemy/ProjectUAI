-- Persisted inference-rate values. Counters and reservations stay in memory.
return function(env)
	local M = { MAX = 1000000 }
	function M.valid(value)
		return type(value) == "number" and value == value and value >= 0
			and value <= M.MAX and value % 1 == 0
	end
	function M.problem(value, optional)
		if value == nil and optional then return nil end
		if M.valid(value) then return nil end
		return "Requests per minute must be a whole number from 0 to " .. tostring(M.MAX) .. "; 0 is unlimited."
	end
	function M.configProblem(data)
		if type(data) ~= "table" then return nil end
		local agent = data.agent
		local problem = type(agent) == "table" and M.problem(agent.requestsPerMinute, true) or nil
		if problem then return "agent.requestsPerMinute: " .. problem end
		local providers = data.providers
		for _, record in pairs(type(providers) == "table" and type(providers.list) == "table" and providers.list or {}) do
			if type(record) == "table" then
				problem = M.problem(record.requestsPerMinute, true)
				if problem then return "provider.requestsPerMinute: " .. problem end
			end
		end
		return nil
	end
	function M.settingProblem(path, value)
		if path == "agent.requestsPerMinute" or path:match("^providers%.list%.%d+%.requestsPerMinute$") then
			return M.problem(value)
		end
		if path:match("^agent%.requestsPerMinute%.") or path:match("^providers%.list%.%d+%.requestsPerMinute%.") then
			return "Requests per minute is a number, not a setting section."
		end
		if path == "agent" then return M.configProblem({ agent = value }) end
		if path == "providers" then return M.configProblem({ providers = value }) end
		if path == "providers.list" then return M.configProblem({ providers = { list = value } }) end
		if path:match("^providers%.list%.%d+$") then return M.configProblem({ providers = { list = { value } } }) end
		return nil
	end
	return M
end
