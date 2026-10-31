-- Sessions: the object the interface talks to, and the thread list behind it.
--
-- A session owns a conversation, an event stream and a busy flag. The loop is a
-- pure function over a session, so a subagent is just another session with a
-- smaller tool set and no interface attached -- which is why this module, not the
-- loop, is where threads and persistence live.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local fsx = env.require("runtime/fsx")
	local attachments = env.require("runtime/attachments")
	local log = env.require("runtime/log")
	local signal = env.require("runtime/signal")
	local context = env.require("agent/context")
	local transcript = env.require("agent/transcript")
	local hooks = env.require("agent/hooks")
	local permissions = env.require("agent/permissions")
	local state = env.require("agent/state")
	local folderStore = env.require("runtime/conversation_folders")
	local accounting = env.require("agent/stats")
	local metadata = env.require("runtime/conversation_metadata")
	local draftStore = env.require("runtime/draft_store")
	local transcriptSearch = env.require("runtime/transcript_search")
	local workflow = env.require("runtime/script_workflow")

	local THREAD_DIR = "sessions"
	-- Disk history survives eviction. Unsaved/ephemeral threads stay in memory.
	local THREAD_LIMIT = 64
	local running, alive = 0, true
	local historyBusy = {}
	local function historyIO(id, operation, ...)
		historyBusy[id] = (historyBusy[id] or 0) + 1
		local ok, result, detail = pcall(operation, ...)
		local pending = historyBusy[id] - 1
		historyBusy[id] = pending > 0 and pending or nil
		if not ok then return false, tostring(result) end
		return result, detail
	end
	local function deleteHistory(id)
		return historyIO(id, fsx.delete, THREAD_DIR .. "/" .. id .. ".json")
	end

	-- How long a pasted message may be before it stops being a message. A long script
	-- pasted into the composer is reference material, not a request: sent whole it
	-- drowns the turn, and the model's only use for it is file_read anyway. Over this
	-- the body goes to pastes/ and the conversation carries a pointer -- the user's
	-- words plus "the code is in this file" -- which is the same information for a
	-- fraction of the context.
	local PASTE_CAP = attachments.INLINE_LIMIT

	local M = {
		threads = {},
		activeId = nil,
		listChanged = signal.new("threads"),
		-- Every event from every session, with the session it came from.
		--
		-- A per-session stream is what a panel showing one conversation wants, and it is
		-- what the transcript uses. It is the wrong shape for anything that has to answer
		-- a conversation nobody is looking at -- and the permission prompt is exactly
		-- that: it subscribed to the active session only, so a second conversation left
		-- running in the background raised a prompt into a stream with no listener and sat
		-- there until its own deadline denied every call it had asked for.
		anyEvent = signal.new("session:any"),
		usageChanged = accounting.changed,
	}

	-- Presentation reads recorded counters through the session boundary.
	function M.keyUsage(record, index) return accounting.keyUsage(record, index) end
	function M.conversationUsage(session) return accounting.conversationUsage(session) end

	-- Published for the composer's paste detection, so the two halves of the feature
	-- share one number rather than each keeping a copy that drifts.
	M.PASTE_CAP = PASTE_CAP
	local function markDirty(session)
		session.persistenceDirty = true
		session.persistenceRevision = (session.persistenceRevision or 0) + 1
	end

	local function placeNumber(value)
		local number = tonumber(value)
		return number and number == number and number >= 0 and number < 9007199254740991 and number == math.floor(number) and number or 0
	end

	local function gameFolderId(id) return "game:" .. string.format("%.0f", placeNumber(id)) end
	local function folderPlace(id)
		if type(id) ~= "string" then return nil end
		local raw = id:match("^game:(%d+)$")
		local number = raw and tonumber(raw)
		if number and gameFolderId(number) == id then return number end
		return nil
	end

	local function validDestination(id)
		return type(id) == "string" and (id == "universal" or folderPlace(id) ~= nil or folderStore.get(id) ~= nil)
	end

	local function folderFor(session)
		local place = env.require("runtime/place")
		local id = session.folderId or gameFolderId(session.placeId)
		local placeId = folderPlace(id)
		if placeId ~= nil then
			local current = placeId == place.id
			local label = current and place.label() or nil
			if not label then
				local newest = -1
				for _, candidate in pairs(M.threads) do
					if placeNumber(candidate.placeId) == placeId and type(candidate.placeName) == "string"
						and util.trim(candidate.placeName) ~= "" and (candidate.updatedAt or 0) > newest then
						label, newest = candidate.placeName, candidate.updatedAt or 0
					end
				end
				if not label and placeNumber(session.placeId) == placeId then label = session.placeName end
			end
			if type(label) ~= "string" or util.trim(label) == "" then label = placeId > 0 and ("Place " .. string.format("%.0f", placeId)) or "Unknown place" end
			return { id = id, kind = "game", placeId = placeId, label = label, current = current }
		end
		local folder = folderStore.get(id)
		if folder then folder.current = false; return folder end
		-- Deleted folders also cover archived conversations outside the 64 loaded
		-- threads. Their files need no rewrite, and an unreadable catalog cannot
		-- erase the original association merely because a conversation was saved.
		return { id = "universal", kind = "universal", label = "Universal", current = false }
	end

	local FILTER_OPTIONS = { "toolFilter", "toolGroups", "toolExclude" }
	local POLICY_OPTIONS = { "toolFilter", "toolGroups", "toolExclude", "maxTurns", "budgetSeconds", "unlimited", "stream" }
	local function validateOptions(opts)
		if opts == nil then opts = {} end
		if type(opts) ~= "table" then return nil, "session options must be a table" end
		if opts.id ~= nil and (type(opts.id) ~= "string" or #opts.id > 120 or not opts.id:match("^[%w_-]+$")) then
			return nil, "session id must contain 1-120 letters, digits, underscores or hyphens"
		end
		if opts.title ~= nil and type(opts.title) ~= "string" then return nil, "session title must be a string" end
		if opts.folderId ~= nil and not validDestination(opts.folderId) then return nil, "conversation folder does not exist" end
		for _, key in ipairs({ "ephemeral", "headless", "stream", "unlimited", "activate" }) do
			if opts[key] ~= nil and type(opts[key]) ~= "boolean" then return nil, key .. " must be a boolean" end
		end
		for _, key in ipairs({ "maxTurns", "budgetSeconds", "depth" }) do
			local value = opts[key]
			if value ~= nil then
				if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
					return nil, key .. " must be a finite number"
				end
				if key == "depth" then
					if value < 0 or value ~= math.floor(value) then return nil, "depth must be a nonnegative integer" end
				elseif key == "maxTurns" then
					if value < 1 or value ~= math.floor(value) then return nil, "maxTurns must be a positive integer" end
				elseif value <= 0 then return nil, "budgetSeconds must be positive" end
			end
		end
		local options = util.copy(opts)
		for _, key in ipairs(FILTER_OPTIONS) do
			local filter = opts[key]
			if filter ~= nil then
				if type(filter) ~= "table" then return nil, key .. " must be a map of names to booleans" end
				local copied = {}
				for name, allowed in pairs(filter) do
					if type(name) ~= "string" or util.trim(name) == "" or type(allowed) ~= "boolean" then
						return nil, key .. " must be a map of names to booleans"
					end
					copied[name] = allowed
				end
				options[key] = copied
			end
		end
		return options
	end

	function M.create(opts)
		if not alive then return nil, "client is unloaded" end
		local checked, why = validateOptions(opts)
		if not checked then return nil, why end
		opts = checked
		local place = env.require("runtime/place")
		local session = {
			id = opts.id or util.uid("s"),
			title = opts.title or "New chat",
			ctx = context.new(),
			events = signal.new("session"),
			status = "Ready",
			busy = false,
			depth = opts.depth or 0,
			maxTurns = opts.maxTurns,
			toolFilter = opts.toolFilter,
			toolGroups = opts.toolGroups,
			-- Tools this conversation must not be offered at all -- not denied, absent.
			-- The registry's definitions() reads it; the field is opt-in so a session
			-- that wants everything (the main conversation) does not have to say so.
			toolExclude = opts.toolExclude,
			budgetSeconds = opts.budgetSeconds,
			-- Set by whoever created the session, and read by the loop in place of the
			-- global switch: a subagent carries its own budget, so lifting it is a
			-- decision the dispatcher takes per child rather than one a conversation
			-- inherits from a setting.
			unlimited = opts.unlimited == true,
			stream = opts.stream,
			headless = opts.headless == true,
			ephemeral = opts.ephemeral == true,
			-- Which place the conversation happened in. A client is loaded into one game
			-- at a time and the transcripts outlive the visit, so without this the list
			-- is a flat pile of titles with no way to tell last week's game from this
			-- one. Recorded at creation rather than read at display time, because by the
			-- time anyone reads it they are somewhere else.
			placeId = placeNumber(opts.placeId or place.id),
			placeName = opts.placeName or (placeNumber(opts.placeId or place.id) == place.id and place.label() or nil),
			folderId = opts.folderId or gameFolderId(opts.placeId or place.id),
			createdAt = clock.ms(),
			updatedAt = clock.ms(),
			turns = 0,
			metadata = metadata.restore(),
			viewReaders = {},
			toolEpoch = {},
			abortFlag = false,
			log = {},
			logBytes = 0,
			persistenceDirty = true,
			persistenceRevision = 0,
			-- The plan for this conversation's job. agent/state owns the shape of it;
			-- the list lives here so two conversations cannot overwrite each other's.
			todos = {},
		}
		local queue = env.require("agent/message_queue").new(session, function() if alive then M.listChanged:fire() end end)
		local unloaded = false
		local callbacks, runPrepared, startReady
		local function preparing() session.preparing = queue.preparing() and true or nil end
		local function validateFiles(files, needTools, aborted)
			if #files == 0 and not needTools then return true end
			local readable = false
			for _, tool in ipairs(env.require("agent/registry").definitions({ only = session.toolFilter,
				groups = session.toolGroups, exclude = session.toolExclude })) do
				if tool["function"].name == "file_read" then readable = true; break end
			end
			if not readable then return nil, "Enable the Files tools and file storage to send long inputs as files." end
			for _, file in ipairs(files) do
				local content, err = fsx.readUser(file.path)
				if not content or not env.require("runtime/attachment_identity").matches(file, content, aborted) then return nil, "attachment is missing or changed: " .. file.path .. ". " .. tostring(err or "Attach it again.") end
			end
			return true
		end
		local function takeReady(deadline)
			local access = config.accessProblem()
			if access then queue.hold(access); return nil end
			local head = queue.peek()
			if not head or head.state ~= "queued" or queue.held() then return nil end
			if head.needsValidation then
				local ok, valid, why = pcall(function()
					if #head.images > 0 and not env.require("net/bridge_connection").enabled() then return nil, "Connect the web bridge to resume these images" end
					return validateFiles(head.files, false, function() return not head.active or session.aborted() or deadline and clock.ms() >= deadline end)
				end)
				if not head.active or queue.peek() ~= head then return nil end
				if not ok or not valid then queue.hold(ok and why or "Unable to verify queued attachments"); return nil end
				head.needsValidation = false
			end
			if session.aborted() or deadline and clock.ms() >= deadline then return nil end
			access = config.accessProblem()
			if access then queue.hold(access); return nil end
			return queue.take()
		end

		session.transcript = transcript.new(session)
		session.appendLog = session.transcript.append
		function session.emit(kind, payload)
			if session.removed or not alive then return end
			markDirty(session)
			payload = util.copy(payload or {})
			if kind == "error" then payload.message = env.require("runtime/support").error(payload.message) end
			if kind == "tool:error" or kind == "tool:result" and payload.ok == false then
				payload.text = env.require("runtime/support").error(payload.text or payload.error)
			end
			if kind == "request:done" and payload.error then payload.error = env.require("runtime/support").error(payload.error) end
			payload.kind = kind
			payload.at = clock.ms()
			session.updatedAt = payload.at
			if kind == "status" then session.status = payload.text or session.status end
			if session.acceptingMessages and (kind == "error" or kind == "turn:end" and payload.failed) then
				session.turnFailure = payload.message or payload.text or "The current turn failed"
			end
			if kind == "request:start" then session.liveRequest, session.livePreview = payload, nil
			elseif kind == "assistant:preview" then session.livePreview = payload
			elseif kind == "request:done" then session.liveRequest = nil; if payload.error then session.livePreview = nil end
			elseif kind == "assistant:complete" or kind == "abort" or kind == "error" or kind == "cleared" or (kind == "status" and payload.text == "Ready") then
				session.liveRequest, session.livePreview = nil, nil
			end
			if not session.headless then
				local retained = session.appendLog(payload)
				payload.transcriptId = retained and retained.transcriptId or nil
			end
			local changedMetadata = metadata.observe(session.metadata, payload, next(session.viewReaders) ~= nil)
			hooks.run("onEvent", { session = session, event = payload })
			session.events:fire(payload)
			M.anyEvent:fire(session, payload)
			if changedMetadata then M.listChanged:fire() end
		end

		function session.aborted()
			return session.abortFlag == true or session.removed == true or not alive
		end

		function session.toolContext()
			-- A later send clears abortFlag. Old tool workers must not come back to
			-- life when that happens after a stopped or failed turn.
			local epoch = session.toolEpoch
			local cancelled = false
			local function aborted()
				cancelled = cancelled or session.toolEpoch ~= epoch or session.aborted()
				return cancelled
			end
			return {
				env = env,
				session = session,
				depth = session.depth,
				emit = function(kind, text)
					if not aborted() then session.emit(kind, type(text) == "table" and text or { text = text }) end
				end,
				progress = function(text)
					if not aborted() then session.emit("tool:progress", { text = tostring(text) }) end
				end,
				aborted = aborted,
			}
		end

		function session.queueSnapshot() return queue.snapshot() end
		function session.serialiseQueue() return queue.serialise() end
		function session.restoreQueue(saved)
			local ok, why = queue.restore(saved)
			if ok then markDirty(session) end
			return ok, why
		end
		function session.removeQueued(id)
			local ok, why = queue.remove(id)
			preparing()
			if ok then session.persist() end
			if ok then startReady() end
			return ok, why
		end
		function session.hasQueued() return queue.pending() > 0 end
		local function changeQueue(operation, ...)
			if not alive or session.removed or session.clearingMessages then return false, "Conversation is unavailable" end
			local ok, why = operation(...)
			if ok then session.persist(); startReady() end
			return ok, why
		end
		function session.editQueued(id, text, expected) return changeQueue(queue.edit, id, text, expected) end
		function session.moveQueued(id, direction, neighborId) return changeQueue(queue.move, id, direction, neighborId) end
		function session.clearQueued(ids) return changeQueue(queue.clearSelected, ids) end
		-- Called only after a complete assistant/tool exchange, never while its
		-- inference or native tools are running. A preparing head retains order.
		function session.consumeQueued(waitForPreparation, deadline)
			local count = 0
			while count < 16 and not session.aborted() and not queue.held() do
				local access = config.accessProblem()
				if access then queue.hold(access); break end
				if deadline and clock.ms() >= deadline then break end
				local head = queue.peek()
				if not head then break end
				if head.state == "preparing" then
					if not waitForPreparation then break end
					clock.wait(0.03)
				else
					local entry = takeReady(deadline)
					if not entry then break end
					if entry.onDone and callbacks then callbacks[#callbacks + 1] = { id = entry.id, fn = entry.onDone } end
					session.ctx.pushUser(entry.text, entry.images)
					session.emit("user", { text = entry.text, messageId = entry.id, queued = true })
					queue.consumed(entry)
					count = count + 1
				end
			end
			if count > 0 then session.persist() end
			return count
		end
		function session.resumeQueue()
			if not alive or session.removed then return false, "conversation no longer exists" end
			local access = config.accessProblem()
			if access then return false, access end
			if session.clearingMessages then return false, "conversation is being cleared" end
			if session.cancellingMessages then return false, "conversation is being stopped" end
			if session.busy then return false, "The current turn is still working" end
			if queue.pending() == 0 then return false, "No queued messages to resume" end
			if running >= 8 then return false, "Eight native session workers are already active; wait for a turn to finish" end
			queue.release()
			if not queue.peek() or queue.peek().state == "preparing" or session.busy then return true end
			return startReady()
		end

		-- A single worker owns context and tools. Further sends reserve a pending
		-- message and join that worker only at a safe response/tool boundary.
		function session.send(text, onDone, files, images, options)
			if not alive then return false, "client is unloaded" end
			local access = config.accessProblem()
			if access then return false, access end
			if session.removed then return false, "conversation no longer exists" end
			if session.clearingMessages then return false, "conversation is being cleared" end
			if session.cancellingMessages then return false, "conversation is being stopped" end
			if onDone ~= nil and type(onDone) ~= "function" then return false, "completion callback must be a function" end
			if options ~= nil and type(options) ~= "table" then return false, "invalid send options" end
			options = options or {}
			for key in pairs(options) do if key ~= "messageId" then return false, "unknown send option: " .. tostring(key) end end
			if options.messageId ~= nil and type(options.messageId) ~= "string" then return false, "invalid message id" end
			local id = options.messageId or util.uid("message")
			local receipt = queue.receipt(id)
			if receipt then return true, receipt end
			if session.busy and (not session.acceptingMessages or session.abortFlag) then return false, "Wait for the current operation to finish stopping" end
			if not session.busy and running >= 8 then return false, "Eight native session workers are already active; wait for a turn to finish" end
			text = tostring(text or "")
			if #text > attachments.MAX_BYTES then return false, "attachments support up to 10 MiB; split this input into smaller files" end
			local validated, imageError = env.require("runtime/images").validate(images, session.id)
			if not validated then return false, imageError end
			images = validated
			if #images > 0 and not env.require("net/bridge_connection").enabled() then return false, "Connect the web bridge to send these images" end
			local clean = util.trim(text)
			if clean == "" and #images > 0 then clean = "Please look at the attached " .. (#images == 1 and "image." or "images."); text = clean end
			if clean == "" then return false, "nothing to send" end
			files = files or {}
			if type(files) ~= "table" or not util.isArray(files) or #files > 32 then return false, "invalid attachment list" end
			local references = {}
			for _, file in ipairs(files) do
				if type(file) ~= "table" or type(file.path) ~= "string" or #file.path == 0 or #file.path > 1000
					or type(file.bytes) ~= "number" or file.bytes ~= file.bytes or file.bytes < 0 or file.bytes % 1 ~= 0
					or file.bytes > attachments.MAX_BYTES then return false, "invalid attachment reference" end
				if file.sha256 ~= nil and not env.require("runtime/attachment_identity").valid(file.sha256) then return false, "invalid attachment digest" end
				references[#references + 1] = { path = file.path, bytes = file.bytes, sha256 = file.sha256 }
			end
			files = references

			local title = util.ellipsis(clean, 42)
			local resumeHeld = not session.busy and queue.held()
			local entry, reserveError = queue.reserve(clean, files, images, onDone, id, session.busy or queue.pending() > 0, #text)
			if not entry then return false, reserveError end
			files = entry.files
			local function preparationAborted() return not alive or session.removed or not entry.active end
			preparing()
			-- This boundary also covers Quick Chat, bridge clients and host scripts.
			-- Never turn a failed upload into an enormous inference request.
			if #text > PASTE_CAP or #files > 0 then
				local ok, prepared, why = pcall(function()
					local valid, validationError = validateFiles(files, #text > PASTE_CAP, preparationAborted)
					if not valid then return nil, validationError end
					if #text <= PASTE_CAP then return clean end
					local saved, err = attachments.save(text, nil, preparationAborted)
					if not saved then return nil, err end
					if #entry.files >= 32 then return nil, "A message supports up to 32 file attachments" end
					entry.files[#entry.files + 1] = { path = saved.path, bytes = saved.bytes, sha256 = saved.sha256 }
					return attachments.reference(saved) .. "\n\nRead this file for the user's complete input, including any request at the end."
				end)
				if not entry.active then preparing(); return false, "message preparation was cancelled; your draft was kept" end
				if not ok or not prepared then
					local failure = ok and why or tostring(prepared)
					queue.reject(entry, failure); preparing(); startReady(); return false, failure
				end
				clean = prepared
			end
			access = config.accessProblem()
			if access then queue.reject(entry, access); preparing(); return false, access end
			local accepted, commitError = queue.commit(entry, clean)
			preparing()
			if not accepted then queue.reject(entry, commitError); preparing(); startReady(); return false, commitError end
			if session.title == "New chat" and not session.named then session.title = title end
			session.persist()
			if not session.busy and not queue.held() then startReady()
			elseif not session.busy and resumeHeld then session.resumeQueue() end
			return true, accepted
		end

		startReady = function()
			if not alive or session.removed or session.clearingMessages or session.busy or queue.held() then return false end
			local head = queue.peek()
			if not head or head.state ~= "queued" then return false end
			local started, why = runPrepared()
			if not started then queue.hold(why) end
			return started, why
		end

		runPrepared = function()
			if not alive or session.removed then return false, "conversation no longer exists" end
			local access = config.accessProblem()
			if access then return false, access end
			if session.busy then return false, "already working" end
			if running >= 8 then return false, "Eight native session workers are already active; wait for a turn to finish" end
			local head = queue.peek()
			if not head or head.state ~= "queued" or queue.held() then return false, "The first queued message is still being prepared" end
			running = running + 1
			session.busy = true
			session.acceptingMessages = true
			session.turnFailure = nil
			session.abortFlag = false
			session.toolEpoch = {}
			local completed = {}
			callbacks = completed
			-- The list is where "this one is still working" is visible while you are
			-- reading another conversation, so a busy flag that moves is a list change.
			M.listChanged:fire()

			task.spawn(function()
				local ok, reply = pcall(function()
					local entry = takeReady()
					if not entry then return nil end
					session.turns = session.turns + 1
					if entry.onDone then completed[#completed + 1] = { id = entry.id, fn = entry.onDone } end
					session.emit("user", { text = entry.text, messageId = entry.id, queued = entry.queued })
					queue.consumed(entry)
					return env.require("agent/loop").run(session, entry.text, entry.images)
				end)
				if not ok then session.abortFlag = true end
				if not ok then session.turnFailure = "The native agent stopped after an internal error" end
				-- A turn owns its background children through its terminal settlement,
				-- including limits and provider failures. Intermediate tools do not end
				-- that lifetime; normal completion has already collected their reports.
				local subagents = env.loadedModules and env.loadedModules["agent/subagent"]
				if subagents then
					local unfinished = #subagents.pending(session) > 0
					subagents.stopAll(session)
					if unfinished then session.toolEpoch = {} end
				end
				session.acceptingMessages = false
				if callbacks == completed then callbacks = nil end
				local finalStatus = not ok and "failed" or session.abortFlag and "cancelled" or session.turnFailure and "failed" or "succeeded"
				if queue.pending() > 0 and finalStatus ~= "succeeded" then queue.hold(finalStatus == "cancelled" and "Stopped before these follow-ups were applied" or session.turnFailure) end
				if session.removed or not alive then running = math.max(0, running - 1); session.busy = false; return end
				-- Only this conversation's prompts. It used to clear every pending
				-- request in the client, so one conversation finishing a turn silently
				-- denied whatever another was waiting on -- and a denied write is
				-- reported to that model as the user refusing it.
				permissions.denyAll(nil, session)
				-- Its questions too: a turn that ended still had an ask on screen, which
				-- the user could then answer for a conversation that had moved on.
				local asks = env.loadedModules and env.loadedModules["ui/panels/ask"]
				if asks then pcall(asks.sweep, session) end
				if not ok then
					log.error("session", "loop crashed", reply)
					session.emit("error", { message = "The native agent stopped after an internal error", fatal = true })
					reply = "The native agent stopped after an internal error. Your conversation is retained."
					session.emit("turn:end", { text = reply, failed = true })
					session.emit("status", { text = "Ready" })
				end
				M.persist(session)
				running = math.max(0, running - 1)
				session.busy = false
				M.listChanged:fire()
				for _, callback in ipairs(completed) do
					if not session.removed then pcall(callback.fn, reply, { messageId = callback.id,
						status = finalStatus }) end
				end
				-- Terminal-event sends belong to the next turn. Start only after this
				-- worker's cleanup and callbacks; a preparing head starts on commit.
				startReady()
			end)
			return true
		end

		function session.abort()
			if session.cancellingMessages or unloaded then return false end
			if not alive then unloaded = true end
			session.cancellingMessages = true
			session.toolEpoch = {}
			session.abortFlag = not alive or session.busy == true
			local wasPreparing = queue.preparing()
			queue.cancelPreparations("message preparation was cancelled; your draft was kept")
			preparing()
			if session.removed or not alive then
				-- Idle saved histories need no serialization on unload. Save pending
				-- follow-ups once before cancelling their in-memory callbacks.
				if not session.removed and session.persistenceDirty then session.persist() end
				queue.clear(session.removed and "conversation removed" or "client unloaded")
			else
				queue.hold("Stopped before these follow-ups were applied")
				session.persist()
			end
			local capture = env.loadedModules and env.loadedModules["runtime/remote_capture"]
			if capture then capture.revokeAgent(session.id) end
			local subagents = env.loadedModules and env.loadedModules["agent/subagent"]
			local stoppedChildren = subagents and subagents.stopAll(session) or 0
			local loops = env.loadedModules and env.loadedModules["runtime/chatloops"]
			local stoppedLoops = loops and loops.stop(nil, session) or 0
			if not session.busy then session.cancellingMessages = nil; return wasPreparing or stoppedLoops > 0 or stoppedChildren > 0 end
			session.abortFlag = true
			session.emit("status", { text = "Stopping" })
			permissions.denyAll("aborted", session)
			local asks = env.loadedModules and env.loadedModules["ui/panels/ask"]
			if asks then pcall(asks.sweep, session) end
			session.cancellingMessages = nil
			return true
		end

		-- Fold older turns into the summary now, on the user's command, without
		-- starting a turn. Reuses the busy interlock so a send cannot interleave with
		-- the mutation, and persists the trimmed conversation when it changes.
		function session.compact(onDone)
			local access = config.accessProblem()
			if access then return false, access end
			if session.busy or session.preparing then return false, "already working" end
			if session.removed then return false, "conversation no longer exists" end
			if not alive or running >= 8 then return false, "Eight native session workers are already active; wait for a turn to finish" end
			running = running + 1
			session.busy = true
			session.abortFlag = false
			session.emit("status", { text = "Compacting" })
			M.listChanged:fire()
			task.spawn(function()
				local ok, summary, reason = pcall(function()
					local note, before, after, why = env.require("agent/loop").compact(session)
					return note, why
				end)
				running = math.max(0, running - 1)
				session.busy = false
				if session.removed or not alive then return end
				session.emit("status", { text = "Ready" })
				if not ok then log.error("session", "manual compaction crashed", summary) end
				if ok and summary then M.persist(session) end
				M.listChanged:fire()
				if onDone then pcall(onDone, ok and summary ~= nil, ok and summary or nil, ok and reason or tostring(summary)) end
			end)
			return true
		end

		function session.clear()
			if session.busy then return false, "Stop this turn before clearing its conversation" end
			session.clearingMessages = true
			queue.clear("conversation cleared")
			session.preparing = nil
			attachments.clearUploads(session.id)
			local loops = env.loadedModules and env.loadedModules["runtime/chatloops"]
			if loops then loops.stop(nil, session) end
			local subagents = env.loadedModules and env.loadedModules["agent/subagent"]
			if subagents then subagents.stopAll(session) end
			session.ctx.clear()
			session.transcript.reset()
			session.viewState = nil
			session.turns = 0
			session.toolEpoch = {}
			session.abortFlag = false
			session.title = "New chat"
			session.workflow = nil
			-- The plan goes with the conversation it belonged to.
			state.clearTodos(session)
			session.emit("cleared", {})
			session.emit("status", { text = "Ready" })
			M.persist(session)
			session.clearingMessages = nil
		end

		-- A title the user typed wins over the one derived from the first message, and
		-- keeps winning: the derivation only ever fires while the title is still the
		-- placeholder.
		function session.rename(title)
			local clean = util.ellipsis(util.trim(title), 60)
			if clean == "" then return false, "a conversation needs a title" end
			session.title = clean
			session.named = true
			M.listChanged:fire()
			M.persist(session)
			return true
		end

		function session.setPinned(value)
			if session.removed then return false end
			session.metadata.pinned = value == true
			markDirty(session); M.listChanged:fire(); session.persist()
			return true
		end
		function session.markRead()
			if not metadata.read(session.metadata) then return false end
			markDirty(session); M.listChanged:fire()
			return true
		end
		function session.setViewed(owner, value)
			if owner == nil then return end
			session.viewReaders[owner] = value == true and true or nil
			if value then session.markRead() end
		end
		local saveDraftLater, cancelDraftSave = clock.debounce(function()
			if alive and not session.removed then session.persist() end
		end, 1.5)
		session.cancelDraftSave = cancelDraftSave
		local saveWorkflowLater, cancelWorkflowSave = clock.debounce(function()
			if alive and not session.removed then session.persist() end
		end, 0.5)
		session.cancelWorkflowSave = cancelWorkflowSave
		function session.setDraft(value)
			if session.removed or not alive then return false, "Conversation is unavailable" end
			local saved, why = draftStore.snapshot(value)
			if why then session.draftError = why; return false, why end
			local changedPresence = (session.draft ~= nil) ~= (saved ~= nil)
			session.draft, session.draftError = saved, nil
			markDirty(session); saveDraftLater()
			if changedPresence then M.listChanged:fire() end
			return true
		end
		function session.searchTranscript(query, options) return transcriptSearch.page(session.log, query, options) end
		function session.setWorkflow(value, options)
			if session.removed or not alive then return false, "Conversation is unavailable" end
			local validated, why = workflow.restore(value)
			if value ~= nil and not validated then return false, why or "Invalid script workflow" end
			session.workflow = validated
			session.emit("workflow:changed", { version = 1 })
			M.listChanged:fire()
			if options and options.deferSave == true then saveWorkflowLater()
			else cancelWorkflowSave(); session.persist() end
			return true
		end

		-- A title the agent chose for the thread, from what it turned out to be
		-- about. Deliberately not `rename`: naming the conversation stays the
		-- user's move, so a name they typed is refused outright and `named` is
		-- left alone -- another turn may refine the agent's own title, and the
		-- first-message fallback still belongs to the user, not to the agent.
		function session.renameByAgent(title)
			if session.named then return false, "the user named this conversation" end
			if session.headless then return false, "a subagent has no conversation title to set" end
			local clean = util.ellipsis(util.trim(tostring(title or "")), 60)
			if clean == "" then return false, "a title is required" end
			if clean == session.title then return true, clean end
			session.title = clean
			M.listChanged:fire()
			M.persist(session)
			return true, clean
		end

		-- Nothing about this conversation is written to disk. The composer's isolation
		-- toggle is what turns it on, for the same reason a worktree exists: somewhere
		-- to try something without it becoming part of the history.
		function session.setEphemeral(value)
			if session.removed or not alive then return false end
			session.ephemeral = value == true
			if session.ephemeral and fsx.enabled then
				deleteHistory(session.id)
			else
				M.persist(session)
			end
			M.listChanged:fire()
			return session.ephemeral
		end

		-- Mid-turn checkpoint. A turn used to reach disk only when it settled, so a
		-- host crash during a long tool run lost the prompt and every completed step.
		-- The loop calls this at step boundaries; M.persist still refuses headless,
		-- child, ephemeral and removed sessions, and a failed write never ends a turn.
		function session.persist()
			local ok, saved = pcall(M.persist, session)
			if not ok then log.warn("session", "checkpoint failed", saved) end
			return ok and saved or false
		end

		function session.stats()
			local stats = session.ctx.stats()
			stats.busy = session.busy
			stats.turns = session.turns
			stats.todos = state.todoCounts(session)
			return stats
		end

		return session
	end

	-- Threads ---------------------------------------------------------------

	function M.current()
		if not alive then return nil, "client is unloaded" end
		if M.activeId and M.threads[M.activeId] then return M.threads[M.activeId] end
		return M.newThread()
	end

	function M.newThread(opts)
		if opts ~= nil and type(opts) ~= "table" then return nil, "session options must be a table" end
		if opts and opts.id ~= nil and M.threads[opts.id] then return nil, "session id already exists" end
		local session, why = M.create(opts)
		if not session then return nil, why end
		if M.threads[session.id] then return nil, "session id already exists" end
		if historyBusy[session.id] then return nil, "session history is still being saved or removed; try again shortly" end
		if fsx.enabled and fsx.exists(THREAD_DIR .. "/" .. session.id .. ".json") then
			return nil, "session id already exists on disk but is not loaded; choose a different id"
		end
		M.threads[session.id] = session
		if not opts or opts.activate ~= false then M.activeId = session.id end
		M.trimThreads(session)
		M.listChanged:fire()
		return session
	end

	function M.get(id)
		if not alive or type(id) ~= "string" then return nil end
		local session = M.threads[id]
		return session and not session.removed and session or nil
	end

	-- Open a stable host identity without replacing a live worker or stealing the
	-- native view's selection. Options apply only when the conversation is created.
	function M.open(id, opts)
		if not alive then return nil, "client is unloaded" end
		if type(id) ~= "string" or #id > 120 or not id:match("^[%w_-]+$") then
			return nil, "session id must contain 1-120 letters, digits, underscores or hyphens"
		end
		local options, why = validateOptions(opts)
		if not options then return nil, why end
		local existing = M.get(id)
		if existing then
			if options.activate == true then M.switch(id) end
			return existing, false
		end
		options.id, options.activate = id, options.activate == true
		local session, createdWhy = M.newThread(options)
		if not session then return nil, createdWhy end
		return session, true
	end

	function M.switch(id)
		if not M.threads[id] then return false end
		M.activeId = id
		M.threads[id].markRead()
		M.listChanged:fire()
		return true
	end

	function M.list()
		local out = {}
		for _, session in pairs(M.threads) do out[#out + 1] = session end
		table.sort(out, function(a, b)
			local ap, bp = a.metadata and a.metadata.pinned == true, b.metadata and b.metadata.pinned == true
			if ap ~= bp then return ap end
			if a.updatedAt ~= b.updatedAt then return (a.updatedAt or 0) > (b.updatedAt or 0) end
			return a.id < b.id
		end)
		return out
	end

	-- The conversations currently running a turn, newest activity first.
	--
	-- Switching conversation does not stop the one you left -- its loop is on its own
	-- thread and keeps going -- so more than one can be working at a time, and the
	-- interface needs to be able to say which. Anything that reads "is the agent
	-- busy" from the active session alone is asking the wrong question.
	function M.busy()
		local out = {}
		for _, session in ipairs(M.list()) do
			if session.busy then out[#out + 1] = session end
		end
		return out
	end

	function M.busyCount()
		return #M.busy()
	end

	-- Folder organization never changes a conversation's recorded game or the
	-- runtime environment sent to the model. Empty destinations remain reachable.
	function M.groups()
		local place = env.require("runtime/place")
		local byId, order = {}, {}
		local function add(folder)
			if byId[folder.id] then return byId[folder.id] end
			folder.current = folder.current == true
			folder.sessions, folder.updatedAt = {}, 0
			byId[folder.id], order[#order + 1] = folder, folder
			return folder
		end
		add(folderFor({ folderId = gameFolderId(place.id) }))
		add(folderFor({ folderId = "universal" }))
		for _, folder in ipairs(folderStore.list()) do add(folder) end
		for _, session in ipairs(M.list()) do
			local group = add(folderFor(session))
			group.sessions[#group.sessions + 1] = session
			if (session.updatedAt or 0) > group.updatedAt then group.updatedAt = session.updatedAt or 0 end
		end
		table.sort(order, function(a, b)
			if a.current ~= b.current then return a.current end
			if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
			if tostring(a.label) ~= tostring(b.label) then return tostring(a.label) < tostring(b.label) end
			return a.id < b.id
		end)
		return order
	end

	function M.folders()
		local out = {}
		for _, group in ipairs(M.groups()) do
			out[#out + 1] = { id = group.id, label = group.label, kind = group.kind, current = group.current, placeId = group.placeId }
		end
		return out
	end

	function M.folderLabel(sessionOrId)
		local session = type(sessionOrId) == "table" and sessionOrId or M.get(sessionOrId)
		return session and folderFor(session).label or nil
	end

	function M.createFolder(name)
		if not alive then return nil, "client is unloaded" end
		local folder, why = folderStore.create(name)
		if folder then M.listChanged:fire() end
		return folder, why
	end

	function M.renameFolder(id, name)
		if not alive then return false, "client is unloaded" end
		local ok, why = folderStore.rename(id, name)
		if ok then M.listChanged:fire() end
		return ok, why
	end

	function M.removeFolder(id)
		if not alive then return false, "client is unloaded" end
		local ok, why = folderStore.remove(id)
		if not ok then return false, why end
		for _, session in pairs(M.threads) do
			if session.folderId == id then session.folderId = "universal" end
		end
		M.listChanged:fire()
		return true
	end

	function M.moveToFolder(sessionOrId, folderId)
		if not alive then return false, "client is unloaded" end
		local session = type(sessionOrId) == "table" and sessionOrId or M.get(sessionOrId)
		if not session or M.get(session.id) ~= session then return false, "conversation no longer exists" end
		if not validDestination(folderId) then return false, "conversation folder does not exist" end
		if session.folderId == folderId then return true end
		local previous = session.folderId
		session.folderId = folderId
		if fsx.enabled and not session.ephemeral and not session.headless and session.depth == 0 then
			local ok, why = M.persist(session)
			if not ok then session.folderId = previous; return false, why or "conversation could not be saved" end
		end
		M.listChanged:fire()
		return true
	end

	-- Title, then the transcript. A search that only matched titles would miss the
	-- conversation you remember by something that was said in it.
	function M.search(query)
		if util.trim(tostring(query or "")) == "" then return {} end
		local out = {}
		for _, session in ipairs(M.list()) do
			local hit = env.require("runtime/conversation_search").find(session, M.folderLabel(session), query)
			if hit then hit.session = session; out[#out + 1] = hit end
		end
		return out
	end

	function M.remove(id)
		local session = M.threads[id]
		if not session then return false end
		session.preparing, session.removed = nil, true
		session.cancelDraftSave()
		session.cancelWorkflowSave()
		attachments.clearUploads(id)
		session.abort(); session.events:clear()
		local subagents = env.loadedModules and env.loadedModules["agent/subagent"]
		if subagents then subagents.stopAll(session) end
		M.threads[id] = nil
		if fsx.enabled then deleteHistory(id) end
		local evidence = env.loadedModules and env.loadedModules["runtime/evidence"]
		if evidence then pcall(evidence.clear, session) end
		if M.activeId == id then
			local remaining = M.list()
			M.activeId = remaining[1] and remaining[1].id or nil
			if not M.activeId then M.newThread() end
		end
		M.listChanged:fire()
		return true
	end

	function M.trimThreads(protected)
		local ordered = M.list()
		local excess = #ordered - THREAD_LIMIT
		for index = #ordered, 1, -1 do
			if excess <= 0 then break end
			local victim = ordered[index]
			if victim ~= protected and not victim.busy and not victim.preparing and victim.id ~= M.activeId and fsx.enabled and M.persist(victim) then
				victim.removed = true; victim.cancelDraftSave(); victim.cancelWorkflowSave()
				victim.abort(); victim.events:clear(); M.threads[victim.id] = nil
				excess = excess - 1
				attachments.clearUploads(victim.id)
				local evidence = env.loadedModules and env.loadedModules["runtime/evidence"]
				if evidence then pcall(evidence.clear, victim) end
				local subagents = env.loadedModules and env.loadedModules["agent/subagent"]
				if subagents then subagents.stopAll(victim) end
			end
		end
	end

	-- Persistence is best-effort by design: a host with no filesystem simply keeps
	-- everything in memory for the session, and nothing above here cares.
	--
	-- The transcript goes in the file as well as the context. It did not, and the
	-- consequence was the one thing about restored conversations anybody would notice:
	-- the sidebar listed them, switching to one worked, and the panel showed the
	-- greeting card -- because the transcript is a pure function of `session.log` and
	-- `log` was the one field restore left empty. `ctx.serialise` is not a substitute:
	-- it keeps what the *model* needs to continue, which has no reasoning, no timings,
	-- no risk levels and no tool arguments.
	function M.persist(session)
		if not fsx.enabled or session.headless or session.removed then return false end
		if session.depth and session.depth > 0 then return false end
		if session.ephemeral then return false end
		markDirty(session)
		local savedPolicy = {}
		for _, key in ipairs(POLICY_OPTIONS) do savedPolicy[key] = session[key] end
		local policy, why = validateOptions(savedPolicy)
		if not policy then return false, "invalid session policy: " .. tostring(why) end
		policy.version = 1
		return env.require("agent/checkpoint").write(session, function()
			local snapshot = {
				id = session.id,
				title = session.title,
				named = session.named == true,
				placeId = session.placeId,
				placeName = session.placeName,
				folderId = session.folderId,
				updatedAt = session.updatedAt,
				createdAt = session.createdAt,
				turns = session.turns, opencodeSession = session.opencodeSession,
				policy = policy,
				queue = session.serialiseQueue(),
				metadata = metadata.snapshot(session.metadata),
				draft = draftStore.snapshot(session.draft),
				workflow = workflow.snapshot(session.workflow),
				todos = env.require("runtime/todo_snapshot").snapshot(session.todos),
				context = session.ctx.serialise(),
				transcript = session.transcript.snapshot(),
				transcriptState = session.transcript.metadata(),
			}
			return historyIO(session.id, function()
				local path = THREAD_DIR .. "/" .. session.id .. ".json"
				local ok, saved, reason = pcall(fsx.writeJson, path, snapshot)
				-- A host write may yield across no-save or removal. Keep this id
				-- reserved until the old snapshot has been removed again.
				if session.ephemeral or session.removed then
					local deleted, deleteWhy = deleteHistory(session.id)
					if not deleted and fsx.exists(path) then log.warn("session", "could not remove conversation history", deleteWhy) end
					return false, "Conversation history is no longer saved"
				end
				if not ok then return false, tostring(saved) end
				return saved, reason
			end)
		end, function()
			clock.delay(0, function() if alive and not session.removed then session.persist() end end)
		end)
	end

	function M.restore()
		if not fsx.enabled then return 0 end
		local restored, candidates = 0, {}
		local function timestamp(value)
			local number = tonumber(value)
			return number and number == number and number > 0 and number < math.huge and number or 0
		end
		local function readThread(entry)
			if entry.isDir or not entry.name:match("%.json$") then return nil end
			local raw = fsx.read(entry.path)
			local data = raw and #raw <= 12 * 1024 * 1024 and util.decode(raw)
			if type(data) ~= "table" or type(data.id) ~= "string" or #data.id > 120
				or not data.id:match("^[%w_-]+$") or entry.name ~= data.id .. ".json" then return nil end
			if data.policy ~= nil then
				local policy = data.policy
				if type(policy) ~= "table" or policy.version ~= 1 then
					log.warn("session", "skipped saved conversation with unsupported policy", data.id)
					return nil
				end
				local options = {}
				for _, key in ipairs(POLICY_OPTIONS) do options[key] = policy[key] end
				local validated, why = validateOptions(options)
				if not validated then
					log.warn("session", "skipped saved conversation with invalid policy", data.id .. ": " .. tostring(why))
					return nil
				end
				data.policy = validated
			end
			return data
		end
		-- Keep only candidate metadata while finding the newest files; a host listing
		-- is alphabetic, not ordered by conversation activity.
		for _, entry in ipairs(fsx.list(THREAD_DIR)) do
			local data = readThread(entry)
			if data and not M.threads[data.id] then
				candidates[#candidates + 1] = { entry = entry, id = data.id, updatedAt = timestamp(data.updatedAt), pinned = metadata.restore(data.metadata).pinned }
				table.sort(candidates, function(a, b)
					if a.pinned ~= b.pinned then return a.pinned end
					if a.updatedAt ~= b.updatedAt then return a.updatedAt > b.updatedAt end
					return a.id < b.id
				end)
				if #candidates > THREAD_LIMIT then table.remove(candidates) end
			end
		end
		local slots = math.max(0, THREAD_LIMIT - #M.list())
		for index = 1, math.min(slots, #candidates) do
			local candidate = candidates[index]
			local data = readThread(candidate.entry)
			if data and data.id == candidate.id and not M.threads[data.id] then
				local options = data.policy or {}
				options.id = data.id
				options.title = type(data.title) == "string" and util.ellipsis(data.title, 60) or nil
				options.placeId = placeNumber(data.placeId)
				options.placeName = type(data.placeName) == "string" and data.placeName or nil
				local session = M.create(options)
				if type(data.folderId) == "string" and #data.folderId <= 120 then
					session.folderId = data.folderId
				end
				session.named = data.named == true
				session.metadata = metadata.restore(data.metadata)
				session.draft = draftStore.restore(data.draft)
				session.workflow = workflow.restore(data.workflow)
				session.todos = env.require("runtime/todo_snapshot").restore(data.todos)
				session.createdAt = timestamp(data.createdAt)
				session.updatedAt = timestamp(data.updatedAt)
				session.turns = math.floor(timestamp(data.turns)); session.opencodeSession = data.opencodeSession
				local queueOk, queueError = session.restoreQueue(data.queue)
				if queueOk then
					session.ctx.restore(data.context)
					session.transcript.restore(data.transcript, session.ctx, data.transcriptState)
					session.persistenceDirty = false
					M.threads[session.id] = session
					restored = restored + 1
				else log.warn("session", "skipped saved conversation with invalid follow-ups", queueError) end
			end
		end
		if restored > 0 then
			local ordered = M.list()
			M.activeId = ordered[1] and ordered[1].id or nil
			log.info("session", util.pluralise(restored, "conversation") .. " restored")
			M.listChanged:fire()
		end
		return restored
	end

	M.limits = { threads = THREAD_LIMIT, folders = folderStore.limit, folderNameBytes = folderStore.nameBytes, workers = 8, events = transcript.limits.events,
		transcriptBytes = transcript.limits.bytes, transcriptBudgets = transcript.limits.budgets }
	function M.beginShutdown()
		if not alive then return end
		alive = false
		-- Close admission and invalidate every turn before any save can yield.
		for _, item in pairs(M.threads) do item.abortFlag = true; item.toolEpoch = {}; item.cancelDraftSave(); item.cancelWorkflowSave() end
	end
	env.require("runtime/dispose").add(function()
		M.beginShutdown()
		local slice = clock.ms()
		for _, item in pairs(M.threads) do
			local ok, why = pcall(item.abort)
			item.events:clear()
			if not ok then log.warn("session", "unload cleanup failed", why) end
			-- Many newly changed histories still need saving. Give Roblox a frame
			-- between batches; never close a native worker or wait for it to finish.
			if coroutine.running() and clock.since(slice) >= 8 then clock.wait(); slice = clock.ms() end
		end
		M.anyEvent:clear(); M.listChanged:clear()
	end, "native sessions")
	return M
end
