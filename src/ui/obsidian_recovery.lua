-- Explicit review after a conflicting or unconfirmed save. No write is retried.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	function M.open(entry, latest, onChoose)
		local modal = overlay.modal({ title = "Review current note", description = "Your draft is kept. Review the file before choosing which text to keep.",
			width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		P.text(modal.content, { text = latest.path .. " / current file: " .. tostring(latest.bytes) .. " bytes / draft: " .. tostring(#entry.text) .. " bytes",
			role = "caption", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
		local field = P.field(modal.content, { name = "CurrentVaultNote", text = env.require("runtime/obsidian_document").editorText(latest.content),
			multiline = true, height = 240, role = "mono", syntax = false, layoutOrder = 2 })
		field.instance.TextEditable = false
		P.text(modal.content, { text = "Keep draft uses this file revision for your next explicit Save. It can replace changes shown above. Use file discards the local draft.",
			role = "small", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		P.button(modal.footer, { text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "KeepVaultDraft", text = "Keep draft", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() modal.close(); onChoose(false) end })
		P.button(modal.footer, { name = "UseVaultFile", text = "Use file", variant = "primary", size = "sm", layoutOrder = 3,
			onClick = function() modal.close(); onChoose(true) end })
		return modal
	end
	return M
end
