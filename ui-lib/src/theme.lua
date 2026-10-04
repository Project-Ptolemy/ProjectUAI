-- Graphite chrome, inset surfaces and a warm signal color. Window surfaces use
-- opaque native UI; consumer scripts continue to own only content and behavior.
return function(env)
	local rgb = Color3.fromRGB
	local M = {}
	M.Dark = {
		Canvas = rgb(23, 25, 29), Sidebar = rgb(17, 19, 22), Chrome = rgb(20, 22, 26),
		Surface = rgb(30, 33, 38), Raised = rgb(39, 43, 49), Input = rgb(22, 25, 29),
		Hover = rgb(48, 52, 59), Pressed = rgb(59, 64, 72), Track = rgb(47, 52, 61),
		Border = rgb(79, 85, 95), Subtle = rgb(46, 51, 59), Edge = rgb(61, 67, 77),
		Text = rgb(242, 243, 245), Secondary = rgb(193, 198, 207),
		Muted = rgb(153, 161, 174), Disabled = rgb(106, 113, 124),
		Accent = rgb(235, 148, 117), OnAccent = rgb(22, 24, 28),
		Primary = rgb(244, 240, 232), OnPrimary = rgb(22, 24, 28),
		Success = rgb(125, 211, 167), Warning = rgb(237, 193, 119),
		Danger = rgb(247, 145, 151), Scrim = rgb(7, 9, 12),
	}
	M.Light = {
		Canvas = rgb(246, 247, 249), Sidebar = rgb(236, 238, 242), Chrome = rgb(241, 243, 246),
		Surface = rgb(255, 255, 255), Raised = rgb(233, 236, 241), Input = rgb(246, 247, 249),
		Hover = rgb(226, 230, 237), Pressed = rgb(212, 218, 228), Track = rgb(221, 226, 234),
		Border = rgb(157, 166, 181), Subtle = rgb(221, 226, 234), Edge = rgb(203, 210, 221),
		Text = rgb(28, 33, 42), Secondary = rgb(65, 75, 91),
		Muted = rgb(98, 108, 125), Disabled = rgb(139, 148, 163),
		Accent = rgb(167, 69, 44), OnAccent = rgb(255, 255, 255),
		Primary = rgb(31, 37, 47), OnPrimary = rgb(255, 255, 255),
		Success = rgb(26, 117, 76), Warning = rgb(136, 87, 21),
		Danger = rgb(179, 49, 65), Scrim = rgb(7, 9, 12),
	}
	M.Size = {
		Target = 40, TouchTarget = 44, TouchSlop = 8, Gap = 12, Pad = 20, MobilePad = 12,
		Header = 80, Footer = 30, Sidebar = 196, Tabs = 52, Avatar = 36,
		Radius = 18, FieldRadius = 10, Scrollbar = 3,
		Width = 780, Height = 580, Compact = 640,
	}
	M.Type = { Display = 26, Title = 20, Heading = 15, Body = 14, Caption = 12, Small = 11, Eyebrow = 10 }
	M.Motion = { Fast = 0.10, Enter = 0.16, Toggle = 0.14, Press = 0.06 }
	local function linear(channel)
		if channel <= 0.04045 then return channel / 12.92 end
		return ((channel + 0.055) / 1.055) ^ 2.4
	end
	function M.resolve(name, accent)
		assert(name == nil or name == "Dark" or name == "Light", "Theme must be Dark or Light")
		local result = {}
		for key, value in pairs(M[name or "Dark"]) do result[key] = value end
		if accent ~= nil then
			assert(typeof(accent) == "Color3", "Accent must be a Color3")
			for _, channel in ipairs({ accent.R, accent.G, accent.B }) do
				assert(channel == channel and channel >= 0 and channel <= 1, "Accent components must be between 0 and 1")
			end
			result.Accent = accent
			-- Compare actual sRGB contrast, rather than brightness in gamma space.
			local luminance = linear(accent.R) * 0.2126 + linear(accent.G) * 0.7152 + linear(accent.B) * 0.0722
			result.OnAccent = (luminance + 0.05) / 0.05 >= 1.05 / (luminance + 0.05) and rgb(0, 0, 0) or rgb(255, 255, 255)
		end
		result.Selected = result.Raised:Lerp(result.Accent, 0.16)
		result.AccentSoft = result.Surface:Lerp(result.Accent, 0.12)
		return result
	end
	return M
end
