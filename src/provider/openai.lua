-- The OpenAI chat-completions adapter.
--
-- One request shape in, one normalised result out. Everything vendor-specific
-- lives here: auth style, the streaming decision, error extraction, and the
-- parameter repairs that make the same call work across a dozen gateways that all
-- claim to be OpenAI-compatible and none of which quite are.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local http = env.require("net/http")
	local sse = env.require("net/sse")
	local registry = env.require("provider/registry")
	local proxy = env.require("provider/proxy")
	local traits = env.require("provider/traits")
	local responses = env.require("provider/responses")
	local urls = env.require("net/url")
	local headerMap = env.require("net/headers")
	local toolCatalog = env.require("provider/tool_catalog")

	local M = {}

	-- The executor's own transport wall, answered with a smaller ask. Some executors
	-- hard-cap every HTTP request at thirty or sixty seconds and ignore Timeout
	-- entirely, so no config value lifts that wall. What can change is the ask: a
	-- model that thinks for ninety seconds finishes inside sixty when asked to think
	-- less. One notch of effort down and the reply ceiling halved, and only when the
	-- first attempt produced nothing at all -- a refusal with a body is a decision,
	-- not a deadline, and retrying it smaller is not going to change the answer.
	-- Returns the shrunk body and a one-line note, or nil when there is nothing left
	-- to shrink.
	local function smallerAsk(body)
		local changes = {}
		local lowered = util.copy(body)

		local order = { "low", "medium", "high", "xhigh", "max" }
		local current = 0
		for index, level in ipairs(order) do
			if level == tostring(body.reasoning_effort or "") then current = index break end
		end
		if current > 1 then
			lowered.reasoning_effort = order[current - 1]
			changes[#changes + 1] = "effort " .. lowered.reasoning_effort
		end

		local ceiling = tonumber(body.max_tokens or body.max_completion_tokens)
		if ceiling and ceiling > 4000 then
			local halved = math.floor(ceiling / 2)
			if body.max_tokens then lowered.max_tokens = halved
			else lowered.max_completion_tokens = halved end
			changes[#changes + 1] = "max_tokens " .. halved
		end

		if #changes == 0 then return nil end
		return lowered, table.concat(changes, ", ")
	end

	-- Requested wait budget, shared by HTTP and gateway sockets. Native transports
	-- enforce their own 300-second bound; executor/provider limits may be shorter.
	local function requestTimeout(request)
		if request.timeout then return request.timeout end
		if config.get("agent.requestUnlimited", false) then return 86400 end
		return config.get("agent.requestTimeout", 86400)
	end

	-- Messages are rewritten into the wire shape rather than passed through, so a
	-- field the context store finds useful (timing, ids) cannot leak into a
	-- payload. Reasoning models (DeepSeek-R1, Claude thinking, QwQ, etc.) require
	-- previous assistant reasoning to be passed back on subsequent turns to
	-- maintain thinking state.
	function M.wireMessages(messages)
		local out = {}
		for _, message in ipairs(messages or {}) do
			local entry = { role = message.role }
			if message.role == "tool" then
				entry.tool_call_id = message.tool_call_id
				entry.content = tostring(message.content or "")
			elseif message.role == "assistant" then
				if message.toolCalls and #message.toolCalls > 0 then
					-- An assistant turn that called tools must replay those calls
					-- verbatim, and content may legitimately be an empty string.
					entry.content = message.content or ""
					entry.tool_calls = {}
					for _, call in ipairs(message.toolCalls) do
						entry.tool_calls[#entry.tool_calls + 1] = {
							id = call.id,
							type = "function",
							["function"] = {
								name = call["function"] and call["function"].name or call.name,
								arguments = call["function"] and call["function"].arguments or call.arguments or "{}",
							},
						}
					end
				elseif type(message.content) == "table" then
					entry.content = message.content
				else
					entry.content = tostring(message.content or "")
				end
				local reasoning = message.reasoning_content or message.reasoning
				if type(reasoning) == "string" and util.trim(reasoning) ~= "" then
					entry.reasoning_content = reasoning
				end
			else
				if type(message.content) == "table" then
					entry.content = message.content
				else
					entry.content = tostring(message.content or "")
				end
			end
			if message.role == "user" then entry.content = env.require("runtime/images").openai(entry.content, message.images) end
			out[#out + 1] = entry
		end
		return out
	end

	-- Standard OpenCode tool definitions required by OpenCode Zen free tier
	local OPENCODE_TOOLS = {
		{
			type = "function",
			["function"] = {
				name = "bash",
				description = "Execute bash command",
				parameters = {
					type = "object",
					properties = {
						command = { type = "string", description = "The command to run" },
					},
					required = { "command" },
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "read",
				description = "Read file",
				parameters = {
					type = "object",
					properties = {
						path = { type = "string", description = "The path to the file" },
					},
					required = { "path" },
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "edit",
				description = "Edit file",
				parameters = {
					type = "object",
					properties = {
						path = { type = "string", description = "The path to the file" },
					},
					required = { "path" },
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "glob",
				description = "Find files",
				parameters = {
					type = "object",
					properties = {
						pattern = { type = "string", description = "Glob pattern" },
					},
					required = { "pattern" },
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "grep",
				description = "Search pattern",
				parameters = {
					type = "object",
					properties = {
						pattern = { type = "string", description = "Regex pattern" },
					},
					required = { "pattern" },
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "list",
				description = "List files",
				parameters = {
					type = "object",
					properties = {
						path = { type = "string", description = "Directory path" },
					},
				},
			},
		},
		{
			type = "function",
			["function"] = {
				name = "shell",
				description = "Execute shell command",
				parameters = {
					type = "object",
					properties = {
						command = { type = "string", description = "The command to run" },
					},
					required = { "command" },
				},
			},
		},
	}

	-- The declarations are shared with the Responses adapter, which must carry
	-- them too so the same compatibility check passes on that lane.
	M.opencodeTools = OPENCODE_TOOLS
	local OPENCODE_NAMES = {}
	for _, tool in ipairs(OPENCODE_TOOLS) do OPENCODE_NAMES[tool["function"].name] = true end
	function M.limitTools(body, limit, isOpencode)
		toolCatalog.limit(body, limit, isOpencode and OPENCODE_NAMES or nil)
	end

	function M.buildBody(record, request)
		local body = {
			messages = M.wireMessages(request.messages),
		}

		-- The classic Azure preview path takes the model from the deployment in the
		-- URL and rejects the field; everyone else -- the Azure v1 surface included
		-- -- requires it.
		if record.preset ~= "azure" and util.trim(record.model) ~= "" then
			body.model = record.model
		end

		if request.tools and #request.tools > 0 then
			body.tools = request.tools
			-- Ollama accepts tools but does not implement tool_choice. Keep automatic
			-- selection implicit; an explicit override remains the user's choice.
			if record.preset ~= "ollama" or request.toolChoice then body.tool_choice = request.toolChoice or "auto" end
			if request.parallelToolCalls ~= nil then
				body.parallel_tool_calls = request.parallelToolCalls == true
			elseif record.preset ~= "ollama" then
				body.parallel_tool_calls = true
			end
		end

		-- Keep compatibility declarations for desktop direct and older bridges.
		-- The native CLI adapter supplies real schemas and removes these placeholders.
		if registry.isOpencode(record) then
			body.stream = true
			body.stream_options = { include_usage = true }

			if not body.tools or #body.tools == 0 then
				body.tools = OPENCODE_TOOLS
				body.tool_choice = "auto"
			else
				local toolNames = {}
				for _, t in ipairs(body.tools) do
					local name = t["function"] and t["function"].name or t.name
					if name then toolNames[name] = true end
				end
				local merged = { unpack(body.tools) }
				for _, stdTool in ipairs(OPENCODE_TOOLS) do
					if not toolNames[stdTool["function"].name] then
						merged[#merged + 1] = stdTool
					end
				end
				body.tools = merged
				body.tool_choice = body.tool_choice or "auto"
			end
		end

		local maxTokens = M.cappedMaxTokens(record, request.maxTokens or config.get("agent.maxTokens", 4096))
		if maxTokens and maxTokens > 0 then body.max_tokens = maxTokens end

		-- Reasoning depth, spelled the way the chat-completions wire spells it. Only
		-- sent to a model with a scale to place it on, and clamped to that scale, so
		-- asking for more than a model has is a smaller request rather than a refusal.
		local effort = M.effortFor(record, request)
		if effort then body.reasoning_effort = effort end

		if request.stream then
			body.stream = true
			body.stream_options = { include_usage = true }
		end

		for key, value in pairs(record.params or {}) do body[key] = value end
		for key, value in pairs(request.extra or {}) do body[key] = value end
		-- Apply the wire limit after overrides too: the full enabled catalogue
		-- can exceed Chat Completions' 128 declarations even for unknown models.
		local toolCeiling = M.toolCeiling(record)
		if type(body.tools) == "table" and #body.tools > toolCeiling then
			M.limitTools(body, toolCeiling, registry.isOpencode(record))
		end
		env.require("provider/sampling").apply(record, request, body)
		M.enforceOutputCeiling(record, body, request.outputCeiling)
		if not body.stream then body.stream_options = nil end
		return body
	end

	-- Error text, in the order gateways actually use. A 401 with an empty body is
	-- common enough that the status alone has to produce something readable.
	local STATUS_TEXT = {
		[400] = "the provider rejected the request",
		[401] = "the API key was rejected",
		[402] = "the account is out of credit",
		[403] = "the provider refused the request -- the key may lack access to it",
		[404] = "endpoint or model not found -- check the base URL and model name",
		[410] = "the endpoint has been retired",
		[413] = "the request was too large",
		[422] = "the provider could not process the request",
		[429] = "rate limited",
		[500] = "the provider had an internal error",
		[502] = "the provider gateway is unavailable",
		[503] = "the provider is overloaded",
		[529] = "the provider is overloaded",
	}

	-- An HTML body on a refusal is not the API talking.
	--
	-- A gateway answers in JSON. A whole HTML document -- especially one opening with
	-- Cloudflare's `<!--[if lt IE 7]>` conditional-comment block -- means the request was
	-- stopped in front of the API and never reached the account, the key or the model. So
	-- naming any of those as a possible cause, which the 403 text did, sends the reader
	-- off to check three things that are all fine. The response headers say which edge it
	-- was: `server`, `cf-ray` and `cf-mitigated` are already kept for the Requests view.
	local function edgeBlock(res)
		if not res then return nil end
		local body = util.trim(tostring(res.body or ""))
		if body == "" then return nil end
		local head = body:sub(1, 400):lower()
		local looksHtml = body:sub(1, 1) == "<"
			and (head:find("<!doctype", 1, true) or head:find("<html", 1, true)
				or head:find("<!--[if", 1, true))
		if not looksHtml then return nil end
		local bits = {}
		local server = util.trim(tostring(http.header(res, "server") or ""))
		local mitigated = util.trim(tostring(http.header(res, "cf-mitigated") or ""))
		local ray = util.trim(tostring(http.header(res, "cf-ray") or ""))
		if server ~= "" then bits[#bits + 1] = server end
		if mitigated ~= "" then bits[#bits + 1] = "cf-mitigated " .. mitigated end
		if ray ~= "" then bits[#bits + 1] = ray end
		return #bits > 0 and table.concat(bits, ", ") or "an edge in front of the API"
	end

	local function errorText(res, err)
		if err and not res then return tostring(err) end
		local status = res and res.status or 0
		-- Checked before the status table, because the status is the least informative
		-- thing about this class of failure.
		local edge = edgeBlock(res)
		if edge then
			return string.format(
				"stopped before it reached the API (%d) by %s. It answered with an HTML page "
				.. "rather than JSON, so the key, the model and the account are not implicated -- "
				.. "the request itself was refused. Turning off the Claude Code identity for this "
				.. "provider is the one thing this client can change about how it looks.",
				status, edge)
		end
		local decoded = res and util.decode(res.body) or nil
		local message
		if type(decoded) == "table" then
			if type(decoded.error) == "table" then
				local errType = tostring(decoded.error.type or decoded.error.name or decoded.error.code or "")
				local errMsg = tostring(decoded.error.message or "")
				if env.require("runtime/support").opencodeProblem(errMsg) then
					message = errMsg
				elseif tostring(decoded.error.type):lower() == "freetiererror" or tostring(decoded.error.name):lower() == "freetiererror"
					or tostring(decoded.error.code):lower() == "freetiererror" or errMsg:lower():find("can only be used from within opencode", 1, true) then
					message = (errMsg ~= "" and errMsg or "Error from provider (Console): OpenCode's free tier can only be used from within OpenCode")
						.. " -- " .. env.require("runtime/support").opencode()
				elseif errType == "ModelProtocolUnsupported" or errMsg:find("does not support this protocol", 1, true) then
					message = (errMsg ~= "" and errMsg or "Model does not support this protocol")
						.. " -- the model does not answer on this route"
				else
					message = decoded.error.message or decoded.error.type or decoded.error.code
				end
			elseif type(decoded.error) == "string" then
				message = decoded.error
			elseif type(decoded.message) == "string" then
				message = decoded.message
			elseif type(decoded.detail) == "string" then
				message = decoded.detail
			elseif type(decoded.detail) == "table" then
				-- FastAPI/Pydantic servers report an array of {loc,msg,type}. Never
				-- echo their `input` field, which may contain the entire prompt.
				local parts = {}
				for index, detail in ipairs(decoded.detail) do
					if index > 8 then break end
					if type(detail) == "table" then
						local location = {}
						for _, part in ipairs(type(detail.loc) == "table" and detail.loc or {}) do
							if type(part) == "string" or type(part) == "number" then location[#location + 1] = tostring(part) end
						end
						parts[#parts + 1] = table.concat(location, ".") .. ": " .. tostring(detail.msg or detail.type or "invalid field")
					end
				end
				message = table.concat(parts, "; ")
			end
		end
		if not message or message == "" then
			local raw = res and util.trim(res.body) or ""
			if raw ~= "" and #raw < 400 and not raw:find("^<") then
				message = raw
			end
		end
		local prefix = STATUS_TEXT[status]
		local problem = env.require("runtime/support").opencodeProblem(message)
		if problem == "subscription" then prefix = "OpenCode Go subscription access was refused"
		elseif problem == "region" then prefix = "OpenCode Go requires a different workspace region" end
		-- A refusal that carries no body at all is worth naming as such. It usually
		-- means the call never reached the API, so nothing about the key or the model
		-- accounts for it, and the answer is in the response headers the Requests view
		-- now keeps rather than anywhere in this string.
		if (not message or message == "") and res and util.trim(res.body or "") == "" then
			return string.format("%s (%d), and the response had no body -- see the Requests view",
				prefix or "the request was refused", status)
		end
		if message and prefix then return string.format("%s (%d): %s", prefix, status, message) end
		if message then return string.format("%s (%d)", message, status) end
		if prefix then return string.format("%s (%d)", prefix, status) end
		return string.format("request failed with status %d", status)
	end

	function M.errorText(res, err)
		return env.require("runtime/support").error(errorText(res, err))
	end

	-- The output ceiling a refusal names, or nil when it names nothing usable.
	--
	-- Every model has its own max_tokens limit and no endpoint publishes it: /models
	-- reports ids, not capabilities. The one place the number appears is the 400 that
	-- comes back when a request exceeds it, and the wording is different everywhere --
	-- "max_tokens: 200000 > 64000, which is the maximum allowed number of output
	-- tokens for claude-sonnet-4-5-20250929", "max_tokens is too large: 200000. This
	-- model supports at most 16384 completion tokens", "must be less than or equal to
	-- 8192". What they share is that the limit is the largest number in the sentence
	-- below what was sent, so that is what is taken.
	--
	-- The floor is a thousand and it is load-bearing: the status code is part of the
	-- text this is handed, and clamping a reply ceiling to 400 tokens because "(400)"
	-- appeared in the prefix would be worse than the original error. Nothing caps
	-- output below a thousand tokens.
	function M.ceilingFromMessage(message, current)
		current = tonumber(current) or 0
		if current <= 0 then return nil end
		-- Explicit bounds are safe even for very small local models; a status code
		-- cannot match this wording. Keep the conservative floor for the heuristic.
		local text = tostring(message or ""):lower():gsub("(%d),(%d%d%d)", "%1%2")
		for _, pattern in ipairs({ "less than or equal to%s*(%d+)", "must be%s*<=%s*(%d+)",
			"at most%s*(%d+)%s*completion tokens", "at most%s*(%d+)%s*output tokens" }) do
			local limit = tonumber(text:match(pattern))
			if limit and limit >= 1 and limit < current then return limit end
		end
		local best
		for digits in tostring(message or ""):gmatch("%d+") do
			local number = tonumber(digits)
			if number and number >= 1000 and number < current and (not best or number > best) then
				best = number
			end
		end
		if best then return best end
		-- Nothing quotable. Halving converges in a couple of attempts and cannot loop,
		-- because each attempt is a fresh request against a smaller number.
		local halved = math.floor(current / 2)
		return (halved >= 1000) and halved or nil
	end

	-- The ceiling to actually send: what the user asked for, lowered to whatever this
	-- record has already been told its model allows.
	--
	-- Kept per model rather than per record, because the limit belongs to the model.
	-- Pointing a record at a wider Claude has to stop clamping it to the narrower
	-- one's limit, and there would be nothing on screen to explain it if it did not:
	-- the slider would read 64k while every request asked for 32k.
	function M.cappedMaxTokens(record, wanted)
		wanted = tonumber(wanted) or 0
		-- What the model documents comes first, so a slider set above a model's
		-- ceiling costs nothing to discover. What a refusal actually taught this
		-- record still applies after it, because the gateway is the final word on
		-- what it will accept.
		local documented = traits.maxOutput(record.model, record)
		if documented and wanted > documented then wanted = documented end
		local cap = record.maxTokensCap
		if type(cap) ~= "table" or cap.model ~= record.model then return wanted end
		local scope = registry.compatibilityKey(record)
		if cap.scope == nil then cap.scope = scope end -- adopt older saved caps once
		if cap.scope ~= scope then return wanted end
		local limit = tonumber(cap.tokens) or 0
		if limit > 0 and wanted > limit then return limit end
		return wanted
	end

	-- A temporary request allowance is applied after raw parameter overrides.
	-- It is never a provider lesson: later requests may have room for a larger
	-- reply. Keep valid smaller overrides and both supported field spellings.
	function M.enforceOutputCeiling(record, body, ceiling)
		ceiling = tonumber(ceiling)
		if not ceiling or ceiling ~= ceiling or ceiling < 1 or ceiling == math.huge then return end
		ceiling = math.max(1, math.floor(M.cappedMaxTokens(record, ceiling)))
		local present = false
		for _, key in ipairs({ "max_tokens", "max_completion_tokens" }) do
			if body[key] ~= nil then
				local value = tonumber(body[key])
				if not value or value ~= value or value < 1 or value == math.huge then value = ceiling end
				body[key] = math.min(ceiling, math.floor(value))
				present = true
			end
		end
		if not present then body.max_tokens = ceiling end
	end

	-- The effort level to send, or nil for none. Both adapters ask this and differ
	-- only in how the answer is spelled on the wire.
	--
	-- Clamped to the model's own scale rather than passed through, because the scales
	-- differ by generation -- "xhigh" arrived after 4.6 -- and a level a model has
	-- never heard of is a refusal rather than a rounding.
	function M.effortFor(record, request)
		local wanted = request and request.effort
		if wanted == nil then wanted = config.get("agent.effort", "low") end
		wanted = tostring(wanted or "")
		if wanted == "" or wanted == "off" then return nil end
		-- nearestEffort passes the level through for a model the user has manually
		-- marked as a reasoner, and clamps it against the documented scale for one
		-- the table knows -- which is the same contract as before, plus the override.
		return traits.nearestEffort(record and record.model, wanted)
	end

	-- Stores a refusal's limit or a successful smaller reply after a transport wall.
	-- Both adapters call this; the record persists, so the lesson outlives a session.
	function M.rememberMaxTokens(record, tokens)
		tokens = tonumber(tokens)
		if not tokens or tokens ~= tokens or tokens <= 0 or tokens == math.huge then return end
		local previous = record.maxTokensCap
		local previousTokens = type(previous) == "table" and tonumber(previous.tokens)
		local scope = registry.compatibilityKey(record)
		if previousTokens and previous.model == record.model and (previous.scope == nil or previous.scope == scope) and previousTokens > 0 then
			tokens = math.min(tokens, previousTokens)
		end
		record.maxTokensCap = { model = record.model, tokens = tokens, scope = scope }
		if registry.get(record.id) == record then registry.save(record, { force = true }) end
	end
	function M.toolCeiling(record)
		if not record then return 128 end
		local documented = math.min(traits.maxTools(record.model) or 128, 128)
		local cap = record.toolsCap
		local scope = registry.compatibilityKey(record)
		if type(cap) == "table" and cap.model == record.model and (cap.scope == nil or cap.scope == scope) then
			local limit = tonumber(cap.limit)
			if limit and limit >= 1 and limit < math.huge then return math.min(math.floor(limit), documented or math.huge) end
		end
		return documented
	end

	function M.rememberToolCeiling(record, limit)
		limit = tonumber(limit)
		if not limit or limit ~= limit or limit <= 0 or limit == math.huge then return end
		limit = math.floor(limit)
		local previous = record.toolsCap
		local previousLimit = type(previous) == "table" and tonumber(previous.limit)
		local scope = registry.compatibilityKey(record)
		if previousLimit and previous.model == record.model and (previous.scope == nil or previous.scope == scope) and previousLimit > 0 then
			limit = math.min(limit, previousLimit)
		end
		record.toolsCap = { model = record.model, limit = limit, scope = scope }
		if registry.get(record.id) == record then registry.save(record, { force = true }) end
	end

	function M.toolCeilingFromMessage(message)
		local text = tostring(message or ""):lower():gsub("(%d),(%d%d%d)", "%1%2")
		if not (text:find("tool", 1, true) or text:find("function", 1, true) or text:find("items", 1, true)) then return nil end
		local patterns = {
			"tools.-array too long.-maximum length%s*(%d+)",
			"maximum number of items is%s*(%d+)",
			"maximum of%s*(%d+)%s*tools",
			"maximum of%s*(%d+)%s*functions",
			"at most%s*(%d+)%s*tools",
			"at most%s*(%d+)%s*functions",
			"tools.-maximum.-is%s*(%d+)",
			"tools.-at most%s*(%d+)",
			"tools.-limit.-is%s*(%d+)",
		}
		for _, pattern in ipairs(patterns) do
			local limit = tonumber(text:match(pattern))
			if limit and limit >= 1 and limit < 1000 then return limit end
		end
		return nil
	end

	function M.capTools(tools, limit, isOpencode)
		limit = tonumber(limit) or 128
		if limit ~= limit or limit == math.huge then limit = 128 end
		local body = { tools = tools }
		M.limitTools(body, math.max(1, math.floor(limit)), isOpencode)
		return body.tools
	end

	-- Read the window named by a context refusal, never the request size or the
	-- output budget beside it. A max_tokens refusal alone cannot teach a window.
	function M.isContextError(message)
		local text = tostring(message or ""):lower()
		local isContext = text:find("context length", 1, true)
			or text:find("context window", 1, true)
			or text:find("context_length_exceeded", 1, true)
			or text:find("prompt is too long", 1, true)
			or text:find("maximum context", 1, true)
			or text:find("context size", 1, true)
			or text:find("n_ctx", 1, true)
			or text:find("too many tokens", 1, true)
			or text:find("reduce the length of the messages", 1, true)
		return isContext ~= nil and isContext ~= false
	end

	function M.contextWindowFromMessage(message)
		if not M.isContextError(message) then return nil end
		local text = tostring(message or ""):lower()
		-- Some gateways format limits as 128,000 or 1,048,576.
		text = text:gsub("(%d),(%d%d%d)", "%1%2"):gsub("(%d),(%d%d%d)", "%1%2")
		local patterns = {
			"maximum context length is%s*(%d+)",
			"maximum context length of%s*(%d+)",
			"maximum context window is%s*(%d+)",
			"context length of%s*(%d+)",
			"context window of%s*(%d+)",
			"context length%s*[:=]%s*(%d+)",
			"context window%s*[:=]%s*(%d+)",
			"context size%s*[:=]?%s*(%d+)",
			"n_ctx%s*[:=]%s*(%d+)",
			">%s*(%d+)%s*maximum",
			"maximum of%s*(%d+)%s*tokens",
			"at most%s*(%d+)%s*tokens",
		}
		for _, pattern in ipairs(patterns) do
			local window = tonumber(text:match(pattern))
			if window and window >= 512 and window < math.huge then return window end
		end
		return nil
	end

	-- A refusal can only lower an existing claim. The shared model map feeds
	-- compaction, badges and configuration export, and persists across executions.
	function M.rememberContextWindow(record, window)
		window = tonumber(window)
		if not window or window ~= window or window < 512 or window == math.huge then return end
		local id = util.trim(tostring(record and record.model or "")):lower()
		if id == "" then return end
		window = math.floor(window)
		local contexts = util.deepCopy(config.get("agent.forceContext", {}) or {})
		local previous = tonumber(contexts[id])
		if previous and previous > 0 then window = math.min(window, previous) end
		if previous == window then return end
		contexts[id] = window
		config.set("agent.forceContext", contexts)
		log.info("provider", string.format("%s: learned context window %d for %s",
			tostring(record.label or id), window, tostring(record.model)))
	end

	function M.learnContextWindow(record, res)
		if not res then return nil end
		local window = M.contextWindowFromMessage(M.errorText(res, nil))
		if window then M.rememberContextWindow(record, window) end
		return window
	end

	-- Gateways reject different subsets of the payload. Rather than maintaining a
	-- per-vendor allowlist that goes stale, a 400 whose text names a field is
	-- repaired once and retried -- and the repair is remembered on the record so
	-- the next turn does not pay for it again.
	local REPAIRS = {
		{
			match = "max_completion_tokens",
			apply = function(body)
				if body.max_tokens then
					body.max_completion_tokens = body.max_tokens
					body.max_tokens = nil
					return "renamed max_tokens to max_completion_tokens"
				end
			end,
		},
		{
			-- Ordered after the rename on purpose: a gateway that wants the other field
			-- name says so in a message this would otherwise read as a size complaint.
			match = "max_tokens",
			apply = function(body, message)
				-- Only ever driven by a live refusal. Replayed from record.repairs there
				-- is no message, and halving on every request would be a silent bug.
				if not message then return nil end
				local current = body.max_tokens or body.max_completion_tokens
				if not current then return nil end
				local allowed = M.ceilingFromMessage(message, current)
				if not allowed or allowed >= current then return nil end
				if body.max_tokens then body.max_tokens = allowed end
				if body.max_completion_tokens then body.max_completion_tokens = allowed end
				return string.format("lowered max_tokens from %d to %d", current, allowed)
			end,
		},
		{
			match = "temperature",
			apply = function(body, message)
				if message and not env.require("provider/sampling").isRejection(message) then return nil end
				if body.temperature ~= nil then
					body.temperature = nil
					return "dropped temperature"
				end
			end,
		},
		{
			match = "parallel_tool_calls",
			apply = function(body)
				if body.parallel_tool_calls ~= nil then
					body.parallel_tool_calls = nil
					return "dropped parallel_tool_calls"
				end
			end,
		},
		{
			match = "stream_options",
			apply = function(body)
				if body.stream_options ~= nil then
					body.stream_options = nil
					return "dropped stream_options"
				end
			end,
		},
		{
			-- Not every gateway that relays to a reasoning model forwards the field
			-- that asks for a depth. Dropping it costs the setting, not the turn.
			match = "reasoning_effort",
			apply = function(body)
				if body.reasoning_effort ~= nil then
					body.reasoning_effort = nil
					return "dropped reasoning_effort"
				end
			end,
		},
		{
			match = "tool_choice",
			apply = function(body)
				if body.tool_choice ~= nil then
					body.tool_choice = nil
					return "dropped tool_choice"
				end
			end,
		},
		{
			-- Gateways relaying to reasoning models reject the classic system role and
			-- name the newer one in the message. Rewriting the first system message to
			-- `developer` is the documented mapping, and it is remembered on the record
			-- like every other repair so only the first turn pays for the lesson.
			match = "developer",
			apply = function(body)
				local renamed = false
				for _, message in ipairs(body.messages or {}) do
					if type(message) == "table" and message.role == "system" then
						message.role = "developer"
						renamed = true
					end
				end
				if renamed then return "rewrote system messages as developer" end
			end,
		},
		{
			-- Thinking mode on Anthropic gateways (e.g. AgentRouter/NewAPI routing to Claude):
			-- requires assistant turns to carry content blocks with type = "thinking".
			--
			-- Ephemeral (see EPHEMERAL_REPAIRS): a gateway like AgentRouter multiplexes
			-- several backends behind one endpoint, and a sibling backend rejects these
			-- blocks as an unknown variant. Remembering the conversion would poison every
			-- later turn that lands on the OpenAI-schema backend, so it is applied per
			-- refusal and never saved.
			--
			-- Only turns that actually captured reasoning are converted: a thinking block
			-- rebuilt from empty text has no signature and is rejected again, so a turn
			-- with nothing to replay is left as-is for the sibling backend to accept.
			match = "content[].thinking",
			apply = function(body)
				local fixed = 0
				for _, msg in ipairs(body.messages or {}) do
					if type(msg) == "table" and msg.role == "assistant" and type(msg.content) ~= "table" then
						local reasoning = msg.reasoning_content
						local text = type(msg.content) == "string" and msg.content or ""
						if type(reasoning) == "string" and util.trim(reasoning) ~= "" then
							local blocks = { { type = "thinking", thinking = reasoning } }
							if text ~= "" then
								blocks[#blocks + 1] = { type = "text", text = text }
							end
							msg.content = blocks
							msg.reasoning_content = nil
							fixed = fixed + 1
						end
					end
				end
				if fixed > 0 then
					return string.format("converted %d assistant message(s) to thinking content blocks", fixed), "content[].thinking"
				end
			end,
		},
		{
			-- The inverse of the conversion above. A sibling backend behind the same
			-- gateway uses an OpenAI-style deserializer with no `thinking` variant and
			-- rejects the blocks with "unknown variant `thinking`, expected one of
			-- `text`, `image_url`, `file`". Flatten assistant content back to a plain
			-- string and restore reasoning_content so the request the sibling backend
			-- can read goes out. Ephemeral for the same reason its inverse is: neither
			-- content shape is stable across the gateway's routing.
			match = "unknown variant `thinking`",
			apply = function(body)
				local fixed = 0
				for _, msg in ipairs(body.messages or {}) do
					if type(msg) == "table" and msg.role == "assistant" and type(msg.content) == "table" then
						local textParts, thinkParts = {}, {}
						for _, block in ipairs(msg.content) do
							if type(block) == "table" then
								if block.type == "thinking" then
									local think = block.thinking or block.text
									if type(think) == "string" and think ~= "" then
										thinkParts[#thinkParts + 1] = think
									end
								elseif type(block.text) == "string" then
									textParts[#textParts + 1] = block.text
								end
							end
						end
						msg.content = table.concat(textParts)
						if #thinkParts > 0 then
							msg.reasoning_content = table.concat(thinkParts, "\n")
						end
						fixed = fixed + 1
					end
				end
				if fixed > 0 then
					return string.format("flattened %d assistant message(s) back to plain content", fixed), "revert_thinking_blocks"
				end
			end,
		},
		{
			-- Reasoning models (DeepSeek-R1, QwQ, Step, etc.) require reasoning_content passed back
			-- on every assistant turn, even when empty. If a gateway rejects because reasoning_content
			-- is missing or required, ensure it is set. If a gateway rejects reasoning_content as
			-- an unknown/unsupported parameter, drop it.
			match = "reasoning_content",
			apply = function(body, message)
				local lowered = tostring(message or ""):lower()
				local isForbidden = lowered:find("unrecognized", 1, true)
					or lowered:find("not permitted", 1, true)
					or lowered:find("unknown", 1, true)
					or lowered:find("unexpected", 1, true)
					or lowered:find("extra", 1, true)

				if isForbidden then
					local dropped = 0
					for _, msg in ipairs(body.messages or {}) do
						if type(msg) == "table" and msg.role == "assistant" and msg.reasoning_content ~= nil then
							msg.reasoning_content = nil
							dropped = dropped + 1
						end
					end
					if dropped > 0 then
						return "dropped reasoning_content", "drop_reasoning_content"
					end
					return nil
				end

				-- Required in thinking mode: ensure reasoning_content is present on all assistant messages
				local fixed = 0
				for _, msg in ipairs(body.messages or {}) do
					if type(msg) == "table" and msg.role == "assistant" then
						if msg.reasoning_content == nil then
							msg.reasoning_content = ""
							fixed = fixed + 1
						end
					end
				end
				if fixed > 0 then
					return string.format("ensured reasoning_content on %d assistant message(s)", fixed), "require_reasoning_content"
				end
			end,
		},
		{
			match = "require_reasoning_content",
			apply = function(body)
				for _, msg in ipairs(body.messages or {}) do
					if type(msg) == "table" and msg.role == "assistant" and msg.reasoning_content == nil then
						msg.reasoning_content = ""
					end
				end
			end,
		},
		{
			match = "drop_reasoning_content",
			apply = function(body)
				for _, msg in ipairs(body.messages or {}) do
					if type(msg) == "table" and msg.role == "assistant" and msg.reasoning_content ~= nil then
						msg.reasoning_content = nil
					end
				end
			end,
		},
		{
			match = "cap_tools",
			apply = function(body, message)
				local limit = (message and M.toolCeilingFromMessage(message)) or 128
				local before = body.tools and #body.tools or 0
				if before <= limit then return nil end
				M.limitTools(body, limit, false)
				return string.format("capped tools from %d to %d", before, #body.tools), "cap_tools"
			end,
		},
	}

	-- Repairs that change the shape of message content rather than a top-level
	-- parameter. AgentRouter and other NewAPI gateways multiplex several backends
	-- behind one endpoint, and the two backends disagree about content shape: one
	-- demands thinking blocks, the other rejects them. A remembered content repair
	-- would replay onto whichever backend the next turn happens to hit and fail
	-- there, so these are applied per refusal and never saved to the record.
	local EPHEMERAL_REPAIRS = {
		["content[].thinking"] = true,
		["revert_thinking_blocks"] = true,
	}

	local function repair(body, message)
		-- A context error often mentions max_tokens too. It needs shorter history,
		-- not output-ceiling repairs that would learn the wrong limit.
		if M.isContextError(message) then return nil end
		-- Gateways spell fields the way their host language does: HCNSEC's validator
		-- answers "field MaxTokens invalid" where the wire says `max_tokens`, and a
		-- plain lowercase compare reads that as "maxtokens" -- no underscore -- so the
		-- repair below never fires and the ceiling is never lowered or learned. The
		-- copy matched against puts those camel humps back into snake case first;
		-- the repairs still parse their numbers from the original wording.
		local camel = tostring(message or ""):gsub("(%l)(%u)", "%1_%2")
		local lowered = camel:lower()
		local toolCeil = M.toolCeilingFromMessage(message)
		if toolCeil and body.tools and #body.tools > toolCeil then
			local before = #body.tools
			M.limitTools(body, toolCeil, false)
			return string.format("capped tools from %d to %d", before, #body.tools), "cap_tools"
		end
		if body.max_completion_tokens and not body.max_tokens and lowered:find("max_completion_tokens", 1, true) then
			local note = REPAIRS[2].apply(body, message)
			if note then return note, "max_tokens" end
		end
		for _, entry in ipairs(REPAIRS) do
			if lowered:find(entry.match:lower(), 1, true) then
				local note, keyOverride = entry.apply(body, message)
				if note then return note, keyOverride or entry.match end
			end
		end
		return nil
	end

	-- Exposed for tests: repair mutates the body in place and returns the note and
	-- key the dispatch loop would act on, without needing a live transport.
	M.repairForTest = repair

	local function applyRemembered(record, body)
		local scope = registry.compatibilityKey(record)
		if record.repairScope ~= nil and record.repairScope ~= scope then record.repairs = {} end
		record.repairScope = scope
		for _, key in ipairs(record.repairs or {}) do
			for _, entry in ipairs(REPAIRS) do
				if entry.match == key and (key ~= "temperature" or env.require("provider/sampling").state(record).override ~= "send") then entry.apply(body) end
			end
		end
	end

	local function remember(record, key)
		local scope = registry.compatibilityKey(record)
		if record.repairScope ~= nil and record.repairScope ~= scope then record.repairs = {} end
		record.repairScope = scope
		record.repairs = record.repairs or {}
		for _, existing in ipairs(record.repairs) do
			if existing == key then return end
		end
		record.repairs[#record.repairs + 1] = key
		if registry.get(record.id) == record then registry.save(record, { force = true }) end
	end

	-- Performs one completion against one provider. Returns result, nil on success
	-- or nil, message on failure. Retries inside net/http cover transport and
	-- 5xx/429; the provider chain above this handles a dead endpoint.
	--
	-- A record with several keys gets one more layer: a 429 or quota refusal
	-- benches the key that carried it and re-fires on the next key immediately.
	-- No sleep, because the refusal arrived in milliseconds and the next key's
	-- quota is untouched -- waiting would only spend the wall clock the reply
	-- still has to fit inside.
	local function quotaRefusal(res)
		if not res then return false end
		if res.status == 429 then return true end
		if res.status == 402 or res.status == 403 then
			local body = tostring(res.body or ""):lower()
			if body:find("resource_exhausted", 1, true) then return true end
			if body:find("quota", 1, true) then return true end
			if body:find("rate limit", 1, true) then return true end
		end
		return false
	end

	local function rotationSuffix(index)
		return string.format(" (key %d)", index)
	end

	function M.complete(record, request)
		local owns = env.require("provider/sampling").owner(record)
		local problem = registry.protocolProblem(record)
		if problem then return nil, problem end
		request = util.copy(request or {})
		if request.onRetry then
			local callback = request.onRetry
			request.onRetry = function(info) if not pcall(callback, info) then log.warn("provider", "retry callback failed safely") end end
		end
		-- Choose a known native Responses route before building and limiting a
		-- second, unused Chat Completions payload for the same tool catalog.
		if responses.eligible(record) and (responses.remembered(record) or responses.wantsResponses(record)) then
			return responses.complete(record, request)
		end
		local wantStream = request.stream
		if wantStream == nil then wantStream = record.stream ~= false and config.get("agent.stream", true) end
		if env.require("net/transport").streamForced() or registry.isOpencode(record) then wantStream = true end

		local body = M.buildBody(record, util.merge(request, { stream = wantStream }))
		applyRemembered(record, body)
		local requestScope = registry.compatibilityKey(record)

		local url = registry.endpoint(record, "/chat/completions")
		local pool = registry.requestKeys(record)
		local currentKey = registry.nextKey(record)
		local accounting = env.require("runtime/request_accounting").new(record, request)
		local currentKeyIndex = 0

		local function rebuildHeaders()
			-- Rebuilding proxy/identity headers must not consume another pool slot.
			for index, key in ipairs(pool) do
				if key == currentKey then currentKeyIndex = index end
			end
			local accept = body.stream and "text/event-stream" or "application/json"
			if registry.isOpencode(record) then accept = headerMap.get(record.headers, "Accept") or "*/*" end
			return headerMap.merge(registry.authHeaders(record, currentKey), registry.opencodeHeaders(record, request),
				record.headers, { Accept = accept })
		end

		local headers = rebuildHeaders()

		local started = clock.ms()
		local relayUnlimited = env.require("net/transport").unlimited(request)
		local deadline = env.require("net/deadline").at(requestTimeout(request), request.deadlineMs, started, relayUnlimited)
		local recovery = proxy.new(record, { aborted = request.aborted, onRetry = request.onRetry, deadlineMs = deadline })
		local lastRequestMs = 0
		local attemptsAllowed = request.attempts or config.get("agent.retries", 3)
		local rotationsLeft = math.max(#pool - 1, 0)
		-- With a pool, a 429 belongs to the rotation above, not to the transport's
		-- backoff: sleeping on an exhausted key spends the wall clock the reply still
		-- needs, and the next key answers at once. Without a pool the flag is nil and
		-- the transport behaves exactly as it always has.
		local skip429 = (#pool > 1) and { [429] = true } or nil

		local function fire(payload)
			if not owns() or registry.compatibilityKey(record) ~= requestScope then return nil, "aborted" end
			if deadline and clock.ms() >= deadline then return nil, "deadline: request budget expired" end
			-- A socket is only used when the record names one and the host has
			-- WebSocket support; otherwise the SSE body arrives whole over HTTP.
			local imageRequest = env.require("runtime/images").hasReferences(request.messages)
			local web = env.require("net/transport").shouldRelay(imageRequest)
			if not web and not registry.proxyProvider(record) and payload.stream and util.trim(record.wsUrl) ~= "" and caps.ws then
				local ws = env.require("net/ws")
				local socketHeaders = http.headersFor({ url = url, headers = headers, body = payload,
					identity = registry.identityFor(record), identityRequired = registry.requiresClaude(record), timeout = requestTimeout(request) })
				local streamBody, wsErr = ws.stream({
					url = record.wsUrl,
					path = urls.requestTarget(url),
					headers = socketHeaders,
					body = payload,
					onDispatch = function() accounting.dispatch(currentKey, socketHeaders) end,
					aborted = request.aborted,
					onFrame = request.onFrame,
					-- The transport bounds this setting to 1..300 seconds.
					timeout = requestTimeout(request),
					deadlineMs = deadline,
				})
				if streamBody then
					return { ok = true, status = 200, body = streamBody, via = "websocket", ms = clock.since(started) }
				end
				if http.terminal(wsErr) then return nil, wsErr end
				log.warn("provider", "websocket stream failed, falling back to http", wsErr)
			end
			local requestStarted = clock.ms()
			-- Setup fallback and explicit refusals spend the original budget. A slow
			-- socket connection cannot silently grant another full HTTP timeout.
			local res, err = http.send({
				requiresAccess = true,
				onDispatch = function() accounting.dispatch(currentKey, headers) end,
				relay = web,
				relayUnlimited = relayUnlimited,
				sessionId = request.sessionId,
				url = url,
				method = "POST",
				headers = headers,
				body = util.encode(payload),
				identity = registry.identityFor(record),
				identityRequired = registry.requiresClaude(record),
				attempts = attemptsAllowed,
				skipStatus = skip429,
				aborted = request.aborted,
				onRetry = request.onRetry,
				tag = "chat:" .. record.id,
				onFrame = request.onFrame,
				-- The one deadline that matters for a reasoning model: nothing arrives
				-- until it finishes thinking, so this has to outlast the think.
				timeout = requestTimeout(request),
				deadlineMs = deadline,
			})
			lastRequestMs = clock.since(requestStarted)
			if request.aborted and request.aborted() then return nil, "aborted" end
			if recovery.recover(res, err) then
				requestScope = registry.compatibilityKey(record)
				url = registry.endpoint(record, "/chat/completions")
				headers = rebuildHeaders()
				return fire(payload)
			end
			return res, err
		end

		local function fireWithRotation(payload)
			local res, err = fire(payload)
			while res and not res.ok and quotaRefusal(res) and rotationsLeft > 0 do
				rotationsLeft = rotationsLeft - 1
				local benched = currentKey or pool[1]
				registry.cooldownKey(record, benched)
				currentKey = registry.nextKey(record)
				headers = rebuildHeaders()
				local label = "rate limited, rotating to key #" .. currentKeyIndex
				log.info("provider", record.label .. ": " .. label)
				if request.onRetry then
					request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = label, status = res.status })
				end
				res, err = fire(payload)
			end
			return res, err
		end

		local res, err = fireWithRotation(body)
		if not owns() or registry.compatibilityKey(record) ~= requestScope or (request.aborted and request.aborted()) then return nil, "aborted" end
		-- Some Zen models only speak the Responses protocol: /chat/completions
		-- answers ModelProtocolUnsupported for them. Switch lanes and retry there.
		-- Preserve the direct desktop workaround when the bridge is absent.
		-- Mobile free-tier refusals are terminal; the retired proxy is never tried.
		if res and not res.terminal and not http.terminal(err) and registry.compatibilityKey(record) == requestScope and responses.eligible(record)
			and (responses.isProtocolRefusal(res) or (not registry.isOpencodeGo(record) and responses.canRetryFreeTier(res))) then
			log.info("provider", record.label .. ": chat route refused, retrying on the Responses lane")
			if request.onRetry then
				request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = "model may need the Responses protocol", status = res.status })
			end
			if not owns() or registry.compatibilityKey(record) ~= requestScope or (request.aborted and request.aborted()) then return nil, "aborted" end
			local switched, switchErr, switchRes = responses.complete(record, request,
				{ deadlineMs = deadline, relayUnlimited = relayUnlimited, key = currentKey, rotationsLeft = rotationsLeft, owns = owns })
			if switched then
				remember(record, responses.key())
				return switched, nil, switchRes
			end
			-- The original refusal does not erase an unknown outcome or a failed
			-- stream on the fallback lane. Keep those terminal across providers.
			if http.terminal(switchErr) or (switchRes and switchRes.terminal) then return nil, switchErr, switchRes end
		end
		-- A gateway names a bad field in a 400, and a NewAPI gateway names a bad
		-- content variant in a 422. Both are repairable, and both can chain: a
		-- gateway that multiplexes backends can refuse the very shape a sibling
		-- backend just demanded, so a single repair is not enough -- the reversal
		-- has to get its own retry. Bounded so a gateway that flip-flops between
		-- two backends cannot spin here forever; when the budget runs out the body
		-- falls through to the normal failure path and the chain moves on.
		local repairsLeft = 4
		while res and not res.terminal and not http.terminal(err) and (res.status == 400 or res.status == 422) and repairsLeft > 0
			and owns() and registry.compatibilityKey(record) == requestScope and not (request.aborted and request.aborted()) do
			repairsLeft = repairsLeft - 1
			local message = M.errorText(res, nil)
			local note, key = repair(body, message)
			if not note then break end
			log.info("provider", record.label .. ": " .. note .. ", retrying")
			-- Do not teach a model/endpoint selected while this request was in flight.
			if registry.compatibilityKey(record) == requestScope then
				if key == "max_tokens" then
					-- A value, not a switch: replaying a halving repair would lower it on every turn.
					M.rememberMaxTokens(record, body.max_tokens or body.max_completion_tokens)
				elseif key == "cap_tools" then
					local limit = M.toolCeilingFromMessage(message) or 128
					M.rememberToolCeiling(record, limit)
					remember(record, key)
				elseif not EPHEMERAL_REPAIRS[key] then
					remember(record, key)
				end
			end
			if request.onRetry then
				request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = note, status = res.status })
			end
			res, err = fireWithRotation(body)
		end

		-- The executor's transport wall: no body, no headers, an executor raise for
		-- the error text, and no config value can lift that wall because the option
		-- was never honoured. Retry once with a smaller ask -- less thinking, half the
		-- reply ceiling -- so the model finishes inside the wall instead of dying at
		-- it. Only when an HTTP request produced nothing after 20-130 seconds,
		-- and only when the smaller ask is actually smaller: a
		-- deadline on an already-minimal body would re-send the same prompt to the
		-- same wall, and that is the one outcome this must not do.
		local recoveredTokens
		if not res and err and not http.terminal(err) and lastRequestMs >= 20000 and lastRequestMs <= 130000 then
			local lowered, note = smallerAsk(body)
			if lowered and util.encode(lowered) ~= util.encode(body) then
				log.info("provider", record.label .. ": hit the transport wall, retrying smaller (" .. note .. ")")
				if request.onRetry then
					request.onRetry({ attempt = 1, attempts = 2, wait = 0, reason = note, status = 0 })
				end
				res, err = fireWithRotation(lowered)
				if res and res.ok then recoveredTokens = lowered.max_tokens or lowered.max_completion_tokens end
			end
		end

		if not res or not res.ok then
			if registry.compatibilityKey(record) == requestScope then M.learnContextWindow(record, res) end
			local message = M.errorText(res, err)
			registry.markFail(record, message)
			return nil, message, res
		end

		local parsed
		if sse.looksStreamed(res.body) then
			parsed = sse.parse(res.body)
		else
			local decoded, decodeErr = util.decode(res.body)
			if type(decoded) ~= "table" then
				local message = "provider returned a body that is not JSON: " .. tostring(decodeErr)
				registry.markFail(record, message)
				return nil, message, res
			end
			if decoded.error then
				local message = M.errorText(res, nil)
				registry.markFail(record, message)
				return nil, message, res
			end
			parsed = sse.fromResponse(decoded)
		end

		accounting.attach(parsed)
		if parsed.streamError then
			registry.markFail(record, parsed.streamError)
			return nil, "stream error: " .. parsed.streamError, res
		end

		local hasText = util.trim(parsed.content) ~= ""
		local hasCalls = #(parsed.toolCalls or {}) > 0
		if not hasText and not hasCalls and util.trim(parsed.reasoning) == "" then
			-- An empty completion is not an error the model can act on, so it is
			-- reported as a failure and the chain may try elsewhere.
			local message = "the provider returned an empty completion"
			registry.markFail(record, message)
			return nil, message, res
		end

		-- A 200 with an error, malformed JSON or an empty completion did not recover.
		if recoveredTokens and registry.compatibilityKey(record) == requestScope then
			M.rememberMaxTokens(record, recoveredTokens)
			log.info("provider", record.label .. ": smaller request succeeded; remembered max_tokens " .. tostring(recoveredTokens))
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
