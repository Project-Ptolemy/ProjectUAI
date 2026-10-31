-- Providers panel: a list on the left, one provider's whole configuration on the
-- right.
--
-- This is the screen that makes the client universal, so it is deliberately plain: a
-- base URL, a key, an auth style and a model. Anything that speaks
-- /v1/chat/completions is a first-class citizen here, and the presets are only a way
-- to avoid typing a URL.
--
-- It was a list of cards plus one modal holding nine rows of form, and four things
-- were wrong with that beyond the density. The modal was the only way to see any of a
-- record's configuration, and it printed the API key in clear text while the hint
-- underneath said the key was redacted. Picking a different preset inside it rebuilt
-- the record from scratch and threw away whatever had been typed, with no warning. The
-- record's headers, params, query, order and note -- five fields the registry keeps,
-- two of which decide whether Azure and OpenRouter work at all -- had no
-- representation anywhere in the interface. And every completion fired a health event
-- that rebuilt the entire panel mid-turn, scroll position included.
return function(env)
	local util = env.require("runtime/util")
	local keyData = env.require("runtime/provider_keys")
	local clock = env.require("runtime/clock")
	local caps = env.require("runtime/caps")
	local config = env.require("runtime/config")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local R = env.require("ui/settingsrows")
	local overlay = env.require("ui/overlay")
	local catalog = env.require("provider/catalog")
	local registry = env.require("provider/registry")
	local models = env.require("provider/models")
	local chat = env.require("provider/chat")
	local traits = env.require("provider/traits")
	local communityKey = env.require("provider/community_key")
	local icons = env.require("ui/icons")
	local urls = env.require("net/url")
	local connectionActions = env.require("provider/connection_actions")

	local M = {}

	local AUTH_OPTIONS = {
		{ value = "bearer", label = "Bearer" },
		{ value = "x-api-key", label = "x-api-key" },
		{ value = "x-goog-api-key", label = "x-goog-api-key" },
		{ value = "api-key", label = "api-key" },
		{ value = "both", label = "Both" },
		{ value = "none", label = "None" },
	}

	local function labelOf(options, value)
		for _, option in ipairs(options) do
			if option.value == value then return option.label end
		end
		return tostring(value)
	end

	local function keyUsage(record)
		if keyData.mode(record) == "single" then
			local index = keyData.selected(record)
			local entry = keyData.entries(record)[index or 0]
			local name = entry and entry.name ~= "" and entry.name or ("API key " .. tostring(index or 1))
			return "Use one key: " .. name .. (entry and entry.paused and " (paused)" or "")
		end
		local pool, active = keyData.entries(record), 0
		for _, entry in ipairs(pool) do if not entry.paused then active = active + 1 end end
		if active < #pool then return active == 0 and "All API keys are paused" or ("Rotate " .. active .. " active keys / " .. #pool .. " saved") end
		return "Rotate keys automatically"
	end

	local function sameKeyConnection(record, updated)
		if record.apiKey ~= updated.apiKey or keyData.mode(record) ~= keyData.mode(updated)
			or keyData.selected(record) ~= keyData.selected(updated) then return false end
		for index in ipairs(keyData.keys(record)) do
			if keyData.paused(record, index) ~= keyData.paused(updated, index) then return false end
		end
		return true
	end

	local function applyKeys(record, updated)
		local connectionChanged = not sameKeyConnection(record, updated)
		record.apiKey = updated.apiKey
		record.keyNames = util.deepCopy(updated.keyNames)
		record.keyPaused = util.deepCopy(updated.keyPaused)
		record.keyIds = util.deepCopy(updated.keyIds)
		record.keyMode = updated.keyMode
		record.selectedKey = updated.selectedKey
		if connectionChanged then record.keyRotation = nil end
		return connectionChanged
	end

	-- Never the key itself.
	--
	-- The editor rendered record.apiKey into an ordinary field, so opening Edit on any
	-- saved provider printed the whole secret on screen -- while the hint under it said
	-- "redacted in the log", the privacy pane promised only the last four characters
	-- were kept, and the export path reduced it to exactly that.
	local function maskedKey(record)
		local raw = tostring(record.apiKey or "")
		if registry.isCline(record) then return "Sign in to Cline in the desktop app", nil end
		if record.authStyle == "none" then return "No API key required", nil end
		if util.trim(raw) == "" and registry.opencodeKeyOptional(record) then return "Provided by connected OpenCode CLI", nil end
		if util.trim(raw) == "" then return "not set", "warn" end
		local pool = registry.keysOf(record)
		if #pool > 0 and #keyData.requestKeys(record) == 0 then return "No active API key", "warn" end
		if keyData.mode(record) == "single" then
			local key = keyData.requestKeys(record)[1]
			if not key then return "Choose an API key", "warn" end
			return #key <= 4 and "set" or (string.rep("\226\128\162", 4) .. " " .. key:sub(-4)), nil
		end
		if #pool > 1 then
			local last = pool[#pool]
			local suffix = #last <= 4 and "set" or (string.rep("\226\128\162", 4) .. " " .. last:sub(-4))
			return suffix .. "  \194\183  pool of " .. #pool .. " keys", nil
		end
		local key = pool[1] or ""
		if #key <= 4 then return "set", nil end
		return string.rep("\226\128\162", 4) .. " " .. key:sub(-4), nil
	end

	local function modelSource(record)
		if registry.isCline(record) then return "Cline's free catalog through the desktop bridge" end
		if registry.isOpencodeZen(record) and env.require("net/bridge").opencodeStatus().available then return "OpenCode CLI through the desktop bridge" end
		return urls.display(registry.endpoint(record, "/models"))
	end

	local function fetchLabel(record)
		return registry.isCline(record) and "Refresh Cline models" or "Fetch models"
	end

	-- Everything the registry knows about a record and the panel never said.
	--
	-- `chat.endpointOf` and `registry.endpoint` both existed for this and both had zero
	-- call sites; the comment on endpointOf says "for the Providers panel to show".
	local function factsFor(record)
		local health = env.require("provider/health").read(record)
		local key, keyTone = maskedKey(record)
		local streaming = record.stream ~= false and config.get("agent.stream", true)
		if record.params and record.params.stream ~= nil then streaming = record.params.stream == true end
		local transport = streaming and "Buffered SSE over HTTP" or "JSON over HTTP"
		if not chat.supportsSocket(record) and util.trim(record.wsUrl) ~= "" then
			transport = transport .. " (socket unused for this protocol)"
		elseif streaming and util.trim(record.wsUrl) ~= "" then
			transport = caps.ws and "UAI gateway socket, with HTTP fallback before send" or "Buffered SSE over HTTP (socket unavailable)"
		end
		local route = env.require("net/transport").target()
		if route == "cowork" then transport = "Web relay"
		elseif route == "companion" then transport = "Relay (companion)" end
		if registry.isCline(record) then transport = "Cline CLI through the desktop bridge / text only" end
		local out = {
			{ key = "Endpoint", value = registry.isCline(record) and "Cline through Project UAI Bridge" or urls.display(chat.endpointOf(record)) },
			{ key = "Model list", value = modelSource(record) },
			{ key = "Protocol", value = chat.protocolOf(record) == "responses" and "OpenAI Responses" or labelOf(chat.STYLES, chat.styleOf(record)) },
			{ key = "Availability", value = env.require("provider/availability").describe(record).message },
			{ key = "Auth", value = labelOf(AUTH_OPTIONS, record.authStyle or "bearer")
				.. "  \194\183  " .. key, tone = keyTone },
			{ key = "Streaming", value = transport },
		}
		if not registry.isCline(record) and #registry.keysOf(record) > 0 then
			out[#out + 1] = { key = "Key usage", value = keyUsage(record) }
		end
		if (health.ok or 0) + (health.fail or 0) > 0 then
			out[#out + 1] = {
				key = "Health",
				value = string.format("%d ok, %d failed", health.ok or 0, health.fail or 0),
				tone = (health.streak or 0) > 0 and "warn" or "good",
			}
		end
		-- Recorded on every success and shown nowhere until now.
		if (health.lastMs or 0) > 0 then
			out[#out + 1] = { key = "Last reply", value = util.formatDuration(health.lastMs) }
		end
		-- The bench was a red dot with no words: no label, no remaining time, and no
		-- statement of the three-failure rule that put it there.
		if registry.cooling(record) then
			local left = math.max((health.cooldownUntil or 0) - clock.ms(), 0)
			out[#out + 1] = {
				key = "Benched",
				value = string.format("%s left, after 3 failures in a row", util.formatDuration(left)),
				tone = "bad",
			}
		end
		if registry.needsExecutor(record) then
			local have = caps.http == "executor"
			out[#out + 1] = {
				key = "Requires",
				value = have and "an executor HTTP function, which this host has"
					or "an executor HTTP function, which this host does not have",
				tone = have and "good" or "bad",
			}
		end
		return out
	end

	-- Keep an unfinished Add in memory for this client session. Existing records
	-- remain isolated edit copies; their unsaved changes do not become Add drafts.
	local addDraft = nil
	env.require("runtime/dispose").add(config.changed:connect(function(path)
		if (path == nil or path == "security" or path == "security.vault") and config.vaultStatus().locked then addDraft = nil end
	end), "provider draft vault state")

	local function draftDirty(candidate)
		local blank = registry.blank("custom")
		for _, key in ipairs({ "preset", "label", "baseUrl", "apiKey", "api", "authStyle", "model" }) do
			if util.trim(candidate[key]) ~= util.trim(blank[key]) then return true end
		end
		return false
	end

	-- Provider gallery ---------------------------------------------------------
	--
	-- Adding a provider used to start with a form and a preset dropdown, which asked
	-- someone to know a vendor's name and URL before it showed them a single vendor.
	-- The gallery starts from what a person actually has -- a budget -- and puts the
	-- free routes first, paid ones behind a tab, local servers behind another. Search
	-- spans all three, because a name is the one thing someone arriving here usually
	-- does know.
	--
	-- Roomy layouts pin search, tabs and counts. Short layouts keep those same
	-- controls in one scrolling body so the keyboard cannot crowd out the catalog.

	local function highlighted(text, needle)
		local value = tostring(text or "")
		if not needle or needle == "" then return value, false end
		local at = value:find(needle, 1, true)
		if not at then return value, false end
		local function escape(part)
			return (part:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
		end
		return escape(value:sub(1, at - 1))
			.. string.format('<b><font color="#%s">%s</font></b>', theme.color.accent:ToHex(), escape(needle))
			.. escape(value:sub(at + #needle)), true
	end

	local function countText(count, tier, searching)
		if searching then
			return count == 1 and "1 match in all providers" or (tostring(count) .. " matches in all providers")
		end
		if tier == "free" then
			return count == 1 and "1 free route" or (tostring(count) .. " free routes")
		elseif tier == "local" then
			return count == 1 and "1 local server" or (tostring(count) .. " local servers")
		end
		return count == 1 and "1 paid provider" or (tostring(count) .. " paid providers")
	end

	-- `opts.onPick` receives the chosen preset and the gallery closes into whatever
	-- opened it. `opts.onSaved` is the add flow: the gallery closes and the editor
	-- opens, seeded from the preset, so a name and a key are typed in one place.
	function M.picker(opts)
		opts = opts or {}
		local dialog = overlay.dialog({
			name = "ProviderPicker",
			width = responsive.isMobile() and theme.size.providerPicker or (theme.size.providerPicker + theme.size.menuMin),
			height = math.ceil(theme.size.providerPickerTall / (responsive.isMobile() and theme.metricScale or 1)),
		})
		if not dialog then return end

		-- The gallery also opens from inside the editor, where a modal is already on
		-- screen. Both surfaces share the modal layer, so the picker lifts itself and
		-- its dismissal regions one step above the editor instead of leaving the
		-- editor's card to draw over the dimmed backdrop.
		local lift = theme.z.modal + 6
		dialog.scrim.ZIndex = lift
		for _, child in ipairs(dialog.scrim:GetChildren()) do
			if child:IsA("GuiObject") then child.ZIndex = lift + 1 end
		end

		local closed, chosen, pendingSearch = false, false, nil
		local tier = opts.tier
		local known = false
		for _, entry in ipairs(catalog.tiers) do
			if entry.id == tier then known = true end
		end
		if not known then tier = "free" end
		local query = ""

		local viewport = P.scroll(dialog.card, { name = "PickerViewport", size = UDim2.fromScale(1, 1), bar = 0 })
		viewport.instance.ScrollingEnabled = false
		viewport.instance.VerticalScrollBarInset = Enum.ScrollBarInset.None
		local root = P.column(viewport.instance, {
			name = "PickerRoot",
			size = UDim2.new(1, 0, 0, dialog.height),
			gap = theme.space.md,
			padding = { x = theme.space.lg, top = theme.space.lg, bottom = theme.space.md },
		})

		local head = P.column(root, {
			name = "PickerHead",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.hair,
			layoutOrder = 1,
			-- The dialog's close button floats over this corner; the title stops
			-- short of it rather than running underneath.
			padding = { right = dialog.closeInset },
		})
		P.text(head, {
			name = "PickerOverline",
			text = opts.onPick and "CONNECTION PRESET" or "INFERENCE PROVIDERS",
			role = "overline",
			color = theme.color.accent,
			size = UDim2.new(1, 0, 0, theme.text.overline.height),
			layoutOrder = 1,
		})
		P.text(head, {
			name = "PickerTitle",
			text = opts.onPick and "Choose a provider" or "Add an inference provider",
			role = "display",
			color = theme.color.text,
			wrap = true,
			auto = "Y",
			layoutOrder = 2,
		})
		P.text(head, {
			name = "PickerDescription",
			text = "Choose a hosted API or a local server. You'll review the connection before saving.",
			role = "small",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
			layoutOrder = 3,
		})

		local tabsRow = P.row(root, {
			name = "PickerTabs",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 2,
		})
		local countLabel
		local search
		local gallery
		local cards = {}
		local render
		local resetSearch
		local silent = false

		C.segmented(tabsRow, {
			name = "ProviderTier",
			options = (function()
				local out = {}
				for _, entry in ipairs(catalog.tiers) do
					out[#out + 1] = { value = entry.id, label = entry.id == "free" and "Free & included" or entry.label }
				end
				return out
			end)(),
			value = tier,
			layoutOrder = 1,
			onChange = function(value)
				tier = value
				resetSearch()
			end,
		})

		search = P.field(root, {
			name = "ProviderSearch",
			placeholder = "Search providers or models",
			-- Room for the glyph at the left and the clear control at the right; both
			-- are drawn into the field's own shell, so the text has to start past them.
			padX = theme.size.icon + theme.space.md + theme.space.xs,
			layoutOrder = 3,
			onChange = function(text)
				query = tostring(text or "")
				-- A programmatic reset (tab switch, clear control) already renders; the
				-- change event it fires must not schedule a second pass that rebuilds the
				-- same cards and resets the scroll twice.
				if silent then return end
				if pendingSearch then pcall(task.cancel, pendingSearch); pendingSearch = nil end
				-- One render per keystroke would rebuild every card while someone is
				-- still typing. A short delay coalesces a word into one pass.
				pendingSearch = clock.delay(0.12, function()
					pendingSearch = nil
					render()
				end)
			end,
			onSubmit = function()
				if pendingSearch then pcall(task.cancel, pendingSearch); pendingSearch = nil end
				render()
			end,
		})
		local searchIcon = P.frame(search.shell, {
			name = "SearchGlyph",
			size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
			anchor = Vector2.new(0, 0.5),
			position = UDim2.new(0, theme.space.sm, 0.5, 0),
		})
		icons.draw("search", searchIcon, theme.size.icon, theme.color.textTertiary)
		local clearSize = math.max(theme.size.controlSmall, responsive.minTarget())
		local searchPadding = search.instance:FindFirstChildOfClass("UIPadding")
		if searchPadding then searchPadding.PaddingRight = UDim.new(0, clearSize + theme.space.xs) end
		local clearSearch = P.iconButton(search.shell, {
			name = "ClearProviderSearch",
			icon = "close",
			diameter = clearSize,
			anchor = Vector2.new(1, 0.5),
			position = UDim2.new(1, -theme.space.xxs, 0.5, 0),
			visible = false,
			onClick = function()
				resetSearch()
				search.focus()
			end,
		})

		resetSearch = function()
			if pendingSearch then pcall(task.cancel, pendingSearch); pendingSearch = nil end
			query = ""
			if search then
				silent = true
				search.set("")
				silent = false
			end
			render()
		end

		local galleryHolder = P.frame(root, {
			name = "ProviderGalleryHolder",
			size = UDim2.new(1, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 4,
		})
		gallery = P.scroll(galleryHolder, {
			name = "ProviderGallery",
			size = UDim2.fromScale(1, 1),
			gap = theme.space.md,
			-- Keep card outlines clear of every scroll edge, with extra room below
			-- the final row to clear the fade and footer.
			padding = { x = theme.space.sm, top = theme.space.sm, bottom = theme.space.xl },
			fade = true,
			fadeColor = theme.color.surface,
		})
		gallery.layout.FillDirection = Enum.FillDirection.Horizontal
		gallery.layout.Wraps = true
		gallery.layout.ItemLineAlignment = Enum.ItemLineAlignment.Stretch

		local footer = P.row(root, {
			name = "PickerFooter",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 5,
		})
		-- The result count lives here rather than beside the tabs: a segmented control
		-- is sized by its labels and capped, so a sibling that wants the rest of the row
		-- competes with it for width on a phone. Roomy layouts pin the footer;
		-- short layouts scroll it after the cards with the rest of the original body.
		countLabel = P.text(footer, {
			name = "ProviderCount",
			text = "",
			role = "caption",
			color = theme.color.textTertiary,
			truncate = true,
			size = UDim2.new(0, 0, 0, theme.text.caption.height),
			flex = "Fill",
			layoutOrder = 1,
		})
		P.button(footer, {
			name = "PickerClose",
			text = "Close",
			variant = "ghost",
			size = "sm",
			layoutOrder = 3,
			onClick = function() dialog.close() end,
		})
		local fittingPicker, compactPicker = false, false
		local galleryFlex = galleryHolder:FindFirstChildOfClass("UIFlexItem")
		local function fitPicker()
			if dialog.closed or fittingPicker then return end
			local height = dialog.card.AbsoluteSize.Y
			if height <= 0 then return end
			fittingPicker = true
			local width = gallery.viewportSize().X -- excludes the gallery insets and scrollbar
			local minimumCard = math.max(theme.size.modalMin, theme.text.small.size * 20)
			local columns = not responsive.isMobile() and width >= minimumCard * 2 + theme.space.md and 2 or 1
			galleryHolder:SetAttribute("Columns", columns)
			for _, card in ipairs(cards) do
				card.instance.Size = UDim2.new(1 / columns, -theme.space.md * (columns - 1) / columns, 0, 0)
			end
			local chrome = math.max(head.AbsoluteSize.Y, theme.text.overline.height + theme.text.title.height + theme.text.small.height * 2 + theme.space.hair * 2)
				+ math.max(tabsRow.AbsoluteSize.Y, theme.size.tab) + math.max(search.shell.AbsoluteSize.Y, theme.size.control)
				+ math.max(footer.AbsoluteSize.Y, theme.size.control) + theme.space.lg + theme.space.md * 5
			local compact = height < chrome + theme.size.control * 3
			-- In short/keyboard space, the original search, tabs, cards and footer
			-- share one scrolling body. No focused field is replaced or hidden.
			viewport.instance.ScrollingEnabled = compact
			viewport.instance.ScrollBarThickness = compact and theme.size.scrollbar or 0
			gallery.instance.ScrollingEnabled = not compact
			galleryFlex.FlexMode = compact and Enum.UIFlexMode.None or Enum.UIFlexMode.Fill
			root.AutomaticSize = compact and Enum.AutomaticSize.Y or Enum.AutomaticSize.None
			root.Size = compact and UDim2.new(1, 0, 0, 0) or UDim2.new(1, 0, 0, height)
			galleryHolder.Size = compact and UDim2.new(1, 0, 0, math.max(theme.size.control,
				gallery.layout.AbsoluteContentSize.Y + theme.space.sm + theme.space.xl)) or UDim2.new(1, 0, 0, 0)
			if compact ~= compactPicker then
				viewport.instance.CanvasPosition = Vector2.new(0, 0)
				gallery.instance.CanvasPosition = Vector2.new(0, 0)
			end
			compactPicker, fittingPicker = compact, false
		end
		dialog.card:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPicker)
		gallery.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPicker)
		for _, instance in ipairs({ head, tabsRow, search.shell, footer }) do
			instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitPicker)
		end
		gallery.layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitPicker)
		local unsubscribePickerLayout = responsive.changed:connect(fitPicker)
		fitPicker()

		local function choose(preset)
			if chosen or closed or not preset then return end
			chosen = true
			if pendingSearch then pcall(task.cancel, pendingSearch); pendingSearch = nil end
			dialog.close()
			if opts.onPick then
				opts.onPick(preset)
				return
			end
			M.editor(registry.blank(preset.id), opts.onSaved)
		end
		P.button(footer, {
			name = "CustomProviderShortcut", text = "Custom endpoint", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() choose(catalog.get("custom")) end,
		})

		local function buildCard(parent, preset, index)
			local included = preset.free == true
			local actionHeight = theme.text.label.height + theme.space.xs * 2
			local card = P.rowButton(parent, {
				name = "Choice_" .. tostring(preset.id),
				auto = "Y",
				vertical = true,
				gap = theme.space.sm,
				padding = { x = theme.space.md, top = theme.space.md, bottom = theme.space.md + theme.space.sm + actionHeight },
				radius = theme.radius.lg,
				bg = theme.color.surfaceRaised,
				bgHover = theme.color.surfaceHover,
				stroke = true,
				strokeColor = included and P.freeModelOutline(theme.color.surfaceRaised) or theme.color.borderSubtle,
				strokeWidth = theme.stroke.hair,
				layoutOrder = index,
				onClick = function() choose(preset) end,
			})
			cards[#cards + 1] = card
			local cardHead = P.row(card.row, {
				name = "ChoiceHead",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.sm,
				layoutOrder = 1,
			})
			local textColumn = P.column(cardHead, {
				name = "ChoiceText",
				size = UDim2.new(0, 0, 0, 0),
				auto = "Y",
				flex = "Fill",
				gap = theme.space.hair,
				layoutOrder = 1,
			})
			P.text(textColumn, {
				name = "ChoiceName",
				text = tostring(preset.label),
				role = "heading",
				color = theme.color.text,
				wrap = true,
				auto = "Y",
				layoutOrder = 1,
			})
			-- Keep the introduction brief, but never trim a highlighted access
			-- requirement. Cost and eligibility stay visible before choosing a route.
			local summary = tostring(preset.description or "")
			local stop = summary:find(". ", 1, true)
			if stop then summary = summary:sub(1, stop) end
			local requirement = tostring(preset.noteHighlight or "")
			if not included and requirement ~= "" and not summary:find(requirement, 1, true) then
				if tostring(preset.description):find(requirement, 1, true) then
					summary = preset.description
				else
					summary = summary .. "\n" .. requirement .. "."
				end
			end
			local description, rich = highlighted(summary, preset.noteHighlight)
			P.text(card.row, {
				name = "ChoiceDescription",
				text = description,
				rich = rich,
				role = "small",
				color = theme.color.textSecondary,
				wrap = true,
				auto = "Y",
				layoutOrder = 2,
			})
			local badgeText, tone = catalog.badge(preset)
			local _, badgeLabel = P.badge(cardHead, { text = badgeText, tone = tone, layoutOrder = 2 })
			badgeLabel.Name = "ChoiceBadge"

			P.text(card.row, {
				name = "ChoiceCost",
				text = tostring(preset.cost or ""),
				role = "caption",
				color = theme.color.textSecondary,
				wrap = true,
				auto = "Y",
				size = UDim2.new(1, 0, 0, 0),
				layoutOrder = 3,
			})
			-- The intrinsic content reserves this space; the action follows the outer
			-- card's bottom when a grid line stretches to fit its taller neighbour.
			local footerRow = P.row(card.instance, {
				name = "ChoiceActionRow", size = UDim2.new(1, -theme.space.md * 2, 0, actionHeight),
				anchor = Vector2.new(0, 1), position = UDim2.new(0, theme.space.md, 1, -theme.space.md), alignX = "Right",
			})
			local action = P.row(footerRow, {
				name = "ChoiceOpen", size = UDim2.fromOffset(0, actionHeight), auto = "X", padding = { x = theme.space.sm, y = theme.space.xs },
				bg = theme.color.surfaceActive, radius = theme.radius.sm,
			})
			P.text(action, { name = "ChoiceAction", text = "Set up", role = "label", color = theme.color.text, auto = "X" })
			return card
		end

		local function emptyGallery(message)
			local column = P.column(gallery.instance, {
				name = "NoProviderMatch",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.sm,
				padding = { x = theme.space.md, y = theme.space.xl },
				layoutOrder = 1,
			})
			P.text(column, {
				name = "NoProviderMatchTitle",
				text = message,
				role = "bodyStrong",
				color = theme.color.text,
				wrap = true,
				auto = "Y",
			})
			P.text(column, {
				text = "Try a company, a model family, or a tier such as free or local.",
				role = "small",
				color = theme.color.textTertiary,
				wrap = true,
				auto = "Y",
			})
			P.button(column, {
				name = "ClearProviderSearchEmpty",
				text = "Clear search",
				variant = "secondary",
				size = "sm",
				onClick = function() resetSearch() end,
			})
		end

		render = function()
			if closed or dialog.closed then return end
			local searching = util.trim(query) ~= ""
			local list
			if searching then
				list = catalog.search(query) or {}
			else
				list = catalog.byTier(tier)
			end
			clearSearch.instance.Visible = searching
			countLabel.Text = countText(#list, tier, searching)
			cards = {}
			gallery.clear()
			viewport.instance.CanvasPosition = Vector2.new(0, 0)
			if #list == 0 then
				local caption = "No provider matches that search."
				if not searching then
					for _, entry in ipairs(catalog.tiers) do
						if entry.id == tier then caption = entry.empty end
					end
				end
				emptyGallery(caption)
				return
			end
			for index, preset in ipairs(list) do
				buildCard(gallery.instance, preset, index)
			end
			-- The escape hatch belongs to every tier. It is also the one card that has
			-- to survive a search for "custom", which is why it is only appended when
			-- the query is empty: a search result set is whatever matched.
			if not searching then
				local custom = catalog.get("custom")
				if custom then buildCard(gallery.instance, custom, #list + 1) end
			end
			gallery.instance.CanvasPosition = Vector2.new(0, 0)
			fitPicker()
		end

		dialog.scrim.Destroying:Connect(function()
			closed = true
			unsubscribePickerLayout()
			if pendingSearch then pcall(task.cancel, pendingSearch); pendingSearch = nil end
		end)

		render()
	end

	-- The connection modal: preset, name, URL, protocol, auth, key and model.
	-- Everything else a record carries -- its models, its behaviour switches, its extra
	-- headers -- is edited in the detail pane, which is a surface that does not have to
	-- be dismissed to see the rest of the screen. This modal exists for the one moment
	-- when none of that is reachable yet: there is no record to select.
	function M.editor(record, onSaved)
		if config.vaultStatus().locked then return env.require("ui/credentialvault").open("unlock") end
		keyData.ensureIds(record)
		local editing = util.deepCopy(record)
		local adding = util.trim(editing.id) == ""
		local retainDraft = adding
		local keyManager, unsubscribeVault
		local modal = overlay.modal({
			title = adding and "Connect a provider" or "Edit connection",
			description = adding and "Add access, choose a model, and save when you're ready."
				or "Update this provider's connection and model.",
			width = theme.size.providerPicker,
			height = math.ceil(theme.size.providerPickerTall / (responsive.isMobile() and theme.metricScale or 1)),
			-- Six labelled rows, two segmented pickers and a footer do not fit on a phone,
			-- and an unbounded modal is centred -- so what did not fit went off the top and
			-- the bottom at once, taking the title and the Save button with it. Bounded and
			-- scrolled, the header and the footer stay put and the form moves.
			scroll = true,
			-- Scrim, close button and Escape preserve every editable connection
			-- field. Saving and Start over explicitly release the retained draft.
			onClose = function()
				if unsubscribeVault then unsubscribeVault(); unsubscribeVault = nil end
				if keyManager and not keyManager.closed then keyManager.close() end
				if retainDraft and util.trim(editing.id) == "" then
					addDraft = draftDirty(editing) and util.deepCopy(editing) or nil
				end
			end,
		})
		if not modal then return end
		modal.card.BackgroundColor3 = theme.color.surface
		unsubscribeVault = config.changed:connect(function(path)
			if (path == nil or path == "security" or path == "security.vault") and config.vaultStatus().locked then
				retainDraft, addDraft = false, nil
				modal.close()
				for _, child in ipairs(modal.card:GetDescendants()) do
					if child:IsA("TextBox") then child.Text = "" end
				end
				for name in pairs(editing) do editing[name] = nil end
			end
		end)

		local form = P.column(modal.content, {
			name = "Form",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.md,
			layoutOrder = 1,
		})
		if editing.credentialsOmitted == true then
			R.paragraph(form,
				"Provider credentials were omitted from saved settings. Restore your API key and any required custom headers, query parameters, body fields or URL credentials. Saving this connection confirms you reviewed those fields and enables requests.",
				{ name = "RestoreProviderCredentials", color = theme.color.warn, role = "small", layoutOrder = 0 })
		end

		-- What this vendor is, in the same words the gallery used to describe it. The
		-- editor is where a key gets pasted, and pasting one into a screen that no
		-- longer says which service it belongs to is how a key ends up on the wrong
		-- endpoint.
		local introHolder, introBadge, introBadgeLabel, introText
		do
			introHolder = P.card(form, {
				name = "PresetIntro",
				gap = theme.space.sm,
				padding = theme.space.md,
				layoutOrder = 1,
			})
			local badgeText, tone = catalog.badge(catalog.get(editing.preset) or {})
			introBadge, introBadgeLabel = P.badge(introHolder, { text = badgeText, tone = tone, layoutOrder = 1 })
			introText = P.text(introHolder, {
				name = "PresetDescription",
				text = "",
				role = "small",
				color = theme.color.textSecondary,
				wrap = true,
				auto = "Y",
				layoutOrder = 3,
			})
		end
		local connectionSection = R.section(form, {
			name = "ConnectionSetup", title = "Connection details", description = "Name and endpoint. Preset defaults stay editable.", layoutOrder = 30,
		})
		local accessSection = R.section(form, {
			name = "AccessSetup", title = "Access", layoutOrder = 10,
		})
		local modelSection = R.section(form, {
			name = "ModelSetup", title = "Model", layoutOrder = 20,
		})
		local function details(name, title, description, opened, order)
			local group = P.column(form, {
				name = name .. "Group", size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm, layoutOrder = order,
			})
			local body, label
			local toggle = P.rowButton(group, {
				name = name .. "Toggle", auto = "Y", vertical = true, padding = { x = theme.space.sm, y = theme.space.sm },
				gap = theme.space.xxs, layoutOrder = 1,
				onClick = function(handle)
					opened = not opened
					body.Visible = opened
					handle.instance:SetAttribute("Expanded", opened)
					label.Text = opened and ("Hide " .. title:lower()) or title
				end,
			})
			label = P.text(toggle.row, { name = name .. "Label", text = opened and ("Hide " .. title:lower()) or title,
				role = "label", color = theme.color.textSecondary, wrap = true, auto = "Y", layoutOrder = 1 })
			P.text(toggle.row, { text = description, role = "caption", color = theme.color.textTertiary,
				wrap = true, auto = "Y", layoutOrder = 2 })
			toggle.instance:SetAttribute("Expanded", opened)
			body = P.card(group, { name = name, gap = theme.space.md, padding = theme.space.md, layoutOrder = 2 })
			body.Visible = opened
			return body
		end
		local guideBody = details("ProviderGuide", "Setup guide", "Key links and provider requirements", true, 40)
		local accessNotice = R.paragraph(accessSection, "", { name = "AccessSummary", color = theme.color.textSecondary, layoutOrder = 1 })

		local problemLabel
		local presetButton, urlField, nameField
		local protocolControl, authControl, keyHintLabel
		local docsRow, docsNoteRow, presetNoteRow
		local proxyNote, communityRow, keyLabel, setKeyButton
		local urlColumn, keyUsageLabel
		local function refreshConnectionInfo()
			local custom = editing.preset == "custom"
			connectionSection.Parent.LayoutOrder = custom and 10 or 30
			accessSection.Parent.LayoutOrder = custom and 20 or 10
			modelSection.Parent.LayoutOrder = custom and 30 or 20
			if proxyNote then
				local target = registry.proxyTarget(editing)
				local usingProxy = registry.proxyProvider(editing)
				proxyNote.Visible = target ~= nil or usingProxy ~= nil
				proxyNote.Text = usingProxy and ("Using the Project UAI proxy: " .. env.require("net/url").display(editing.baseUrl)
					.. ". Requests and API keys pass through puai-proxy.davidzk.tech. Shared limit: 90,000 requests per day. You can edit the Base URL at any time.")
					or target and ("If this endpoint rejects UAI as an unauthorized client, UAI retries through " .. env.require("net/url").display(target)
					.. " and saves that Base URL for this provider. Requests and API keys pass through puai-proxy.davidzk.tech. Shared limit: 90,000 requests per day. The URL stays editable.") or ""
			end
			local included = communityKey.isApplied(editing)
			if communityRow then communityRow.Visible = communityKey.eligible(editing) and not included end
			local preset = catalog.get(editing.preset)
			local requirement = preset and not preset.free and preset.noteHighlight or ""
			if requirement ~= "" and tostring(preset.description):find(requirement, 1, true) then requirement = "" end
			accessNotice.Text = included and "Included access is ready. Shared capacity and response times vary." or requirement
			accessNotice.Visible = accessNotice.Text ~= ""
		end
		-- Any connection edit invalidates fetched choices and in-flight discovery,
		-- including changing away and back before the old response arrives.
		local forgetFetchedModels
		local modelRevision = 0
		local testButton, testRun
		local function invalidateTest()
			testRun = nil
			if testButton and testButton.instance.Parent then
				testButton.setText("Test connection")
				testButton.setEnabled(true)
			end
		end

		local function showProblems()
			refreshConnectionInfo()
			local ok, problems = registry.validate(editing)
			if keyLabel then
				local shown, tone = maskedKey(editing)
				keyLabel.Text, keyLabel.TextColor3 = shown, tone and theme.color.warn or theme.color.textSecondary
			end
			if setKeyButton then
				setKeyButton.instance.Visible = not registry.isCline(editing)
			end
			if keyUsageLabel then
				keyUsageLabel.Text = keyUsage(editing)
				keyUsageLabel.Visible = not registry.isCline(editing)
			end
			if problemLabel then
				problemLabel.Text = ok and "" or (problems[1]:gsub("^%l", string.upper) .. ".")
				problemLabel.Visible = not ok
			end
			return ok
		end

		-- Stable field order is independent of a preset's optional help and links.
		local rowOrder = 0
		local function row(label, hint, build)
			rowOrder = rowOrder + 1
			local parent = label == "Preset" and introHolder
				or (label == "Name" or label == "Base URL") and connectionSection
				or label == "API keys" and accessSection
				or label == "Model" and modelSection or connectionSection
			local column = P.column(parent, {
				name = label:gsub("%s", "") .. "FieldGroup",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.xs,
				layoutOrder = label == "Preset" and 2 or rowOrder * 10,
			})
			if label ~= "Preset" and label ~= "Model" then
				P.text(column, { text = tostring(label), role = "label", color = theme.color.text, layoutOrder = 1 })
			end
			local handle = build(column)
			if type(handle) == "table" then
				local instance = handle.shell or handle.instance
				if instance then instance.LayoutOrder = 2 end
			end
			if hint then
				local note = P.text(column, {
					text = hint,
					role = "caption",
					color = theme.color.textTertiary,
					wrap = true,
					auto = "Y",
					layoutOrder = 9,
				})
				note.Size = UDim2.new(1, 0, 0, 0)
			end
			return handle
		end

		-- Applied in place, not by rebuilding the record.
		--
		-- Choosing a preset used to call registry.blank, replace `editing` wholesale,
		-- close the modal and re-open it -- so a name typed, a key pasted and a URL
		-- corrected were all discarded the moment someone realised they had picked the
		-- wrong vendor. Only the fields the preset actually describes move; the label is
		-- carried over when it still matches the old preset's own name, which is the case
		-- where it was never edited.
		--
		-- Extended help stays in the optional guide. Signup requirements in the
		-- preset summary and the active proxy notice remain in the main form.
		local function refreshDocs()
			refreshConnectionInfo()
			if introHolder then
				local current = catalog.get(editing.preset)
				if current then
					local badgeText, tone = catalog.badge(current)
					introBadgeLabel.Text = badgeText
					introBadgeLabel.TextColor3 = theme.toneColor(tone)
					introBadge.BackgroundColor3 = theme.toneSurface(tone)
					introText.Text = tostring(current.description or "")
					introBadge.Visible = true
				else
					introBadge.Visible = false
					introText.Text = "A custom provider connection."
				end
			end
			if docsRow then docsRow:Destroy() docsRow = nil end
			if docsNoteRow then docsNoteRow:Destroy() docsNoteRow = nil end
			if presetNoteRow then presetNoteRow:Destroy() presetNoteRow = nil end
			local presetRecord = catalog.get(editing.preset)
			if not presetRecord then return end
			if presetRecord.docs then
				-- The full URL, selectable and copyable. Roblox cannot open a browser from
				-- a client GUI, so "get a key here" has to be text a person can select or
				-- one press away from the clipboard -- a "click here" label with the
				-- destination hidden behind it is neither.
				docsRow = P.row(guideBody, {
					name = "KeyLink",
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = theme.space.xs,
					layoutOrder = 11,
				})
				local linkText = P.text(docsRow, {
					name = "KeyLinkUrl",
					text = tostring(presetRecord.docs),
					role = "small",
					color = theme.color.accent,
					wrap = true,
					auto = "Y",
					size = UDim2.new(0, 0, 0, 0),
					flex = "Fill",
					layoutOrder = 1,
				})
				if caps.clipboard then
					P.iconButton(docsRow, {
						name = "CopyKeyLink",
						icon = "copy",
						diameter = theme.size.controlSmall,
						layoutOrder = 2,
						onClick = function()
							local ok = env.require("runtime/clipboard").write(tostring(presetRecord.docs))
							overlay.toast(ok and "Link copied" or "Could not reach the clipboard",
								ok and "good" or "warn", 2)
						end,
					})
				end
				docsNoteRow = R.paragraph(guideBody,
					presetRecord.free and "Save this library choice to enable community access. Discord has availability notices and help."
						or presetRecord.authStyle == "none"
						and "Server setup and API documentation are at the address above."
						or "Keys for this provider are issued at the address above.",
					{ layoutOrder = 12 })
			end
			if presetRecord.note then
				presetNoteRow = R.paragraph(guideBody, presetRecord.note, { layoutOrder = 13 })
			end
		end

		local function applyPreset(id)
			local preset = catalog.get(id)
			if not preset then return end
			local ok, why = env.require("provider/preset").apply(editing, id)
			if not ok then overlay.toast(why, "warn"); return false end
			if keyLabel then
				local shown, tone = maskedKey(editing)
				keyLabel.Text, keyLabel.TextColor3 = shown, tone and theme.color.warn or theme.color.textSecondary
			end
			if presetButton then presetButton.setText(preset.label) end
			if urlField then urlField.set(editing.baseUrl) end
			-- The name follows when it was never hand-edited -- the same rule the label
			-- above applies -- and every control derived from the preset repaints, because a
			-- preset changes the protocol, the auth header, the key hint and the docs link,
			-- and a form where half the rows still describe the previous vendor reads as
			-- broken rather than as partially updated.
			if nameField then nameField.set(editing.label) end
			if protocolControl then protocolControl.set(chat.styleOf(editing)) end
			if authControl then authControl.set(editing.authStyle) end
			if keyHintLabel then
				keyHintLabel.Text = preset.keyHint
					and ("Key hint: " .. tostring(preset.keyHint))
					or ""
				keyHintLabel.Visible = keyHintLabel.Text ~= ""
			end
			refreshDocs()
			if forgetFetchedModels then forgetFetchedModels() end
			showProblems()
			return true
		end

		row("Preset", nil, function(column)
			presetButton = P.button(column, {
				name = "Preset",
				text = (catalog.get(editing.preset) or {}).label or "Custom endpoint",
				variant = "secondary",
				fill = true,
				align = "Left",
				trailing = "chevron",
				trailingColor = theme.color.textTertiary,
				onClick = function()
					-- The same gallery the add flow uses. A menu of every preset was
					-- workable at nine vendors and is unusable at seventy: it cannot be
					-- searched, it cannot say what a vendor costs, and it scrolls in a
					-- 320-pixel column.
					M.picker({
						tier = catalog.tierOf(catalog.get(editing.preset)),
						onPick = function(preset) applyPreset(preset.id) end,
					})
				end,
			})
			return presetButton
		end)

		row("Name", nil, function(column)
			nameField = P.field(column, {
				name = "ProviderName",
				text = editing.label,
				placeholder = "My provider",
				onChange = function(text) editing.label = text end,
				onBlur = showProblems,
			})
			return nameField
		end)

		local normalisedNote
		row("Base URL", nil, function(column)
			urlColumn = column
			urlField = P.field(column, {
				name = "BaseUrl",
				text = editing.baseUrl,
				placeholder = "https://api.example.com/v1",
				onChange = function(text)
					local changed = editing.baseUrl ~= text
					editing.baseUrl = text
					refreshConnectionInfo()
					if changed and forgetFetchedModels then forgetFetchedModels() end
					-- What will actually be stored, before it is stored.
					--
					-- registry.save normalises the URL *and then* validates, so a rejected
					-- save had already rewritten the value while the field still showed the
					-- old text. Saying what the rule does to the input is better than
					-- describing the rule.
					local normalised = registry.normaliseBaseUrl(text)
					if normalisedNote then
						normalisedNote.Text = (normalised ~= "" and normalised ~= util.trim(text))
							and ("Saved as " .. normalised) or ""
						normalisedNote.Visible = normalisedNote.Text ~= ""
					end
				end,
				onBlur = showProblems,
			})
			normalisedNote = P.text(column, {
				text = "",
				visible = false,
				role = "caption",
				color = theme.color.textTertiary,
				wrap = true,
				auto = "Y",
				layoutOrder = 3,
			})
			normalisedNote.Size = UDim2.new(1, 0, 0, 0)
			return urlField
		end)
		proxyNote = R.paragraph(urlColumn, "", { name = "ProxyFallbackNotice", layoutOrder = 10 })

		row("Protocol", "Choose the API exposed by the server: Chat completions, Anthropic Messages, or Google's native Gemini API.",
			function(column)
				protocolControl = C.segmented(column, {
					name = "Protocol",
					options = chat.STYLES,
					value = chat.styleOf(editing),
					onChange = function(value)
						if editing.api == value then return end
						editing.api = value
						if forgetFetchedModels then forgetFetchedModels() end
						showProblems()
					end,
				})
				return protocolControl
			end)

		row("Auth header", nil, function(column)
			authControl = P.button(column, {
				name = "AuthStyle",
				text = labelOf(AUTH_OPTIONS, editing.authStyle), variant = "secondary", fill = true, align = "Left", trailing = "chevron",
				onClick = function(handle)
					local options = {}
					for _, option in ipairs(AUTH_OPTIONS) do
						options[#options + 1] = { value = option.value, label = option.label, selected = editing.authStyle == option.value }
					end
					overlay.menu({ target = handle.instance, options = options, onSelect = function(value)
						local changed = editing.authStyle ~= value
						editing.authStyle = value
						handle.setText(labelOf(AUTH_OPTIONS, value))
						if changed and forgetFetchedModels then forgetFetchedModels() end
						showProblems()
					end })
				end,
			})
			authControl.set = function(value) authControl.setText(labelOf(AUTH_OPTIONS, value)) end
			return authControl
		end)

		-- Keep connection setup compact. The key manager owns its own draft and
		-- applies names, credentials and routing together, without saving the provider.
		row("API keys", nil, function(column)
			local shown, tone = maskedKey(editing)
			keyLabel = P.text(column, {
				name = "KeyState",
				text = shown,
				role = "monoSmall",
				color = tone and theme.color.warn or theme.color.textSecondary,
				wrap = true, auto = "Y",
				layoutOrder = 2,
			})
			keyUsageLabel = R.paragraph(column, keyUsage(editing), { name = "KeyUsage", layoutOrder = 3 })
			setKeyButton = P.button(column, {
				name = "ManageKeys",
				text = "Manage API keys",
				variant = "secondary",
				size = "sm",
				layoutOrder = 4,
				onClick = function()
					if modal.closed or registry.isCline(editing) or (keyManager and not keyManager.closed) then return end
					keyManager = env.require("ui/providerkeys").open({
						record = editing,
						onClose = function() keyManager = nil end,
						onApply = function(updated)
							if modal.closed or registry.isCline(editing) then return false end
							if applyKeys(editing, updated) and forgetFetchedModels then forgetFetchedModels() end
							if editing.preset == "projectuai-free" and not communityKey.isApplied(editing)
								and util.trim(editing.apiKey) ~= "" then
								if not applyPreset("hcnsec") then return false end
								overlay.toast("Personal keys use the separate HCNSEC provider. This draft now uses HCNSEC.", "info")
							end
							showProblems()
							return true
						end,
					})
				end,
			})
			communityRow = P.column(column, { name = "CommunityKey", size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.xs, layoutOrder = 6 })
			R.paragraph(communityRow, "Restore this provider's community access. Personal keys belong to the separate HCNSEC provider.", { layoutOrder = 1 })
			P.button(communityRow, { name = "UseCommunityKey", text = "Use included free access", variant = "secondary", fill = true, layoutOrder = 2,
				onClick = function()
					local ok, why = communityKey.apply(editing)
					if not ok then overlay.toast(why, "warn"); return end
					if forgetFetchedModels then forgetFetchedModels() end
					local shown = maskedKey(editing)
					keyLabel.Text, keyLabel.TextColor3 = shown, theme.color.textSecondary
					showProblems()
					overlay.toast("Community key added to this draft. Choose a model and save to use it.", "good")
				end })
			return keyLabel
		end)

		-- What a key for this preset looks like, when the preset knows. It is a hint,
		-- not a field: the shape of an OpenAI key is not the shape of a Gemini key, and
		-- the person pasting one wants to know they are pasting the right kind of thing
		-- before the request fails on the far end. The docs link and the preset note sit
		-- together in the optional guide, and update in place with the preset.
		keyHintLabel = P.text(guideBody, {
			name = "KeyHint",
			text = (catalog.get(editing.preset) or {}).keyHint
				and ("Key hint: " .. tostring((catalog.get(editing.preset) or {}).keyHint)) or "",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 10,
		})
		keyHintLabel.Size = UDim2.new(1, 0, 0, 0)
		keyHintLabel.Visible = keyHintLabel.Text ~= ""
		R.paragraph(guideBody, "Keys are masked here. Settings / Privacy lets you choose password encryption or unprotected storage. Requests send them to the configured provider, gateway or relay.", { layoutOrder = 14 })

		-- Model.
		--
		-- The one field a record cannot be saved without, and the editor had none. The
		-- picker lives on the detail pane, which you reach by selecting a provider that has
		-- already been saved -- and `registry.validate` refuses to save a record with no
		-- model. So adding a provider ended at "fetch the model list or add a model id"
		-- with nothing on screen that could do either, and Test asked the endpoint for a
		-- completion with no model named, which comes back as the provider's own wording
		-- for that and reads as a broken connection.
		local modelButton, modelNote, fetchButton
		local fetched = {}

		-- What the picker offers: the ids already on the record, plus whatever this
		-- editor's own fetch turned up. Discovery has a connection-scoped cache, but
		-- choices here belong to this editor and expire as its connection is edited.
		local function knownModels()
			local out, seen = {}, {}
			for _, id in ipairs(editing.models or {}) do
				if util.trim(id) ~= "" and not seen[id] then
					seen[id] = true
					out[#out + 1] = id
				end
			end
			for _, id in ipairs(fetched) do
				if not seen[id] then
					seen[id] = true
					out[#out + 1] = id
				end
			end
			return out
		end

		local DEFAULT_MODEL_NOTE = "Model IDs come from your provider. Fetch its catalog or add an ID manually."

		local function setModelNote(text, bad)
			if not modelNote then return end
			modelNote.Text = tostring(text)
			modelNote.TextColor3 = bad and theme.color.warn or theme.color.textTertiary
		end

		local paintedModel
		local function paintModel()
			local current = util.trim(editing.model)
			if current ~= paintedModel then invalidateTest(); paintedModel = current end
			if modelButton then
				modelButton.setText(current ~= "" and current or "Choose a model")
			end
		end

		local openModelMenu
		local function adoptProxy(candidate, revision)
			if revision ~= modelRevision or not registry.proxyProvider(candidate) or candidate.baseUrl == registry.normaliseBaseUrl(editing.baseUrl) then return end
			editing.baseUrl = candidate.baseUrl
			urlField.set(editing.baseUrl)
			if forgetFetchedModels then forgetFetchedModels() end
			refreshConnectionInfo()
		end

		-- Fetches against the record as it would be saved, not as it is typed: the URL is
		-- normalised the same way `save` normalises it, so what is asked for is the
		-- endpoint the provider will actually use.
		local function fetchModels(handle)
			local target = util.deepCopy(editing)
			target.baseUrl = registry.normaliseBaseUrl(target.baseUrl)
			if target.baseUrl == "" then
				setModelNote("Add the base URL first -- there is nothing to ask.", true)
				return
			end
			modelRevision = modelRevision + 1
			local revision = modelRevision
			invalidateTest()
			handle.setEnabled(false)
			if fetchButton then fetchButton.setEnabled(false) end
			setModelNote("Loading " .. modelSource(target) .. "...", false)
			task.spawn(function()
				local found, note = models.discover(target, { force = true,
					aborted = function() return modal.closed or revision ~= modelRevision end })
				if modal.closed or not handle.instance.Parent or revision ~= modelRevision then return end
				adoptProxy(target, revision)
				handle.setEnabled(true)
				if fetchButton then fetchButton.setEnabled(true) end
				fetched = found
				setModelNote(note, #found == 0)
				-- Straight back into the list. Picking one is the reason to fetch, and a
				-- notice that says "42 models" while the menu stays shut makes someone press
				-- the same control twice for one decision.
				if #found > 0 then openModelMenu(handle) end
			end)
		end

		local function typeModel()
			-- A manual entry supersedes a discovery still loading in this form.
			modelRevision = modelRevision + 1
			invalidateTest()
			if modelButton then modelButton.setEnabled(true) end
			if fetchButton then fetchButton.setEnabled(true) end
			overlay.prompt({
				title = "Model id",
				description = "Type it exactly as the provider expects it. It is saved with this "
					.. "provider and selected.",
				placeholder = "model id",
				confirmText = "Use it",
				onConfirm = function(text)
					-- Not persisted: the record is still being edited and may never be saved.
					local ok, result = models.add(editing, text, { persist = false, select = true })
					setModelNote(ok and ("Using " .. tostring(result)) or tostring(result), not ok)
					paintModel()
					showProblems()
				end,
			})
		end

		openModelMenu = function(handle)
			local revision = modelRevision
			local options = {}
			local own = {}
			for _, id in ipairs(editing.models or {}) do own[id] = true end
			for _, id in ipairs(knownModels()) do
				local badge = traits.badge(id, editing)
				local bits = {}
				if models.isFree(editing, id) then bits[#bits + 1] = "Free" end
				if badge then bits[#bits + 1] = badge end
				if not own[id] then bits[#bits + 1] = "from catalog" end
				options[#options + 1] = {
					label = id,
					value = "model:" .. id,
					detail = #bits > 0 and table.concat(bits, "  \194\183  ") or nil,
					selected = id == editing.model,
					free = models.isFree(editing, id),
				}
			end
			if #options > 0 then options[#options + 1] = { divider = true } end
			options[#options + 1] = {
				label = fetchLabel(editing),
				value = "fetch",
				detail = modelSource(editing),
				searchable = false,
				tone = "info",
			}
			options[#options + 1] = { label = "Type an id", value = "add", tone = "info", searchable = false }
			overlay.menu({
				target = handle.instance,
				width = theme.size.menuWide,
				options = options,
				searchable = true,
				searchPlaceholder = "Search model IDs...",
				emptyText = "No matching models. Refresh the catalog or type an exact ID.",
				onSelect = function(value)
					if revision ~= modelRevision then return end
					if value == "fetch" then
						fetchModels(handle)
					elseif value == "add" then
						typeModel()
					elseif util.startsWith(tostring(value), "model:") then
						local id = tostring(value):sub(7)
						models.add(editing, id, { persist = false, select = true })
						editing.model = id
						setModelNote(DEFAULT_MODEL_NOTE, false)
						paintModel()
						showProblems()
					end
				end,
			})
		end

		row("Model", nil, function(column)
			modelButton = P.button(column, {
				name = "ActiveModel",
				text = "Choose a model",
				variant = "secondary",
				fill = true,
				align = "Left",
				trailing = "chevron",
				onClick = openModelMenu,
			})
			modelNote = P.text(column, {
				name = "ModelNote",
				text = DEFAULT_MODEL_NOTE,
				role = "caption",
				color = theme.color.textTertiary,
				wrap = true,
				auto = "Y",
				layoutOrder = 4,
			})
			local actions = P.row(column, { name = "SetupModelActions", size = UDim2.new(1, 0, 0, 0), auto = "Y",
				gap = theme.space.xs, wrap = true, layoutOrder = 3 })
			fetchButton = P.button(actions, { name = "FetchSetupModels", text = "Fetch catalog", variant = "secondary", size = "sm", layoutOrder = 1,
				onClick = function() if modelButton.instance.Active then fetchModels(modelButton) end end })
			P.button(actions, { name = "TypeSetupModel", text = "Enter model ID", variant = "ghost", size = "sm", layoutOrder = 2,
				onClick = typeModel })
			modelNote.Size = UDim2.new(1, 0, 0, 0)
			paintModel()
			return modelButton
		end)

		forgetFetchedModels = function()
			modelRevision = modelRevision + 1
			invalidateTest()
			fetched = {}
			if modelButton then modelButton.setEnabled(true) end
			if fetchButton then fetchButton.setEnabled(true) end
			paintModel()
			setModelNote(DEFAULT_MODEL_NOTE, false)
		end

		refreshDocs()

		problemLabel = P.text(modal.content, {
			name = "Problem",
			text = "",
			role = "small",
			color = theme.color.danger,
			wrap = true,
			auto = "Y",
			visible = false,
			layoutOrder = 0,
		})
		problemLabel.Size = UDim2.new(1, 0, 0, 0)

		testButton = P.button(modal.footer, {
			name = "TestConnection",
			text = "Test connection",
			variant = "ghost",
			size = "sm",
			layoutOrder = 1,
			-- Through onClick, not a raw Activated connection: that is what P.button's own
			-- re-entry guard hangs off, and connecting to Activated directly meant a double
			-- tap fired two concurrent completions.
			onClick = function(handle)
				-- A completion needs a model named, so testing without one asks the endpoint
				-- a question it cannot answer -- and what comes back is that provider's own
				-- wording for "no model", which reads as a broken connection rather than as
				-- an empty field one row up.
				if editing.preset ~= "azure" and util.trim(editing.model) == "" then
					problemLabel.Text = "Choose a model first: fetch the list, or type the id."
					problemLabel.Visible = true
					modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
					return
				end
				handle.setEnabled(false)
				handle.setText("Testing")
				local revision = modelRevision
				local token = {}; testRun = token
				local candidate = registry.shareKeyRotation(editing, util.deepCopy(editing))
				candidate.baseUrl = registry.normaliseBaseUrl(candidate.baseUrl)
				local function aborted()
					return modal.closed or not handle.instance.Parent or testRun ~= token or revision ~= modelRevision
				end
				task.spawn(function()
					local result, err = chat.complete(candidate, {
						messages = { { role = "user", content = "Reply with the single word: ready" } },
						stream = registry.isOpencode(candidate) or false,
						maxTokens = 12,
						attempts = 1,
						aborted = aborted,
					})
					if aborted() then return end
					testRun = nil
					adoptProxy(candidate, revision)
					handle.setText("Test connection")
					handle.setEnabled(true)
					if result then
						overlay.toast(string.format("Reached %s in %s",
							candidate.label, util.formatDuration(result.ms)), "good")
					else
						problemLabel.Text = tostring(err)
						problemLabel.Visible = true
						modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
					end
				end)
			end,
		})

		if adding then
			P.button(modal.footer, {
				name = "StartOverProvider",
				text = "Start over",
				variant = "ghost",
				size = "sm",
				layoutOrder = 0,
				onClick = function()
					retainDraft = false
					addDraft = nil
					modal.close()
					M.add(onSaved)
				end,
			})
		end

		P.button(modal.footer, {
			name = "SaveProvider",
			text = adding and "Add provider" or "Save changes",
			variant = "primary",
			size = "sm",
			layoutOrder = 2,
			onClick = function()
				local current = not adding and registry.get(editing.id)
				if current and sameKeyConnection(current, editing) then
					-- Requests may advance the live cursor while a connection draft is
					-- open. A label-only edit must not restore its old copied cursor.
					editing.keyRotation = current.keyRotation
				end
				local ok, problems = registry.save(editing, { credentialsRestored = true })
				if not ok then
					-- Sentence-cased and one per line. It was table.concat(problems, ". "),
					-- which turned two lowercase fragments into "give the provider a name.
					-- base URL is required".
					local lines = {}
					for index, problem in ipairs(problems) do
						lines[index] = problem:gsub("^%l", string.upper) .. "."
					end
					problemLabel.Text = table.concat(lines, "\n")
					problemLabel.Visible = true
					modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
					return
				end
				if adding then addDraft = nil end
				retainDraft = false
				modal.close()
				overlay.toast("Saved " .. editing.label, "good", 2)
				if onSaved then onSaved(editing.id) end
			end,
		})

		showProblems()
		-- Nothing is wrong yet on a brand-new record; it is simply incomplete.
		if adding then problemLabel.Visible = false end
	end

	-- The entry point for adding: the gallery, then the editor.
	--
	-- A retained draft resumes directly. Someone who dismissed the editor mid-setup is
	-- not starting over, and showing them the gallery first would make them choose the
	-- vendor twice for the same unfinished provider.
	function M.add(onSaved)
		if addDraft then
			local draft = addDraft
			addDraft = nil
			M.editor(draft, onSaved)
			return
		end
		M.picker({ onSaved = onSaved })
	end

	local savedKeyManager
	function M.manageKeys(record, onSaved)
		if registry.isCline(record) then return nil end
		if savedKeyManager and not savedKeyManager.closed then return savedKeyManager end
		savedKeyManager = env.require("ui/providerkeys").open({
			record = record,
			applyHint = "Apply changes updates this provider's keys and request preferences using the storage preference shown above.",
			onClose = function() savedKeyManager = nil end,
			onApply = function(updated)
				local current = registry.get(record.id)
				if not current or registry.isCline(current) then
					overlay.toast("This provider is no longer available. Reopen its settings.", "warn")
					return false
				end
				local candidate = util.deepCopy(current)
				candidate.keyRotation, candidate.health = current.keyRotation, current.health
				local connectionChanged = applyKeys(candidate, updated)
				local ok, problems = registry.save(candidate)
				if not ok then
					overlay.toast(problems[1] or "Could not save API keys", "warn")
					return false
				end
				if connectionChanged then models.invalidate(candidate.id) end
				if candidate.credentialsOmitted == true then
					overlay.toast("Keys updated. Open Edit connection to review custom authentication, then save to enable requests.", "info", 5)
				end
				if onSaved then onSaved(candidate.id) end
				return true
			end,
		})
		return savedKeyManager
	end

	-- The empty panel's start card.
	--
	-- One card rather than a stack of five. The gallery is where the full list lives
	-- now, so this surface only has to answer "what do I do first": browse, go custom,
	-- or take one of the first recommendations. Each quick pick opens the editor already
	-- seeded, and included free access still needs one press.
	function M.startCard(parent, onSetup, nextOrder)
		local card = P.card(parent, {
			name = "StartCard",
			gap = theme.space.md,
			padding = theme.space.lg,
			layoutOrder = type(nextOrder) == "function" and nextOrder() or 1,
			strokeColor = theme.color.accentBorder,
		})

		local head = P.column(card, {
			name = "StartHead",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.hair,
			layoutOrder = 1,
		})
		P.text(head, {
			name = "StartOverline",
			text = "START HERE",
			role = "overline",
			color = theme.color.accent,
			size = UDim2.new(1, 0, 0, theme.text.overline.height),
			layoutOrder = 1,
		})
		P.text(head, {
			name = "StartTitle",
			text = "Add a provider",
			role = "display",
			color = theme.color.text,
			wrap = true,
			auto = "Y",
			layoutOrder = 2,
		})
		P.text(head, {
			name = "StartDescription",
			text = "Free routes need no card. Paid routes need a key or credit. Local servers run on your machine. Pick any of them and every field stays editable.",
			role = "small",
			color = theme.color.textSecondary,
			wrap = true,
			auto = "Y",
			layoutOrder = 3,
		})

		local actions = P.row(card, {
			name = "StartActions",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			wrap = true,
			gap = theme.space.sm,
			layoutOrder = 2,
		})
		P.button(actions, {
			name = "StartBrowse",
			text = "Browse providers",
			variant = "primary",
			size = "sm",
			layoutOrder = 1,
			onClick = function() M.picker({ onSaved = onSetup }) end,
		})
		P.button(actions, {
			name = "StartCustom",
			text = "Custom endpoint",
			variant = "secondary",
			size = "sm",
			layoutOrder = 2,
			onClick = function() M.editor(registry.blank("custom"), onSetup) end,
		})

		local picks = P.column(card, {
			name = "StartPicks",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.hair,
			layoutOrder = 3,
		})
		for index, preset in ipairs(catalog.featured()) do
			local row = P.rowButton(picks, {
				name = "Start_" .. tostring(preset.id),
				height = theme.size.controlLarge,
				padding = { x = theme.space.sm },
				radius = theme.radius.md,
				layoutOrder = index,
				onClick = function()
					M.editor(registry.blank(preset.id), onSetup)
				end,
			})
			row.label(preset.label, 1, theme.color.text, "small")
			local badgeText, tone = catalog.badge(preset)
			P.badge(row.row, { text = badgeText, tone = tone, layoutOrder = 2 })
			row.icon("chevron", 3, theme.color.textTertiary, theme.size.icon)
		end
		return card
	end

	-- List and detail ---------------------------------------------------------

	function M.new(parent)
		local panel = {}
		local selected = nil
		local selectionRevision = 0

		-- Two columns where there is room for two, stacked where there is not. Same rule
		-- and same threshold as the settings dialog, which solved this first.
		local wide = parent.AbsoluteSize.X >= (theme.size.dialogNav * 3)

		local root, rootLayout = P.row(parent, { name = "ProvidersRoot", size = UDim2.fromScale(1, 1), gap = 0 })
		rootLayout.FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		local railHeight = math.max(theme.size.controlLarge, responsive.minTarget(),
			theme.text.small.height + theme.space.xs * 2)

		local railHolder = P.frame(root, {
			name = "ProviderRail",
			size = wide and UDim2.new(0, theme.size.dialogNav, 1, 0)
				or UDim2.new(1, 0, 0, railHeight + theme.space.xs * 2 + theme.size.scrollbar),
			bg = theme.color.sidebar,
			layoutOrder = 1,
		})
		local rail = P.column(railHolder, {
			size = UDim2.fromScale(1, 1),
			gap = theme.space.xs,
			padding = theme.space.xs,
		})
		local railScrollHolder = P.frame(rail, {
			size = UDim2.new(1, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 1,
		})
		local railScroll = P.scroll(railScrollHolder, {
			name = "ProviderList",
			size = UDim2.fromScale(1, 1),
			gap = theme.space.hair,
			horizontal = not wide,
			alignX = "Left",
		})
		railScroll.layout.VerticalAlignment = wide and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
		-- Under the list where there is a column to put it under, and at the end of the
		-- strip where there is not -- so there is exactly one of it either way.
		local addButton = P.button(rail, {
			name = "AddProvider",
			text = "Add a provider",
			icon = "plus",
			variant = "secondary",
			size = "sm",
			fill = true,
			layoutOrder = 2,
			onClick = function()
				M.add(function(id) panel.select(id) end)
			end,
		})
		addButton.instance.Visible = wide

		local divider = P.divider(root, {
			vertical = wide,
			color = theme.color.borderSubtle,
			layoutOrder = 2,
		})

		local detailHolder = P.frame(root, {
			name = "ProviderDetail",
			size = wide and UDim2.new(0, 0, 1, 0) or UDim2.new(1, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 3,
		})
		local detail = P.scroll(detailHolder, {
			name = "DetailScroll",
			size = UDim2.fromScale(1, 1),
			gap = theme.space.lg,
			padding = { x = theme.space.lg, top = theme.space.lg, bottom = theme.space.xl },
		})

		-- Rail -----------------------------------------------------------------

		local railRows = {}

		local function dotFor(record, isActive)
			if registry.cooling(record) then return theme.color.danger end
			if record.enabled == false then return theme.color.textDisabled end
			if isActive then return theme.color.accent end
			return theme.color.textTertiary
		end

		function panel.renderRail()
			local position = railScroll.instance.CanvasPosition
			railScroll.clear()
			railRows = {}
			local list = registry.list()
			local active = registry.active()
			for index, record in ipairs(list) do
				local isActive = active and active.id == record.id
				local row = P.rowButton(railScroll.instance, {
					name = "Provider_" .. tostring(record.id),
					size = (not wide) and UDim2.fromOffset(0, railHeight) or nil,
					auto = (not wide) and "X" or nil,
					height = railHeight,
					padding = { x = theme.space.sm },
					radius = theme.radius.md,
					selected = record.id == selected,
					layoutOrder = index,
					onClick = function() panel.select(record.id) end,
				})
				local dotSlot = P.frame(row.row, {
					name = "Health",
					size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
					layoutOrder = 1,
				})
				local dot = P.statusDot(dotSlot, {
					diameter = theme.size.dot,
					color = dotFor(record, isActive),
					anchor = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
				})
				local colour = record.id == selected and theme.color.text or theme.color.textSecondary
				if wide then
					row.label(record.label, 2, colour, "small")
				else
					-- Intrinsic tabs: no menu-width reserve and no Fill child in an
					-- auto-width row. Long names stop growing before consuming the strip.
					P.text(row.row, { name = "Label", text = record.label, role = "small",
						color = colour, auto = "X", truncate = true,
						maxSize = Vector2.new(theme.size.menuMin, math.huge), layoutOrder = 2 })
				end
				-- A badge, not text appended to the title. It used to be "  (active)"
				-- concatenated into a truncating label, so on a narrow rail the one fact
				-- that says which endpoint is in use was the first thing cut.
				if isActive then
					local badge = P.badge(row.row, { text = "Active", tone = "accent", layoutOrder = 3 })
					badge.LayoutOrder = 3
				end
				railRows[record.id] = { row = row, dot = dot }
			end
			if #list == 0 then
				local empty = P.text(railScroll.instance, {
					name = "NoProviders",
					text = "Nothing configured yet.",
					role = "caption",
					color = theme.color.textTertiary,
					wrap = true,
					auto = "Y",
					padding = { x = theme.space.sm, y = theme.space.xs },
					layoutOrder = 1,
				})
				empty.Size = wide and UDim2.new(1, 0, 0, 0) or UDim2.fromOffset(theme.size.menuMin, theme.text.caption.height)
			end
			if not wide then
				-- With the rail collapsed to a strip there is no room under it for the
				-- button, so it rides at the end of the strip instead.
				local add = P.button(railScroll.instance, {
					name = "AddProvider",
					text = "Add",
					icon = "plus",
					variant = "secondary",
					size = "sm",
					layoutOrder = #list + 1,
					onClick = function(handle)
						M.add(function(id) panel.select(id) end)
					end,
				})
				add.instance.LayoutOrder = #list + 1
			end
			railScroll.instance.CanvasPosition = position
		end

		-- AbsoluteSize may still be zero at construction, and desktop resizing does
		-- not change responsive.mode. Reflow the existing detail rather than replacing
		-- a form somebody is typing into.
		local function reflow()
			local width = root.AbsoluteSize.X
			if width <= 0 then return end
			local nextWide = width >= theme.size.dialogNav * 3
			local changed = nextWide ~= wide
			wide = nextWide
			rootLayout.FillDirection = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
			rootLayout.VerticalAlignment = Enum.VerticalAlignment.Top
			railHolder.Size = wide and UDim2.new(0, theme.size.dialogNav, 1, 0)
				or UDim2.new(1, 0, 0, railHeight + theme.space.xs * 2 + theme.size.scrollbar)
			addButton.instance.Visible = wide
			divider.Size = wide and UDim2.new(0, theme.stroke.hair, 1, 0)
				or UDim2.new(1, 0, 0, theme.stroke.hair)
			detailHolder.Size = wide and UDim2.new(0, 0, 1, 0) or UDim2.new(1, 0, 0, 0)
			railScroll.layout.FillDirection = wide and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
			railScroll.layout.VerticalAlignment = wide and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
			railScroll.instance.AutomaticCanvasSize = wide and Enum.AutomaticSize.Y or Enum.AutomaticSize.X
			railScroll.instance.ScrollingDirection = wide and Enum.ScrollingDirection.Y or Enum.ScrollingDirection.X
			railScroll.instance.VerticalScrollBarInset = wide and Enum.ScrollBarInset.ScrollBar or Enum.ScrollBarInset.None
			railScroll.instance.HorizontalScrollBarInset = wide and Enum.ScrollBarInset.None or Enum.ScrollBarInset.ScrollBar
			if changed then
				railScroll.instance.CanvasPosition = Vector2.new(0, 0)
				panel.renderRail()
			end
		end
		root:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
		local unsubscribeLayout = responsive.changed:connect(reflow)
		reflow()

		-- Detail ---------------------------------------------------------------

		local statusBox = nil
		local healthError = nil
		local modelQueries = {}
		local modelPositions = {}

		local function order()
			panel.__order = (panel.__order or 0) + 1
			return panel.__order
		end

		local function modelMenu(record, target, onDone)
			local options = {}
			local own = {}
			for _, id in ipairs(record.models or {}) do own[id] = true end
			for _, id in ipairs(models.list(record)) do
				local badge = traits.badge(id, record)
				local bits = {}
				if models.isFree(record, id) then bits[#bits + 1] = "Free" end
				if badge then bits[#bits + 1] = badge end
				if not own[id] then bits[#bits + 1] = "from catalog" end
				options[#options + 1] = {
					label = id,
					value = "model:" .. id,
					detail = #bits > 0 and table.concat(bits, "  \194\183  ") or nil,
					selected = id == record.model,
					free = models.isFree(record, id),
				}
			end
			if #options > 0 then options[#options + 1] = { divider = true } end
			options[#options + 1] = {
				label = fetchLabel(record),
				value = "fetch",
				detail = modelSource(record),
				searchable = false,
				tone = "info",
			}
			options[#options + 1] = { label = "Add a model by id", value = "add", tone = "info", searchable = false }
			overlay.menu({
				target = target,
				width = theme.size.menuWide,
				options = options,
				searchable = true,
				searchPlaceholder = "Search model IDs...",
				emptyText = "No matching models. Refresh the catalog or add an exact ID.",
				onSelect = function(value)
					if value == "fetch" then
						local revision = selectionRevision
						local function aborted()
							return not root.Parent or selected ~= record.id or revision ~= selectionRevision or registry.get(record.id) ~= record
						end
						overlay.toast("Fetching models from " .. record.label, "info", 2)
						task.spawn(function()
							local found, note = models.discover(record, { force = true, aborted = aborted })
							if aborted() then return end
							overlay.toast(tostring(note), #found > 0 and "good" or "warn", 3)
							if onDone then pcall(onDone) end
						end)
					elseif value == "add" then
						overlay.prompt({
							title = "Add a model to " .. record.label,
							description = "Type the id exactly as the provider expects it. "
								.. "It is saved to this provider and selected.",
							placeholder = "model id",
							confirmText = "Add",
							onConfirm = function(text)
								local ok, result = models.add(record, text)
								if ok then registry.setModel(record.id, util.trim(text)) end
								overlay.toast(tostring(result), ok and "good" or "warn", 3)
								if onDone then pcall(onDone) end
							end,
						})
					elseif util.startsWith(tostring(value), "model:") then
						registry.setModel(record.id, tostring(value):sub(7))
						if onDone then pcall(onDone) end
					end
				end,
			})
		end

		function panel.renderDetail()
			detail.clear()
			statusBox = nil
			healthError = nil
			panel.__order = 0
			local record = selected and registry.get(selected) or nil
			if config.vaultStatus().locked then
				local locked = R.section(detail.instance, { name = "ProviderVaultLocked", title = "Credential vault locked",
					description = "Unlock saved credentials before changing providers or making requests.", layoutOrder = order() })
				P.button(locked, { name = "UnlockProviderVault", text = "Unlock credential vault", fill = true,
					onClick = function() env.require("ui/credentialvault").open("unlock") end })
				return
			end
			-- Included free access must not hide the way to anything else.
			local list = registry.list()
			if not record then
				if #list == 0 then
					-- Nothing configured: the start card is the empty state. Two surfaces
					-- saying "add a provider" one above the other is one too many.
					M.startCard(detail.instance, function(id) panel.select(id) end, order)
				else
					C.emptyState(detail.instance, {
						title = "Pick a provider from the list",
						description = "Its endpoint, key, model and health are all edited here.",
						layoutOrder = order(),
					})
				end
				return
			end
			-- A panel holding nothing but the included free route is still a first run:
			-- keep the way to a paid or local provider visible above its detail.
			if #list == 1 and communityKey.isApplied(list[1]) then
				M.startCard(detail.instance, function(id) panel.select(id) end, order)
			end

			local active = registry.active()
			local isActive = active and active.id == record.id

			-- Header. The window chrome already names the panel and the active provider, so
			-- this names the record being edited instead of repeating either.
			local head = P.row(detail.instance, {
				name = "DetailHead",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.sm,
				layoutOrder = order(),
			})
			local titleColumn = P.column(head, {
				size = UDim2.new(0, 0, 0, 0),
				auto = "Y",
				flex = "Fill",
				gap = theme.space.hair,
				layoutOrder = 1,
			})
			local title = P.text(titleColumn, {
				name = "ProviderTitle",
				text = record.label,
				role = "display",
				color = theme.color.text,
				wrap = true,
				auto = "Y",
			})
			title.Size = UDim2.new(1, 0, 0, 0)
			-- Which tier this record belongs to, before the address. A panel with a
			-- free route and three paid ones reads as a list of equal things otherwise,
			-- and the one question someone has about a provider is what it costs.
			local subtitleRow = P.row(titleColumn, {
				name = "ProviderMeta",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.xs,
			})
			local presetForRecord = catalog.get(record.preset)
			if presetForRecord then
				local badgeText, tone = catalog.badge(presetForRecord)
				P.badge(subtitleRow, { text = badgeText, tone = tone, layoutOrder = 1 })
			end
			local subtitle = P.text(subtitleRow, {
				name = "ProviderEndpoint",
				text = registry.isCline(record) and "Cline through the desktop app" or urls.display(record.baseUrl),
				role = "caption",
				color = theme.color.textTertiary,
				truncate = true,
				size = UDim2.new(0, 0, 0, theme.text.caption.height),
				flex = "Fill",
				layoutOrder = 2,
			})

			-- Status ------------------------------------------------------------
			local modelOrder = order()
			local status = R.section(detail.instance, {
				name = "Status",
				title = "Connection",
				description = "Your endpoint, authentication and recent connection health.",
				layoutOrder = order(),
			})
			statusBox = R.facts(status, factsFor(record), { name = "StatusFacts", layoutOrder = 1 })

			local health = record.health or {}
			healthError = R.paragraph(status, health.lastError or "",
				{ name = "HealthError", color = theme.color.danger, layoutOrder = 2 })
			healthError.Visible = util.trim(health.lastError or "") ~= ""
			-- The preset's own guidance, which the registry copies onto every record and
			-- nothing has ever rendered: Azure's deployment-path rule, Ollama's loopback
			-- warning, DeepSeek's reasoning field.
			local preset = catalog.get(record.preset)
			local note = (preset and (preset.free or registry.isOpencode(record)) and preset.note) or record.note
			if util.trim(note or "") ~= "" then
				R.paragraph(status, note, { name = "ProviderIntroduction", layoutOrder = 3 })
			end
			-- Fallback is a global switch, and the old header claimed the chain was always
			-- in use. Saying which it is beats asserting one of them.
			R.paragraph(status, config.get("agent.fallback", true)
				and "Requests try the active provider first, then every other enabled one."
				or "Fallback is off under Settings, so only the active provider is tried.",
				{ layoutOrder = 4 })

			local actions = {}
			actions[#actions + 1] = {
				name = "ProviderCommunity", text = "Discord community", variant = "ghost",
				onClick = function() env.require("ui/community").open() end,
			}
			if not isActive then
				actions[#actions + 1] = {
					name = "UseProvider",
					text = "Use this provider",
					variant = "primary",
					onClick = function()
						local ok, why = registry.setActive(record.id)
						overlay.toast(ok and (record.label .. " is now the active provider") or tostring(why), ok and "good" or "warn", 2)
					end,
				}
			end
			actions[#actions + 1] = {
				name = "EditConnection",
				text = "Edit connection",
				variant = "secondary",
				onClick = function() M.editor(record, function() panel.select(record.id) end) end,
			}
			if record.preset ~= "projectuai-free" then
				actions[#actions + 1] = { name = "DuplicateConnection", text = "Duplicate setup", variant = "ghost", onClick = function()
					local draft, why = connectionActions.duplicate(record)
					if not draft then overlay.toast(tostring(why), "warn", 3); return end
					M.editor(draft, function(id) panel.select(id) end)
					overlay.toast("Setup copied without keys or custom credential fields. Review and save the new connection.", "info", 4)
				end }
			end
			if connectionActions.hasLearned(record) then
				actions[#actions + 1] = { name = "ResetCompatibility", text = "Reset learned compatibility", variant = "ghost", onClick = function()
					local ok, why = connectionActions.resetLearned(record)
					overlay.toast(ok and "Future requests can relearn this connection's parameter and token limits." or tostring(why), ok and "good" or "warn", 4)
				end }
			end
			if not registry.isCline(record) then
				actions[#actions + 1] = {
					name = "ManageProviderKeys", text = "Manage API keys", variant = "secondary",
					onClick = function() M.manageKeys(record, function() panel.select(record.id) end) end,
				}
			end
			if caps.clipboard then
				actions[#actions + 1] = {
					name = "CopyEndpoint",
					text = "Copy endpoint",
					variant = "ghost",
					onClick = function()
						local ok, why = env.require("runtime/clipboard").write(chat.endpointOf(record))
						overlay.toast(ok and "Copied" or why, ok and "good" or "warn", 1.5)
					end,
				}
			end
			R.actions(status, actions, { name = "StatusActions", layoutOrder = 5 })

			-- Model -------------------------------------------------------------
			local modelSection = R.section(detail.instance, {
				name = "Model",
				title = "Model",
				description = communityKey.isApplied(record)
					and "Auto measures available models in the background and prefers a verified tool-capable route below ten seconds. Speed varies with your prompt and shared capacity. Choose a specific model to keep it fixed."
					or "Models come from the endpoint or your manual entries. Fetch the current list if none are known yet.",
				layoutOrder = modelOrder,
			})
			local known = models.list(record)
			R.select(modelSection, {
				name = "ActiveModel",
				label = "Active model",
				searchable = true,
				searchPlaceholder = "Search model IDs...",
				hint = #known == 0 and "Nothing known yet. Fetch the list, or add an id by hand."
					or (traits.badge(record.model, record) and ("Context window " .. traits.badge(record.model, record))
						or "No published context window for this id."),
				options = (function()
					local out = {}
					for _, id in ipairs(known) do out[#out + 1] = { value = id, label = id, free = models.isFree(record, id) } end
					if #out == 0 then
						out[#out + 1] = { value = record.model, label = record.model ~= "" and record.model or "none" }
					end
					return out
				end)(),
				value = record.model ~= "" and record.model or (known[1] or ""),
				width = theme.size.menu,
				onChange = function(value) registry.setModel(record.id, value) end,
			})
			R.actions(modelSection, {
				{
					name = "ManageModels",
					text = #known == 0 and "Fetch or add a model" or "Manage models",
					variant = "secondary",
					onClick = function(handle)
						modelMenu(record, handle.instance, function() panel.select(record.id) end)
					end,
				},
			}, { name = "ModelActions" })

			local modelRows, modelCount, modelEmpty, modelList = {}, nil, nil, nil
			local modelRowHeight = math.max(theme.size.rowSmall, responsive.minTarget(), theme.text.monoSmall.height + theme.space.xs)
			local function modelListHeight(count)
				local visible = math.min(6, count)
				return visible * modelRowHeight + math.max(0, visible - 1) * theme.space.xs + theme.space.xxs * 2
			end
			local function filterModels(text, preservePosition)
				modelQueries[record.id] = tostring(text or "")
				local matches = env.require("runtime/search").compile(text)
				local visible = 0
				for _, entry in ipairs(modelRows) do
					entry.instance.Visible = matches(entry.id) ~= nil
					if entry.instance.Visible then visible = visible + 1 end
				end
				if modelCount then modelCount.Text = string.format("%d of %d models", visible, #known) end
				if modelEmpty then modelEmpty.Visible = visible == 0 end
				if modelList then
					modelList.instance.Visible = visible > 0
					modelList.instance.Size = UDim2.new(1, 0, 0, modelListHeight(visible))
					if preservePosition ~= true then modelList.instance.CanvasPosition = Vector2.new(0, 0) end
				end
			end
			if #known > 8 then
				P.field(modelSection, { name = "SavedModelSearch", placeholder = "Search this provider's models...",
					text = modelQueries[record.id] or "", layoutOrder = 50, onChange = filterModels })
				modelCount = P.text(modelSection, { name = "SavedModelCount", role = "caption", color = theme.color.textTertiary, layoutOrder = 51 })
				modelEmpty = P.text(modelSection, { name = "NoSavedModelsMatch", text = "No matching models. Clear the search or fetch the latest catalog.",
					role = "small", color = theme.color.textTertiary, wrap = true, auto = "Y", visible = false, layoutOrder = 52 })
			end
			modelList = P.scroll(modelSection, {
				name = "SavedModelList", size = UDim2.new(1, 0, 0, modelListHeight(#known)), gap = theme.space.xs,
				padding = { left = theme.space.xxs, right = theme.space.xs, top = theme.space.xxs, bottom = theme.space.xxs }, layoutOrder = 100,
			})
			modelList.instance.Visible = #known > 0
			local own = {}
			for _, id in ipairs(record.models or {}) do own[id] = true end
			for index, id in ipairs(known) do
				local free = models.isFree(record, id)
				local row = P.rowButton(modelList.instance, {
					name = "Model_" .. tostring(index),
					height = modelRowHeight,
					padding = { x = theme.space.sm },
					radius = theme.radius.sm,
					stroke = free, strokeColor = free and P.freeModelOutline() or nil,
					strokeWidth = free and 1 or nil,
					selected = id == record.model,
					layoutOrder = 100 + index,
					onClick = function()
						registry.setModel(record.id, id)
						panel.select(record.id)
					end,
				})
				local slot = P.frame(row.row, {
					size = UDim2.fromOffset(theme.size.icon, theme.size.icon),
					layoutOrder = 1,
				})
				modelRows[#modelRows + 1] = { instance = row.instance, id = id }
				P.statusDot(slot, {
					diameter = theme.size.dot,
					color = id == record.model and theme.color.accent or theme.color.borderStrong,
					anchor = Vector2.new(0.5, 0.5),
					position = UDim2.fromScale(0.5, 0.5),
				})
				row.label(id, 2, id == record.model and theme.color.text or theme.color.textSecondary,
					"monoSmall")
				if not own[id] then
					local mark = P.badge(row.row, { text = "fetched", layoutOrder = 3 })
					mark.LayoutOrder = 3
				end
				if own[id] and #known > 1 then
					local remove = P.iconButton(row.row, {
						name = "RemoveModel",
						icon = "close",
						diameter = theme.size.rowSmall,
						variant = "ghost",
						layoutOrder = 4,
						onClick = function()
							models.remove(record, id)
							panel.select(record.id)
						end,
					})
					remove.instance.LayoutOrder = 4
				end
			end
			if modelCount then filterModels(modelQueries[record.id] or "", true) end
			modelList.instance.CanvasPosition = modelPositions[record.id] or Vector2.new(0, 0)
			modelList.instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
				modelPositions[record.id] = modelList.instance.CanvasPosition
			end)

			-- Behaviour ---------------------------------------------------------
			local behaviour = R.section(detail.instance, {
				name = "Behaviour",
				title = "Behaviour",
				description = "Preferences for this provider. Global settings still apply.",
				layoutOrder = order(),
			})
			R.toggle(behaviour, {
				name = "Enabled",
				label = "Enabled",
				hint = "A disabled provider is skipped by the fallback chain. Disabling the active "
					.. "one leaves it flagged active while requests go elsewhere.",
				value = record.enabled ~= false,
				layoutOrder = 1,
				onChange = function(value)
					record.enabled = value
					registry.save(record, { force = true })
				end,
			})
			R.toggle(behaviour, {
				name = "Stream",
				label = "Streaming responses",
				hint = "Streamed replies carry reasoning text and token counts. Turning this off "
					.. "always takes effect; turning it on only does while Settings has streaming on.",
				value = record.stream ~= false,
				layoutOrder = 2,
				onChange = function(value)
					record.stream = value
					registry.save(record, { force = true })
				end,
			})
			if registry.requiresClaude(record) then
				R.paragraph(behaviour,
					"Claude Code identity is required by AgentRouter and is always sent. It cannot be turned off for this endpoint.",
					{ name = "ClaudeUaRequired", role = "small", color = theme.color.textSecondary, layoutOrder = 3 })
			else
				R.toggle(behaviour, {
					name = "ClaudeUa",
					label = "Send the Claude Code identity",
					hint = "The claude-cli User-Agent and its client headers. Turning this off suppresses "
						.. "the whole set for this endpoint whatever the global switch says, which is the "
						.. "one lever this client has when a CDN in front of an API refuses the request.",
					value = record.claudeUa ~= false,
					layoutOrder = 3,
					onChange = function(value)
						record.claudeUa = value
						registry.save(record, { force = true })
					end,
				})
			end

			-- Transport and the three invisible maps -----------------------------
			local advanced = R.section(detail.instance, {
				name = "Advanced",
				title = "Transport",
				description = "Optional gateway streaming and extra headers, body fields and query parameters. "
					.. "HTTP works without a socket; the provider and host still set request limits.",
				layoutOrder = order(),
			})
			R.field(advanced, {
				name = "SocketUrl",
				label = "Gateway socket URL",
				hint = "Optional, for Chat completions only. Requires a gateway implementing UAI's envelope protocol. "
					.. "Ordinary local servers and OpenAI Responses/Realtime sockets use different protocols. The gateway receives your provider headers.",
				value = record.wsUrl or "",
				placeholder = "wss://your-uai-gateway.example/stream",
				layoutOrder = 1,
				onChange = function(text)
					record.wsUrl = util.trim(text)
					registry.save(record, { force = true })
				end,
			})

			local extras = {}
			for _, group in ipairs({
				{ field = "headers", label = "header" },
				{ field = "params", label = "body field" },
				{ field = "query", label = "query" },
			}) do
				for _, key in ipairs(util.keys(record[group.field] or {}, true)) do
					extras[#extras + 1] = {
						key = group.label .. " " .. tostring(key),
						value = tostring(record[group.field][key]),
					}
				end
			end
			if #extras > 0 then
				R.facts(advanced, extras, { name = "ExtraFacts", layoutOrder = 4 })
			else
				R.paragraph(advanced, "No extra headers, body fields or query parameters.",
					{ layoutOrder = 4 })
			end

			-- Fallback order ----------------------------------------------------
			local list = registry.list()
			if #list > 1 then
				local position = 1
				for index, entry in ipairs(list) do
					if entry.id == record.id then position = index end
				end
				local ordering = R.section(detail.instance, {
					name = "Order",
					title = "Fallback order",
					description = string.format(
						"Position %d of %d. If fallback is enabled and the active provider fails, "
						.. "other enabled providers are tried in this order.", position, #list),
					layoutOrder = order(),
				})
				local moves = {}
				if position > 1 then
					moves[#moves + 1] = {
						name = "MoveUp",
						text = "Move up",
						variant = "secondary",
						onClick = function() registry.reorder(record.id, -1) end,
					}
				end
				if position < #list then
					moves[#moves + 1] = {
						name = "MoveDown",
						text = "Move down",
						variant = "secondary",
						onClick = function() registry.reorder(record.id, 1) end,
					}
				end
				R.actions(ordering, moves, { name = "OrderActions" })
			end

			-- Removal -----------------------------------------------------------
			local danger = R.section(detail.instance, {
				name = "Remove",
				title = "Remove",
				description = "The endpoint and its key are deleted from this device. This cannot "
					.. "be undone.",
				layoutOrder = order(),
			})
			R.actions(danger, {
				{
					name = "RemoveProvider",
					text = "Remove " .. record.label,
					-- The danger variant, which exists for exactly this and which every other
					-- destructive control in the app already uses. This one was a ghost button
					-- sitting between Edit and nothing.
					variant = "danger",
					onClick = function()
						-- Says what happens next. registry.remove silently promotes the first
						-- remaining record when the active one goes, and the old confirmation
						-- did not mention it.
						local successor = nil
						for _, entry in ipairs(registry.list()) do
							if entry.id ~= record.id and not successor then successor = entry end
						end
						local description = "The endpoint and its key are deleted from this device."
						if isActive and successor then
							description = description .. " " .. successor.label
								.. " becomes the active provider."
						elseif isActive then
							description = description .. " No provider will be configured afterwards."
						end
						overlay.confirm({
							title = "Remove " .. record.label .. "?",
							description = description,
							confirmText = "Remove",
							danger = true,
							onConfirm = function()
								local removed, why = registry.remove(record.id)
								if not removed then overlay.toast(why, "warn", 4); return end
								panel.select(successor and successor.id or nil)
							end,
						})
					end,
				},
			}, { name = "DangerActions" })
		end

		-- Wiring ---------------------------------------------------------------

		function panel.select(id)
			if not root.Parent then return end
			local previous = selected
			local position = detail.instance.CanvasPosition
			local list = registry.list()
			if id and registry.get(id) then
				selected = id
			else
				local active = registry.active()
				selected = (active and active.id) or (list[1] and list[1].id) or nil
			end
			if selected ~= previous then selectionRevision = selectionRevision + 1 end
			panel.renderRail()
			panel.renderDetail()
			detail.instance.CanvasPosition = previous == selected and position or Vector2.new(0, 0)
		end

		-- Health arrives on every single completion, and the panel used to rebuild
		-- itself from scratch each time -- header, rail, detail, scroll position, and the
		-- enable switch mid-animation. Only the facts block and the rail dots can change
		-- for a health event, so only those are repainted.
		local function repaintHealth()
			local record = selected and registry.get(selected) or nil
			local active = registry.active()
			for id, entry in pairs(railRows) do
				local candidate = registry.get(id)
				if candidate and entry.dot.Parent then
					entry.dot.BackgroundColor3 = dotFor(candidate, active and active.id == id)
				end
			end
			if record and statusBox and statusBox.Parent then
				local replacement = R.facts(statusBox.Parent, factsFor(record),
					{ name = "StatusFacts", layoutOrder = 1 })
				pcall(function() statusBox:Destroy() end)
				statusBox = replacement
			end
			if record and healthError and healthError.Parent then
				healthError.Text = tostring((record.health or {}).lastError or "")
				healthError.Visible = util.trim(healthError.Text) ~= ""
			end
		end

		panel.select(nil)

		panel.unsubscribe = registry.changed:connect(function(reason)
			if not root.Parent then return end
			if reason == "health" then
				repaintHealth()
			else
				panel.select(selected)
			end
		end)
		local unsubscribeVault = config.changed:connect(function(path)
			if root.Parent and (path == nil or path == "security" or path == "security.vault") then panel.select(selected) end
		end)
		root.Destroying:Connect(function()
			pcall(panel.unsubscribe)
			pcall(unsubscribeLayout)
			pcall(unsubscribeVault)
		end)

		panel.root = root
		panel.scroll = detail
		return panel
	end

	return M
end
