return function(env)
	local C = env.require("core")
	local M, Tab, Section = {}, {}, {}
	Tab.__index, Section.__index = Tab, Section
	function M.tab(window, options)
		assert(window.Alive, "Window is destroyed")
		options = type(options) == "string" and { Title = options } or options or {}
		local title = tostring(options.Title or "Tab")
		local id = tostring(options.Id or title)
		for _, tab in ipairs(window.Tabs) do assert(tab.Id ~= id, "Duplicate tab Id: " .. id) end
		local tab = setmetatable(C.owner(window), Tab)
		tab.Id, tab.Title, tab.Alive, tab.Visible, tab.Sections = id, title, true, true, {}
		tab._scope:Add(function() tab.Alive = false end)
		tab.Frame = C.scroll(tab, window._content, "Tab_" .. id)
		tab._scope:Connect(tab.Frame.Destroying, function() tab:Destroy() end)
		tab.Frame.Visible = false
		local padding = C.pad(tab.Frame, 20, 20)
		C.reflow(tab, function()
			padding.PaddingLeft, padding.PaddingRight = UDim.new(0, window._contentPad), UDim.new(0, window._contentPad)
			padding.PaddingTop, padding.PaddingBottom = UDim.new(0, window._contentPad), UDim.new(0, window._contentPad)
		end)
		C.list(tab.Frame, false, 20)
		local intro = C.node(tab, "Frame", tab.Frame, {
			Name = "TabHeading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 76), LayoutOrder = 0,
		})
		tab._intro = intro
		local eyebrow = C.text(tab, intro, "WORKSPACE", "Eyebrow", "Accent", { Size = UDim2.new(1, 0, 0, 14), TextWrapped = false })
		local heading = C.text(tab, intro, title, "Display", "Text", { Position = UDim2.fromOffset(0, 20), TextYAlignment = Enum.TextYAlignment.Top })
		tab._summary = C.text(tab, intro, "", "Caption", "Muted", { TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		C.reflow(tab, function()
			local width = math.max(1, window._contentWidth - window._contentPad * 2)
			local titleTop = math.ceil(20 * window.TextScale)
			local titleHeight = C.measure(title, math.floor(C.tokens.Type.Display * window.TextScale + 0.5), width, heading.Font)
			local detailHeight = math.ceil(18 * window.TextScale)
			eyebrow.Size = UDim2.new(1, 0, 0, math.ceil(14 * window.TextScale))
			heading.Position, heading.Size = UDim2.fromOffset(0, titleTop), UDim2.new(1, 0, 0, titleHeight)
			tab._summary.Position = UDim2.fromOffset(0, titleTop + titleHeight + 6)
			tab._summary.Size = UDim2.new(1, 0, 0, detailHeight)
			intro.Size = UDim2.new(1, 0, 0, titleTop + titleHeight + detailHeight + 8)
		end)
		tab._button = C.node(tab, "TextButton", window._nav, { Name = "Tab_" .. id, LayoutOrder = #window.Tabs + 1 })
		C.corner(tab._button)
		local selected, hovered = false, false
		local edge = C.stroke(tab, tab._button, "Accent")
		C.bind(tab, edge, { Transparency = function() return selected and 0 or window._activeTab == tab and 0.72 or 1 end })
		local indicator = C.node(tab, "Frame", tab._button, { Name = "ActiveIndicator", Size = UDim2.fromOffset(3, 16), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0) }, {
			BackgroundColor3 = "Accent", BackgroundTransparency = function() return window._activeTab == tab and 0 or 1 end,
		})
		C.corner(indicator, 1)
		-- Legacy Icon options are ignored. Navigation is always readable text.
		C.text(tab, tab._button, title, "Body", function(theme) return window._activeTab == tab and theme.Text or theme.Secondary end, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		C.bind(tab, tab._button, { BackgroundColor3 = function(theme) return window._activeTab == tab and theme.Selected or hovered and theme.Hover or theme.Sidebar end })
		local function hover(value)
			hovered = value
			env.require("motion").to(tab, tab._button, { BackgroundColor3 = window._activeTab == tab and window.Theme.Selected or hovered and window.Theme.Hover or window.Theme.Sidebar })
		end
		tab._scope:Connect(tab._button.MouseEnter, function() hover(true) end)
		tab._scope:Connect(tab._button.MouseLeave, function() hover(false) end)
		tab._scope:Connect(tab._button.SelectionGained, function() selected = true; edge.Transparency = 0 end)
		tab._scope:Connect(tab._button.SelectionLost, function() selected = false; edge.Transparency = window._activeTab == tab and 0.72 or 1 end)
		tab._scope:Connect(tab._button.Activated, function() window:SelectTab(tab) end)
		window.Tabs[#window.Tabs + 1] = tab
		window:_Layout()
		if not window._activeTab then window:SelectTab(tab) end
		return tab
	end
	function Tab:Select() self._window:SelectTab(self); return self end
	function Tab:SetVisible(visible)
		self.Visible, self._button.Visible = visible == true, visible == true
		self.Frame.Visible = self.Visible and self._window._activeTab == self
		if not self.Visible and self._window._activeTab == self then
			self._window._activeTab = nil
			self._window:_CloseOverlay()
			for _, tab in ipairs(self._window.Tabs) do if tab.Visible then tab:Select(); break end end
		end
		return self
	end
	function Tab:Destroy()
		if not self.Alive then return end
		self:SetVisible(false)
		self.Alive = false
		for index = #self.Sections, 1, -1 do self.Sections[index]:Destroy() end
		for index, tab in ipairs(self._window.Tabs) do if tab == self then table.remove(self._window.Tabs, index); break end end
		self._scope:Destroy()
		self.Frame:Destroy(); self._button:Destroy()
	end
	function Tab:Section(options)
		assert(self.Alive, "Tab is destroyed")
		options = type(options) == "string" and { Title = options } or options or {}
		local window = self._window
		local section = setmetatable(C.owner(window, self._scope), Section)
		section._tab, section.Title, section.Description = self, tostring(options.Title or ""), tostring(options.Description or "")
		section.Alive, section.Visible, section.Collapsed, section.Controls = true, true, options.Collapsed == true, {}
		section._scope:Add(function() section.Alive = false end)
		section.Frame = C.node(section, "Frame", self.Frame, {
			Name = "Section_" .. section.Title, BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = #self.Sections + 1,
		})
		section._scope:Connect(section.Frame.Destroying, function() section:Destroy() end)
		C.list(section.Frame, false, 10)
		section._header = C.node(section, "TextButton", section.Frame, {
			Name = "SectionHeader", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 0,
			Selectable = options.Collapsible == true,
		})
		section._heading = C.text(section, section._header, section.Title, "Heading", "Text", { Size = UDim2.new(1, -24, 0, 22) })
		section._description = C.text(section, section._header, section.Description, "Caption", "Muted", { Position = UDim2.fromOffset(0, 24), TextYAlignment = Enum.TextYAlignment.Top })
		if options.Collapsible then
			section._collapseLabel = C.text(section, section._header, section.Collapsed and "Show" or "Hide", "Caption", "Muted", {
				Position = UDim2.new(1, -64, 0, 0), Size = UDim2.fromOffset(64, window.Target), TextXAlignment = Enum.TextXAlignment.Right, TextWrapped = false })
			section._scope:Connect(section._header.Activated, function() section:SetCollapsed(not section.Collapsed) end)
		end
		section._body = C.node(section, "Frame", section.Frame, {
			Name = "Rows", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Visible = not section.Collapsed,
		}, { BackgroundColor3 = "Surface" })
		C.corner(section._body, 12); C.stroke(section, section._body, "Subtle")
		C.list(section._body, false, 0); C.pad(section._body, 0, 4)
		C.reflow(section, function()
			local width = math.max(1, window._contentWidth - window._contentPad * 2)
			local reserve = options.Collapsible and 72 or 0
			local headingHeight = C.measure(section.Title, math.floor(15 * window.TextScale + 0.5), width - reserve, section._heading.Font)
			local descriptionHeight = section.Description ~= "" and C.measure(section.Description, 12 * window.TextScale, width - reserve) or 0
			section._header.Visible = section.Title ~= "" or section.Description ~= ""
			section._header.Size = UDim2.new(1, 0, 0, math.max(options.Collapsible and window.Target or 0, headingHeight + (descriptionHeight > 0 and descriptionHeight + 4 or 0)))
			section._heading.Size = UDim2.new(1, -reserve, 0, headingHeight)
			section._description.Position = UDim2.fromOffset(0, headingHeight + 4)
			section._description.Size = UDim2.new(1, -reserve, 0, descriptionHeight)
			if section._collapseLabel then section._collapseLabel.Size = UDim2.fromOffset(64, window.Target) end
			section._description.Visible = descriptionHeight > 0
		end)
		self.Sections[#self.Sections + 1] = section
		window:_Filter()
		return section
	end
	function Section:SetCollapsed(collapsed)
		self.Collapsed = collapsed == true
		if self._collapseLabel then self._collapseLabel.Text = self.Collapsed and "Show" or "Hide" end
		self._window:_Filter()
		self._window:_Refresh()
		return self
	end
	function Section:SetVisible(visible)
		self.Visible = visible == true
		self._window:_Filter()
		return self
	end
	function Section:Destroy()
		if not self.Alive then return end
		self.Alive = false
		for index = #self.Controls, 1, -1 do self.Controls[index]:Destroy() end
		for index, section in ipairs(self._tab.Sections) do if section == self then table.remove(self._tab.Sections, index); break end end
		self._scope:Destroy()
		self.Frame:Destroy()
		if self._window.Alive then self._window:_Filter() end
	end
	for _, kind in ipairs({ "Button", "Toggle", "Checkbox", "Slider", "Input", "Dropdown", "Segmented", "Keybind", "ColorPicker", "Label", "Paragraph", "Divider", "Badge", "Progress" }) do
		Section[kind] = function(section, options)
			return env.require("controls").create(section, kind, options)
		end
	end
	return M
end
