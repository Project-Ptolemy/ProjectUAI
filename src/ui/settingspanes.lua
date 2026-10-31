-- What is in the settings, as a list of panes.
--
-- Two surfaces render these: the Settings panel stacks every pane in one scroll, and
-- the settings dialog the sidebar opens shows one at a time behind a category list.
-- Declaring them once is what keeps the two from drifting -- the dialog used to hold
-- its own copy of three appearance rows, none of which were wired to anything, while
-- the panel held the real ones.
--
-- A pane is `{ id, section, label, icon, build(container) }`. `build` is handed a
-- column to fill and returns nothing. Controls read their initial configuration
-- when built; a retaining dialog invalidates panes when that configuration or
-- their live facts change, preserving drafts only for unchanged bound values.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local configTransfer = env.require("runtime/config_transfer")
	local credentials = env.require("runtime/credentials")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local fsx = env.require("runtime/fsx")
	local place = env.require("runtime/place")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local icons = env.require("ui/icons")
	local overlay = env.require("ui/overlay")
	local quickchat = env.require("ui/quickchat")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local R = env.require("ui/settingsrows")
	local permissions = env.require("agent/permissions")
	local state = env.require("agent/state")
	local usage = env.require("agent/usage")
	local stats = env.require("agent/stats")
	local registry = env.require("agent/registry")
	local sessions = env.require("agent/session")
	local providers = env.require("provider/registry")
	local ua = env.require("net/ua")
	local http = env.require("net/http")
	local bridgeModule = env.require("net/bridge")

	local M = {}
	function M.observeChanges(callback)
		local subscriptions = { config.changed:connect(callback), providers.changed:connect(callback),
			permissions.changed:connect(callback), usage.changed:connect(callback), stats.changed:connect(callback) }
		return function() for _, unsubscribe in ipairs(subscriptions) do unsubscribe() end end
	end

	-- The token budgets. They stop where the widest models of the moment do -- a
	-- million in, a hundred and twenty-eight thousand out -- rather than where a
	-- default conversation needs, because a ceiling that cannot reach the model is
	-- indistinguishable from the model not having it.
	local BUDGET_STOPS = {
		4000, 8000, 12000, 16000, 24000, 32000, 48000, 64000, 96000,
		128000, 160000, 200000, 256000, 320000, 400000, 512000, 750000, 1000000,
	}
	local REPLY_STOPS = { 256, 512, 1024, 2048, 4096, 8192, 16000, 24000, 32000, 64000, 96000, 128000 }
	local RESULT_STOPS = { 1000, 2000, 4000, 6000, 8000, 12000, 16000, 24000, 32000, 48000, 64000, 96000, 128000 }

	-- The request timeout. The top stop is the default and is the highest of any
	-- clock in this client: no other deadline can rescue a model call that times out,
	-- so it has to sit above every other budget by default. The stops are the
	-- plausible lowerings rather than a linear scale -- the difference between sixty
	-- seconds and ninety is a setting someone might want, and the difference between
	-- eight hours and nine is not.
	local REQUEST_STOPS = { 30, 60, 120, 180, 300, 600, 900, 1800, 3600, 7200, 21600, 43200, 86400 }

	-- Each pane builds into a fresh column, so the layout order it needs is just a
	-- running count. This is the only bookkeeping a pane does.
	local function builder(container)
		local order = 0
		local api = {}
		function api.order()
			order = order + 1
			return order
		end
		-- Share the same heading/card rhythm as the provider and settings panels.
		function api.section(title, description)
			return R.section(container, {
				title = title,
				description = description,
				layoutOrder = api.order(),
			})
		end
		function api.note(text, colour)
			return R.paragraph(container, text, { color = colour, layoutOrder = api.order() })
		end
		return api
	end

	local function accentOptions()
		local out = {}
		for key, entry in pairs(theme.ACCENTS) do
			out[#out + 1] = { value = key, label = entry.label }
		end
		table.sort(out, function(a, b) return a.label < b.label end)
		return out
	end

	-- General -----------------------------------------------------------------

	local function paneGeneral(container)
		local build = builder(container)

		local appearance = build.section("Appearance",
			"Layout follows the viewport by default. Pin it if you would rather it did not.")

		P.text(appearance, { text = "Accent", role = "small" })
		C.segmented(appearance, {
			options = accentOptions(),
			value = config.get("ui.accent", "claude"),
			onChange = function(value) config.set("ui.accent", value) end,
		})

		P.text(appearance, { text = "Density", role = "small" })
		C.segmented(appearance, {
			options = {
				{ value = "comfortable", label = "Comfortable" },
				{ value = "compact", label = "Compact" },
			},
			value = config.get("ui.density", "comfortable"),
			onChange = function(value) config.set("ui.density", value) end,
		})

		P.text(appearance, { text = "Layout", role = "small" })
		C.segmented(appearance, {
			options = {
				{ value = "auto", label = "Auto" },
				{ value = "sheet", label = "Sheet" },
				{ value = "panel", label = "Panel" },
				{ value = "window", label = "Window" },
			},
			value = config.get("ui.layout", "auto"),
			onChange = function(value) config.set("ui.layout", value) end,
		})

		R.number(appearance, "Text scale", "Multiplies every type size.", "ui.fontScale", 0.85, 1.4, 0.05)
		local conversation = build.section("Conversation display", "Choose how messages, tool activity and notifications appear.")
		R.toggle(conversation, {
			label = "Show reasoning",
			hint = "Display the model's chain of thought when it sends one. Applies to the conversation already on screen.",
			path = "ui.showReasoning",
		})
		R.toggle(conversation, {
			label = "Show the code a tool was given",
			hint = "Draws the Luau, the file body or the property map a tool call carries under its "
				.. "row, outside the fold. Off, it is still there behind the row's own caret.",
			path = "ui.showToolCode",
		})
		R.toggle(conversation, {
			label = "Expand tool detail",
			hint = "Open the remaining arguments and the result by default, rather than on the first click.",
			path = "ui.showToolDetail",
		})
		R.toggle(conversation, {
			label = "Show token counts",
			hint = "Token and cost details in the composer's options menu.",
			path = "ui.showUsage",
		})
		R.toggle(conversation, {
			label = "Show the activity card",
			hint = "The greeting and the counters an empty conversation opens with.",
			path = "ui.showActivity",
		})
		R.toggle(conversation, {
			label = "Notify while minimized",
			hint = "A toast when a turn finishes, fails or is stopped with the window closed -- from any conversation. The count on the launcher appears either way.",
			path = "ui.notifications",
		})

		-- Keep the live layout note with the appearance controls it describes.
		local viewportNote = P.text(appearance, {
			text = "Now: " .. responsive.describe(),
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		viewportNote.Size = UDim2.new(1, 0, 0, 0)
		local unsubscribe = responsive.changed:connect(function()
			if not viewportNote.Parent then return end
			viewportNote.Text = "Now: " .. responsive.describe()
		end)
		viewportNote.Destroying:Connect(function() pcall(unsubscribe) end)

		local shortcuts = build.section("Shortcuts",
			"Quick chat opens in the middle of the screen, takes one message to the conversation the Chat panel shows, and closes itself.")
		local row = P.row(shortcuts, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm })
		local text = P.column(row, {
			size = UDim2.new(0, 0, 0, 0), auto = "Y", flex = "Fill", gap = 0, layoutOrder = 1,
		})
		P.text(text, { text = "Quick chat key", role = "label", wrap = true, auto = "Y" })
		local keyHint = P.text(text, {
			text = "",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		local keyButton
		local function describeKey()
			keyHint.Text = "Currently " .. quickchat.keyName()
				.. ". Press the button, then the key you want it to be."
		end
		keyButton = P.button(row, {
			name = "QuickKey",
			text = quickchat.keyName(),
			variant = "secondary",
			size = "sm",
			width = theme.size.keyColumn + theme.space.xxl,
			layoutOrder = 2,
			onClick = function()
				keyButton.setText("press a key")
				-- Captured rather than typed: a user thinks "this key", and a character
				-- would not survive a different keyboard layout.
				quickchat.captureNext(function(name)
					if not keyButton.instance.Parent then return end
					keyButton.setText(name)
					describeKey()
				end)
			end,
		})
		keyButton.instance.LayoutOrder = 2
		describeKey()
	end

	-- Privacy -----------------------------------------------------------------

	local function paneprivacy(container)
		local build = builder(container)

		local where = build.section("Where your data goes",
			"Enabled providers and connected local relays are listed below. The selected route receives "
			.. "your messages and relevant tool results. Tools can make additional requests when used.")

		local list = {}
		for _, record in ipairs(providers.list()) do
			if record.enabled ~= false then
				list[#list + 1] = {
					key = record.label,
					value = credentials.cleanUrl(record.baseUrl),
					tone = record.id == (providers.active() or {}).id and "good" or nil,
				}
			end
		end
		if env.require("net/bridge_connection").enabled() then
			list[#list + 1] = { key = "Web bridge", value = bridgeModule.status().url }
		end
		local relayLink = env.require("net/relay_link")
		if relayLink.usable() then
			list[#list + 1] = { key = "Companion relay", value = "127.0.0.1:" .. tostring(relayLink.status().port) }
		end
		if #list == 0 then
			R.paragraph(where, "No enabled provider or connected local relay.")
		else
			R.facts(where, list, { name = "Endpoints" })
		end

		local storage = build.section("Provider credential storage",
			"Choose password encryption or explicitly save without encryption. Protected credentials need your password each time UAI starts. Other scripts can still intercept credentials while you use them.")
		local storageStatus = R.paragraph(storage, "", { name = "CredentialStorageStatus", layoutOrder = 1 })
		local function refreshStorage()
			if not storage.Parent then return end
			local vault = config.vaultStatus()
			local unverified = type(config.storageError) == "string" and config.storageError ~= ""
			storageStatus.Text = unverified and "Saved credential storage could not be verified. Keep this run open to preserve your keys and retry the storage choice."
				or not fsx.enabled and "Filesystem access is unavailable. UAI needs verified storage before it can save your protection choice."
				or vault.enabled and (vault.locked and "Saved provider credentials are encrypted and locked. Enter your master password to open UAI."
					or "Saved provider credentials are encrypted. The vault is unlocked for this run.")
				or vault.protection == "unprotected" and "Your API keys are saved without encryption. Their byte encoding is reversible; anyone with file access can recover them. Password prompts are skipped."
				or "Set a master password or explicitly continue without encryption. Existing keys and key-pool settings carry over after storage is verified."
			storageStatus.TextColor3 = (unverified or not vault.enabled) and theme.color.warn or theme.color.textSecondary
		end
		R.paragraph(storage,
			"The vault covers provider keys, custom headers, query parameters and body overrides. Existing copies, clipboard history, backups and other scripts are outside the vault. "
			.. "Review remaining configuration before sharing it; notes and other text can contain anything you entered.", { layoutOrder = 2 })
		R.paragraph(storage,
			"Replace personal keys regularly at the provider and revoke the old keys. Revoke immediately if theft is suspected. Daily replacement can shorten exposure, but it does not stop a malicious script stealing the replacement. "
			.. "UAI's Rotate keys option only takes turns between keys; it does not renew or revoke them.", { layoutOrder = 3 })
		refreshStorage()
		local unsubscribeStorage = config.changed:connect(function(path)
			if path == nil or path == "security" or path == "security.vault" then refreshStorage() end
		end)
		storage.Destroying:Connect(unsubscribeStorage)

		local vaultSection = build.section("Master-password vault",
			"Encrypted storage requires unlocking each run. There is no password recovery: forgotten-password reset removes saved vault credentials. You can also choose unprotected storage after unlocking.")
		local vaultStatus = R.paragraph(vaultSection, "", { name = "CredentialVaultStatus", layoutOrder = 1 })
		local vaultButton = P.button(vaultSection, { name = "ManageCredentialVault", text = "Set master password", fill = true, layoutOrder = 2,
			onClick = function() env.require("ui/credentialvault").open() end })
		local function refreshVault()
			if not vaultSection.Parent then return end
			local vault = config.vaultStatus()
			vaultStatus.Text = vault.busy and "A vault operation is in progress."
				or vault.error or (vault.enabled and (vault.locked and "Locked. Your encrypted credentials need your master password."
					or "Unlocked for this run. Lock the vault or change the master password below.")
				or vault.protection == "unprotected" and "Unprotected storage is active. Set a master password to encrypt your saved credentials."
				or "Choose password protection or continue without encryption before using UAI.")
			vaultStatus.TextColor3 = (vault.error or vault.protection == "unprotected") and theme.color.warn or theme.color.textSecondary
			vaultButton.setText(vault.enabled and (vault.locked and "Unlock credential vault" or "Manage credential vault") or "Set master password")
			vaultButton.setEnabled(not vault.busy)
		end
		refreshVault()
		local unsubscribeVault = config.changed:connect(function(path)
			if path == nil or path == "security" or path == "security.vault" then refreshVault() end
		end)
		vaultSection.Destroying:Connect(unsubscribeVault)

		local secrets = build.section("Logs and exports",
			"Request logs mask recognised credentials. Configuration and diagnostic exports exclude credential fields by default. "
			.. "Only the explicitly labelled private configuration copy includes credentials; keep it private.")
		R.toggle(secrets, {
			label = "Mirror the log to the console",
			hint = "Also print every entry with print/warn, which a developer console can read.",
			path = "logs.mirror",
			onChange = function(value) log.mirror = value == true end,
		})
		P.text(secrets, { text = "Level", role = "small" })
		C.segmented(secrets, {
			options = {
				{ value = "debug", label = "Debug" },
				{ value = "info", label = "Info" },
				{ value = "warn", label = "Warn" },
				{ value = "error", label = "Error" },
			},
			value = config.get("logs.level", "info"),
			onChange = function(value)
				config.set("logs.level", value)
				log.setLevel(value)
			end,
		})

		local clear = build.section("Clear what is stored",
			"Each of these is immediate and cannot be undone.")
		R.actions(clear, {
			{
				name = "ClearRequests",
				text = "Request history",
				variant = "ghost",
				onClick = function()
					http.clearHistory()
					overlay.toast("Request history cleared", "good", 2)
				end,
			},
			{
				name = "ClearLog",
				text = "Log",
				variant = "ghost",
				onClick = function()
					log.clear()
					overlay.toast("Log cleared", "good", 2)
				end,
			},
			{
				name = "ClearConversations",
				text = "All conversations",
				variant = "danger",
				onClick = function()
					overlay.confirm({
						title = "Delete every conversation?",
						description = "Every transcript on disk is removed. The activity counters are kept.",
						confirmText = "Delete",
						danger = true,
						onConfirm = function()
							for _, session in ipairs(sessions.list()) do
								sessions.remove(session.id)
							end
							overlay.toast("Conversations deleted", "good", 2)
						end,
					})
				end,
			},
			{
				name = "ClearActivity",
				text = "Activity history",
				variant = "danger",
				onClick = function()
					overlay.confirm({
						title = "Reset the activity history?",
						description = "Every day, model and token count this client has recorded is discarded. "
							.. "The conversations themselves are kept.",
						confirmText = "Reset",
						danger = true,
						onConfirm = function()
							stats.reset()
							overlay.toast("Activity history reset", "good", 2)
						end,
					})
				end,
			},
		})
	end

	-- Usage -------------------------------------------------------------------

	local function paneUsage(container)
		local build = builder(container)

		local live = build.section("This session",
			"What the client has spent since it started, as the provider reported it.")
		local liveText = P.text(live, {
			name = "UsageLine",
			text = usage.line(),
			role = "monoSmall",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
		})
		liveText.Size = UDim2.new(1, 0, 0, 0)
		local unsubscribe = usage.changed:connect(function()
			if not liveText.Parent then return end
			liveText.Text = usage.line()
		end)
		liveText.Destroying:Connect(function() pcall(unsubscribe) end)
		R.actions(live, { {
			name = "ResetCounters",
			text = "Reset counters",
			variant = "ghost",
			onClick = function() usage.reset() end,
		} })

		local window = stats.window("all")
		local totals = build.section("Everything recorded",
			"Counted from what this client observed and kept on disk, so it survives a restart.")
		local facts = {
			{ key = "Conversations", value = util.formatNumber(window.sessions) },
			{ key = "Messages", value = util.formatNumber(window.messages) },
			{ key = "Requests", value = util.formatNumber(window.requests) },
			{ key = "Tokens in", value = util.formatNumber(window.tokensIn) },
			{ key = "Tokens out", value = util.formatNumber(window.tokensOut) },
			{ key = "Tool calls", value = util.formatNumber(window.toolCalls) },
			{ key = "Active days", value = util.formatNumber(window.activeDays) },
		}
		local cost = usage.formatCost(window.cost)
		if cost ~= "" then
			facts[#facts + 1] = { key = "Known cost estimate", value = cost }
		end
		if window.tokensFrom then
			facts[#facts + 1] = { key = "Tokens since", value = clock.describeDay(clock.dayKey(window.tokensFrom)) }
		end
		R.facts(totals, facts, { name = "Totals" })
		if not window.tokensFrom then
			R.paragraph(totals,
				"No request has been recorded yet, so there are no token counts. Messages and "
				.. "conversations from before counting began were read back out of the transcripts "
				.. "already on disk; tokens could not be, because nothing recorded them.")
		end

		if #window.models > 0 then
			local models = build.section("By model", "Which model spent what.")
			for index, row in ipairs(window.models) do
				C.keyValue(models, {
					key = row.id,
					value = string.format("%s tokens  %s  %d%%",
						util.formatCompact(row.tokens), util.pluralise(row.requests, "request"),
						math.floor((row.share or 0) * 100 + 0.5)),
					layoutOrder = index,
				})
			end
		end

		local tools = stats.topTools(8)
		if #tools > 0 then
			local toolCard = build.section("Most used tools", "Across every conversation.")
			for index, entry in ipairs(tools) do
				C.keyValue(toolCard, {
					key = entry.name,
					value = util.formatNumber(entry.count),
					layoutOrder = index,
				})
			end
		end
	end

	-- Claude Code -------------------------------------------------------------

	-- A live sample of one code palette, drawn in that palette's own colours rather
	-- than the active one -- which is what lets both be shown side by side and picked
	-- by pressing the one you want, the way the reference client does it.
	local function codePreview(parent, name, order, onPick)
		local palette = theme.CODE_THEMES[name] or theme.CODE_THEMES.dark
		local selected = theme.codeThemeName == name
		local lineHeight = theme.text.monoSmall.height + theme.space.hair
		-- Four sample lines, a bar, and the two hair-thin paddings around them. Stated
		-- once and passed as the card's own size: P.rowButton takes `size` when it is
		-- given one and ignores `height` unless the button is auto-sizing, so passing
		-- both -- with a zero height in the size -- gave the card no height at all and
		-- spilled a hundred pixels of preview over the control below it.
		local cardHeight = lineHeight * 4 + theme.size.rowTight + theme.space.hair * 2
		local card = P.rowButton(parent, {
			name = "CodePreview_" .. name,
			vertical = true,
			size = UDim2.new(0.5, -theme.space.sm, 0, cardHeight),
			height = cardHeight,
			bg = palette.surface,
			radius = theme.radius.md,
			gap = 0,
			padding = theme.space.hair,
			alignY = "Top",
			clip = true,
			stroke = true,
			strokeColor = selected and theme.color.accent or palette.border,
			bgHover = palette.surface,
			bgPress = palette.surface,
			bgSelected = palette.surface,
			selected = selected,
			layoutOrder = order,
			onClick = function()
				config.set("ui.codeTheme", name)
				if onPick then pcall(onPick, name) end
			end,
		})

		local head = P.row(card.row, {
			name = "PreviewBar",
			size = UDim2.new(1, 0, 0, theme.size.rowTight),
			bg = palette.bar,
			padding = { x = theme.space.xs },
			gap = theme.space.xs,
			layoutOrder = 1,
		})
		P.text(head, {
			text = palette.label,
			role = "caption",
			color = palette.gutter,
			size = UDim2.new(0, 0, 1, 0),
			flex = "Fill",
			truncate = true,
			layoutOrder = 1,
		})
		if selected then
			local mark = P.frame(head, {
				size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
				layoutOrder = 2,
			})
			icons.check(mark, theme.size.icon, theme.color.accent)
		end

		local lines = {
			{ number = 1, prefix = " ", text = "local function greet(name)" },
			{ number = 2, prefix = "-", text = 'return "Hello, " .. name', tone = "remove" },
			{ number = 2, prefix = "+", text = 'return string.format("Hi %s!", name)', tone = "add" },
			{ number = 3, prefix = " ", text = "end" },
		}
		for index, line in ipairs(lines) do
			local fill, ink = nil, palette.text
			if line.tone == "add" then
				fill, ink = palette.addSurface, palette.addText
			elseif line.tone == "remove" then
				fill, ink = palette.removeSurface, palette.removeText
			end
			local row = P.row(card.row, {
				name = "Line" .. tostring(index),
				size = UDim2.new(1, 0, 0, lineHeight),
				bg = fill,
				gap = theme.space.xs,
				padding = { x = theme.space.xs },
				layoutOrder = index + 1,
			})
			P.text(row, {
				text = tostring(line.number),
				role = "monoSmall",
				color = palette.gutter,
				align = "Right",
				size = UDim2.fromOffset(theme.space.md, theme.text.monoSmall.height),
				layoutOrder = 1,
			})
			P.text(row, {
				text = line.prefix,
				role = "monoSmall",
				color = ink,
				size = UDim2.fromOffset(theme.space.sm, theme.text.monoSmall.height),
				layoutOrder = 2,
			})
			P.text(row, {
				text = line.text,
				role = "monoSmall",
				color = ink,
				size = UDim2.new(0, 0, 0, theme.text.monoSmall.height),
				flex = "Fill",
				truncate = true,
				layoutOrder = 3,
			})
		end
		return card
	end

	local function paneClaudeCode(container)
		local build = builder(container)

		local appearance = build.section("Code appearance",
			"How a fenced code block is drawn, in the transcript and everywhere else. "
			.. "Press one to use it.")
		local row = P.row(appearance, {
			name = "CodeThemes",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.md,
			alignY = "Top",
		})
		for index, key in ipairs(theme.CODE_THEME_ORDER) do
			codePreview(row, key, index)
		end

		local fontOptions = {}
		for _, key in ipairs(theme.CODE_ORDER) do
			fontOptions[#fontOptions + 1] = { value = key, label = theme.CODE_FONTS[key].label }
		end
		R.segmented(appearance, {
			name = "CodeFont",
			label = "Code font",
			hint = "Monospace fonts available on this device. Used for code and diagnostic details.",
			path = "ui.codeFont",
			options = fontOptions,
		})

		local interface = build.section("Appearance",
			"The type the interface itself is set in.")
		local interfaceOptions = {}
		for _, key in ipairs(theme.INTERFACE_ORDER) do
			interfaceOptions[#interfaceOptions + 1] = { value = key, label = theme.INTERFACE_FONTS[key].label }
		end
		R.select(interface, {
			name = "InterfaceFont",
			label = "Interface font",
			hint = "The font for menus, navigation and messages. Shows the families available on this device.",
			path = "ui.interfaceFont",
			options = interfaceOptions,
		})
		-- What is being rendered, as opposed to what is selected. Two clients can resolve
		-- the same setting differently: the weight axis needs the modern type stack, and
		-- without it every "medium" role falls back to whichever legacy member pairs that
		-- family with a heavier weight. Saying so is cheaper than someone wondering why
		-- their headings look the same as their body text.
		R.paragraph(interface, string.format("Now: %s, %s.",
			theme.interfaceFontName,
			theme.hasFontFace and "with the regular/medium/semibold weight axis"
				or "weights from the legacy font set on this client"))

		-- Text size is the same setting as the scale slider under General, expressed the
		-- way the reference client expresses it. One value, two controls: the segmented
		-- one reads the scale back rather than keeping a second copy of it.
		local scale = tonumber(config.get("ui.fontScale", 1)) or 1
		local currentSize = "medium"
		if scale < 0.95 then currentSize = "small" end
		if scale > 1.08 then currentSize = "large" end
		R.segmented(interface, {
			name = "TranscriptSize",
			label = "Transcript text size",
			hint = "The same value as the text scale under General.",
			value = currentSize,
			options = {
				{ value = "small", label = "Small" },
				{ value = "medium", label = "Medium" },
				{ value = "large", label = "Large" },
			},
			onChange = function(value)
				local scales = { small = 0.9, medium = 1, large = 1.15 }
				config.set("ui.fontScale", scales[value] or 1)
			end,
		})

		R.segmented(interface, {
			name = "TranscriptWidth",
			label = "Transcript width",
			hint = "The widest the transcript and the composer will grow on a large screen.",
			path = "ui.transcriptWidth",
			options = {
				{ value = "narrow", label = "Narrow" },
				{ value = "medium", label = "Medium" },
				{ value = "wide", label = "Wide" },
			},
		})
	end

	-- Cowork ------------------------------------------------------------------

	local function paneCowork(container)
		local build = builder(container)
		build.section("Cowork",
			"A browser on this machine can join the conversation that is open here. Both sides "
			.. "dial out to a small local process, because a Roblox client cannot accept a "
			.. "connection.")
		env.require("ui/panels/cowork").rows(container, { layoutOrder = build.order() })
		build.order()
	end

	-- Import and export -------------------------------------------------------

	local EXPORT_DIR = "export"

	-- What an export contains, and what it deliberately does not.
	local function exportPayload()
		local settings = credentials.sanitise(config.data)
		return {
			exportedAt = clock.ms(),
			version = env.info and env.info.version or "",
			place = place.facts(),
			settings = settings,
			activity = stats.data,
		}
	end

	local function fullConfigImport()
		local modal = overlay.modal({
			title = "Import configuration",
			description = "Paste a configuration copy and review it before replacing your settings. Private copies can contain credentials.",
			width = theme.size.modalWide,
			height = theme.size.dialogTall,
			scroll = true,
		})
		if not modal then return end
		local candidate, applyButton, passwordModal
		local sourceRevision = 0
		modal.scrim.Destroying:Connect(function()
			candidate = nil
			if passwordModal and not passwordModal.closed then passwordModal.close() end
		end)
		local status = P.text(modal.content, {
			name = "ConfigImportStatus",
			text = "Paste your JSON below, then select Review.",
			role = "small",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
			layoutOrder = 1,
		})
		local field = P.field(modal.content, {
			name = "ConfigImportJSON",
			placeholder = '{"format":"project-uai-config","version":1,...}',
			role = "monoSmall",
			multiline = true,
			height = theme.text.monoSmall.height * 8 + theme.space.md * 2,
			layoutOrder = 2,
			onChange = function()
				sourceRevision = sourceRevision + 1
				candidate = nil
				if passwordModal and not passwordModal.closed then passwordModal.close() end
				if applyButton then applyButton.setEnabled(false) end
				status.Text = "Select Review to validate this configuration."
				status.TextColor3 = theme.color.textSecondary
			end,
		})
		P.text(modal.content, {
			text = "Applying replaces providers, credentials, permissions and preferences. Copies that exclude credentials require you to enter them again. This device keeps its storage choice and any vault password. Conversations, activity history, workspace files and skill files stay on this device.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 3,
		})
		P.button(modal.footer, {
			text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1,
			onClick = function() modal.close() end,
		})
		local function displayPreview(preview, err)
			if modal.closed then return end
			candidate = preview
			applyButton.setEnabled(preview ~= nil)
			if not preview then
				status.Text = tostring(err)
				status.TextColor3 = theme.color.warn
				return
			end
			local summary = preview.summary
			status.Text = string.format("Ready to import\n%s · %s\nActive provider: %s\nPermission mode: %s · %s\n%s · Bridge %s",
				util.pluralise(summary.providers, "provider"), util.pluralise(summary.keys, "API key"),
				util.ellipsis(summary.active, 64), permissions.MODE_LABELS[summary.permissionMode] or summary.permissionMode,
				util.pluralise(summary.rules, "rule"), util.pluralise(summary.memory, "memory entry"),
				summary.bridgeEnabled and "enabled" or "disabled")
			status.Text = status.Text .. (summary.credentialsIncluded == false
				and "\nCredentials excluded: enter your credentials again after import."
				or "\nThis copy can include private credentials.")
			status.Text = status.Text .. (config.vaultStatus().enabled
				and "\nThis device keeps its own master-password vault."
				or summary.rememberCredentials == true and "\nThis device remembers provider credentials using reversible byte encoding."
				or "\nProvider credentials will stay in this run only.")
			status.TextColor3 = theme.color.text
		end
		P.button(modal.footer, {
			name = "ReviewConfigImport", text = "Review", size = "sm", layoutOrder = 2,
			onClick = function()
				if passwordModal and not passwordModal.closed then return end
				local source, revision = field.get(), sourceRevision
				local preview, err, reason = configTransfer.preview(source)
				if reason == "password" then
					candidate = nil; applyButton.setEnabled(false)
					status.Text, status.TextColor3 = "Enter the source master password to review this encrypted copy.", theme.color.textSecondary
					passwordModal = env.require("ui/credentialvault").open("import", {
						cancelled = function() return modal.closed or sourceRevision ~= revision end,
						submit = function(password, options)
							local unlocked, why = configTransfer.preview(source, { password = password, progress = options.progress, cancelled = options.cancelled })
							return unlocked ~= nil, unlocked or why
						end,
						onSuccess = function(unlocked) if not modal.closed and sourceRevision == revision then displayPreview(unlocked) end end,
					})
				else
					displayPreview(preview, err)
				end
			end,
		})
		applyButton = P.button(modal.footer, {
			name = "ApplyConfigImport", text = "Apply", variant = "primary", size = "sm", layoutOrder = 3,
			enabled = false,
			onClick = function()
				if not candidate then return end
				local ok, persisted = configTransfer.apply(candidate)
				if not ok then
					status.Text = tostring(persisted)
					status.TextColor3 = theme.color.warn
					return
				end
				log.setLevel(config.get("logs.level", "info"))
				log.mirror = config.get("logs.mirror", false) == true
				providers.changed:fire("import")
				permissions.changed:fire("import")
				state.memoryChanged:fire(config.get("memory.entries", {}))
				env.require("runtime/skills").changed:fire(nil, nil)
				modal.close(true)
				-- The Settings dialog survives app rebuilds, so close its stale controls.
				for index = #overlay.open, 1, -1 do
					local entry = overlay.open[index]
					if entry.card and entry.card.Name == "SettingsDialog" then entry.close() end
				end
				overlay.toast(persisted and "Configuration imported with this device's credential storage preference"
					or "Configuration imported for this session", "good", 4)
			end,
		})
		clock.delay(theme.duration("fast"), function()
			if not modal.closed then field.focus() end
		end)
	end

	local function paneImportExport(container)
		local build = builder(container)

		local transfer = build.section("Configuration transfer",
			"Copy provider records, permissions and preferences to another device. The default copy excludes credential fields, custom headers, query parameters and body overrides. Enter those again after import.")
		R.paragraph(transfer,
			"Saved memory and skill preferences are included. Review other text before sharing it. Conversations, activity history, workspace files and skill files are not included.")
		local copyButton = P.button(transfer, {
			name = "CopyFullConfig",
			text = "Copy config without credentials",
			variant = "secondary",
			fill = true,
			enabled = caps.clipboard,
			onClick = function()
				local copied, err = configTransfer.copyToClipboard(caps.fn.clipboard)
				overlay.toast(copied and "Configuration copied with credential fields excluded" or tostring(err), copied and "good" or "warn", 4)
			end,
		})
		copyButton.setEnabled(caps.clipboard)
		local privateCopyButton = P.button(transfer, {
			name = "CopyPrivateConfig", text = "Copy private config including credentials", variant = "ghost", fill = true,
			enabled = caps.clipboard,
			onClick = function()
				local copied, err = configTransfer.copyToClipboard(caps.fn.clipboard, { includeCredentials = true })
				local message = config.vaultStatus().enabled and "Private configuration copied with encrypted provider credentials. Import requires its master password. Other settings and connection tokens remain readable; keep it private."
					or "Private configuration copied with recoverable provider credentials and connection tokens. Do not share it."
				overlay.toast(copied and message
					or tostring(err), copied and "good" or "warn", 5)
			end,
		})
		privateCopyButton.setEnabled(caps.clipboard)
		R.paragraph(transfer,
			"Private copies retain your storage mode. Encrypted copies require the source vault's password; unprotected copies contain recoverable credentials. Other settings and bridge/relay tokens remain readable. Clipboard managers may retain either copy.")
		if not caps.clipboard then
			R.paragraph(transfer, "This host cannot write to the clipboard. You can still paste an export to import it.")
		end
		P.button(transfer, {
			name = "PasteFullConfig", text = "Paste configuration to import", fill = true,
			onClick = fullConfigImport,
		})

		local out = build.section("Diagnostic export",
			"Writes a copy of your settings and the activity history into the client's own "
			.. "folder. Credential fields, custom headers, query parameters, body overrides and connection tokens "
			.. "are excluded. Review remaining text before sharing.")
		local outPath = EXPORT_DIR .. "/uai-export.json"
		local result = P.text(out, {
			name = "ExportResult",
			text = fsx.enabled and ("Will write " .. fsx.root .. "/" .. outPath)
				or "This host has no filesystem, so an export can only go to the clipboard.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		result.Size = UDim2.new(1, 0, 0, 0)

		local actions = {}
		if fsx.enabled then
			actions[#actions + 1] = {
				name = "ExportFile",
				text = "Export to a file",
				variant = "secondary",
				onClick = function()
					local ok, err = fsx.writeJson(outPath, exportPayload())
					result.Text = ok and ("Written to " .. fsx.root .. "/" .. outPath)
						or ("Could not write it: " .. tostring(err))
					overlay.toast(ok and "Exported" or "Export failed", ok and "good" or "warn", 2)
				end,
			}
		end
		if caps.clipboard then
			actions[#actions + 1] = {
				name = "ExportClipboard",
				text = "Copy to clipboard",
				variant = "ghost",
				onClick = function()
					local okEncode, body = pcall(util.encode, exportPayload())
					if not okEncode then
						overlay.toast("Could not encode the export", "warn", 2)
						return
					end
					local ok = env.require("runtime/clipboard").write(body)
					overlay.toast(ok and "Copied" or "Could not reach the clipboard",
						ok and "good" or "warn", 2)
				end,
			}
		end
		if #actions > 0 then R.actions(out, actions) end

		local inbound = build.section("Import",
			"Reads a file from the client's folder and applies the settings in it. Providers, "
			-- Being explicit about this: an import that silently replaced a working key
			-- with "...abcd" from an export would break the client in a way that looks
			-- like the provider rejecting you.
			.. "keys and the bridge token are never imported, because an export does not "
			.. "contain them.")
		local importResult = P.text(inbound, {
			name = "ImportResult",
			text = "",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		importResult.Size = UDim2.new(1, 0, 0, 0)
		R.actions(inbound, { {
			name = "ImportFile",
			text = "Import from a file",
			variant = "secondary",
			onClick = function()
				overlay.prompt({
					title = "Import settings",
					description = "A path inside " .. fsx.root .. ", as it appears in the folder.",
					placeholder = EXPORT_DIR .. "/uai-export.json",
					value = outPath,
					confirmText = "Import",
					onConfirm = function(path)
						local data = fsx.readJson(path, nil)
						local incoming = type(data) == "table" and (data.settings or data) or nil
						if type(incoming) ~= "table" then
							importResult.Text = "Nothing readable at " .. tostring(path)
							return
						end
						local applied = 0
						for _, section in ipairs({ "ui", "agent", "logs", "identity" }) do
							if type(incoming[section]) == "table" then
								config.set(section, util.merge(config.get(section, {}), incoming[section]))
								applied = applied + 1
							end
						end
						importResult.Text = applied > 0
							and (util.pluralise(applied, "section") .. " imported")
							or "That file had no settings in it"
						overlay.toast(importResult.Text, applied > 0 and "good" or "warn", 2)
					end,
				})
			end,
		} })
	end

	-- Desktop app -------------------------------------------------------------

	local function paneDesktop(container)
		local build = builder(container)

		local shell = build.section("Window",
			"Where the interface opens and how much of the screen it takes.")
		R.segmented(shell, {
			name = "OpenPanel",
			label = "Open on",
			hint = "Which surface the interface shows when it is opened.",
			path = "ui.panel",
			options = {
				{ value = "chat", label = "Chat" },
				{ value = "cowork", label = "Cowork" },
				{ value = "providers", label = "Providers" },
				{ value = "tools", label = "Tools" },
				{ value = "logs", label = "Logs" },
			},
		})
		R.toggle(shell, {
			label = "Start with the sidebar collapsed",
			hint = "The conversation list can always be brought back with the toggle in the header.",
			path = "ui.sidebarCollapsed",
		})
		R.toggle(shell, {
			label = "Keep the panel list open",
			hint = "Whether the sidebar's More section starts expanded.",
			path = "ui.sidebarExpanded",
		})
		R.actions(shell, {
			{
				name = "ResetWindow",
				text = "Reset window position",
				variant = "ghost",
				onClick = function()
					config.set("ui.window", util.deepCopy(util.get(config.defaults, "ui.window")))
					overlay.toast("Window position reset", "good", 2)
				end,
			},
			{
				name = "ResetLauncher",
				text = "Reset the launcher",
				variant = "ghost",
				onClick = function()
					config.set("ui.launcher", util.deepCopy(util.get(config.defaults, "ui.launcher")))
					overlay.toast("Launcher reset", "good", 2)
				end,
			},
		})

		local host = build.section("This host",
			"What the client found when it started. None of it is configurable; all of it "
			.. "decides what works.")
		local facts = {
			{ key = "Client", value = tostring(env.info and env.info.version or "") },
			{ key = "Transport", value = caps.http .. (caps.requestName and (" (" .. caps.requestName .. ")") or "") },
			{ key = "Identity", value = caps.uaSupported and "can be sent" or "cannot be sent here", tone = caps.uaSupported and "good" or "warn" },
			{ key = "Filesystem", value = caps.fs and "yes" or "no", tone = caps.fs and "good" or "warn" },
			{ key = "Executor", value = caps.executor },
			{ key = "Viewport", value = responsive.describe() },
		}
		if caps.studio then facts[#facts + 1] = { key = "Studio", value = "yes" } end
		for _, entry in ipairs(place.facts()) do facts[#facts + 1] = entry end
		R.facts(host, facts, { name = "HostFacts" })
	end

	-- Developer ---------------------------------------------------------------

	local function paneDeveloper(container)
		local build = builder(container)

		local logs = build.section("Diagnostics",
			"Every request and every log line the client has kept, and what it keeps them for.")
		local counts = P.text(logs, {
			name = "LogCounts",
			text = "",
			role = "monoSmall",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
		})
		counts.Size = UDim2.new(1, 0, 0, 0)
		local function describeCounts()
			counts.Text = string.format("%s in the request history\n%s in the log\n%s registered for cleanup",
				util.pluralise(#http.history, "entry"),
				util.pluralise(#log.entries, "line"),
				util.pluralise(env.require("runtime/dispose").count(), "handle"))
		end
		describeCounts()
		R.actions(logs, {
			{
				name = "OpenLogs",
				text = "Open the log",
				variant = "secondary",
				onClick = function()
					env.require("ui/app").show("logs")
				end,
			},
			{
				name = "RefreshCounts",
				text = "Refresh",
				variant = "ghost",
				onClick = describeCounts,
			},
			{
				name = "CreateSupportBundle",
				text = "Create support bundle",
				variant = "ghost",
				onClick = function()
					local result, why = env.require("runtime/support_bundle").write()
					if result then
						overlay.toast("Support bundle written to " .. tostring(result.path or "the workspace"), "good", 4)
					else
						overlay.toast("Could not write the support bundle: " .. tostring(why), "warn", 4)
					end
				end,
			},
			{
				name = "ClearEvidence",
				text = "Clear evidence",
				variant = "ghost",
				onClick = function()
					local current = sessions.activeId and sessions.get(sessions.activeId)
					if not current then overlay.toast("No active conversation", "warn", 3); return end
					local evidence = env.require("runtime/evidence")
					local before = evidence.state(current)
					evidence.clear(current)
					overlay.toast(string.format("Cleared %d evidence record(s), %.1f KiB",
						before.records or 0, (before.bytes or 0) / 1024), "good", 3)
				end,
			},
			{
				name = "CopyDiagnostics",
				text = "Copy diagnostics",
				variant = "ghost",
				onClick = function()
					local report = table.concat({
						"UAI " .. tostring(env.info and env.info.version or ""),
						caps.summary(),
						responsive.describe(),
						place.describe(),
						ua.describe(),
						usage.line(),
						log.export(),
					}, "\n")
					if caps.clipboard then
						local ok = env.require("runtime/clipboard").write(report)
						overlay.toast(ok and "Diagnostics copied" or "Could not reach the clipboard",
							ok and "good" or "warn", 2)
					else
						log.info("diagnostics", report)
						overlay.toast("No clipboard here, so it went to the log", "info", 3)
					end
				end,
			},
		})

		local identity = build.section("Client identity",
			"Requests are sent as the Claude Code CLI. Gateways that gate on it accept them; "
			.. "others ignore the extra headers.")
		R.toggle(identity, {
			label = "Send the Claude Code identity",
			hint = "Applies to every inference request.",
			path = "identity.claudeUa",
		})
		R.field(identity, {
			name = "IdentityVersion",
			path = "identity.version",
			placeholder = ua.DEFAULT_VERSION,
			transform = function(text)
				if util.trim(text) == "" then return ua.DEFAULT_VERSION end
				return util.trim(text)
			end,
		})
		local identityBox = P.frame(identity, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			bg = theme.color.codeSurface,
			radius = theme.radius.md,
			padding = theme.space.sm,
		})
		P.stroke(identityBox, theme.color.codeBorder)
		local identityText = P.text(identityBox, {
			text = ua.describe(),
			role = "monoSmall",
			color = theme.color.codeText,
			wrap = true,
			auto = "Y",
		})
		identityText.Size = UDim2.new(1, 0, 0, 0)
		local unsubscribe = config.changed:connect(function(path)
			if not identityText.Parent then return end
			if path == nil or util.startsWith(tostring(path), "identity.") then
				identityText.Text = ua.describe()
			end
		end)
		identityText.Destroying:Connect(function() pcall(unsubscribe) end)
		if not caps.uaSupported then
			R.paragraph(identity,
				"This host has no executor HTTP function, so Roblox sends its own User-Agent and "
				.. "drops ours. Everything else still works.", { color = theme.color.warn })
		end

		local danger = build.section("Reset",
			"Providers, permission rules and memory are kept unless you say otherwise.")
		R.actions(danger, {
			{
				name = "ResetSettings",
				text = "Reset all settings",
				variant = "danger",
				onClick = function()
					overlay.confirm({
						title = "Reset every setting?",
						description = "Appearance and agent settings go back to defaults. Providers, rules and memory are kept.",
						confirmText = "Reset",
						danger = true,
						onConfirm = function()
							config.reset("ui")
							config.reset("agent")
							overlay.toast("Settings reset", "good")
						end,
					})
				end,
			},
			{
				name = "UnloadUai",
				text = "Unload UAI",
				variant = "danger",
				onClick = function()
					overlay.confirm({
						title = "Unload UAI?",
						description = "Stops the current turn, drains every timer and input handler, saves your settings and removes the interface. Run the loader again to come back.",
						confirmText = "Unload",
						danger = true,
						onConfirm = function()
							-- The handle the bootstrap published, which is the only thing
							-- holding the disposer registry and the ScreenGui together.
							local globals = (type(getgenv) == "function") and getgenv() or nil
							local live = globals and globals.UAI
							if live and live.destroy then
								local finished, why = live.destroy()
								if finished == false then overlay.toast(why or "UAI could not finish unloading. Try again.", "warn", 5) end
							else
								if config.vaultStatus().busy then overlay.toast("Finish or cancel credential storage before unloading UAI.", "warn", 5); return end
								env.require("runtime/dispose").drain()
								pcall(function() env.require("ui/app").screen:Destroy() end)
							end
						end,
					})
				end,
			},
		})
	end

	-- Agent -------------------------------------------------------------------

	local function paneAgent(container)
		local build = builder(container)

		local agent = build.section("Tools & execution", "Control how much work the agent can do in one turn.")
		R.number(agent, "Step limit", "Tool rounds allowed in one turn, unless the switch below removes it.",
			"agent.maxTurns", 4, 60, 1)
		R.toggle(agent, {
			label = "Unlimited tool calls",
			hint = "Ignore the step limit and the fifteen-minute turn deadline, and keep calling tools until the answer is written. The repeat breaker, each tool's own timeout and Stop still apply, and subagents keep their own budgets.",
			path = "agent.unlimitedTurns",
		})
		R.number(agent, "Parallel tools", "Tool calls run at once within one step.",
			"agent.toolConcurrency", 1, 8, 1)
		R.select(agent, {
			label = "Tool profile",
			hint = "All keeps every tool declared. Other profiles declare a smaller core; hidden tools remain callable through tool_search with their normal permissions and scope.",
			path = "agent.toolProfile",
			options = env.require("agent/tool_profiles").options(),
		})
		R.select(agent, {
			label = "Tool evidence",
			hint = "Large keeps only results at or above 8 KiB for later recovery; source and file tools are already durable. All keeps every result; Off writes nothing.",
			path = "agent.evidence",
			options = {
				{ value = "large", label = "Large results (8 KiB+)" },
				{ value = "all", label = "All results" },
				{ value = "off", label = "Off" },
			},
		})
		R.number(agent, "Tool timeout",
			"Seconds before a tool is abandoned. Subagents are exempt: they run to their own budget below.",
			"agent.toolTimeout", 5, 60, 1)
		R.number(agent, "Tool result cap",
			"Maximum bytes kept from one tool result. A tool's own page limit can be smaller. Roughly four bytes per token for English text; code and Unicode vary.",
			"agent.resultCap", RESULT_STOPS)

		local requests = build.section("Model requests", "Routing, wait time and recovery when contacting your provider.")
		R.toggle(requests, {
			name = "AutomaticFreeRouting", label = "Automatic free routing",
			hint = "Choose a recently verified free model for included HCNSEC access when its model is Auto. Off keeps provider Auto and stops new local routing probes; an active request continues.",
			path = "agent.autoFreeRouting", value = config.get("agent.autoFreeRouting", true) ~= false,
		})
		R.number(requests, "Request timeout",
			"Wait for a direct or companion model call. Direct native requests cap at 300 seconds; hosts and providers may stop sooner. Cowork bridge requests always wait until completion, failure or Stop.",
			"agent.requestTimeout", REQUEST_STOPS)
		R.toggle(requests, {
			label = "Maximum request wait",
			hint = "Use the direct transport's maximum wait instead of a shorter timeout, up to 300 seconds. Cowork bridge requests already have no time limit. Stop remains available.",
			path = "agent.requestUnlimited",
		})
		R.number(requests, "Retries", "Attempts per provider before moving to the next.",
			"agent.retries", 1, 6, 1)
		R.toggle(requests, {
			label = "Ask for streams",
			hint = "Streamed replies carry reasoning text and usage counts.",
			path = "agent.stream",
		})
		R.toggle(requests, {
			label = "Provider fallback",
			hint = "Try the next enabled provider when one fails.",
			path = "agent.fallback",
		})

		local delegation = build.section("Subagents", "Set the capacity and limits for delegated work.")
		R.number(delegation, "Subagent budget",
			"Seconds one subagent may work before it wraps up. The main agent can continue its own work and check progress while the child runs. Ignored while the switch below is on.",
			"agent.subagentBudget", 30, 900, 30)
		-- The switch the step-limit message asks for. A subagent that stops mid-job and
		-- says "I reached this session's step limit" has spent the whole dispatch and
		-- answered nothing, and until this existed the only way past it was to edit
		-- config.json -- `Unlimited tool calls` deliberately stops at the conversation the
		-- user is watching.
		R.toggle(delegation, {
			label = "Unlimited subagents",
			hint = "Let a dispatched subagent run with no step limit or clock while its parent continues working. The repeat breaker, each tool's timeout, the ceilings below and Stop still apply. The Subagents panel can stop one child, and ending the parent turn stops unfinished children.",
			path = "agent.subagentUnlimited",
		})
		R.number(delegation, "Parallel subagents",
			"Subagents alive at once across the whole tree. Several dispatched in one step run together; this is the ceiling on how many, including the ones a subagent starts itself. Anything over it waits for a slot.",
			"agent.subagentConcurrency", 1, 12, 1)
		-- Two ceilings that had no control anywhere: the only way to change either was
		-- to edit config.json, which for the depth cap means the only switch that can
		-- turn delegation off entirely was unreachable.
		R.number(delegation, "Subagent steps",
			"Tool rounds one subagent may take before it has to answer the parent with what it has. Ignored while Unlimited subagents is on.",
			"agent.subagentTurns", 1, 30, 1)
		R.number(delegation, "Delegation depth",
			"How many levels of subagent are allowed. A subagent given the full tool set can dispatch its own; at 0 the agent cannot dispatch at all and does the work in the conversation instead. The Subagents panel lists what is running under these limits.",
			"agent.subagentDepth", 0, 4, 1)

		local context = build.section("Conversation memory", "Keep long conversations within the model's context window.")
		R.number(context, "Context budget",
			"Hard ceiling on tokens kept before older turns are summarised. When the model's context window is known, compaction begins at the Compact-at fraction of it, so this mainly caps models with very large or unknown windows.",
			"agent.contextTokens", BUDGET_STOPS)
		R.number(context, "Compact at",
			"Share of the model's context window at which older turns are summarised, when the window is known. Lower compacts sooner and cheaper; higher keeps more history in view. The Context budget above is still a hard ceiling.",
			"agent.contextFraction", 0.5, 0.95, 0.05)
		R.toggle(context, {
			label = "Summarise old turns",
			hint = "Keeps a long conversation inside the context budget.",
			path = "agent.compaction",
		})

		local response = build.section("Responses", "Adjust response length, effort and language.")
		R.number(response, "Reply ceiling",
			"Maximum generated tokens per request, including reasoning where the provider counts it. Model limits, available context and learned provider caps may lower it. This does not require the model to use the whole allowance.",
			"agent.maxTokens", REPLY_STOPS)
		R.choice(response, "Effort",
			"Low is the faster default; raise it for difficult tasks. Existing saved choices are kept. "
			.. "Sent as the provider's effort level where supported; raw provider parameters can override it. Provider default omits the effort field and may still think extensively. The Thinking row shows visible text, not a 5,999-token limit.",
			"agent.effort",
			{ "low", "medium", "high", "xhigh", "max", "off" },
			{ "Low", "Medium", "High", "Very high", "Max", "Provider default" },
			{ "Faster", "Provider default" })
		R.number(response, "Temperature",
			"Lower is steadier; 0 is as deterministic as the provider allows. The current Claude models reject it, and it is not sent to them.",
			"agent.temperature", 0, 1.5, 0.05)
		-- One field, and the only half of the old language picker that was ever wired to
		-- anything. That control was a grid of eleven tiles behind a modal behind a menu
		-- entry, and it advertised two effects: the language the agent answers in, which
		-- src/agent/prompt.lua does read, and the locale dates are formatted with, which
		-- nothing reads at all. What survives is the effect that exists.
		R.field(response, {
			name = "ReplyLanguage",
			label = "Reply language",
			hint = "Added to the system prompt as one line: answer in this language, leaving code "
				.. "and identifiers alone. Empty means whatever the conversation is already in, "
				.. "which is what a model does by default.",
			path = "agent.replyLanguage",
			placeholder = "Japanese",
		})

		-- The user's own standing instructions. This is the personal half of the prompt;
		-- the built-in half is fixed on purpose, and the copy action below is how it is
		-- inspected -- read-only, on the record, diffable between versions.
		local custom = build.section("Custom instructions",
			"Added to the system prompt every turn, after the built-in rules, so they win "
			.. "when the two disagree. The rest of the prompt is not editable: it is this "
			.. "client's own behaviour, and what is yours is kept separate from it so you "
			.. "can always tell which is which.")
		R.textarea(custom, {
			name = "CustomInstructions",
			path = "agent.customInstructions",
			height = theme.size.formTextarea,
			placeholder = "e.g. Reply short. I build obby games. My alt account is DaveAlt99 -- ignore it when counting players.",
			hint = "Written when the box loses focus. Applies from the next turn, including "
				.. "subagents, which inherit it with the rest of the brief.",
		})
		R.actions(custom, { {
			name = "CopySystemPrompt",
			text = "Copy system prompt",
			variant = "ghost",
			onClick = function()
				-- The assembled thing rather than the module's constants, so what is on
				-- the clipboard is what the next request will carry: the environment
				-- block, the permission line, this pane's own instructions included.
				local providers = env.require("provider/registry")
				local prompt = env.require("agent/prompt")
				local record = providers.active()
				local body = prompt.build({
					model = record and record.model or nil,
					provider = record and record.label or nil,
				})
				if caps.clipboard then
					local ok = env.require("runtime/clipboard").write(body)
					overlay.toast(ok and "System prompt copied" or "Could not reach the clipboard",
						ok and "good" or "warn", 2)
				else
					log.info("prompt", body)
					overlay.toast("No clipboard here, so it went to the log", "info", 3)
				end
			end,
		} })
	end

	-- Permissions -------------------------------------------------------------

	local function panePermissions(container)
		local build = builder(container)
		local card = build.section("Permissions", "Choose when tools can run and review saved exceptions.")

		local modeOptions = {}
		for _, mode in ipairs(permissions.MODES) do
			modeOptions[#modeOptions + 1] = { value = mode, label = permissions.MODE_LABELS[mode] or mode }
		end
		local modeHint
		C.segmented(card, {
			options = modeOptions,
			value = permissions.mode(),
			onChange = function(value)
				permissions.setMode(value)
				if modeHint then modeHint.Text = permissions.MODE_HINTS[value] or "" end
			end,
		})
		modeHint = P.text(card, {
			text = permissions.MODE_HINTS[permissions.mode()] or "",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
		})
		modeHint.Size = UDim2.new(1, 0, 0, 0)

		R.toggle(card, {
			label = "Offer to remember",
			hint = "Show the remember switch on each prompt.",
			path = "permissions.remember",
		})

		local rulesLabel = P.text(card, {
			text = "",
			role = "caption",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
		})
		rulesLabel.Size = UDim2.new(1, 0, 0, 0)
		local function refreshRules()
			local rules = permissions.listRules()
			if #rules == 0 then
				rulesLabel.Text = "No per-tool rules saved."
				return
			end
			local parts = {}
			for _, rule in ipairs(rules) do
				parts[#parts + 1] = rule.pattern .. " = " .. rule.verdict
			end
			rulesLabel.Text = util.pluralise(#rules, "saved rule") .. ": " .. table.concat(parts, ", ")
		end
		refreshRules()
		local unsubscribe = permissions.changed:connect(function()
			if not rulesLabel.Parent then return end
			refreshRules()
		end)
		rulesLabel.Destroying:Connect(function() pcall(unsubscribe) end)
		R.actions(card, { {
			name = "ClearRules",
			text = "Clear saved rules",
			variant = "ghost",
			onClick = function()
				permissions.clearRules()
				refreshRules()
			end,
		} })
	end

	-- Skills ------------------------------------------------------------------

	local function paneSkills(container)
		local build = builder(container)

		-- Skills (playbooks) ------------------------------------------------
		--
		-- .md files under skills/, each a frontmatter description and a body of
		-- instructions. The list is files on disk rather than config state, so
		-- the honest subtitle is where they come from: dropped in by hand,
		-- written by the agent, or installed from GitHub. The toggle is the one
		-- bit of state kept, and it is stored per filename.
		local skillsCard = build.section("Playbooks",
			"Agents read enabled skills when relevant or explicitly requested, and reuse "
			.. "unchanged bodies still in context. Drop a .md playbook into skills/, or ask "
			.. "the agent to install one from GitHub. Turn off a skill to exclude it.")
		local skillsEngine = env.require("runtime/skills")

		local skillsList = P.column(skillsCard, {
			name = "SkillsList",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
		})
		local function refreshSkills()
			-- Keep the layout: clearing it stacked every installed skill at (0, 0).
			for _, child in ipairs(skillsList:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			local list = skillsEngine.list()
			if #list == 0 then
				R.paragraph(skillsList, "No skills installed yet.",
					{ layoutOrder = 1 })
				return
			end
			for index, skill in ipairs(list) do
				local row = P.row(skillsList, {
					name = "Skill_" .. skill.file,
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = theme.space.sm,
					layoutOrder = index,
				})
				local text = P.column(row, {
					size = UDim2.new(0, 0, 0, 0), auto = "Y", flex = "Fill", gap = 0, layoutOrder = 1,
				})
				P.text(text, { text = skill.name, role = "small", wrap = true, auto = "Y" })
				local detail = skill.description ~= "" and util.ellipsis(skill.description, 140)
					or (skill.unreadable and "could not be read") or "no description"
				P.text(text, {
					text = detail,
					role = "caption",
					color = theme.color.textTertiary,
					wrap = true,
					auto = "Y",
				})
				local switch = C.switch(row, {
					value = skill.enabled,
					onChange = function(value)
						skillsEngine.setEnabled(skill.file, value)
					end,
				})
				switch.instance.LayoutOrder = 2
			end
		end
		refreshSkills()
		local unsubscribeSkills = skillsEngine.changed:connect(function()
			if not skillsList.Parent then return end
			refreshSkills()
		end)
		skillsList.Destroying:Connect(function() pcall(unsubscribeSkills) end)

		local memory = build.section("Memory",
			"Facts the agent has chosen to keep between sessions. It writes these itself, with "
			.. "the memory tool; this is where they can be read and removed.")
		R.toggle(memory, {
			label = "Enabled",
			hint = "When off, nothing new is stored and nothing is injected.",
			path = "memory.enabled",
		})
		local memoryList = P.column(memory, {
			name = "MemoryEntries", size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.xs,
		})
		local function refreshMemory()
			for _, child in ipairs(memoryList:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			local list = state.memoryList()
			if #list == 0 then
				P.text(memoryList, { text = "Nothing stored.", role = "caption", color = theme.color.textTertiary,
					auto = "Y", wrap = true })
				return
			end
			for index, entry in ipairs(list) do
				local row = P.row(memoryList, {
					name = "MemoryEntry_" .. entry.key, size = UDim2.new(1, 0, 0, 0), auto = "Y",
					gap = theme.space.sm, alignY = "Top", layoutOrder = index,
				})
				P.text(row, {
					text = entry.key .. ": " .. util.ellipsis(entry.value, 120),
					role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y",
					size = UDim2.new(0, 0, 0, 0), flex = "Fill", layoutOrder = 1,
				})
				local key = entry.key
				P.iconButton(row, {
					name = "ForgetOne", icon = "trash", variant = "ghost", diameter = theme.size.controlSmall,
					layoutOrder = 2,
					onClick = function() state.forget(key) end,
				})
			end
		end
		refreshMemory()
		local unsubscribe = state.memoryChanged:connect(function()
			if not memoryList.Parent then return end
			refreshMemory()
		end)
		memoryList.Destroying:Connect(function() pcall(unsubscribe) end)
		R.actions(memory, { {
			name = "ForgetEverything",
			text = "Forget everything",
			variant = "ghost",
			onClick = function()
				overlay.confirm({
					title = "Clear memory?",
					description = "Every stored fact is deleted.",
					confirmText = "Clear",
					danger = true,
					onConfirm = function()
						state.clearMemory()
						refreshMemory()
					end,
				})
			end,
		} })

		local host = build.section("Host instructions",
			"A script that embeds this client can add its own instructions and hooks. This is "
			.. "what the current host provided.")
		local hostPrompt = env.context and env.context.prompt
		local hooks = env.require("agent/hooks")
		local hookCounts = {}
		for kind in pairs(hooks.KINDS) do
			local count = hooks.count(kind)
			if count > 0 then hookCounts[#hookCounts + 1] = { key = kind, value = tostring(count) } end
		end
		if type(hostPrompt) == "string" and util.trim(hostPrompt) ~= "" then
			R.paragraph(host, util.ellipsis(hostPrompt, 600), { role = "small", color = theme.color.text })
		else
			R.paragraph(host, "No host instructions: this client was loaded on its own.")
		end
		if #hookCounts > 0 then
			table.sort(hookCounts, function(a, b) return a.key < b.key end)
			R.facts(host, hookCounts, { name = "Hooks" })
		end
	end

	-- Connectors --------------------------------------------------------------

	local function paneConnectors(container)
		local build = builder(container)

		local card = build.section("Inference providers",
			"Your configured providers and models. Add a service or edit its connection details in Providers.")
		local list = providers.list()
		if #list == 0 then
			R.paragraph(card, "Nothing configured yet.")
		else
			local facts = {}
			for _, record in ipairs(list) do
				local detail = record.baseUrl
				if util.trim(tostring(record.model or "")) ~= "" then
					detail = record.model .. "  " .. record.baseUrl
				end
				facts[#facts + 1] = {
					key = record.label,
					value = detail,
					tone = (providers.active() or {}).id == record.id and "good" or nil,
				}
			end
			R.facts(card, facts, { name = "Providers" })
		end
		R.actions(card, { {
			name = "OpenInference",
			text = "Manage providers",
			variant = "secondary",
			onClick = function()
				env.require("ui/app").show("providers")
			end,
		} })

		local bridgeCard = build.section("Web bridge",
			"The one connector that is not a model: a browser on this machine sharing the "
			.. "conversation.")
		local status = bridgeModule.status()
		R.facts(bridgeCard, {
			{ key = "State", value = status.running and (status.online and "connected" or "polling") or "off",
				tone = status.running and (status.online and "good" or "warn") or nil },
			{ key = "Address", value = status.url },
		}, { name = "BridgeFacts" })
		R.actions(bridgeCard, { {
			name = "OpenCowork",
			text = "Open Cowork",
			variant = "ghost",
			onClick = function()
				env.require("ui/app").show("cowork")
			end,
		} })
	end

	-- Infinite Yield ------------------------------------------------------------

	-- The mode picker is a segmented control rather than a toggle because there
	-- are three honest states, not two: off, hidden (IY's engine, no IY pixels)
	-- and visible (IY exactly as it draws itself). A toggle would have to fold
	-- "off" and "hidden" into one position, and they are different decisions --
	-- one withholds the commands from the agent, the other only the interface.
	--
	-- Changing the mode does not load anything here. Loading is a megabyte
	-- fetch, a compile and a GUI; a settings row is not where that should spend
	-- itself. The next iy_cmd call picks the new mode up, and the status lines
	-- below say which state it will find.
	local function paneInfiniteYield(container)
		local build = builder(container)
		local card = build.section("Infinite Yield",
			"Run Infinite Yield inside this client and give the agent every one of its "
			.. "commands through the iy tools.")

		local iy = env.require("runtime/iy")
		local facts = P.column(card, {
			name = "IyStatus",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.xxs,
		})
		local function refresh()
			for _, child in ipairs(facts:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			local status = iy.status()
			for index, row in ipairs(status) do
				P.text(facts, {
					text = row[1] .. ": " .. tostring(row[2]),
					role = "caption",
					color = theme.color.textTertiary,
					wrap = true,
					auto = "Y",
					layoutOrder = index,
				}).Size = UDim2.new(1, 0, 0, 0)
			end
		end
		refresh()

		C.segmented(card, {
			options = {
				{ value = "off", label = "Off" },
				{ value = "hidden", label = "Hidden" },
				{ value = "visible", label = "With GUI" },
			},
			value = config.get("iy.mode", "hidden"),
			onChange = function(value)
				iy.setMode(value)
				refresh()
			end,
		})

		R.paragraph(card,
			"Hidden loads Infinite Yield with its interface parked, so the agent has "
			.. "every command and you keep the screen. With GUI loads it untouched. "
			.. "Either way the agent reaches everything through the same dispatcher, and "
			.. "iy_cmd calls still pass the permission prompt. If Infinite Yield is "
			.. "already running when a command is sent, that copy is used as-is.",
			{ layoutOrder = 4 })

		if not caps.exec then
			R.paragraph(card,
				"This host cannot compile code, so an internal load is unavailable here. "
				.. "An Infinite Yield you start yourself still works.",
				{ color = theme.color.warn })
		end
	end

	-- Plugins -----------------------------------------------------------------

	local function panePlugins(container)
		local build = builder(container)
		local card = build.section("Tool groups",
			"A family of tools can be withheld from the model entirely. That is a different "
			.. "thing from denying a call: a tool that is not offered is one the model will not "
			.. "spend a turn discovering it cannot use.")

		for _, group in ipairs(registry.groups()) do
			local row = P.row(card, {
				name = "Group_" .. group.id,
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.sm,
			})
			local text = P.column(row, {
				size = UDim2.new(0, 0, 0, 0), auto = "Y", flex = "Fill", gap = 0, layoutOrder = 1,
			})
			P.text(text, { text = group.label, role = "label", wrap = true, auto = "Y" })
			local detail = util.pluralise(group.total, "tool")
			if group.unavailable > 0 then
				detail = detail .. ", " .. tostring(group.unavailable) .. " unavailable on this host"
			end
			P.text(text, {
				text = detail,
				role = "caption",
				color = theme.color.textTertiary,
				wrap = true,
				auto = "Y",
			})
			local switch = C.switch(row, {
				value = group.enabled,
				onChange = function(value)
					registry.setGroupEnabled(group.id, value)
				end,
			})
			switch.instance.LayoutOrder = 2
		end

		R.actions(card, { {
			name = "OpenTools",
			text = "See every tool",
			variant = "secondary",
			onClick = function()
				env.require("ui/app").show("tools")
			end,
		} })
	end

	-- The list -----------------------------------------------------------------

	-- Grouped the way the reference client groups them. "Agent" is the one section it
	-- does not have, and it is not optional here: the step limit, the context budget
	-- and the permission mode are the settings this client is actually about, and
	-- filing them under Developer to preserve a menu shape would hide them.
	M.PANES = {
		{ id = "general", section = "Settings", label = "General", icon = "gear", build = paneGeneral },
		{ id = "privacy", section = "Settings", label = "Privacy", icon = "worktree", build = paneprivacy },
		{ id = "usage", section = "Settings", label = "Usage", icon = "sliders", build = paneUsage },
		{ id = "claude_code", section = "Settings", label = "Project UAI", icon = "code", build = paneClaudeCode },
		{ id = "cowork", section = "Settings", label = "Cowork", icon = "terminal", build = paneCowork },
		{ id = "import_export", section = "Settings", label = "Import & export", icon = "document", build = paneImportExport },
		{ id = "agent", section = "Agent", label = "Behaviour", icon = "spark", build = paneAgent },
		{ id = "permissions", section = "Agent", label = "Permissions", icon = "check", build = panePermissions },
		{ id = "desktop_general", section = "Desktop app", label = "General", icon = "windowMaximize", build = paneDesktop },
		{ id = "developer", section = "Desktop app", label = "Developer", icon = "terminal", build = paneDeveloper },
		{ id = "skills", section = "Customize", label = "Skills", icon = "book", build = paneSkills },
		{ id = "connectors", section = "Customize", label = "Connectors", icon = "branch", build = paneConnectors },
		{ id = "obsidian", section = "Customize", label = "Obsidian", icon = "book", build = function(container) env.require("ui/obsidian").build(container) end },
		{ id = "infinite_yield", section = "Customize", label = "Infinite Yield", icon = "terminal", build = paneInfiniteYield },
		{ id = "plugins", section = "Customize", label = "Plugins", icon = "worktree", build = panePlugins },
	}

	function M.pane(id)
		for _, entry in ipairs(M.PANES) do
			if entry.id == id then return entry end
		end
		return nil
	end

	-- The dialog's nav, in declaration order, with the section headings kept.
	function M.sections()
		local out, seen = {}, {}
		for _, entry in ipairs(M.PANES) do
			if not seen[entry.section] then
				seen[entry.section] = { title = entry.section, panes = {} }
				out[#out + 1] = seen[entry.section]
			end
			local group = seen[entry.section]
			group.panes[#group.panes + 1] = entry
		end
		return out
	end

	-- One pane into a container of its own. Used by the dialog when a category is
	-- chosen, and by the Settings panel for every pane in turn.
	function M.render(id, container)
		local entry = M.pane(id)
		if not entry then return false end
		local heading = P.column(container, { name = "SettingsPaneHeading", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.xxs, layoutOrder = -1 })
		P.text(heading, { name = "SettingsPaneSection", text = entry.section, role = "caption",
			color = theme.color.textTertiary, auto = "Y", wrap = true, layoutOrder = 1 })
		P.text(heading, { name = "SettingsPaneTitle", text = entry.label, role = "title",
			auto = "Y", wrap = true, layoutOrder = 2 })
		local ok, err = pcall(entry.build, container)
		if not ok then
			log.warn("settings", "the " .. tostring(id) .. " pane failed to build", err)
			R.paragraph(container, "This pane could not be built: " .. tostring(err),
				{ color = theme.color.danger })
		end
		return ok
	end

	return M
end
