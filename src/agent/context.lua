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
	local SUMMARY_BYTES = 12288
	local SUMMARY_INPUT_BYTES = 48000
	-- A handover replaces the work it folds, so removed messages are also kept as
	-- bounded plain text. The agent can recover exact earlier wording with the
	-- context_archive tool after the summary has taken over the live context.
	local ARCHIVE_SEGMENT_BYTES = 64 * 1024
	local ARCHIVE_TOTAL_BYTES = 512 * 1024
	local ARCHIVE_MESSAGE_BYTES = 12 * 1024
	local ARCHIVE_CALL_BYTES = 2 * 1024
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
			archive = {},
			archiveSerial = 0,
			archiveTrimmed = 0,
			-- The tokens a request spends beyond the message estimate: the system
			-- prompt and tool schemas ctx.tokens() does not see. Learned from what the
			-- provider actually counted, so the budget check reflects the real prompt.
			overhead = 0,
			calibrated = false,
		}
		local calibration, promptEstimate, promptKey
		local estimates, estimateMap, estimateTotal, estimateRoles = {}, {}, 0, {}
		local function unchanged(entry, message)
			if not entry or entry.message ~= message or entry.mutable or entry.content ~= message.content
				or entry.reasoning ~= (message.reasoning_content or message.reasoning)
				or entry.images ~= #(message.images or {}) then return false end
			local calls = message.toolCalls or message.tool_calls or {}
			if #calls ~= #entry.calls then return false end
			for index, call in ipairs(calls) do
				local fn, saved = call["function"] or {}, entry.calls[index]
				if saved.name ~= fn.name or saved.arguments ~= fn.arguments then return false end
			end
			return true
		end
		local function estimate(message)
			local entry = { message = message, content = message.content, reasoning = message.reasoning_content or message.reasoning,
				images = #(message.images or {}), calls = {}, mutable = type(message.content) == "table" }
			for index, call in ipairs(message.toolCalls or message.tool_calls or {}) do
				local fn = call["function"] or {}
				entry.calls[index] = { name = fn.name, arguments = fn.arguments }
				entry.mutable = entry.mutable or type(fn.arguments) == "table"
			end
			entry.tokens = usage.estimateMessages({ message })
			return entry
		end
		-- Public message tables remain editable. One shallow metadata pass detects
		-- changed prose/call strings; unchanged history never repeats JSON argument
		-- encoding or the full estimator. Mutable graphs are estimated conservatively.
		local function refreshEstimates()
			local total, roles, rebuild = 0, {}, #estimates > #ctx.messages
			for index, message in ipairs(ctx.messages) do
				local previous = estimates[index]
				local entry = previous and previous.message == message and previous or estimateMap[message]
				if not unchanged(entry, message) then entry = estimate(message) end
				if previous and previous.message ~= message then rebuild = true end
				estimates[index], estimateMap[message] = entry, entry
				total = total + entry.tokens
				local role = message.role or "message"
				roles[role] = (roles[role] or 0) + 1
			end
			for index = #estimates, #ctx.messages + 1, -1 do estimates[index] = nil end
			if rebuild then
				estimateMap = {}
				for _, entry in ipairs(estimates) do estimateMap[entry.message] = entry end
			end
			estimateTotal, estimateRoles = total, roles
			return total
		end
		local function preparedEstimate(messages)
			local total = 0
			for _, message in ipairs(messages or {}) do
				local entry = estimateMap[message]
				total = total + (entry and unchanged(entry, message) and entry.tokens or usage.estimateMessages({ message }))
			end
			return total
		end
		local function messageText(message, contentLimit, callLimit)
			local role = tostring(message.role or "message")
			local label = role == "tool" and ("tool " .. tostring(message.name or "unknown")) or role
			local text = excerpt(message.content, contentLimit)
			if message.toolCalls then
				local calls = {}
				for _, call in ipairs(message.toolCalls) do
					local fn = call["function"] or {}
					local args = type(fn.arguments) == "table" and util.encode(fn.arguments) or tostring(fn.arguments or "{}")
					calls[#calls + 1] = tostring(fn.name or "tool") .. " " .. excerpt(args, callLimit)
				end
				if #calls > 0 then text = text .. "\n[called: " .. table.concat(calls, "; ") .. "]" end
			end
			-- The whole entry shares one cap so a message with many tool calls cannot
			-- make the summary input or an archive segment grow past its budget.
			return excerpt(label .. ": " .. text, contentLimit)
		end
		local function archiveBytes()
			local total = 0
			for _, segment in ipairs(ctx.archive) do total = total + #segment.text end
			return total
		end
		local function trimArchive()
			local total = archiveBytes()
			while #ctx.archive > 1 and total > ARCHIVE_TOTAL_BYTES do
				local removed = table.remove(ctx.archive, 1)
				if removed then
					total = total - #removed.text
					ctx.archiveTrimmed = ctx.archiveTrimmed + 1
				end
			end
		end
		local function archive(removed)
			if #removed == 0 then return end
			local entries, size, messages = {}, 0, 0
			local function flush()
				if #entries == 0 then return end
				ctx.archiveSerial = ctx.archiveSerial + 1
				ctx.archive[#ctx.archive + 1] = {
					id = "c" .. tostring(ctx.archiveSerial),
					at = clock.ms(),
					messages = messages,
					text = table.concat(entries, "\n\n"),
				}
				entries, size, messages = {}, 0, 0
			end
			for _, message in ipairs(removed) do
				local entry = messageText(message, ARCHIVE_MESSAGE_BYTES, ARCHIVE_CALL_BYTES)
				if size > 0 and size + #entry + 2 > ARCHIVE_SEGMENT_BYTES then flush() end
				entries[#entries + 1] = entry
				size, messages = size + #entry + 2, messages + 1
			end
			flush()
			trimArchive()
		end
		local function providerKey(record)
			if type(record) ~= "table" then return record end
			return tostring(record.id or "") .. "|" .. tostring(record.baseUrl or "") .. "|" .. tostring(record.model or "")
		end
		local function overheadFor(record, history)
			local key = providerKey(record)
			if key ~= nil and promptKey ~= nil and key ~= promptKey then return promptEstimate or 0, false end
			if ctx.calibrated and calibration then
				-- Tokenizer error in a large history is not fixed system overhead.
				-- Retire that correction proportionally when the history shrinks.
				local retained = math.min(1, (history or ctx.tokens()) / math.max(1, calibration.history))
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
				geminiParts = result.geminiParts and util.deepCopy(result.geminiParts),
				geminiScope = result.geminiScope,
				responsesItems = result.responsesItems and util.deepCopy(result.responsesItems),
				responsesScope = result.responsesScope,
				model = result.model,
				provider = result.provider,
				ms = result.ms,
				outputTokens = result.outputTokens,
				requestMs = result.requestMs,
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
			local total = refreshEstimates()
			if ctx.summary then total = total + usage.estimateText(ctx.summary) end
			return total
		end

		-- The whole-prompt token budget at which older turns get summarised. The
		-- manual "Context budget" setting is a hard ceiling; when the model's own
		-- context window is known, compaction starts at a fraction of it, so a small-
		-- window model compacts on its own without the user tuning a number for it.
		function ctx.limitFor(model, record)
			local configured = tonumber(config.get("agent.contextTokens", 24000)) or 24000
			if configured ~= configured or configured == math.huge then configured = 24000 end
			configured = math.max(configured, 1000)
			local window = model and env.require("provider/traits").contextWindow(model, record) or nil
			if not window then return configured end
			local fraction = tonumber(config.get("agent.contextFraction", 0.8)) or 0.8
			if fraction ~= fraction then fraction = 0.8 end
			fraction = math.max(0.3, math.min(fraction, 0.95))
			return math.max(1000, math.min(configured, math.floor(window * fraction)))
		end

		-- What the next request is expected to actually cost the window: the message
		-- estimate plus the measured overhead of the system prompt and tool schemas.
		function ctx.pressure(record)
			local history = ctx.tokens()
			return history + overheadFor(record, history)
		end

		function ctx.observeRequest(messages, tools, record)
			local history = ctx.tokens()
			local toolTokens = tools and #tools > 0 and usage.estimateText(util.encode(tools)) or 0
			promptEstimate = math.max(0, preparedEstimate(messages) + toolTokens - history)
			promptKey = providerKey(record)
			ctx.calibrated = calibration ~= nil and calibration.key == promptKey
			ctx.overhead = ctx.calibrated and math.max(0, calibration.overhead + promptEstimate - calibration.estimate) or promptEstimate
			return { history = history, estimate = promptEstimate, key = promptKey }
		end

		function ctx.breakdown(record)
			local messages = refreshEstimates()
			local summary = ctx.summary and usage.estimateText(ctx.summary) or 0
			local system, calibrated = overheadFor(record, messages + summary)
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
			local tokens = ctx.tokens()
			local archived = 0
			for _, segment in ipairs(ctx.archive) do archived = archived + segment.messages end
			return {
				messages = #ctx.messages,
				tokens = tokens,
				pressure = tokens + overheadFor(nil, tokens),
				overhead = ctx.overhead or 0,
				turns = estimateRoles.user or 0,
				toolResults = estimateRoles.tool or 0,
				compactions = ctx.compactions,
				dropped = ctx.dropped,
				archived = archived,
				archiveSegments = #ctx.archive,
				archiveTrimmed = ctx.archiveTrimmed,
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
			local budget = opts.tokenLimit or ctx.limitFor(opts.model, opts.record)
			local force = opts.force == true
			local msgLimit = math.max(0, budget - overheadFor(opts.record))
			local before = ctx.tokens()
			if not force and before <= msgLimit then return nil, "already below the compaction point" end
			local original, originalSummary = ctx.messages, ctx.summary
			local count = #original
			local dropped, keptTokens = {}, estimateTotal
			local reserve = math.min(SUMMARY_BYTES / 4, math.max(64, math.floor(msgLimit * 0.2)))
			local target = math.max(0, math.floor(msgLimit * 0.75))
			local function needsSpace() return force or keptTokens + reserve > target end
			local function remove(first, last)
				for index = first, last do
					if not dropped[index] then
						dropped[index] = true
						keptTokens = keptTokens - estimateMap[original[index]].tokens
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
			local window = opts.model and env.require("provider/traits").contextWindow(opts.model, opts.record)
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
				local entry = messageText(message, perMessage, 800)
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
			-- Keep the folded work recoverable only after the replacement commits; a
			-- cancelled or non-reducing pass must leave both sides untouched.
			archive(removed)
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
			local out, dropped, filled = {}, 0, 0
			local owner, pending = nil, nil
			local function finishOwner()
				if not owner then return end
				for _, call in ipairs(owner.toolCalls) do
					if call.id ~= nil and pending[tostring(call.id)] then
						pending[tostring(call.id)] = nil
						out[#out + 1] = {
							role = "tool", tool_call_id = call.id,
							name = (call["function"] and call["function"].name) or call.name or "tool",
							content = "This call did not complete: the turn ended before a result was recorded.",
							at = owner.at,
						}
						filled = filled + 1
					end
				end
				owner, pending = nil, nil
			end
			-- One forward pass indexes the immediately preceding batch. Each result
			-- consumes its ID once, preventing duplicate receipts from poisoning the
			-- provider request without rescanning siblings or the whole call list.
			for _, message in ipairs(ctx.messages) do
				if message.role == "tool" then
					local key = message.tool_call_id ~= nil and tostring(message.tool_call_id) or nil
					if pending and key and pending[key] then
						pending[key] = nil
						out[#out + 1] = message
					else dropped = dropped + 1 end
				else
					finishOwner()
					out[#out + 1] = message
					if message.role == "assistant" and message.toolCalls and #message.toolCalls > 0 then
						owner, pending = message, {}
						for _, call in ipairs(message.toolCalls) do
							if call.id ~= nil then pending[tostring(call.id)] = true end
						end
					end
				end
			end
			finishOwner()

			if dropped > 0 or filled > 0 then
				ctx.messages = out
				log.warn("context", string.format(
					"repaired tool pairing: %s dropped, %s filled in",
					util.pluralise(dropped, "orphaned or duplicate result"),
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
				if #ctx.archive > 0 then
					local archived = 0
					for _, segment in ipairs(ctx.archive) do archived = archived + segment.messages end
					local range = #ctx.archive == 1 and ctx.archive[1].id
						or (ctx.archive[1].id .. " to " .. ctx.archive[#ctx.archive].id)
					out[#out + 1] = { role = "system", content = string.format(
						"Archived earlier detail: %s in %s (%s). Recover exact text with context_archive (list, search, read).",
						util.pluralise(archived, "message"), util.pluralise(#ctx.archive, "segment"), range) }
				end
			end
			for _, message in ipairs(ctx.messages) do out[#out + 1] = message end
			return out
		end

		function ctx.clear()
			ctx.messages = {}
			estimates, estimateMap, estimateTotal, estimateRoles = {}, {}, 0, {}
			ctx.summary = nil
			ctx.compactions = 0
			ctx.dropped = 0
			ctx.archive = {}
			ctx.archiveSerial = 0
			ctx.archiveTrimmed = 0
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
					-- Gemini validates signed model parts on tool-result replay. Keep
					-- their original boundaries and route scope across client reloads.
					geminiParts = message.geminiParts,
					geminiScope = message.geminiScope,
					-- Responses reasoning items are opaque signed state, kept in order
					-- with their matching tool calls and opaque route-scope fingerprint.
					responsesItems = message.responsesItems,
					responsesScope = message.responsesScope,
					at = message.at,
					model = message.model,
					outputTokens = message.outputTokens,
					requestMs = message.requestMs,
				}
			end
			out.archive = {}
			for _, segment in ipairs(ctx.archive) do
				out.archive[#out.archive + 1] = {
					id = segment.id, at = segment.at, messages = segment.messages, text = segment.text,
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
			for _, segment in ipairs(type(data.archive) == "table" and data.archive or {}) do
				if type(segment) == "table" and type(segment.id) == "string" and type(segment.text) == "string" then
					local number = tonumber(segment.id:match("^c(%d+)$"))
					if number and #segment.text > 0 and #segment.text <= ARCHIVE_SEGMENT_BYTES then
						ctx.archive[#ctx.archive + 1] = { id = "c" .. tostring(number), at = tonumber(segment.at) or 0,
							messages = math.max(0, math.floor(tonumber(segment.messages) or 0)), text = segment.text }
						ctx.archiveSerial = math.max(ctx.archiveSerial, number)
					end
				end
			end
			trimArchive()
			return true
		end

		return ctx
	end

	return M
end
