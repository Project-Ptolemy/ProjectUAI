-- Loaded conversation browsing with independent title/content and state filters.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local sessions = env.require("agent/session")
	local metadata = env.require("runtime/conversation_metadata")
	local overlay = env.require("ui/overlay")
	local clock = env.require("runtime/clock")
	local util = env.require("runtime/util")
	local M = {}
	function M.open(app)
		local modal = overlay.modal({ title = "Conversations", description = 'Search loaded titles and recent messages. Use "phrases" or -exclude.',
			width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local query, filter = "", "all"
		local render
		local field = P.field(modal.content, { name = "ConversationSearch", placeholder = "Find a conversation", layoutOrder = 1,
			onChange = function(value) query = util.trim(value); if render then render() end end })
		local filters = P.row(modal.content, { name = "ConversationFilters", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 2 })
		local selectFilter, filterMenu
		selectFilter = P.button(filters, { name = "ConversationFilter", text = "All conversations", variant = "secondary", size = "sm",
			onClick = function()
				if modal.closed then return end
				if filterMenu and not filterMenu.closed then filterMenu.close(); return end
				filterMenu = overlay.menu({ target = selectFilter.instance, options = {
					{ label = "All conversations", value = "all" }, { label = "Pinned", value = "pinned" },
					{ label = "Unread or failed", value = "unread" }, { label = "Running", value = "running" }, { label = "Has draft", value = "draft" },
				}, onSelect = function(value, option)
					if modal.closed then return end
					filter = value; selectFilter.setText(option and option.label or value); render()
				end })
			end })
		local status = P.text(modal.content, { name = "ConversationCount", text = "", role = "caption", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		local rows = P.column(modal.content, { name = "ConversationResults", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 4 })
		local function refresh()
			if modal.closed then return end
			for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local entries = query ~= "" and sessions.search(query) or {}
			if query == "" then for _, session in ipairs(sessions.list()) do entries[#entries + 1] = { session = session } end end
			local count = 0
			for _, entry in ipairs(entries) do
				local session = entry.session
				local meta = session.metadata
				local wanted = filter == "all" or filter == "pinned" and meta.pinned or filter == "unread" and (meta.unread > 0 or meta.failures > 0)
					or filter == "running" and session.busy or filter == "draft" and session.draft ~= nil
				if wanted then
					count = count + 1
					local row = P.rowButton(rows, { name = "Conversation_" .. session.id, vertical = true, auto = "Y",
						size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, gap = theme.space.xxs, layoutOrder = count,
						bg = theme.color.surfaceRaised, radius = theme.radius.md, onClick = function()
							if modal.closed then return end
							if sessions.get(session.id) ~= session then
								render(); overlay.toast("This conversation is no longer available.", "warn"); return
							end
							modal.close(); app.openSession(session.id)
						end })
					P.text(row.row, { text = session.title, role = "label", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
					local detail = metadata.label(meta)
					P.text(row.row, { text = sessions.folderLabel(session) .. (detail ~= "" and " / " .. detail or "")
						.. (session.busy and " / Running" or "") .. (session.draft and " / Draft" or ""), role = "caption",
						color = theme.color.textSecondary, wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
					if entry.snippet then P.text(row.row, { text = entry.snippet, role = "small", wrap = true, auto = "Y",
						size = UDim2.new(1, 0, 0, 0), color = theme.color.textTertiary, layoutOrder = 3 }) end
				end
			end
			status.Text = tostring(count) .. " conversations shown. Search covers bounded recent saved text."
		end
		local update, cancel = clock.debounce(refresh, 0.15)
		render = update
		local unsubscribe = sessions.listChanged:connect(update)
		modal.scrim.Destroying:Connect(function()
			cancel(); unsubscribe()
			if filterMenu and not filterMenu.closed then filterMenu.close() end
		end)
		P.button(modal.footer, { text = "Done", variant = "ghost", size = "sm", onClick = modal.close })
		refresh(); field.focus()
		return modal
	end
	return M
end
