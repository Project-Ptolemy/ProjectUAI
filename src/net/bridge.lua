-- The game half of the web bridge.
--
-- A Roblox client cannot listen for a connection, so it cannot be talked to -- it
-- can only talk. This module is therefore a client of a small local process
-- (bridge/server.js) rather than a server: it pushes the session's events up and
-- long-polls for anything typed in the browser.
--
-- Two threads, because the two directions have different rhythms. Events must
-- leave promptly and in order, so they are batched off a queue every fraction of a
-- second. Commands arrive rarely, so that direction is one request held open for
-- eighteen seconds at a time -- which reads as instant and costs three requests a
-- minute, where a busy poll would cost hundreds.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local config = env.require("runtime/config")
	local dispose = env.require("runtime/dispose")
	local caps = env.require("runtime/caps")
	local http = env.require("net/http")
	local signal = env.require("runtime/signal")
	local connection = env.require("net/bridge_connection")

	-- Fired on a state transition only -- started, stopped, reachable, unreachable --
	-- so the Settings panel can show the truth without polling for it.
	local M = { running = false, online = false, lastError = nil, changed = signal.new("bridge") }
	local clientId = env.services.HttpService:GenerateGUID(false)
	local alive, generation = false, 0
	local opencode, nextHello, bridgeInstance = nil, 0, nil
	local kiloStatus = env.require("net/kilo_status")
	local kilo
	local cline
	local opencodeModels = {}
	local clineModelIds = {}
	local clineStates = { disabled = true, missing = true, starting = true, ["auth-required"] = true, ready = true, failed = true }
	local capability = env.require("net/capability")
	local opencodeStates = { disabled = true, missing = true, starting = true, ready = true, failed = true, stopped = true }
	local function readCline(value)
		local state = capability.read(value, clineStates)
		if state and state.message == "" then state.message = "Check the Cline connection in the Windows app's Tunnels tab." end
		return state
	end
	local uploadFailed, pollFailed = false, false
	local function syncRuntime()
		local value = M.online and "web" or "game"
		if config.get("bridge.runtime") ~= value then config.set("bridge.runtime", value, { transient = true }) end
	end

	-- Queue bounds limit offline buffering; event text itself stays lossless so
	-- Markdown, code listings, and streamed finals agree between both interfaces.
	local QUEUE_CAP = 200
	local DRAIN_SECONDS = 0.15
	local POLL_TIMEOUT = 25

	-- What the browser renders. Everything else -- reasoning, usage, request and turn
	-- bookkeeping, compaction -- stays in the client, so a thinking block does not
	-- travel over the wire to be discarded on arrival.
	local FORWARD = {
		["user"] = true,
		["assistant:text"] = true,
		["tool:call"] = true,
		["tool:result"] = true,
		["tool:error"] = true,
		["tool:progress"] = true,
		["status"] = true,
		["model:route"] = true,
		["error"] = true,
		["abort"] = true,
		["cleared"] = true,
		["provider:switch"] = true,
		["permission:ask"] = true,
		["subagent:start"] = true,
		["subagent:done"] = true,
		-- The running commentary around a turn. None of it is conversation, but the
		-- browser's telemetry, latency readouts and live subagent cards are built
		-- from exactly these.
		["assistant:reasoning"] = true,
		["request:start"] = true,
		["request:retry"] = true,
		["request:done"] = true,
		["usage"] = true,
		["turn:start"] = true,
		["turn:end"] = true,
		["compact"] = true,
		["ask:user"] = true,
		["subagent:text"] = true,
		["subagent:tool"] = true,
		["subagent:tool:done"] = true,
	}

	-- Event payloads are not automatically safe to encode. `permission:ask` carries
	-- the resolve function the in-game panel calls, and signal.lua exists precisely
	-- so that payloads like it can hold non-serialisable values. Anything that is
	-- not a string, number, boolean or table is dropped rather than encoded.
	local function scrub(value, depth)
		local kind = type(value)
		if kind == "string" then return value end
		if kind == "number" or kind == "boolean" then return value end
		if kind ~= "table" or depth > 5 then return nil end
		local out = {}
		for key, item in pairs(value) do
			local keyKind = type(key)
			if keyKind == "string" or keyKind == "number" then
				local cleaned = scrub(item, depth + 1)
				if cleaned ~= nil then out[key] = cleaned end
			end
		end
		return out
	end

	local queue = {}
	local snapshotPending = nil
	local attachedId, detach = nil, nil

	local function enqueue(payload)
		if type(payload) ~= "table" or not FORWARD[payload.kind] then return end
		local entry = scrub(payload, 0)
		entry.sessionId = payload.sessionId or attachedId
		queue[#queue + 1] = entry
		-- Dropping the oldest rather than the newest: a browser that reconnects gets
		-- a fresh snapshot anyway, so the recent end is the half worth keeping.
		while #queue > QUEUE_CAP do table.remove(queue, 1) end
	end

	-- A browser can open at any point in a turn, so the game sends its whole
	-- transcript on connect and whenever the active thread changes. session.log is
	-- already bounded to 400 entries, which is the same ceiling the in-game view
	-- redraws from.
	local function snapshotOf(session)
		local out = {}
		for _, payload in ipairs(session.log or {}) do
			if FORWARD[payload.kind] then out[#out + 1] = scrub(payload, 0) end
		end
		return out
	end

	-- The browser follows the active thread rather than owning one, so switching
	-- conversations in-game moves the browser with it. Re-checked on every drain
	-- because a switch is not announced to this module directly.
	local function attach()
		local sessions = env.require("agent/session")
		local session = sessions.current()
		if attachedId == session.id then return session end
		if detach then
			pcall(detach)
			detach = nil
		end
		attachedId = session.id
		detach = session.events:connect(enqueue)
		snapshotPending = snapshotOf(session)
		-- The snapshot already includes these events; uploading both would repeat them.
		queue = {}
		return session
	end

	local function base()
		return "http://127.0.0.1:" .. tostring(connection.get().port)
	end

	local function headers()
		return { ["Authorization"] = "Bearer " .. connection.get().token, ["X-UAI-Client"] = clientId }
	end

	-- `identity = "none"` because the Claude Code headers identify this client to an
	-- inference gateway and mean nothing to a local relay. `silent` keeps the poll
	-- out of the Requests view.
	local function call(spec)
		local mine = generation
		local callerAborted = spec.aborted
		local supplied = spec.headers or {}
		spec.headers = headers()
		if supplied["X-UAI-Poll-Wait-Ms"] then spec.headers["X-UAI-Poll-Wait-Ms"] = supplied["X-UAI-Poll-Wait-Ms"] end
		spec.aborted = function() return not alive or mine ~= generation or callerAborted and callerAborted() end
		spec.identity = "none"
		spec.silent = true
		spec.waitForSlot = true
		spec.tag = "bridge"
		return http.request(spec)
	end

	function M.opencodeStatus()
		if not M.online or not opencode then return { available = false, state = "disconnected" } end
		return util.copy(opencode)
	end

	function M.opencodeHasModel(id)
		return M.opencodeStatus().available and opencodeModels[tostring(id)] == true
	end

	function M.clineStatus()
		if not M.online then return { enabled = false, available = false, state = "disconnected",
			message = "Start UAI Bridge and connect Cowork before using Cline. Android and direct executor requests cannot use this provider." } end
		if not cline then return { enabled = false, available = false, state = "unavailable",
			message = "Update UAI Bridge to use the Cline connection, then enable it in Tunnels." } end
		return util.copy(cline)
	end

	function M.clineHasModel(id)
		return M.clineStatus().available and clineModelIds[tostring(id)] == true
	end

	function M.clineModels(opts)
		local access = config.accessProblem()
		if access then return nil, access end
		opts = opts or {}
		local status, mine, instance = M.clineStatus(), generation, bridgeInstance
		if not status.enabled then return nil, status.message end
		-- Authentication can become ready during this explicit catalog refresh.
		local res, err = call({ url = base() .. "/api/tunnels/cline/models", method = "GET",
			requiresAccess = true, timeout = opts.timeout or 20, aborted = opts.aborted })
		if mine ~= generation or instance ~= bridgeInstance or not M.online or not M.clineStatus().enabled then
			return nil, "Cline connection changed; fetch models again."
		end
		if not res or not res.ok then return nil, err or "Could not read Cline's free models. Check its sign-in and status in Tunnels." end
		local value = #res.body <= 2097152 and util.decode(res.body)
		if type(value) ~= "table" or type(value.data) ~= "table" or value.error then
			return nil, "Cline returned an invalid model list."
		end
		local known = {}
		for index, row in ipairs(value.data) do
			if index > 10000 then break end
			local id = type(row) == "table" and env.require("provider/model_id").parse(row.id)
			if id then known[id] = true end
		end
		clineModelIds = known
		return value
	end

	function M.opencodeModels(opts)
		local access = config.accessProblem()
		if access then return nil, access end
		opts = opts or {}
		local support = env.require("runtime/support")
		if not M.opencodeStatus().available then return nil, support.error(support.opencode()) end
		local mine, instance = generation, bridgeInstance
		local res, err = call({ url = base() .. "/api/opencode/models", method = "GET",
			requiresAccess = true, timeout = opts.timeout or 10, aborted = opts.aborted })
		if not res or not res.ok then return nil, env.require("provider/openai").errorText(res, err) end
		local value = #res.body <= 2097152 and util.decode(res.body)
		if type(value) ~= "table" or type(value.data) ~= "table" or value.error then
			return nil, support.error("OpenCode CLI returned an invalid model list.")
		end
		if mine ~= generation or instance ~= bridgeInstance or not M.opencodeStatus().available then
			return nil, support.error("OpenCode CLI connection changed; fetch models again.")
		end
		local known = {}
		for index, row in ipairs(value.data) do
			if index > 10000 then break end
			local id = type(row) == "table" and env.require("provider/model_id").parse(row.id)
			if id then known[id] = true end
		end
		opencodeModels = known
		return value
	end

	local function runCommand(command)
		if type(command) ~= "table" then return end
		if type(command.type) == "string" and command.type:sub(1, 4) == "mcp:" then
			return env.require("net/mcp").run(command)
		end
		local sessions = env.require("agent/session")
		local kind = tostring(command.type or "")
		local access = config.accessProblem()
		if access and kind ~= "abort" and kind ~= "subagent:stop" and kind ~= "loops:stop" then error(access, 0) end
		local session = command.sessionId and sessions.threads[command.sessionId] or sessions.current()
		if not session then error("Conversation no longer exists", 0) end

		if kind == "send" then
			local ok, why = session.send(tostring(command.text or ""), nil, command.files, command.images,
				{ messageId = command.commandId })
			-- Admission can queue a follow-up. Preserve the receipt across retries;
			-- refusals must reach the composer so its draft is retained.
			if not ok then
				error(tostring(why or "could not send"), 0)
			end
			return why
		elseif kind == "queue:remove" then
			local ok, why = session.removeQueued(tostring(command.messageId or ""))
			if not ok then error(tostring(why), 0) end
			return session.queueSnapshot()
		elseif kind == "queue:resume" then
			local ok, why = session.resumeQueue()
			if not ok then error(tostring(why), 0) end
			return session.queueSnapshot()
		elseif kind == "queue:edit" or kind == "queue:move" or kind == "queue:clear" then
			local ok, why
			if kind == "queue:edit" then ok, why = session.editQueued(command.messageId, command.text, command.expectedText)
			elseif kind == "queue:move" then ok, why = session.moveQueued(command.messageId, command.direction, command.neighborId)
			else ok, why = session.clearQueued(command.messageIds) end
			if not ok then error(tostring(why), 0) end
			return session.queueSnapshot()
		elseif kind == "abort" then
			session.abort()
		elseif kind == "clear" then
			if session.busy then error("Stop this conversation before clearing it", 0) end
			session.clear()
		elseif kind == "permission" then
			-- The same door the in-game panel uses: the agent left a resolve function
			-- behind and whoever answers first calls it. No new authority is created
			-- here, and an id that has already been answered is simply absent.
			local permissions = env.require("agent/permissions")
			local entry = permissions.pending[tostring(command.id or "")]
			if entry and type(entry.resolve) == "function" then
				entry.resolve(command.allow == true, command.remember == true)
			end
		elseif kind == "provider" then
			env.require("provider/registry").setActive(tostring(command.id or ""))
		elseif kind == "model" then
			env.require("provider/registry").setModel(tostring(command.provider or ""), tostring(command.model or ""))
			env.require("provider/registry").setActive(tostring(command.provider or ""))
		elseif kind == "models:discover" then
			-- Discovery is a network round trip, so it runs on its own thread: the
			-- poller must not park behind it or the browser would stall for seconds.
			local providers = env.require("provider/registry")
			local record = providers.get(tostring(command.provider or ""))
			if record then
				clock.spawn(function()
					local models = env.require("provider/models")
					local ids, note = models.discover(record, { force = true })
					local count = type(ids) == "table" and #ids or 0
					log.info("bridge", "model discovery: " .. tostring(note) .. " (" .. count .. " models)")
				end)
			end
		elseif kind == "thread" then
			env.require("agent/session").switch(tostring(command.id or ""))
		elseif kind == "thread:new" then
			env.require("agent/session").newThread()
		elseif kind == "thread:delete" then
			env.require("agent/session").remove(tostring(command.id or ""))
		elseif kind == "thread:rename" then
			local target = env.require("agent/session").threads[tostring(command.id or "")]
			if target and target.rename then target.rename(tostring(command.title or "")) end
		elseif kind == "permission-mode" then
			env.require("agent/permissions").setMode(tostring(command.mode or "ask"))
		elseif kind == "subagent:stop" then
			env.require("agent/subagent").stop(tostring(command.id or ""))
		else
			local result = env.require("net/bridge_commands").run(command)
			if result == false then error("Unknown command: " .. kind, 0) end
			return result
		end
	end

	-- Reported once per streak rather than per attempt: with the bridge not running,
	-- a per-attempt warning would be the only thing in the log.
	local function offline(reason, direction)
		-- Local slot admission sent no request and says nothing about reachability.
		if tostring(reason or ""):find("capacity:", 1, true) then return end
		if direction == "upload" then uploadFailed = true else pollFailed = true end
		local moved = M.online or M.lastError == nil
		local changed = M.online or M.lastError ~= reason
		M.online = false
		opencode, nextHello, kilo, cline = nil, 0, nil, nil
		opencodeModels = {}
		clineModelIds = {}
		M.lastError = reason
		syncRuntime()
		if moved then
			log.warn("bridge", "not reachable", reason)
		end
		if changed then M.changed:fire() end
	end

	local function onlineNow(direction)
		if direction == "upload" then uploadFailed = false else pollFailed = false end
		if uploadFailed or pollFailed then return end
		if M.online then return end
		M.online = true
		M.lastError = nil
		syncRuntime()
		log.info("bridge", "connected to the local bridge")
		M.changed:fire()
	end

	-- The browser's panels are drawn from the same modules the in-game interface
	-- reads, so nothing in the web UI is a guess: providers and their real model
	-- lists, the tool registry, threads, subagents, usage and the host's
	-- capabilities all arrive as they are. Pushed at most once a second and only
	-- when the encoded form changed, so a still session costs nothing.
	local function stateOf()
		local sessions = env.require("agent/session")
		local providers = env.require("provider/registry")
		local models = env.require("provider/models")
		local metadata = env.require("net/bridge_metadata")
		local registry = env.require("agent/registry")
		local subagents = env.require("agent/subagent")
		local usage = env.require("agent/usage")
		local permissions = env.require("agent/permissions")
		local place = env.require("runtime/place")

		pcall(function() registry.load() end)

		local threads = {}
		for _, session in ipairs(sessions.list()) do
			local pending = session.queueSnapshot()
			threads[#threads + 1] = {
				id = session.id,
				title = session.title,
				place = session.placeName,
				busy = session.busy == true,
				queuedCount = pending.count,
				queueHeld = pending.held,
				turns = session.turns or 0,
				updatedAt = session.updatedAt or 0,
				active = session.id == sessions.activeId,
				ephemeral = session.ephemeral == true,
			}
		end

		local providerList = {}
		for _, record in ipairs(providers.list()) do
			local health = record.health or {}
			local ids, freeModels, modelInfo = models.list(record), {}, {}
			for _, id in ipairs(ids) do
				if models.isFree(record, id) then freeModels[#freeModels + 1] = id end
				modelInfo[id] = metadata.model(record, id)
			end
			if record.model and not modelInfo[record.model] then modelInfo[record.model] = metadata.model(record) end
			providerList[#providerList + 1] = {
				id = record.id,
				label = record.label,
				baseUrl = record.baseUrl,
				api = record.api,
				authStyle = record.authStyle,
				preset = record.preset,
				hasKey = util.trim(record.apiKey or "") ~= "",
				model = record.model,
				models = ids,
				modelInfo = modelInfo,
				freeModels = freeModels,
				free = models.isFree(record, record.model),
				freeRoute = env.require("provider/free_route").status(record),
				enabled = record.enabled ~= false,
				health = {
					ok = health.ok or 0,
					fail = health.fail or 0,
					lastError = health.lastError or "",
				},
				cooling = providers.cooling(record),
			}
		end

		local tools, schemas = {}, {}
		for _, definition in ipairs(registry.definitions()) do
			schemas[definition["function"].name] = definition["function"].parameters
		end
		for _, tool in ipairs(registry.list()) do
			tools[#tools + 1] = {
				name = tool.name,
				group = tool.group,
				description = tool.description,
				risk = tool.risk or "write",
				parameters = schemas[tool.name] or tool.parameters,
				available = registry.missingCapability(tool) == nil,
				enabled = registry.groupEnabled(tool.group),
				rule = permissions.ruleFor(tool.name) or "default",
				effectiveRule = permissions.check(tool),
			}
		end

		local subs = {}
		for _, record in ipairs(subagents.list()) do
			local live = record.status == "running" or record.status == "queued"
			local access = {}
			for group in pairs(subagents.PRESETS[record.preset] or {}) do access[#access + 1] = registry.groupLabel(group) end
			table.sort(access)
			local activity, chosen = {}, {}
			local function addActivity(item)
				if #activity >= 12 or chosen[item] then return end
				chosen[item] = true
				activity[#activity + 1] = { index = item.index, name = util.ellipsis(item.name or "Tool", 120), done = item.done == true,
					ok = item.ok, interrupted = item.interrupted == true, ms = item.ms,
					progress = item.progress and util.ellipsis(item.progress, 400), summary = item.summary and util.ellipsis(item.summary, 600) }
			end
			for _, item in ipairs(record.activity or {}) do if not item.done then addActivity(item) end end
			for index = #(record.activity or {}), 1, -1 do addActivity(record.activity[index]) end
			table.sort(activity, function(a, b) return (a.index or 0) < (b.index or 0) end)
			local preview = record.preview
			subs[#subs + 1] = {
				id = record.id,
				label = record.label,
				task = util.ellipsis(record.task or "", 2000), currentTask = record.currentTask and util.ellipsis(record.currentTask, 2000),
				preset = record.preset,
				toolAccess = subagents.PRESETS[record.preset] == nil and "Every available tool" or table.concat(access, ", "),
				status = record.status,
				ms = record.ms,
				messages = record.messages,
				report = record.report and util.ellipsis(record.report, 12000) or nil, reportExcerpt = record.report and #record.report > 12000 or false,
				provider = record.provider, model = record.model, parentTitle = record.parentTitle,
				elapsedMs = live and clock.since(record.startedAt or clock.ms()) or (record.ms or 0),
				stopping = record.stopping == true, runs = record.runs or 1, canFollowup = not live and record.session ~= nil,
				calls = math.max(0, (record.calls or 0) - (record.runCallBase or 0)), finishedCalls = math.max(0, (record.finishedCalls or 0) - (record.runFinishedBase or 0)),
				currentTool = record.currentTool, statusText = record.statusText and util.ellipsis(record.statusText, 240),
				latestText = record.latestText and util.ellipsis(record.latestText, 8000), latestReasoning = record.latestReasoning and util.ellipsis(record.latestReasoning, 4000),
				textExcerpt = record.textExcerpt == true or record.latestText ~= nil and #record.latestText > 8000,
				reasoningExcerpt = record.reasoningExcerpt == true or record.latestReasoning ~= nil and #record.latestReasoning > 4000,
				preview = preview and { text = util.ellipsis(preview.text or "", 4000), reasoning = util.ellipsis(preview.reasoning or "", 2000),
					limited = preview.limited == true, textExcerpt = preview.textExcerpt == true or #(preview.text or "") > 4000,
					reasoningExcerpt = preview.reasoningExcerpt == true or #(preview.reasoning or "") > 2000 } or nil,
				activity = activity, activityOmitted = math.max(0, #(record.activity or {}) - #activity),
			}
		end

		local activeRecord = providers.active()
		local current = sessions.current()
		local loops = {}
		for _, job in ipairs(env.require("runtime/chatloops").list()) do
			loops[#loops + 1] = { id = job.id, kind = job.kind, state = job.state, channel = job.channel,
				sent = job.sent, count = job.count, completed = job.completed, reason = job.reason, scores = job.scores }
		end
		local pendingPermissions = {}
		for id, request in pairs(permissions.pending) do
			pendingPermissions[#pendingPermissions + 1] = { id = id, name = request.tool.name,
				description = request.tool.description, args = request.args,
				sessionId = request.session and request.session.id }
		end
		local asks = env.require("ui/panels/ask")
		local questions = {}
		local function question(request)
			if request then questions[#questions + 1] = { id = request.id, question = request.question,
				options = request.options, sessionTitle = request.sessionTitle } end
		end
		question(asks.current)
		for _, request in ipairs(asks.queue) do question(request) end
		local settings = {}
		for _, section in ipairs({ "ui", "agent", "logs", "iy", "identity" }) do
			settings[section] = {}
			for key, value in pairs(config.get(section, {})) do
				if type(value) ~= "table" then settings[section][key] = value end
			end
		end
		local themeColors = {}
		for _, key in ipairs({ "canvas", "sidebar", "surface", "surfaceRaised", "surfaceActive", "border", "text", "textSecondary", "textTertiary", "accent", "accentHot", "solid", "onSolid" }) do
			themeColors[key] = "#" .. env.require("ui/theme").color[key]:ToHex()
		end

		return {
			protocol = 2,
			mcp = { schema = 1, available = true },
			imageInput = true,
			attachments = { inlineLimit = env.require("runtime/attachments").INLINE_LIMIT,
				maxBytes = env.require("runtime/attachments").MAX_BYTES, available = caps.fs },
			runtime = config.get("bridge.runtime", "game"),
			sessionId = current.id,
			player = env.plr and env.plr.DisplayName or "you",
			settings = settings, theme = themeColors, loops = loops, todos = current.todos,
			questions = questions, pendingPermissions = pendingPermissions,
			logs = util.slice(log.entries, math.max(1, #log.entries - 59), #log.entries),
			requests = http.history,
			presets = env.require("provider/catalog").presets,
			place = { id = place.id, name = place.label() },
			caps = { executor = caps.executor, http = caps.http, summary = caps.summary() },
			agent = {
				status = current.status,
				busy = current.busy == true,
				provider = activeRecord and activeRecord.label or nil,
				model = activeRecord and activeRecord.model or nil,
			},
			context = metadata.context(current, activeRecord),
			queue = current.queueSnapshot(),
			usage = {
				prompt = usage.session.prompt,
				completion = usage.session.completion,
				total = usage.session.total,
				cost = usage.session.cost,
				unpriced = usage.session.unpriced or 0,
				requests = usage.session.requests,
				estimated = usage.session.estimated == true,
			},
			permissions = { mode = permissions.mode(), pending = permissions.pendingCount() },
			threads = threads,
			providers = providerList,
			activeProvider = activeRecord and activeRecord.id or nil,
			tools = tools,
			subagents = subs,
		}
	end

	local lastStateJson, lastStateAt = nil, 0
	local STATE_EVERY = 1000
	local inflight, commandResults = nil, {}
	local unackedCommands = {}
	local function commandScope() return base() .. "\0" .. connection.get().token .. "\0" end

	local function drain(mine)
		if next(commandResults) then
			local results = {}
			for _, result in pairs(commandResults) do results[#results + 1] = result end
			local res = call({ url = base() .. "/api/agent/ack", method = "POST", body = util.encode({ results = results }), timeout = 10 })
			if not alive or mine ~= generation then return true end
			if res and res.ok then
				for _, result in ipairs(results) do
					if commandResults[result.id] == result then commandResults[result.id] = nil end
					local key = commandScope() .. result.id
					if unackedCommands[key] == result then unackedCommands[key] = nil end
				end
			end
		end
		if inflight then
			local res, err = call({ url = base() .. "/api/agent/events", method = "POST", body = inflight, timeout = 10 })
			if not alive or mine ~= generation then return true end
			if res and res.ok then inflight = nil; onlineNow("upload"); return true end
			return false, err or "Bridge upload failed"
		end
		attach()
		local stateDue = nil
		if clock.since(lastStateAt) >= STATE_EVERY then
			lastStateAt = clock.ms()
			local ok, built = pcall(stateOf)
			if ok then
				local encoded = util.encode(built)
				if encoded ~= lastStateJson then
					lastStateJson = encoded
					stateDue = built
				end
			end
		end
		if #queue == 0 and snapshotPending == nil and stateDue == nil then return true end
		local batch = queue
		local snapshot = snapshotPending
		queue = {}
		snapshotPending = nil

		inflight = util.encode({ batchId = env.services.HttpService:GenerateGUID(false), events = batch, snapshot = snapshot, state = stateDue,
			sessionId = attachedId })
		local res, err = call({
			url = base() .. "/api/agent/events",
			method = "POST",
			body = inflight,
			timeout = 10,
		})
		if not alive or mine ~= generation then return true end
		if res and res.ok then inflight = nil; onlineNow("upload"); return true end

		-- Keep this exact encoded batch and ID until acknowledged. Events arriving
		-- during the request stay in the next batch instead of being duplicated.
		return false, err or ("status " .. tostring(res and res.status or 0))
	end

	local function uploadLoop(mine)
		local attempt = 0
		while alive and mine == generation do
			local ok, reason = drain(mine)
			if not alive or mine ~= generation then return end
			if ok then
				attempt = 0
				clock.wait(DRAIN_SECONDS)
			else
				attempt = attempt + 1
				offline(reason, "upload")
				clock.wait(clock.backoff(attempt, { cap = 10 }))
			end
		end
	end

	local handledCommands = {}
	local function pollLoop(mine)
		local attempt = 0
		local scope = commandScope()
		local mobile = false
		pcall(function() mobile = env.uis.TouchEnabled == true and env.uis.MouseEnabled ~= true end)
		local timeout = POLL_TIMEOUT
		while alive and mine == generation do
			if clock.ms() >= nextHello then
				local hello = call({ url = base() .. "/api/hello", method = "GET", timeout = 2 })
				if not alive or mine ~= generation then return end
				local info = hello and hello.ok and #hello.body <= 16384 and util.decode(hello.body)
				local capabilities = type(info) == "table" and info.protocol == 2 and info.capabilities
				local instance = type(info) == "table" and info.protocol == 2 and info.instance
				if type(instance) == "string" and #instance > 0 and #instance <= 160 then
					if bridgeInstance and bridgeInstance ~= instance then
						clineModelIds = {}
						local mcp = env.loadedModules and env.loadedModules["net/mcp"]
						if mcp then mcp.clear() end
						-- Automatic worker updates keep manual credentials. A new worker
						-- still needs a complete state, without resending any user action.
						lastStateJson, lastStateAt = nil, 0
						snapshotPending = snapshotOf(attach())
					end
					bridgeInstance = instance
				end
				local inbox = type(capabilities) == "table" and capabilities.agentInbox
				if mobile and type(inbox) == "table" and inbox.waitHeader == "X-UAI-Poll-Wait-Ms" then timeout = 5 end
				local backend = type(capabilities) == "table" and capabilities.opencode
				local previous = opencode
				local previousKilo = kilo
				local previousCline = cline
				kilo = kiloStatus.read(type(capabilities) == "table" and capabilities.kilo)
				cline = readCline(type(capabilities) == "table" and capabilities.cline)
				opencode = capability.read(backend, opencodeStates, { ready = true, starting = true })
				nextHello = clock.ms() + 4000
				if not opencode or not opencode.available or previous and previous.version ~= opencode.version then opencodeModels = {} end
				if not cline or not cline.enabled or (previousCline and previousCline.available and not cline.available)
					or (previousCline and cline and previousCline.version ~= cline.version) then clineModelIds = {} end
				if util.encode(previous) ~= util.encode(opencode) then M.changed:fire() end
				if util.encode(previousKilo) ~= util.encode(kilo) then M.changed:fire() end
				if util.encode(previousCline) ~= util.encode(cline) then M.changed:fire() end
			end
			-- After a failed poll, prove the inbox is back without waiting through
			-- another idle long poll before Web runtime can recover.
			local waitMs = attempt > 0 and "0" or (mobile and "1000" or nil)
			local res, err = call({
				url = base() .. "/api/agent/inbox",
				method = "GET",
				timeout = timeout,
				headers = waitMs and { ["X-UAI-Poll-Wait-Ms"] = waitMs } or nil,
			})
			-- The request parked for up to eighteen seconds; an unload during that
			-- window means the answer is no longer wanted.
			if not alive or mine ~= generation then return end

			local decoded = res and res.ok and util.decode(res.body)
			local commands = type(decoded) == "table" and decoded.commands
			if res and res.ok and type(commands) == "table" then
				attempt = 0
				onlineNow("poll")
				local handled = 0
				for _, command in ipairs(commands) do
					if type(command) == "table" then
						handled = handled + 1
						-- One bad command must not stop the poller: that would take the
						-- browser offline until the next reload.
						local id = command.commandId
						if type(id) ~= "string" or #id == 0 or #id > 160 then id = nil end
						local key = id and scope .. id
						if key and handledCommands[key] then
							if handledCommands[key] ~= true then commandResults[id] = handledCommands[key] end
						else
							if id then
								handledCommands[key] = true
								commandResults[id] = { id = id, pending = true }
							end
							clock.spawn(function()
								if not alive or mine ~= generation then return end
								local ok, result = pcall(runCommand, command)
								if id then
									local answer = { id = id, ok = ok, error = not ok and tostring(result) or nil,
										data = ok and type(result) == "table" and result or nil }
									-- Pending ACKs remove the inbox command. Retain its final
									-- receipt until this endpoint accepts it, even across Stop.
									handledCommands[key] = answer
									unackedCommands[key] = answer
									if alive and commandScope() == scope then commandResults[id] = answer end
								elseif not ok then log.warn("bridge", "command failed", result) end
							end)
						end
					end
				end
				-- The bridge is expected to hold this request open until it has
				-- something to say. One that answers empty straight away -- an older
				-- build, or a proxy that will not park a connection -- would otherwise
				-- turn this loop into a flood of requests.
				if (res.ms or 0) < 100 then clock.wait(handled == 0 and 0.25 or 0.05) end
			else
				attempt = attempt + 1
				offline(err or (res and res.ok and "Invalid bridge inbox response" or "status " .. tostring(res and res.status or 0)), "poll")
				clock.wait(clock.backoff(attempt, { cap = 10 }))
			end
		end
	end

	local unregister = nil

	local function shutdown()
		generation = generation + 1
		local mcp = env.loadedModules and env.loadedModules["net/mcp"]
		if mcp then mcp.clear() end
		alive = false
		M.running = false
		M.online = false
		opencode, nextHello, kilo, cline = nil, 0, nil, nil
		bridgeInstance = nil
		opencodeModels = {}
		clineModelIds = {}
		syncRuntime()
		if detach then pcall(detach) end
		detach, attachedId = nil, nil
		queue = {}
		snapshotPending = nil
		inflight = nil
		commandResults = {}
	end

	function M.start()
		local access = config.accessProblem()
		if access then return false, access end
		if M.running then return true end
		if not caps.has("http") then return false, caps.reason("http") end
		if util.trim(connection.get().token) == "" then
			return false, "no token yet -- run bridge/server.js and paste the token it prints"
		end

		M.running = true
		alive = true
		generation = generation + 1
		lastStateJson, lastStateAt = nil, 0
		M.lastError = nil
		uploadFailed, pollFailed = false, false
		local scope = commandScope()
		for key, answer in pairs(unackedCommands) do
			if key:sub(1, #scope) == scope then commandResults[answer.id] = answer end
		end
		attach()
		clock.spawn(uploadLoop, generation)
		clock.spawn(pollLoop, generation)
		-- Two threads that outlive the interface, so unloading has to be able to
		-- stop them. The canceller is kept rather than discarded because stopping
		-- from Settings has to unregister as well, or the drain would run it twice.
		unregister = dispose.add(shutdown, "bridge")
		log.debug("bridge", "connecting to " .. base())
		M.changed:fire()
		return true
	end

	function M.stop(keepDiscovery)
		local wasRunning = M.running
		if not keepDiscovery then connection.pause() end
		if not M.running then return wasRunning end
		if unregister then
			unregister()
			unregister = nil
		else
			shutdown()
		end
		log.info("bridge", "stopped")
		M.changed:fire()
		return true
	end

	-- One place decides whether the bridge should be up, so boot and the Settings
	-- toggle cannot disagree about it.
	function M.sync()
		local access = config.accessProblem()
		if access then return false, access end
		connection.resume()
		if connection.enabled() then return M.start() end
		M.stop(true)
		return false
	end

	function M.status()
		return {
			running = M.running,
			online = M.online,
			url = base(),
			instance = bridgeInstance,
			source = connection.get().source,
			searching = connection.searching(),
			opencode = M.opencodeStatus(),
			kilo = M.online and kilo and util.copy(kilo) or nil,
			cline = M.online and cline and util.copy(cline) or nil,
			queued = #queue,
			runtime = M.online and "web" or "game",
			error = M.lastError,
		}
	end

	-- Any route that changes the setting takes effect, whether that is the Settings
	-- panel, a console call or a host script, so the panel only has to write config
	-- rather than orchestrate this. A port or token change aims the connection
	-- somewhere new, so it is torn down and rebuilt rather than adjusted in place.
	dispose.add(connection.changed:connect(function()
		if M.running then M.stop(true) end
		if connection.enabled() then M.start() end
		M.changed:fire()
	end), "bridge connection")
	dispose.add(config.changed:connect(function(path)
		if path == nil or path == "bridge" or path == "bridge.runtime" then syncRuntime(); lastStateJson = nil end
	end), "bridge config")
	-- Runtime is a live connection fact, including when an older save selected Web.
	syncRuntime()

	return M






end
