-- A density changes spacing together with targets. Touch retains its minimum
-- target even when the user prefers compact desktop spacing.
return function(env)
	local M = { Names = { "Comfortable", "Compact", "Spacious" } }
	local presets = {
		Comfortable = { Target = 40, Pad = 20, MobilePad = 12, RowX = 16, RowY = 14, Gap = 12, SectionGap = 20 },
		Compact = { Target = 36, Pad = 14, MobilePad = 10, RowX = 12, RowY = 9, Gap = 8, SectionGap = 14 },
		Spacious = { Target = 46, Pad = 24, MobilePad = 16, RowX = 20, RowY = 18, Gap = 16, SectionGap = 26 },
	}
	function M.valid(name) return presets[name] ~= nil end
	function M.resolve(name, touch, scale)
		local preset = presets[name or "Comfortable"]
		assert(preset, "Unknown density: " .. tostring(name))
		local result = {}
		for key, value in pairs(preset) do result[key] = value end
		result.Target = math.max(preset.Target, touch and 44 or 0, math.ceil(36 * (scale or 1)))
		return result
	end
	return M
end
