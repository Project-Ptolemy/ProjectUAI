-- Inspect one conversation without switching or interrupting its worker.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local summaries = env.require("runtime/conversation_summary")
	local sessions = env.require("agent/session")
	local M = {}
	function M.open(session)
		if not session or session.removed then return nil end
		local modal = overlay.modal({ title = "Conversation details", width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local body = P.text(modal.content, { name = "ConversationDetails", text = "", role = "small", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
		local function refresh()
			if modal.closed then return end
			if session.removed then modal.close(); return end
			body.Text = summaries.text(summaries.snapshot(session, sessions.folderLabel(session)))
		end
		local update, cancel = env.require("runtime/clock").debounce(refresh, 0.15)
		local unsubscribe = sessions.listChanged:connect(update)
		modal.scrim.Destroying:Connect(function() cancel(); unsubscribe() end)
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "CopyConversationDetails", text = "Copy details", variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
			local ok, why = env.require("runtime/clipboard").write(body.Text)
			overlay.toast(ok and "Conversation details copied." or tostring(why), ok and "info" or "warn")
		end })
		refresh()
		return modal
	end
	return M
end
