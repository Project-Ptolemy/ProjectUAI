-- Inspect and remove draft attachments without opening or executing their files.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local summary = env.require("runtime/attachment_summary")
	local M = {}
	function M.open(entries, remove)
		local modal = overlay.modal({ title = "Draft attachments", description = "Removing an attachment keeps its original file.", width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		for index, entry in ipairs(entries) do
			local value = summary.describe(entry)
			local card = P.column(modal.content, { auto = "Y", gap = theme.space.xs, padding = theme.space.sm,
				bg = theme.color.surfaceRaised, radius = theme.radius.md, layoutOrder = index })
			P.text(card, { text = value.label, role = "label", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
			P.text(card, { text = value.detail, role = "small", color = theme.color.textSecondary, wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
			if value.path then P.button(card, { text = "Copy path", variant = "ghost", size = "sm", layoutOrder = 3, onClick = function()
				local ok, why = env.require("runtime/clipboard").write(value.path); overlay.toast(ok and "Attachment path copied." or tostring(why), ok and "info" or "warn")
			end }) end
			P.button(card, { name = "RemoveDraftAttachment_" .. tostring(index), text = "Remove attachment", variant = "secondary", size = "sm", layoutOrder = 4,
				onClick = function() if remove(entry) then card:Destroy() end end })
		end
		P.button(modal.footer, { text = "Done", variant = "ghost", size = "sm", onClick = modal.close })
		return modal
	end
	return M
end
