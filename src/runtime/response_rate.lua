-- Static request averages use provider counts and wall time, never preview pacing.
return function(env)
	local M = {}
	local function finite(value)
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end
	function M.validCount(value)
		return finite(value) and value >= 0 and value <= 1e12 and value == math.floor(value)
	end
	function M.outputTokens(usage)
		if type(usage) ~= "table" or usage.output_tokens_reported == false then return nil end
		if M.validCount(usage.completion_tokens) then return usage.completion_tokens end
		if M.validCount(usage.output_tokens) then return usage.output_tokens end
		return nil
	end
	function M.rate(outputTokens, requestMs)
		if not M.validCount(outputTokens) or not finite(requestMs) or requestMs <= 0 then return nil end
		local rate = outputTokens / (requestMs / 1000)
		return finite(rate) and rate or nil
	end
	function M.text(outputTokens, requestMs)
		local rate = M.rate(outputTokens, requestMs)
		if not rate then return nil end
		if rate > 0 and rate < 0.1 then return "<0.1 tk/s request avg" end
		if rate >= 1e6 then return string.format("%.3g tk/s request avg", rate) end
		return string.format("%.1f tk/s request avg", rate)
	end
	return M
end
