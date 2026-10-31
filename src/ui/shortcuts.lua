return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	function M.open()
		local modal = overlay.modal({ title = "Keyboard shortcuts", width = theme.size.modal,
			description = "Available with the UAI window open and no text field or dialog focused." })
		if not modal then return nil end
		for index, entry in ipairs(env.require("runtime/shortcuts").items) do
			P.text(modal.content, { name = "Shortcut_" .. entry.id, text = entry.display .. "  —  " .. entry.label,
				role = "small", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = index })
		end
		P.text(modal.content, { text = "In command search, use Up/Down to choose and Enter to open. On touch devices, tap a result.",
			role = "caption", auto = "Y", wrap = true, color = theme.color.textSecondary,
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 20 })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		return modal
	end
	return M
end
