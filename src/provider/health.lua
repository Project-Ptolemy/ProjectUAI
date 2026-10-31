-- Bounded local observations, independent of account quotas and model access.
return function(env)
	local clock = env.require("runtime/clock")
	local util = env.require("runtime/util")
	local M = {}
	local function number(value)
		value = tonumber(value)
		return value and value == value and value >= 0 and value < math.huge and value or 0
	end
	function M.read(record)
		local value = type(record and record.health) == "table" and record.health or {}
		return { ok = math.floor(number(value.ok)), fail = math.floor(number(value.fail)), streak = math.floor(number(value.streak)),
			lastMs = number(value.lastMs), cooldownUntil = number(value.cooldownUntil),
			lastError = util.ellipsis(type(value.lastError) == "string" and value.lastError or "", 200) }
	end
	function M.remaining(record)
		return math.max(0, M.read(record).cooldownUntil - clock.ms())
	end
	function M.message(record)
		local remaining = M.remaining(record)
		if remaining > 0 then return "Cooling down for " .. util.formatDuration(remaining) end
		local state = M.read(record)
		if state.ok + state.fail == 0 then return "No requests observed yet" end
		return tostring(state.ok) .. " successful / " .. tostring(state.fail) .. " failed requests"
	end
	return M
end
