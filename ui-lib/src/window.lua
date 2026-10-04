return function(env)
	local C = env.require("core")
	local T = env.require("theme")
	local motion = env.require("motion")
	local Window = {}
	Window.__index = Window
	local function parentScreen(screen, requested)
		if requested then
			assert(typeof(requested) == "Instance", "Parent must be a Roblox instance")
			screen.Parent = requested
			return
		end
		if type(gethui) == "function" then
			local ok, parent = pcall(gethui)
			if ok and parent and pcall(function() screen.Parent = parent end) then return end
		end
		if pcall(function() screen.Parent = env.services.CoreGui end) then return end
		local player = env.services.Players.LocalPlayer
		assert(player, "UI LIB requires a local player or an explicit Parent")
		screen.Parent = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 10)
		assert(screen.Parent, "UI LIB could not find PlayerGui")
	end
	function Window:Give(resource) return self._scope:Add(resource) end
	function Window:OnDestroy(callback) return self:Give(callback) end
	function Window:Get(id) return self.Controls[id] end
	function Window:Tab(options) return env.require("containers").tab(self, options) end
	function Window:Notify(options) return env.require("overlays").notify(self, options) end
	function Window:Dialog(options) return env.require("overlays").dialog(self, options) end
	function Window:Confirm(options)
		options = options or {}
		return self:Dialog({
			Title = options.Title or "Confirm action", Content = options.Content,
			Buttons = {
				{ Text = options.CancelText or "Cancel" },
				{ Text = options.ConfirmText or "Confirm", Style = options.Danger and "Danger" or "Primary", Callback = options.Callback },
			},
		})
	end
	function Window:_CloseOverlay()
		if self._overlay then self._overlay:Close() end
	end
	function Window:_Refresh(animated)
		if not self.Alive then return end
		if not animated then motion.stopAll(self, true) end
		for binding in pairs(self._paint) do
			if binding.node.Parent then
				local goals = {}
				for key, value in pairs(binding.properties) do
					local resolved
					if type(value) == "function" then resolved = value(self.Theme) else resolved = self.Theme[value] end
					if animated and (key:find("Color", 1, true) or key:find("Transparency", 1, true)) then goals[key] = resolved
					else binding.node[key] = resolved end
				end
				if next(goals) then motion.to(binding.owner, binding.node, goals) end
			end
		end
	end
	function Window:SetReducedMotion(value)
		assert(type(value) == "boolean", "ReducedMotion must be a boolean")
		self._motionOverride, self.ReducedMotion = value, value
		motion.stopAll(self, true)
		return self
	end
	function Window:SetTheme(name, accent)
		self.Theme = T.resolve(name, accent)
		self._themeName, self._accent = name or "Dark", accent
		if self._themeLabel then self._themeLabel.Text = self._themeName == "Dark" and "Light mode" or "Dark mode" end
		self:_Refresh()
		return self
	end
	function Window:GetTheme() return self._themeName, self._accent end
	function Window:ToggleTheme()
		return self:SetTheme(self._themeName == "Dark" and "Light" or "Dark", self._accent)
	end
	function Window:SetTextScale(value)
		assert(C.finite(value), "TextScale must be a finite number")
		self.TextScale = C.clamp(value, 0.85, 1.5)
		self:_Refresh()
		self:_Layout()
		return self
	end
	function Window:SetTitle(title, subtitle)
		assert(self.Alive, "Window is destroyed")
		self.Title = tostring(title)
		self._title.Text, self._launcherTitle.Text = self.Title, self.Title
		if subtitle ~= nil then
			self._subtitle.Text = tostring(subtitle)
			self._launcherDetail.Text = self._subtitle.Text ~= "" and self._subtitle.Text or "Minimized"
		end
		self:_Layout()
		return self
	end
	function Window:_ReleaseKeys()
		for binding in pairs(self._keys) do if binding.release then binding.release() end end
	end
	function Window:_CancelCapture()
		if self._captureControl then self._captureControl:_CancelInteraction() end
		self._capture, self._captureControl = nil, nil
	end
	function Window:Show()
		if not self.Alive or self.Visible then return self end
		motion.stopAll(self, true)
		self.Visible = true
		self.Frame.Visible, self._launcher.Visible = true, false
		self._launcherDetail.Text = self._subtitle.Text ~= "" and self._subtitle.Text or "Minimized"
		self:_Layout()
		motion.reveal(self, self.Frame)
		return self
	end
	function Window:Hide()
		if not self.Alive then return self end
		C.releaseFocus(self)
		self:_CloseOverlay()
		self:_CancelCapture()
		self:_ReleaseKeys()
		C.cancelGesture(self)
		for release in pairs(self._presses) do release() end
		motion.stopAll(self, true)
		self.Visible = false
		self.Frame.Visible, self._launcher.Visible = false, false
		pcall(function()
			local selected = env.services.GuiService.SelectedObject
			if selected and selected:IsDescendantOf(self.ScreenGui) then env.services.GuiService.SelectedObject = nil end
		end)
		return self
	end
	function Window:_PopLauncher()
		motion.reveal(self, self._launcher)
	end
	-- A notification that arrives while the window is minimized nudges the
	-- launcher instead of being silent: the pill is visible, but nothing else
	-- says new content is waiting there.
	function Window:_PulseLauncher()
		if not self._launcher.Visible then return end
		self._launcherDetail.Text = "New notification"
		self._launcherStroke.Color = self.Theme.Accent
		motion.to(self, self._launcherStroke, { Color = self._launcherHovered and self.Theme.Accent or self.Theme.Border }, T.Motion.Enter)
	end
	function Window:Minimize()
		if not self.Alive or not self.Visible then return self end
		self:Hide()
		if self.Alive then
			self._launcher.Visible = true
			self:_PopLauncher()
		end
		return self
	end
	function Window:Toggle()
		if self.Visible then return self:Minimize() end
		return self:Show()
	end
	function Window:Destroy()
		if not self.Alive then return end
		C.releaseFocus(self)
		self:_CloseOverlay()
		self:_CancelCapture()
		self:_ReleaseKeys()
		motion.stopAll(self, true)
		self.Alive, self.Visible = false, false
		C.cancelGesture(self)
		self._capture = nil
		if env.windows[self.Id] == self then env.windows[self.Id] = nil end
		self._scope:Destroy()
		self.ScreenGui:Destroy()
		self.Controls, self.Tabs, self._toasts = {}, {}, {}
	end
	function Window:SelectTab(target)
		local tab = target
		if type(target) == "string" then
			tab = nil
			for _, candidate in ipairs(self.Tabs) do
				if candidate.Id == target then tab = candidate; break end
			end
		end
		assert(tab and tab._window == self and tab.Alive, "Unknown tab")
		if not tab.Visible then return self end
		if self._activeTab == tab then return self end
		local previous = self._activeTab
		if previous then C.releaseFocus(self, previous.Frame) end
		self:_CloseOverlay()
		self:_CancelCapture()
		self:_ReleaseKeys()
		C.cancelGesture(self)
		self._activeTab = tab
		for _, candidate in ipairs(self.Tabs) do candidate.Frame.Visible = candidate == tab and candidate.Visible end
		if previous then previous._refresh() end
		tab._refresh()
		self:_Filter()
		if previous then motion.reveal(self, self._content, self.Theme.Canvas, 14) end
		return self
	end
	function Window:_Filter()
		local query = string.lower(self._search and self._search.Text or "")
		local count = 0
		for _, tab in ipairs(self.Tabs) do
			local tabCount, sectionCount = 0, 0
			for _, section in ipairs(tab.Sections) do
				local matches = 0
				for _, control in ipairs(section.Controls) do
					local haystack = string.lower(control.Text .. " " .. control.Description .. " " .. section.Title)
					local visible = control.Visible and (query == "" or haystack:find(query, 1, true) ~= nil)
					control.Frame.Visible = visible
					if visible then matches = matches + 1 end
				end
				section.Frame.Visible = section.Visible and (matches > 0 or query == "")
				section._body.Visible = not section.Collapsed or query ~= ""
				if section.Visible then
					tabCount = tabCount + matches
					if section.Frame.Visible then sectionCount = sectionCount + 1 end
				end
			end
			if tab == self._activeTab then count = tabCount end
			if tab._summary then
				tab._intro.Visible = query == "" or tabCount > 0
				tab._summary.Text = query ~= "" and string.format("%d matching control%s", tabCount, tabCount == 1 and "" or "s")
					or string.format("%d control%s  /  %d section%s", tabCount, tabCount == 1 and "" or "s", sectionCount, sectionCount == 1 and "" or "s")
			end
		end
		self._empty.Visible = query ~= "" and count == 0
	end
	function Window:_RevealFocused()
		local focused = env.services.UserInputService:GetFocusedTextBox()
		if not focused or not focused:IsDescendantOf(self.ScreenGui) then return end
		local ancestor = focused.Parent
		while ancestor and ancestor ~= self.ScreenGui do
			if ancestor:IsA("ScrollingFrame") then
				local top = focused.AbsolutePosition.Y - ancestor.AbsolutePosition.Y
				local bottom = top + focused.AbsoluteSize.Y
				local height = ancestor.AbsoluteSize.Y
				local y = ancestor.CanvasPosition.Y
				if focused.AbsoluteSize.Y > height - 16 then
					-- A multiline field may be taller than the keyboard-safe view.
					-- Reveal its editing line rather than alternately jumping to
					-- opposite ends of an impossible-to-fit field.
					local lineTop = 0
					if focused.MultiLine and focused.CursorPosition > 0 then
						local before = focused.Text:sub(1, focused.CursorPosition - 1)
						lineTop = math.max(0, C.measure(before, focused.TextSize, focused.AbsoluteSize.X - 24) - focused.TextSize) + 10
					end
					local lineBottom = top + lineTop + focused.TextSize + 8
					if top + lineTop < 8 then y = y + top + lineTop - 8
					elseif lineBottom > height - 8 then y = y + lineBottom - height + 8 end
				elseif top < 8 then y = y + top - 8
				elseif bottom > height - 8 then y = y + bottom - height + 8 end
				ancestor.CanvasPosition = Vector2.new(ancestor.CanvasPosition.X, math.max(0, y))
			end
			ancestor = ancestor.Parent
		end
	end
	function Window:_Layout()
		if not self.Alive then return end
		local uis = env.services.UserInputService
		self.Touch = uis.TouchEnabled == true
		self.Target = math.max(self.Touch and T.Size.TouchTarget or T.Size.Target, math.ceil(36 * self.TextScale))
		local size, origin = self._viewport.AbsoluteSize, self._viewport.AbsolutePosition
		if size.X < 1 or size.Y < 1 then
			local camera = env.services.Workspace.CurrentCamera
			size = camera and camera.ViewportSize or Vector2.new(800, 600)
		end
		local availableHeight, keyboardVisible = size.Y, false
		pcall(function()
			if uis.OnScreenKeyboardVisible then
				keyboardVisible = true
				local keyboard = uis.OnScreenKeyboardSize
				local top = uis.OnScreenKeyboardPosition.Y
				availableHeight = top > 0 and math.min(size.Y, top - origin.Y) or size.Y - keyboard.Y
			end
		end)
		availableHeight = math.max(1, availableHeight)
		local margin = math.min(self.Touch and 8 or 16, size.X / 10, availableHeight / 10)
		local width = math.max(1, math.min(self._requestedWidth, size.X - margin * 2))
		local height = math.max(1, math.min(self._requestedHeight, availableHeight - margin * 2))
		if self.Touch and width < T.Size.Compact and self._autoHeight then height = math.max(1, availableHeight - margin * 2) end
		local x = self._position and self._position.X or (size.X - width) / 2
		local y = self._position and self._position.Y or (availableHeight - height) / 2
		x = C.clamp(x, margin, math.max(margin, size.X - width - margin))
		y = C.clamp(y, margin, math.max(margin, availableHeight - height - margin))
		self._rect = { x = margin, y = margin, width = math.max(1, size.X - margin * 2), height = math.max(1, availableHeight - margin * 2) }
		if self.Touch and (self._width ~= width or self._height ~= height) then C.cancelGesture(self) end
		self._width, self._height = width, height
		local short = height < (self.Touch and 440 or 380)
		self._compact = width < T.Size.Compact or short
		self._contentPad = self.Touch and self._compact and T.Size.MobilePad or T.Size.Pad
		local titleHeight = math.ceil(26 * self.TextScale)
		local subtitleHeight = math.ceil(18 * self.TextScale)
		local header = short and math.max(52, self.Target + 8) or math.max(T.Size.Header, 14 + titleHeight + 3 + subtitleHeight + 12)
		local nav = self._compact and math.max(T.Size.Tabs, self.Target + 8) or 0
		local sidebar = self._compact and 0 or math.floor(T.Size.Sidebar * math.min(1.28, self.TextScale))
		local railHeading = self._compact and 0 or 32
		local searchFocused = self._search and uis:GetFocusedTextBox() == self._search
		local searchVisible = self._search and (searchFocused or (height >= 300 and not (self.Touch and keyboardVisible)))
		local search = searchVisible and self.Target + 12 or 0
		local footer = T.Size.Footer
		local themeHeight = self._themeToggle and not self._compact and (self.Target + 12) or 0
		local themeWidth = self._themeToggle and math.max(96, math.ceil(78 * self.TextScale + 20)) or 0
		if self._compact and height < 240 then nav = 0 end
		if height < header + footer + self.Target then header = 0 end
		self.Frame.Size = UDim2.fromOffset(math.floor(width), math.floor(height))
		self.Frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
		self._header.Size = UDim2.new(1, 0, 0, header)
		self._header.Visible = header > 0
		-- The mark sits beside the title when there is room for both to read;
		-- the title keeps its old inset when it is hidden, so only extremely
		-- narrow layouts lose the logo before they lose their name.
		local brand = math.min(22, math.max(14, math.floor(18 * self.TextScale)))
		self._brand.Size = UDim2.fromOffset(brand, brand)
		self._brand.Position = UDim2.fromOffset(26, math.floor((header - brand) / 2))
		self._brand.Visible = header > 0 and width >= 300
		self._brandTile.Visible = self._brand.Visible
		self._brandTile.Position = UDim2.fromOffset(18, math.floor((header - brand) / 2) - 8)
		self._brandTile.Size = UDim2.fromOffset(brand + 16, brand + 16)
		local titleInset = self._brand.Visible and (26 + brand + 20) or 20
		self._title.Position = UDim2.fromOffset(titleInset, short and 12 or 14)
		self._title.Size = UDim2.new(1, -(titleInset + self.Target * 2 + 32), 0, titleHeight)
		self._subtitle.Visible = not short and self._subtitle.Text ~= ""
		self._subtitle.Position = UDim2.fromOffset(titleInset, 17 + titleHeight)
		self._subtitle.Size = UDim2.new(1, -(titleInset + self.Target * 2 + 32), 0, subtitleHeight)
		self._headerActions.Position = UDim2.new(1, -self.Target * 2 - 20, 0, (header - self.Target) / 2)
		self._headerActions.Size = UDim2.fromOffset(self.Target * 2 + 4, self.Target)
		self._minimize.Size, self._close.Size = UDim2.fromOffset(self.Target, self.Target), UDim2.fromOffset(self.Target, self.Target)
		local profileHeight = 0
		if self._profile then
			profileHeight = self._profile.Layout(sidebar)
			self._profile.Frame.Visible = not self._compact
			self._profile.Frame.Position = UDim2.new(0, 0, 1, -footer - profileHeight)
			if self._compact then profileHeight = 0 end
		end
		self._rail.Position = UDim2.fromOffset(0, header)
		self._rail.Size = UDim2.fromOffset(sidebar, math.max(0, height - header - footer))
		self._rail.Visible = not self._compact
		self._navCaption.Position = UDim2.fromOffset(20, header + 12)
		self._navCaption.Size = UDim2.fromOffset(math.max(0, sidebar - 40), 14 * self.TextScale)
		self._navCaption.Visible = not self._compact
		self._nav.Position = UDim2.fromOffset(0, header + railHeading)
		self._nav.Visible = not self._compact or nav > 0
		self._nav.Size = self._compact and UDim2.new(1, self._themeToggle and -themeWidth - 12 or 0, 0, nav)
			or UDim2.new(0, sidebar, 1, -header - railHeading - footer - profileHeight - themeHeight)
		if self._themeToggle then
			self._themeToggle.Visible = not self._compact or nav > 0
			self._themeToggle.Size = UDim2.fromOffset(self._compact and themeWidth or sidebar - 24, self.Target)
			self._themeToggle.Position = self._compact and UDim2.new(1, -themeWidth - 12, 0, header + 4)
				or UDim2.new(0, 12, 1, -footer - profileHeight - themeHeight)
		end
		self._navLayout.FillDirection = self._compact and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
		self._nav.ScrollingDirection = self._compact and Enum.ScrollingDirection.X or Enum.ScrollingDirection.Y
		self._nav.AutomaticCanvasSize = self._compact and Enum.AutomaticSize.X or Enum.AutomaticSize.Y
		self._nav.ScrollBarThickness = self._compact and 0 or T.Size.Scrollbar
		self._navPad.PaddingTop = UDim.new(0, self._compact and 4 or 10)
		for _, tab in ipairs(self.Tabs) do
			local tabWidth = self._compact and math.max(80, math.min(220, #tab.Title * 8 * self.TextScale + 28)) or sidebar - 24
			tab._button.Size = UDim2.fromOffset(tabWidth, self.Target)
		end
		local top = header + nav
		local inset = self._compact and 6 or 10
		self._contentWidth = math.max(1, width - sidebar - inset * 2)
		self._workspace.Position = UDim2.fromOffset(sidebar + inset, top + 6)
		self._workspace.Size = UDim2.fromOffset(self._contentWidth, math.max(0, height - top - footer - 12))
		self._content.Position = UDim2.fromOffset(sidebar + inset, top + 6 + search)
		self._content.Size = UDim2.fromOffset(self._contentWidth, math.max(0, height - top - search - footer - 12))
		if self._search then
			self._search.Visible = searchVisible == true
			self._search.Position = UDim2.fromOffset(sidebar + inset + self._contentPad, top + 14)
			self._search.Size = UDim2.fromOffset(math.max(1, self._contentWidth - self._contentPad * 2), self.Target)
		end
		self._resize.Visible = not self.Touch
		-- The restore pill: title and a status line over the permanent
		-- attribution. Its height follows the text scale, it remembers where it
		-- was dragged, and it is clamped back into view on every reflow.
		local launcherTitle = math.ceil(15 * self.TextScale)
		local launcherDetail = math.ceil(12 * self.TextScale)
		local launcherBody = launcherTitle + launcherDetail + 16
		local launcherHeight = launcherBody + T.Size.Footer
		local launcherWidth = math.min(264, size.X - margin * 2)
		local placeX = self._launcherPosition and self._launcherPosition.X or margin
		local placeY = self._launcherPosition and self._launcherPosition.Y or (availableHeight - launcherHeight - margin)
		placeX = C.clamp(placeX, margin, math.max(margin, size.X - launcherWidth - margin))
		placeY = C.clamp(placeY, margin, math.max(margin, availableHeight - launcherHeight - margin))
		self._launcher.Position = UDim2.fromOffset(math.floor(placeX), math.floor(placeY))
		self._launcher.Size = UDim2.fromOffset(math.floor(launcherWidth), math.floor(launcherHeight))
		local launcherMark = math.min(24, launcherBody - 8)
		self._launcherBrand.Size = UDim2.fromOffset(launcherMark, launcherMark)
		self._launcherBrand.Position = UDim2.fromOffset(14, math.floor((launcherBody - launcherMark) / 2))
		local launcherText = 14 + launcherMark + 10
		local launcherTop = math.max(4, math.floor((launcherBody - launcherTitle - launcherDetail) / 2))
		self._launcherTitle.Position = UDim2.fromOffset(launcherText, launcherTop)
		self._launcherTitle.Size = UDim2.new(1, -(launcherText + 64), 0, launcherTitle)
		self._launcherDetail.Position = UDim2.fromOffset(launcherText, launcherTop + launcherTitle + 2)
		self._launcherDetail.Size = UDim2.new(1, -(launcherText + 64), 0, launcherDetail)
		self._launcherHint.Position = UDim2.new(1, -12, 0, math.floor(launcherBody / 2))
		self._toastHost.Position = UDim2.new(1, -margin, 1, -margin - (size.Y - availableHeight))
		self._toastHost.Size = UDim2.fromOffset(math.min(360, size.X - margin * 2), math.max(1, availableHeight - margin * 2))
		for callback in pairs(self._reflow) do callback() end
	end
	function Window:_Move(frame, position)
		local rect = self._rect
		local width, height = frame.Size.X.Offset, frame.Size.Y.Offset
		frame.Position = UDim2.fromOffset(math.floor(C.clamp(position.X, rect.x, math.max(rect.x, rect.x + rect.width - width))),
			math.floor(C.clamp(position.Y, rect.y, math.max(rect.y, rect.y + rect.height - height))))
	end
	function Window.new(options)
		options = options or {}
		local id = options.Id or options.Title or "project-uai"
		assert(type(id) == "string" and #id > 0 and #id <= 100, "Window Id must contain 1-100 characters")
		local theme = T.resolve(options.Theme, options.Accent)
		if options.Parent ~= nil then assert(typeof(options.Parent) == "Instance", "Parent must be a Roblox instance") end
		if options.ToggleKey ~= nil and options.ToggleKey ~= false then
			assert(typeof(options.ToggleKey) == "EnumItem" and tostring(options.ToggleKey):find("Enum.KeyCode.", 1, true) == 1, "ToggleKey must be an Enum.KeyCode or false")
		end
		assert(options.ReducedMotion == nil or type(options.ReducedMotion) == "boolean", "ReducedMotion must be a boolean")
		assert(options.ThemeToggle == nil or type(options.ThemeToggle) == "boolean", "ThemeToggle must be a boolean")
		assert(options.GameName == nil or type(options.GameName) == "string", "GameName must be a string")
		local toggleKey = options.ToggleKey
		if toggleKey == nil then toggleKey = Enum.KeyCode.RightShift end
		if env.windows[id] then env.windows[id]:Destroy() end
		local self = setmetatable({
			Id = id, Title = tostring(options.Title or "Project UAI"), Alive = true, Visible = true,
			Theme = theme, TextScale = C.number(options.TextScale, 1, 0.85, 1.5),
			_themeName = options.Theme or "Dark", _accent = options.Accent,
			_scope = C.scope(), _paint = {}, _paintNodes = {}, _reflow = {}, _keys = {}, _motions = {}, _presses = {}, Controls = {}, Tabs = {}, _toasts = {},
			ReducedMotion = options.ReducedMotion == true, _motionOverride = options.ReducedMotion,
			_requestedWidth = C.number(options.Width, T.Size.Width, 280, 1600),
			_requestedHeight = C.number(options.Height, T.Size.Height, 240, 1200),
			_autoHeight = options.Height == nil,
			ToggleKey = toggleKey,
		}, Window)
		self._window = self
		self.ScreenGui = Instance.new("ScreenGui")
		self.ScreenGui.Name = "ProjectUAI_UI_" .. id
		self.ScreenGui.ResetOnSpawn = false
		self.ScreenGui.IgnoreGuiInset = false
		self.ScreenGui.DisplayOrder = C.number(options.DisplayOrder, 80, 0, 10000)
		self.ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		pcall(function() self.ScreenGui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets end)
		local ok, why = pcall(parentScreen, self.ScreenGui, options.Parent)
		if not ok then self.ScreenGui:Destroy(); error(why, 0) end
		self._viewport = C.node(self, "Frame", self.ScreenGui, { Name = "SafeViewport", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
		self.Frame = C.node(self, "Frame", self._viewport, { Name = "Window", Active = true, ClipsDescendants = true }, { BackgroundColor3 = "Chrome" })
		C.corner(self.Frame, T.Size.Radius)
		C.stroke(self, self.Frame, "Edge")
		self._header = C.node(self, "Frame", self.Frame, { Name = "Header", BackgroundTransparency = 1, Active = true })
		self._brandTile = C.node(self, "Frame", self._header, { Name = "BrandTile" }, { BackgroundColor3 = "AccentSoft" })
		C.corner(self._brandTile, 12)
		C.stroke(self, self._brandTile, "Subtle")
		self._brand = C.mark(self, self._header, 18)
		self._title = C.text(self, self._header, self.Title, "Title", "Text", { TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		self._subtitle = C.text(self, self._header, options.Subtitle or "", "Caption", "Muted", { TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		self._headerActions = C.node(self, "Frame", self._header, { BackgroundTransparency = 1 })
		C.list(self._headerActions, true, 4)
		-- Window controls sit directly on the header with no resting fill: the
		-- glyph is the control. Hover and gamepad selection brighten that glyph
		-- instead of painting a tile behind it, and Close warms to the danger
		-- tone rather than shouting in red until it is pointed at.
		local function headerButton(name, icon, callback, tone)
			local button = C.node(self, "TextButton", self._headerActions, { Name = name, BackgroundTransparency = 1 })
			C.corner(button)
			local hovered, selected = false, false
			local function glyphColor(theme)
				if selected then return theme.Text end
				if hovered then return (tone == "Danger") and theme.Danger or theme.Text end
				return theme.Muted
			end
			local glyph = C.icon(self, button, icon, glyphColor)
			glyph.AnchorPoint, glyph.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5)
			local focus = C.stroke(self, button, "Accent"); focus.Transparency = 1
			local function repaint()
				local color = glyphColor(self.Theme)
				for _, line in ipairs(glyph:GetChildren()) do
					if line:IsA("Frame") then motion.to(self, line, { BackgroundColor3 = color }) end
				end
				motion.to(self, focus, { Transparency = selected and 0 or 1 })
			end
			self._scope:Connect(button.MouseEnter, function() hovered = true; repaint() end)
			self._scope:Connect(button.MouseLeave, function() hovered = false; repaint() end)
			self._scope:Connect(button.SelectionGained, function() selected = true; repaint() end)
			self._scope:Connect(button.SelectionLost, function() selected = false; repaint() end)
			self._scope:Connect(button.Activated, callback)
			return button
		end
		self._minimize = headerButton("Minimize", "minus", function() self:Minimize() end)
		self._close = headerButton("Close", "close", function() self:Destroy() end, "Danger")
		self._rail = C.node(self, "Frame", self.Frame, { Name = "NavigationRail" }, { BackgroundColor3 = "Sidebar" })
		self._navCaption = C.text(self, self.Frame, "NAVIGATION", "Eyebrow", "Muted", { TextWrapped = false })
		self._nav = C.scroll(self, self.Frame, "Tabs")
		C.bind(self, self._nav, { BackgroundColor3 = "Sidebar" })
		self._nav.BackgroundTransparency = 0
		self._navLayout = C.list(self._nav, false, 6)
		self._navPad = C.pad(self._nav, 12, 14)
		if options.ThemeToggle ~= false then
			self._themeToggle = C.node(self, "TextButton", self.Frame, { Name = "ThemeToggle" })
			C.corner(self._themeToggle)
			C.feedback(self, self._themeToggle)
			self._themeLabel = C.text(self, self._themeToggle, self._themeName == "Dark" and "Light mode" or "Dark mode", "Body", "Text", {
				Name = "ThemeLabel", Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0),
				TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center,
			})
			self._scope:Connect(self._themeToggle.Activated, function() self:ToggleTheme() end)
		end
		self._profile = env.require("profile").new(self, self.Frame, options.GameName)
		self._workspace = C.node(self, "Frame", self.Frame, { Name = "Workspace", Active = false }, { BackgroundColor3 = "Canvas" })
		C.corner(self._workspace, 14); C.stroke(self, self._workspace, "Subtle")
		self._content = C.node(self, "Frame", self.Frame, { Name = "Content", BackgroundTransparency = 1, ClipsDescendants = true })
		self._empty = C.text(self, self._content, "No matching controls", "Body", "Muted", { Name = "EmptySearch", Visible = false, Position = UDim2.fromOffset(20, 28), Size = UDim2.new(1, -40, 0, 40) })
		if options.Search ~= false then
			self._search = C.node(self, "TextBox", self.Frame, {
				Name = "Search", Text = "", PlaceholderText = "Search this tab", ClearTextOnFocus = false,
				Font = C.Font, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
			}, { BackgroundColor3 = "Input", TextColor3 = "Text", PlaceholderColor3 = "Muted", TextSize = function() return math.floor(14 * self.TextScale + 0.5) end })
			C.corner(self._search); C.pad(self._search, 14, 0)
			C.fieldBorder(self, self._search)
			self._scope:Connect(self._search:GetPropertyChangedSignal("Text"), function()
				self:_Filter()
				if self._activeTab then self._activeTab.Frame.CanvasPosition = Vector2.new(0, 0) end
			end)
		end
		C.footer(self, self.Frame)
		self._resize = C.node(self, "TextButton", self.Frame, {
			Name = "Resize", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1),
			Size = UDim2.fromOffset(24, 24), Selectable = false,
		})
		for index = 1, 3 do
			C.node(self, "Frame", self._resize, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(7 + index * 3, 16), Size = UDim2.fromOffset(2, 2 + index * 3), Rotation = 45 }, { BackgroundColor3 = "Muted" })
		end
		-- The restore pill. It carries the mark, the window title and a status
		-- line above the permanent attribution, it can be dragged anywhere in
		-- the safe viewport, and it restores on a click that was not a drag.
		self._launcher = C.node(self, "TextButton", self._viewport, { Name = "Restore", Visible = false, ClipsDescendants = true }, { BackgroundColor3 = "Canvas" })
		C.corner(self._launcher, T.Size.Radius)
		local launcherDragged = false
		C.bind(self, self._launcher, {
			BackgroundColor3 = function(theme) return self._launcherHovered and theme.Hover or theme.Canvas end,
		})
		self._launcherStroke = C.stroke(self, self._launcher)
		C.bind(self, self._launcherStroke, {
			Color = function(theme) return self._launcherHovered and theme.Accent or theme.Border end,
		})
		self._launcherBrand = C.mark(self, self._launcher, 20)
		self._launcherTitle = C.text(self, self._launcher, self.Title, "Heading", "Text", { Name = "RestoreTitle", Position = UDim2.fromOffset(44, 6), Size = UDim2.new(1, -84, 0, 20), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		self._launcherDetail = C.text(self, self._launcher, self._subtitle.Text ~= "" and self._subtitle.Text or "Minimized", "Caption", "Muted", { Name = "RestoreDetail", Position = UDim2.fromOffset(44, 26), Size = UDim2.new(1, -84, 0, 16), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		self._launcherHint = C.text(self, self._launcher, "Open", "Caption", "Secondary", { Size = UDim2.fromOffset(44, 24), TextXAlignment = Enum.TextXAlignment.Right })
		self._launcherHint.AnchorPoint = Vector2.new(1, 0.5)
		C.footer(self, self._launcher)
		local function hoverLauncher(value)
			self._launcherHovered = value
			motion.to(self, self._launcher, { BackgroundColor3 = value and self.Theme.Hover or self.Theme.Canvas })
			motion.to(self, self._launcherStroke, { Color = value and self.Theme.Accent or self.Theme.Border })
		end
		self._scope:Connect(self._launcher.MouseEnter, function() hoverLauncher(true) end)
		self._scope:Connect(self._launcher.MouseLeave, function() hoverLauncher(false) end)
		-- A press that moved is a drag, not a restore. The flag is cleared when
		-- the next press begins, so a drag released off the pill cannot swallow
		-- the click after it.
		self._scope:Connect(self._launcher.Activated, function()
			if launcherDragged then launcherDragged = false; return end
			self:Show()
		end)
		self._toastHost = C.node(self, "Frame", self._viewport, { Name = "Notifications", AnchorPoint = Vector2.new(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 200 })
		local toastLayout = C.list(self._toastHost, false, 8)
		toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
		self:_Layout()

		local dragStart, frameStart, sizeStart
		C.pointer(self, self._header, function(input)
			if C.isInside(self._headerActions, input.Position.X, input.Position.Y) then return false end
			dragStart, frameStart = input.Position, self.Frame.Position
		end, function(input)
			self._position = Vector2.new(frameStart.X.Offset + input.Position.X - dragStart.X, frameStart.Y.Offset + input.Position.Y - dragStart.Y)
			self:_Move(self.Frame, self._position)
		end)
		C.pointer(self, self._resize, function(input)
			dragStart, sizeStart = input.Position, self.Frame.AbsoluteSize
			self._position = Vector2.new(self.Frame.Position.X.Offset, self.Frame.Position.Y.Offset)
		end, function(input)
			self._requestedWidth = math.max(280, sizeStart.X + input.Position.X - dragStart.X)
			self._requestedHeight = math.max(240, sizeStart.Y + input.Position.Y - dragStart.Y)
			self:_Layout()
		end)
		local launcherOrigin, launcherStart
		C.pointer(self, self._launcher, function(input)
			launcherDragged = false
			launcherOrigin, launcherStart = input.Position, self._launcher.Position
			return true
		end, function(input)
			if not launcherStart then return end
			local delta = input.Position - launcherOrigin
			if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then launcherDragged = true end
			if not launcherDragged then return end
			self._launcherPosition = Vector2.new(launcherStart.X.Offset + delta.X, launcherStart.Y.Offset + delta.Y)
			self:_Move(self._launcher, self._launcherPosition)
		end, function()
			launcherOrigin, launcherStart = nil, nil
		end)
		local uis = env.services.UserInputService
		self._scope:Connect(uis.InputChanged, function(input)
			local gesture = self._gesture
			if not gesture then return end
			local touch = gesture.input.UserInputType == Enum.UserInputType.Touch
			if (touch and input == gesture.input) or (not touch and input.UserInputType == Enum.UserInputType.MouseMovement) then
				if gesture.owner._scope.alive and gesture.move then gesture.move(input) end
			end
		end)
		self._scope:Connect(uis.InputEnded, function(input)
			for release in pairs(self._presses) do release() end
			local gesture = self._gesture
			if gesture then
				local touch = gesture.input.UserInputType == Enum.UserInputType.Touch
				if (touch and input == gesture.input) or (not touch and input.UserInputType == Enum.UserInputType.MouseButton1) then
					if input.UserInputState ~= Enum.UserInputState.Cancel and gesture.owner._scope.alive and gesture.finish then gesture.finish(input) end
					if self._gesture == gesture then C.cancelGesture(self) end
				end
			end
			for binding in pairs(self._keys) do if binding.ended then binding.ended(input) end end
		end)
		self._scope:Connect(uis.InputBegan, function(input, processed)
			if self._capture then self._capture(input); return end
			if self._overlay and (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) then
				if self._overlay.Dismissible then self:_CloseOverlay() end
				return
			end
			if processed or uis:GetFocusedTextBox() then return end
			if self.ToggleKey and input.KeyCode == self.ToggleKey then self:Toggle(); return end
			if self._overlay then return end
			for binding in pairs(self._keys) do if binding.began then binding.began(input) end end
		end)
		self._scope:Connect(uis.WindowFocusReleased, function()
			C.cancelGesture(self); self:_CancelCapture(); self:_ReleaseKeys()
			for release in pairs(self._presses) do release() end
			motion.stopAll(self, true)
		end)
		pcall(function()
			local function preference()
				if self._motionOverride == nil then self.ReducedMotion = env.services.GuiService.ReducedMotionEnabled == true; motion.stopAll(self, true) end
			end
			preference()
			self._scope:Connect(env.services.GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"), preference)
		end)
		self._scope:Connect(self._viewport:GetPropertyChangedSignal("AbsoluteSize"), function() self:_Layout() end)
		self._scope:Connect(self._viewport:GetPropertyChangedSignal("AbsolutePosition"), function() self:_Layout() end)
		local cameraRelease
		local function cameraChanged()
			if cameraRelease then cameraRelease(); cameraRelease = nil end
			local camera = env.services.Workspace.CurrentCamera
			if camera then cameraRelease = self._scope:Add(camera:GetPropertyChangedSignal("ViewportSize"):Connect(function() self:_Layout() end)) end
			self:_Layout()
		end
		self._scope:Connect(env.services.Workspace:GetPropertyChangedSignal("CurrentCamera"), cameraChanged)
		cameraChanged()
		for _, property in ipairs({ "OnScreenKeyboardVisible", "OnScreenKeyboardSize", "OnScreenKeyboardPosition", "TouchEnabled" }) do
			pcall(function()
				self._scope:Connect(uis:GetPropertyChangedSignal(property), function()
					self:_Layout()
					self._scope:Delay(0.05, function() self:_RevealFocused() end)
				end)
			end)
		end
		self._scope:Connect(uis.TextBoxFocused, function()
			self:_Layout()
			self._scope:Delay(0.05, function() self:_RevealFocused() end)
		end)
		self._scope:Connect(uis.TextBoxFocusReleased, function() self:_Layout() end)
		self._scope:Connect(self.ScreenGui.Destroying, function() self:Destroy() end)
		self._scope:Connect(self.Frame.Destroying, function() self:Destroy() end)
		env.windows[id] = self
		if options.OnDestroy then self:OnDestroy(options.OnDestroy) end
		motion.reveal(self, self.Frame)
		return self
	end
	C.elevate(Window)
	return Window
end
