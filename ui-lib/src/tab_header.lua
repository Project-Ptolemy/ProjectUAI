-- Simple titles are the neutral default. Detailed introductions remain useful
-- for dashboards, while Hidden makes compact utility tabs content-first.
return function(env)
	local C = env.require("core")
	local typography = env.require("typography")
	local M = {}
	function M.mount(tab)
		local window = tab._window
		local intro = C.node(tab, "Frame", tab.Frame, {
			Name = "TabHeading", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 0,
		})
		tab._intro = intro
		local eyebrow = C.text(tab, intro, "WORKSPACE", "Eyebrow", "Muted", { TextWrapped = false })
		local heading = C.text(tab, intro, tab.Title, "Title", "Text", { TextYAlignment = Enum.TextYAlignment.Top })
		tab._heading = heading
		tab._summary = C.text(tab, intro, "", "Caption", "Muted", { TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		C.bind(tab, heading, {
			TextSize = function() return math.floor((window.TabHeader == "Detailed" and 26 or 20) * window.TextScale + 0.5) end,
			Font = function() return typography.font(window.Typography, window.TabHeader == "Detailed" and "Display" or "Title") end,
		})
		C.reflow(tab, function()
			local detailed = window.TabHeader == "Detailed"
			local width = math.max(1, window._contentWidth - window._contentPad * 2)
			local top = detailed and math.ceil(20 * window.TextScale) or 0
			local titleHeight = C.measure(tab.Title, heading.TextSize, width, heading.Font)
			local detail = detailed and math.ceil(18 * window.TextScale) or 0
			eyebrow.Visible, tab._summary.Visible = detailed, detailed
			eyebrow.Size = UDim2.new(1, 0, 0, math.ceil(14 * window.TextScale))
			heading.Position, heading.Size = UDim2.fromOffset(0, top), UDim2.new(1, 0, 0, titleHeight)
			tab._summary.Position = UDim2.fromOffset(0, top + titleHeight + 6)
			tab._summary.Size = UDim2.new(1, 0, 0, detail)
			intro.Size = UDim2.new(1, 0, 0, top + titleHeight + detail + (detailed and 8 or 2))
			intro.Visible = window.TabHeader ~= "Hidden" and tab._introMatches ~= false
		end)
		return heading
	end
	return M
end
