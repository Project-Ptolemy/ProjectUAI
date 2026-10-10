-- Tools the agent uses on itself: the task list, durable memory, delegation and
-- deliberate waiting.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local config = env.require("runtime/config")
	local state = env.require("agent/state")
	local subagent = env.require("agent/subagent")
	local H = env.require("tools/helpers")

	-- How long ask_user waits for a person before giving up on them, in seconds.
	-- Ten minutes rather than the permission prompt's three: a question is asked at
	-- the start of a turn and the user may be mid-game, while a permission prompt
	-- arrives during work they are already watching.
	local ASK_TIMEOUT = 600
	local reportReads = setmetatable({}, { __mode = "k" })
	local function isLive(record)
		return record.status == "queued" or record.status == "running"
	end
	local function aborted(ctx)
		return ctx and ctx.aborted and ctx.aborted()
	end
	local function backgroundReceipt(record)
		reportReads[record] = nil
		return { text = string.format("Subagent %s started in the background (%s). Continue your own independent work. "
			.. "Use agent_status with id=\"%s\" to check progress and collect its report before your final answer.",
			record.id, record.status, record.id),
			data = { id = record.id, status = record.status, background = true, run = record.runs or 0 } }
	end
	local function callCounts(record)
		return math.max(0, (record.calls or 0) - (record.runCallBase or 0)),
			math.max(0, (record.finishedCalls or 0) - (record.runFinishedBase or 0))
	end
	local function progressText(record)
		local calls, finished = callCounts(record)
		local lines = {
			"Status: " .. tostring(record.status) .. (record.stopping and " (stopping)" or ""),
			"Task: " .. util.ellipsis(record.currentTask or record.task or record.label, 240),
			string.format("Calls: %d of %d finished", finished, calls),
			"Current step: " .. util.ellipsis(record.statusText or record.currentTool or "Waiting for a slot", 240),
		}
		local shown = 0
		for _, item in ipairs(record.activity or {}) do
			if not item.done and shown < 4 then
				shown = shown + 1
				lines[#lines + 1] = util.ellipsis(item.name, 100) .. ": " .. util.ellipsis(item.progress or "In progress", 300)
			end
		end
		local preview = record.preview
		local latest = preview and preview.text ~= "" and preview.text or record.latestText
		if latest and latest ~= "" then lines[#lines + 1] = "Latest delivered message: " .. util.ellipsis(latest, 1000) end
		local reasoning = preview and preview.reasoning ~= "" and preview.reasoning or record.latestReasoning
		if reasoning and reasoning ~= "" then lines[#lines + 1] = "Latest reasoning: " .. util.ellipsis(reasoning, 600) end
		return table.concat(lines, "\n")
	end
	local function statusResult(args, ctx)
		local parent = ctx and ctx.session
		if not parent then return H.fail("there is no conversation to inspect subagents for") end
		local id = args.id and util.trim(args.id)
		if id == "" then return H.fail("id must name a subagent, or be omitted to list this conversation's subagents") end
		local function selected()
			if id then
				local record = subagent.get(id)
				if not record or record.parent ~= parent then return nil end
				return { record }
			end
			local records = {}
			for _, record in ipairs(subagent.list()) do
				if record.parent == parent then records[#records + 1] = record end
			end
			return records
		end
		local records = selected()
		if not records then return H.fail("no subagent with that id belongs to this conversation") end
		local seconds = tonumber(args.wait_seconds) or 0
		if seconds ~= seconds or seconds == math.huge or seconds == -math.huge then return H.fail("wait_seconds must be between 0 and 30") end
		seconds = seconds > 0 and math.max(1, math.min(30, seconds)) or 0
		local waiting = {}
		for _, record in ipairs(records) do
			if isLive(record) then waiting[#waiting + 1] = record
			elseif record.collectedRun ~= (record.runs or 0) then seconds = 0 end
		end
		local waited = 0
		while #waiting > 0 and waited < seconds do
			if aborted(ctx) then return H.fail("subagent status wait was aborted") end
			local finished = false
			for _, record in ipairs(waiting) do
				if subagent.get(record.id) ~= record or record.parent ~= parent or not isLive(record) then finished = true; break end
			end
			if finished then break end
			local step = math.min(0.25, seconds - waited)
			waited = waited + (clock.wait(step) or step)
		end
		if aborted(ctx) then return H.fail("subagent status wait was aborted") end
		records = selected()
		if not records then return H.fail("the subagent is no longer available to this conversation") end
		if id then
			local record = records[1]
			local live, run = isLive(record), record.runs or 0
			local body = live and progressText(record) or tostring(record.report or "No report was retained.")
			local result = H.readSlice("Subagent " .. record.id .. " " .. record.status .. (live and " activity" or " report"), body, args, 3500)
			if live then reportReads[record] = nil end
			if result.data then
				local data = result.data
				data.id, data.status, data.run, data.complete = record.id, record.status, run, not live
				data.calls, data.finishedCalls = callCounts(record)
				data.resumable, data.waited = not live and record.session ~= nil, waited
				if not live then
					local read = reportReads[record]
					local epoch = record.runEpoch
					if not read or read.run ~= run or read.epoch ~= epoch then read = { run = run, epoch = epoch, through = 1 }; reportReads[record] = read end
					if data.offset <= read.through then read.through = math.max(read.through, data.nextOffset or (#body + 1)) end
					if data.eof and read.through >= #body + 1 then data.collected = subagent.markCollected(record, parent, run, epoch) end
				end
			end
			return result
		end
		local lines, live = {}, 0
		for _, record in ipairs(records) do
			local calls, finished = callCounts(record)
			if isLive(record) then live = live + 1 end
			lines[#lines + 1] = string.format("[%s] %s: %s; %d/%d calls finished%s", record.id, record.status,
				util.ellipsis(record.label or record.currentTask or record.task, 80), finished, calls,
				isLive(record) and ("; " .. util.ellipsis(record.statusText or record.currentTool or "Waiting", 120))
					or "; read its report with agent_status id=\"" .. record.id .. "\"")
		end
		local result = H.readSlice("Subagents owned by this conversation", #lines > 0 and table.concat(lines, "\n") or "No subagents belong to this conversation.", args, 3500)
		if result.data then result.data.total, result.data.live, result.data.waited = #records, live, waited end
		return result
	end

	-- A previous conversation rendered for review by the agent. Built from the
	-- durable transcript (the full persisted history), falling back to the model
	-- context for a thread that predates stored logs. Condensed by default: long
	-- turns are shortened and tool runs collapsed, so a whole conversation fits in
	-- one bounded read; full=true returns every turn verbatim for byte-sliced paging.
	local REVIEW_USER_CAP, REVIEW_REPLY_CAP = 500, 900
	local function turnText(text, full, limit)
		text = util.trim(tostring(text or ""))
		if full or #text <= limit then return text end
		return util.ellipsis(text, limit)
	end
	local function readableTranscript(session, full)
		local parts = {}
		if session.ctx.summary and util.trim(session.ctx.summary) ~= "" then
			parts[#parts + 1] = "[earlier turns, summarised: " .. util.trim(session.ctx.summary) .. "]"
		end
		local tools = {}
		local function flush()
			if #tools > 0 then parts[#parts + 1] = "[ran " .. table.concat(tools, ", ") .. "]"; tools = {} end
		end
		for _, event in ipairs(session.log or {}) do
			local kind = event.kind
			if kind == "user" then
				flush(); parts[#parts + 1] = "User: " .. turnText(event.text, full, REVIEW_USER_CAP)
			elseif kind == "assistant:text" then
				flush()
				local text = turnText(event.text, full, REVIEW_REPLY_CAP)
				if text ~= "" then parts[#parts + 1] = "Assistant: " .. text end
			elseif kind == "tool:call" then
				tools[#tools + 1] = tostring(event.name or "tool")
			elseif kind == "compact" then
				flush(); parts[#parts + 1] = "[conversation compacted here]"
			elseif kind == "error" then
				flush(); parts[#parts + 1] = "[error: " .. util.ellipsis(tostring(event.message or ""), 160) .. "]"
			end
		end
		flush()
		if #parts == 0 then
			for _, message in ipairs(session.ctx.messages or {}) do
				if message.role == "user" then
					parts[#parts + 1] = "User: " .. turnText(message.content, full, REVIEW_USER_CAP)
				elseif message.role == "assistant" and util.trim(tostring(message.content or "")) ~= "" then
					parts[#parts + 1] = "Assistant: " .. turnText(message.content, full, REVIEW_REPLY_CAP)
				end
			end
		end
		return table.concat(parts, "\n\n")
	end

	-- The opening request of a thread, for list previews and triage. A thread with
	-- no user message has nothing to review, and returns nil so the list can skip it.
	local function openingLine(session)
		for _, event in ipairs(session.log or {}) do
			if event.kind == "user" and type(event.text) == "string" and util.trim(event.text) ~= "" then
				return util.ellipsis(util.trim(event.text), 140)
			end
		end
		for _, message in ipairs(session.ctx.messages or {}) do
			if message.role == "user" and util.trim(tostring(message.content or "")) ~= "" then
				return util.ellipsis(util.trim(tostring(message.content)), 140)
			end
		end
		return nil
	end

	return {
		{
			name = "todo_write",
			risk = "read",
			description = "Replace the full task list. Use when substantial work benefits from a tracked plan; keep one item active while work remains. Routine tool sequences need no list.",
			parameters = {
				type = "object",
				properties = {
					items = {
						type = "array",
						description = "The complete list, in order. Sending a partial list deletes the rest.",
						items = {
							type = "object",
							properties = {
								text = { type = "string", description = "What the step is, in the imperative." },
								status = { type = "string", enum = { "pending", "active", "done", "dropped" } },
							},
							required = { "text" },
						},
					},
				},
				required = { "items" },
			},
			run = function(args, ctx)
				-- Written to the conversation that asked, not to the client: two
				-- conversations open at once each keep their own plan.
				local session = ctx and ctx.session or nil
				local items = state.setTodos(args.items, session)
				if #items == 0 then return "Task list cleared." end
				local counts = state.todoCounts(session)
				return string.format("Task list set: %d items (%d done, %d active, %d pending).\n%s",
					counts.total, counts.done, counts.active, counts.pending, state.todoBlock(session))
			end,
		},
		{
			name = "todo_read",
			risk = "read",
			description = "Read the current task list.",
			parameters = { type = "object", properties = util.emptyObject(), required = {} },
			run = function(_, ctx)
				local block = state.todoBlock(ctx and ctx.session or nil)
				if not block then return "The task list is empty." end
				return block
			end,
		},
		{
			-- Reading other conversations. A user who has discussed a build in three
			-- threads this week should not have to re-explain it in the fourth, and the
			-- agent should not have to re-derive it. Read-only by construction: it
			-- searches the session store, and the transcripts it reads are the durable
			-- ones on disk as well as the live ones.
			name = "conversation_search",
			risk = "read",
			description = "Search this user's other conversations for something they or the agent said earlier. Use it when the current request refers to earlier work -- 'like last time', 'the script you fixed', 'my usual setup' -- and the facts are not in this conversation. Returns the matching lines with which conversation they came from and its [id]; read the whole thread with conversation_read. This conversation is not searched; you already have it.",
			parameters = {
				type = "object",
				properties = {
					query = {
						type = "string",
						description = "The words to look for, as the user would have written them.",
					},
					limit = {
						type = "integer",
						description = "Maximum matches. Default 5.",
						minimum = 1,
						maximum = 12,
					},
				},
				required = { "query" },
			},
			run = function(args, ctx)
				local sessions = env.require("agent/session")
				local current = ctx and ctx.session or nil
				local needle = util.trim(tostring(args.query or "")):lower()
				if needle == "" then return H.fail("a query is required") end
				local limit = util.clamp(tonumber(args.limit) or 5, 1, 12)

				local lines, seen = {}, {}

				-- Pasted material first: a script the user pasted last week is often the
				-- thing "that code I sent you" refers to, and it lives in files rather
				-- than in any conversation's context -- the conversation holds only the
				-- pointer.
				local fsx = env.require("runtime/fsx")
				if fsx.enabled then
					for _, entry in ipairs(fsx.list("", { scope = "pastes" })) do
						if not entry.isDir and #lines < limit then
							local body = fsx.read(entry.path, { scope = "pastes" })
							if body then
								local at = body:lower():find(needle, 1, true)
								if at then
									lines[#lines + 1] = string.format("pasted in pastes/%s: %s",
										entry.name, util.ellipsis(body:sub(math.max(at - 60, 1)), 320))
								end
							end
						end
					end
				end

				-- All conversation text: the context the model saw plus the transcript
				-- the user read. The transcript is where a restored conversation keeps
				-- everything -- a context that has been compacted holds a summary, not
				-- the words -- so searching only ctx.messages would silently miss old
				-- threads.
				for _, session in ipairs(sessions.list()) do
					if session ~= current and not session.headless then
						local entries = {}
						for _, message in ipairs(session.ctx.messages or {}) do
							local role = message.role == "user" and "the user"
								or (message.role == "assistant" and "you" or nil)
							if role then
								entries[#entries + 1] = { role = role, text = tostring(message.content or "") }
							end
						end
						for _, event in ipairs(session.log or {}) do
							if (event.kind == "user" or event.kind == "assistant:text")
								and type(event.text) == "string" then
								entries[#entries + 1] = {
									role = event.kind == "user" and "the user" or "you",
									text = event.text,
								}
							end
						end
						for _, entry in ipairs(entries) do
							if #lines >= limit then break end
							local at = entry.text:lower():find(needle, 1, true)
							if at then
								-- One line per conversation, the first match, stated once:
								-- a thread that mentioned the term six times is one
								-- lead, not six results.
								if seen[session.id] then break end
								seen[session.id] = true
								lines[#lines + 1] = string.format('%s in "%s" [%s]: %s',
									entry.role, session.title, session.id,
									util.ellipsis(entry.text:sub(math.max(at - 60, 1)), 320))
								break
							end
						end
					end
					if #lines >= limit then break end
				end

				if #lines == 0 then
					return string.format("No other conversation or paste mentions '%s'. The user may be thinking of something from before this client kept threads, or of work in this conversation.", tostring(args.query))
				end
				return string.format("%d match%s elsewhere (read a full thread with conversation_read using its [id]):\n%s",
					#lines, #lines == 1 and "" or "es", table.concat(lines, "\n"))
			end,
		},
		{
			-- The survey: what conversations exist, with the ids the reader needs.
			name = "conversation_list",
			risk = "read",
			description = "List this user's other conversations for review, most recent first, each with its id, title, place, age, size and opening request. Use it to triage which past thread is relevant, then read that one with conversation_read. Untouched empty chats are omitted; the current conversation is marked and does not need reading. Query filters on the title or the opening request.",
			parameters = {
				type = "object",
				properties = {
					query = { type = "string", description = "Optional: only conversations whose title or opening request contains this text." },
					offset = { type = "integer", minimum = 1 },
					limit = { type = "integer", minimum = 1, maximum = 30, description = "Maximum rows. Default 10." },
				},
				required = {},
			},
			run = function(args, ctx)
				local sessions = env.require("agent/session")
				local current = ctx and ctx.session or nil
				local needle = util.trim(tostring(args.query or "")):lower()
				local all = {}
				for _, session in ipairs(sessions.list()) do
					if not session.headless then
						local preview = openingLine(session)
						-- A thread with no user message is an untouched chat: nothing to review.
						if preview and (needle == "" or tostring(session.title):lower():find(needle, 1, true)
							or preview:lower():find(needle, 1, true)) then
							all[#all + 1] = { session = session, preview = preview }
						end
					end
				end
				if #all == 0 then
					return needle == "" and "This client has no other conversations to review yet."
						or ("Nothing matches '" .. tostring(args.query) .. "' in other conversations.")
				end
				local offset = math.max(1, math.floor(tonumber(args.offset) or 1))
				local limit = util.clamp(tonumber(args.limit) or 10, 1, 30)
				local now = clock.ms()
				local lines, shown = {}, {}
				for index = offset, math.min(#all, offset + limit - 1) do
					local session, preview = all[index].session, all[index].preview
					local ago = session.updatedAt and (util.formatDuration(math.max(now - session.updatedAt, 0)) .. " ago") or "unknown age"
					lines[#lines + 1] = string.format('%s [%s]%s -- %s, %s%s\n    %s',
						session.title, session.id,
						session.placeName and (" in " .. session.placeName) or "",
						util.pluralise(session.turns or 0, "turn"), ago,
						session == current and " (this conversation)" or "", preview)
					shown[#shown + 1] = { id = session.id, title = session.title, turns = session.turns or 0,
						place = session.placeName, current = session == current, preview = preview }
				end
				local nextOffset = offset + limit <= #all and offset + limit or nil
				local header = string.format("%d conversation%s%s. Read one with conversation_read [id] (add full=true for verbatim text):",
					#all, #all == 1 and "" or "s",
					nextOffset and (", showing " .. offset .. "-" .. (offset + #lines - 1)) or "")
				return { text = header .. "\n" .. table.concat(lines, "\n"),
					data = { total = #all, conversations = shown, nextOffset = nextOffset } }
			end,
		},
		{
			-- Reading a whole thread, not just a search snippet. This is what turns
			-- "the user mentioned a build last week" into the actual decisions taken.
			name = "conversation_read",
			risk = "read",
			description = "Read one of this user's other conversations by id (from conversation_list or conversation_search). Condensed by default: the whole thread with long turns shortened and tool runs collapsed, so a review costs one bounded read. Pass full=true for the verbatim transcript in UTF-8-safe byte slices, following nextOffset for the rest. Use it after a list or search points at a relevant thread, so you carry forward what was decided instead of re-deriving or re-asking it.",
			parameters = {
				type = "object",
				properties = {
					id = { type = "string", description = "The conversation id, as shown in [brackets] by conversation_list or conversation_search." },
					full = { type = "boolean", description = "Return every turn verbatim instead of the condensed review. Use only when you need exact wording; it costs more slices." },
					offset = { type = "integer", minimum = 1, description = "Byte offset to continue from; use the nextOffset from the previous read." },
					limit = { type = "integer", minimum = 200, maximum = 6000, description = "Maximum bytes to return in this slice." },
				},
				required = { "id" },
			},
			run = function(args, ctx)
				local sessions = env.require("agent/session")
				local id = util.trim(tostring(args.id or ""))
				if id == "" then return H.fail("a conversation id is required; list them with conversation_list") end
				local session = sessions.threads[id]
				if not session then
					for _, candidate in ipairs(sessions.list()) do
						if candidate.title == args.id then session = candidate; break end
					end
				end
				if not session then return H.fail("no conversation with id '" .. id .. "'. Use conversation_list for current ids.") end
				if session.headless then return H.fail("that id is an internal subagent session, not a conversation.") end
				local full = args.full == true
				local body = readableTranscript(session, full)
				if util.trim(body) == "" then body = "(this conversation has no readable messages yet)" end
				if not full then
					body = "(condensed: long turns are shortened and tool runs collapsed; call again with full=true for verbatim text)\n\n" .. body
				end
				local label = string.format('Conversation "%s" [%s]%s (%s)', session.title, session.id,
					session.placeName and (" in " .. session.placeName) or "", full and "full" or "condensed")
				return H.readSlice(label, body, args, 4000)
			end,
		},
		{
			-- The conversation list is read by a person, and a title derived from the
			-- opening message goes stale as soon as the thread moves on. The agent has
			-- read the whole conversation, so it is the party that can name what the
			-- thread actually became. A name the user typed is theirs: the loop does
			-- not offer this tool in a named conversation, and the handler refuses as
			-- the second line of defence.
			name = "conversation_rename",
			risk = "read",
			description = "Rename this conversation to a short, specific title based on what it is actually about, so the user can pick the thread out of their list later. Call it once the subject is clear -- usually after the first exchange -- and again only when the work has genuinely moved on. Name the job, not the tools used. Never use it to replace a name the user set themselves; a conversation the user has named is not offered this tool.",
			parameters = {
				type = "object",
				properties = {
					title = {
						type = "string",
						description = "The new title, under about 60 characters: a few specific words, not a sentence.",
					},
				},
				required = { "title" },
			},
			run = function(args, ctx)
				local session = ctx and ctx.session or nil
				if not session then return H.fail("there is no conversation to rename") end
				local ok, result = session.renameByAgent(args.title)
				if not ok then return H.fail(result) end
				return "Conversation renamed to \"" .. tostring(result) .. "\"."
			end,
		},
		{
			-- The model's side of a question it cannot answer from the world. A
			-- permission prompt asks "may I" and the permission layer owns it; this
			-- asks "which" or "what" and the answer is a fact, not a decision about
			-- the agent's own conduct -- so it is a tool result like any other and
			-- rides the same turn, rather than a modal the loop knows about.
			--
			-- Headless is refused in words rather than by omission: a subagent that
			-- asks a question has misunderstood its brief -- nothing it writes reaches
			-- the user directly -- and the message it gets back says so, which teaches
			-- the next dispatch rather than costing it a turn to rediscover.
			name = "ask_user",
			risk = "read",
			-- Not the generic tool timeout. A person is being waited on and people are
			-- slower than any tool; the generic wall would report them as lost. This is
			-- the wall the wait loop below honours, stated once here so the two cannot
			-- drift apart -- the loop gives up a fraction before the registry kills the
			-- call, so the model hears "nobody answered" rather than "did not finish".
			timeout = ASK_TIMEOUT + 5,
			description = "Ask the user one question and wait for their answer. Use when a request is genuinely ambiguous -- two ways to read it, a choice of targets, a preference you cannot infer -- and answering it wrong would waste work. Offer concrete options when the plausible answers are few; omit them for an open question. The answer comes back as this call's result. You cannot ask from a subagent.",
			parameters = {
				type = "object",
				properties = {
					question = {
						type = "string",
						description = "The question itself, one or two sentences, in the words you would use to the user.",
					},
					options = {
						type = "array",
						description = "The concrete answers to pick from, 2 to 4. Omit entirely for an open question.",
						items = { type = "string" },
					},
				},
				required = { "question" },
			},
			run = function(args, ctx)
				local session = ctx and ctx.session or nil
				if session and session.headless then
					return H.fail("a subagent has no user to ask. Answer with your best reading of the task, or state what you could not determine.")
				end
				local question = util.trim(tostring(args.question or ""))
				if question == "" then return H.fail("a question is required") end
				local options = {}
				for index, value in ipairs(type(args.options) == "table" and args.options or {}) do
					local clean = util.trim(tostring(value))
					if clean ~= "" then options[#options + 1] = clean end
					if #options >= 4 then break end
				end
				if #options == 1 then options = {} end

				-- The loop blocks on this thread for as long as the user takes, so the
				-- answer has to come back through a channel the interface can reach: an
				-- event carrying a resolve closure, exactly the shape the permission
				-- prompt already uses. Nothing here trusts a listener to exist -- with
				-- none, the wall is the timeout and the model is told nobody answered.
				local answered, reply = false, nil
				local function resolve(text)
					if answered then return end
					answered = true
					reply = text
				end

				if ctx and ctx.emit then
					ctx.emit("ask:user", {
						id = util.uid("ask"),
						question = question,
						options = options,
						resolve = resolve,
					})
				end

				local waited = 0
				while not answered and waited < (ASK_TIMEOUT) do
					if ctx and ctx.aborted and ctx.aborted() then
						resolve("The turn was stopped before you answered.")
						return "The user stopped the turn. Ask again in a new message if the question still matters."
					end
					waited = waited + (clock.wait(0.1) or 0.1)
				end

				if not answered then
					return "Nobody answered within ten minutes. Continue with your best reading of the request, and say you had to assume an answer."
				end
				local text = util.trim(tostring(reply or ""))
				if text == "" then
					return "The user dismissed the question without answering. Continue with your best reading, and say you had to assume an answer."
				end
				return "The user answered: " .. text
			end,
		},
		{
			name = "memory_write",
			risk = "read",
			description = "Save a durable fact about this user or project under a short key. Survives context compaction and restarts. Use for preferences, paths and goals, not for transcript chatter.",
			parameters = {
				type = "object",
				properties = {
					key = { type = "string", description = "Short snake_case key, e.g. 'preferred_shape' or 'main_build_path'." },
					value = { type = "string", description = "The fact, in one or two sentences." },
				},
				required = { "key", "value" },
			},
			run = function(args)
				local ok, note = state.remember(args.key, args.value)
				if not ok then return H.fail(note) end
				return "Remembered: " .. tostring(note)
			end,
		},
		{
			name = "memory_read",
			risk = "read",
			description = "Read a saved memory by exact key, search keys/values with a literal query, or list all memories. Historical facts may be stale; current instructions and observed state take precedence. Follow returned offsets with the same filters.",
			parameters = {
				type = "object",
				properties = {
					key = { type = "string", description = "Exact key; omit to search or list." },
					query = { type = "string", description = "Case-insensitive literal text in keys or values; omit key when searching." },
					offset = { type = "integer", minimum = 1, description = "Byte offset from the previous page." },
					limit = { type = "integer", minimum = 200, maximum = 64000, description = "Maximum bytes, bounded by the tool result budget." },
				},
				required = {},
			},
			run = function(args)
				local key, query = util.trim(args.key or ""), util.trim(args.query or ""):lower()
				if key ~= "" and query ~= "" then return H.fail("use key or query, not both") end
				if key ~= "" then
					local value = state.recall(key)
					if not value then return "Nothing is stored under '" .. key .. "'." end
					return H.readSlice("Saved memory", key .. ": " .. value, args, 4000)
				end
				local list = state.memoryList()
				if #list == 0 then return "Nothing is remembered yet." end
				local lines = {}
				for _, entry in ipairs(list) do
					if query == "" or tostring(entry.key):lower():find(query, 1, true)
						or tostring(entry.value):lower():find(query, 1, true) then
						lines[#lines + 1] = "- " .. entry.key .. ": " .. entry.value
					end
				end
				if #lines == 0 then return "No memories match that query." end
				return H.readSlice("Saved memories (" .. #lines .. " matches)", table.concat(lines, "\n"), args, 4000)
			end,
		},
		{
			name = "memory_forget",
			risk = "read",
			description = "Delete one remembered key.",
			parameters = {
				type = "object",
				properties = { key = { type = "string" } },
				required = { "key" },
			},
			run = function(args)
				if state.forget(args.key) then return "Forgot '" .. tostring(args.key) .. "'." end
				return "Nothing was stored under '" .. tostring(args.key) .. "'."
			end,
		},
		{
			name = "dispatch_agent",
			risk = "write",
			description = "Start a self-contained task in a background subagent and immediately receive its id. Keep doing your own independent work while it runs; check agent_status periodically and collect its report before your final answer. Give each worker a distinct scope and avoid concurrent edits to the same file or runtime state. A subagent cannot ask questions, so include the full task and completion criteria. Set background=false only when this tool call must wait for the report.",
			timeout = function(args) return args and args.background == false and subagent.toolTimeout() or 10 end,
			parameters = {
				type = "object",
				properties = {
					task = {
						type = "string",
						description = "The complete task, including what counts as a finished answer.",
					},
					preset = {
						type = "string",
						enum = { "read", "web", "game", "full" },
						description = "Which tools it gets. 'read' cannot change anything; 'full' can. Unset uses the configured default, which is 'full'.",
					},
					turns = { type = "integer", description = "Step limit, 1-30. Default 14.", minimum = 1, maximum = 30 },
					background = { type = "boolean", description = "Defaults to true: return an id immediately so you can continue working. False waits for the report." },
				},
				required = { "task" },
			},
			run = function(args, ctx)
				if aborted(ctx) then return H.fail("the turn was stopped before dispatch") end
				local launch = args.background == false and subagent.dispatch or subagent.start
				local result, err = launch({
					parent = ctx and ctx.session or nil,
					-- Which call this is, so the transcript can nest the subagent's live
					-- feed under the row the user is already looking at.
					callId = ctx and ctx.callId or nil,
					task = args.task,
					-- The default preset is a setting, so it can be widened or narrowed once
					-- for every dispatch rather than only when the model names one. Permission
					-- mode still gates what actually runs, and a prompt raised inside a child
					-- is forwarded to the parent's stream.
					preset = args.preset or config.get("agent.subagentPreset", "full"),
					turns = args.turns,
				})
				if not result then return H.fail(err) end
				if args.background ~= false then return backgroundReceipt(result) end
				-- The id, in both branches. Without it the report is a dead end: a child
				-- that stopped at its step limit says so in its own words and the parent
				-- had no way to say "carry on" -- the only move left was to describe the
				-- whole job again to a fresh subagent that knew none of it.
				if result.aborted then
					return string.format("Subagent %s stopped early (%s, %d messages). What it had:\n\n%s",
						result.id, util.formatDuration(result.ms), result.messages, result.text)
				end
				return string.format(
					"Subagent report from %s (%s, %d messages).%s\n\n%s",
					result.id, util.formatDuration(result.ms), result.messages,
					result.resumable and string.format(
						" It kept its context: send it more with agent_followup, agent \"%s\".", result.id) or "",
					result.text)
			end,
		},
		{
			name = "agent_followup",
			risk = "write",
			description = "Continue a completed subagent with its existing context. Returns its id immediately by default; do independent work while it runs, check agent_status periodically and collect the new report. Use the id from dispatch_agent or agent_status. Set background=false only when this call must wait for the answer.",
			timeout = function(args) return args and args.background == false and subagent.toolTimeout() or 10 end,
			parameters = {
				type = "object",
				properties = {
					agent = {
						type = "string",
						description = "The subagent's id, as printed in its report.",
					},
					message = {
						type = "string",
						description = "What you want from it now. It still cannot ask questions, so be complete.",
					},
					turns = {
						type = "integer",
						description = "Step limit for this follow-up, 1-30. Defaults to the configured one.",
						minimum = 1,
						maximum = 30,
					},
					background = { type = "boolean", description = "Defaults to true: return immediately while the follow-up runs. False waits for the answer." },
				},
				required = { "agent", "message" },
			},
			run = function(args, ctx)
				if aborted(ctx) then return H.fail("the turn was stopped before the follow-up") end
				local launch = args.background == false and subagent.followUp or subagent.startFollowUp
				local result, err = launch({
					parent = ctx and ctx.session or nil,
					callId = ctx and ctx.callId or nil,
					id = args.agent,
					task = args.message,
					turns = args.turns,
				})
				if not result then return H.fail(err) end
				if args.background ~= false then return backgroundReceipt(result) end
				if result.aborted then
					return string.format("Subagent %s stopped early (%s). What it had:\n\n%s",
						result.id, util.formatDuration(result.ms), result.text)
				end
				return string.format("Subagent %s answered (%s, %d messages).%s\n\n%s",
					result.id, util.formatDuration(result.ms), result.messages,
					result.resumable and " Still open for another follow-up." or "",
					result.text)
			end,
		},
		{
			name = "agent_status",
			risk = "read",
			description = "Check subagents owned by this conversation. Omit id for compact statuses; give an exact id for current progress or its completed report. Reports and lists use bounded UTF-8 byte pages: follow nextOffset with offset until eof. Check after 2-3 work batches or about 15-30 seconds, while continuing independent work. When no independent work remains, wait_seconds=1-30 waits for a selected child to finish or the deadline; 0 returns immediately. Never tight-poll. Waiting does not stop the children.",
			timeout = 35,
			parameters = {
				type = "object",
				properties = {
					id = { type = "string", description = "Exact subagent id; omit to list this conversation's children without their reports." },
					wait_seconds = { type = "integer", minimum = 0, maximum = 30, description = "0 returns now; 1-30 waits up to that many seconds for one selected live child to finish." },
					offset = { type = "integer", minimum = 1, description = "UTF-8 byte continuation offset from nextOffset; begin at 1." },
					limit = { type = "integer", minimum = 200, maximum = 6000, description = "Maximum page bytes, additionally bounded by the configured tool result budget." },
				},
				required = {},
			},
			run = statusResult,
		},
		{
			name = "wait",
			risk = "read",
			description = "Pause for a few seconds before continuing, to let something in the game settle or a change take effect.",
			parameters = {
				type = "object",
				properties = {
					seconds = { type = "number", description = "0.1 to 10.", minimum = 0.1, maximum = 10 },
				},
				required = { "seconds" },
			},
			run = function(args, ctx)
				local seconds = util.clamp(tonumber(args.seconds) or 1, 0.1, 10)
				local waited = 0
				while waited < seconds do
					if ctx and ctx.aborted and ctx.aborted() then
						return string.format("Waited %.1fs, then stopped.", waited)
					end
					waited = waited + (clock.wait(math.min(0.25, seconds - waited)) or 0.25)
				end
				return string.format("Waited %.1f seconds.", seconds)
			end,
		},
	}
end
