-- A compact Home continuation card driven by real conversation state.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local sessions = env.require("agent/session")
	local M = {}
	function M.build(parent, order)
		local root = P.column(parent, { name = "ContinueConversations", auto = "Y", gap = theme.space.xs,
			size = UDim2.new(1, 0, 0, 0), maxSize = Vector2.new(theme.size.statCard, math.huge), layoutOrder = order })
		local function render()
			if not root.Parent then return end
			for _, child in ipairs(root:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local count = 0
			for _, session in ipairs(sessions.list()) do
				local meta = session.metadata
				if count < 3 and (meta.pinned or meta.unread > 0 or meta.failures > 0 or session.draft) then
					count = count + 1
					local row = P.rowButton(root, { name = "Resume_" .. session.id, vertical = true, auto = "Y",
						size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, gap = theme.space.xxs,
						bg = theme.color.surfaceRaised, radius = theme.radius.md, layoutOrder = count,
						onClick = function() env.require("ui/app").openSession(session.id) end })
					P.text(row.row, { text = session.title, role = "label", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
					P.text(row.row, { text = session.draft and "Continue your draft" or env.require("runtime/conversation_metadata").label(meta),
						role = "caption", color = theme.color.textSecondary, layoutOrder = 2 })
				end
			end
			P.button(root, { name = "BrowseConversations", text = "Browse conversations", variant = "ghost", size = "sm", layoutOrder = 4,
				onClick = function() env.require("ui/conversation_browser").open(env.require("ui/app")) end })
		end
		local update, cancel = env.require("runtime/clock").debounce(render, 0.15)
		local unsubscribe = sessions.listChanged:connect(update)
		root.Destroying:Connect(function() cancel(); unsubscribe() end)
		render()
		return root
	end
	return M
end
