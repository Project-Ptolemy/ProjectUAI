-- Estimated text-token costs from the reviewed provider catalog snapshot.
-- Runtime policy is maintained here; tools/sync_pricing.js generates model_data.
return function(env)
	local info = env.require("provider/model_info")
	local community = env.require("provider/community_key")
	local urls = env.require("net/url")
	local clock = env.require("runtime/clock")
	local M = { updated = info.updated }
	local ZERO = { input = 0, output = 0, cacheRead = 0, cacheWrite = 0 }
	local LOCAL = { ollama = true, lmstudio = true, vllm = true, llamacpp = true, sglang = true }

	local function localEndpoint(record)
		local raw = tostring(record.baseUrl or "")
		if raw == "" then return LOCAL[record.preset] == true end
		local parsed = urls.parse(urls.normaliseBase(raw))
		if not parsed then return false end
		local host = parsed.host
		-- A loopback host denotes local inference, never a query-string substring.
		return host == "localhost" or host:match("%.localhost$") ~= nil
			or host:match("^127%.%d+%.%d+%.%d+$") ~= nil or host == "::1" or host == "0:0:0:0:0:0:0:1"
	end

	function M.ratesFor(model, record, promptTokens)
		if record and (community.isApplied(record) or localEndpoint(record)) then return ZERO end
		local row = info.lookup(model, record)
		local base = row and row.price
		if not base then return nil end
		-- A reviewed introductory rate cannot remain an estimate after its end
		-- date. Limits stay available while the next price awaits another review.
		if base.expiresAt and clock.ms() >= base.expiresAt then return nil end
		local rate = base
		for _, tier in ipairs(base.tiers or {}) do
			if (tonumber(promptTokens) or 0) > tier.above then rate = tier end
		end
		return rate
	end

	function M.priceFor(model, record, promptTokens)
		local rate = M.ratesFor(model, record, promptTokens)
		return rate and { rate.input, rate.output } or nil
	end

	function M.costFor(model, record, prompt, completion, cached, created)
		local rate = M.ratesFor(model, record, prompt)
		if not rate then return nil end
		cached = math.min(prompt, math.max(0, tonumber(cached) or 0))
		created = math.min(prompt - cached, math.max(0, tonumber(created) or 0))
		return ((prompt - cached - created) * rate.input + completion * rate.output
			+ cached * (rate.cacheRead or rate.input) + created * (rate.cacheWrite or rate.input)) / 1000000
	end
	return M
end
