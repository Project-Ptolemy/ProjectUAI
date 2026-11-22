-- Real vault controls with cooperative fake derivation; cryptography is covered
-- by the runtime suites. Passwords, provider keys and files here are synthetic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Credential vault UI")
local case, check = suite.case, suite.check

local function fixture(width, enabled, locked)
	local f = F.ui(width or 390, 700)
	f.config, f.util = f.env.require("runtime/config"), f.env.require("runtime/util")
	f.vault, f.calls, f.password = { enabled = enabled == true, locked = locked == true, busy = false }, {}, "fixture master phrase"
	f.vault.required = true
	f.vault.protection = enabled and "password" or "undecided"
	f.config.vaultStatus = function()
		local status = f.util.copy(f.vault)
		status.ready = status.enabled and not status.locked and not status.challengePending or status.protection == "unprotected"
		return status
	end
	local function changed() f.config.changed:fire("security.vault") end
	local function derive(name, password, options)
		f.calls[#f.calls + 1] = { name = name, password = password }
		f.vault.busy = true; changed()
		for step = 1, 4 do
			if options.cancelled() or options.progress(step, 4) == false then
				f.vault.busy = false; changed(); return false, "Cancelled"
			end
			f.h.sandbox.task.wait(0.1)
		end
		f.vault.busy = false
		if options.cancelled() then changed(); return false, "Cancelled" end
		if f.nextError then local err = f.nextError; f.nextError = nil; changed(); return false, err end
		if name == "unlock" and password ~= f.password then changed(); return false, "Incorrect master password." end
		if name ~= "unlock" then f.password = password end
		f.vault.enabled, f.vault.locked = true, false
		f.vault.protection = "password"
		f.vault.challengePending = false
		f.config.set("security.rememberCredentials", true)
		changed(); return true
	end
	f.config.enableVault = function(password, options) return derive("enable", password, options) end
	f.config.unlockVault = function(password, options) return derive("unlock", password, options) end
	f.config.changeVaultPassword = function(password, options) return derive("change", password, options) end
	f.config.lockVault = function()
		f.calls[#f.calls + 1] = { name = "lock" }; f.vault.locked = true; changed(); return true
	end
	f.config.continueWithoutEncryption = function()
		if f.vault.locked or (f.vault.enabled and f.vault.challengePending) then return false, "Unlock the vault first." end
		if f.vault.busy then return false, "A credential storage operation is already in progress." end
		f.calls[#f.calls + 1] = { name = "unprotected" }
		if f.nextError then local err = f.nextError; f.nextError = nil; return false, err end
		f.vault.enabled, f.vault.locked, f.vault.challengePending = false, false, false
		f.vault.protection = "unprotected"
		f.config.set("security.rememberCredentials", true); changed(); return true
	end
	f.config.resetVault = function()
		f.calls[#f.calls + 1] = { name = "reset" }; f.vault.enabled, f.vault.locked = false, false
		f.vault.protection = "undecided"
		f.config.set("security.rememberCredentials", false); changed(); return true
	end
	return f
end

local function click(f, name, delay)
	if name == "VaultCancel" and f.h.byName("VaultProgressCancel") then name = "VaultProgressCancel" end
	if name == "VaultExit" and f.h.byName("VaultProgressExit") then name = "VaultProgressExit" end
	local button = assert(f.h.byName(name), "missing control: " .. name)
	-- The shared click helper advances 0.6s; fire directly when checking work
	-- while it is still pending rather than after the fake derivation settles.
	if delay then button.Activated:Fire() else f.h.click(button) end
	f.h.settle(delay or 0.6)
end
local function field(f, name)
	return assert(f.h.byName(name or "VaultPassword")):FindFirstChildOfClass("TextBox")
end
local function enter(f, password, confirmation)
	field(f).Text = password
	local confirm = f.h.byName("VaultConfirmPassword")
	if confirm then confirm:FindFirstChildOfClass("TextBox").Text = confirmation or password end
end
local function confirm(f, root, text)
	for _, node in ipairs(assert(f.h.byName(root)):GetDescendants()) do
		if node:IsA("TextLabel") and node.Text == text then
			local button = node.Parent
			while button and not button:IsA("TextButton") do button = button.Parent end
			f.h.click(assert(button)); f.h.settle(0.6); return
		end
	end
	error("missing confirmation: " .. text)
end
local function finish(f)
	f.env.require("ui/overlay").closeAll(); f.h.settle(0.3); f.healthy(); f.host:Destroy(); f.close()
end

case("setup masks native input, validates confirmation and preserves the exact password", function()
	for _, width in ipairs({ 320, 900 }) do
		local f = fixture(width)
		local picker = f.env.require("ui/credentialvault")
		local baseline = f.config.changed:count()
		local modal = picker.open(); f.h.settle(0.3)
		check("opening setup keeps the current storage choice", not f.vault.enabled and #f.calls == 0)
		check("setup explains verified migration", f.h.byName("VaultDescription").Text:find("existing keys", 1, true)
			and f.h.byName("VaultDescription").Text:find("encrypted save is verified", 1, true))
		local warning = assert(f.h.byName("VaultRecoveryWarning"))
		check("setup prominently warns that the password cannot be recovered", f.h.byName("VaultRecoveryHeading").Text == "NO PASSWORD RECOVERY"
			and f.h.byName("VaultRecoveryConsequences").Text:find("cannot recover your password", 1, true))
		check("setup explains permanent vault key removal and re-entry", f.h.byName("VaultRecoveryConsequences").Text:find("permanently removes every API key saved in this vault", 1, true)
			and f.h.byName("VaultRecoveryConsequences").Text:find("You must enter them again", 1, true))
		check("setup distinguishes saved copies from provider revocation and backups", f.h.byName("VaultRecoveryAdvice").Text:find("does not revoke keys at your providers or erase existing backups", 1, true))
		check("the recovery warning precedes the form and fits the modal", warning.LayoutOrder < f.h.byName("VaultPasswordForm").LayoutOrder
			and warning.AbsolutePosition.X >= modal.card.AbsolutePosition.X
			and warning.AbsolutePosition.X + warning.AbsoluteSize.X <= modal.card.AbsolutePosition.X + modal.card.AbsoluteSize.X)
		local password = "  fixture master phrase  "
		enter(f, password, "different fixture phrase")
		local box, mask = field(f), f.h.byName("VaultPasswordMask")
		check("password input is visually masked by default", box.TextTransparency == 1 and mask.Visible and not mask.Text:find("fixture", 1, true))
		click(f, "VaultPasswordShow")
		check("showing the password requires its explicit action", box.TextTransparency == 0 and not mask.Visible and box.Text == password)
		click(f, "VaultPasswordShow")
		check("the same action hides the password again", box.TextTransparency == 1 and mask.Visible)
		click(f, "VaultSubmit")
		check("mismatched confirmation never calls runtime", #f.calls == 0 and f.h.byName("VaultOperationStatus").Text:find("do not match", 1, true))
		enter(f, "short")
		click(f, "VaultSubmit")
		check("short setup passwords are rejected before deriving", #f.calls == 0)
		enter(f, string.rep("\195\169", 6))
		click(f, "VaultSubmit")
		check("setup counts Unicode characters rather than encoded bytes", #f.calls == 0)
		enter(f, password)
		check("the modal stays inside the viewport", modal.card.AbsoluteSize.X <= width)
		click(f, "VaultSubmit")
		check("setup passes the exact untrimmed password once", #f.calls == 1 and f.calls[1].name == "enable" and f.calls[1].password == password)
		check("success clears input and closes the modal", modal.closed and box.Text == "" and f.vault.enabled and not f.vault.locked)
		check("passwords never enter configuration state", not f.util.encode(f.config.data):find(password, 1, true))
		check("closing releases the vault settings subscription", f.config.changed:count() == baseline)
		finish(f)
	end
end)

case("setup warning and password fields remain usable after rotation and keyboard obstruction", function()
	local f = fixture(320)
	local uis = f.h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, false, false
	f.env.require("ui/responsive").init(f.env.root)
	f.env.require("ui/theme").rebuild()
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	modal.content:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize = f.h.dt.Vector2.new(280, 500)
	modal.relayout()
	enter(f, f.password)
	local password, confirmation, warning = field(f), field(f, "VaultConfirmPassword"), f.h.byName("VaultRecoveryWarning")
	f.h.setViewport(844, 390); f.h.settle(0.3)
	uis.OnScreenKeyboardSize, uis.OnScreenKeyboardVisible = f.h.dt.Vector2.new(844, 240), true
	uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); f.h.settle(0.3)
	check("rotation and keyboard retain the original warning and masked inputs", field(f) == password and field(f, "VaultConfirmPassword") == confirmation
		and f.h.byName("VaultRecoveryWarning") == warning and password.Text == f.password and confirmation.Text == f.password
		and password.TextTransparency == 1)
	check("the keyboard leaves a bounded scrolling form", modal.card.AbsoluteSize.Y <= 150
		and modal.scroll.instance.ScrollingEnabled and modal.scroll.viewportSize().Y > 0)
	check("setup and Exit remain in the reachable fixed or scrolling footer", f.h.byName("VaultSubmit"):IsDescendantOf(modal.footer)
		and f.h.byName("VaultExit"):IsDescendantOf(modal.footer)
		and (modal.footer.Parent == modal.card or modal.footer:IsDescendantOf(modal.scroll.instance)))
	-- The offline mock does not solve automatic text/list geometry. Supply the
	-- synthetic shape of a short viewport whose later inline footer makes a jump
	-- to the canvas bottom hide the status above it.
	local viewport, feedback = modal.scroll.instance, f.h.byName("VaultOperationStatus")
	local function measureFeedback()
		viewport.AbsolutePosition = f.h.dt.Vector2.new(0, 0)
		viewport.AbsoluteWindowSize = f.h.dt.Vector2.new(300, 60)
		viewport.AbsoluteCanvasSize = f.h.dt.Vector2.new(300, 560)
		viewport.CanvasPosition = f.h.dt.Vector2.new(0, 0)
		feedback.AbsolutePosition = f.h.dt.Vector2.new(0, 400)
		feedback.AbsoluteSize = f.h.dt.Vector2.new(300, 24)
	end
	local function feedbackVisible()
		local top = 400 - viewport.CanvasPosition.Y
		return top >= 0 and top + 24 <= 60
	end
	measureFeedback()
	enter(f, f.password, "different fixture confirmation"); click(f, "VaultSubmit", 0.05)
	check("password mismatch scrolls its explanation into the keyboard viewport", #f.calls == 0 and feedbackVisible()
		and f.h.byName("VaultOperationStatus").Text:find("do not match", 1, true))
	check("revealing feedback stops before the later footer at the canvas bottom", viewport.CanvasPosition.Y < 500)
	measureFeedback()
	enter(f, f.password); click(f, "VaultSubmit", 0.05)
	check("starting derivation moves progress to the corner without dismissing the gate", f.vault.busy and not modal.closed and modal.suspended
		and f.h.byName("VaultProgressPercent").Text == "25%")
	viewport.CanvasPosition = f.h.dt.Vector2.new(0, 80); f.h.settle(0.1)
	check("later progress updates preserve the user's chosen scroll position", f.vault.busy and viewport.CanvasPosition.Y == 80)
	click(f, "VaultCancel", 0.05); f.h.settle(0.6)
	viewport.__props.AbsolutePosition, viewport.__props.AbsoluteWindowSize, viewport.__props.AbsoluteCanvasSize = nil, nil, nil
	uis.OnScreenKeyboardVisible = false; uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
	f.h.setViewport(320, 700); f.h.settle(0.3)
	enter(f, f.password)
	click(f, "VaultSubmit")
	check("the resized form still submits the exact password after cancellation", modal.closed and #f.calls == 2 and f.calls[2].password == f.password)
	finish(f)
end)

case("setup and unlock share compact progress without releasing admission", function()
	local setupSize
	for _, enabled in ipairs({ false, true }) do
		local f = fixture(390, enabled, enabled)
		local responsive, theme = f.env.require("ui/responsive"), f.env.require("ui/theme")
		responsive.init(f.env.root); theme.rebuild()
		local progress
		f.config[enabled and "unlockVault" or "enableVault"] = function(_, options)
			f.vault.busy = true; f.config.changed:fire("security.vault"); progress = options.progress
			while not options.cancelled() do f.h.sandbox.task.wait(0.05) end
			f.vault.busy = false; f.config.changed:fire("security.vault"); return false, "Cancelled"
		end
		local picker, overlay = f.env.require("ui/credentialvault"), f.env.require("ui/overlay")
		local modal = picker.open("required"); f.h.settle(0.3)
		local subscriptions = responsive.changed:count()
		enter(f, f.password); field(f):CaptureFocus(); click(f, "VaultSubmit", 0.05)
		local panel, percentage = assert(f.h.byName("VaultProgress")), assert(f.h.byName("VaultProgressPercent"))
		check("password work hides the full scrim and releases native keyboard focus", modal.suspended and not modal.scrim.Visible
			and not modal.scrim.Active and f.h.services.UserInputService:GetFocusedTextBox() == nil)
		check("only the compact corner owns input while admission stays closed", panel.Parent == overlay.layer and panel.Active
			and not overlay.layer.Active and modal.operationPending and not f.config.vaultStatus().ready)
		check("compact progress names the operation above its percentage and actions", f.h.byName("VaultProgressTitle").Text == (enabled and "Decrypting API keys" or "Encrypting API keys")
			and f.h.byName("VaultProgressCancel"):IsDescendantOf(panel) and f.h.byName("VaultProgressExit"):IsDescendantOf(panel)
			and percentage.Text == "0%" and panel.AbsoluteSize.Y < 80 and panel.AbsoluteSize.X < 300)
		local rect = responsive.usableRect(overlay.layer, theme.space.md)
		check("the indicator is inset at the bottom right", panel.Position.X.Offset == rect.x + rect.width
			and panel.Position.Y.Offset == rect.y + rect.height and panel.AnchorPoint.X == 1 and panel.AnchorPoint.Y == 1)
		if enabled then check("unlock uses the exact setup progress dimensions", panel.Size == setupSize)
		else setupSize = panel.Size end
		local changes = 0
		local observed = percentage:GetPropertyChangedSignal("Text"):Connect(function() changes = changes + 1 end)
		for done = 2500, 2599 do assert(progress(done, 10000)) end
		check("frequent derivation callbacks coalesce to the displayed percentage", changes == 1 and percentage.Text == "25%")
		observed:Disconnect()
		check("reopening a pending required entry retains its modal and indicator", picker.open("required") == modal
			and f.h.byName("VaultProgress") == panel and responsive.changed:count() == subscriptions + 1)
		f.h.press("Escape"); f.h.press("ButtonB"); f.h.settle(0.1)
		check("Escape and gamepad dismissal preserve corner work", f.vault.busy and modal.operationPending and not modal.closed
			and f.h.byName("VaultProgress") == panel)
		f.h.setViewport(700, 390); f.h.settle(0.1)
		rect = responsive.usableRect(overlay.layer, theme.space.md)
		check("rotation repositions the same compact progress row", f.h.byName("VaultProgress") == panel
			and panel.Position.X.Offset == rect.x + rect.width and panel.Position.Y.Offset == rect.y + rect.height)
		click(f, "VaultCancel", 0.05); f.h.settle(0.2)
		check("cooperative cancellation restores entry and releases its progress subscription", not modal.suspended and modal.scrim.Visible
			and modal.scrim.Active and not modal.operationPending and f.h.byName("VaultProgress") == nil
			and responsive.changed:count() == subscriptions and field(f).Text == "" and field(f).TextEditable)
		finish(f)
	end
end)

case("suspended work is cancelled when its modal owner is closed or destroyed", function()
	for _, destroy in ipairs({ false, true }) do
		local f = fixture(390)
		local responsive, overlay = f.env.require("ui/responsive"), f.env.require("ui/overlay")
		local before, configBefore = responsive.changed:count(), f.config.changed:count()
		local closes = 0
		local modal = f.env.require("ui/credentialvault").open("required", { onClose = function() closes = closes + 1 end })
		f.h.settle(0.3); enter(f, f.password); click(f, "VaultSubmit", 0.05)
		check("derivation is pending before owner teardown", f.vault.busy and modal.suspended)
		if destroy then modal.scrim:Destroy() else overlay.closeAll() end
		f.h.settle(0.6)
		check("owner teardown cancels derivation without committing setup", not f.vault.busy and not f.vault.enabled and modal.closed
			and f.h.byName("VaultProgress") == nil and closes == 1)
		check("owner teardown releases modal, progress and settings subscriptions", responsive.changed:count() == before
			and f.config.changed:count() == configBefore and #overlay.open == 0)
		modal.close(); f.h.settle(0.1)
		check("repeated close does not repeat owned cleanup", closes == 1 and responsive.changed:count() == before)
		finish(f)
	end
end)

case("unlock fits measured contents while keeping a bounded scrolling body", function()
	local f = fixture(900, true, true)
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	local theme = f.env.require("ui/theme")
	-- The offline mock does not solve automatic text or list geometry. Feed two
	-- content measurements to verify fitting and its usable-height ceiling.
	local layout = modal.content:FindFirstChildOfClass("UIListLayout")
	layout.AbsoluteContentSize = f.h.dt.Vector2.new(400, 220); modal.relayout()
	local compactHeight = modal.card.AbsoluteSize.Y
	check("a short unlock form fits its measured contents instead of modalTall", compactHeight < theme.size.modalTall
		and modal.scroll.instance.AbsoluteSize.Y >= 220 and f.h.byName("VaultConfirmPassword") == nil)
	layout.AbsoluteContentSize = f.h.dt.Vector2.new(400, 1200); modal.relayout()
	check("long unlock contents cap at the viewport and retain scrolling", modal.card.AbsoluteSize.Y > compactHeight
		and modal.card.AbsoluteSize.Y <= 700 and modal.scroll.instance.ScrollingEnabled
		and modal.scroll.instance.AbsoluteSize.Y < 1200)
	finish(f)
end)

case("unprotected storage requires its red explicit action and a verified save", function()
	for _, enabled in ipairs({ false, true }) do
		local f = fixture(390, enabled, false)
		local picker = f.env.require("ui/credentialvault")
		local modal = picker.open(); f.h.settle(0.3)
		local button, theme = assert(f.h.byName("VaultContinueUnprotected")), f.env.require("ui/theme")
		local label = button:FindFirstChild("Content"):FindFirstChildOfClass("TextLabel")
		check("setup and unlocked management label the red opt-out explicitly", label.Text == "Continue without encryption"
			and label.TextColor3 == theme.color.danger and f.h.byName("VaultUnprotectedWarning").Text:find("saved API keys are unprotected", 1, true))
		check("displaying the choice does not change saved protection", f.vault.protection == (enabled and "password" or "undecided") and #f.calls == 0)
		if not enabled then enter(f, f.password) end
		f.nextError = "Could not verify the saved storage choice. Existing credentials are unchanged."
		click(f, "VaultContinueUnprotected")
		check("failed opt-out preserves the current vault and shows the save error", not modal.closed and f.vault.enabled == enabled
			and f.vault.protection == (enabled and "password" or "undecided")
			and f.h.byName("VaultOperationStatus").Text:find("Existing credentials are unchanged", 1, true))
		if not enabled then check("opt-out clears a password draft even after save failure", field(f).Text == "" and field(f).TextEditable) end
		click(f, "VaultContinueUnprotected")
		check("verified explicit opt-out closes entry and admits unprotected storage", modal.closed and not f.vault.enabled
			and f.vault.protection == "unprotected" and f.config.vaultStatus().ready and f.calls[#f.calls].name == "unprotected")
		modal = picker.open(); f.h.settle(0.3)
		check("unprotected users can return to password setup", f.h.byName("VaultPassword") ~= nil
			and f.h.byName("VaultRecoveryHeading").Text == "NO PASSWORD RECOVERY")
		enter(f, f.password); click(f, "VaultSubmit")
		check("successful password setup replaces the unprotected choice", modal.closed and f.vault.enabled and f.vault.protection == "password")
		finish(f)
	end
end)

case("locked and warm-challenged vaults expose no unprotected bypass", function()
	for _, locked in ipairs({ false, true }) do
		local f = fixture(390, true, locked)
		f.vault.challengePending = not locked
		local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
		check("locked and warm entry require unlock or explicit reset", f.h.byName("VaultContinueUnprotected") == nil
			and f.h.byName("VaultUnprotectedWarning") == nil and f.h.byName("VaultReset") ~= nil and not f.config.vaultStatus().ready)
		click(f, "VaultReset"); confirm(f, "ResetCredentialVault", "Remove saved credentials")
		check("confirmed reset returns to an undecided choice with no saved vault", not modal.closed and not f.vault.enabled
			and not f.config.vaultStatus().ready and f.h.byName("VaultContinueUnprotected") ~= nil)
		click(f, "VaultContinueUnprotected")
		check("only the explicit post-reset choice permits unprotected entry", modal.closed and f.config.vaultStatus().ready)
		finish(f)
	end
end)

case("unlock handles wrong passwords and restores the existing manager", function()
	local f = fixture(390, true, true)
	local picker = f.env.require("ui/credentialvault")
	local modal = picker.open(); f.h.settle(0.3)
	check("locked vault asks for one password", f.h.byName("VaultConfirmPassword") == nil and f.h.byName("VaultReset") ~= nil)
	enter(f, "wrong fixture phrase")
	click(f, "VaultSubmit")
	check("a wrong password stays locked with a readable error", f.vault.locked and not modal.closed
		and f.h.byName("VaultOperationStatus").Text == "Incorrect master password." and field(f).Text == ""
		and not modal.suspended and modal.scrim.Visible and f.h.byName("VaultProgress") == nil)
	enter(f, f.password); click(f, "VaultSubmit")
	check("successful unlock closes entry without changing the master password", not f.vault.locked and modal.closed and f.password == "fixture master phrase")
	local management = picker.open(); f.h.settle(0.3)
	check("reopening exposes only unlocked management actions", f.h.byName("VaultPassword") == nil and f.h.byName("VaultLock") ~= nil and f.h.byName("VaultChangePassword") ~= nil)
	click(f, "VaultChangePassword")
	enter(f, "replacement fixture phrase"); click(f, "VaultSubmit", 0.05)
	-- press() advances 0.2s per key, which would finish this 0.4s fake
	-- derivation before the pending-work assertion. Dispatch both now.
	local enum = f.h.sandbox.Enum
	for _, key in ipairs({ "Escape", "ButtonB" }) do
		f.h.services.UserInputService.InputBegan:Fire({ KeyCode = enum.KeyCode[key], UserInputType = enum.UserInputType.Keyboard }, false)
	end
	f.h.settle(0.1)
	check("a normally dismissable password-change dialog remains owned while suspended", management.dismissable and management.suspended
		and not management.closed and f.vault.busy and f.h.byName("VaultProgress") ~= nil and f.h.byName("VaultProgressExit") == nil)
	f.h.settle(0.6)
	check("password change uses the dedicated runtime operation", f.calls[#f.calls].name == "change" and f.password == "replacement fixture phrase")
	picker.open(); f.h.settle(0.3); click(f, "VaultLock")
	check("locking closes management and updates runtime state", f.vault.locked and f.calls[#f.calls].name == "lock")
	finish(f)
end)

case("required setup cannot be dismissed and cancelling derivation keeps the gate", function()
	local f = fixture(390)
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	check("the required prompt omits the close control", modal.dismissable == false and f.h.byName("Close", modal.card) == nil)
	f.h.press("Escape"); f.h.press("ButtonB"); f.h.settle(0.3)
	check("keyboard and gamepad dismissal leave setup open", not modal.closed)
	f.h.click(modal.scrim); f.h.settle(0.3)
	check("the scrim has no outside-dismiss controls", not modal.closed and f.h.byName("Dismiss", modal.scrim) == nil)
	click(f, "VaultCancel")
	check("idle cancellation explains the explicit storage choice", not modal.closed and f.h.byName("VaultOperationStatus").Text:find("explicitly continue without encryption", 1, true))
	enter(f, f.password)
	local box = field(f)
	click(f, "VaultSubmit", 0.05)
	check("derivation reports compact progress with cleared disabled input", f.vault.busy and box.Text == "" and not box.TextEditable
		and f.h.byName("VaultProgressPercent").Text == "25%" and modal.suspended and not modal.scrim.Visible)
	click(f, "VaultCancel", 0.05); f.h.settle(0.7)
	check("cancelled setup preserves storage and restores the gate", not f.vault.enabled and not f.vault.busy and not modal.closed
		and not modal.suspended and modal.scrim.Visible and f.h.byName("VaultProgress") == nil)
	check("cancelled work returns to editable password setup", field(f).Text == "" and field(f).TextEditable
		and f.h.byName("VaultOperationStatus").Text:find("Operation cancelled", 1, true))
	enter(f, f.password); click(f, "VaultSubmit")
	check("setup can succeed after cancellation", f.vault.enabled and modal.closed)
	finish(f)
end)

case("warm execution asks for a password while the runtime retains its session key", function()
	local f = fixture(390, true, false)
	f.vault.challengePending = true
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	check("a warm challenge presents unlock rather than management", f.h.byName("VaultHeading").Text == "Unlock saved credentials"
		and f.h.byName("VaultPassword") ~= nil and f.h.byName("VaultChangePassword") == nil)
	enter(f, "wrong fixture phrase"); click(f, "VaultSubmit")
	check("a wrong warm password keeps the gate open", not modal.closed and not f.config.vaultStatus().ready
		and f.h.byName("VaultOperationStatus").Text == "Incorrect master password.")
	enter(f, f.password); click(f, "VaultSubmit")
	check("warm authentication calls unlock and releases only the completed challenge", modal.closed and f.config.vaultStatus().ready
		and #f.calls == 2 and f.calls[2].name == "unlock")
	finish(f)
end)

case("reexecution during setup retains the newest password challenge", function()
	local f = fixture(390)
	f.config.enableVault = function()
		f.vault.enabled, f.vault.locked, f.vault.challengePending = true, false, true
		f.config.changed:fire("security.vault"); return true
	end
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	enter(f, f.password); click(f, "VaultSubmit")
	check("verified setup does not dismiss a newer challenge", not modal.closed and not f.config.vaultStatus().ready
		and f.h.byName("VaultHeading").Text == "Unlock saved credentials")
	check("the dialog explains the new execution without claiming access", f.h.byName("VaultOperationStatus").Text:find("new execution", 1, true)
		and not f.h.textOf():find("unlocked for this run", 1, true))
	enter(f, f.password); click(f, "VaultSubmit")
	check("entering the password for the new execution grants access", modal.closed and f.config.vaultStatus().ready)
	finish(f)
end)

case("forgotten-password reset requires confirmation and returns to required setup", function()
	local f = fixture(390, true, true)
	local picker = f.env.require("ui/credentialvault")
	local modal = picker.open("required"); f.h.settle(0.3); click(f, "VaultReset")
	check("forgotten-password reset warns about permanent loss", f.h.textOf(f.h.byName("ResetCredentialVault")):find("permanently removes every API key and credential", 1, true))
	confirm(f, "ResetCredentialVault", "Cancel")
	check("cancelling reset keeps encrypted credentials", f.vault.enabled and f.vault.locked and #f.calls == 0)
	click(f, "VaultReset"); confirm(f, "ResetCredentialVault", "Remove saved credentials")
	check("only confirmed reset calls the destructive operation", not f.vault.enabled and f.calls[1].name == "reset")
	check("reset does not grant access or dismiss the gate", not modal.closed and not f.config.vaultStatus().ready
		and f.h.byName("VaultHeading").Text == "Set a master password")
	enter(f, f.password); click(f, "VaultSubmit")
	picker.open(); f.h.settle(0.3)
	check("unlocked management exposes the explicit unprotected choice", f.h.byName("VaultContinueUnprotected") ~= nil and f.h.byName("VaultLock") ~= nil)
	finish(f)
end)

case("a verified commit that finishes after Cancel reports its successful result", function()
	local f = fixture(390)
	f.config.enableVault = function()
		f.vault.busy = true; f.config.changed:fire("security.vault")
		-- Model a filesystem commit whose ownership outlives cooperative Cancel.
		f.h.sandbox.task.wait(0.4)
		f.vault.busy, f.vault.enabled, f.vault.locked = false, true, false
		f.config.changed:fire("security.vault")
		return true
	end
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	enter(f, f.password); click(f, "VaultSubmit", 0.05); click(f, "VaultCancel", 0.05); f.h.settle(0.6)
	check("completed encryption closes the gate even after late cancellation", modal.closed and f.config.vaultStatus().ready)
	check("the dialog reports verified success instead of a false cancellation", f.h.textOf():find("Credential vault enabled", 1, true) ~= nil)
	finish(f)
end)

case("Privacy explains encryption and opens the explicit storage choice", function()
	local f = fixture(390)
	f.env.require("ui/settingspanes").render("privacy", f.host); f.h.settle(0.3)
	check("setup preserves keys while awaiting an explicit storage choice", f.h.byName("CredentialStorageStatus").Text:find("carry over", 1, true)
		and f.h.byName("RememberCredentialsSwitch") == nil and #f.calls == 0)
	click(f, "ManageCredentialVault"); click(f, "VaultCancel")
	check("cancelling setup leaves the previous credentials intact", not f.vault.enabled and f.config.get("security.rememberCredentials") == true)
	enter(f, f.password); click(f, "VaultSubmit")
	check("setup refreshes Privacy with encrypted unlocked status", f.h.byName("CredentialVaultStatus").Text:find("Unlocked", 1, true))
	f.config.lockVault(); f.h.settle(0.3)
	check("locked status explains why credentials cannot be used", f.h.byName("CredentialStorageStatus").Text:find("encrypted and locked", 1, true)
		and f.h.byName("CredentialVaultStatus").Text:find("Locked", 1, true))
	click(f, "ManageCredentialVault")
	check("Privacy opens required unlock", f.h.byName("VaultHeading").Text == "Unlock saved credentials")
	enter(f, f.password); click(f, "VaultSubmit")
	check("unlock refreshes Privacy while keeping storage protected", f.h.byName("CredentialVaultStatus").Text:find("Unlocked", 1, true)
		and f.h.byName("RememberCredentialsSwitch") == nil)
	click(f, "ManageCredentialVault"); click(f, "VaultContinueUnprotected")
	check("Privacy labels the verified unprotected state and explains file recovery", f.h.byName("CredentialVaultStatus").Text:find("Unprotected storage is active", 1, true)
		and f.h.byName("CredentialStorageStatus").Text:find("anyone with file access can recover", 1, true))
	click(f, "ManageCredentialVault")
	check("Privacy can re-enable encryption after opting out", f.h.byName("VaultHeading").Text == "Set a master password")
	finish(f)
end)

case("encrypted imports ask for the source password and stop at review", function()
	local f = fixture(390, true, false)
	local applied, decrypted = 0, 0
	local preview = { config = {}, summary = { providers = 1, keys = 2, active = "Imported fixture", permissionMode = "ask",
		rules = 0, memory = 0, bridgeEnabled = false, credentialsIncluded = true, rememberCredentials = true } }
	f.loaded["runtime/config_transfer"] = {
		preview = function(source, options)
			if not options or not options.password then return nil, "Enter the source password.", "password" end
			decrypted = decrypted + 1
			for step = 1, 3 do
				if options.cancelled() or options.progress(step, 3) == false then return nil, "Cancelled" end
				f.h.sandbox.task.wait(0.1)
			end
			if options.cancelled() then return nil, "Cancelled" end
			if options.password ~= "source fixture password" then return nil, "Incorrect source password." end
			return preview
		end,
		apply = function() applied = applied + 1; return true, true end,
	}
	f.env.require("ui/settingspanes").render("import_export", f.host); f.h.settle(0.3)
	click(f, "PasteFullConfig")
	local source = assert(f.h.byName("ConfigImportJSON")):FindFirstChildOfClass("TextBox")
	source.Text = "encrypted fixture copy"; click(f, "ReviewConfigImport")
	check("encrypted review asks for one masked source password", field(f).TextTransparency == 1 and f.h.byName("VaultConfirmPassword") == nil)
	enter(f, "source fixture password"); click(f, "VaultSubmit")
	check("decryption presents ordinary review without applying", decrypted == 1 and applied == 0
		and f.h.byName("ConfigImportStatus").Text:find("Ready to import", 1, true) and f.vault.enabled)
	source.Text = "changed encrypted fixture copy"
	check("editing the copy invalidates a decrypted preview", not f.h.byName("ApplyConfigImport").Active)
	click(f, "ReviewConfigImport"); enter(f, "source fixture password"); click(f, "VaultSubmit", 0.05)
	click(f, "VaultCancel", 0.05); f.h.settle(0.4)
	check("explicit import cancellation restores entry for the same source", f.h.byName("CredentialVault") ~= nil
		and f.h.byName("VaultProgress") == nil and field(f).Text == "" and field(f).TextEditable
		and f.h.byName("VaultOperationStatus").Text:find("Operation cancelled", 1, true))
	enter(f, "source fixture password"); click(f, "VaultSubmit", 0.05)
	source.Text = "changed during decryption"; f.h.settle(0.6)
	check("editing during decryption cancels it and cannot restore a stale preview", applied == 0 and f.h.byName("CredentialVault") == nil
		and not f.h.byName("ApplyConfigImport").Active and not f.h.byName("ConfigImportStatus").Text:find("Ready to import", 1, true))
	finish(f)
end)

case("external import invalidation closes stale entry even after decryption completes", function()
	for _, completed in ipairs({ false, true }) do
		local f = fixture(390, true, false)
		local stale, accepted = false, 0
		local modal = f.env.require("ui/credentialvault").open("import", {
			cancelled = function() return stale end,
			submit = function()
				-- Model source ownership changing while a decrypt callback is
				-- awaiting native completion and cannot stop immediately.
				f.h.sandbox.task.wait(0.2); return completed, completed and {} or "Cancelled"
			end,
			onSuccess = function() accepted = accepted + 1 end,
		})
		f.h.settle(0.3); enter(f, "source fixture password"); click(f, "VaultSubmit", 0.05)
		stale = true; f.h.settle(0.4)
		check("a stale source releases its dialog and cannot accept a late preview", modal.closed and f.h.byName("CredentialVault") == nil
			and f.h.byName("VaultProgress") == nil and accepted == 0)
		finish(f)
	end
end)

case("failed encrypted write leaves the setup open and the previous storage choice usable", function()
	local f = fixture(390)
	local modal = f.env.require("ui/credentialvault").open(); f.h.settle(0.3)
	f.nextError = "Could not verify the staged encrypted file. Your existing configuration is unchanged."
	enter(f, f.password); click(f, "VaultSubmit")
	check("write failure is visible without claiming encryption succeeded", not f.vault.enabled and not modal.closed
		and f.h.byName("VaultOperationStatus").Text:find("existing configuration is unchanged", 1, true)
		and not modal.suspended and modal.scrim.Visible and f.h.byName("VaultProgress") == nil)
	check("failed setup clears the supplied password and allows retry", field(f).Text == "" and field(f).TextEditable
		and f.config.get("security.rememberCredentials") == true)
	enter(f, f.password); click(f, "VaultSubmit")
	check("the same setup can retry successfully", f.vault.enabled and modal.closed)
	finish(f)
end)

case("locking closes credential drafts and offers unlock instead of editing empty keys", function()
	local f = fixture(390, true, false)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.apiKey, record.baseUrl = "Vault provider fixture", "vault-ui-fixture-key", "https://vault-ui.fixture/v1"
	record.model, record.models = "fixture-model", { "fixture-model" }
	assert(registry.save(record))
	local manager = f.env.require("ui/providerkeys").open({ record = record }); f.h.settle(0.3)
	check("key manager describes encrypted persistence", f.h.byName("KeyStorageSummary").Text:find("encrypted", 1, true)
		and not f.h.byName("KeyStorageSummary").Text:find("not encryption", 1, true))
	f.config.lockVault(); f.h.settle(0.3)
	check("lock closes the existing key draft", manager.closed and f.h.byName("APIKeyManager") == nil)
	local editor = f.env.require("ui/panels/providers")
	editor.editor(record); f.h.settle(0.3)
	check("locked provider editing opens the unlock dialog", f.h.byName("VaultHeading").Text == "Unlock saved credentials"
		and f.h.byName("SaveProvider") == nil)
	click(f, "VaultCancel")
	local before = f.util.encode(f.config.data.providers)
	check("locked provider saves and removals fail without touching records", registry.save(f.util.deepCopy(record)) == false
		and registry.remove(record.id) == false and before == f.util.encode(f.config.data.providers))
	check("locked provider requests explain how to unlock", registry.protocolProblem(record):find("master password", 1, true))
	f.env.require("ui/overlay").closeAll(); f.h.settle(0.3)
	f.vault.locked = false; f.config.changed:fire("security.vault")
	editor.editor(record); f.h.settle(0.3)
	local url = assert(f.h.byName("BaseUrl")):FindFirstChildOfClass("TextBox")
	url.Text = "https://vault-ui.fixture/v1?private=unsaved-secret"
	f.config.lockVault(); f.h.settle(0.3)
	check("lock discards the open connection draft and clears its fields", f.h.byName("SaveProvider") == nil and url.Text == "")
	finish(f)
end)

case("cold vault boot gates every UI entry point and allows explicit Exit", function()
	for _, ui in ipairs({ true, false }) do
		local h = require("env").new({ context = { ui = ui } })
		local function find(name) return h.byName(name, h.coreGui) end
		h.files["UAI/config.json"] = h.json.encode({ security = { rememberCredentials = true },
			ui = { tutorial = { seen = true }, communityInvite = { disabled = true } },
			providers = { list = {}, active = "" }, credentialVault = { version = 1, cipher = "aes-256-siv",
				kdf = "pbkdf2-hmac-sha256", iterations = 600000, salt = "uai-vault-v1:00000000-0000-4000-8000-000000000001", data = string.rep("0", 32) } })
		local handle = assert(h.boot("dist/uai.lua")); h.settle(0.5)
		check("cold vault remains locked and preserves an empty provider mapping", handle.config.vaultStatus().locked
			and handle.config.vaultStatus().required and not handle.config.vaultStatus().ready and #handle.config.get("providers.list") == 0)
		check("every startup mounts its mandatory password prompt", handle.uiMounted and find("CredentialVault") ~= nil)
		check("the mounted client asks for the existing master password", assert(find("VaultHeading")).Text == "Unlock saved credentials"
			and not handle.app.window.visible and not handle.app.launcher.Visible)
		h.click(assert(find("VaultCancel"))); h.press("Escape"); h.press("ButtonB"); h.settle(0.3)
		handle.show(); handle.toggle(); handle.app.showSettingsDialog("privacy"); handle.app.showAppMenu(handle.app.launcher)
		handle.env.require("ui/quickchat").show(); handle.app.window.show(); h.settle(0.3)
		check("all UI entry points keep the password gate", find("CredentialVault") ~= nil and not handle.app.window.visible
			and not handle.app.launcher.Visible and not handle.env.require("ui/quickchat").visible and find("CredentialStorageStatus") == nil)
		local overlay = handle.env.require("ui/overlay")
		overlay.closeAll(); h.settle(0.3)
		handle.app.mount(); handle.app.rebuild("vault prompt fixture"); h.settle(0.4)
		check("closing overlays and rebuilding cannot bypass required unlock", find("CredentialVault") ~= nil
			and not handle.app.window.visible and not handle.app.launcher.Visible)
		-- Runtime encryption has separate vectors and storage tests. Simulate only
		-- its readiness notification here so the full mounted app exercises unlock.
		local vaultStatus, unlocked = handle.config.vaultStatus, false
		handle.config.vaultStatus = function()
			local status = vaultStatus()
			status.ready, status.locked = unlocked, not unlocked
			return status
		end
		handle.config.unlockVault = function()
			unlocked = true; handle.config.changed:fire("security.vault"); return true
		end
		find("VaultPassword"):FindFirstChildOfClass("TextBox").Text = "fixture unlock phrase"
		h.click(assert(find("VaultSubmit"))); h.settle(0.3)
		check("successful password entry reveals the app and releases the gate", handle.app.window.visible and find("CredentialVault") == nil)
		check("synchronous readiness still reports unlock success", h.textOf(handle.app.screen):find("Credential vault unlocked for this run", 1, true) ~= nil)
		handle.app.showSettingsDialog("privacy"); h.settle(0.3)
		check("the unlocked app exposes Settings", find("CredentialStorageStatus") ~= nil)
		handle.env.require("ui/credentialvault").open(); h.settle(0.3)
		unlocked = false; handle.config.changed:fire("security.vault"); h.settle(0.3)
		check("locking upgrades management to mandatory entry and removes Settings", not handle.app.window.visible
			and not handle.app.launcher.Visible and find("CredentialStorageStatus") == nil
			and find("VaultHeading").Text == "Unlock saved credentials" and find("VaultExit") ~= nil)
		h.click(assert(find("VaultExit"))); h.settle(0.3)
		check("explicit Exit unloads the client", handle.app.disposed and find("CredentialVault") == nil)
		check("cold startup and gated exit stay healthy", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	end
end)

case("UI-free startup shows password entry and stays hidden after authentication", function()
	local h = require("env").new({ context = { ui = false } })
	local handle = assert(h.boot("dist/uai.lua")); h.settle(0.5)
	local function find(name) return h.byName(name, h.coreGui) end
	check("UI-free startup presents required setup", handle.uiMounted and find("VaultPassword") ~= nil
		and not handle.app.window.visible and not handle.app.launcher.Visible)
	local originalStatus, ready = handle.config.vaultStatus, false
	handle.config.vaultStatus = function()
		local status = originalStatus()
		status.enabled, status.locked, status.ready = ready, false, ready
		return status
	end
	handle.config.enableVault = function()
		ready = true; handle.config.changed:fire("security.vault"); return true
	end
	find("VaultPassword"):FindFirstChildOfClass("TextBox").Text = "fixture headless master phrase"
	find("VaultConfirmPassword"):FindFirstChildOfClass("TextBox").Text = "fixture headless master phrase"
	h.click(assert(find("VaultSubmit"))); h.settle(0.3)
	check("successful headless authentication leaves ordinary UI hidden", find("CredentialVault") == nil
		and not handle.app.window.visible and not handle.app.launcher.Visible)
	handle.app.rebuild("headless credential fixture"); h.settle(0.3)
	check("rebuilding retains the hidden headless preference", not handle.app.window.visible and not handle.app.launcher.Visible)
	handle.show(); h.settle(0.3)
	check("an explicit show reveals the authenticated interface", handle.app.window.visible)
	check("headless authentication UI stays healthy", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	handle.destroy(); h.settle(0.3)
end)

case("the real startup opt-out saves its choice and respects normal or hidden UI", function()
	for _, showUI in ipairs({ false, true }) do
		local h = require("env").new({ context = { ui = showUI } })
		local handle = assert(h.boot("dist/uai.lua")); h.settle(0.5)
		local function find(name) return h.byName(name, h.coreGui) end
		check("fresh startup waits for a deliberate protection choice", not handle.config.vaultStatus().ready
			and find("VaultContinueUnprotected") ~= nil and not handle.app.window.visible)
		h.click(assert(find("VaultContinueUnprotected"))); h.settle(0.3)
		check("the startup action verifies and persists the unprotected choice", handle.config.vaultStatus().ready
			and handle.config.vaultStatus().protection == "unprotected"
			and h.json.decode(h.files["UAI/config.json"]).security.credentialProtection == "unprotected")
		check("successful opt-out releases entry and honors the startup UI preference", find("CredentialVault") == nil
			and handle.app.window.visible == showUI and (showUI or not handle.app.launcher.Visible))
		check("the completed action visibly reports unprotected API-key storage", h.textOf(handle.app.screen):find("Saved API keys are unprotected", 1, true) ~= nil)
		check("actual opt-out UI stays healthy", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
		handle.destroy(); h.settle(0.3)
	end
end)

case("required Exit reports storage refusal and cancellation remains available", function()
	local f = fixture(390)
	f.h.sandbox.getgenv = nil
	local exits = 0
	f.env.exitClient = function()
		exits = exits + 1
		if f.vault.busy then return false, "Fixture storage is still saving." end
		f.env.require("ui/overlay").closeAll(); return true
	end
	local modal = f.env.require("ui/credentialvault").open("required"); f.h.settle(0.3)
	enter(f, f.password); click(f, "VaultSubmit", 0.05); click(f, "VaultExit", 0.01)
	check("refused Exit shows the storage reason and retains the gate", exits == 1 and not modal.closed
		and f.h.textOf():find("Fixture storage is still saving.", 1, true) ~= nil)
	click(f, "VaultCancel"); click(f, "VaultExit")
	check("Exit works without executor globals after cancellation", exits == 2 and modal.closed and not f.vault.enabled)
	finish(f)
end)

case("Unload explains a pending storage refusal without draining the client", function()
	for _, published in ipairs({ true, false }) do
		local f = fixture(390, true, false)
		f.vault.busy = true
		if published then
			f.h.sandbox.UAI = { destroy = function() return false, "Fixture storage is still saving." end }
		else f.h.sandbox.getgenv = nil end
		f.env.require("ui/settingspanes").render("developer", f.host); f.h.settle(0.3)
		local count = f.env.require("runtime/dispose").count()
		click(f, "UnloadUai")
		local overlay = f.env.require("ui/overlay")
		overlay.open[#overlay.open].card.Name = "UnloadFixtureConfirm"
		confirm(f, "UnloadFixtureConfirm", "Unload")
		check("Unload displays why the storage owner must finish", f.h.textOf():find(published and "Fixture storage is still saving."
			or "Finish or cancel credential storage before unloading UAI.", 1, true))
		check("refused Unload keeps mounted controls and owned resources", f.h.byName("UnloadUai") ~= nil
			and f.env.require("runtime/dispose").count() == count)
		finish(f)
	end
end)

suite.finish()
