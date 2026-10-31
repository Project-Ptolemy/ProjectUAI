-- A provider's named credentials and request policy, edited as one local draft.
-- The provider editor owns persistence; this surface applies only key fields.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local fsx = env.require("runtime/fsx")
	local keys = env.require("runtime/provider_keys")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local overlay = env.require("ui/overlay")
	local search = env.require("runtime/search")
	local M = {}

	local function label(entry, index)
		return entry.name ~= "" and entry.name or ("API key " .. index)
	end

	local function snapshot(record)
		local names, paused = {}, {}
		for index, entry in ipairs(keys.entries(record)) do
			names[index] = entry.name
			paused[index] = entry.paused == true
		end
		-- Retain legacy separators until credentials actually change. Naming a key
		-- does not change authentication or invalidate a provider's model cache.
		return { apiKey = tostring(record.apiKey or ""), keyNames = names, keyPaused = paused,
			keyIds = util.deepCopy(record.keyIds),
			keyMode = keys.mode(record), selectedKey = keys.selected(record) }
	end

	function M.open(props)
		props = props or {}
		if config.vaultStatus().locked then return env.require("ui/credentialvault").open("unlock") end
		local record = props.record or {}
		keys.ensureIds(record)
		local draft = snapshot(record)
		draft.id = record.id
		local prompt, modal, unsubscribeUsage, unsubscribeStorage
		local function cleanup()
			for name in pairs(draft) do draft[name] = nil end
			if unsubscribeUsage then unsubscribeUsage(); unsubscribeUsage = nil end
			if unsubscribeStorage then unsubscribeStorage(); unsubscribeStorage = nil end
			if prompt and not prompt.closed then prompt.close() end
			prompt = nil
			if props.onClose then props.onClose() end
		end
		modal = overlay.modal({ title = "API keys",
			description = tostring(record.label or "Provider") .. ". Name your keys and choose how requests use them.",
			width = theme.size.modalWide, onClose = cleanup })
		if not modal then return nil end
		modal.card.Name = "APIKeyManager"
		local form = P.column(modal.content, { name = "KeyManagerContent", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.md, layoutOrder = 1 })
		local storage = P.card(form, { name = "KeyStorageNotice", padding = theme.space.md, gap = theme.space.xs, layoutOrder = 0 })
		local storageText = P.text(storage, { name = "KeyStorageSummary", text = "", role = "small", wrap = true,
			auto = "Y", layoutOrder = 1 })
		P.text(storage, { text = "Change this in Settings / Privacy. Other scripts sharing the executor can still intercept keys while they are in use.",
			role = "caption", color = theme.color.textTertiary, wrap = true, auto = "Y", layoutOrder = 2 })
		if record.credentialsOmitted == true then
			P.text(storage, { name = "KeyRestorationRequired",
				text = "Saved credentials were omitted. After applying keys, open Edit connection to review custom authentication and save the full connection before sending requests.",
				role = "small", color = theme.color.warn, wrap = true, auto = "Y", layoutOrder = 3 })
		end
		local function refreshStorage()
			if modal.closed then return end
			local vault = config.vaultStatus()
			if vault.locked then modal.close(); return end
			local remember = fsx.enabled and config.get("security.rememberCredentials", true) == true
			local unverified = type(config.storageError) == "string" and config.storageError ~= ""
			storageText.Text = unverified and "Saved credential storage could not be verified. An earlier plaintext copy may remain. Keep this session open to retain your keys."
				or not fsx.enabled and "Filesystem access is unavailable. These credentials stay in this run; previously saved files cannot be checked or removed."
				or vault.enabled and "These keys and custom provider credentials are encrypted in UAI/config.json. The credential vault is unlocked for this run."
				or remember and "These keys and custom provider credentials are remembered as byte-encoded data in UAI/config.json. Other scripts can decode them; encoding is not encryption."
				or "These keys and custom provider credentials are session-only. Apply keeps them usable now; enter them again after restarting."
			storageText.TextColor3 = (unverified or (remember and not vault.enabled)) and theme.color.warn or theme.color.textSecondary
		end
		refreshStorage()
		unsubscribeStorage = config.changed:connect(function(path)
			if path == nil or path == "security" or path == "security.rememberCredentials" or path == "security.vault" then refreshStorage() end
		end)
		local routing = P.card(form, { name = "KeyRouting", padding = theme.space.md, gap = theme.space.sm, layoutOrder = 1 })
		P.text(routing, { text = "How to use your keys", role = "label", wrap = true, auto = "Y", layoutOrder = 1 })
		local modeControl, refresh
		local notice = P.text(form, { name = "KeyManagerNotice", text = "", role = "small", wrap = true,
			auto = "Y", color = theme.color.warn, layoutOrder = 2 })
		notice.Visible = false
		local function status(text)
			notice.Text = text or ""
			notice.Visible = notice.Text ~= ""
		end
		modeControl = C.segmented(routing, { name = "KeyMode", value = keys.mode(draft), layoutOrder = 2,
			options = { { value = "rotate", label = "Rotate keys" }, { value = "single", label = "Use one key" } },
			onChange = function(value)
				if modal.closed then return end
				local selected = keys.selected(draft)
				if value == "single" and keys.paused(draft, selected) then
					for index, entry in ipairs(keys.entries(draft)) do
						if not entry.paused then selected = index; break end
					end
				end
				local ok, why = keys.setMode(draft, value, value == "single" and selected or nil)
				status(ok and "" or why)
				refresh()
			end })
		local modeHelp = P.text(routing, { name = "KeyModeHelp", text = "", role = "small",
			color = theme.color.textSecondary, wrap = true, auto = "Y", layoutOrder = 3 })
		P.text(routing, { text = "Rotate keys only takes turns between existing keys. Replace keys at the provider and revoke the old ones to rotate credentials securely. Revoke immediately if a key is stolen.",
			role = "caption", color = theme.color.textTertiary, wrap = true, auto = "Y", layoutOrder = 4 })
		local listHeader = P.row(form, { name = "KeyListHeader", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", wrap = true, gap = theme.space.sm, alignY = "Center", layoutOrder = 3 })
		local count = P.text(listHeader, { name = "KeyCount", text = "", role = "label",
			size = UDim2.fromOffset(0, theme.text.label.height), auto = "X", layoutOrder = 1 })
		P.spacer(listHeader, { grow = true, size = UDim2.fromOffset(0, 1), layoutOrder = 2 })
		local keyFilter, filterRows, cardRows = "", nil, {}
		P.field(form, { name = "KeyFilter", placeholder = "Search key names or active / paused...", layoutOrder = 4,
			onChange = function(text) keyFilter = text; if filterRows then filterRows() end end })
		local entries = P.column(form, { name = "APIKeyEntries", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.sm, layoutOrder = 5 })
		local noMatch = P.text(form, { name = "NoKeyMatch", text = "No matching key names. Clear the search to see all keys.", role = "small",
			wrap = true, auto = "Y", color = theme.color.textTertiary, layoutOrder = 5 })
		noMatch.Visible = false
		filterRows = function()
			local matches, visible = search.compile(keyFilter), 0
			for _, entry in ipairs(cardRows) do
				entry.card.Visible = matches(entry.name, entry.state) ~= nil
				if entry.card.Visible then visible = visible + 1 end
			end
			local summary = keys.summary(draft)
			count.Text = (visible < #cardRows and (visible .. " of ") or "") .. util.pluralise(summary.total, "key")
				.. (summary.active < summary.total and (" / " .. summary.active .. " active") or "")
			noMatch.Visible = #cardRows > 0 and visible == 0
		end
		local usageNodes = {}
		local function refreshUsage()
			if modal.closed then return end
			for index, node in pairs(usageNodes) do
				local used = sessions.keyUsage(draft, index)
				node.Text = util.formatNumber(used.requests) .. (used.requests == 1 and " request" or " requests")
					.. "\n" .. (used.estimated and "About " or "") .. util.formatNumber(used.tokensIn)
					.. " input / " .. util.formatNumber(used.tokensOut) .. " output tokens"
			end
		end
		local function locate(secret)
			for index, entry in ipairs(keys.entries(draft)) do
				if entry.key == secret then return index end
			end
		end
		local function edit(options, callback)
			if modal.closed then return end
			if prompt and not prompt.closed then prompt.close() end
			options.onConfirm = function(value)
				prompt = nil
				if modal.closed then return end
				callback(value)
			end
			prompt = overlay.prompt(options)
		end
		P.button(listHeader, { name = "AddKey", text = "Add API key", variant = "secondary", size = "sm", layoutOrder = 3,
			onClick = function()
				edit({ title = "Add API key", description = "Paste one key per line to add several. Existing keys and names stay in place.",
					placeholder = "Paste API key", multiline = true, confirmText = "Save key" }, function(value)
					local ok, why = keys.add(draft, value)
					status(ok and "" or why)
					refresh()
				end)
			end })
		P.text(form, { name = "KeyDraftHint", text = props.applyHint or "Apply changes returns these keys to provider setup. Save the provider to use them with the storage preference shown above.",
			role = "caption", color = theme.color.textTertiary, wrap = true, auto = "Y", layoutOrder = 6 })
		P.text(form, { name = "KeyUsageHint", text = "Usage is recorded on this device from this update. Requests include retries; estimated tokens are marked.",
			role = "caption", color = theme.color.textTertiary, wrap = true, auto = "Y", layoutOrder = 7 })
		refresh = function()
			if modal.closed then return end
			local pool, mode, selected = keys.entries(draft), keys.mode(draft), keys.selected(draft)
			modeControl.set(mode)
			local active = 0
			for _, entry in ipairs(pool) do if not entry.paused then active = active + 1 end end
			count.Text = util.pluralise(#pool, "key") .. (active < #pool and (" / " .. active .. " active") or "")
			if mode == "single" then
				modeHelp.Text = pool[selected] and pool[selected].paused and "The selected key is paused. Resume it or choose another active key."
					or pool[selected] and ("Only " .. label(pool[selected], selected)
					.. " will be used. Other keys will not be tried.")
					or "Choose a key below, or turn on rotation. No key is selected for requests."
			else
				modeHelp.Text = #pool > 0 and active == 0 and "All keys are paused. Resume a key to send requests."
					or "New requests take turns using active keys. Paused keys stay in this pool until you resume or remove them."
			end
			usageNodes, cardRows = {}, {}
			for _, child in ipairs(entries:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			if #pool == 0 then
				local empty = P.card(entries, { name = "NoAPIKeys", padding = theme.space.md, gap = theme.space.xs })
				P.text(empty, { text = "No API keys yet", role = "label", auto = "Y", wrap = true, layoutOrder = 1 })
				P.text(empty, { text = "Add a key to get started. You can add more whenever you need them.", role = "small",
					color = theme.color.textSecondary, auto = "Y", wrap = true, layoutOrder = 2 })
			end
			for index, entry in ipairs(pool) do
				local slot, secret, name, paused = index, entry.key, entry.name, entry.paused
				local chosen = mode == "single" and selected == slot
				local card = P.card(entries, { name = "APIKey_" .. slot, padding = theme.space.md, gap = theme.space.sm,
					bg = chosen and theme.color.accentSurface or theme.color.surfaceRaised,
					strokeColor = chosen and theme.color.accent or theme.color.borderSubtle, layoutOrder = slot })
				cardRows[#cardRows + 1] = { card = card, name = label(entry, slot), state = paused and "paused" or "active" }
				local head = P.row(card, { size = UDim2.new(1, 0, 0, 0), auto = "Y", gap = theme.space.sm, layoutOrder = 1 })
				local identity = P.column(head, { size = UDim2.new(0, 0, 0, 0), auto = "Y", flex = "Fill",
					gap = theme.space.xxs, layoutOrder = 1 })
				P.text(identity, { name = "APIKeyLabel_" .. slot, text = util.ellipsis(label(entry, slot), 120),
					role = "label", wrap = true, auto = "Y", layoutOrder = 1 })
				if name ~= "" or paused then
					P.text(identity, { name = "APIKeyState_" .. slot,
						text = "API key " .. slot .. (paused and " / Paused" or ""), role = "caption", color = theme.color.textTertiary,
						wrap = true, auto = "Y", layoutOrder = 2 })
				end
				P.text(head, { name = "APIKeyMask_" .. slot,
					text = #secret <= 4 and "set" or (string.rep("\226\128\162", 4) .. " " .. secret:sub(-4)),
					role = "monoSmall", color = theme.color.textSecondary, auto = "XY", size = UDim2.fromOffset(0, 0), layoutOrder = 2 })
				usageNodes[slot] = P.text(card, { name = "APIKeyUsage_" .. slot, text = "", role = "caption",
					color = theme.color.textSecondary, wrap = true, auto = "Y", layoutOrder = 2 })
				local actions = P.row(card, { name = "APIKeyActions_" .. slot, size = UDim2.new(1, 0, 0, 0),
					auto = "Y", wrap = true, gap = theme.space.xs, layoutOrder = 3 })
				local use = P.button(actions, { name = "UseKey_" .. slot, text = chosen and "Selected" or "Use this key",
					variant = "secondary", size = "sm", layoutOrder = 1, enabled = not chosen and not paused,
					onClick = function()
						if modal.closed then return end
						local position = locate(secret)
						if not position then return end
						local ok, why = keys.setMode(draft, "single", position)
						status(ok and "" or why); refresh()
					end })
				use.instance.Visible = mode == "single"
				P.button(actions, { name = "PauseKey_" .. slot, text = paused and "Resume" or "Pause",
					variant = "secondary", size = "sm", layoutOrder = 2,
					onClick = function()
						if modal.closed then return end
						local position = locate(secret)
						if not position then return end
						local ok, why = keys.setPaused(draft, position, not keys.paused(draft, position))
						status(ok and "" or why); refresh()
					end })
				P.button(actions, { name = "RenameKey_" .. slot, text = "Rename", variant = "ghost", size = "sm", layoutOrder = 3,
					onClick = function()
						edit({ title = "Name this key", description = "Choose a name you recognize. Leave blank to use its number.",
							value = name, placeholder = "API key " .. slot, confirmText = "Save name" }, function(value)
							local position = locate(secret)
							if not position then return end
							local ok, why = keys.rename(draft, position, value)
							status(ok and "" or why); refresh()
						end)
					end })
				P.button(actions, { name = "ReplaceKey_" .. slot, text = "Replace", variant = "ghost", size = "sm", layoutOrder = 4,
					onClick = function()
						edit({ title = "Replace API key", description = "Paste a replacement for " .. label(entry, slot)
							.. ". Its name and the other keys stay in place.", placeholder = "Paste replacement key", confirmText = "Save key" }, function(value)
							local position = locate(secret)
							if not position or util.trim(value) == "" then return end
							local ok, why = keys.replace(draft, position, value)
							status(ok and "" or why); refresh()
						end)
					end })
				P.button(actions, { name = "RemoveKey_" .. slot, text = "Remove", variant = "ghost", size = "sm", layoutOrder = 5,
					onClick = function()
						if modal.closed then return end
						local position = locate(secret)
						if not position then return end
						local wasSelected = keys.mode(draft) == "single" and keys.selected(draft) == position
						local ok, why = keys.remove(draft, position)
						status(ok and (wasSelected and "The selected key was removed. Rotation is on; choose another key to use just one." or "") or why)
						refresh()
					end })
			end
			refreshUsage()
			filterRows()
		end
		P.button(modal.footer, { name = "CancelKeys", text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "ApplyKeys", text = "Apply changes", variant = "primary", size = "sm", layoutOrder = 2,
			onClick = function()
				if modal.closed then return end
				local candidate = snapshot(draft)
				local valid, why = keys.validate(candidate)
				if not valid then status(why); return end
				if props.onApply then
					local ok, accepted = pcall(props.onApply, candidate)
					if modal.closed then return end
					if not ok or accepted == false then
						status("Changes could not be applied. Review the provider and try again.")
						return
					end
				end
				modal.close()
			end })
		refresh()
		unsubscribeUsage = sessions.usageChanged:connect(refreshUsage)
		return modal
	end

	return M
end
