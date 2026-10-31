-- Native transports and protocol retries spend one bounded request budget.
return function(env)
	local clock = env.require("runtime/clock")
	local M = {}
	function M.seconds(value, fallback)
		local number = tonumber(value)
		if not number or number ~= number then number = tonumber(fallback) or 120 end
		if number ~= number then number = 120 end
		return math.max(1, math.min(300, number))
	end
	function M.at(timeout, deadlineMs, started, unlimited)
		if unlimited == true then return math.huge end
		local stop = tonumber(deadlineMs)
		if not stop or stop ~= stop then stop = math.huge end
		return math.min(stop, (started or clock.ms()) + M.seconds(timeout) * 1000)
	end
	function M.expired(deadlineMs)
		local stop = tonumber(deadlineMs)
		return stop ~= nil and stop == stop and clock.ms() >= stop
	end
	return M
end
