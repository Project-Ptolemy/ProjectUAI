-- A bounded numeric editor reuses the input's draft validation and commit
-- lifecycle while adding named increment/decrement actions for pointer users.
return function(env)
	local C = env.require("core")
	local M = {}
	function M.NumberInput(section, options)
		options = C.copy(options)
		local step = options.Step or 1
		assert(C.finite(step) and step > 0, "NumberInput Step must be positive")
		local prepared = C.copy(options)
		prepared.Numeric, prepared.MultiLine, prepared.Live = true, false, false
		local controls = env.require("controls")
		local self = controls.Input(section, prepared)
		self.Kind, self.Step = "NumberInput", step
		local field = self._inputs[1]
		local function quantize(value)
			local base = options.Min or 0
			if options.Max ~= nil and value >= options.Max then return options.Max end
			value = base + math.floor((value - base) / step + 0.5) * step
			return tonumber(string.format("%.12g", C.clamp(value, options.Min or -math.huge, options.Max or math.huge)))
		end
		local function normalize(value)
			assert(C.finite(value), "Enter a valid number")
			value = quantize(C.clamp(value, options.Min or -math.huge, options.Max or math.huge))
			assert(C.finite(value), "Enter a valid number")
			return value
		end
		local function readValue(raw)
			local ok, value = pcall(normalize, raw)
			if not ok then return false, "Enter a valid number." end
			local valid, message = self._validateValue(value)
			if not valid then return false, message end
			return true, value
		end
		self._normalize = function(value)
			local ok, result = readValue(value)
			assert(ok, result)
			return result
		end
		self._normalizeDefault = normalize
		self._value = normalize(self._value)
		self._readDraft = function() return readValue(tonumber(field.Text)) end
		local buttons = {}
		for _, item in ipairs({ { "Decrease", -1 }, { "Increase", 1 } }) do
			local button = controls.input(self, "TextButton", self._slot, { Name = item[1] })
			C.corner(button)
			local enabled = function() return not self.Disabled and (item[2] < 0 and (options.Min == nil or self._value > options.Min)
				or item[2] > 0 and (options.Max == nil or self._value < options.Max)) end
			local refresh = C.feedback(self, button, nil, enabled)
			local color = function(theme) return enabled() and theme.Text or theme.Disabled end
			local label = C.text(self, button, item[2] < 0 and "Less" or "More", "Small", color,
				{ Size = UDim2.fromScale(1, 1), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Center })
			buttons[#buttons + 1] = { node = button, label = label, color = color, refresh = refresh, enabled = enabled }
			self._scope:Connect(button.Activated, function() self:StepBy(item[2]) end)
		end
		local layout, render = self._afterLayout, self._render
		self._afterLayout = function(width, height)
			layout(width, height)
			local side = math.min(56, math.max(40, self._window.Target))
			field.Position, field.Size = UDim2.fromOffset(side + 4, 0), UDim2.new(1, -(side + 4) * 2, 0, height - (self._errorHeight or 0))
			buttons[1].node.Size, buttons[2].node.Size = UDim2.fromOffset(side, self._window.Target), UDim2.fromOffset(side, self._window.Target)
			buttons[2].node.Position = UDim2.new(1, -side, 0, 0)
		end
		self._render = function(preserve)
			render(preserve)
			for _, button in ipairs(buttons) do
				button.node.Active, button.node.Selectable = button.enabled(), button.enabled()
				button.label.TextColor3 = button.color(self._window.Theme)
				button.refresh()
			end
		end
		function self:StepBy(count)
			assert(C.finite(count) and count == math.floor(count) and math.abs(count) <= 1000, "StepBy expects a bounded integer")
			if not self:_Interactive() then return false end
			local ok, value = self:_readDraft()
			if not ok then self:_showValidation(value); return false, value end
			ok, value = readValue(value + count * step)
			if not ok then self:_showValidation(value); return false, value end
			self:Set(value)
			if self.Alive then C.call(self._window, options.OnCommit, self:Get()) end
			return true
		end
		self._render()
		return self
	end
	return M
end
