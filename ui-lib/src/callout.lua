-- A semantic message with an optional domain action. Tones are shared with
-- validation and status controls and remain legible across appearance presets.
return function(env)
	local C = env.require("core")
	local M = {}
	local tones = { Info = "Accent", Success = "Success", Warning = "Warning", Danger = "Danger" }
	function M.Callout(section, options)
		options = C.copy(options)
		local tone = options.Kind or "Info"
		assert(tones[tone], "Unknown callout Kind")
		local controls = env.require("controls")
		local prepared = C.copy(options)
		prepared.Description = options.Content or options.Description or ""
		local self = controls.base(section, "Callout", prepared, options.ActionText and "stack" or "content")
		self.Persist, self.StatusKind = false, tone
		local stripe = C.node(self, "Frame", self.Frame, {
			Name = "CalloutTone", Position = UDim2.fromOffset(0, 8), Size = UDim2.new(0, 3, 1, -16),
		}, { BackgroundColor3 = function(theme) return theme[tones[tone]] end })
		C.corner(stripe, 1)
		C.bind(self, self._label, { TextColor3 = function(theme) return theme[tones[tone]] end })
		if options.ActionText then
			self.Loading = false
			local button, label, refresh = controls.action(self, tostring(options.ActionText))
			self._render = function() label.Text = self.Loading and "Working" or tostring(options.ActionText); refresh() end
			function self:Press()
				if not self:_Interactive() or self.Loading then return false end
				self.Loading = true; self._render()
				self._scope:Spawn(function()
					C.call(self._window, options.Callback)
					if self.Alive then self.Loading = false; self._render() end
				end)
				return true
			end
			self._scope:Connect(button.Activated, function() self:Press() end)
		end
		function self:SetKind(kind)
			assert(self.Alive, "Control is destroyed")
			assert(tones[kind], "Unknown callout Kind")
			tone, self.StatusKind = kind, kind
			self._window:_Refresh()
			return self
		end
		function self:SetContent(text) return self:SetDescription(text) end
		self._layout()
		return self
	end
	return M
end
