-- Profiles retain semantic choices and advanced overrides in one place. Older
-- format-1 profiles omit new fields and preserve the window's current choices.
return function(env)
	local C, T = env.require("core"), env.require("theme")
	local M = {}
	local fields = {
		palette = "Palette", contrast = "Contrast", density = "Density", shape = "Shape",
		typography = "Typography", tabHeader = "TabHeader", cornerRadius = "CornerRadius",
		textScale = "TextScale", reducedMotion = "ReducedMotion", seasonalTheme = "SeasonalTheme",
	}
	local function encodeColor(color) return { color.R, color.G, color.B } end
	local function decodeColor(rgb, label)
		assert(type(rgb) == "table" and #rgb == 3, "Invalid appearance " .. label)
		for key in pairs(rgb) do assert(key == 1 or key == 2 or key == 3, "Invalid appearance " .. label) end
		for index = 1, 3 do
			assert(C.finite(rgb[index]) and rgb[index] >= 0 and rgb[index] <= 1, "Invalid appearance " .. label)
		end
		return Color3.new(rgb[1], rgb[2], rgb[3])
	end
	function M.encode(current)
		local result = { theme = current.Theme, colors = {} }
		for key, field in pairs(fields) do result[key] = current[field] end
		if current.Accent then result.accent = encodeColor(current.Accent) end
		for token, color in pairs(current.Colors) do result.colors[token] = encodeColor(color) end
		return result
	end
	function M.decode(value, current)
		assert(type(value) == "table" and (value.theme == "Dark" or value.theme == "Light"), "Invalid appearance theme")
		local patch = { Theme = value.theme, Accent = false }
		for key, field in pairs(fields) do patch[field] = value[key] end
		if value.accent ~= nil then patch.Accent = decodeColor(value.accent, "accent") end
		if value.colors ~= nil then
			assert(type(value.colors) == "table", "Invalid appearance colors")
			patch.Colors = {}
			for token, rgb in pairs(value.colors) do
				assert(type(token) == "string", "Invalid appearance color name")
				patch.Colors[token] = decodeColor(rgb, "color " .. token)
			end
		end
		T.normalizeAppearance(patch, current)
		return patch
	end
	return M
end
