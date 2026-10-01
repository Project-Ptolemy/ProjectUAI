-- A quiet, optional invitation. Never mounts UI from a headless runtime.
return function(env)
	local community = env.require("runtime/community")
	local clock = env.require("runtime/clock")
	local caps = env.require("runtime/caps")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local overlay = env.require("ui/overlay")
	local P = env.require("ui/primitives")
	local M = {}
	local current

	function M.open()
		if current and not current.closed then return current end
		local modal = overlay.modal({ title = "Join the Project UAI community",
			description = "Get updates, ask for help, and share what you build.",
			width = theme.size.modalWide, onClose = function() current = nil end })
		if not modal then return nil end
		current = modal
		community.markShown()
		local invite = P.field(modal.content, { name = "CommunityInvite", text = community.invite,
			role = "small", multiline = true, height = responsive.minTarget(), layoutOrder = 1 })
		invite.instance.TextEditable = false
		P.text(modal.content, { name = "CommunityReminderNote", text = "Reminders appear at most once every two weeks. Joining is optional.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		P.button(modal.content, { name = "CommunityNever", text = "Don't show again", variant = "ghost",
			fill = true, layoutOrder = 3, onClick = function() community.disable(); modal.close() end })
		P.button(modal.footer, { name = "CommunityLater", text = "Not now", variant = "ghost", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "CommunityCopy", text = "Copy invite", variant = "primary", layoutOrder = 2,
			onClick = function()
				local ok, value = false, nil
				if caps.fn.clipboard then ok, value = pcall(caps.fn.clipboard, community.invite) end
				if ok and value ~= false then
					community.disable()
					modal.close()
					overlay.toast("Discord invite copied. Reminders are off.", "good", 4)
				else
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
