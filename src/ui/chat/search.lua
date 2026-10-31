-- Search saved transcript events; opening a result navigates by its stable id.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local clock = env.require("runtime/clock")
	local overlay = env.require("ui/overlay")
	local M = {}
	function M.open(session)
		if not session or session.removed then return nil end
		local modal = overlay.modal({ title = "Find in conversation", description = env.require("runtime/search").hint,
			width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local query, before, role = "", nil, "all"
		local render, more
		local field = P.field(modal.content, { name = "TranscriptSearch", placeholder = "Search this conversation", layoutOrder = 1,
			onChange = function(value) query, before = value, nil; if render then render() end end })
		local filters = P.row(modal.content, { name = "TranscriptSearchRoles", auto = "Y", wrap = true,
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 2 })
		for _, entry in ipairs({ { "All", "all" }, { "Messages", "user" }, { "Replies", "assistant:text" }, { "Errors", "error" } }) do
			P.button(filters, { text = entry[1], variant = "ghost", size = "sm", onClick = function()
				role, before = entry[2], nil; render()
			end })
		end
		local status = P.text(modal.content, { name = "TranscriptSearchStatus", text = "Enter words to search the saved transcript.",
			role = "caption", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		local rows = P.column(modal.content, { name = "TranscriptSearchResults", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 4 })
		local function refresh()
			if modal.closed then return end
			for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local page = session.searchTranscript(query, { before = before, role = role })
			status.Text = tostring(#page.items) .. " matches on this page / " .. (role == "all" and "all messages" or role)
				.. (page.clipped and ". Long messages search their first 16 KiB." or "")
				.. (page.complete and ". Saved history searched." or ". Continue to search older history.")
			for index, hit in ipairs(page.items) do
				local row = P.rowButton(rows, { name = "SearchResult_" .. tostring(hit.id), vertical = true, auto = "Y",
					size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, gap = theme.space.xxs,
					bg = theme.color.surfaceRaised, radius = theme.radius.md, layoutOrder = index,
					onClick = function()
						local app = env.require("ui/app")
						modal.close(); app.openSession(session.id)
						if app.chatPanel and app.chatPanel.view then app.chatPanel.view.jumpTo(hit.id) end
					end })
				P.text(row.row, { text = hit.label, role = "label", layoutOrder = 1 })
				P.text(row.row, { text = hit.snippet, role = "small", wrap = true, auto = "Y",
					size = UDim2.new(1, 0, 0, 0), color = theme.color.textSecondary, layoutOrder = 2 })
			end
			more.setEnabled(page.nextBefore ~= nil)
			more.nextBefore = page.nextBefore
		end
		local update, cancel = clock.debounce(refresh, 0.15)
		render = update
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		more = P.button(modal.footer, { name = "OlderSearchResults", text = "Search older", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() before = more.nextBefore; refresh() end })
		more.setEnabled(false)
		modal.scrim.Destroying:Connect(cancel)
		field.focus()
		return modal
	end
	return M
end
