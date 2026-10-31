-- Picks the wire protocol for a provider record.
--
-- Adapters implement one contract: OpenAI Chat, Anthropic Messages and native
-- Google Gemini. This is the only place that decides which one a record uses.
-- Everything above it (the agent loop,
-- the transcript, the connection test) is written against one shape and does not
-- know there is a choice.
--
-- `record.api` is the switch. It is absent on every record saved before the second
-- adapter existed, and absent means OpenAI. Documented Go model families select
-- their required adapter without changing the saved choice for other endpoints.
return function(env)
	local M = {}

	M.STYLES = {
		{ value = "openai", label = "Chat completions" },
		{ value = "anthropic", label = "Anthropic messages" },
		{ value = "gemini", label = "Google Gemini" },
	}

	function M.styleOf(record)
		if env.require("provider/agentrouter").protocol(record) == "responses" then return "openai" end
		local protocol = env.require("provider/registry").opencodeGoProtocol(record)
		if protocol then return protocol == "gemini" and "gemini" or protocol == "anthropic" and "anthropic" or "openai" end
		if record and record.api == "gemini" then return "gemini" end
		return (tostring(record and record.api or "openai") == "anthropic")
			and "anthropic" or "openai"
	end

	function M.adapterFor(record)
		if M.styleOf(record) == "gemini" then return env.require("provider/gemini") end
		if M.styleOf(record) == "anthropic" then
			return env.require("provider/anthropic")
		end
		return env.require("provider/openai")
	end

	-- Display the effective wire API rather than the compatibility adapter used
	-- internally to reach Responses routes.
	function M.protocolOf(record)
		local style = M.styleOf(record)
		local responses = env.require("provider/responses")
		if style == "openai" and responses.eligible(record) and (responses.wantsResponses(record) or responses.remembered(record)) then return "responses" end
		return style
	end
	function M.supportsSocket(record)
		return M.protocolOf(record) == "openai" and not env.require("provider/registry").isCline(record)
	end

	function M.complete(record, request)
		local support = env.require("runtime/support")
		local problem = env.require("provider/registry").protocolProblem(record)
		if problem then return nil, support.error(problem) end
		env.require("net/transport").prepare()
		if request and request.aborted and request.aborted() then return nil, "aborted" end
		local result, err, response = M.adapterFor(record).complete(record, request)
		return result, err and support.error(err) or nil, response
	end

	function M.errorText(record, res, err)
		return M.adapterFor(record).errorText(res, err)
	end

	-- The headers a record's requests carry, including the ones its wire protocol
	-- requires. Model discovery hits the same host, so it asks for these too rather
	-- than assembling auth itself and getting the Anthropic case wrong.
	function M.headers(record, request)
		local adapter = M.adapterFor(record)
		local registry = env.require("provider/registry")
		local headers = adapter.headers and adapter.headers(record) or registry.authHeaders(record)
		return env.require("net/headers").merge(headers, registry.opencodeHeaders(record, request), record.headers)
	end

	-- The path a record's completions go to, for the Providers panel to show.
	function M.endpointOf(record)
		local responses = env.require("provider/responses")
		if M.styleOf(record) == "openai" and responses.eligible(record)
			and (responses.wantsResponses(record) or responses.remembered(record)) then
			return responses.endpointFor(record)
		end
		local adapter = M.adapterFor(record)
		if adapter.endpoint then return adapter.endpoint(record) end
		return env.require("provider/registry").endpoint(record, "/chat/completions")
	end

	function M.contextOverflow(message)
		return env.require("provider/openai").contextWindowFromMessage(message)
	end

	return M
end
