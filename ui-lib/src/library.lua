return function(env)
	local Window = env.require("window")
	local C, T = env.require("core"), env.require("theme")
	local appearance = env.require("appearance")
	local methods = env.require("config")
	for _, id in ipairs({ "values", "tasks", "profiles" }) do
		for name, method in pairs(env.require(id)) do if name:match("^%u") then methods[name] = method end end
	end
	function methods.GetAppearance(self)
		return { Theme = self._themeName, Accent = self._accent, Colors = C.copy(self._colors or {}),
			CornerRadius = self.CornerRadius or T.Size.Radius, TextScale = self.TextScale, ReducedMotion = self.ReducedMotion,
			Palette = self.Palette, Contrast = self.Contrast, Density = self.Density, Shape = self.Shape,
			Typography = self.Typography, TabHeader = self.TabHeader }
	end
	function methods.SetAppearance(self, options)
		assert(self.Alive, "Window is destroyed")
		local value = T.normalizeAppearance(options, self:GetAppearance())
		local palette = T.resolve(value.Theme, value.Accent, value.Colors, value.Palette, value.Contrast)
		self.Theme, self._themeName, self._accent, self._colors = palette, value.Theme, value.Accent, value.Colors
		self.CornerRadius, self.TextScale = value.CornerRadius, value.TextScale
		self.Palette, self.Contrast, self.Density, self.Shape = value.Palette, value.Contrast, value.Density, value.Shape
		self.Typography, self.TabHeader = value.Typography, value.TabHeader
		if options.ReducedMotion ~= nil then self._motionOverride = value.ReducedMotion end
		self.ReducedMotion = value.ReducedMotion
		if self._themeIcon then self._themeIcon(value.Theme == "Light") end
		self:_Refresh()
		self:_Layout()
		self:_Filter()
		if self._appearanceSync then self._appearanceSync() end
		return self
	end
	function methods.ResetAppearance(self)
		local value = C.copy(self._appearanceDefaults)
		if value.Accent == nil then value.Accent = false end
		self:SetAppearance(value)
		self._motionOverride = self._appearanceMotionOverride
		if self._motionOverride == nil then
			pcall(function() self.ReducedMotion = env.services.GuiService.ReducedMotionEnabled == true end)
			if self._appearanceSync then self._appearanceSync() end
		end
		return self
	end
	function methods.SetTheme(self, name, accent)
		if name == nil then name = "Dark" end
		assert(accent ~= false, "Accent must be a Color3")
		if accent == nil then accent = false end
		return self:SetAppearance({ Theme = name, Accent = accent })
	end
	-- Keep existing setters reflected in the automatic preferences without firing
	-- application callbacks, including changes made by a host script.
	for _, name in ipairs({ "SetTextScale", "SetReducedMotion" }) do
		local original = Window[name]
		methods[name] = function(self, ...)
			local result = original(self, ...)
			if self._appearanceSync then self._appearanceSync() end
			return result
		end
	end
	C.elevate(methods)
	for name, method in pairs(methods) do Window[name] = method end
	local UI = { Version = env.metadata.version, URL = env.metadata.url, Repository = env.metadata.repository }
	function UI:CreateWindow(options)
		options = options or {}
		local window = Window.new(options)
		window._appearanceDefaults = window:GetAppearance()
		window._appearanceMotionOverride = window._motionOverride
		window._mountingAppearance = true
		appearance.mount(window)
		window._mountingAppearance = nil
		return window
	end
	function UI:GetWindow(id) return env.windows[id] end
	function UI:GetAppearanceOptions() return T.options() end
	function UI:GetPalette(name, mode)
		return T.resolve(mode, nil, nil, name)
	end
	function UI:DestroyAll()
		local windows = {}
		for _, window in pairs(env.windows) do windows[#windows + 1] = window end
		for _, window in ipairs(windows) do window:Destroy() end
	end
	return C.elevate(UI)
end
