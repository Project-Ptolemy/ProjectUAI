-- Google's native generateContent protocol. Signed model parts are retained
-- separately from presentation text and replayed unchanged to the same route.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local http = env.require("net/http")
	local sse = env.require("net/sse")
	local registry = env.require("provider/registry")
	local openai = env.require("provider/openai")
	local traits = env.require("provider/traits")
	local sampling = env.require("provider/sampling")
	local headers = env.require("net/headers")
	local M = {}
	local FINISH = { STOP = "stop", MAX_TOKENS = "length", SAFETY = "content_filter",
		RECITATION = "content_filter", BLOCKLIST = "content_filter", PROHIBITED_CONTENT = "content_filter",
		SPII = "content_filter", IMAGE_SAFETY = "content_filter", IMAGE_PROHIBITED_CONTENT = "content_filter" }

	local function modelId(record)
		local id = util.trim(record.model):gsub("^models/", "")
		if #id == 0 or #id > 160 or not id:match("^[%w_.%-]+$") then return nil, "Enter a Gemini model ID from this provider's model list" end
		return id
	end
	function M.endpoint(record, stream)
		local id = modelId(record)
		if not id then return registry.endpoint(record, "/models") end
		local query = util.copy(record.query or {})
		query.alt = stream and "sse" or "json"
		local route = util.copy(record); route.query = query
		return registry.endpoint(route, "/models/" .. util.urlEncode(id) .. (stream and ":streamGenerateContent" or ":generateContent"))
	end
	function M.headers(record, key)
		local auth = record
		if record.authStyle == nil and not registry.isOpencodeGo(record) then
			key = key or registry.nextKey(record) or ""
			auth = util.copy(record); auth.authStyle = "x-goog-api-key"
		end
		return headers.merge({ ["Content-Type"] = "application/json" }, registry.authHeaders(auth, key))
	end
	function M.errorText(response, err) return openai.errorText(response, err) end

	-- Empty tables must stay JSON objects for function arguments and schemas.
	local function object(value)
		if type(value) ~= "table" then return nil end
		if next(value) == nil then return util.emptyObject() end
		if util.isArray(value) then return nil end
		return util.deepCopy(value)
	end
	local function partsCopy(parts)
		if type(parts) ~= "table" or not util.isArray(parts) or #parts > 8192 then return nil, "Invalid Gemini response parts" end
		local out, bytes = {}, 0
		for _, part in ipairs(parts) do
			if type(part) ~= "table" then return nil, "Invalid Gemini response part" end
			local copy = {}
			if part.text ~= nil then
				if type(part.text) ~= "string" then return nil, "Invalid Gemini response text" end
				copy.text = part.text; bytes = bytes + #part.text
			end
			if part.thought ~= nil then copy.thought = part.thought == true end
			if part.thoughtSignature ~= nil then
				if type(part.thoughtSignature) ~= "string" then return nil, "Invalid Gemini thought signature" end
				copy.thoughtSignature = part.thoughtSignature; bytes = bytes + #part.thoughtSignature
			end
			if part.functionCall then
				local call = part.functionCall
				if type(call) ~= "table" or type(call.name) ~= "string" or #call.name == 0 or #call.name > 128
					or call.id ~= nil and (type(call.id) ~= "string" or #call.id == 0 or #call.id > 200) then return nil, "Invalid Gemini function call" end
				local args = object(call.args or {})
				if not args then return nil, "Invalid Gemini function arguments" end
				local encoded = util.encode(args)
				if #encoded > sse.limits.arguments then return nil, "Gemini function arguments exceed the supported limit" end
				copy.functionCall = { name = call.name, args = args, id = call.id }; bytes = bytes + #encoded
			end
			if part.inlineData or part.fileData then return nil, "This Gemini model returned media; select a text model for the agent conversation" end
			if next(copy) then out[#out + 1] = copy end
			if bytes > sse.limits.body then return nil, "Gemini response exceeds the supported size" end
		end
		return out
	end

	local function addText(parts, text)
		if type(text) == "string" and text ~= "" then parts[#parts + 1] = { text = text } end
	end
	local function addImage(parts, uri, mime)
		if type(uri) ~= "string" then error("Invalid Gemini image reference", 0) end
		local media, data = uri:match("^data:(image/[%w+.-]+);base64,(.+)$")
		if media then parts[#parts + 1] = { inlineData = { mimeType = media, data = data } }
		else parts[#parts + 1] = { fileData = { mimeType = mime or "image/png", fileUri = uri } } end
	end
	local function textParts(content)
		local parts = {}
		if type(content) == "table" then
			for _, block in ipairs(content) do
				if type(block) == "table" then
					if block.type == "text" then addText(parts, block.text)
					elseif block.type == "image_url" and type(block.image_url) == "table" then addImage(parts, block.image_url.url)
					end
				end
			end
		else addText(parts, tostring(content or "")) end
		return parts
	end
	function M.wireMessages(record, messages)
		local contents, system, pending = {}, {}, {}
		local scope = registry.compatibilityKey(record)
		local function append(role, parts, combine)
			if #parts == 0 then return end
			local previous = contents[#contents]
			if combine and previous and previous.role == role then
				for _, part in ipairs(parts) do previous.parts[#previous.parts + 1] = part end
			else contents[#contents + 1] = { role = role, parts = parts } end
		end
		for _, message in ipairs(messages or {}) do
			local role = message.role
			if role == "system" or role == "developer" then
				for _, part in ipairs(textParts(message.content)) do if part.text then system[#system + 1] = part end end
			elseif role == "assistant" then
				local calls = message.toolCalls or message.tool_calls or {}
				local parts
				if message.geminiParts and message.geminiScope == scope then
					local why; parts, why = partsCopy(message.geminiParts)
					if not parts then error(why, 0) end
				else
					parts = textParts(message.content)
					for _, call in ipairs(calls) do
						local fn = call["function"] or call
						local args = type(fn.arguments) == "table" and fn.arguments or util.decode(fn.arguments or "{}")
						parts[#parts + 1] = { functionCall = { name = fn.name, args = object(args or {}) or util.emptyObject() } }
					end
				end
				local index = 0
				for _, part in ipairs(parts) do if part.functionCall then
					index = index + 1
					local call = calls[index]
					if call and call.id then pending[call.id] = { name = part.functionCall.name, id = part.functionCall.id } end
				end end
				append("model", parts, false)
			elseif role == "tool" then
				local call = pending[message.tool_call_id] or { name = message.name }
				if not call.name then error("Gemini tool result has no matching function name", 0) end
				append("user", { { functionResponse = { name = call.name, id = call.id,
					response = { result = tostring(message.content or "") } } } }, true)
			else
				local parts = textParts(message.content)
				for _, image in ipairs(message.images or {}) do addImage(parts, image.url, image.mediaType) end
				append("user", parts, true)
			end
		end
		return contents, system
	end
	function M.wireTools(tools)
		local out = {}
		for _, definition in ipairs(tools or {}) do
			local fn = definition["function"] or definition
			if type(fn.name) == "string" then
				local schema = util.deepCopy(fn.parameters or { type = "object" })
				if type(schema.properties) == "table" and next(schema.properties) == nil then schema.properties = util.emptyObject() end
				out[#out + 1] = { name = fn.name, description = fn.description or fn.name, parametersJsonSchema = schema }
			end
		end
		return out
	end
	function M.buildBody(record, request)
		local contents, system = M.wireMessages(record, request.messages)
		local body = { contents = contents, generationConfig = {
			maxOutputTokens = openai.cappedMaxTokens(record, request.maxTokens or config.get("agent.maxTokens", 4096)) or 4096 } }
		if #system > 0 then body.systemInstruction = { parts = system } end
		local tools = M.wireTools(request.tools)
		if #tools > 0 then
			body.tools = { { functionDeclarations = tools } }
			local choice = request.toolChoice
			local mode = choice == "none" and "NONE" or choice == "required" and "ANY" or "AUTO"
			local settings = { mode = mode }
			if type(choice) == "table" and choice["function"] and choice["function"].name then
				settings.mode, settings.allowedFunctionNames = "ANY", { choice["function"].name }
			end
			body.toolConfig = { functionCallingConfig = settings }
		end
		local row = traits.of(record.model, record)
		if row.reasoning or row.thinking == "gemini-level" or row.thinking == "gemini-budget" then
			local thinking = { includeThoughts = config.get("ui.showReasoning", true) ~= false }
			local effort = openai.effortFor(record, request)
			if effort and row.thinking == "gemini-level" then thinking.thinkingLevel = effort:upper()
			elseif effort and row.thinking == "gemini-budget" then
				local budgets = { low = 1024, medium = 8192, high = row.thinkingMax or 24576 }
				thinking.thinkingBudget = budgets[effort]
			end
			body.generationConfig.thinkingConfig = thinking
		end
		body = util.merge(body, record.params or {})
		body = util.merge(body, request.extra or {})
		if type(body.generationConfig) ~= "table" then error("Gemini generationConfig must be an object", 0) end
		local ceiling = tonumber(request.outputCeiling)
		local wanted = tonumber(body.generationConfig.maxOutputTokens)
		if not wanted or wanted ~= wanted or wanted < 1 or wanted == math.huge then wanted = 4096 end
		wanted = openai.cappedMaxTokens(record, wanted) or wanted
		if ceiling and ceiling >= 1 and ceiling < math.huge then wanted = math.min(wanted, ceiling) end
		body.generationConfig.maxOutputTokens = math.max(1, math.floor(wanted))
		local id = modelId(record) or ""
		sampling.apply(record, request, body.generationConfig, { defaultOmit = id:match("^gemini%-[34]") ~= nil })
		return body
	end

	local function count(value)
		return type(value) == "number" and value == value and value >= 0 and value < math.huge and math.floor(value) or 0
	end
	local function usage(value)
		if type(value) ~= "table" or value.promptTokenCount == nil and value.candidatesTokenCount == nil and value.totalTokenCount == nil then return nil end
		local prompt, completion = count(value.promptTokenCount), count(value.candidatesTokenCount) + count(value.thoughtsTokenCount)
		return { prompt_tokens = prompt, completion_tokens = completion,
			total_tokens = count(value.totalTokenCount) > 0 and count(value.totalTokenCount) or prompt + completion,
			prompt_tokens_details = { cached_tokens = count(value.cachedContentTokenCount) },
			completion_tokens_details = { reasoning_tokens = count(value.thoughtsTokenCount) } }
	end
	local function resultFor(parts, finish, metadata, model, id)
		local copied, why = partsCopy(parts)
		if not copied then return nil, why end
		local text, reasoning, calls, seen = {}, {}, {}, {}
		local callPrefix = util.uid("gemini")
		for _, part in ipairs(copied) do
			if part.text then local target = part.thought and reasoning or text; target[#target + 1] = part.text end
			if part.functionCall then
				local call = part.functionCall
				local callId = call.id or (callPrefix .. "_" .. (#calls + 1))
				if seen[callId] or #calls >= sse.limits.calls then return nil, "Invalid or excessive Gemini function calls" end
				seen[callId] = true
				calls[#calls + 1] = { id = callId, type = "function", ["function"] = { name = call.name, arguments = util.encode(call.args) } }
			end
		end
		if not FINISH[finish] then return nil, "Gemini stopped without a complete response (" .. tostring(finish or "missing finish reason") .. ")" end
		if FINISH[finish] == "content_filter" and #calls > 0 then return nil, "Gemini filtered the function-call response" end
		return { role = "assistant", content = table.concat(text), reasoning = table.concat(reasoning), toolCalls = calls,
			finish = FINISH[finish], stopReason = finish, usage = usage(metadata), model = model, id = id, geminiParts = copied }
	end
	function M.fromResponse(decoded)
		if type(decoded) ~= "table" then return nil, "Invalid Gemini response" end
		if decoded.error then return nil, "Gemini returned an API error" end
		local candidate = type(decoded.candidates) == "table" and decoded.candidates[1]
		if type(candidate) ~= "table" then return nil, "Gemini did not return a candidate (" .. tostring(type(decoded.promptFeedback) == "table" and decoded.promptFeedback.blockReason or "empty response") .. ")" end
		if candidate.content ~= nil and type(candidate.content) ~= "table" then return nil, "Invalid Gemini candidate content" end
		return resultFor(candidate.content and candidate.content.parts or {}, candidate.finishReason, decoded.usageMetadata, decoded.modelVersion, decoded.responseId)
	end
	function M.parseStream(body, onFrame)
		local parts, finish, metadata, model, id, frames = {}, nil, {}, nil, nil, 0
		local failure
		local decoder = sse.decoder(function(frame)
			local decoded = util.decode(frame.data)
			failure = failure or sse.providerError(decoded or frame.data, frame.event)
			if failure then return false, failure end
			if type(decoded) ~= "table" then return false, "invalid Gemini stream JSON" end
			frames = frames + 1
			model, id = decoded.modelVersion or model, decoded.responseId or id
			if decoded.usageMetadata ~= nil and type(decoded.usageMetadata) ~= "table" then return false, "invalid Gemini stream usage" end
			for key, value in pairs(decoded.usageMetadata or {}) do metadata[key] = value end
			local candidate = type(decoded.candidates) == "table" and decoded.candidates[1]
			if candidate then
				if type(candidate) ~= "table" then return false, "invalid Gemini stream candidate" end
				if candidate.content ~= nil and type(candidate.content) ~= "table" then return false, "invalid Gemini stream content" end
				if candidate.content and candidate.content.parts ~= nil and (type(candidate.content.parts) ~= "table" or not util.isArray(candidate.content.parts)) then
					return false, "invalid Gemini stream parts"
				end
				if finish and candidate.content and #(candidate.content.parts or {}) > 0 then return false, "Gemini stream continued after its final response" end
				local visible, thought = {}, {}
				for _, part in ipairs(candidate.content and candidate.content.parts or {}) do
					if type(part) ~= "table" then return false, "invalid Gemini stream part" end
					if type(part.text) == "string" then local target = part.thought and thought or visible; target[#target + 1] = part.text end
					local previous = parts[#parts]
					-- Never combine a signed part or a function call. Ordinary adjacent
					-- text fragments can share a part without changing signed metadata.
					if type(part.text) == "string" and not part.thoughtSignature and not part.functionCall and not part.inlineData and not part.fileData and previous
						and type(previous.text) == "string" and not previous.thoughtSignature and not previous.functionCall and not previous.inlineData and not previous.fileData
						and previous.thought == part.thought then previous.text = previous.text .. part.text
					else parts[#parts + 1] = part end
				end
				finish = candidate.finishReason or finish
				if onFrame then pcall(onFrame, { model = model, choices = { { delta = { content = table.concat(visible),
					reasoning_content = table.concat(thought) }, finish_reason = FINISH[candidate.finishReason] } } }) end
			elseif type(decoded.promptFeedback) == "table" and decoded.promptFeedback.blockReason then
				return false, "Gemini blocked the prompt: " .. tostring(decoded.promptFeedback.blockReason)
			end
			return true
		end)
		local ok, why = decoder.push(body)
		if ok then ok, why = decoder.finish() end
		if not ok then return nil, why end
		local result, err = resultFor(parts, finish, metadata, model, id)
		if result then result.frames, result.chunks = frames, frames end
		return result, err
	end

	function M.complete(record, request)
		local problem = registry.protocolProblem(record)
		if problem then return nil, problem end
		local id, why = modelId(record)
		if not id then return nil, why end
		request = util.copy(request or {})
		local owned = sampling.owner(record)
		local wantStream = request.stream
		if wantStream == nil then wantStream = record.stream ~= false and config.get("agent.stream", true) end
		local transport = env.require("net/transport")
		if transport.streamForced() then wantStream = true end
		local ok, body = pcall(M.buildBody, record, request)
		if not ok then return nil, "Unable to prepare Gemini request: " .. tostring(body) end
		local scope, started = registry.compatibilityKey(record), clock.ms()
		local timeout = request.timeout or config.get("agent.requestTimeout", 86400)
		local relayUnlimited = transport.unlimited(request)
		local deadline = env.require("net/deadline").at(timeout, request.deadlineMs, started, relayUnlimited)
		local pool, key = registry.requestKeys(record), registry.nextKey(record)
		local accounting = env.require("runtime/request_accounting").new(record, request)
		local left = math.max(0, #pool - 1)
		local function cancelled()
			return not owned() or registry.compatibilityKey(record) ~= scope or request.aborted and request.aborted()
		end
		local function retry(note, status)
			if request.onRetry then pcall(request.onRetry, { attempt = 1, attempts = 2, wait = 0, status = status, reason = note }) end
		end
		local function fire()
			if cancelled() then return nil, "aborted" end
			local outgoing = headers.merge(M.headers(record, key), registry.opencodeHeaders(record, request), record.headers,
				{ Accept = wantStream and "text/event-stream" or "application/json" })
			return http.send({ url = M.endpoint(record, wantStream), method = "POST", body = util.encode(body),
				requiresAccess = true,
				onDispatch = function() accounting.dispatch(key, outgoing) end,
				headers = outgoing,
				relay = transport.shouldRelay(env.require("runtime/images").hasReferences(request.messages)), sessionId = request.sessionId,
				relayUnlimited = relayUnlimited,
				identity = registry.identityFor(record), identityRequired = registry.requiresClaude(record),
				attempts = request.attempts or config.get("agent.retries", 3), skipStatus = #pool > 1 and { [429] = true } or nil,
				timeout = timeout, deadlineMs = deadline, aborted = cancelled, onRetry = request.onRetry,
				onFrame = request.onFrame, tag = "gemini:" .. tostring(record.id) })
		end
		local response, err = fire()
		while response and not response.ok and not response.terminal and not http.terminal(err) and left > 0 and (response.status == 429 or (response.status == 403 or response.status == 402)
			and tostring(response.body):lower():find("resource_exhausted", 1, true)) and not cancelled() do
			left = left - 1; registry.cooldownKey(record, key); key = registry.nextKey(record)
			retry("Rate limited; trying the next configured key", response.status)
			response, err = fire()
		end
		if cancelled() then return nil, "aborted" end
		if response and not response.ok and not http.terminal(err) and sampling.repair(record, body.generationConfig, response, M.errorText(response, err), scope, owned) then
			retry("Omitted unsupported temperature", response.status); response, err = fire()
		end
		if cancelled() then return nil, "aborted" end
		if not response or not response.ok then
			local message = M.errorText(response, err); registry.markFail(record, message); return nil, message, response
		end
		local result, parseError
		if sse.looksStreamed(response.body) then
			local parsed, value, note = pcall(M.parseStream, response.body)
			result, parseError = parsed and value or nil, parsed and note or "Invalid Gemini stream"
		else
			local decoded = util.decode(response.body)
			if type(decoded) == "table" and decoded.error then parseError = M.errorText(response)
			else result, parseError = M.fromResponse(decoded) end
		end
		if not result then
			local message = sse.looksStreamed(response.body) and ("malformed_stream: " .. tostring(parseError)) or tostring(parseError)
			registry.markFail(record, message); return nil, message, response
		end
		accounting.attach(result)
		if cancelled() then return nil, "aborted" end
		if util.trim(result.content) == "" and #result.toolCalls == 0 then
			local message = result.finish == "content_filter" and "Gemini filtered this response" or "Gemini returned no answer or function call"
			registry.markFail(record, message); return nil, message, response
		end
		result.model = result.model or record.model
		result.provider, result.providerLabel, result.ms = record.id, record.label, clock.since(started)
		result.via, result.requestId, result.streamed = response.via, response.inferenceId, (result.frames or 0) > 0
		result.geminiScope = scope
		registry.markOk(record, result.ms)
		return result, nil, response
	end
	return M
end
