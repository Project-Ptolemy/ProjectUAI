-- A bounded searchable selection list with stable identities and explicit pages.
-- Replacing items validates the complete snapshot before changing selection.
return function(env)
	local C = env.require("core")
	local M = {}
	local function normalize(items)
		assert(type(items) == "table" and #items <= 500, "ItemList expects at most 500 items")
		local result, seen = {}, {}
		for index, item in ipairs(items) do
			assert(type(item) == "table" and type(item.Id) == "string" and #item.Id > 0 and #item.Id <= 128, "List items need bounded Ids")
			assert(not seen[item.Id], "Duplicate list item Id")
			assert(type(item.Text) == "string" and #item.Text > 0 and #item.Text <= 256, "List items need bounded Text")
			assert(item.Description == nil or type(item.Description) == "string" and #item.Description <= 1024, "List Description is too long")
			assert(item.Disabled == nil or type(item.Disabled) == "boolean", "List Disabled must be boolean")
			seen[item.Id] = true
			result[index] = { Id = item.Id, Text = item.Text, Description = item.Description or "", Disabled = item.Disabled == true }
		end
		for key in pairs(items) do assert(type(key) == "number" and key >= 1 and key <= #items and key == math.floor(key), "List items must be an array") end
		assert(#result == #items, "List items must be a dense array")
		return result
	end
	function M.ItemList(section, options)
		local items = normalize(options.Items or {})
		local controls = env.require("controls")
		local self = controls.base(section, "ItemList", options, "stack")
		local pageSize = math.floor(C.number(options.PageSize, 6, 1, 20))
		local query, page, pages, matches, rows, rowsScope = "", 1, 1, {}, {}, nil
		local function find(id)
			for _, item in ipairs(items) do if item.Id == id then return item end end
		end
		self._normalize = function(value)
			assert(type(value) == "string" and (value == "" or find(value)), "Unknown list selection")
			return value
		end
		self._value = self._normalize(options.Default or "")
		local search
		if options.Searchable ~= false then
			search = controls.input(self, "TextBox", self._slot, { Name = "ListSearch", Text = "", PlaceholderText = "Search items",
				ClearTextOnFocus = false, Font = C.Font, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
			})
			C.bind(self, search, { BackgroundColor3 = "Input", TextColor3 = "Text", PlaceholderColor3 = "Muted",
				TextSize = function() return math.floor(14 * self._window.TextScale + 0.5) end })
			C.corner(search); C.pad(search, 10, 0); C.fieldBorder(self, search)
		end
		local host = C.node(self, "Frame", self._slot, { Name = "ListRows", BackgroundTransparency = 1 })
		local footer = C.node(self, "Frame", self._slot, { Name = "ListPages", BackgroundTransparency = 1 })
		local previous = controls.input(self, "TextButton", footer, { Name = "Previous" })
		local nextPage = controls.input(self, "TextButton", footer, { Name = "Next" })
		C.corner(previous); C.corner(nextPage)
		local previousFeedback = C.feedback(self, previous, nil, function() return not self.Disabled and page > 1 end)
		local nextFeedback = C.feedback(self, nextPage, nil, function() return not self.Disabled and page < pages end)
		C.text(self, previous, "Previous", "Small", "Text", { Size = UDim2.fromScale(1, 1), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
		C.text(self, nextPage, "Next", "Small", "Text", { Size = UDim2.fromScale(1, 1), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
		local status = C.text(self, footer, "", "Small", "Muted", { TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center })
		self._slotHeight = function(width)
			local target = self._window.Target
			local top = search and target + 8 or 0
			if search then search.Size = UDim2.fromOffset(width, target) end
			host.Position = UDim2.fromOffset(0, top)
			local height = 0
			for _, row in ipairs(rows) do
				local titleHeight = C.measure(row.title.Text, row.title.TextSize, math.max(1, width - 24), row.title.Font)
				local detailHeight = row.detail.Text ~= "" and C.measure(row.detail.Text, row.detail.TextSize, math.max(1, width - 24), row.detail.Font) or 0
				local rowHeight = math.max(target, titleHeight + detailHeight + (detailHeight > 0 and 4 or 0) + 16)
				row.node.Position, row.node.Size = UDim2.fromOffset(0, height), UDim2.fromOffset(width, rowHeight)
				row.title.Position, row.title.Size = UDim2.fromOffset(12, 8), UDim2.fromOffset(math.max(1, width - 24), titleHeight)
				row.detail.Position, row.detail.Size = UDim2.fromOffset(12, 12 + titleHeight), UDim2.fromOffset(math.max(1, width - 24), detailHeight)
				height = height + rowHeight + 4
			end
			host.Size = UDim2.fromOffset(width, math.max(0, height - 4))
			footer.Position, footer.Size = UDim2.fromOffset(0, top + height + 4), UDim2.fromOffset(width, target)
			local actionWidth = math.min(76, width * 0.3)
			previous.Size, nextPage.Size = UDim2.fromOffset(actionWidth, target), UDim2.fromOffset(actionWidth, target)
			nextPage.Position = UDim2.new(1, -actionWidth, 0, 0)
			status.Position, status.Size = UDim2.fromOffset(actionWidth + 4, 0), UDim2.new(1, -actionWidth * 2 - 8, 1, 0)
			return top + height + 4 + target
		end
		self._render = function()
			matches = {}
			for _, item in ipairs(items) do
				if query == "" or (item.Text .. " " .. item.Description):lower():find(query:lower(), 1, true) then matches[#matches + 1] = item end
			end
			pages = math.max(1, math.ceil(#matches / pageSize)); page = math.min(page, pages)
			if rowsScope then rowsScope:Destroy() end
			rowsScope, rows = C.scope(self._scope), {}
			local owner = { _window = self._window, _scope = rowsScope }
			for index = (page - 1) * pageSize + 1, math.min(page * pageSize, #matches) do
				local item = matches[index]
				local enabled = not self.Disabled and not item.Disabled
				local row = C.node(owner, "TextButton", host, { Name = "Item_" .. item.Id, Active = enabled, Selectable = enabled },
					{ BackgroundColor3 = self._value == item.Id and "Selected" or "Raised" })
				rowsScope:Add(row); C.corner(row)
				local label = C.text(owner, row, item.Text, "Body", enabled and "Text" or "Disabled", { TextYAlignment = Enum.TextYAlignment.Top })
				local detail = C.text(owner, row, item.Description, "Caption", "Muted", { TextYAlignment = Enum.TextYAlignment.Top })
				C.selection(owner, row, function() return self._value == item.Id end, function() return not self.Disabled and not item.Disabled end)
				rows[#rows + 1] = { node = row, title = label, detail = detail }
				rowsScope:Connect(row.Activated, function() if self:_Interactive() and not item.Disabled then self:Set(item.Id) end end)
			end
			previous.Active, previous.Selectable = not self.Disabled and page > 1, not self.Disabled and page > 1
			nextPage.Active, nextPage.Selectable = not self.Disabled and page < pages, not self.Disabled and page < pages
			previousFeedback(); nextFeedback()
			status.Text = #matches == 0 and "No matching items" or tostring(page) .. " / " .. tostring(pages) .. "  (" .. #matches .. ")"
			self._layout()
		end
		function self:SetItems(nextItems, silent)
			assert(self.Alive, "Control is destroyed")
			local snapshot = normalize(nextItems)
			items, page = snapshot, 1
			if self._default and self._default ~= "" and not find(self._default) then self._default = "" end
			if self._value ~= "" and not find(self._value) then self:Set("", silent ~= false) else self._render() end
			return self
		end
		function self:GetItems() return C.copy(items) end
		function self:SetQuery(value)
			assert(self.Alive, "Control is destroyed")
			assert(type(value) == "string" and #value <= 256, "List query must be text under 256 bytes")
			query, page = value, 1
			if search and search.Text ~= query then search.Text = query end
			self._render(); return self
		end
		function self:SetPage(value)
			assert(self.Alive, "Control is destroyed")
			assert(C.finite(value) and value >= 1 and value <= pages and value == math.floor(value), "List page is outside its range")
			page = value; self._render(); return self
		end
		function self:GetPage() return page, pages, #matches end
		self._scope:Connect(previous.Activated, function() if self:_Interactive() and page > 1 then self:SetPage(page - 1) end end)
		self._scope:Connect(nextPage.Activated, function() if self:_Interactive() and page < pages then self:SetPage(page + 1) end end)
		if search then self._scope:Connect(search:GetPropertyChangedSignal("Text"), function()
			if search.Text ~= query then self:SetQuery(C.truncate(search.Text, 256)) end
		end) end
		self._render()
		return self
	end
	return M
end
