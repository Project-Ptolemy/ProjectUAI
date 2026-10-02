return function(env)
	local C = env.require("core")
	local motion = env.require("motion")
	local M = {}
	function M.panel(window, options)
		assert(window.Alive, "Window is destroyed")
		options = options or {}
		window:_CloseOverlay()
		window:_CancelCapture()
		window:_ReleaseKeys()
		C.cancelGesture(window)
		local panel = C.owner(window)
		panel.Dismissible, panel.Closed, panel.Control = options.Dismissible ~= false, false, options.Control
		local previous = env.services.GuiService.SelectedObject
		panel.Root = C.node(panel, "Frame", window._viewport, {
			Name = "Overlay", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 100,
		})
		local scrim = C.node(panel, "TextButton", panel.Root, { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundTransparency = options.Anchor and 1 or 0.4, Selectable = false, Modal = true }, { BackgroundColor3 = "Scrim" })
		panel.Frame = C.node(panel, "Frame", panel.Root, { Name = "Panel", Active = true, ClipsDescendants = true, ZIndex = 2 }, { BackgroundColor3 = "Surface" })
		C.corner(panel.Frame, C.tokens.Size.Radius); C.stroke(panel, panel.Frame, "Edge")
		local headerSurface = C.node(panel, "Frame", panel.Frame, { Name = "PanelHeader", Size = UDim2.new(1, 0, 0, 54) }, { BackgroundColor3 = "Chrome" })
		C.corner(headerSurface, C.tokens.Size.Radius)
		C.node(panel, "Frame", headerSurface, { Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(40, 2) }, { BackgroundColor3 = "Accent" })
		pcall(function()
			panel.Frame.SelectionGroup = true
			panel.Frame.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
			panel.Frame.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
			panel.Frame.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
			panel.Frame.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
		end)
		local title = C.text(panel, panel.Frame, options.Title or "", "Title", "Text", {
			Position = UDim2.fromOffset(20, 12), Size = UDim2.new(1, -40 - math.max(window.Target, 64 * window.TextScale), 0, 32), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local close = C.node(panel, "TextButton", panel.Frame, { Name = "Dismiss", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(window.Target, window.Target), Visible = panel.Dismissible })
		close.Size = UDim2.fromOffset(math.max(window.Target, 64 * window.TextScale), window.Target)
		C.corner(close); C.feedback(panel, close)
		C.text(panel, close, "Close", "Caption", "Secondary", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		panel.Body = C.scroll(panel, panel.Frame, "Body")
		C.pad(panel.Body, 20, 8); C.list(panel.Body, false, 12)
		panel.Actions = C.scroll(panel, panel.Frame, "Actions")
		panel.Actions.ScrollBarThickness = 0
		C.footer(panel, panel.Frame)
		function panel:Close()
			if self.Closed then return end
			self.Closed = true
			C.releaseFocus(window, self.Root)
			if window._overlay == self then window._overlay = nil end
			C.cancelGesture(window, self)
			self._scope:Destroy()
			self.Root:Destroy()
			pcall(function()
				env.services.GuiService.SelectedObject = previous and previous.Parent and previous or nil
			end)
			C.call(window, options.OnClose)
		end
		function panel:Focus(node)
			if previous then pcall(function() env.services.GuiService.SelectedObject = node end) end
		end
		panel._scope:Connect(scrim.Activated, function() if panel.Dismissible then panel:Close() end end)
		panel._scope:Connect(close.Activated, function() panel:Close() end)
		panel._scope:Add(function() if window._overlay == panel then window._overlay = nil end end)
		window._overlay = panel
		C.reflow(panel, function()
			local rect = window._rect
			scrim.BackgroundTransparency = options.Anchor and not window._compact and 1 or 0.4
			local width = math.min(C.number(options.Width, 440, 160, 1200), rect.width)
			local height = math.min(C.number(options.Height, 320, 120, 1200), rect.height)
			local header = math.max(54, window.Target + 12)
			headerSurface.Size = UDim2.new(1, 0, 0, header)
			local actionHeight = options.Actions and window.Target or 0
			if panel.LayoutActions then actionHeight = panel.LayoutActions(width) end
			if window.Touch and actionHeight > window.Target then
				height = math.min(rect.height, math.max(height, header + 30 + actionHeight + 20 + window.Target + 16))
			end
			local inlineActions = window.Touch and options.Actions and height - header - 30 - actionHeight - 20 < window.Target + 16
			local x, y = rect.x + (rect.width - width) / 2, rect.y + (rect.height - height) / 2
			if options.Anchor and not window._compact then
				local anchor, origin = options.Anchor, window._viewport.AbsolutePosition
				x = C.clamp(anchor.AbsolutePosition.X - origin.X, rect.x, rect.x + rect.width - width)
				y = anchor.AbsolutePosition.Y - origin.Y + anchor.AbsoluteSize.Y + 6
				if y + height > rect.y + rect.height then y = anchor.AbsolutePosition.Y - origin.Y - height - 6 end
				y = C.clamp(y, rect.y, rect.y + rect.height - height)
			end
			panel.Width, panel.Height = width, height
			panel.Frame.Position, panel.Frame.Size = UDim2.fromOffset(math.floor(x), math.floor(y)), UDim2.fromOffset(width, height)
			local actions = options.Actions and not inlineActions and actionHeight + 20 or 0
			local closeWidth = math.max(window.Target, 64 * window.TextScale)
			close.Size = UDim2.fromOffset(closeWidth, window.Target)
			title.Size = UDim2.new(1, -(panel.Dismissible and (40 + closeWidth) or 40), 0, math.max(32, 22 * window.TextScale))
			panel.HeaderHeight = header
			panel.Body.Position = UDim2.fromOffset(0, header)
			panel.Body.Size = UDim2.fromOffset(width, math.max(0, height - header - 30 - actions))
			panel.InlineActions = inlineActions == true
			panel.Actions.Parent = inlineActions and panel.Body or panel.Frame
			panel.Actions.LayoutOrder = 10000
			panel.Actions.Position = inlineActions and UDim2.fromOffset(0, 0) or UDim2.new(0, 20, 1, -30 - actions + 8)
			panel.Actions.Size = UDim2.new(1, inlineActions and 0 or -40, 0, actionHeight)
			panel.Actions.ScrollingEnabled = not inlineActions
			panel.Actions.Visible = options.Actions == true
			if panel.OnLayout then panel.OnLayout(width, height) end
		end)
		panel:Focus(close)
		motion.reveal(panel, panel.Frame)
		return panel
	end
	function M.dialog(window, options)
		options = options or {}
		local buttons = options.Buttons or { { Text = "Done", Style = "Primary" } }
		assert(type(buttons) == "table" and #buttons > 0 and #buttons <= 4, "Dialog expects 1-4 buttons")
		for _, spec in ipairs(buttons) do
			assert(type(spec) == "table" and (spec.Callback == nil or type(spec.Callback) == "function"), "Dialog buttons must be records with optional callbacks")
		end
		local panel = M.panel(window, { Title = options.Title or "Project UAI", Height = options.Height or 300, Width = options.Width, Dismissible = options.Dismissible, Actions = true })
		local content = C.text(panel, panel.Body, options.Content or "", "Body", "Secondary", {
			Name = "Message", TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 0,
		})
		local actions = {}
		for index, spec in ipairs(buttons) do
			local button = C.node(panel, "TextButton", panel.Actions, { Name = "DialogAction_" .. index, LayoutOrder = index })
			C.corner(button); C.feedback(panel, button, spec.Style)
			C.text(panel, button, spec.Text or "Done", "Body", (spec.Style == "Primary" or spec.Style == "Danger") and "OnPrimary" or "Text", {
				Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Center,
			})
			panel._scope:Connect(button.Activated, function()
				panel:Close()
				if window.Alive then window._scope:Spawn(function() C.call(window, spec.Callback) end) end
			end)
			actions[#actions + 1] = button
		end
		panel.LayoutActions = function(width)
			local columns = #actions
			if window.Touch then columns = math.max(1, math.min(#actions, math.floor((width - 32) / (112 * window.TextScale + 8)))) end
			local cellWidth = math.max(1, (width - 40 - (columns - 1) * 8) / columns)
			local rowHeight = window.Target
			if window.Touch then
				for _, spec in ipairs(buttons) do
					rowHeight = math.max(rowHeight, math.min(window.Target * 2, C.measure(spec.Text or "Done", 14 * window.TextScale, cellWidth - 16) + 16))
				end
			end
			for index, button in ipairs(actions) do
				button.Size = UDim2.fromOffset(cellWidth, rowHeight)
				button.Position = UDim2.fromOffset(((index - 1) % columns) * (cellWidth + 8), math.floor((index - 1) / columns) * (rowHeight + 8))
			end
			return math.ceil(#actions / columns) * (rowHeight + 8) - 8
		end
		panel.OnLayout = function(width)
			content.Size = UDim2.new(1, 0, 0, C.measure(content.Text, 14 * window.TextScale, width - 40))
		end
		window:_Layout()
		panel:Focus(actions[#actions])
		return panel
	end
	local function fitToasts(window)
		local remaining = window._toastHost.Size.Y.Offset
		for index = #window._toasts, 1, -1 do
			local toast = window._toasts[index]
			local height = toast.Frame.Size.Y.Offset
			toast.Frame.LayoutOrder = index
			toast.Frame.Visible = height <= remaining
			if toast.Frame.Visible then remaining = remaining - height - 8 end
		end
	end
	function M.notify(window, options)
		if not window.Alive then return nil end
		options = type(options) == "string" and { Content = options } or options or {}
		assert(options.Action == nil or (type(options.Action) == "table" and (options.Action.Callback == nil or type(options.Action.Callback) == "function")), "Notification Action must be a record with an optional callback")
		local toast = C.owner(window)
		toast.Closed = false
		toast._scope:Add(function() toast.Closed = true end)
		toast.Frame = C.node(toast, "Frame", window._toastHost, { Name = "Notification", ClipsDescendants = true, Size = UDim2.new(1, 0, 0, 100), LayoutOrder = #window._toasts + 1 }, { BackgroundColor3 = "Surface" })
		C.corner(toast.Frame, 14); C.stroke(toast, toast.Frame, "Edge")
		local kind = ({ Success = "Success", Warning = "Warning", Danger = "Danger", Info = "Accent" })[options.Kind] or "Accent"
		local status = C.node(toast, "Frame", toast.Frame, { Position = UDim2.fromOffset(16, 19), Size = UDim2.fromOffset(6, 6) }, { BackgroundColor3 = kind })
		C.corner(status, 3)
		local title = C.text(toast, toast.Frame, C.truncate(tostring(options.Title or "Project UAI"), 240), "Heading", "Text", { Position = UDim2.fromOffset(32, 12), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local body = C.text(toast, toast.Frame, C.truncate(tostring(options.Content or ""), 800), "Caption", "Secondary", { Name = "Message", Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd })
		local close = C.node(toast, "TextButton", toast.Frame, { Name = "Dismiss", BackgroundTransparency = 1, Position = UDim2.new(1, -window.Target, 0, 2), Size = UDim2.fromOffset(window.Target, window.Target) })
		C.text(toast, close, "Dismiss", "Small", "Muted", { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false })
		function toast:Close()
			if self.Closed then return end
			self.Closed = true
			for index, item in ipairs(window._toasts) do if item == self then table.remove(window._toasts, index); break end end
			self._scope:Destroy()
			self.Frame:Destroy()
			if window.Alive then fitToasts(window) end
		end
		toast._scope:Connect(toast.Frame.Destroying, function() toast:Close() end)
		toast._scope:Connect(close.Activated, function() toast:Close() end)
		local action
		if options.Action then
			action = C.node(toast, "TextButton", toast.Frame, { Name = "NotificationAction", Position = UDim2.new(0, 16, 1, -window.Target - 12), Size = UDim2.new(1, -32, 0, window.Target) })
			C.corner(action); C.feedback(toast, action)
			C.text(toast, action, options.Action.Text or "Open", "Caption", "Text", { Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
			toast._scope:Connect(action.Activated, function()
				toast:Close()
				if window.Alive then window._scope:Spawn(function() C.call(window, options.Action.Callback) end) end
			end)
		end
		window._toasts[#window._toasts + 1] = toast
		if window._PulseLauncher then window:_PulseLauncher() end
		C.reflow(toast, function()
			local width, available = window._toastHost.Size.X.Offset, window._toastHost.Size.Y.Offset
			local titleHeight = math.ceil(20 * window.TextScale)
			status.Position = UDim2.fromOffset(16, 12 + math.floor((titleHeight - 6) / 2))
			local headerHeight = math.max(titleHeight + 32, window.Target + 4)
			local actionHeight = action and window.Target + 12 or 0
			if headerHeight + actionHeight > available then actionHeight = 0 end
			local bodyHeight = body.Text == "" and 0 or math.min(120, math.max(0, available - headerHeight - actionHeight), C.measure(body.Text, 12 * window.TextScale, width - 32))
			local dismissWidth = math.max(window.Target, 64 * window.TextScale)
			title.Size = UDim2.new(1, -dismissWidth - 40, 0, titleHeight)
			body.Position = UDim2.fromOffset(16, headerHeight - 14)
			body.Size = UDim2.new(1, -32, 0, bodyHeight)
			body.Visible = bodyHeight > 0
			close.Position, close.Size = UDim2.new(1, -dismissWidth, 0, 2), UDim2.fromOffset(dismissWidth, window.Target)
			if action then
				action.Visible = actionHeight > 0
				action.Position, action.Size = UDim2.new(0, 16, 1, -window.Target - 12), UDim2.new(1, -32, 0, window.Target)
			end
			toast.Frame.Size = UDim2.new(1, 0, 0, math.min(available, headerHeight + bodyHeight + actionHeight))
			fitToasts(window)
		end)
		while #window._toasts > 3 do window._toasts[1]:Close() end
		local duration = C.number(options.Duration, 5, 0, 60)
		if duration > 0 then toast._scope:Delay(duration, function() toast:Close() end) end
		motion.reveal(toast, toast.Frame)
		return toast
	end
	return M
end
