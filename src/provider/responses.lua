-- The OpenAI Responses adapter, for documented model and tool routes.
--
-- Zen serves some models (muse-spark contributor builds) exclusively on the
-- Responses protocol: /chat/completions answers ModelProtocolUnsupported for
-- them, while the Responses endpoint streams full reasoning and text.
-- This adapter speaks that lane and returns the same normalised result the
-- chat adapter does, so everything above it is unchanged.
--
-- The chat adapter delegates for known Responses models, remembered routes,
-- or an explicit protocol/free-tier refusal on desktop. Provider/chat does not select it.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local http = env.require("net/http")
	local sse = env.require("net/sse")
	local urls = env.require("net/url")
	local headerMap = env.require("net/headers")
	local registry = env.require("provider/registry")
	local agentrouter = env.require("provider/agentrouter")
	local proxy = env.require("provider/proxy")
	local toolCatalog = env.require("provider/tool_catalog")

	local M = {}
	local HISTORY_ITEMS, HISTORY_BYTES, HISTORY_NODES = 256, 2097152, 16384
	M.limits = { historyItems = HISTORY_ITEMS, historyBytes = HISTORY_BYTES, historyNodes = HISTORY_NODES }
	local function directOpenai(record)
		return registry.isDirectOpenaiResponses(record)
	end
	local function historyScope(record)
		if not directOpenai(record) then return nil end
		-- Compatibility keys retain query parameters for live route ownership.
		-- Conversation files need only a stable comparison token, never that URL.
		local digest = env.require("runtime/credential_sha256").digest("ProjectUAI Responses history v1\n" .. registry.compatibilityKey(record))
		if type(digest) ~= "string" or #digest ~= 32 then error("Could not fingerprint Responses history scope", 0) end
		return "sha256:" .. (digest:gsub(".", function(char) return string.format("%02x", char:byte()) end))
	end

	-- Opaque reasoning tokens must survive unchanged. Reject malformed or oversized
	-- data rather than truncating it into an unusable tool-history signature.
	function M.itemsCopy(items)
		if not util.isArray(items) or #items > HISTORY_ITEMS then return nil, "Invalid Responses history item count" end
		local bytes, nodes, seen = 0, 0, {}
		local function copy(value, depth)
			nodes = nodes + 1
			if nodes > HISTORY_NODES or depth > 16 then error("Responses history exceeds its structure limit", 0) end
			local kind = type(value)
			if kind == "string" then
				if not util.validUtf8(value) then error("Invalid Responses history text", 0) end
				bytes = bytes + #value + 8
				if bytes > HISTORY_BYTES then error("Responses history exceeds its 2 MiB limit", 0) end
				return value
			elseif kind == "number" then
				if value ~= value or math.abs(value) == math.huge then error("Invalid Responses history number", 0) end
				bytes = bytes + 24; return value
			elseif kind == "boolean" then bytes = bytes + 8; return value
			elseif kind ~= "table" then error("Invalid Responses history value", 0) end
			if seen[value] then error("Invalid cyclic Responses history", 0) end
			seen[value] = true
			local out, fields, array = {}, 0, util.isArray(value)
			for key, child in pairs(value) do
				fields = fields + 1
				if fields > HISTORY_ITEMS then error("Responses history exceeds its field limit", 0) end
				if array then
					if key < 1 or key ~= math.floor(key) then error("Invalid Responses history array", 0) end
				elseif type(key) ~= "string" or #key > 128 or not util.validUtf8(key) then
					error("Invalid Responses history field", 0)
				end
				bytes = bytes + (type(key) == "string" and #key or 8) + 8
				out[key] = copy(child, depth + 1)
			end
			seen[value] = nil
			return out
		end
		local ok, out = pcall(function()
			for _, item in ipairs(items) do
				if type(item) ~= "table" or type(item.type) ~= "string" or #item.type > 80
					or not item.type:match("^[a-z_]+$") then error("Invalid Responses history item type", 0) end
			end
			local cloned = copy(items, 0)
			if #util.encode(cloned) > HISTORY_BYTES then error("Responses history exceeds its 2 MiB limit", 0) end
			return cloned
		end)
		return ok and out or nil, not ok and tostring(out) or nil
	end

	local RESPONSES_KEY = "responses_protocol"
	function M.key() return RESPONSES_KEY end

	function M.eligible(record)
		return directOpenai(record) or registry.isOpencode(record) or agentrouter.matches(record)
	end

	-- Models verified to speak only the Responses lane (live 200 on
	-- /inference/openai/v1/responses with chat refused). Proactive so the
	-- first turn never burns a chat refusal: on the direct route the free-tier
	-- gate answers 403 before protocol validation runs, so a reactive switch
	-- would never fire there.
	function M.wantsResponses(record)
		if not M.eligible(record) then return false end
		if directOpenai(record) then return true end
		if agentrouter.matches(record) then return agentrouter.protocol(record) == "responses" end
		if registry.isOpencodeGo(record) then return registry.opencodeGoProtocol(record) == "responses" end
		return tostring(record and record.model or ""):find("muse-spark", 1, true) ~= nil
	end

	function M.isProtocolRefusal(res)
		if not res or tonumber(res.status) ~= 400 then return false end
		if http.isOpencodeFreeUsageRefusal(res) then return false end
		local decoded = util.decode(tostring(res.body or ""))
		if type(decoded) ~= "table" then return false end
		local failure = decoded.error
		local function unsupported(text)
			return text:find("does not support this protocol", 1, true) ~= nil
				or (text:find("does not support /v1/chat/completions", 1, true) ~= nil and text:find("/v1/responses", 1, true) ~= nil)
		end
		if type(failure) == "string" then
			return unsupported(failure)
		end
		if type(failure) == "table" then
			if tostring(failure.type or "") == "ModelProtocolUnsupported" then return true end
			return unsupported(tostring(failure.message or ""))
		end
		return false
	end

	function M.isFreeTierRefusal(res)
		if not res or tonumber(res.status) ~= 403 then return false end
		if http.isOpencodeFreeUsageRefusal(res) then return false end
		local decoded = util.decode(tostring(res.body or ""))
		if type(decoded) ~= "table" then return false end
		local failure = decoded.error
		if type(failure) == "string" then
			local text = failure:lower()
			return text:find("freetiererror", 1, true) ~= nil
				or text:find("can only be used from within opencode", 1, true) ~= nil
				or text:find("free tier can only be used from within", 1, true) ~= nil
		end
		if type(failure) == "table" then
			local t = tostring(failure.type or ""):lower()
			local n = tostring(failure.name or ""):lower()
			local c = tostring(failure.code or ""):lower()
			if t == "freetiererror" or n == "freetiererror" or c == "freetiererror" then return true end
			local msg = tostring(failure.message or ""):lower()
			return msg:find("can only be used from within opencode", 1, true) ~= nil
				or msg:find("free tier can only be used from within", 1, true) ~= nil
				or msg:find("freetiererror", 1, true) ~= nil
		end
		return false
	end

	function M.canRetryFreeTier(res)
		local mobile = false
		pcall(function() mobile = env.uis.TouchEnabled == true and env.uis.MouseEnabled ~= true end)
		return not mobile and M.isFreeTierRefusal(res)
	end

	function M.remembered(record)
		local scope = registry.compatibilityKey(record)
		if record.repairScope ~= nil and record.repairScope ~= scope then return false end
		for _, existing in ipairs(record.repairs or {}) do
			if existing == RESPONSES_KEY then return true end
		end
		return false
	end

	-- OpenCode uses its official inference route. Direct OpenAI and AgentRouter
	-- retain their supported saved routes and query parameters.
	function M.endpointFor(record)
		if directOpenai(record) or registry.isOpencodeGo(record) or agentrouter.matches(record) then return registry.endpoint(record, "/responses") end
		if not registry.isOpencode(record) then return nil end
		local parsed = urls.parse(record.baseUrl or "")
		local query = parsed and parsed.query
		local base = "https://opencode.ai/inference/v1" .. (query and query ~= "" and ("?" .. query) or "")
		return urls.endpoint(base, "/responses", record.query)
	end

	local function textOf(content)
		if type(content) == "string" then return content end
		if type(content) ~= "table" then return "" end
		local parts = {}
		for _, block in ipairs(content) do
			if type(block) == "table" and type(block.text) == "string" and block.text ~= "" then
				parts[#parts + 1] = block.text
			end
		end
		return table.concat(parts, "")
	end

	-- Chat history into Responses input items. Text passes through; assistant
	-- tool calls become function_call items and tool answers become
	-- function_call_output items so multi-turn agent loops keep working.
	function M.inputFor(messages, record)
		local input, instructions = {}, {}
		local scope = historyScope(record)
		for _, message in ipairs(messages or {}) do
			local role = message.role
			if role == "system" or role == "developer" then
				local text = textOf(message.content)
				if util.trim(text) ~= "" then instructions[#instructions + 1] = text end
			elseif role == "tool" then
				input[#input + 1] = {
					type = "function_call_output",
					call_id = tostring(message.tool_call_id or message.id or ""),
					output = textOf(message.content),
				}
			elseif role == "assistant" and scope and message.responsesItems and message.responsesScope == scope then
				local items, why = M.itemsCopy(message.responsesItems)
				if not items then error(why, 0) end
				for _, item in ipairs(items) do input[#input + 1] = item end
			elseif role == "assistant" and message.toolCalls and #message.toolCalls > 0 then
				if util.trim(textOf(message.content)) ~= "" then
					input[#input + 1] = { role = "assistant", content = textOf(message.content) }
				end
				for _, call in ipairs(message.toolCalls) do
					local fn = call["function"]
					input[#input + 1] = {
						type = "function_call",
						call_id = tostring(call.id or ""),
						name = tostring((type(fn) == "table" and fn.name) or call.name or ""),
						arguments = tostring((type(fn) == "table" and fn.arguments) or call.arguments or "{}"),
					}
				end
			elseif role == "user" or role == "assistant" then
				local content = message.content
				if role == "user" then content = env.require("runtime/images").openai(content, message.images) end
				if type(content) == "table" then
					local parts = {}
					for _, block in ipairs(content) do
						if type(block) == "table" then
							if block.type == "input_image" then
								parts[#parts + 1] = block
							elseif block.type == "image_url" and type(block.image_url) == "table" then
								parts[#parts + 1] = { type = "input_image", image_url = tostring(block.image_url.url or "") }
							elseif type(block.text) == "string" and block.text ~= "" then
								parts[#parts + 1] = { type = role == "assistant" and "output_text" or "input_text", text = block.text }
							end
						end
					end
					if #parts > 0 then input[#input + 1] = { role = role, content = parts } end
				elseif util.trim(tostring(content or "")) ~= "" then
					input[#input + 1] = { role = role, content = tostring(content) }
				end
			end
		end
		return input, table.concat(instructions, "\n\n")
	end

	-- Chat-shaped tool definitions into Responses shape: top-level name and
	-- parameters rather than nested under a "function" key. Already-flat
	-- definitions pass through untouched.
	function M.toolsFor(tools)
		if type(tools) ~= "table" or #tools == 0 then return nil end
		local out = {}
		for _, tool in ipairs(tools) do
			if type(tool) == "table" then
				local fn = tool["function"]
				if type(fn) == "table" then
					local translated = {
						type = "function",
						name = tostring(fn.name or ""),
						description = tostring(fn.description or ""),
						parameters = type(fn.parameters) == "table" and fn.parameters or { type = "object", properties = {} },
					}
					if type(fn.strict) == "boolean" then translated.strict = fn.strict end
					out[#out + 1] = translated
				elseif type(tool.name) == "string" then
					out[#out + 1] = tool
				end
			end
		end
		if #out == 0 then return nil end
		return out
	end

	local function toolDefaults(record, body)
		agentrouter.toolDefaults(record, body)
		if not directOpenai(record) then return end
		if type(body.tools) == "table" then
			local explicit = {}
			for index, tool in ipairs(body.tools) do
				explicit[index] = util.deepCopy(tool)
				if tool.type == "function" and tool.strict == nil then explicit[index].strict = false end
			end
			body.tools = explicit
		end
		local choice = body.tool_choice
		if type(choice) == "table" and type(choice["function"]) == "table" then
			body.tool_choice = { type = "function", name = choice["function"].name }
		end
	end

	function M.buildBody(record, request)
		request = request or {}
		local direct = directOpenai(record)
		local input, instructions = M.inputFor(request.messages, record)
		if registry.isOpencodeZen(record) then
			instructions = env.require("provider/opencode_context").instructions(instructions)
		end
		local body = {
			model = record.model,
			input = input,
			-- OpenCode's free lane requires SSE. Direct OpenAI retains the normal
			-- stream preference below.
			stream = true,
		}
		if direct then
			local stream = request.stream
			if stream == nil then stream = record.stream ~= false and config.get("agent.stream", true) end
			if env.require("net/transport").streamForced() then stream = true end
			body.stream, body.store = stream, false
			local level = env.require("provider/openai").effortFor(record, request)
			local reasoning = {}
			if level then reasoning.effort = level end
			if config.get("ui.showReasoning", true) ~= false then reasoning.summary = "auto" end
			if next(reasoning) then body.reasoning = reasoning end
		end
		if instructions ~= "" then body.instructions = instructions end
		local tools = M.toolsFor(request.tools) or {}
		local names = {}
		for _, tool in ipairs(tools) do names[tool.name] = true end
		for _, tool in ipairs(registry.isOpencode(record) and M.toolsFor(env.require("provider/openai").opencodeTools) or {}) do
			if not names[tool.name] then
				tools[#tools + 1] = tool
				names[tool.name] = true
			end
		end
		local openai = env.require("provider/openai")
		if #tools > 0 then body.tools = tools end
		if direct and body.tools then body.parallel_tool_calls = request.parallelToolCalls ~= false end
		if request.toolChoice ~= nil then body.tool_choice = request.toolChoice end
		-- The lane has its own spelling and rejections: max_output_tokens rather
		-- than max_tokens, and no reasoning_effort (the server answers unknown
		-- parameter). Temperature is only sent when explicitly asked for.
		local wanted = tonumber(request.maxTokens or config.get("agent.maxTokens", 4096)) or 0
		local documented = env.require("provider/traits").maxOutput(record.model, record)
		if documented and documented > 0 and wanted > documented then wanted = documented end
		local ceiling = tonumber(request.outputCeiling)
		if ceiling and ceiling >= 1 and ceiling < wanted then wanted = math.floor(ceiling) end
		if wanted > 0 then body.max_output_tokens = wanted end
		agentrouter.responsesDefaults(record, request, body)
		for key, value in pairs(record.params or {}) do body[key] = value end
		for key, value in pairs(request.extra or {}) do body[key] = value end
		if direct and body.model ~= record.model then error("Direct Responses model override must match the selected model", 0) end
		local toolCeiling = openai.toolCeiling(record)
		if type(body.tools) == "table" and #body.tools > toolCeiling then
			openai.limitTools(body, toolCeiling, registry.isOpencode(record))
		end
		toolDefaults(record, body)
		local sampling = env.require("provider/sampling")
		sampling.apply(record, request, body, { defaultOmit = true })
		if direct then
			local effort = type(body.reasoning) == "table" and body.reasoning.effort
			local omitLogprobs = effort ~= "none" and sampling.state(record).override ~= "send"
			if omitLogprobs then
				body.temperature, body.top_p, body.top_k, body.top_logprobs, body.logprobs = nil, nil, nil, nil, nil
			end
			-- Stateless reasoning/tool continuations require the original encrypted
			-- reasoning items even when their human-readable summaries are hidden.
			local include, retained = {}, {}
			for _, field in ipairs(type(body.include) == "table" and body.include or {}) do
				if type(field) == "string" and field ~= "" and not retained[field]
					and (not omitLogprobs or field ~= "message.output_text.logprobs") then
					include[#include + 1], retained[field] = field, true
				end
			end
			if not retained["reasoning.encrypted_content"] then include[#include + 1] = "reasoning.encrypted_content" end
			body.include = include
		end
		-- Apply temporary and documented reply limits after raw parameters, too.
		local final = tonumber(body.max_output_tokens)
		local cap = tonumber(request.outputCeiling)
		if cap and cap == cap and cap >= 1 and cap < math.huge then
			final = final and final == final and final > 0 and math.min(final, cap) or cap
		end
		if final and final == final and final > 0 and final < math.huge then
			if documented and documented > 0 then final = math.min(final, documented) end
			body.max_output_tokens = math.floor(final)
		end
		return body
	end

	-- One Responses object (streamed or whole) into the assembler shape the
	-- chat adapter returns, so the loop cannot tell which lane answered.
	local function assembleOutput(output)
		local content, reasoning, calls = {}, {}, {}
		for _, item in ipairs(type(output) == "table" and output or {}) do
			if type(item) == "table" then
				if item.type == "message" then
					for _, part in ipairs(type(item.content) == "table" and item.content or {}) do
						if type(part) == "table" and part.type == "output_text" and type(part.text) == "string" and part.text ~= "" then
							content[#content + 1] = part.text
						end
					end
				elseif item.type == "function_call" then
					if #calls >= sse.limits.calls then return "", "", {}, "tool call limit exceeded" end
					local arguments = item.arguments == nil and "{}" or item.arguments
					if type(arguments) ~= "string" then return "", "", {}, "tool arguments must be a string" end
					if #arguments > sse.limits.arguments then return "", "", {}, "tool argument limit exceeded" end
					calls[#calls + 1] = {
						id = tostring(item.call_id or item.id or ""),
						type = "function",
						["function"] = {
							name = tostring(item.name or ""),
							arguments = arguments,
						},
					}
				elseif item.type == "reasoning" then
					for _, part in ipairs(type(item.summary) == "table" and item.summary or {}) do
						if type(part) == "table" and type(part.text) == "string" and part.text ~= "" then
							reasoning[#reasoning + 1] = part.text
						end
					end
				end
			end
		end
		return table.concat(content), table.concat(reasoning, "\n"), calls
	end

	function M.parse(body)
		local completion = sse.completionDiagnostic("responses")
		local content, reasoning, slots, order = {}, {}, {}, {}
		local usage, model, id, streamError, frames, responsesOutput = nil, nil, nil, nil, 0, nil
		local completed = false
		local function slotFor(itemId, callId, outputIndex)
			local keys = {}
			if type(itemId) == "string" and itemId ~= "" then keys[#keys + 1] = "id:" .. itemId end
			if type(callId) == "string" and callId ~= "" then keys[#keys + 1] = "id:" .. callId end
			if type(outputIndex) == "number" and outputIndex >= 0 and outputIndex < math.huge and outputIndex == math.floor(outputIndex) then
				keys[#keys + 1] = "index:" .. tostring(outputIndex)
			end
			if #keys == 0 then error("tool call has no item, call or output identity", 0) end
			local slot
			for _, key in ipairs(keys) do
				local existing = slots[key]
				if existing then
					if slot and slot ~= existing then error("conflicting tool call identities", 0) end
					slot = existing
				end
			end
			if not slot then
				if #order >= sse.limits.calls then error("tool call limit exceeded", 0) end
				slot = { id = itemId, args = {}, bytes = 0 }
				order[#order + 1] = slot
			end
			if type(callId) == "string" and callId ~= "" then
				if slot.callId and slot.callId ~= callId then error("conflicting tool call identity", 0) end
				slot.id, slot.callId = callId, callId
			end
			for _, key in ipairs(keys) do slots[key] = slot end
			return slot
		end
		local function argumentsFor(slot, arguments, replace)
			if arguments == nil then return end
			if type(arguments) ~= "string" then error("tool arguments must be a string", 0) end
			local bytes = (replace and 0 or slot.bytes) + #arguments
			if bytes > sse.limits.arguments then error("tool argument limit exceeded", 0) end
			if replace then slot.args = { arguments }
			else
				if slot.complete then error("tool argument delta arrived after completion", 0) end
				slot.args[#slot.args + 1] = arguments
			end
			slot.bytes = bytes
		end
		local decoder = sse.decoder(function(frame)
			frames = frames + 1
			local payload = util.trim(frame.data)
			if payload == "" or payload == "[DONE]" then return true end
			local decoded = util.decode(payload)
			local providerError = sse.providerError(decoded or payload, frame.event)
			if providerError then streamError = streamError or providerError; return true end
			if type(decoded) ~= "table" then
				streamError = streamError or "malformed_stream: invalid JSON frame"
				return true
			end
			completion.observe(decoded, frame.event)
			local kind = tostring(decoded.type or frame.event or "")
			local response = type(decoded.response) == "table" and decoded.response or nil
			local status = response and response.status
			if kind == "response.failed" or kind == "response.incomplete" or kind == "response.cancelled"
				or status == "failed" or status == "incomplete" or status == "cancelled" then
				local detail = response and (response.error or response.incomplete_details)
				streamError = streamError or sse.providerError({ error = detail or { message = "Responses request " .. tostring(status or kind) } }, "error")
				return true
			end
			if kind == "response.output_text.delta" and type(decoded.delta) == "string" then
				content[#content + 1] = decoded.delta
			elseif kind == "response.function_call_arguments.delta" then
				local slot = slotFor(decoded.item_id, decoded.call_id, decoded.output_index)
				argumentsFor(slot, decoded.delta, false)
			elseif kind == "response.function_call_arguments.done" then
				local slot = slotFor(decoded.item_id, decoded.call_id, decoded.output_index)
				argumentsFor(slot, decoded.arguments, true)
				slot.complete = true
			elseif (kind == "response.output_item.added" or kind == "response.output_item.done") and type(decoded.item) == "table" then
				local item = decoded.item
				if item.type == "function_call" then
					local slot = slotFor(item.id, item.call_id, decoded.output_index)
					if type(item.name) == "string" then slot.name = item.name end
					-- Done items contain the full value, not another delta. Bind both
					-- IDs to one slot and replace fragments even when IDs coincide.
					if kind == "response.output_item.done" then
						argumentsFor(slot, item.arguments, true); slot.complete = true
					elseif item.arguments ~= nil and item.arguments ~= "" then argumentsFor(slot, item.arguments, true) end
				elseif item.type == "reasoning" and kind == "response.output_item.done" then
					for _, part in ipairs(type(item.summary) == "table" and item.summary or {}) do
						if type(part) == "table" and type(part.text) == "string" and part.text ~= "" then
							reasoning[#reasoning + 1] = part.text
						end
					end
				end
			elseif kind == "response.completed" and type(decoded.response) == "table" then
				completed = true
				local response = decoded.response
				model = model or response.model
				id = id or response.id
				if type(response.usage) == "table" then usage = response.usage end
				-- The completed payload is authoritative: done items repeat the
				-- text already streamed as deltas, so a non-empty final output
				-- replaces the accumulated partials rather than doubling them.
				if type(response.output) == "table" then
					responsesOutput = response.output
					local finalContent, finalReasoning, finalCalls, finalError = assembleOutput(response.output)
					if finalError then error(finalError, 0) end
					if finalContent ~= "" then content = { finalContent } end
					if finalReasoning ~= "" then reasoning = { finalReasoning } end
					if #response.output > 0 then
						slots, order = {}, {}
						for _, call in ipairs(finalCalls) do
							local slot = slotFor(nil, call.id)
							slot.name = call["function"].name
							argumentsFor(slot, call["function"].arguments, true)
						end
					end
				end
			end
			return true
		end)
		local ok, why = decoder.push(body)
		if ok then ok, why = decoder.finish() end
		streamError = streamError or (not ok and why or nil)
		local calls = {}
		for _, slot in ipairs(order) do
			if slot.name then
				calls[#calls + 1] = {
					id = slot.id or ("call_" .. tostring(#calls + 1)),
					type = "function",
					["function"] = { name = slot.name, arguments = table.concat(slot.args) },
				}
			end
		end
		return {
			role = "assistant",
			content = table.concat(content),
			reasoning = table.concat(reasoning, "\n"),
			toolCalls = calls,
			finish = completed and "stop" or nil,
			model = model,
			id = id,
			usage = usage,
			responsesOutput = responsesOutput,
			frames = frames,
			streamError = streamError or (not completed and completion.error() or nil),
		}
	end

	function M.fromResponse(decoded)
		if type(decoded) ~= "table" then return nil end
		local output = decoded.output
		if type(decoded) == "table" and decoded.object == "response" and output == nil then output = {} end
		local content, reasoning, calls, outputError = assembleOutput(output)
		local usage = type(decoded.usage) == "table" and decoded.usage or nil
		local responseError
		if decoded.status and decoded.status ~= "completed" then
			responseError = sse.providerError({ error = decoded.error or decoded.incomplete_details
				or { message = "Responses request " .. tostring(decoded.status) } }, "error")
		end
		return {
			role = "assistant",
			content = content,
			reasoning = reasoning,
			toolCalls = calls,
			finish = tostring(decoded.status or "completed") == "completed" and "stop" or nil,
			model = decoded.model,
			id = decoded.id,
			usage = usage,
			responsesOutput = decoded.output,
			frames = 0,
			streamError = responseError or (outputError and ("malformed_stream: " .. outputError) or nil),
		}
	end

	local function requestTimeout(request)
		if request.timeout then return request.timeout end
		if config.get("agent.requestUnlimited", false) then return 86400 end
		return config.get("agent.requestTimeout", 86400)
	end

	function M.complete(record, request, handoff)
		local owns = handoff and handoff.owns or env.require("provider/sampling").owner(record)
		local problem = registry.protocolProblem(record)
		if problem then return nil, problem end
		if not M.eligible(record) then return nil, "Responses is unavailable for this endpoint and model" end
		request = util.copy(request or {})
		handoff = handoff or {}
		if request.onRetry then
			local callback = request.onRetry
			request.onRetry = function(info) if not pcall(callback, info) then log.warn("provider", "retry callback failed safely") end end
		end
		local prepared, body = pcall(M.buildBody, record, request)
		if not prepared then return nil, "Unable to prepare Responses request: " .. tostring(body) end
		local url = M.endpointFor(record)
		-- Share the live-verified desktop fingerprint with Chat, including stable
		-- conversation affinity and explicit saved compatibility overrides.
		local pool = registry.requestKeys(record)
		local currentKey = handoff.key or registry.nextKey(record)
		local accounting = env.require("runtime/request_accounting").new(record, request)
		local rotationsLeft = math.min(handoff.rotationsLeft or math.max(#pool - 1, 0), math.max(#pool - 1, 0))
		local function headersFor()
			local defaults = directOpenai(record) and { Accept = body.stream and "text/event-stream" or "application/json" } or {}
			return headerMap.merge(defaults, registry.authHeaders(record, currentKey or ""), registry.opencodeHeaders(record, request), record.headers)
		end
		local started = clock.ms()
		local relayUnlimited = handoff.relayUnlimited
		if relayUnlimited == nil then relayUnlimited = env.require("net/transport").unlimited(request) end
		if handoff.deadlineMs and handoff.deadlineMs < math.huge then relayUnlimited = false end
		local deadline = handoff.deadlineMs or env.require("net/deadline").at(requestTimeout(request), request.deadlineMs, started, relayUnlimited)
		local scope = registry.compatibilityKey(record)
		local recovery = proxy.new(record, { aborted = request.aborted, onRetry = request.onRetry, deadlineMs = deadline })
		local attemptsAllowed = request.attempts or config.get("agent.retries", 3)
		local function fire()
			if not owns() or registry.compatibilityKey(record) ~= scope then return nil, "aborted" end
			if clock.ms() >= deadline then return nil, "deadline: request budget expired" end
			local imageRequest = env.require("runtime/images").hasReferences(request.messages)
			local headers = headersFor()
			local res, err = http.send({
				requiresAccess = true,
				onDispatch = function() accounting.dispatch(currentKey, headers) end,
				relay = env.require("net/transport").shouldRelay(imageRequest), sessionId = request.sessionId,
				relayUnlimited = relayUnlimited,
				url = url, method = "POST", headers = headers, body = util.encode(body),
				identity = registry.identityFor(record), identityRequired = registry.requiresClaude(record),
				attempts = attemptsAllowed, skipStatus = #pool > 1 and { [429] = true } or nil,
				aborted = request.aborted, onRetry = request.onRetry, tag = "responses:" .. record.id,
				onFrame = request.onFrame,
				timeout = requestTimeout(request), deadlineMs = deadline,
			})
			if request.aborted and request.aborted() then return nil, "aborted" end
			if not (res and res.terminal) and not http.terminal(err) and recovery.recover(res, err) then
				scope, url = registry.compatibilityKey(record), M.endpointFor(record)
				return fire()
			end
			return res, err
		end
		local res, err = fire()
		while res and not res.terminal and not http.terminal(err) do
			if not res.ok and res.status == 429 and not http.isOpencodeFreeUsageRefusal(res) and rotationsLeft > 0 then
				rotationsLeft = rotationsLeft - 1
				registry.cooldownKey(record, currentKey)
				currentKey = registry.nextKey(record)
				if request.onRetry then request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = "rate limited, rotating API key", status = res.status }) end
			else break end
			res, err = fire()
		end
		if request.aborted and request.aborted() then return nil, "aborted" end
		-- An explicit declaration-limit refusal is safe to repair once. Keep the
		-- full catalogue behind the same router and teach only this live scope.
		local toolLimit = res and not res.ok and (res.status == 400 or res.status == 422)
			and not res.terminal and not http.terminal(err)
			and env.require("provider/openai").toolCeilingFromMessage(env.require("provider/openai").errorText(res, err))
		if toolLimit and body.tools and #body.tools > toolLimit and owns() and registry.compatibilityKey(record) == scope then
			local openai = env.require("provider/openai")
			openai.limitTools(body, toolLimit, registry.isOpencode(record))
			toolDefaults(record, body)
			openai.rememberToolCeiling(record, toolLimit)
			if request.onRetry then request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = "limited tool declarations with catalogue preserved", status = res.status }) end
			res, err = fire()
		end
		if not http.terminal(err) and env.require("provider/sampling").repair(record, body, res,
			env.require("provider/openai").errorText(res, err), scope, owns) then
			if request.onRetry then request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = "omitted unsupported temperature", status = res.status }) end
			res, err = fire()
		end
		if not owns() or registry.compatibilityKey(record) ~= scope then return nil, "aborted" end
		if not res or not res.ok then
			local message = env.require("provider/openai").errorText(res, err)
			registry.markFail(record, message)
			return nil, message, res
		end
		local parsed
		if sse.looksStreamed(res.body) then
			parsed = M.parse(res.body)
		else
			local decoded = util.decode(res.body)
			if type(decoded) ~= "table" then
				local message = "provider returned a body that is not JSON: " .. tostring(decoded)
				registry.markFail(record, message)
				return nil, message, res
			end
			if decoded.error then
				local message = env.require("provider/openai").errorText(res, nil)
				registry.markFail(record, message)
				return nil, message, res
			end
			if directOpenai(record) and (decoded.object ~= "response" or type(decoded.status) ~= "string") then
				local message = "malformed_stream: direct Responses body needs a response object and completion status"
				registry.markFail(record, message)
				return nil, message, res
			end
			parsed = M.fromResponse(decoded)
		end
		if directOpenai(record) and not parsed.streamError then
			local items, why = M.itemsCopy(parsed.responsesOutput)
			if not items then parsed.streamError = "malformed_stream: " .. tostring(why)
			else parsed.responsesItems, parsed.responsesScope = items, historyScope(record) end
		end
		parsed.responsesOutput = nil
		accounting.attach(parsed)
		if parsed.streamError then
			registry.markFail(record, parsed.streamError)
			return nil, "stream error: " .. parsed.streamError, res
		end
		local hasText = util.trim(parsed.content) ~= ""
		local hasCalls = #(parsed.toolCalls or {}) > 0
		if not hasText and not hasCalls and util.trim(parsed.reasoning) == "" then
			local message = "the provider returned an empty completion"
			registry.markFail(record, message)
			return nil, message, res
		end
		parsed.ms = clock.since(started)
		parsed.provider = record.id
		parsed.providerLabel = record.label
		parsed.via = res.via
		parsed.requestId = res.inferenceId
		parsed.streamed = parsed.frames and parsed.frames > 0 or false
		registry.markOk(record, parsed.ms)
		return toolCatalog.bind(parsed, body), nil, res
	end

	return M
end
