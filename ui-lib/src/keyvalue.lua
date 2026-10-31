-- Structured readouts wrap into stacked key/value rows on narrow screens.
-- Updating one value preserves order and never gives scripts layout ownership.
return function(env)
	local C = env.require("core")
	local M = {}
	function M.KeyValue(section, options)
		local self = env.require("controls").base(section, "KeyValue", options, "stack")
		self.Persist = options.Persist == true
		self._normalize = function(items)
			assert(type(items) == "table" and #items <= 64, "KeyValue expects at most 64 rows")
			local normalized, seen = {}, {}
			for index, item in ipairs(items) do
				assert(type(item) == "table" and type(item.Key) == "string" and #item.Key > 0 and #item.Key <= 128, "KeyValue rows need a bounded Key")
				assert(not seen[item.Key], "Duplicate KeyValue key: " .. item.Key)
				assert(type(item.Value) == "string" or type(item.Value) == "boolean" or C.finite(item.Value), "KeyValue Value must be text, a number or a boolean")
				assert(#tostring(item.Value) <= 4096, "KeyValue Value is too long")
				seen[item.Key] = true
				normalized[index] = { Key = item.Key, Value = tostring(item.Value) }
			end
			for key in pairs(items) do assert(type(key) == "number" and key >= 1 and key <= #items and key == math.floor(key), "KeyValue rows must be an array") end
			assert(#normalized == #items, "KeyValue rows must be a dense array")
			return normalized
		end
		self._value = self._normalize(options.Default or options.Items or {})
		local rows, rowScope = {}, nil
		self._slotHeight = function(width)
			local top, stacked = 0, width < 260 * self._window.TextScale
			for _, row in ipairs(rows) do
				local keyWidth = stacked and width or math.max(1, width * 0.38 - 12)
				local valueWidth = stacked and width or math.max(1, width * 0.62)
				local keyHeight = C.measure(row.key.Text, row.key.TextSize, keyWidth, row.key.Font)
				local valueHeight = C.measure(row.value.Text, row.value.TextSize, valueWidth, row.value.Font)
				row.key.Position, row.key.Size = UDim2.fromOffset(0, top), UDim2.fromOffset(keyWidth, keyHeight)
				row.value.Position = UDim2.fromOffset(stacked and 0 or width * 0.38, top + (stacked and keyHeight + 3 or 0))
				row.value.Size = UDim2.fromOffset(valueWidth, valueHeight)
				top = top + (stacked and keyHeight + valueHeight + 3 or math.max(keyHeight, valueHeight)) + 12
			end
			return math.max(1, top - 12)
		end
		self._render = function()
			if rowScope then rowScope:Destroy() end
			rowScope, rows = C.scope(self._scope), {}
			local owner = { _window = self._window, _scope = rowScope }
			for _, item in ipairs(self._value) do
				local key = C.text(owner, self._slot, item.Key, "Caption", "Muted", { TextYAlignment = Enum.TextYAlignment.Top })
				local value = C.text(owner, self._slot, item.Value, "Body", "Text", { TextYAlignment = Enum.TextYAlignment.Top })
				rowScope:Add(key); rowScope:Add(value)
				rows[#rows + 1] = { key = key, value = value }
			end
			self._layout()
		end
		function self:SetValue(key, value, silent)
			assert(self.Alive, "Control is destroyed")
			local items = self:Get()
			for _, item in ipairs(items) do if item.Key == key then item.Value = value; return self:Set(items, silent) end end
			error("Unknown KeyValue key: " .. tostring(key))
		end
		self._render()
		return self
	end
	return M
end
