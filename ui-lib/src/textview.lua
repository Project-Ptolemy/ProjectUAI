-- Selectable output belongs to the library: scripts supply text and copy intent,
-- while the viewer owns typography, scrolling, bounds and clipboard outcomes.
return function(env)
	local C = env.require("core")
	local M = {}
	function M.TextView(section, options)
		options = C.copy(options)
		local maximum = options.MaxLength or 65536
		assert(C.finite(maximum) and maximum >= 1 and maximum <= 262144, "TextView MaxLength must be 1-262144")
		local controls = env.require("controls")
		local self = controls.base(section, "TextView", options, "stack")
		self.Persist = options.Persist == true
		self._normalize = function(value)
			assert(type(value) == "string" and #value <= maximum, "TextView value exceeds its text limit")
			return value
		end
		self._value = self._normalize(options.Default or options.Value or "")
		local scroll = C.scroll(self, self._slot, "TextViewport")
		C.bind(self, scroll, { BackgroundColor3 = "Input" }); scroll.BackgroundTransparency = 0
		C.corner(scroll); C.stroke(self, scroll, "Edge")
		local field = C.node(self, "TextBox", scroll, { Name = "TextView", Text = self._value, TextEditable = false,
			ClearTextOnFocus = false, MultiLine = true, TextWrapped = true, BackgroundTransparency = 1,
			Font = options.Code and Enum.Font.Code or C.Font, TextSize = 14, RichText = false,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -28, 0, 40),
		}, { TextColor3 = "Text", TextSize = function() return math.floor(14 * self._window.TextScale + 0.5) end })
		self._slotHeight = function() return self._window.Target * C.number(options.Lines, 4, 2, 12) end
		local painting = false
		self._afterLayout = function(width)
			field.Size = UDim2.new(1, -28, 0, math.max(self._window.Target, C.measure(self._value, field.TextSize, math.max(1, width - 28), field.Font) + 10))
		end
		self._render = function()
			painting = true; field.Text = self._value; painting = false
			self._layout()
		end
		self._scope:Connect(field:GetPropertyChangedSignal("Text"), function()
			if not painting and field.Text ~= self._value then self._render() end
		end)
		function self:Append(text)
			assert(type(text) == "string", "Append expects text")
			return self:Set(self._value .. text, true)
		end
		function self:Copy()
			assert(self.Alive, "Control is destroyed")
			local clipboard = env.globals.setclipboard or env.globals.toclipboard or setclipboard
			if type(clipboard) ~= "function" then return false, "Clipboard unavailable; select and copy the text manually." end
			local ok, result = pcall(clipboard, self._value)
			if not ok or result == false then return false, "Clipboard could not copy the text." end
			return true
		end
		function self:ScrollToEnd()
			assert(self.Alive, "Control is destroyed")
			scroll.CanvasPosition = Vector2.new(0, math.max(0, field.Size.Y.Offset + 20 - scroll.AbsoluteSize.Y))
			return self
		end
		self._render()
		return self
	end
	return M
end
