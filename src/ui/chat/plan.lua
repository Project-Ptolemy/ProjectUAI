-- Full task details remain reachable when the compact plan strip truncates them.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local snapshots = env.require("runtime/todo_snapshot")
	local M = {}
	function M.open(session)
		if not session then return nil end
		local modal = overlay.modal({ title = "Conversation plan", description = session.title, width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local body = P.text(modal.content, { name = "FullPlan", text = "", role = "small", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
		local function refresh() if not modal.closed then body.Text = snapshots.text(session.todos); if body.Text == "" then body.Text = "No task plan yet." end end end
		local unsubscribe = env.require("agent/state").todosChanged:connect(function(_, owner) if owner == session then refresh() end end)
		modal.scrim.Destroying:Connect(unsubscribe)
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "CopyPlan", text = "Copy plan", variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
			local ok, why = env.require("runtime/clipboard").write(snapshots.text(session.todos))
			overlay.toast(ok and "Task plan copied." or tostring(why), ok and "info" or "warn")
		end })
		refresh()
		return modal
	end
	return M
end
