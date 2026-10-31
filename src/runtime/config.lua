-- Persisted settings.
--
-- One file, one shape, defaults merged under whatever was saved -- so adding a
-- setting in a later version does not invalidate an existing install, and a
-- half-written file falls back to defaults rather than bricking the client.
-- Writes are debounced because the interface calls set() from slider drags.
return function(env)
	local util = env.require("runtime/util")
	local fsx = env.require("runtime/fsx")
	local clock = env.require("runtime/clock")
	local signal = env.require("runtime/signal")
	local log = env.require("runtime/log")
	local credentials = env.require("runtime/credentials")
	local vault = env.require("runtime/credential_vault")
	local dispose = env.require("runtime/dispose")

	local FILE = "config.json"
	local STAGED = "config.vault.pending.json"

	local DEFAULTS = {
		version = 1,
		ui = {
			density = "comfortable",
			accent = "claude",
			theme = "default",
			seasonalThemes = true,
			layout = "auto",
			panel = "chat",
			fontScale = 1,
			showReasoning = true,
			showToolDetail = false,
			-- Whether the code a tool was handed is drawn under its row, outside the
			-- fold. On by default: the listing is the single most useful thing in a
			-- transcript of an agent that writes and executes code, and it used to be
			-- reachable only by opening a pane that defaulted shut.
			showToolCode = true,
			-- The key that opens quick chat, stored as an Enum.KeyCode name because
			-- that is what the capture in Settings produces and what survives a
			-- keyboard layout the character would not.
			quickKey = "Semicolon",
			showUsage = true,
			modelFavorites = {},
			recentModels = {},
			-- Appearance choices that name a family or a palette rather than a number.
			-- All four are read by ui/theme, so each one changes what is on screen.
			interfaceFont = "builder",
			codeFont = "code",
			codeTheme = "dark",
			transcriptWidth = "wide",
			-- The sidebar, the home card and the range the card opens on. Remembered
			-- because each is a place the user put something.
			sidebarCollapsed = false,
			sidebarExpanded = false,
			showActivity = true,
			activityRange = "all",
			-- Whether a minimized client still gets toasts when a turn finishes, fails
			-- or is stopped. The launcher badge happens either way; this is only the
			-- floating text.
			notifications = true,
			window = { width = 0, height = 0, x = 0, y = 0, maximised = false, placed = false },
			mobilePanel = { width = 0, height = 0, x = 0, y = 0, maximised = false, placed = false },
			mobileSheet = { width = 0, height = 0, x = 0, y = 0, maximised = false, placed = false },
			launcher = { x = 0, y = 0, placed = false },
			-- The last changelog version the user opened. The app menu marks What's
			-- New while the running version is newer than this; opening the modal
			-- sets it. "0.0.0" rather than the shipping version so a first run
			-- shows the marker -- a new user is exactly who the notes are for.
			lastSeenVersion = "0.0.0",
			-- Note revisions can change without changing the client version.
			lastSeenChangelog = "",
			communityInvite = { lastShown = 0, disabled = false },
			-- The intro tour's first-run gate. Set when the tour is shown, so a
			-- fresh install sees it once; the profile menu's Tutorial entry opens
			-- it again whether the flag is set or not.
			tutorial = { seen = false },
		},
		agent = {
			maxTurns = 60,
			-- Lifts the step limit and the turn deadline for the top-level
			-- conversation, so a long job runs until the model answers in prose
			-- instead of stopping mid-way with "I reached this session's step limit".
			-- What still bounds a runaway: the repeat breaker, each tool's own
			-- timeout, the provider retry cap, and Stop. Subagents keep their own
			-- turn and time budgets either way -- an unbounded child is the one
			-- thing here nobody is watching.
			unlimitedTurns = true,
			toolConcurrency = 8,
			toolTimeout = 60,
			-- Configured model-call wait, shared by parent and child agents. Native
			-- transports enforce a separate 300-second maximum; hosts may stop sooner.
			-- Buffered HTTP delivers the response only after the host call completes.
			requestTimeout = 86400,
			-- Use the transport's maximum wait without changing the saved shorter
			-- timeout. This never disables native deadlines or cooperative Stop.
			requestUnlimited = true,
			-- Large contexts increase upload and prefill time under executor HTTP
			-- deadlines; lower this budget when even short replies time out.
			contextTokens = 1000000,
			-- The share of a model's known context window at which older turns are
			-- summarised. contextTokens above is the hard ceiling; this is what makes
			-- compaction adapt to a small-window model without retuning that number.
			contextFraction = 0.8,
			keepTurns = 14,
			compaction = true,
			stream = true,
			-- Optional measured routing for included Free access with model auto.
			autoFreeRouting = true,
			temperature = 0.4,
			-- Reasoning depth: sent as `reasoning_effort` on chat completions and as
			-- `output_config.effort` on the Messages API. Start with low latency;
			-- saved choices and explicit request/provider overrides remain authoritative.
			-- "off" omits the field (provider default), not a promise of no thinking.
			effort = "low",
			-- Manual capability claims, keyed by lowercased model id. No endpoint
			-- publishes what a relayed id can do, so this is the user's word against
			-- nothing: `forceReasoning` makes the adapters ask a model to think, and
			-- `forceContext` states its window, which both the badge and the context
			-- budget slider then read. Effort follows reasoning: a model forced to
			-- think gets the effort scale even where the table documents none.
			forceReasoning = {},
			forceContext = {},
			forceSampling = {},
			maxTokens = 128000,
			-- Characters, not tokens, and it is the last word on how much of a tool
			-- result reaches the model. Eight thousand rather than four so that the
			-- tools' own defaults -- a six thousand character file read, a five thousand
			-- character response body -- arrive whole instead of being cut in half by a
			-- limit set somewhere the caller cannot see.
			resultCap = 128000,
			repeatLimit = 3,
			subagentDepth = 4,
			subagentTurns = 30,
			-- Live subagents anywhere in the tree. `toolConcurrency` bounds one batch,
			-- so it is what caps a parallel dispatch from the main conversation; this
			-- caps the whole tree, which nothing else did. Depth alone does not: a
			-- subagent's own batch is bounded separately, and two levels of that
			-- multiply rather than add.
			subagentConcurrency = 12,
			-- Seconds one subagent may run for. The tool that dispatches it derives its
			-- own timeout from this, so the two cannot drift apart -- when they did, the
			-- generic 25s tool timeout fired first and every finished report was thrown
			-- away by a caller that had already given up.
			subagentBudget = 900,
			-- Lifts every clock and counter on a dispatched subagent: no step limit, no
			-- wall-clock budget, and the call that dispatched it waits as long as the
			-- child takes rather than abandoning a report nobody is left to collect.
			--
			-- Separate from `unlimitedTurns` on purpose. That switch is for the turn
			-- someone is watching and deliberately does not reach a child; this is the
			-- decision to let a delegated job finish instead of stopping mid-way with "I
			-- reached this session's step limit", which is the one outcome that wastes the
			-- whole dispatch. What still bounds a child either way: the repeat breaker,
			-- each tool's own timeout, the provider retry cap, the depth and parallel
			-- ceilings, and Stop -- from the parent turn or from the Subagents panel.
			subagentUnlimited = true,
			-- Which tool preset a dispatch gets when the call does not name one. "full"
			-- hands a subagent every tool; permission mode still gates what actually runs,
			-- and a prompt raised inside a child is forwarded to the parent's stream.
			subagentPreset = "full",
			retries = 6,
			fallback = false,
			-- Tool families the model is not told about at all, keyed by group id. A
			-- permission rule decides whether a call is allowed; this decides whether the
			-- tool is offered, which is the coarser thing somebody who does not want the
			-- agent near remotes in this game is asking for.
			disabledGroups = {},
			-- Declared-tool profile. "all" keeps every tool declared; another
			-- profile hides the long tail behind tool_search without changing
			-- dispatch scope or permissions.
			toolProfile = "focused",
			-- Durable evidence policy. "large" copies only results at or above
			-- evidenceMinBytes; source and file tools already have a durable home.
			evidence = "large",
			evidenceMinBytes = 8192,
			-- The language the agent is asked to answer in, when one has been named.
			-- Empty means "whatever the conversation is in".
			--
			-- A plain string rather than a locale, because that is all the client can
			-- honestly act on. There used to be a grid of eleven languages behind it
			-- claiming to set the locale dates are formatted with as well; nothing read
			-- that half -- runtime/clock formats with a hardcoded en-us and English month
			-- names -- so ten of the eleven tiles did one thing and advertised two.
			replyLanguage = "",
			-- The user's own standing instructions, appended to the system prompt each
			-- turn. Empty means none. The system prompt itself is not editable -- it is
			-- this client's behaviour, and a prompt a user can silently rewrite is one
			-- nobody can debug -- so this is the whole of the personal half: one block,
			-- read back verbatim, placed after the built-in rules so it wins on conflict.
			customInstructions = "",
		},
		permissions = {
			mode = "full",
			remember = true,
			rules = {},
		},
		providers = {
			active = "",
			list = {},
		},
		security = {
			rememberCredentials = true,
			credentialProtection = "password",
		},
		identity = {
			claudeUa = true,
			version = "2.0.14",
			extraHeaders = {},
		},
		memory = {
			enabled = true,
			entries = {},
		},
		-- Manual bridges remain opt-in. The desktop app is discovered only on its
		-- dedicated loopback port; its rotating token stays in memory, not config.
		bridge = {
			enabled = false,
			autoDiscover = true,
			port = 8790,
			token = "",
			runtime = "game",
		},
		-- The local inference relay (mobile companion). It owns the upstream
		-- connection so every executor-visible call stays short, which is what a
		-- phone's executor otherwise cuts off. `token`/`instance` are written by
		-- `/api/pair` and the probe; they are never copied into Cowork settings.
		relay = {
			mode = "auto",
			port = 8790,
			token = "",
			instance = "",
			server = "",
			placeId = 0,
		},
		logs = {
			mirror = false,
			level = "info",
		},
		-- Infinite Yield as an internal command engine. "off" withholds the iy
		-- tools' engine entirely; "hidden" loads IY with its interface parked so
		-- the agent has every command and the user keeps the screen; "visible"
		-- loads it as IY draws itself. The mode is a request, not a state: it is
		-- applied on the next command, never at boot, because loading is a
		-- megabyte fetch and a GUI and a settings row should not spend that.
		iy = {
			mode = "hidden",
		},
		-- Markdown skills (.md playbooks) under skills/. The engine injects nothing
		-- into the system prompt -- the environment block carries names and
		-- one-line descriptions only, and a body is fetched by a tool call when a
		-- task matches. `disabled` is the set of switched-off filenames; an absent
		-- entry means enabled, so a file dropped in by hand works with no second
		-- step.
		skills = {
			disabled = {},
		},
		fs = {
			migrated = false,
		},
	}

	local M = {
		defaults = DEFAULTS,
		data = util.deepCopy(DEFAULTS),
		changed = signal.new("config"),
		loaded = false,
		dirty = false,
	}

	local flush, operation, writing, replacing, loading
	local generation, revision = 0, 0
	-- Bootstrap activates this on every execution. A retained key cannot satisfy a
	-- password challenge; only a verified local unprotected choice skips that gate.
	local required, challengePending, accessEpoch = false, false, 0
	local function unprotected()
		return M.data.credentialVault == nil and type(M.data.security) == "table"
			and M.data.security.credentialProtection == "unprotected"
	end
	local function retirePreferences(data)
		if type(data.ui) == "table" then data.ui.reduceMotion = nil end
		if type(data.bridge) == "table" then data.bridge.requestTimeout = nil end
		if type(data.security) == "table" and (data.credentialVault ~= nil or data.security.credentialProtection ~= "unprotected") then
			data.security.credentialProtection = "password"
		end
	end
	local function same(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end
	local function verified(path, projected)
		local encoded, body = pcall(util.encode, projected)
		return encoded and same(fsx.readJson(path, nil, { sensitive = true }), util.decode(body))
	end
	local function commitProjected(projected, verify, guard)
		if not fsx.enabled then return false, "This executor cannot save credentials because filesystem access is unavailable." end
		local encrypted = projected.credentialVault ~= nil
		local recovery = encrypted and projected or guard and guard.recovery
		local staged = recovery ~= nil
		verify = verify or staged
		-- Stage encrypted recovery before touching the existing config. A downgrade
		-- retains that recovery until its new storage and cleanup are verified.
		if staged then
			local ok = fsx.writeJson(STAGED, recovery, { sensitive = true })
			if not ok or not verified(STAGED, recovery) then
				return false, "Could not verify the staged encrypted file. Your existing configuration is unchanged."
			end
		end
		local previous = verify and fsx.read(FILE) or nil
		if guard and guard.cancelled() then
			if staged and verified(STAGED, recovery) then
				fsx.delete(STAGED)
				if fsx.exists(STAGED) then
					local marker = { cancelled = true }
					local cleared = fsx.writeJson(STAGED, marker, { sensitive = true })
					if not cleared or not verified(STAGED, marker) then
						return false, "Cancelled, but the encrypted staging file could not be removed. Keep this session open and retry."
					end
				end
			end
			return false, "Cancelled"
		end
		-- Once the primary write begins, a dialog close cannot undo the commit.
		-- Unload/load still invalidates ownership before any live key activation.
		if guard then guard.committing = true end
		local ok = fsx.writeJson(FILE, projected, { sensitive = true })
		if not ok or (verify and not verified(FILE, projected)) then
			-- Executor filesystems do not promise atomic rename. Retain the live
			-- state and try to restore the exact previous bytes on failed writeback.
			local restored = previous and fsx.write(FILE, previous, { sensitive = true }) and fsx.read(FILE) == previous
			if staged and restored then fsx.delete(STAGED) end
			return false, "Could not verify saved credential storage. Keep this session open to retain your keys."
		end
		if fsx.exists(STAGED) then
			fsx.delete(STAGED)
			if not encrypted and fsx.exists(STAGED) then
				-- Hosts may lack deletion. Verified overwrite also removes the old
				-- encrypted recovery copy when disabling or resetting the vault.
				local cleared = fsx.writeJson(STAGED, projected, { sensitive = true })
				if not cleared or not verified(STAGED, projected) then
					if previous then fsx.write(FILE, previous, { sensitive = true }) end
					return false, "Could not remove the staged credential recovery file. Keep this session open and retry."
				end
			end
		end
		return true
	end
	local function writeProjected(projected, verify, guard)
		if writing then return false, "A configuration save is already in progress." end
		local token = {}
		writing = token
		local called, ok, why = pcall(commitProjected, projected, verify, guard)
		if writing == token then writing = nil end
		if not called then return false, "Could not complete credential storage. Keep this session open and retry." end
		return ok, why
	end
	local function writeSnapshot(snapshot, verify, guard)
		local projected, why = credentials.persistent(snapshot)
		if not projected then return false, why end
		local ok, err = writeProjected(projected, verify, guard)
		return ok, err, projected
	end

	local function loadSnapshot(handoff, keyHandoff)
		generation = generation + 1
		if required then challengePending = true; accessEpoch = accessEpoch + 1 end
		operation = nil
		vault.clear()
		local stored = type(handoff) == "table" and handoff or fsx.readJson(FILE, nil, { sensitive = true })
		local complete = type(stored) == "table" and stored.version == DEFAULTS.version
			and type(stored.providers) == "table" and type(stored.providers.list) == "table"
			and type(stored.ui) == "table" and type(stored.agent) == "table" and type(stored.permissions) == "table"
		if handoff == nil then
			local pending = fsx.readJson(STAGED, nil, { sensitive = true })
			-- A failed removal may have cleared the primary before its rollback
			-- also failed. Preserve the remaining encrypted recovery in that case.
			local removedPrimary = complete and stored.credentialVault == nil
				and type(stored.security) == "table" and (stored.security.rememberCredentials == false
					or stored.security.credentialProtection == "unprotected")
			if (not complete or removedPrimary) and type(pending) == "table" and vault.validate(pending.credentialVault) then stored = pending end
		end
		if type(stored) == "table" then
			M.data = util.merge(DEFAULTS, credentials.restore(stored))
			if keyHandoff and vault.acceptHandoff(M.data.credentialVault, keyHandoff) then
				local unlocked = credentials.openVault(M.data, vault.key(M.data.credentialVault))
				if unlocked then M.data = unlocked else vault.clear() end
			end
			-- Remembering remains the default. Legacy plaintext and current encoded
			-- credentials restore to the same live shape without losing key pools.
			if type(stored.security) ~= "table" or type(stored.security.rememberCredentials) ~= "boolean" then
				M.data.security = util.deepCopy(DEFAULTS.security)
			end
		else
			M.data = util.deepCopy(DEFAULTS)
		end
		retirePreferences(M.data)
		M.loaded = true
		if type(stored) == "table" and handoff == nil and fsx.enabled then M.saveNow(true, loading) end
		return M.data
	end
	function M.load(handoff, keyHandoff)
		if writing or replacing or loading then return nil, "Wait for the current configuration operation before reloading settings." end
		loading = {}
		local called, data = pcall(loadSnapshot, handoff, keyHandoff)
		loading = nil
		if not called then error("Could not load saved configuration. Keep this session open and check credential storage.", 0) end
		M.changed:fire(nil, M.data)
		return data
	end

	function M.saveNow(verify, loadToken)
		if operation or writing or (loading and loadToken ~= loading) then M.dirty = true; return false, "A credential storage operation is already in progress." end
		if required and M.data.credentialVault == nil and not unprotected() then
			M.dirty = true
			return false, "Choose password protection or explicitly continue unprotected before saving. Your existing credentials are unchanged."
		end
		local savedRevision = revision
		retirePreferences(M.data)
		if not fsx.enabled then
			M.dirty = false
			return false, "no filesystem"
		end
		local ok, err, projected = writeSnapshot(M.data, verify or M.storageError ~= nil)
		M.dirty = not ok or savedRevision ~= revision
		if ok then
			M.storageError = nil
			if projected.credentialVault then M.data.credentialVault = util.deepCopy(projected.credentialVault) end
		else M.storageError = "Saved credential storage could not be verified. Old plaintext files may remain. Keep this session open to retain your keys." end
		if not ok then log.warn("config", "could not persist settings", err) end
		if ok and M.dirty then flush() end
		return ok, err
	end

	flush = clock.debounce(function()
		M.saveNow()
	end, 0.75)

	function M.save()
		revision = revision + 1
		M.dirty = true
		flush()
	end

	function M.get(path, fallback)
		local value = util.get(M.data, path)
		if value == nil then
			local default = util.get(DEFAULTS, path)
			if default ~= nil then return util.deepCopy(default) end
			return fallback
		end
		return value
	end

	-- Fires with the path so a subscriber can react to one setting rather than
	-- rebuilding on every keystroke of an unrelated field.
	function M.set(path, value, opts)
		if type(path) ~= "string" or path == "" or path:sub(1, 1) == "." or path:sub(-1) == "." or path:find("..", 1, true) then
			return nil, "Use a setting path with nonempty names separated by single dots."
		end
		if replacing or loading then return nil, "Wait for the configuration operation before changing settings." end
		local protected = path == "providers" or tostring(path):match("^providers%.")
			or path == "identity" or tostring(path):match("^identity%.")
			or path == "security" or tostring(path):match("^security%.")
			or tostring(path):match("^credentialVault")
		if protected and (operation or writing or M.accessProblem()) then return nil, "Unlock the credential vault and finish its current operation before editing credentials." end
		if tostring(path):match("^credentialVault") then return nil, "Use the credential vault controls to change vault storage." end
		if path == "security" or path == "security.credentialProtection" or tostring(path):match("^security%.credentialProtection%.")
			or tostring(path):match("^security%.rememberCredentials%.") then
			return nil, "Use the password vault controls to change credential storage with verification."
		end
		if path == "security.rememberCredentials" then
			local ok, why = M.setRememberCredentials(value)
			if not ok then return nil, why end
			return value
		end
		if path == "identity.extraHeaders" and type(value) == "table" then
			M.data.identity.storedCredentials, M.data.identity.credentialStorageError = nil, nil
			M.data.identity.credentialsOmitted = nil
		end
		-- Client motion is always enabled. Retired preferences cannot be restored
		-- by an old host integration or by replacing the appearance section.
		if path == "ui.reduceMotion" or tostring(path):sub(1, 16) == "ui.reduceMotion." then
			return nil, "Client animations are always enabled"
		end
		if path == "bridge.requestTimeout" or tostring(path):sub(1, 22) == "bridge.requestTimeout." then
			return nil, "Bridged requests wait until completion or Stop"
		end
		if path == "ui" and type(value) == "table" then
			value = util.deepCopy(value)
			value.reduceMotion = nil
		end
		if path == "bridge" and type(value) == "table" then
			value = util.deepCopy(value)
			value.requestTimeout = nil
		end
		opts = opts or {}
		util.set(M.data, path, value)
		if not opts.quiet then M.changed:fire(path, value) end
		if not opts.transient then M.save() end
		return value
	end

	function M.vaultStatus()
		local enabled = M.data.credentialVault ~= nil
		local locked = enabled and (M.data.credentialVaultLocked ~= false or vault.key(M.data.credentialVault) == nil)
		local valid = not enabled or vault.validate(M.data.credentialVault)
		return { enabled = enabled, locked = locked, required = required,
			protection = enabled and "password" or unprotected() and "unprotected" or "undecided",
			ready = not locked and (not required or unprotected() or (enabled and not challengePending)),
			busy = operation ~= nil or writing ~= nil or loading ~= nil,
			error = not valid and vault.error or M.storageError }
	end
	local function vaultChanged()
		M.changed:fire("security.vault", M.vaultStatus())
	end
	function M.accessProblem()
		local status = M.vaultStatus()
		if status.ready then return end
		if required and not status.enabled then return "Choose password protection or explicitly continue unprotected to use Project UAI." end
		if not status.ready then return "Unlock Project UAI with your master password to continue." end
	end
	function M.requireVault()
		required, challengePending = true, true
		accessEpoch = accessEpoch + 1
		vaultChanged()
		return true
	end
	local function transact(options, callback)
		if operation or writing or loading then return false, "A credential storage operation is already in progress." end
		if options ~= nil and type(options) ~= "table" then return false, "Vault options must be a table." end
		options = options or {}
		for _, name in ipairs({ "progress", "cancelled" }) do
			if options[name] ~= nil and type(options[name]) ~= "function" then return false, "Vault callbacks must be functions." end
		end
		local token, original, currentGeneration, currentAccess = {}, M.data, generation, accessEpoch
		operation = token
		local function owned()
			return operation == token and generation == currentGeneration and M.data == original and not dispose.draining
		end
		local guarded
		guarded = { progress = options.progress, owned = owned, accessEpoch = currentAccess, cancelled = function()
			return not owned() or (not guarded.committing and options.cancelled and options.cancelled()) == true
		end }
		vaultChanged()
		local called, ok, why = pcall(callback, guarded)
		if operation == token then
			operation = nil
			vaultChanged()
			if M.dirty then flush() end
		end
		if not called then return false, "Could not complete the credential vault operation. Your live credentials are unchanged." end
		return ok, why
	end
	local function installVault(password, options)
		if not fsx.enabled then return false, "This executor cannot save credentials because filesystem access is unavailable." end
		return transact(options, function(guarded)
			local envelope, key, why = vault.create(password, guarded)
			password = nil
			if not envelope then return false, why end
			if guarded.cancelled() then return false, "Cancelled" end
			local projected, err = credentials.sealVault(M.data, envelope, key)
			if not projected then return false, err end
			projected.security.credentialProtection = "password"
			-- Verify that the authenticated payload reconstructs before committing it.
			local opened, openError = credentials.openVault(projected, key)
			if not opened then return false, openError end
			if guarded.cancelled() then return false, "Cancelled" end
			local savedRevision = revision
			local ok, writeError = writeProjected(projected, true, guarded)
			if not guarded.owned() then return false, "Cancelled" end
			if not ok then
				if writeError ~= "Cancelled" then M.storageError = writeError end
				return false, writeError
			end
			vault.activate(key, projected.credentialVault)
			M.data.credentialVault, M.data.credentialVaultLocked = projected.credentialVault, false
			M.data.security.rememberCredentials = true
			M.data.security.credentialProtection = "password"
			if guarded.accessEpoch == accessEpoch then challengePending = false end
			M.storageError, M.dirty = nil, savedRevision ~= revision
			return true
		end)
	end
	function M.enableVault(password, options)
		if M.vaultStatus().enabled then return false, "The credential vault is already enabled." end
		return installVault(password, options)
	end
	function M.changeVaultPassword(password, options)
		local status = M.vaultStatus()
		if not status.enabled or M.accessProblem() then return false, "Unlock the credential vault before changing its password." end
		return installVault(password, options)
	end
	function M.unlockVault(password, options)
		local status = M.vaultStatus()
		if not status.enabled then return false, "No credential vault is configured." end
		if status.ready then return true end
		return transact(options, function(guarded)
			local key, why = vault.derive(password, M.data.credentialVault, guarded)
			password = nil
			if not key then return false, why end
			if guarded.cancelled() then return false, "Cancelled" end
			local opened, err = credentials.openVault(M.data, key)
			if not opened then return false, err end
			vault.activate(key, M.data.credentialVault)
			-- Warm reauthentication verifies the password without rolling back live
			-- key edits to the last saved payload. Cold unlock restores that payload.
			if status.locked then credentials.applyVault(M.data, opened) end
			if guarded.accessEpoch == accessEpoch then challengePending = false end
			return true
		end)
	end
	function M.lockVault()
		if operation then return false, "A credential vault operation is already in progress." end
		local status = M.vaultStatus()
		if not status.enabled or status.locked then return true end
		return transact(nil, function(guarded)
			local savedRevision = revision
			local ok, why, projected = writeSnapshot(M.data, true, guarded)
			if guarded.cancelled() then return false, "Cancelled" end
			if not ok then M.storageError = why; return false, why end
			M.data.credentialVault = projected.credentialVault
			credentials.applyVault(M.data, credentials.lockedVault(M.data))
			vault.clear()
			M.storageError, M.dirty = nil, savedRevision ~= revision
			return true
		end)
	end
	-- This deliberate local choice stores reversible credential bytes, not
	-- encryption. An existing encrypted vault must first be authenticated.
	function M.continueWithoutEncryption(options)
		local status = M.vaultStatus()
		if status.enabled and not status.ready then return false, "Unlock or reset the credential vault before choosing unprotected storage." end
		return transact(options, function(guarded)
			local savedRevision = revision
			local cancelled = guarded.cancelled
			guarded.cancelled = function()
				return cancelled() or (status.enabled and not guarded.committing and guarded.accessEpoch ~= accessEpoch)
			end
			if guarded.cancelled() then return false, "Cancelled" end
			if status.enabled then
				local recovery, why = credentials.persistent(M.data)
				if not recovery then return false, why end
				guarded.recovery = recovery
			end
			local nextData = credentials.withoutVault(M.data)
			nextData.security.rememberCredentials = true
			nextData.security.credentialProtection = "unprotected"
			local ok, why = writeSnapshot(nextData, true, guarded)
			if not guarded.owned() then return false, "Cancelled" end
			if not ok then
				if why ~= "Cancelled" then M.storageError = why end
				return false, why
			end
			M.data.credentialVault, M.data.credentialVaultLocked = nil, nil
			M.data.security.rememberCredentials = true
			M.data.security.credentialProtection = "unprotected"
			challengePending = false
			vault.clear()
			M.storageError, M.dirty = nil, savedRevision ~= revision
			return true
		end)
	end
	local function removeVault(discard)
		if operation then return false, "A credential vault operation is already in progress." end
		local status = M.vaultStatus()
		if not status.enabled then return false, "No credential vault is configured." end
		if status.locked and not discard then return false, "Unlock the credential vault before disabling it." end
		return transact(nil, function(guarded)
			local savedRevision = revision
			local nextData = credentials.withoutVault(discard and credentials.lockedVault(M.data) or M.data)
			nextData.security.rememberCredentials = false
			nextData.security.credentialProtection = "password"
			local ok, why = writeSnapshot(nextData, true, guarded)
			if guarded.cancelled() then return false, "Cancelled" end
			if not ok then M.storageError = why; return false, why end
			if discard then credentials.applyVault(M.data, nextData) end
			M.data.credentialVault, M.data.credentialVaultLocked = nil, nil
			M.data.security.rememberCredentials = false
			M.data.security.credentialProtection = "password"
			if required then challengePending = true end
			vault.clear()
			M.storageError, M.dirty = nil, savedRevision ~= revision
			M.changed:fire("security.rememberCredentials", false)
			return true
		end)
	end
	function M.disableVault()
		if required then return false, "Use the credential storage controls to explicitly choose unprotected storage." end
		return removeVault(false)
	end
	function M.resetVault() return removeVault(true) end

	dispose.add(function()
		generation = generation + 1
		operation = nil
		if M.data.credentialVault ~= nil then
			-- Preserve the latest edits for bootstrap's final save before releasing
			-- the session key, even when the debounce has not fired yet.
			local projected = credentials.persistent(M.data)
			if projected then M.data.credentialVault = projected.credentialVault end
			credentials.applyVault(M.data, credentials.lockedVault(M.data))
		end
		vault.clear()
	end, "credential vault configuration")

	function M.setRememberCredentials(enabled)
		if type(enabled) ~= "boolean" then return false, "Choose whether to remember provider credentials." end
		if required then
			if enabled and M.vaultStatus().ready then return true end
			return false, "Use the credential storage controls to choose password protection or unprotected storage."
		end
		if operation or writing or loading then return false, "A credential storage operation is already in progress." end
		if M.data.credentialVault ~= nil then
			if enabled then return true end
			return M.disableVault()
		end
		if not enabled then
			local unreadable = util.get(M.data, "identity.credentialStorageError")
			for _, record in pairs(type(M.data.providers) == "table" and type(M.data.providers.list) == "table" and M.data.providers.list or {}) do
				if type(record) == "table" and record.credentialStorageError then unreadable = true end
			end
			if unreadable then return false, "Unreadable saved credentials are being preserved. Replace or remove the affected credentials before switching to session-only storage." end
		end
		local snapshot = util.deepCopy(M.data)
		local savedRevision = revision
		snapshot.security = type(snapshot.security) == "table" and snapshot.security or {}
		snapshot.security.rememberCredentials = enabled
		if fsx.enabled then
			local ok = writeSnapshot(snapshot, true)
			if not ok then
				M.storageError = "Saved credential storage could not be verified. Old plaintext files may remain. Keep this session open to retain your keys."
				return false, "Could not verify credential storage. The previous setting remains active; saved credentials may still be on disk. Keep this session open to retain your keys."
			end
		elseif enabled then
			return false, "This executor cannot save credentials because filesystem access is unavailable."
		else
			return false, "Cannot verify removal of saved credentials without filesystem access. Remove saved credentials from UAI/config.json before relying on session-only storage."
		end
		-- Retain original live records and request snapshots, including key IDs.
		M.data.security = snapshot.security
		M.dirty = savedRevision ~= revision
		M.storageError = nil
		M.changed:fire("security.rememberCredentials", enabled)
		if M.dirty then flush() end
		return true
	end

	-- Applies one validated snapshot. Persistence is attempted before replacing the
	-- live table, and subscribers see the complete new configuration in one event.
	function M.replace(snapshot)
		if type(snapshot) ~= "table" then return false, "configuration must be a table" end
		if operation or writing or loading or M.accessProblem() then return false, "Unlock this device's credential vault and finish its current save before importing settings." end
		local nextData = util.merge(DEFAULTS, credentials.withoutVault(snapshot))
		nextData.security.rememberCredentials = M.get("security.rememberCredentials", true)
		nextData.security.credentialProtection = M.get("security.credentialProtection", "password")
		if M.data.credentialVault ~= nil then
			nextData.credentialVault, nextData.credentialVaultLocked = M.data.credentialVault, false
		end
		retirePreferences(nextData)
		if fsx.enabled then
			replacing = true
			local called, ok, _, projected = pcall(writeSnapshot, nextData, M.storageError ~= nil)
			replacing = nil
			if not called or not ok then return false, "Could not save imported settings. Your current configuration is unchanged." end
			nextData.credentialVault = projected.credentialVault
		elseif nextData.credentialVault ~= nil then
			return false, "Cannot update encrypted credentials without filesystem access."
		end
		M.storageError = nil
		M.data = nextData
		M.loaded = true
		M.dirty = false
		M.changed:fire(nil, M.data)
		-- Live layout consumers listen for this exact path.
		M.changed:fire("ui.layout", M.data.ui.layout)
		return true, fsx.enabled == true
	end

	function M.toggle(path)
		local value = M.get(path) ~= true
		return M.set(path, value)
	end

	function M.reset(section)
		local problem = M.accessProblem()
		if problem then return false, problem end
		local root = tostring(section):match("^[^%.]+")
		if root == "security" then return false, "Use the password vault controls to change credential storage with verification." end
		if operation or writing or loading or (M.vaultStatus().enabled and (not section or root == "providers" or root == "identity" or root == "security"))
			or tostring(section):match("^credentialVault") then
			return false, "Disable or remove the credential vault before resetting credential settings."
		end
		if not section or section == "ui" then
			local capture = env.loadedModules and env.loadedModules["runtime/remote_capture"]
			if capture then capture.stop("settings reset") end
		end
		if section then
			util.set(M.data, section, util.deepCopy(util.get(DEFAULTS, section)))
		else
			M.data = util.deepCopy(DEFAULTS)
		end
		M.changed:fire(section, nil)
		M.save()
	end

	return M
end
