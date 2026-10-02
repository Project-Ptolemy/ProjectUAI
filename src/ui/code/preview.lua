-- Copyable native source preview shared by Code detail panes.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local M = {}
	function M.new(parent, source, name)
		local scroll = P.scroll(parent, { name = name or "SourcePreview", bg = theme.color.codeSurface })
		scroll.layout:Destroy(); scroll.instance.AutomaticCanvasSize = Enum.AutomaticSize.None; scroll.instance.ScrollingDirection = Enum.ScrollingDirection.XY
		local field = P.field(scroll.instance, { name = "PreviewText", role = "mono", multiline = true, bare = true, syntax = false, text = source, padX = theme.space.xl / 2 })
		field.instance.TextEditable, field.instance.TextWrapped, field.instance.TextTransparency = false, false, 0
		field.instance.TextColor3 = theme.color.codeText
		local function layout()
			local measured = P.measureText(source, { role = "mono" })
			local width, height = math.max(scroll.instance.AbsoluteSize.X, measured.X + theme.space.md * 2), math.max(scroll.instance.AbsoluteSize.Y, measured.Y + theme.space.md * 2)
			field.shell.Size, scroll.instance.CanvasSize = UDim2.fromOffset(width, height), UDim2.fromOffset(width, height)
		end
		scroll.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout); layout()
		return { root = scroll.instance, box = field.instance, destroy = function() scroll.instance:Destroy() end }
	end
	return M
end
