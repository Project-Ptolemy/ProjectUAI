-- Relative luminance and foreground selection are shared by built-in palettes
-- and user overrides. High contrast changes semantics, never application values.
return function(env)
	local M = {}
	local function linear(value)
		return value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
	end
	function M.luminance(color)
		return linear(color.R) * 0.2126 + linear(color.G) * 0.7152 + linear(color.B) * 0.0722
	end
	function M.ratio(a, b)
		local x, y = M.luminance(a), M.luminance(b)
		return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
	end
	function M.foreground(color)
		local black, white = Color3.new(0, 0, 0), Color3.new(1, 1, 1)
		return M.ratio(color, black) >= M.ratio(color, white) and black or white
	end
	function M.ensure(color, background, minimum)
		if M.ratio(color, background) >= minimum then return color end
		local target = M.foreground(background)
		for index = 1, 20 do
			local candidate = color:Lerp(target, index / 20)
			if M.ratio(candidate, background) >= minimum then return candidate end
		end
		return target
	end
	function M.apply(palette, mode)
		assert(mode == nil or mode == "Standard" or mode == "High", "Contrast must be Standard or High")
		if mode ~= "High" then return palette end
		local foreground = M.foreground(palette.Canvas)
		palette.Text, palette.Secondary, palette.Muted = foreground, foreground, foreground
		palette.Edge = M.ensure(palette.Edge, palette.Surface, 3)
		palette.Border = M.ensure(palette.Border, palette.Input, 3)
		palette.Subtle = M.ensure(palette.Subtle, palette.Surface, 3)
		for _, key in ipairs({ "Accent", "Success", "Warning", "Danger" }) do
			palette[key] = M.ensure(palette[key], palette.Surface, 4.5)
		end
		palette.OnAccent, palette.OnPrimary = M.foreground(palette.Accent), M.foreground(palette.Primary)
		return palette
	end
	return M
end
