-- Master-password entry and vault actions for the established client UI.
return function(env)
	local config = env.require("runtime/config")
	local util = env.require("runtime/util")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local overlay = env.require("ui/overlay")
	local P = env.require("ui/primitives")
	local dispose = env.require("runtime/dispose")
	local M = {}
	local opened

	-- Roblox has no native password input. Keep its normal editing/paste behavior
	-- and hide its text behind a noninteractive mask until Show is chosen.
	local function passwordField(parent, name, label, order, submit)
		local column = P.column(parent, { name = name .. "Row", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = order })
		local heading = P.row(column, { name = name .. "Heading", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, layoutOrder = 1 })
		P.text(heading, { text = label, role = "small", auto = "Y", wrap = true, flex = "Fill",
			size = UDim2.fromOffset(0, theme.text.small.height), layoutOrder = 1 })
		local field = P.field(column, { name = name, placeholder = "", layoutOrder = 2, onSubmit = submit })
		local box, shown = field.instance, false
		local cursor, selection = 1, -1
		local function rememberSelection()
			if box.CursorPosition >= 1 then cursor, selection = box.CursorPosition, box.SelectionStart end
		end
		box:GetPropertyChangedSignal("CursorPosition"):Connect(rememberSelection)
		box:GetPropertyChangedSignal("SelectionStart"):Connect(rememberSelection)
		box.TextTransparency = 1
		box.TextStrokeTransparency = 1
		local mask = P.text(field.shell, { name = name .. "Mask", text = "Enter your password", role = "body",
			size = UDim2.new(1, -theme.space.md * 2, 1, 0), position = UDim2.fromOffset(theme.space.md, 0),
			color = theme.color.textTertiary, zIndex = box.ZIndex + 1, truncate = true })
		mask.Active, mask.Selectable = false, false
		local function updateMask()
			local text = box.Text
			mask.Text = text == "" and "Enter your password" or string.rep("*", math.min(#text, 24))
			mask.TextColor3 = text == "" and theme.color.textTertiary or theme.color.text
			mask.Visible = not shown
			box.TextTransparency = shown and 0 or 1
		end
		local show = P.button(heading, { name = name .. "Show", text = "Show", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function(button)
				shown = not shown; button.setText(shown and "Hide" or "Show"); updateMask()
				local savedCursor, savedSelection = cursor, selection
				field.focus()
				box.CursorPosition = math.min(savedCursor, #box.Text + 1)
				box.SelectionStart = math.min(savedSelection, #box.Text + 1)
			end })
		local stopFocus = dispose.connection(env.uis.WindowFocusReleased:Connect(function()
			shown = false; show.setText("Show"); updateMask()
		end), "password reveal focus")
		box:GetPropertyChangedSignal("Text"):Connect(updateMask)
		local handle = { instance = box, focus = field.focus, get = field.get }
		function handle.clear()
			shown, cursor, selection = false, 1, -1; field.clear(); show.setText("Show"); updateMask()
		end
		function handle.setEnabled(value)
			field.setEnabled(value)
			show.setEnabled(value)
		end
		column.Destroying:Connect(function() stopFocus(); box.Text = ""; mask.Text = "" end)
		return handle
	end

	function M.open(requestedMode, props)
		props = props or {}
		local initial = config.vaultStatus()
		local required = requestedMode == "required" or (initial.required == true and initial.ready ~= true)
		local importing = not required and requestedMode == "import" and type(props.submit) == "function"
		if opened and not opened.closed then
			if not required or opened.required then return opened end
			opened.close()
		end
		local fields, actions = {}, {}
		local busy, cancelled, released = false, false, false
		local modal, unsubscribe, status, render, currentMode, confirmationModal
		local progressPanel, progressLabel, progressCancel, progressStop, progressValue
		local function clearProgress()
			if progressStop then progressStop(); progressStop = nil end
			if progressPanel then progressPanel:Destroy() end
			progressPanel, progressLabel, progressCancel, progressValue = nil, nil, nil, nil
		end
		local function clearFields()
			for _, field in ipairs(fields) do field.clear() end
		end
		local function release()
			if released then return end
			released, cancelled = true, true
			clearFields()
			clearProgress()
			if confirmationModal and not confirmationModal.closed then confirmationModal.close() end
			if unsubscribe then unsubscribe(); unsubscribe = nil end
			if opened == modal then opened = nil end
			if required and props.onClose then task.defer(props.onClose) end
		end
		modal = overlay.modal({ title = "Credential vault", dismissable = not required, onClose = release })
		if not modal then return end
		opened = modal
		modal.required = required
		modal.card.Name = "CredentialVault"
		modal.scrim.Destroying:Connect(release)
		local function alive() return not released and not modal.closed end
		local function isCancelled() return cancelled or not alive() or (props.cancelled and props.cancelled()) == true end
		local function revealStatus()
			local expected = status
			task.defer(function()
				if not alive() or modal.suspended or status ~= expected then return end
				modal.relayout()
				task.wait()
				if not alive() or modal.suspended or status ~= expected then return end
				local viewport = modal.scroll.instance
				local height = viewport.AbsoluteWindowSize.Y
				if height <= 0 then height = viewport.AbsoluteSize.Y end
				if height <= 0 then return end
				local top, size = expected.AbsolutePosition.Y, expected.AbsoluteSize.Y
				local inset = math.min(theme.space.xs, math.max(0, (height - size) / 2))
				local visibleTop = viewport.AbsolutePosition.Y + inset
				local visibleBottom = viewport.AbsolutePosition.Y + height - inset
				local delta = 0
				if size >= height or top < visibleTop then delta = top - visibleTop
				elseif top + size > visibleBottom then delta = top + size - visibleBottom end
				local maximum = math.max(0, viewport.AbsoluteCanvasSize.Y - height)
				local nextY = util.clamp(viewport.CanvasPosition.Y + delta, 0, maximum)
				viewport.CanvasPosition = Vector2.new(viewport.CanvasPosition.X, nextY)
			end)
		end
		local function fail(message)
			if not alive() then return end
			status.Text, status.TextColor3 = tostring(message), theme.color.warn
			revealStatus()
		end
		local function cancelOperation()
			if not busy and not required then modal.close(); return end
			cancelled = true; clearFields()
			if progressCancel then progressCancel.setEnabled(false) end
			fail(busy and "Cancelling credential operation..." or currentMode == "setup"
				and "Choose a master password or explicitly continue without encryption. Choose Exit to leave UAI."
				or "A master password is required to continue. Choose Exit to leave UAI.")
		end
		local function exitClient()
			if type(env.exitClient) ~= "function" then fail("UAI cannot exit until startup has finished. Try again."); return end
			local called, ok, err = pcall(env.exitClient)
			local message = not called and "Could not exit UAI. Try again."
				or not ok and (err or "Finish or cancel credential storage before exiting UAI.")
			if message then fail(message); overlay.toast(message, "warn", 4) end
		end
		local function showProgress()
			clearProgress()
			local titles = { setup = "Encrypting API keys", unlock = "Decrypting API keys",
				change = "Changing password", import = "Decrypting config" }
			local title = titles[currentMode]
			local height = math.max(theme.size.controlSmall, responsive.minTarget(), theme.text.bodyStrong.height)
			local numberWidth = math.ceil(P.measureText("100%", { role = "bodyStrong" }).X)
			local cancelWidth = math.max(responsive.minTarget(), math.ceil(P.measureText("Cancel", { role = "small" }).X) + theme.space.md * 2)
			local exitWidth = math.max(responsive.minTarget(), math.ceil(P.measureText("Exit", { role = "small" }).X) + theme.space.md * 2)
			local wanted = numberWidth + cancelWidth + theme.space.sm + theme.space.md * 2
			if required then wanted = wanted + exitWidth + theme.space.sm end
			wanted = math.max(wanted, math.ceil(P.measureText(title, { role = "small" }).X) + theme.space.md * 2)
			local panelHeight = height + theme.text.small.height + theme.space.xs * 3
			progressPanel = P.column(overlay.layer, { name = "VaultProgress", auto = "Y",
				size = UDim2.fromOffset(wanted, panelHeight), anchor = Vector2.new(1, 1),
				bg = theme.color.surfaceRaised, radius = theme.radius.lg, stroke = true, strokeColor = theme.color.border,
				padding = { x = theme.space.md, y = theme.space.xs }, gap = theme.space.xs, zIndex = theme.z.modal + 1 })
			progressPanel.Active = true
			P.text(progressPanel, { name = "VaultProgressTitle", text = title, role = "small", color = theme.color.textSecondary,
				auto = "Y", wrap = true, layoutOrder = 1 })
			local controls = P.row(progressPanel, { name = "VaultProgressControls", size = UDim2.new(1, 0, 0, height),
				auto = "Y", wrap = true, gap = theme.space.sm, layoutOrder = 2 })
			progressLabel = P.text(controls, { name = "VaultProgressPercent", text = "0%", role = "bodyStrong",
				size = UDim2.fromOffset(numberWidth, height), layoutOrder = 1 })
			progressValue = 0
			progressCancel = P.button(controls, { name = "VaultProgressCancel", text = "Cancel", size = "sm", variant = "ghost",
				width = cancelWidth, layoutOrder = 2, onClick = cancelOperation })
			if required then
				P.button(controls, { name = "VaultProgressExit", text = "Exit", size = "sm", variant = "ghost",
					width = exitWidth, layoutOrder = 3, onClick = exitClient })
			end
			local function positionProgress()
				if not progressPanel or not progressPanel.Parent then return end
				local bounds = responsive.usableRect(overlay.layer, theme.space.md)
				progressPanel.Size = UDim2.fromOffset(math.min(wanted, bounds.width), panelHeight)
				progressPanel.Position = UDim2.fromOffset(bounds.x + bounds.width, bounds.y + bounds.height)
			end
			progressStop = responsive.changed:connect(positionProgress)
			positionProgress()
			modal.setSuspended(true)
		end
		local function resumeEntry()
			clearProgress()
			modal.setSuspended(false)
		end
		local function setBusy(value)
			busy = value
			modal.operationPending = value
			for _, field in ipairs(fields) do field.setEnabled(not value) end
			for _, action in ipairs(actions) do action.setEnabled(not value) end
		end
		local function run(method, password, working, success, successTone)
			if busy or not alive() then return end
			setBusy(true)
			cancelled = false
			clearFields()
			status.Text, status.TextColor3 = working, theme.color.textSecondary
			if password ~= nil then showProgress() else revealStatus() end
			task.spawn(function()
				local options = {
					cancelled = isCancelled,
					progress = function(done, total)
						if isCancelled() then return false end
						local fraction = tonumber(total) and total > 0 and (tonumber(done) or 0) / total or 0
						local percent = math.floor(util.clamp(fraction, 0, 1) * 100)
						if progressLabel and progressValue ~= percent then
							progressValue = percent; progressLabel.Text = tostring(percent) .. "%"
						end
						return true
					end,
				}
				local called, ok, err
				if password ~= nil then called, ok, err = pcall(method, password, options)
				else called, ok, err = pcall(method, options) end
				password = nil
				if not alive() then return end
				-- An import belongs to the exact source copy that requested it. A
				-- changed source invalidates this entry instead of offering a retry
				-- against stale data, even if its decryption has just completed.
				if props.cancelled and props.cancelled() == true then
					release(); modal.close(true); return
				end
				-- A verified write that crossed its commit boundary can finish after
				-- Cancel. The runtime's successful result is authoritative then.
				if isCancelled() and not (called and ok) then
					setBusy(false); cancelled = false; resumeEntry(); render(currentMode)
					fail(required and currentMode == "setup" and "Operation cancelled. Choose a master password or explicitly continue without encryption."
						or required and "Operation cancelled. A master password is required to continue." or "Operation cancelled. Enter the password to try again.")
					return
				end
				setBusy(false)
				if not called then resumeEntry(); fail("Could not complete the vault operation. Try again.")
				elseif not ok then resumeEntry(); fail(err == "Cancelled" and "Operation cancelled." or err or "Could not update the vault.")
				else
					local vault = config.vaultStatus()
					if required and vault.ready ~= true then
						resumeEntry(); render()
						if vault.enabled then fail("A new execution requires your master password again.")
						elseif success then overlay.toast(success, successTone or "good", 4) end
					else
						release(); modal.close(true)
						if success then overlay.toast(success, successTone or "good", 4) end
					end
					if importing and props.onSuccess then pcall(props.onSuccess, err) end
				end
			end)
		end
		local function submit()
			if busy or not alive() or #fields == 0 then return end
			local password = fields[1].get()
			local valid, why = env.require("runtime/credential_vault").passwordValid(password, currentMode ~= "unlock" and currentMode ~= "import")
			if not valid then fail(why); return end
			if currentMode ~= "unlock" and currentMode ~= "import" then
				if password ~= fields[2].get() then fail("The passwords do not match."); return end
			end
			if currentMode == "import" then
				run(props.submit, password, "Decrypting configuration for review...")
			elseif currentMode == "setup" then
				run(config.enableVault, password, "Protecting saved credentials...", "Credential vault enabled and unlocked for this run")
			elseif currentMode == "change" then
				run(config.changeVaultPassword, password, "Changing master password...", "Master password changed")
			else run(config.unlockVault, password, "Unlocking saved credentials...", "Credential vault unlocked for this run") end
		end
		local function action(parent, props)
			local button = P.button(parent, props); actions[#actions + 1] = button; return button
		end
		render = function(mode)
			if not alive() or busy then return end
			local vault = config.vaultStatus()
			currentMode = importing and "import" or not vault.enabled and "setup"
				or (vault.locked or vault.ready ~= true) and "unlock" or mode == "change" and "change" or "manage"
			clearFields(); fields, actions = {}, {}
			for _, parent in ipairs({ modal.content, modal.footer }) do
				for _, child in ipairs(parent:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			end
			local headings = { setup = "Set a master password", unlock = "Unlock saved credentials", change = "Choose a new master password", manage = "Unlocked for this run", import = "Unlock a configuration copy" }
			local descriptions = {
				setup = "Your existing keys and key-pool settings carry over after the encrypted save is verified. You will need this password each time UAI starts.",
				unlock = "Your saved provider credentials are encrypted. Enter your master password to open UAI. Cancel stops password derivation and leaves the vault locked.",
				change = "Choose a new passphrase with several unrelated words. It will protect your saved credentials on the next run.",
				manage = "Saved provider credentials are encrypted. Lock the vault to remove them from this client's live configuration. Other scripts can still intercept credentials while you use them.",
				import = "Enter the master password used to encrypt this copy. You can review its settings before applying them. This device keeps its storage choice and any vault password.",
			}
			if currentMode ~= "manage" and currentMode ~= "setup" then
				descriptions[currentMode] = descriptions[currentMode] .. " Progress and Cancel appear in the corner while the password is checked."
			end
			local intro = P.column(modal.content, { name = "VaultIntro", auto = "Y", size = UDim2.new(1, 0, 0, 0),
				gap = theme.space.xs, layoutOrder = 1 })
			P.text(intro, { name = "VaultHeading", text = headings[currentMode], role = "heading", auto = "Y", wrap = true, layoutOrder = 1 })
			P.text(intro, { name = "VaultDescription", text = descriptions[currentMode], role = "small", auto = "Y", wrap = true,
				color = theme.color.textSecondary, layoutOrder = 2 })
			if currentMode == "setup" or currentMode == "change" then
				local warning = P.card(modal.content, { name = "VaultRecoveryWarning", bg = theme.color.warnSurface,
					strokeColor = theme.color.warn, padding = theme.space.md, gap = theme.space.sm, layoutOrder = 2 })
				P.text(warning, { name = "VaultRecoveryHeading", text = "NO PASSWORD RECOVERY", role = "label",
					color = theme.color.warn, auto = "Y", wrap = true, layoutOrder = 1 })
				P.text(warning, { name = "VaultRecoveryConsequences", role = "small", auto = "Y", wrap = true, layoutOrder = 2,
					text = "Project UAI cannot recover your password. If you forget it, you cannot unlock your saved API keys. Resetting the vault permanently removes every API key saved in this vault from UAI. You must enter them again." })
				P.text(warning, { name = "VaultRecoveryAdvice", role = "small", auto = "Y", wrap = true, layoutOrder = 3,
					text = "Keep this password safe and back up your provider keys. Reset does not revoke keys at your providers or erase existing backups.", color = theme.color.textSecondary })
			end
			if currentMode ~= "manage" then
				local form = P.column(modal.content, { name = "VaultPasswordForm", auto = "Y", size = UDim2.new(1, 0, 0, 0),
					gap = theme.space.md, layoutOrder = 3 })
				fields[1] = passwordField(form, "VaultPassword", currentMode == "change" and "New master password" or "Master password", 1,
					function() if fields[2] then fields[2].focus() else submit() end end)
				if currentMode ~= "unlock" and currentMode ~= "import" then
					fields[2] = passwordField(form, "VaultConfirmPassword", "Confirm master password", 2, submit)
					P.text(form, { name = "VaultPasswordHint", text = "Use at least 12 characters. Several unrelated words make a strong passphrase.",
						role = "small", color = theme.color.textSecondary, auto = "Y", wrap = true, layoutOrder = 3 })
				end
				if currentMode == "setup" then
					P.text(modal.content, { name = "VaultDerivationNote", text = "Progress and Cancel appear in the corner while encryption is prepared.",
						role = "small", color = theme.color.textTertiary, auto = "Y", wrap = true, layoutOrder = 4 })
				end
				if currentMode == "unlock" then
					action(modal.content, { name = "VaultReset", text = "Forgot password? Remove saved credentials", variant = "ghost", fill = true, layoutOrder = 5,
						onClick = function()
							local confirmation = overlay.confirm({ title = "Remove saved credentials?", confirmText = "Remove saved credentials", danger = true,
								description = "This permanently removes every API key and credential saved in this vault from UAI's active configuration. You must choose storage protection and enter your keys again. Your other settings remain. Keys at your providers and existing backups are not revoked or erased. There is no undo.",
								onConfirm = function() if alive() then run(config.resetVault, nil, "Removing saved credentials...", "Saved vault credentials removed") end end })
							confirmationModal = confirmation
							if confirmation then confirmation.card.Name = "ResetCredentialVault" end
						end })
				end
			else
				action(modal.content, { name = "VaultChangePassword", text = "Change master password", fill = true, layoutOrder = 3,
					onClick = function() render("change") end })
				action(modal.content, { name = "VaultLock", text = "Lock now", fill = true, layoutOrder = 4,
					onClick = function() run(config.lockVault, nil, "Locking credentials...", "Credential vault locked") end })
			end
			if currentMode == "setup" or currentMode == "manage" then
				local choice = P.column(modal.content, { name = "VaultUnprotectedChoice", auto = "Y", size = UDim2.new(1, 0, 0, 0),
					gap = theme.space.xs, layoutOrder = 5 })
				P.text(choice, { name = "VaultUnprotectedWarning", text = "Without encryption, saved API keys are unprotected. Anyone who can read UAI's files can recover them. Your existing keys and key-pool settings will carry over.",
					role = "small", color = theme.color.danger, auto = "Y", wrap = true, layoutOrder = 1 })
				action(choice, { name = "VaultContinueUnprotected", text = "Continue without encryption", variant = "danger", fill = true, layoutOrder = 2,
					onClick = function()
						run(config.continueWithoutEncryption, nil, "Saving storage choice...",
							"Continuing without encryption. Saved API keys are unprotected.", "warn")
					end })
			end
			status = P.text(modal.content, { name = "VaultOperationStatus", text = vault.busy and "Another vault operation is in progress." or vault.error or "",
				role = "small", color = theme.color.warn, auto = "Y", wrap = true, layoutOrder = 6 })
			P.button(modal.footer, { name = "VaultCancel", text = currentMode == "manage" and "Done" or "Cancel", variant = "ghost", size = "sm", layoutOrder = 1,
				onClick = cancelOperation })
			if required then
				P.button(modal.footer, { name = "VaultExit", text = "Exit", variant = "ghost", size = "sm", layoutOrder = 2,
					onClick = exitClient })
			end
			if currentMode ~= "manage" then
				action(modal.footer, { name = "VaultSubmit", text = currentMode == "setup" and "Set password" or currentMode == "change" and "Change password" or currentMode == "import" and "Unlock for review" or "Unlock",
					variant = "primary", size = "sm", layoutOrder = 3, onClick = submit })
			end
			if vault.busy then
				for _, field in ipairs(fields) do field.setEnabled(false) end
				for _, button in ipairs(actions) do button.setEnabled(false) end
			end
			modal.relayout()
		end
		unsubscribe = config.changed:connect(function(path)
			if path == nil or path == "security" or path == "security.vault" then render(currentMode) end
		end)
		render(requestedMode)
		return modal
	end
	return M
end
