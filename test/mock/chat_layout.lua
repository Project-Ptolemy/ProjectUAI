-- Publish fixed spacer/list geometry that the general mock intentionally omits.
-- This fixture does not approximate text shaping or claim native layout coverage.
local M = {}
local function measure(h, view, targetY)
	local frame, V = view.scroll.instance, h.dt.Vector2
	local pad = frame:FindFirstChildOfClass("UIPadding")
	local top, bottom = pad and pad.PaddingTop.Offset or 0, pad and pad.PaddingBottom.Offset or 0
	local gap, children = view.scroll.layout.Padding.Offset, {}
	for index, child in ipairs(frame:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then children[#children + 1] = { node = child, index = index } end
	end
	table.sort(children, function(a, b)
		if a.node.LayoutOrder == b.node.LayoutOrder then return a.index < b.index end
		return a.node.LayoutOrder < b.node.LayoutOrder
	end)
	local offset, y = top, targetY or frame.CanvasPosition.Y
	for _, entry in ipairs(children) do
		local child = entry.node
		local height = math.max(0, child.Size.Y.Offset)
		child.AbsolutePosition = V.new(frame.AbsolutePosition.X, frame.AbsolutePosition.Y + offset - y)
		child.AbsoluteSize = V.new(frame.AbsoluteSize.X, height)
		offset = offset + height + gap
	end
	local content = math.max(0, offset - top - (#children > 0 and gap or 0))
	frame.AbsoluteWindowSize = frame.AbsoluteSize
	view.scroll.layout.AbsoluteContentSize = V.new(frame.AbsoluteSize.X, content)
	frame.AbsoluteCanvasSize = V.new(frame.AbsoluteSize.X, top + content + bottom)
end
function M.scroll(h, view, y)
	measure(h, view, y)
	view.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, y)
end
function M.settle(h, view, seconds)
	for _ = 1, math.max(1, math.ceil((seconds or 0.3) / 0.05)) do
		measure(h, view)
		h.settle(0.05)
	end
end
return M
