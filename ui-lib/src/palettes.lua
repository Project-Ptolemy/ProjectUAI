-- Semantic palettes keep content scripts independent of concrete color values.
return function(env)
	local rgb = Color3.fromRGB
	local M = { Names = { "Neutral", "Graphite", "Ocean", "Forest", "Rose", "Halloween", "Christmas", "NewYear",
		"Valentine", "EarthDay", "Pride", "Peace" } }
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
	local seasonal = {
		Halloween = {
			Dark = {
				Canvas = rgb(26, 20, 32), Sidebar = rgb(20, 15, 26), Chrome = rgb(23, 17, 29),
				Surface = rgb(35, 27, 43), Raised = rgb(46, 34, 54), Input = rgb(23, 17, 29),
				Hover = rgb(58, 43, 66), Pressed = rgb(70, 51, 77), Track = rgb(58, 43, 66),
				Border = rgb(116, 85, 126), Subtle = rgb(61, 43, 70), Edge = rgb(84, 60, 96),
				Text = rgb(255, 242, 226), Secondary = rgb(221, 203, 225), Muted = rgb(183, 161, 193),
				Accent = rgb(255, 157, 67), Primary = rgb(255, 157, 67), OnPrimary = rgb(20, 20, 24),
			},
			Light = {
				Canvas = rgb(255, 247, 233), Sidebar = rgb(247, 235, 215), Chrome = rgb(251, 240, 223),
				Surface = rgb(255, 251, 244), Raised = rgb(244, 226, 204), Input = rgb(252, 242, 226),
				Hover = rgb(238, 216, 193), Pressed = rgb(226, 199, 173), Track = rgb(230, 209, 187),
				Border = rgb(166, 135, 108), Subtle = rgb(231, 214, 194), Edge = rgb(214, 188, 161),
				Text = rgb(49, 31, 57), Secondary = rgb(84, 57, 85), Muted = rgb(115, 85, 111),
				Accent = rgb(141, 51, 15), Primary = rgb(141, 51, 15), OnPrimary = rgb(255, 255, 255),
			},
		},
		Christmas = {
			Dark = {
				Canvas = rgb(17, 29, 25), Sidebar = rgb(13, 23, 20), Chrome = rgb(15, 26, 22),
				Surface = rgb(24, 38, 31), Raised = rgb(31, 49, 40), Input = rgb(15, 26, 22),
				Hover = rgb(40, 60, 48), Pressed = rgb(50, 73, 58), Track = rgb(37, 56, 45),
				Border = rgb(88, 124, 101), Subtle = rgb(38, 57, 46), Edge = rgb(62, 91, 73),
				Text = rgb(255, 246, 229), Secondary = rgb(209, 221, 204), Muted = rgb(169, 191, 169),
				Accent = rgb(241, 128, 132), Primary = rgb(239, 199, 124), OnPrimary = rgb(20, 20, 24),
			},
			Light = {
				Canvas = rgb(250, 249, 239), Sidebar = rgb(234, 240, 228), Chrome = rgb(243, 246, 233),
				Surface = rgb(255, 253, 245), Raised = rgb(229, 238, 220), Input = rgb(247, 248, 236),
				Hover = rgb(217, 230, 209), Pressed = rgb(202, 219, 193), Track = rgb(220, 232, 211),
				Border = rgb(132, 158, 125), Subtle = rgb(217, 229, 207), Edge = rgb(189, 209, 178),
				Text = rgb(27, 49, 35), Secondary = rgb(57, 81, 61), Muted = rgb(87, 112, 84),
				Accent = rgb(159, 39, 61), Primary = rgb(32, 83, 48), OnPrimary = rgb(255, 255, 255),
			},
		},
		NewYear = {
			Dark = {
				Canvas = rgb(18, 23, 38), Sidebar = rgb(13, 18, 31), Chrome = rgb(15, 20, 34),
				Surface = rgb(25, 32, 49), Raised = rgb(34, 42, 64), Input = rgb(15, 20, 34),
				Hover = rgb(43, 53, 79), Pressed = rgb(54, 65, 94), Track = rgb(40, 49, 72),
				Border = rgb(98, 113, 155), Subtle = rgb(42, 52, 77), Edge = rgb(67, 82, 117),
				Text = rgb(255, 248, 231), Secondary = rgb(210, 216, 237), Muted = rgb(166, 180, 210),
				Accent = rgb(239, 199, 124), Primary = rgb(239, 199, 124), OnPrimary = rgb(20, 20, 24),
			},
			Light = {
				Canvas = rgb(247, 248, 253), Sidebar = rgb(234, 239, 250), Chrome = rgb(241, 244, 252),
				Surface = rgb(255, 254, 247), Raised = rgb(231, 236, 248), Input = rgb(245, 247, 253),
				Hover = rgb(220, 227, 243), Pressed = rgb(204, 214, 234), Track = rgb(220, 229, 245),
				Border = rgb(138, 153, 181), Subtle = rgb(221, 230, 246), Edge = rgb(194, 206, 228),
				Text = rgb(28, 39, 69), Secondary = rgb(61, 76, 108), Muted = rgb(89, 106, 139),
				Accent = rgb(126, 80, 16), Primary = rgb(37, 55, 98), OnPrimary = rgb(255, 255, 255),
			},
		},
	}
	local function variant(base, overrides)
		local result = {}
		for key, value in pairs(base) do result[key] = value end
		for key, value in pairs(overrides) do result[key] = value end
		return result
	end
	seasonal.Valentine = {
		Dark = variant(seasonal.Halloween.Dark, {
			Canvas = rgb(31, 18, 27), Sidebar = rgb(25, 13, 21), Chrome = rgb(28, 15, 24),
			Surface = rgb(43, 25, 36), Raised = rgb(56, 32, 47), Input = rgb(28, 15, 24),
			Hover = rgb(70, 41, 58), Pressed = rgb(83, 48, 68), Track = rgb(66, 37, 53),
			Border = rgb(141, 87, 114), Subtle = rgb(74, 40, 58), Edge = rgb(105, 61, 83),
			Text = rgb(255, 240, 246), Secondary = rgb(231, 201, 216), Muted = rgb(195, 160, 178),
			Accent = rgb(245, 150, 181), Primary = rgb(245, 150, 181),
		}),
		Light = variant(seasonal.Halloween.Light, {
			Canvas = rgb(255, 245, 248), Sidebar = rgb(250, 231, 240), Chrome = rgb(253, 238, 245),
			Surface = rgb(255, 250, 252), Raised = rgb(245, 220, 233), Input = rgb(254, 241, 246),
			Hover = rgb(240, 207, 224), Pressed = rgb(231, 191, 213), Track = rgb(240, 211, 226),
			Border = rgb(177, 126, 152), Subtle = rgb(241, 214, 229), Edge = rgb(221, 180, 202),
			Text = rgb(68, 29, 49), Secondary = rgb(99, 54, 77), Muted = rgb(124, 82, 105),
			Accent = rgb(141, 35, 73), Primary = rgb(141, 35, 73),
		}),
	}
	seasonal.EarthDay = {
		Dark = variant(seasonal.Christmas.Dark, {
			Canvas = rgb(16, 29, 31), Sidebar = rgb(11, 22, 25), Chrome = rgb(13, 26, 29),
			Surface = rgb(22, 40, 42), Raised = rgb(30, 52, 54), Input = rgb(13, 26, 29),
			Hover = rgb(40, 65, 65), Pressed = rgb(49, 79, 78), Track = rgb(35, 59, 61),
			Border = rgb(88, 135, 127), Subtle = rgb(39, 64, 61), Edge = rgb(60, 103, 93),
			Text = rgb(236, 252, 241), Secondary = rgb(199, 227, 215), Muted = rgb(156, 193, 181),
			Accent = rgb(108, 208, 166), Primary = rgb(147, 207, 237),
		}),
		Light = variant(seasonal.Christmas.Light, {
			Canvas = rgb(242, 251, 245), Sidebar = rgb(227, 242, 233), Chrome = rgb(236, 248, 239),
			Surface = rgb(250, 255, 248), Raised = rgb(217, 237, 224), Input = rgb(239, 249, 243),
			Hover = rgb(205, 230, 215), Pressed = rgb(190, 218, 202), Track = rgb(209, 232, 219),
			Border = rgb(117, 159, 139), Subtle = rgb(211, 234, 222), Edge = rgb(177, 208, 190),
			Text = rgb(25, 54, 46), Secondary = rgb(49, 83, 73), Muted = rgb(76, 112, 97),
			Accent = rgb(24, 103, 75), Primary = rgb(25, 72, 97),
		}),
	}
	seasonal.Pride = {
		Dark = variant(seasonal.Halloween.Dark, {
			Canvas = rgb(25, 20, 37), Sidebar = rgb(19, 15, 29), Chrome = rgb(22, 17, 33),
			Surface = rgb(34, 28, 49), Raised = rgb(46, 37, 65), Input = rgb(22, 17, 33),
			Hover = rgb(59, 47, 80), Pressed = rgb(72, 57, 94), Track = rgb(53, 42, 75),
			Border = rgb(95, 164, 177), Subtle = rgb(61, 46, 84), Edge = rgb(79, 85, 117),
			Text = rgb(249, 242, 255), Secondary = rgb(221, 207, 240), Muted = rgb(180, 166, 206),
			Accent = rgb(191, 164, 255), Primary = rgb(245, 146, 208),
		}),
		Light = variant(seasonal.Halloween.Light, {
			Canvas = rgb(250, 245, 255), Sidebar = rgb(241, 232, 253), Chrome = rgb(246, 239, 255),
			Surface = rgb(255, 251, 255), Raised = rgb(231, 222, 249), Input = rgb(249, 241, 255),
			Hover = rgb(222, 211, 243), Pressed = rgb(208, 193, 235), Track = rgb(225, 216, 247),
			Border = rgb(112, 165, 177), Subtle = rgb(226, 216, 245), Edge = rgb(169, 191, 210),
			Text = rgb(47, 29, 70), Secondary = rgb(75, 53, 104), Muted = rgb(107, 82, 133),
			Accent = rgb(107, 53, 168), Primary = rgb(142, 33, 110),
		}),
	}
	seasonal.Peace = {
		Dark = variant(seasonal.NewYear.Dark, {
			Canvas = rgb(20, 29, 35), Sidebar = rgb(15, 23, 29), Chrome = rgb(17, 26, 32),
			Surface = rgb(28, 39, 46), Raised = rgb(37, 51, 59), Input = rgb(17, 26, 32),
			Hover = rgb(47, 64, 73), Pressed = rgb(59, 77, 88), Track = rgb(42, 58, 67),
			Border = rgb(100, 141, 157), Subtle = rgb(45, 64, 73), Edge = rgb(71, 105, 120),
			Text = rgb(239, 250, 252), Secondary = rgb(206, 227, 233), Muted = rgb(164, 191, 201),
			Accent = rgb(136, 203, 221), Primary = rgb(156, 197, 245),
		}),
		Light = variant(seasonal.NewYear.Light, {
			Canvas = rgb(245, 251, 253), Sidebar = rgb(232, 243, 247), Chrome = rgb(240, 248, 251),
			Surface = rgb(252, 255, 255), Raised = rgb(224, 239, 245), Input = rgb(242, 249, 252),
			Hover = rgb(211, 230, 239), Pressed = rgb(195, 218, 230), Track = rgb(215, 234, 243),
			Border = rgb(127, 162, 180), Subtle = rgb(218, 237, 245), Edge = rgb(182, 210, 223),
			Text = rgb(31, 50, 62), Secondary = rgb(58, 80, 94), Muted = rgb(83, 111, 130),
			Accent = rgb(31, 99, 122), Primary = rgb(34, 75, 115),
		}),
	}
	function M.isSeasonal(name) return seasonal[name] ~= nil end
	function M.valid(name)
		return name == "Neutral" or accents[name] ~= nil or seasonal[name] ~= nil
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
		if seasonal[name] then for key, value in pairs(seasonal[name][mode]) do result[key] = value end end
		result.OnAccent = env.require("contrast").foreground(result.Accent)
		return result
	end
	return M
end
