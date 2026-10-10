-- Subagent dispatch.
--
-- A subagent is a full session with a smaller tool set, its own context and no
-- interface. It exists to keep long or repetitive work out of the main
-- conversation: the parent pays for one paragraph of report instead of forty tool
-- results, and a search that goes nowhere costs the main context nothing.
--
-- Depth is capped because a subagent that can spawn subagents indefinitely is a
-- fork bomb with a token bill.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local signal = env.require("runtime/signal")
	local codeText = env.require("runtime/code_text")
	local prompt = env.require("agent/prompt")
	local session = env.require("agent/session")

	local M = {}
	local alive = true
	M.backgroundCount = 0

	-- Groups a subagent may be given. Anything that changes the world is absent
	-- from the read-only preset, which is the default: the point of a subagent is
	-- usually to go and find out, and a delegated write is hard for the user to
	-- attribute afterwards.
	M.PRESETS = {
		read = { instance = true, world = true, players = true, perf = true, meta = true, web = true, net = true, fs = true, skills = true },
		web = { web = true, net = true, skills = true },
		game = { instance = true, world = true, players = true, gui = true, remotes = true, meta = true, skills = true },
		full = nil,
	}

	-- The register.
	--
	-- `live` was a bare counter, which is enough to enforce a ceiling and nothing else:
	-- there was no way to ask what is running, what it was asked to do, or to stop one
	-- of them without stopping the whole turn. A dispatch is the longest-lived and least
	-- visible thing this client does -- minutes of work, its own context, its own tool
	-- calls, and a transcript card that scrolls away -- so each one gets a record here
	-- that outlives its card, and the interface reads this rather than the log.
	--
	-- Bounded, because a long session dispatches a lot: running records are never
	-- dropped, finished ones are kept newest-first up to the history limit.
	--
	-- Of those, only the newest few keep the session they ran on. A child's context is
	-- the expensive half of it -- every tool result it collected -- and holding two dozen
	-- of them for the life of the client would make delegation the largest thing in
	-- memory. So a record outlives its session: the newest are resumable, the rest keep
	-- their report and lose the context behind it.
	local HISTORY = 24
	local RESUMABLE = 6
	local ACTIVITY_LIMIT = 24
	local PREVIEW_BYTES = 4096

	M.records = {}
	M.changed = signal.new("subagents")

	local function announceChange()
		M.changed:fire(M.records)
	end

	local function isLive(record)
		return record.status == "running" or record.status == "queued"
	end

	local function awaitingCollection(record)
		if not record.background or isLive(record) or record.collectedRun == (record.runs or 0) then return false end
		local parent = record.parent
		if not parent then return record.parentEpoch == nil end
		return not parent.removed and parent.toolEpoch == record.parentEpoch and not parent.aborted()
	end

	-- Newest first, which is the order the register is held in, so the count runs from
	-- the most recent finished dispatch outward. It used to run from the oldest, which
	-- inverted both rules: the twenty-four kept were the oldest twenty-four, and the
	-- dispatch that had just reported back was the first one dropped.
	local function trimHistory()
		local protected = 0
		for _, record in ipairs(M.records) do if awaitingCollection(record) then protected = protected + 1 end end
		local finished, ordinary = 0, 0
		local ordinaryLimit = math.max(0, HISTORY - protected)
		local kept = {}
		for _, record in ipairs(M.records) do
			if isLive(record) then
				kept[#kept + 1] = record
			else
				local awaiting = awaitingCollection(record)
				if awaiting or ordinary < ordinaryLimit then
					finished = finished + 1
					if not awaiting then ordinary = ordinary + 1 end
					if finished > RESUMABLE then
						-- Release expensive child context. An unread background report still
						-- needs its parent identity for collection and admission accounting.
						if record.disconnect then record.disconnect(); record.disconnect = nil end
						record.session = nil
						if not awaiting then record.parent = nil end
					end
					kept[#kept + 1] = record
				end
			end
		end
		M.records = kept
	end

	local function track(record)
		record.startedAt = clock.ms()
		record.status = "queued"
		record.calls = 0
		record.finishedCalls = 0
		record.tools = {}
		table.insert(M.records, 1, record)
		trimHistory()
		announceChange()
		return record
	end

	-- Newest first, running before finished: what a panel wants to draw in order.
	function M.list()
		local running, done = {}, {}
		for _, record in ipairs(M.records) do
			if isLive(record) then
				running[#running + 1] = record
			else
				done[#done + 1] = record
			end
		end
		local out = {}
		for _, record in ipairs(running) do out[#out + 1] = record end
		for _, record in ipairs(done) do out[#out + 1] = record end
		return out
	end

	function M.running()
		local out = {}
		for _, record in ipairs(M.records) do
			if isLive(record) then out[#out + 1] = record end
		end
		return out
	end

	-- The finished dispatches that still have their context, newest first: the ones a
	-- follow-up can be sent to.
	function M.resumable()
		local out = {}
		for _, record in ipairs(M.records) do
			if record.session and not isLive(record) then out[#out + 1] = record end
		end
		return out
	end

	function M.get(id)
		for _, record in ipairs(M.records) do
			if record.id == id then return record end
		end
		return nil
	end

	-- Finds the dispatch the model named.
	--
	-- The id is what the report hands back, so that is the exact match. A label prefix
	-- is accepted too: a model that has lost the id reaches for the task's first line
	-- instead, and refusing that spends a step teaching it nothing.
	function M.find(reference)
		local needle = util.trim(tostring(reference or ""))
		if needle == "" then return nil end
		local exact = M.get(needle)
		if exact then return exact end
		local lowered = needle:lower()
		for _, record in ipairs(M.records) do
			if tostring(record.label):lower():find(lowered, 1, true) then return record end
		end
		return nil
	end

	-- Stops one dispatch without stopping the turn that asked for it.
	--
	-- The child notices between steps, so this returns before it has actually stopped;
	-- the record says so until its loop unwinds. There is no way to kill a Luau thread,
	-- which is why the flag is the mechanism everywhere in this client.
	function M.stop(id)
		local record = M.get(id)
		if not record or not record.session then return false end
		if not isLive(record) then return false end
		-- Preserve the stop request in the record as well as the child session. The child
		-- may finish between the click and its next cooperative check, and the record must
		-- still report the user-requested stop rather than a normal completion.
		record.stopping = true
		record.stopRequested = true
		record.session.abortFlag = true
		record.session.abort()
		record.session.abortFlag = true
		announceChange()
		log.info("subagent", "stop requested for " .. tostring(record.label))
		return true
	end

	function M.stopAll(parent)
		local stopped = 0
		for _, record in ipairs(M.running()) do
			if (not parent or record.parent == parent) and M.stop(record.id) then stopped = stopped + 1 end
		end
		return stopped
	end

	-- Clear finished history after its owner has collected any background report.
	-- Live work and unread current-turn reports still belong to that conversation.
	function M.clearHistory()
		local kept = {}
		for _, record in ipairs(M.records) do
			if isLive(record) or awaitingCollection(record) then kept[#kept + 1] = record
			elseif record.disconnect then record.disconnect(); record.disconnect = nil end
		end
		M.records = kept
		announceChange()
		return true
	end

	function M.available(depth)
		local limit = config.get("agent.subagentDepth", 2)
		return (depth or 0) < limit
	end

	-- How long a subagent may run, and how long the tool that started it waits.
	--
	-- Both come from one number on purpose. They used to be independent: the child was
	-- given four minutes and the call that started it was bounded by the generic
	-- `agent.toolTimeout` of twenty-five seconds, so nearly every dispatch was reported
	-- to the model as "did not finish within 25s and was left running in the
	-- background" -- and it was, against a caller that had stopped listening. The
	-- report arrived a minute later with nowhere to go, and the model, asked what its
	-- subagents found, could only say it never heard back.
	--
	-- The slack covers one request. A child notices its own deadline between steps, so
	-- it returns a moment after the budget expires rather than exactly on it, and the
	-- tool has to still be there to take the answer.
	local SLACK_SECONDS = 60

	-- Whether a child runs with its clocks off. Read per run rather than captured, so
	-- flipping the switch applies to the next dispatch and to the next follow-up on a
	-- child that has already reported.
	function M.unlimited()
		return config.get("agent.subagentUnlimited", false) == true
	end

	function M.budgetSeconds()
		return math.max(tonumber(config.get("agent.subagentBudget", 240)) or 240, 15)
	end

	-- A day, and it is not a deadline in disguise: with the ceiling lifted there is no
	-- budget to derive a timeout from, and the honest bound on the call above is "as
	-- long as the child takes". A caller that gives up first is the failure this number
	-- exists to avoid -- the child cannot be killed, so it finishes into a void and the
	-- user pays for a report nobody collects.
	local FOREVER_SECONDS = 86400

	function M.toolTimeout()
		if M.unlimited() then return FOREVER_SECONDS end
		return M.budgetSeconds() + SLACK_SECONDS
	end

	-- Width, not just depth.
	--
	-- Several dispatch_agent calls in one step run at the same time, which is the
	-- point: three searches in parallel cost one step instead of three. What that
	-- leaves unbounded is the tree. `agent.toolConcurrency` caps one batch, so it caps
	-- a parallel dispatch from the main conversation -- but a subagent given the
	-- `full` preset dispatches its own batch under its own cap, and two levels of
	-- that multiply rather than add. This is the ceiling on live children anywhere,
	-- and the depth cap above is no substitute for it.
	M.live = 0

	function M.concurrencyLimit()
		local limit = tonumber(config.get("agent.subagentConcurrency", 12))
		if not limit or limit ~= limit then limit = 12 end
		return math.max(1, math.min(12, math.floor(limit)))
	end

	-- A dispatch over the ceiling waits for a slot instead of failing: the model has
	-- already paid for the step that asked, and a refusal would spend another one
	-- learning that it asked for too much at once.
	--
	-- The wait is bounded and comes out of the child's own budget, which is what keeps
	-- `toolTimeout` a valid bound on the call above it. Without that subtraction a
	-- queued child could finish after the tool that started it had given up, and a
	-- report nobody is left to collect is exactly the failure the budget and the
	-- timeout were tied together to prevent.
	--
	-- Returns the budget to run on, `nil` when there is no budget to run against, or
	-- `false` when the turn was stopped while queued. An unlimited child has nothing to
	-- subtract from, so its wait is capped by the ceiling alone.
	local QUEUE_CEILING = 45

	local function waitForSlot(budget, aborted)
		local ceiling = budget and math.min(QUEUE_CEILING, budget / 4) or QUEUE_CEILING
		local waited = 0
		while M.live >= M.concurrencyLimit() and waited < ceiling do
			if aborted and aborted() then return false end
			waited = waited + (clock.wait(0.2) or 0.2)
		end
		if waited <= 0 then return budget end
		log.info("subagent", string.format("queued %.1fs for a slot (%d live)", waited, M.live))
		if not budget then return nil end
		return math.max(budget - waited, 15)
	end

	-- The card in the transcript is titled with the task, so the first line of it is
	-- what the user reads to tell three concurrent subagents apart.
	local function labelFor(task)
		local first = tostring(task):match("^%s*([^\n]*)") or ""
		first = util.trim(first)
		if first == "" then first = "task" end
		return util.ellipsis(first, 64)
	end

	-- A parent must both finish its workers and read their reports. Uncollected
	-- reports remain addressable even after their expensive child context expires.
	function M.pending(parent)
		local out = {}
		local epoch = parent and parent.toolEpoch or nil
		for _, record in ipairs(M.records) do
			if record.background and record.parent == parent and record.parentEpoch == epoch
				and (isLive(record) or awaitingCollection(record)) then out[#out + 1] = record end
		end
		return out
	end

	function M.markCollected(record, parent, runs, runEpoch)
		if type(record) ~= "table" or M.get(record.id) ~= record or isLive(record)
			or record.parent ~= parent or record.parentEpoch ~= (parent and parent.toolEpoch or nil)
			or (runs ~= nil and runs ~= (record.runs or 0))
			or (runEpoch ~= nil and runEpoch ~= record.runEpoch) then return false end
		record.collectedRun = record.runs or 0
		trimHistory()
		announceChange()
		return true
	end

	function M.backgroundLimit()
		return math.min(24, M.concurrencyLimit() * 2)
	end

	-- The monitor keeps bounded display data, never another copy of the child's
	-- context. Parallel progress is matched by call id; an unscoped legacy update
	-- is usable only when exactly one call remains outstanding.
	local function activityFor(record, id)
		local only
		for _, item in ipairs(record.activity or {}) do
			if id ~= nil and item.id == id then return item end
			if not item.done then only = item end
		end
		local pending = (record.calls or 0) - (record.runCallBase or 0)
			- ((record.finishedCalls or 0) - (record.runFinishedBase or 0))
		if id == nil and pending == 1 then return only end
	end

	local function latestExcerpt(value)
		value = tostring(value or "")
		if #value <= PREVIEW_BYTES then return value, false end
		return "...\n" .. value:sub(codeText.clamp(value, #value - PREVIEW_BYTES + 5, true)), true
	end

	local function trimActivity(record)
		if #record.activity <= ACTIVITY_LIMIT then return end
		-- A slow parallel call remains observable as shorter calls finish around it.
		-- If every retained call is pending, the fixed cap still takes precedence.
		for index, item in ipairs(record.activity) do
			if item.done then table.remove(record.activity, index); return end
		end
		table.remove(record.activity, 1)
	end

	local function currentTool(record)
		record.currentTool = nil
		for index = #(record.activity or {}), 1, -1 do
			local item = record.activity[index]
			if not item.done then record.currentTool = item.name; return end
		end
	end

	local function finishActivity(record)
		record.currentTool, record.preview, record.request = nil, nil, nil
		for _, item in ipairs(record.activity or {}) do
			if not item.done then
				item.done, item.interrupted = true, true
			end
		end
	end

	-- Live view.
	--
	-- The transcript renders the parent's event stream and nothing else, so a subagent
	-- that wants to be watched has to speak through it. Every event carries the child's
	-- id, which keys the card, and the id of the tool call that started it, which tells
	-- the view what to nest the card under.
	--
	-- One subscription per child, made with it and kept for the rest of its life: a
	-- follow-up runs the same session again, and a second subscription would draw every
	-- row twice. Which conversation to narrate into is read off the record rather than
	-- captured here, for the same reason -- the turn asking a follow-up is a different
	-- tool call, sometimes in a different conversation, and the card has to appear under
	-- the row the user is looking at now.
	--
	-- Tool RESULTS are summarised to one line rather than forwarded: absorbing that
	-- volume is the entire point of a subagent, and the parent's log is bounded. What
	-- does go across is names, outcomes and timings, because that is the difference
	-- between watching work happen and watching a spinner.
	local function wire(record, child)
		local function announce(kind, payload)
			local parent = record.parent
			-- A stale child must not narrate into a different, still-live parent turn.
			-- An aborted turn moved the epoch too, but its child's final "stopped" still
			-- belongs on the card, so that one is allowed through.
			if not parent or parent.removed or (record.parentEpoch and parent.toolEpoch ~= record.parentEpoch and not parent.aborted()) then return end
			payload = payload or {}
			payload.id = record.id
			payload.call = record.callId
			payload.label = record.label
			parent.emit(kind, payload)
		end
		record.announce = announce

		-- Stop has to reach the child, from whichever conversation is waiting on it.
		-- Without this, aborting the turn left every dispatched subagent running out its
		-- full budget against a conversation that had already moved on -- billed,
		-- invisible and unstoppable.
		child.aborted = function()
			if not alive or not isLive(record) or child.abortFlag == true then return true end
			local parent = record.parent
			if parent and (parent.aborted() or parent.removed or parent.toolEpoch ~= record.parentEpoch) then child.abortFlag = true end
			return child.abortFlag == true
		end

		record.disconnect = child.events:connect(function(event)
			if not isLive(record) then return end
			if event.kind == "tool:call" then
				record.calls = (record.calls or 0) + 1
				record.currentTool = tostring(event.name)
				record.activity[#record.activity + 1] = {
					id = event.id, index = record.calls, name = util.ellipsis(tostring(event.name), 120),
					startedAt = event.at or clock.ms(),
				}
				trimActivity(record)
				-- Names only, and the last twelve of them: the register is read by a
				-- panel that lists every dispatch in the session, so it cannot hold
				-- their arguments as well.
				record.tools[#record.tools + 1] = tostring(event.name)
				if #record.tools > 12 then table.remove(record.tools, 1) end
				announceChange()
				announce("subagent:tool", {
					callId = event.id,
					name = event.name,
					risk = event.risk,
					-- Forwarded whole, and summarised by the view instead.
					--
					-- A child session is headless and therefore keeps no log of its own, so
					-- this event is the only record that the call ever happened. At 160
					-- characters, whitespace-collapsed, the Luau a subagent executed was
					-- unrecoverable -- and a subagent is exactly where the long-running code
					-- in this client gets run. Detailed activity has its own bounded
					-- transcript budget and cannot evict dialogue or dispatch summaries.
					arguments = tostring(event.arguments or ""),
					index = record.calls - (record.runCallBase or 0),
				})
			elseif event.kind == "tool:result" or event.kind == "tool:error" then
				local item = activityFor(record, event.id)
				record.finishedCalls = (record.finishedCalls or 0) + 1
				if item then
					item.done, item.ok, item.ms = true, event.kind == "tool:result" and event.ok ~= false, event.ms
					item.summary = util.ellipsis(tostring(event.text or event.error or ""), 1024)
				end
				currentTool(record)
				if record.calls - (record.runCallBase or 0) == record.finishedCalls - (record.runFinishedBase or 0) then
					record.statusText = "Preparing next step"
				end
				announceChange()
				announce("subagent:tool:done", {
					callId = event.id,
					finishedCalls = record.finishedCalls - (record.runFinishedBase or 0),
					name = event.name,
					ok = event.kind == "tool:result",
					ms = event.ms,
					summary = util.ellipsis(tostring(event.text or ""):gsub("%s+", " "), 140),
					-- The full result as well, for the row that can open. `summary` is what
					-- the collapsed line shows and stays short.
					text = tostring(event.text or ""),
				})
			elseif event.kind == "tool:progress" then
				local item = activityFor(record, event.id)
				if item and not item.done then
					item.progress = util.ellipsis(tostring(event.text or ""), 1024)
					announceChange()
				end
			elseif event.kind == "request:start" then
				record.preview = nil
				record.statusText = "Waiting for provider output"
				record.request = { provider = event.provider, model = event.model, attempt = event.attempt }
				record.provider, record.model = event.provider, event.model
				announceChange()
			elseif event.kind == "request:retry" then
				record.statusText = string.format("Retrying %s (attempt %s): %s", tostring(event.provider or "provider"),
					tostring(event.attempt or ""), util.ellipsis(tostring(event.reason or ""), 200))
				announceChange()
			elseif event.kind == "request:done" then
				record.request = nil
				if event.error then record.preview = nil end
				announceChange()
			elseif event.kind == "assistant:preview" then
				local text, textExcerpt = latestExcerpt(event.text)
				local reasoning, reasoningExcerpt = latestExcerpt(event.reasoning)
				record.preview = { text = text, reasoning = reasoning, textExcerpt = textExcerpt,
					reasoningExcerpt = reasoningExcerpt, limited = event.limited == true }
				announceChange()
			elseif event.kind == "assistant:complete" then
				record.preview = nil
				announceChange()
			elseif event.kind == "assistant:reasoning" then
				record.latestReasoning, record.reasoningExcerpt = latestExcerpt(event.text)
				if record.preview then record.preview.reasoning = "" end
				announceChange()
			elseif event.kind == "assistant:text" then
				if util.trim(tostring(event.text or "")) ~= "" then
					record.latestText, record.textExcerpt = latestExcerpt(event.text)
					if record.preview then record.preview.text = "" end
					announceChange()
					announce("subagent:text", { text = util.ellipsis(util.trim(event.text), 400) })
				end
			elseif event.kind == "status" then
				-- "Ready" is the child's own idle text and means nothing on a card that
				-- reports its finish separately. Dropping it here rather than in the
				-- view keeps one entry per turn out of the parent's bounded log.
				if tostring(event.text) ~= "Ready" then
					record.statusText = util.ellipsis(tostring(event.text), 1024)
					announceChange()
					announce("subagent:status", { text = tostring(event.text) })
				end
			elseif event.kind == "error" then
				record.statusText = util.ellipsis(tostring(event.message), 1024)
				record.preview, record.request = nil, nil
				announceChange()
				announce("subagent:status", { text = tostring(event.message), bad = true })
			elseif event.kind == "permission:ask" then
				-- Nothing is subscribed to a headless session, so a prompt raised
				-- inside a subagent has to surface on the parent's stream or it
				-- would sit unanswered until its own deadline.
				local parent = record.parent
				if parent then parent.emit("permission:ask", event) end
			end
		end)
	end

	-- Reserve this run before publishing it or scheduling its worker. In particular,
	-- Stop and a parent generation change after admission must survive until the
	-- worker starts; the worker never resets these flags or adopts a newer epoch.
	local function prepareRun(record, text, background)
		local child = record.session
		record.background = background == true
		record.parentEpoch = record.parent and record.parent.toolEpoch
		record.stopRequested, record.stopping, record.currentTool = nil, nil, nil
		record.status, record.startedAt = "queued", clock.ms()
		record.ms, record.messages, record.turnsUsed, record.report = nil, nil, nil, nil
		record.error, record.ok, record.aborted = nil, nil, nil
		record.collectedRun = nil
		record.preview, record.latestText, record.latestReasoning, record.request = nil, nil, nil, nil
		record.textExcerpt, record.reasoningExcerpt = nil, nil
		record.provider, record.model = nil, nil
		record.activity, record.currentTask, record.statusText = {}, text, "Waiting for a slot"
		record.runCallBase, record.runFinishedBase = record.calls or 0, record.finishedCalls or 0
		child.toolEpoch = {}
		record.runEpoch = child.toolEpoch
		child.abortFlag = false
	end

	-- Blocking and background entry points share the same slots, budgets, child
	-- loop, event forwarding and completion state.
	local function runChild(record, text, opts)
		opts = opts or {}
		local child = record.session
		local unlimited = M.unlimited()
		local announce = record.announce
		local requestedBudget
		if not unlimited then requestedBudget = opts.budgetSeconds or M.budgetSeconds() end
		local budget = waitForSlot(requestedBudget, child.aborted)
		if budget == false or child.aborted() or M.live >= M.concurrencyLimit() then
			M.stopAll(child)
			record.status = "stopped"
			record.stopping = nil
			record.ms = clock.since(record.startedAt)
			record.report = "Stopped before it started."
			record.ok, record.aborted = false, true
			finishActivity(record)
			trimHistory()
			announceChange()
			announce("subagent:done", { ms = record.ms, ok = false, aborted = true, text = record.report,
				calls = 0, finishedCalls = 0 })
			return nil, "the turn was stopped before this subagent started"
		end

		child.turns = child.turns + 1
		child.unlimited = unlimited
		child.budgetSeconds = budget
		if opts.turns then child.maxTurns = opts.turns end
		record.status = "running"
		record.statusText = "Starting"
		record.stopping = nil
		record.startedAt = clock.ms()
		record.budget = budget
		record.unlimited = unlimited
		record.turns = child.maxTurns
		record.runs = (record.runs or 0) + 1
		announceChange()

		announce("subagent:start", {
			startedAt = record.startedAt,
			task = util.ellipsis(text, 400),
			preset = record.preset,
			turns = unlimited and 0 or child.maxTurns,
			budget = budget,
			unlimited = unlimited,
			depth = record.depth,
			followUp = record.runs > 1,
		})

		-- Counted around the pcall rather than around the whole setup, so a raise
		-- anywhere inside cannot leak a slot and permanently narrow the ceiling.
		local started = clock.ms()
		M.live = M.live + 1
		local ok, reply = pcall(function() return env.require("agent/loop").run(child, text) end)
		M.live = math.max(M.live - 1, 0)
		M.stopAll(child)

		local elapsed = clock.since(started)
		if not ok then
			child.abortFlag = true
			log.warn("subagent", "failed", reply)
			local note = "the subagent failed: " .. util.ellipsis(tostring(reply), 200)
			record.status = "failed"
			record.stopping = nil
			record.ms = elapsed
			record.report = note
			record.error, record.ok = note, false
			finishActivity(record)
			trimHistory()
			announceChange()
			announce("subagent:done", { ms = elapsed, ok = false, text = note,
				calls = (record.calls or 0) - record.runCallBase,
				finishedCalls = (record.finishedCalls or 0) - record.runFinishedBase })
			return nil, note
		end

		local stats = child.ctx.stats()
		local aborted = record.stopRequested == true or child.aborted() == true
		log.info("subagent", string.format("finished in %s over %d messages%s",
			util.formatDuration(elapsed), stats.messages, aborted and " (stopped)" or ""))

		record.status = aborted and "stopped" or "done"
		record.ok, record.aborted = not aborted, aborted
		record.ms = elapsed
		record.messages = stats.messages
		record.turnsUsed = stats.turns
		record.report = tostring(reply)
		finishActivity(record)
		record.stopping = nil
		-- Now that this one has finished, it is the newest resumable record -- which is
		-- what pushes the oldest past the line and releases the context behind it.
		trimHistory()
		announceChange()

		announce("subagent:done", {
			ms = elapsed,
			calls = (record.calls or 0) - record.runCallBase,
			finishedCalls = (record.finishedCalls or 0) - record.runFinishedBase,
			ok = not aborted,
			aborted = aborted,
			messages = stats.messages,
			turns = stats.turns,
			resumable = record.session ~= nil and not aborted,
			text = util.ellipsis(tostring(reply), 600),
		})

		return {
			id = record.id,
			text = tostring(reply),
			ms = elapsed,
			messages = stats.messages,
			turns = stats.turns,
			aborted = aborted,
			resumable = record.session ~= nil,
		}
	end

	local function prepareDispatch(opts, background)
		if not alive then return nil, "the client is unloading" end
		local parent = opts.parent
		local depth = (parent and parent.depth or 0) + 1

		if not M.available(depth - 1) then
			return nil, "subagent depth limit reached (" .. tostring(config.get("agent.subagentDepth", 2)) .. ")"
		end

		local task_text = util.trim(opts.task)
		if task_text == "" then return nil, "a subagent needs a task" end

		local turns = opts.turns or config.get("agent.subagentTurns", 14)

		-- Registered before the queue wait, so a dispatch parked waiting for a slot is
		-- visible as one rather than looking like nothing happened.
		local record = {
			id = util.uid("agent"),
			label = labelFor(task_text),
			task = task_text,
			preset = opts.preset or "read",
			depth = depth,
			-- The conversation currently waiting on this child, and the tool call inside
			-- it. Both move when a follow-up arrives from somewhere else, which is why
			-- they live on the record rather than in a closure.
			parent = parent,
			callId = opts.callId,
			parentId = parent and parent.id or nil,
			parentTitle = parent and parent.title or nil,
			turns = turns,
		}

		-- A child cannot ask, and a headless worker has no conversation of its own to
		-- name: both tools are absent from its catalogue rather than described and
		-- refused.
		local excluded = { ask_user = true, conversation_rename = true }
		if record.preset ~= "full" then
			-- Every preset can read relevant skills. This does not grant a
			-- restricted worker permission to change the user's standing playbooks.
			excluded.skills_write, excluded.skills_install, excluded.skills_delete = true, true, true
		end
		local child = session.create({
			title = "subagent",
			depth = depth,
			headless = true,
			maxTurns = turns,
			toolGroups = M.PRESETS[opts.preset or "read"],
			-- A child has no user to ask, so the tool that asks is absent from its
			-- catalogue entirely rather than described-and-refused. The brief also
			-- says so, because a model that knows it cannot ask writes a complete
			-- report instead of stopping at a question.
			toolExclude = excluded,
			-- Keep the provider's stream setting: buffered HTTP can carry reasoning and
			-- usage metadata, while a compatible socket can also deliver live previews.
		})
		-- The record is what the Subagents panel reads, so it is kept whether or not
		-- there is a parent transcript to narrate into. The wiring below is therefore
		-- unconditional; only the forwarding inside it is not.
		record.session = child

		-- The brief replaces the main system prompt rather than appending to it, and it
		-- is a function so that every turn -- including a follow-up months of tool calls
		-- later -- is built against the environment and the switches in force then.
		-- Carrying it on the session, instead of swapping the prompt module's builder, is
		-- what makes two subagents dispatched in the same batch safe.
		child.systemPrompt = function(request)
			request = request or {}
			return prompt.subagent(task_text, {
				extra = (opts.extra or "") .. "\nNative workspace references are shared with the user. Respect this subagent's tool scope; never use a controller or generated script to bypass a denied native action.",
				unlimited = M.unlimited(),
				tools = request.tools,
				model = request.model,
				provider = request.provider,
				session = child,
			})
		end

		wire(record, child)
		prepareRun(record, task_text, background)
		return track(record), task_text
	end

	-- Existing callers can still request a blocking dispatch explicitly.
	function M.dispatch(opts)
		local record, text = prepareDispatch(opts, false)
		if not record then return nil, text end
		return runChild(record, text, opts)
	end

	-- A second turn on a subagent that has already reported back.
	--
	-- A dispatch used to be one shot: the child answered, its context went on the floor,
	-- and a parent that wanted one more fact had to describe the whole job again to a
	-- fresh subagent that would go and rediscover it. This continues the same
	-- conversation instead -- the child still has everything it found -- which is what
	-- makes a subagent that stopped at a limit worth talking to rather than worth
	-- replacing, and what lets the parent steer one instead of only reading it.
	local function prepareFollowUp(opts, background)
		if not alive then return nil, "the client is unloading" end
		local record = M.find(opts.id)
		if not record then
			local open = M.resumable()
			if #open == 0 then
				return nil, "no subagent is open for a follow-up. Dispatch one with dispatch_agent first."
			end
			local names = {}
			for _, candidate in ipairs(open) do
				names[#names + 1] = string.format("%s (%s)", candidate.id, candidate.label)
			end
			return nil, string.format("no subagent matches '%s'. Open for a follow-up: %s",
				tostring(opts.id), table.concat(names, "; "))
		end
		if isLive(record) then
			return nil, "that subagent is still working. Check its status before sending a follow-up."
		end
		if not record.session then
			return nil, "that subagent's context has already been released, so there is nothing to continue. Dispatch a new one with what you know."
		end

		local text = util.trim(opts.task)
		if text == "" then return nil, "a follow-up needs a message" end

		local parent = opts.parent or record.parent
		if parent ~= record.parent and awaitingCollection(record) then
			return nil, "that subagent's report must be collected by its current conversation before transferring it"
		end
		if background then
			local depth = (parent and parent.depth or 0) + 1
			if not M.available(depth - 1) then return nil, "subagent depth limit reached" end
			record.depth, record.session.depth = depth, depth
		end
		record.parent = parent
		record.parentId, record.parentTitle = parent and parent.id or nil, parent and parent.title or nil
		record.callId = opts.callId
		prepareRun(record, text, background)
		announceChange()
		return record, text
	end

	function M.followUp(opts)
		local record, text = prepareFollowUp(opts, false)
		if not record then return nil, text end
		return runChild(record, text, { turns = opts.turns })
	end

	local function backgroundFailure(record, reason)
		local note = "the subagent failed: " .. util.ellipsis(tostring(reason), 200)
		if record.session then record.session.abortFlag = true; M.stopAll(record.session) end
		record.status, record.stopping = "failed", nil
		record.report, record.error, record.ok = note, note, false
		record.ms = clock.since(record.startedAt or clock.ms())
		finishActivity(record)
		trimHistory()
		announceChange()
		record.announce("subagent:done", { ms = record.ms, ok = false, text = note,
			calls = (record.calls or 0) - (record.runCallBase or 0),
			finishedCalls = (record.finishedCalls or 0) - (record.runFinishedBase or 0) })
	end

	local function startBackground(opts, prepare)
		if not alive then return nil, "the client is unloading" end
		if type(opts) ~= "table" then return nil, "subagent options are required" end
		local parent = opts.parent
		if not parent and prepare == prepareFollowUp then
			local record = M.find(opts.id)
			parent = record and record.parent
		end
		if parent and parent.headless and M.live >= M.concurrencyLimit() then
			return nil, "all subagent execution slots are in use; continue your own work or check existing subagents"
		end
		local awaiting = 0
		for _, record in ipairs(M.records) do if awaitingCollection(record) then awaiting = awaiting + 1 end end
		if M.backgroundCount + awaiting >= M.backgroundLimit() then
			return nil, "background subagent capacity is full; read existing reports before starting another"
		end
		-- Reserve before setup: registration signals may invoke other callers.
		M.backgroundCount = M.backgroundCount + 1
		local reserved = true
		local function release()
			if not reserved then return false end
			reserved = false
			M.backgroundCount = math.max(0, M.backgroundCount - 1)
			return true
		end
		local ok, record, text = pcall(prepare, opts, true)
		if not ok or not record then
			release()
			return nil, tostring(ok and text or record)
		end
		local runOptions = { turns = opts.turns, budgetSeconds = opts.budgetSeconds }
		local scheduled, why = pcall(clock.delay, 0, function()
			if not reserved then return end
			local ran, result, err = pcall(runChild, record, text, runOptions)
			release()
			if not ran then backgroundFailure(record, result)
			elseif not result and record.status == "failed" then record.error = err end
		end)
		if not scheduled then
			release()
			-- The caller receives this failure directly, without an accepted worker id.
			-- It must not leave an unread background obligation behind.
			record.collectedRun = record.runs or 0
			backgroundFailure(record, why)
			return nil, tostring(why)
		end
		return record
	end

	function M.start(opts)
		return startBackground(opts, prepareDispatch)
	end

	function M.startFollowUp(opts)
		return startBackground(opts, prepareFollowUp)
	end

	env.require("runtime/dispose").add(function()
		alive = false
		M.stopAll()
		for _, record in ipairs(M.records) do if record.disconnect then record.disconnect(); record.disconnect = nil end end
		M.changed:clear()
	end, "native subagents")
	return M
end
