-- Export operates on a snapshot made when opened, so background replies cannot change it.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local caps = env.require("runtime/caps")
	local fsx = env.require("runtime/fsx")
	local util = env.require("runtime/util")
	local exporter = env.require("runtime/transcript_export")
	local M = {}
	function M.open(session)
		local text, receipt = exporter.markdown(session)
		if not text then overlay.toast(receipt, "warn", 4); return nil end
		local modal = overlay.modal({ title = "Export conversation", width = theme.size.modal,
			description = "Markdown includes retained messages and replies. Review personal text before sharing." })
		if not modal then return nil end
		P.text(modal.content, { text = util.pluralise(receipt.messages, "message") .. " · " .. util.formatNumber(#text) .. " bytes",
			role = "small", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
		P.text(modal.content, { text = "Tool arguments, request headers and hidden reasoning are excluded. History limits may have removed earlier dialogue.",
			role = "caption", color = theme.color.textSecondary, auto = "Y", wrap = true,
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		local feedback = P.text(modal.content, { name = "ExportFeedback", text = receipt.limited and "Export reached its size limit." or "",
			role = "caption", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		local preview = P.field(modal.content, { name = "ExportPreview", text = util.truncate(text, 12000),
			multiline = true, role = "small", height = theme.size.control * 5, layoutOrder = 4 })
		preview.instance.TextEditable = false
		if #text > 12000 then P.text(modal.content, { text = "Preview shows the beginning; copy and save include the full export.",
			role = "caption", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 5 }) end
		if not caps.clipboard and not fsx.enabled then feedback.Text = "Select text in the preview to copy it manually." end
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		if caps.clipboard then
			P.button(modal.footer, { name = "CopyConversation", text = "Copy Markdown", variant = "secondary", size = "sm", layoutOrder = 2,
				onClick = function()
					local ok, why = env.require("runtime/clipboard").write(text)
					if not modal.closed then feedback.Text = ok and "Markdown copied." or why end
				end })
		end
		if fsx.enabled then
			local saving, savedPath
			P.button(modal.footer, { name = "SaveConversation", text = "Save Markdown", variant = "primary", size = "sm", layoutOrder = 3,
				onClick = function(button)
					if saving or savedPath or modal.closed then return end
					saving = true; button.setEnabled(false)
					local path, why = exporter.save(text)
					saving, savedPath = false, path
					if not modal.closed then
						feedback.Text = path and ("Saved " .. path) or tostring(why)
						button.setEnabled(path == nil)
					end
				end })
		end
		return modal
	end
	return M
end
