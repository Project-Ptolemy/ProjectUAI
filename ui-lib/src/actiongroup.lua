-- Related actions share a responsive row and independent owned busy states.
return function(env)
	local C = env.require("core")
	local M = {}
	function M.ActionGroup(section, options)
		assert(type(options.Actions) == "table" and #options.Actions >= 1 and #options.Actions <= 8, "ActionGroup expects 1-8 actions")
		local items, order = {}, {}
		for index, action in ipairs(options.Actions) do
			assert(type(action) == "table" and type(action.Id) == "string" and #action.Id > 0 and #action.Id <= 80, "Actions need a bounded Id")
			assert(not items[action.Id], "Duplicate action Id")
			assert(type(action.Text) == "string" and #action.Text > 0 and #action.Text <= 80, "Actions need bounded Text")
			assert(type(action.Callback) == "function", "Actions need a Callback")
			assert(action.Disabled == nil or type(action.Disabled) == "boolean", "Action Disabled must be boolean")
			assert(action.Style == nil or action.Style == "Primary" or action.Style == "Danger", "Unknown action Style")
			local item = { Id = action.Id, Text = action.Text, Callback = action.Callback, Style = action.Style, Enabled = action.Disabled ~= true }
			items[action.Id], order[index] = item, item
		end
		assert(#order == #options.Actions, "Actions must be a dense array")
		for key in pairs(options.Actions) do assert(type(key) == "number" and key >= 1 and key <= #order and key == math.floor(key), "Actions must be an array") end
		local controls = env.require("controls")
		local self = controls.base(section, "ActionGroup", options, "stack")
		self.Persist = false
		for _, item in ipairs(order) do
			local button = controls.input(self, "TextButton", self._slot, { Name = "Action_" .. item.Id })
			C.corner(button)
			local function enabled() return not self.Disabled and item.Enabled and not item.Loading end
			item.button, item.refresh = button, C.feedback(self, button, item.Style, enabled)
			item.color = function(theme)
				return not enabled() and theme.Muted or item.Style and theme.OnPrimary or theme.Text
			end
			item.label = C.text(self, button, item.Text, "Body", item.color,
				{ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
			self._scope:Connect(button.Activated, function() self:Press(item.Id) end)
		end
		self._slotHeight = function(width)
			local columns = math.max(1, math.min(#order, math.floor((width + 8) / (120 * self._window.TextScale + 8))))
			local cell = (width - (columns - 1) * 8) / columns
			local row = math.max(self._window.Target, math.ceil(36 * self._window.TextScale))
			for _, item in ipairs(order) do row = math.max(row, C.measure(item.Text, item.label.TextSize, math.max(1, cell - 16), item.label.Font) + 12) end
			for index, item in ipairs(order) do
				item.button.Position = UDim2.fromOffset(((index - 1) % columns) * (cell + 8), math.floor((index - 1) / columns) * (row + 8))
				item.button.Size = UDim2.fromOffset(cell, row)
			end
			return math.ceil(#order / columns) * (row + 8) - 8
		end
		self._render = function()
			for _, item in ipairs(order) do
				item.label.Text = item.Loading and "Working" or item.Text
				item.label.TextColor3 = item.color(self._window.Theme)
				item.button.Active, item.button.Selectable = not self.Disabled and item.Enabled and not item.Loading, not self.Disabled and item.Enabled and not item.Loading
				item.refresh()
			end
		end
		function self:Press(id)
			local item = assert(items[id], "Unknown action Id")
			if not self:_Interactive() or not item.Enabled or item.Loading then return false end
			item.Loading = true; self._render()
			self._scope:Spawn(function()
				C.call(self._window, item.Callback)
				if self.Alive then item.Loading = false; self._render() end
			end)
			return true
		end
		function self:SetActionEnabled(id, enabled)
			assert(self.Alive, "Control is destroyed")
			assert(type(enabled) == "boolean", "Action enabled state must be boolean")
			assert(items[id], "Unknown action Id").Enabled = enabled
			self._render(); self._layout(); return self
		end
		function self:SetActionText(id, text)
			assert(self.Alive, "Control is destroyed")
			assert(type(text) == "string" and #text > 0 and #text <= 80, "Actions need bounded Text")
			assert(items[id], "Unknown action Id").Text = text
			self._render(); self._layout(); return self
		end
		self._render(); self._layout()
		return self
	end
	return M
end
