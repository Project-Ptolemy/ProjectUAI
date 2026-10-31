-- Appearance is an atomic semantic preference set shared by every component.
return function(env)
	local palettes, contrast = env.require("palettes"), env.require("contrast")
	local density, shape, typography = env.require("density"), env.require("shape"), env.require("typography")
	local M = { Dark = palettes.resolve("Dark"), Light = palettes.resolve("Light") }
	M.Size = {
		Target = 40, TouchTarget = 44, TouchSlop = 8, Gap = 12, Pad = 20, MobilePad = 12,
		Header = 72, Footer = 30, Sidebar = 196, Tabs = 52, Avatar = 36,
		Radius = 10, FieldRadius = 6, Scrollbar = 3, Width = 780, Height = 580, Compact = 640,
	}
	M.Type = { Display = 26, Title = 20, Heading = 15, Body = 14, Caption = 12, Small = 11, Eyebrow = 10 }
	M.Motion = { Fast = 0.10, Enter = 0.16, Toggle = 0.14, Press = 0.06 }
	local function color(value, label)
		assert(typeof(value) == "Color3", label .. " must be a Color3")
		for _, channel in ipairs({ value.R, value.G, value.B }) do
			assert(channel == channel and channel >= 0 and channel <= 1, label .. " components must be between 0 and 1")
		end
		return value
	end
	function M.defaults()
		return { Theme = "Dark", Palette = "Neutral", Contrast = "Standard", Density = "Comfortable",
			Shape = "Rounded", Typography = "Sans", TabHeader = "Simple", Colors = {},
			CornerRadius = shape.radius("Rounded"), TextScale = 1, ReducedMotion = false, SeasonalTheme = true }
	end
	function M.normalizeAppearance(options, current)
		assert(type(options) == "table", "Appearance must be a table")
		local result = M.defaults()
		for key, value in pairs(current or {}) do result[key] = value end
		for key, value in pairs(options) do
			if key == "Theme" then assert(value == "Dark" or value == "Light", "Theme must be Dark or Light")
			elseif key == "Palette" then assert(palettes.valid(value), "Unknown Palette")
			elseif key == "Contrast" then assert(value == "Standard" or value == "High", "Contrast must be Standard or High")
			elseif key == "Density" then assert(density.valid(value), "Unknown Density")
			elseif key == "Shape" then assert(shape.valid(value) or value == "Custom", "Unknown Shape")
			elseif key == "Typography" then assert(typography.valid(value), "Unknown Typography")
			elseif key == "TabHeader" then assert(value == "Simple" or value == "Detailed" or value == "Hidden", "Unknown TabHeader")
			elseif key == "Accent" then if value ~= false then color(value, "Accent") end
			elseif key == "Colors" then assert(type(value) == "table", "Colors must be a table")
			elseif key == "ReducedMotion" or key == "SeasonalTheme" then assert(type(value) == "boolean", key .. " must be a boolean")
			elseif key == "CornerRadius" or key == "TextScale" then
				local low, high = key == "CornerRadius" and 0 or 0.85, key == "CornerRadius" and 16 or 1.5
				assert(type(value) == "number" and value == value and value >= low and value <= high, key .. " is outside its supported range")
			else error("Unknown appearance option: " .. tostring(key)) end
			result[key] = value
		end
		if options.Shape and options.Shape ~= "Custom" and options.CornerRadius == nil then result.CornerRadius = shape.radius(options.Shape) end
		if options.CornerRadius ~= nil then result.Shape = shape.infer(options.CornerRadius) end
		assert(options.Shape ~= "Custom" or options.CornerRadius ~= nil or current and current.Shape == "Custom", "Custom Shape needs CornerRadius")
		if result.Accent == false then result.Accent = nil end
		local colors = {}
		for key, value in pairs(result.Colors or {}) do
			assert(M.Dark[key] ~= nil or key == "Selected" or key == "AccentSoft", "Unknown color token: " .. tostring(key))
			assert(key ~= "Accent", "Use Accent to customize the accent color")
			colors[key] = color(value, "Colors." .. key)
		end
		result.Colors = colors
		return result
	end
	function M.resolve(name, accent, colors, palette, contrastMode)
		local result = palettes.resolve(name, palette)
		if accent ~= nil then result.Accent = color(accent, "Accent") end
		for key, value in pairs(colors or {}) do result[key] = value end
		if accent then result.OnAccent = colors and colors.OnAccent or contrast.foreground(result.Accent) end
		if colors and colors.Primary and not colors.OnPrimary then result.OnPrimary = contrast.foreground(result.Primary) end
		contrast.apply(result, contrastMode)
		result.Selected = colors and colors.Selected or result.Raised:Lerp(result.Accent, 0.16)
		result.AccentSoft = colors and colors.AccentSoft or result.Surface:Lerp(result.Accent, 0.12)
		return result
	end
	function M.options()
		local function copy(list) local out = {}; for i, value in ipairs(list) do out[i] = value end; return out end
		return { Theme = { "Dark", "Light" }, Palette = copy(palettes.Names), Contrast = { "Standard", "High" },
			Density = copy(density.Names), Shape = copy(shape.Names), Typography = copy(typography.Names),
			TabHeader = { "Simple", "Detailed", "Hidden" } }
	end
	return M
end
