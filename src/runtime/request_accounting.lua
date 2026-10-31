-- Locally observed inference dispatches and their measured token usage.
-- References contain opaque IDs only; credentials and names never enter statistics.
return function(env)
	local clock = env.require("runtime/clock")
	local signal = env.require("runtime/signal")
	local keys = env.require("runtime/provider_keys")
	local M = { dispatched = signal.new("inference:dispatched"), tokens = signal.new("inference:tokens") }

	function M.conversationId(session)
		if type(session) == "string" then return session end
		local seen = {}
		while type(session) == "table" and not seen[session] do
			seen[session] = true
			local parent = session.accountingParent
			if type(parent) == "function" then
				local ok, value = pcall(parent)
				parent = ok and value or nil
			end
			if type(parent) ~= "table" then
				return not session.headless and (tonumber(session.depth) or 0) == 0 and session.id or nil
			end
			session = parent
		end
	end

	local function count(value)
		local number = tonumber(value)
		if not number or number ~= number or number < 0 or number > 9007199254740991 then return nil end
		return math.floor(number)
	end

	-- Providers can report one side without the other. Credit each field once;
	-- existing agent estimates may fill an absent field after successful parsing.
	function M.report(reference, usage, fallback)
		if type(reference) ~= "table" then return end
		usage = type(usage) == "table" and usage or {}
		local input = count(usage.prompt_tokens) or count(usage.input_tokens)
		local output = count(usage.completion_tokens) or count(usage.output_tokens)
		local inputEstimated, outputEstimated = false, false
		if input == nil and fallback then input = count(fallback.prompt); inputEstimated = input ~= nil end
		if output == nil and fallback then output = count(fallback.completion); outputEstimated = output ~= nil end
		local delta = { reference = reference, prompt = 0, completion = 0, estimated = false }
		local changed = false
		if reference.input == nil and input ~= nil then
			reference.input, delta.prompt, changed = input, input, true
			delta.estimated = inputEstimated
		end
		if reference.output == nil and output ~= nil then
			reference.output, delta.completion, changed = output, output, true
			delta.estimated = delta.estimated or outputEstimated
		end
		if changed then M.tokens:fire(delta) end
	end

	function M.new(record, request)
		keys.ensureIds(record)
		local providerId = tostring(record.id or "")
		local conversationId = M.conversationId(request and (request.session or request.sessionId))
		local identities, authenticated = {}, record.authStyle ~= "none"
		for index, secret in ipairs(keys.keys(record)) do identities[secret] = record.keyIds[index] end
		local tracker = {}
		function tracker.dispatch(secret, headers)
			local keyId
			local sent = headers == nil
			for name, value in pairs(headers or {}) do
				local lower = tostring(name):lower()
				local bearer = type(value) == "string" and value:match("^%s*[Bb][Ee][Aa][Rr][Ee][Rr]%s+(.+)%s*$")
				if bearer then bearer = bearer:gsub("%s+$", "") end
				if (lower == "authorization" or lower == "x-api-key" or lower == "api-key" or lower == "x-goog-api-key")
					and (value == secret or lower == "authorization" and bearer == secret) then sent = true end
			end
			if sent and secret and secret ~= "" and authenticated then keyId = identities[secret] end
			local reference = { providerId = providerId, keyId = keyId, conversationId = conversationId, at = clock.ms() }
			tracker.latest = reference
			M.dispatched:fire(reference)
		end
		function tracker.attach(result)
			if type(result) ~= "table" then return result end
			result.accounting = tracker.latest
			M.report(tracker.latest, result.usage)
			return result
		end
		return tracker
	end

	return M
end
