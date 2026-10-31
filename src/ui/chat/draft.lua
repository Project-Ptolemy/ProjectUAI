-- Recovery status and deliberate draft actions, independent of provider requests.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	function M.open(composer, session)
		if not composer or not composer.isAlive() or not session then return nil end
		local text = composer.field.get()
		local label, metrics = env.require("runtime/text_metrics").label(text)
		local modal = overlay.modal({ title = "Draft details", width = theme.size.modal })
		if not modal then return nil end
		P.text(modal.content, { text = label .. " / " .. tostring(metrics.lines) .. " lines", role = "label",
			wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
		local status = session.ephemeral and "This conversation is not saved. Its draft lasts until the client closes."
			or not env.require("runtime/fsx").enabled and "File storage is unavailable. Copy this draft before closing."
			or session.draftError or "Draft recovery saves with this conversation after typing pauses. Attached files are checked again when sent."
		P.text(modal.content, { name = "DraftRecovery", text = status, role = "small", color = theme.color.textSecondary,
			wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "CopyDraft", text = "Copy text", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function()
				local ok, why = env.require("runtime/clipboard").write(text)
				overlay.toast(ok and "Draft text copied." or tostring(why), ok and "info" or "warn")
			end })
		return modal
	end
	return M
end
