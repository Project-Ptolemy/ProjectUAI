-- Semantic palettes keep content scripts independent of concrete color values.
return function(env)
	local rgb = Color3.fromRGB
	local M = { Names = { "Neutral", "Graphite", "Ocean", "Forest", "Rose" } }
	local modes = {
		Dark = {
			Canvas = rgb(24, 24, 27), Sidebar = rgb(19, 19, 22), Chrome = rgb(22, 22, 25),
			Surface = rgb(31, 31, 35), Raised = rgb(41, 41, 46), Input = rgb(23, 23, 26),
			Hover = rgb(51, 51, 57), Pressed = rgb(62, 62, 69), Track = rgb(49, 49, 56),
			Border = rgb(87, 87, 97), Subtle = rgb(48, 48, 55), Edge = rgb(65, 65, 74),
			Text = rgb(244, 244, 246), Secondary = rgb(200, 200, 209), Muted = rgb(163, 163, 175), Disabled = rgb(111, 111, 124),
			Accent = rgb(196, 199, 209), OnAccent = rgb(20, 20, 24), Primary = rgb(237, 238, 242), OnPrimary = rgb(20, 20, 24),
			Success = rgb(125, 211, 167), Warning = rgb(237, 193, 119), Danger = rgb(247, 145, 151), Scrim = rgb(7, 9, 12),
		},
		Light = {
			Canvas = rgb(247, 247, 249), Sidebar = rgb(239, 239, 242), Chrome = rgb(244, 244, 246),
			Surface = rgb(255, 255, 255), Raised = rgb(235, 235, 240), Input = rgb(247, 247, 249),
			Hover = rgb(229, 229, 236), Pressed = rgb(215, 215, 225), Track = rgb(223, 223, 232),
			Border = rgb(161, 161, 177), Subtle = rgb(224, 224, 232), Edge = rgb(204, 204, 216),
			Text = rgb(29, 29, 36), Secondary = rgb(70, 70, 85), Muted = rgb(102, 102, 120), Disabled = rgb(141, 141, 157),
			Accent = rgb(75, 78, 92), OnAccent = rgb(255, 255, 255), Primary = rgb(34, 34, 43), OnPrimary = rgb(255, 255, 255),
			Success = rgb(26, 117, 76), Warning = rgb(136, 87, 21), Danger = rgb(179, 49, 65), Scrim = rgb(7, 9, 12),
		},
	}
	local accents = {
		Graphite = { Dark = rgb(235, 148, 117), Light = rgb(167, 69, 44) },
		Ocean = { Dark = rgb(125, 184, 246), Light = rgb(30, 94, 169) },
		Forest = { Dark = rgb(136, 203, 158), Light = rgb(38, 111, 70) },
		Rose = { Dark = rgb(227, 153, 194), Light = rgb(155, 56, 111) },
	}
	function M.valid(name)
		return name == "Neutral" or accents[name] ~= nil
	end
	function M.resolve(mode, name)
		if mode == nil then mode = "Dark" end
		if name == nil then name = "Neutral" end
		assert(modes[mode], "Theme must be Dark or Light")
		assert(M.valid(name), "Unknown palette: " .. tostring(name))
		local result = {}
		for key, value in pairs(modes[mode]) do result[key] = value end
		if accents[name] then
			result.Accent = accents[name][mode]
			-- Tint only neutral surfaces; text and status retain their semantics.
			for _, key in ipairs({ "Canvas", "Sidebar", "Chrome", "Raised", "Input" }) do
				result[key] = result[key]:Lerp(result.Accent, mode == "Dark" and 0.025 or 0.015)
			end
		end
		result.OnAccent = env.require("contrast").foreground(result.Accent)
		return result
	end
	return M
end
