-- A quiet, optional invitation. Never mounts UI from a headless runtime.
return function(env)
	local community = env.require("runtime/community")
	local clock = env.require("runtime/clock")
	local clipboard = env.require("runtime/clipboard")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local overlay = env.require("ui/overlay")
	local P = env.require("ui/primitives")
	local M = {}
	local current

	function M.open()
		if current and not current.closed then return current end
		local modal = overlay.modal({ title = "Join our Discord",
			description = "Get Project UAI updates, ask for help, and share what you build.",
			width = theme.size.modal, onClose = function() current = nil end })
		if not modal then return nil end
		current = modal
		community.markShown()
		local card = P.card(modal.content, { name = "CommunityCard", padding = theme.space.md,
			gap = theme.space.sm, bg = theme.color.surface, layoutOrder = 1 })
		P.text(card, { name = "CommunityInviteLabel", text = "Discord invite", role = "label",
			size = UDim2.new(1, 0, 0, 0), auto = "Y", layoutOrder = 1 })
		local invite = P.field(card, { name = "CommunityInvite", text = community.invite, readOnly = true,
			role = "small", multiline = true,
			height = math.max(responsive.minTarget(), theme.text.small.height + theme.space.sm * 2), layoutOrder = 2 })
		local measuredWidth
		local function fitInvite()
			local width = invite.shell.AbsoluteSize.X
			if width <= 0 or width == measuredWidth then return end
			measuredWidth = width
			local textHeight = P.measureText(community.invite, { role = "small", width = math.max(1, width - theme.space.md * 2) }).Y
			local height = math.max(responsive.minTarget(), math.max(theme.text.small.height, math.ceil(textHeight)) + theme.space.sm * 2)
			invite.shell.Size = UDim2.new(1, 0, 0, height)
		end
		invite.shell:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitInvite)
		fitInvite()
		P.text(card, { name = "CommunityCopyHint", text = "Open this link in your browser or Discord.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		P.text(modal.content, { name = "CommunityReminderNote", text = "Joining is optional. Reminders appear at most once every two weeks and stop after you copy the invite.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		P.button(modal.content, { name = "CommunityNever", text = "Don't show again", variant = "ghost",
			size = "sm", layoutOrder = 3, onClick = function() community.disable(); modal.close() end })
		P.button(modal.footer, { name = "CommunityLater", text = "Not now", variant = "ghost", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "CommunityCopy", text = "Copy invite", variant = "primary", layoutOrder = 2,
			onClick = function()
				if clipboard.write(community.invite) then
					community.disable()
					modal.close()
					overlay.toast("Discord invite copied. Reminders are off.", "good", 4)
				else
					invite.selectAll()
					overlay.toast("Select and copy the invite above.", "info", 4)
				end
			end })
		return modal
	end

	function M.watch(app)
		local alive, started, lastInput = true, clock.ms(), clock.ms()
		local windowFocused = true
		local connections = {}
		local function activity() lastInput = clock.ms() end
		for _, name in ipairs({ "InputBegan", "InputChanged", "InputEnded" }) do
			connections[#connections + 1] = env.uis[name]:Connect(activity)
		end
		connections[#connections + 1] = env.uis.WindowFocusReleased:Connect(function() windowFocused = false; activity() end)
		connections[#connections + 1] = env.uis.WindowFocused:Connect(function() windowFocused = true; activity() end)
		local unwatchSessions = sessions.listChanged:connect(activity)
		local stop = clock.interval(30, function()
			if not alive or not community.due() then return end
			local now = clock.ms()
			if now - started < 300000 or now - lastInput < 30000 then return end
			if not windowFocused or not app.screen or not app.screen.Parent or app.screen.Enabled == false
				or not app.window or not app.window.visible then activity(); return end
			if app.panel ~= "chat" and app.panel ~= "home" then activity(); return end
			if #overlay.open > 0 or responsive.keyboardHeight > 0 or sessions.busyCount() > 0 then activity(); return end
			local ok, focused = pcall(function() return env.uis:GetFocusedTextBox() end)
			if not ok or focused then activity(); return end
			local composer = env.require("ui/chat/composer")
			if composer.hasDrafts and composer.hasDrafts() then activity(); return end
			local panel = app.chatPanel
			if panel and panel.composer and (panel.composer.field.get():find("%S") or #(panel.composer.attachments or {}) > 0) then activity(); return end
			if panel and panel.view and panel.view.pinned == false then activity(); return end
			local runner = env.loadedModules and env.loadedModules["tools/code_runner"]
			if runner and runner.busy() then activity(); return end
			M.open()
		end)
		return function()
			if not alive then return end
			alive = false
			stop()
			unwatchSessions()
			for _, connection in ipairs(connections) do connection:Disconnect() end
			connections = {}
			if current then current.close(); current = nil end
		end
	end

	return M
end
