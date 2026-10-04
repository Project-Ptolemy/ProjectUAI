-- Conversation store.
--
-- The system prompt is not kept here. It is rebuilt for every request, because it
-- carries the environment, the task list and the memory block, all of which move
-- while a session runs -- a prompt pinned at index one goes stale within minutes.
--
-- Removal preserves complete assistant/tool exchanges. Whole older user turns
-- go first; a long active task can fold its older exchanges while retaining the
-- user's request. A result separated from its call is a provider error.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local usage = env.require("agent/usage")

	local M = {}
	local SUMMARY_BYTES = 4096
	local SUMMARY_INPUT_BYTES = 48000
	-- Keep both ends, including verdicts/cursors and late user corrections. The
	-- public truncate helper includes its own notice outside the requested size.
	local function excerpt(value, limit)
		local text = util.sanitise(tostring(value or ""))
		if limit < 4 then return "" end
		if #text <= limit then return text end
		local out = util.truncate(text, math.max(1, limit - 80))
		return #out <= limit and out or util.ellipsis(out, limit)
	end
	-- Compact references only; querying context never initializes a workspace or hook.
	function M.workspaceSummary()
		local loaded = env.loadedModules or {}
		local store, explorer, capture = loaded["runtime/code_store"], loaded["runtime/explorer"], loaded["runtime/remote_capture"]
		local out = {}
		if store and store.initialized then
			local doc = store.active()
			out.destination, out.documentId, out.sourceRevision = store.workspace.destination, doc and doc.id, doc and doc.revision
			out.sourceId = store.workspace.sourceId
		end
		if explorer and #explorer.selectedIds > 0 then out.selection = util.slice(explorer.selectedIds, 1, 5); out.selectionCount, out.selectionRevision = #explorer.selectedIds, explorer.selectionRevision end
		if capture and capture.status ~= "idle" then
			local records = loaded["runtime/remote_store"]
			out.captureId, out.captureStatus, out.captureRevision, out.ruleCount = capture.sessionId, capture.status, capture.revision, #capture.rules
			out.recordId = capture.selectedId
			if capture.view.record and capture.view.record.id == capture.selectedId then out.recordRevision = capture.view.record.revision end
			if records then local state = records.state(); out.retained, out.evicted = state.retained, state.counters.evicted end
		end
		return next(out) and util.encode(out) or nil
	end

	function M.new()
		local ctx = {
			messages = {},
			summary = nil,
			compactions = 0,
			dropped = 0,
			-- The tokens a request spends beyond the message estimate: the system
			-- prompt and tool schemas ctx.tokens() does not see. Learned from what the
			-- provider actually counted, so the budget check reflects the real prompt.
			overhead = 0,
			calibrated = false,
		}
		local calibration, promptEstimate, promptKey
		local function providerKey(record)
			if type(record) ~= "table" then return record end
			return tostring(record.id or "") .. "|" .. tostring(record.baseUrl or "") .. "|" .. tostring(record.model or "")
		end
		local function overheadFor(record)
			local key = providerKey(record)
			if key ~= nil and promptKey ~= nil and key ~= promptKey then return promptEstimate or 0, false end
			if ctx.calibrated and calibration then
				-- Tokenizer error in a large history is not fixed system overhead.
				-- Retire that correction proportionally when the history shrinks.
				local retained = math.min(1, ctx.tokens() / math.max(1, calibration.history))
				ctx.overhead = math.max(0, (promptEstimate or 0) + (calibration.overhead - calibration.estimate) * retained)
			end
			return math.max(ctx.overhead or 0, 0), ctx.calibrated
		end

		function ctx.push(message)
			message.at = message.at or clock.ms()
			ctx.messages[#ctx.messages + 1] = message
			return message
		end

		function ctx.pushUser(text, images)
			return ctx.push({ content = tostring(text), role = "user", images = images and #images > 0 and util.deepCopy(images) or nil })
		end

		-- Reasoning text is kept locally for the transcript and replayed on
		-- subsequent turns for models in thinking mode (DeepSeek-R1, Claude thinking,
		-- QwQ, etc.) which require stateful chain-of-thought context.
		function ctx.pushAssistant(result)
			return ctx.push({
				role = "assistant",
				content = result.content or "",
				toolCalls = (result.toolCalls and #result.toolCalls > 0) and result.toolCalls or nil,
				reasoning = (result.reasoning ~= "" ) and result.reasoning or nil,
				-- The provider's own content blocks, when it has them. Only the
				-- Anthropic adapter sets this, and only it reads them back: a thinking
				-- block carries a signature that has to return unchanged, and there is
				-- no way to rebuild that from the text. Deliberately not persisted --
				-- see ctx.serialise -- so a reloaded conversation falls back to the
				-- reconstructed form, which the API accepts.
				raw = result.raw,
				model = result.model,
				provider = result.provider,
				ms = result.ms,
			})
		end

		function ctx.pushToolResult(callId, name, text)
			return ctx.push({
				role = "tool",
				tool_call_id = callId,
				name = name,
				content = tostring(text),
			})
		end

		function ctx.last(role)
			for index = #ctx.messages, 1, -1 do
				if not role or ctx.messages[index].role == role then return ctx.messages[index], index end
			end
			return nil
		end

		-- Internal coordination reminders do not start a new user task. Otherwise
		-- repeated subagent updates can evict the real request they are continuing.
		local function blockStarts()
			local starts = {}
			for index, message in ipairs(ctx.messages) do
				if message.role == "user" and not message.internal then starts[#starts + 1] = index end
			end
			return starts
		end

		function ctx.tokens()
			local total = usage.estimateMessages(ctx.messages)
			if ctx.summary then total = total + usage.estimateText(ctx.summary) end
			return total
		end

		-- The whole-prompt token budget at which older turns get summarised. The
		-- manual "Context budget" setting is a hard ceiling; when the model's own
		-- context window is known, compaction starts at a fraction of it, so a small-
		-- window model compacts on its own without the user tuning a number for it.
		function ctx.limitFor(model)
			local configured = tonumber(config.get("agent.contextTokens", 24000)) or 24000
			if configured ~= configured or configured == math.huge then configured = 24000 end
			configured = math.max(configured, 1000)
			local window = model and env.require("provider/traits").contextWindow(model) or nil
			if not window then return configured end
			local fraction = tonumber(config.get("agent.contextFraction", 0.8)) or 0.8
			if fraction ~= fraction then fraction = 0.8 end
			fraction = math.max(0.3, math.min(fraction, 0.95))
			return math.max(1000, math.min(configured, math.floor(window * fraction)))
		end

		-- What the next request is expected to actually cost the window: the message
		-- estimate plus the measured overhead of the system prompt and tool schemas.
		function ctx.pressure(record)
			return ctx.tokens() + overheadFor(record)
		end

		function ctx.observeRequest(messages, tools, record)
			local history = ctx.tokens()
			local toolTokens = tools and #tools > 0 and usage.estimateText(util.encode(tools)) or 0
			promptEstimate = math.max(0, usage.estimateMessages(messages) + toolTokens - history)
			promptKey = providerKey(record)
			ctx.calibrated = calibration ~= nil and calibration.key == promptKey
			ctx.overhead = ctx.calibrated and math.max(0, calibration.overhead + promptEstimate - calibration.estimate) or promptEstimate
			return { history = history, estimate = promptEstimate, key = promptKey }
		end

		function ctx.breakdown(record)
			local system, calibrated = overheadFor(record)
			local messages = usage.estimateMessages(ctx.messages)
			local summary = ctx.summary and usage.estimateText(ctx.summary) or 0
			return { system = system, messages = messages, summary = summary, used = system + messages + summary,
				calibrated = calibrated, estimatedPrompt = promptEstimate ~= nil }
		end

		-- Fold the provider's reported prompt-token count for the request just sent
		-- into the overhead estimate. Called before the reply is stored, so
		-- ctx.tokens() still reflects exactly what was on the wire.
		function ctx.calibrate(promptTokens, request)
			local real = tonumber(promptTokens)
			if not real or real <= 0 or real ~= real or real == math.huge then return end
			request = request or { history = ctx.tokens(), estimate = promptEstimate or 0, key = promptKey }
			calibration = { key = request.key, estimate = request.estimate, history = request.history, overhead = math.max(0, real - request.history) }
			promptKey, promptEstimate = request.key, request.estimate
			ctx.overhead = calibration.overhead
			ctx.calibrated = true
		end

		function ctx.stats()
			local counts = { user = 0, assistant = 0, tool = 0 }
			for _, message in ipairs(ctx.messages) do
				counts[message.role] = (counts[message.role] or 0) + 1
			end
			return {
				messages = #ctx.messages,
				tokens = ctx.tokens(),
				pressure = ctx.pressure(),
				overhead = ctx.overhead or 0,
				turns = counts.user,
				toolResults = counts.tool,
				compactions = ctx.compactions,
				dropped = ctx.dropped,
			}
		end

		-- Removes whole blocks from the front until the estimate fits, always
		-- keeping the most recent `keep` blocks. Returns the removed messages so a
		-- caller can summarise them.
		function ctx.trim(tokenLimit, keepBlocks, force)
			local limit = tokenLimit or config.get("agent.contextTokens", 24000)
			local keep = math.max(keepBlocks or 2, 1)
			local removed = {}

			while force or ctx.tokens() > limit do
				local starts = blockStarts()
				if #starts <= keep then break end
				local cutTo = starts[2] and (starts[2] - 1) or 0
				if cutTo <= 0 then break end
				local kept = {}
				for index, message in ipairs(ctx.messages) do
					if index <= cutTo then
						removed[#removed + 1] = message
					else
						kept[#kept + 1] = message
					end
				end
				ctx.messages = kept
			end

			-- A single block can exceed the budget on its own -- one enormous tool
			-- result will do it. Shrink the oldest tool results in place rather than
			-- dropping the block and losing the user's actual question. A forced pass
			-- (Compact now) skips this: it is folding history, not rescuing a request,
			-- and must not gut the recent turns it deliberately keeps.
			if not force and ctx.tokens() > limit then
				for _, message in ipairs(ctx.messages) do
					if message.role == "tool" and #tostring(message.content) > 400 then
						message.content = util.truncate(message.content, 400, "trimmed to fit the context budget")
						if ctx.tokens() <= limit then break end
					end
				end
			end

			ctx.dropped = ctx.dropped + #removed
			if #removed > 0 then
				log.info("context", util.pluralise(#removed, "message") .. " trimmed to fit the budget")
			end
			return removed
		end

		-- Plan a replacement before yielding to the summariser. Keep recent user
		-- requests and complete assistant/tool exchanges, including the latest two
		-- exchanges of a long single-user tool loop. No live tool body is silently
		-- cut down in place, and cancellation cannot leave half-compacted history.
		function ctx.compact(summarise, opts)
			opts = opts or {}
			local budget = opts.tokenLimit or ctx.limitFor(opts.model)
			local force = opts.force == true
			local msgLimit = math.max(0, budget - overheadFor(opts.record))
			local before = ctx.tokens()
			if not force and before <= msgLimit then return nil, "already below the compaction point" end
			local original, originalSummary = ctx.messages, ctx.summary
			local count = #original
			local dropped, keptTokens = {}, usage.estimateMessages(original)
			local reserve = math.min(SUMMARY_BYTES / 4, math.max(64, math.floor(msgLimit * 0.2)))
			local target = math.max(0, math.floor(msgLimit * 0.75))
			local function needsSpace() return force or keptTokens + reserve > target end
			local function remove(first, last)
				for index = first, last do
					if not dropped[index] then
						dropped[index] = true
						keptTokens = keptTokens - usage.estimateMessages({ original[index] })
					end
				end
			end
			local starts = blockStarts()
			local keep = math.max(1, opts.keepBlocks or 2)
			for block = 1, #starts - keep do
				if not needsSpace() then break end
				remove(block == 1 and 1 or starts[block], starts[block + 1] - 1)
			end
			-- Whole user turns alone cannot compact "inspect this game" followed by
			-- dozens of tool steps. Fold old exchanges without removing its request.
			for block, first in ipairs(starts) do
				if not dropped[first] and needsSpace() then
					local last = (starts[block + 1] or (count + 1)) - 1
					local exchanges = {}
					for index = first + 1, last do
						if original[index].role == "assistant" then exchanges[#exchanges + 1] = index end
					end
					for step = 1, #exchanges - 2 do
						if not needsSpace() then break end
						remove(exchanges[step], exchanges[step + 1] - 1)
					end
				end
			end
			local removed, kept = {}, {}
			for index, message in ipairs(original) do
				local destination = dropped[index] and removed or kept
				destination[#destination + 1] = message
			end
			if #removed == 0 then return nil, "no older complete exchanges to fold" end
			-- A replacement must make a real saving even if the provider ignores its
			-- output ceiling. Reserve space for it before selecting history to fold.
			local summaryBytes = math.min(SUMMARY_BYTES, reserve * 4, math.floor((before - keptTokens) * 4 * 0.75))
			if summaryBytes < 64 then return nil, "too little older context to compact usefully" end
			local inputLimit = SUMMARY_INPUT_BYTES
			local window = opts.model and env.require("provider/traits").contextWindow(opts.model)
			if window then inputLimit = math.min(inputLimit, math.max(1000, (window - 1536) * 3)) end
			local transcript, entries, size = {}, {}, 0
			local previousSummary = ctx.summary and util.trim(ctx.summary) or ""
			if previousSummary ~= "" then
				transcript[#transcript + 1] = "Summary so far:\n" .. excerpt(previousSummary, math.min(SUMMARY_BYTES, math.floor(inputLimit / 3)))
				transcript[#transcript + 1] = "\nNewer messages to fold into that summary:"
			end
			for index = #kept, 1, -1 do
				if kept[index].role == "user" and not kept[index].internal then
					transcript[#transcript + 1] = "Active request (retained separately; use as context):\n"
						.. excerpt(kept[index].content, math.min(1600, math.floor(inputLimit / 4)))
					break
				end
			end
			size = #table.concat(transcript, "\n")
			local perMessage = math.max(120, math.min(2400, math.floor((inputLimit - size) / #removed) - 2))
			for _, message in ipairs(removed) do
				local label = message.role == "tool" and ("tool " .. tostring(message.name or "unknown")) or message.role
				local text = tostring(message.content or "")
				if message.toolCalls then
					local calls = {}
					for _, call in ipairs(message.toolCalls) do
						local fn = call["function"] or {}
						local args = type(fn.arguments) == "table" and util.encode(fn.arguments) or tostring(fn.arguments or "{}")
						calls[#calls + 1] = tostring(fn.name or "tool") .. " " .. excerpt(args, 800)
					end
					text = text .. "\n[called: " .. table.concat(calls, "; ") .. "]"
				end
				local entry = label .. ": " .. excerpt(text, perMessage)
				transcript[#transcript + 1], entries[#entries + 1] = entry, entry
			end
			local source = excerpt(table.concat(transcript, "\n"), inputLimit)
			local ok, note = false, nil
			if type(summarise) == "function" then ok, note = pcall(summarise, source, summaryBytes) end
			if opts.aborted and opts.aborted() then return nil, "compaction cancelled" end
			if ctx.messages ~= original or #ctx.messages ~= count or ctx.summary ~= originalSummary then
				return nil, "conversation changed during compaction"
			end
			note = ok and type(note) == "string" and util.trim(util.sanitise(note)) or nil
			if not note or note == "" or #note > summaryBytes then
				if opts.requireSummary then return nil, "summary unavailable or too large; conversation preserved" end
				local notice = string.format("[%d messages dropped; summary unavailable. Excerpts:]\n", #removed)
				local available = summaryBytes - #notice
				local prior = previousSummary:gsub("^%[%d+ messages dropped; summary unavailable%. Excerpts:%]%s*", "")
				prior = excerpt(prior, math.floor(available * 0.6))
				if prior ~= "" then prior = prior .. "\n" end
				note = notice .. prior .. excerpt(table.concat(entries, "\n"), available - #prior)
			end
			if keptTokens + usage.estimateText(note) >= before then return nil, "summary would not reduce context" end
			ctx.messages, ctx.summary = kept, note
			ctx.dropped = ctx.dropped + #removed
			ctx.compactions = ctx.compactions + 1
			log.info("context", util.pluralise(#removed, "message") .. " compacted")
			return ctx.summary
		end

		-- Tool pairing, repaired in place.
		--
		-- Every provider rejects, hard, a tool result whose call is not in the message
		-- immediately before it. Anthropic words it "unexpected tool_use_id found in
		-- tool_result blocks"; OpenAI says a `tool` message must answer a preceding
		-- `tool_calls`. Nothing here checked, and the consequence is not one failed turn:
		-- a 400 is not retried, three of them bench the provider, the chain then walks the
		-- same broken history to the next provider, and `ctx.serialise` keeps both halves
		-- of the pairing -- so the conversation stays poisoned across a restart.
		--
		-- Compaction retains complete exchanges. Broken pairs can still come from a turn
		-- that dies between dispatching tools and recording their outcomes (leaving a call
		-- with no result), and a gateway that translates between the two wire shapes and
		-- drops an assistant turn whose content is the empty string -- which is exactly
		-- what this client sends for a tool-only turn (leaving a result with no call).
		--
		-- Both directions are repaired, differently. An orphaned result is dropped: there
		-- is nothing it can be attached to. An unanswered call is *answered*, because
		-- dropping it instead would discard what the model actually did.
		function ctx.repair()
			local kept, dropped = {}, 0
			for _, message in ipairs(ctx.messages) do
				if message.role == "tool" then
					-- The nearest assistant turn behind this one, looking past the sibling
					-- results that arrived with it.
					local owner = nil
					for back = #kept, 1, -1 do
						local candidate = kept[back]
						if candidate.role == "assistant" then
							owner = candidate
							break
						elseif candidate.role ~= "tool" then
							break
						end
					end
					local matched = false
					for _, call in ipairs((owner and owner.toolCalls) or {}) do
						if call.id ~= nil and tostring(call.id) == tostring(message.tool_call_id) then
							matched = true
						end
					end
					if matched then
						kept[#kept + 1] = message
					else
						dropped = dropped + 1
					end
				else
					kept[#kept + 1] = message
				end
			end

			local out, index, filled = {}, 1, 0
			while index <= #kept do
				local message = kept[index]
				out[#out + 1] = message
				index = index + 1
				if message.role == "assistant" and message.toolCalls and #message.toolCalls > 0 then
					local answered = {}
					while index <= #kept and kept[index].role == "tool" do
						answered[tostring(kept[index].tool_call_id)] = true
						out[#out + 1] = kept[index]
						index = index + 1
					end
					for _, call in ipairs(message.toolCalls) do
						if call.id ~= nil and not answered[tostring(call.id)] then
							out[#out + 1] = {
								role = "tool",
								tool_call_id = call.id,
								name = (call["function"] and call["function"].name) or call.name or "tool",
								content = "This call did not complete: the turn ended before a result "
									.. "was recorded.",
								at = message.at,
							}
							filled = filled + 1
						end
					end
				end
			end

			if dropped > 0 or filled > 0 then
				ctx.messages = out
				log.warn("context", string.format(
					"repaired tool pairing: %s dropped, %s filled in",
					util.pluralise(dropped, "orphaned result"),
					util.pluralise(filled, "unanswered call")))
			end
			return dropped, filled
		end

		-- Wire form. The summary rides as a second system message so it cannot be
		-- confused with the live instructions and is trivially droppable.
		function ctx.wire(systemText)
			-- Repaired here rather than at each adapter: this is the single funnel both of
			-- them are fed from, and doing it to the store rather than to a copy means one
			-- broken turn is fixed once instead of warned about on every request.
			ctx.repair()
			local out = {}
			if systemText and util.trim(systemText) ~= "" then
				out[#out + 1] = { role = "system", content = systemText }
			end
			if ctx.summary then
				out[#out + 1] = { role = "system", content = "Earlier in this conversation:\n" .. ctx.summary }
			end
			for _, message in ipairs(ctx.messages) do out[#out + 1] = message end
			return out
		end

		function ctx.clear()
			ctx.messages = {}
			ctx.summary = nil
			ctx.compactions = 0
			ctx.dropped = 0
			ctx.overhead = 0
			ctx.calibrated = false
			calibration, promptEstimate, promptKey = nil, nil, nil
		end

		-- Persistence keeps the fields a reload needs and drops the derived ones.
		function ctx.serialise()
			local out = { summary = ctx.summary, messages = {} }
			for _, message in ipairs(ctx.messages) do
				out.messages[#out.messages + 1] = {
					role = message.role,
					content = message.content,
					images = message.images,
					toolCalls = message.toolCalls,
					tool_call_id = message.tool_call_id,
					name = message.name,
					internal = message.internal,
					reasoning = message.reasoning,
					at = message.at,
				}
			end
			return out
		end

		function ctx.restore(data)
			if type(data) ~= "table" then return false end
			ctx.clear()
			ctx.summary = data.summary
			for _, message in ipairs(data.messages or {}) do
				if type(message) == "table" and message.role then ctx.push(message) end
			end
			return true
		end

		return ctx
	end

	return M
end
