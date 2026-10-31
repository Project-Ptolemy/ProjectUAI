-- One searchable destination picker for application actions, settings and conversations.
return function(env)
	local catalog = env.require("runtime/command_catalog")
	local sessions = env.require("agent/session")
	local panes = env.require("ui/settingspanes")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	local current
	local hints = {
		general = "appearance font code theme text size interface scale sidebar notifications",
		privacy = "password credential vault encryption storage remember API keys",
		usage = "tokens cost statistics requests activity",
		claude_code = "identity user agent headers version",
		cowork = "bridge connection address token runtime browser",
		import_export = "copy configuration import export private transfer review",
		agent = "reasoning effort temperature context compaction budgets timeout free routing",
		permissions = "allow ask read only rules tool access",
		desktop_general = "updates desktop auto start discover",
		developer = "MCP debugging diagnostics",
		skills = "instructions inventory skill files",
		connectors = "Obsidian vault notes integrations MCP",
		obsidian = "local Markdown vault notes browse search backlinks edit bridge",
		infinite_yield = "IY commands engine plugins",
		plugins = "customize extensions",
	}
	function M.open(app, query)
		if current and not current.closed then current.close() end
		local extra = {}
		for _, pane in ipairs(panes.PANES) do
			extra[#extra + 1] = { id = pane.id, label = "Settings: " .. pane.section .. " / " .. pane.label,
				detail = hints[pane.id] or pane.label, kind = "setting" }
		end
		for index, session in ipairs(sessions.list()) do
			if index > 64 then break end
			extra[#extra + 1] = { id = session.id, label = session.title,
				detail = "Conversation · " .. sessions.folderLabel(session), kind = "conversation" }
		end
		local modal = overlay.modal({ title = "Find a command", width = theme.size.dialog,
			description = "Search actions, settings and recent conversation titles. Up/Down selects; Enter opens." })
		if not modal then return nil end
		current = modal
		local results = P.column(modal.content, { name = "CommandResults", auto = "Y", gap = theme.space.hair,
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		local count = P.text(modal.content, { name = "CommandCount", text = "", role = "caption",
			color = theme.color.textSecondary, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		local matches, rows, selected = {}, {}, 1
		local function choose(index)
			local entry = matches[index]
			if modal.closed or not entry then return end
			modal.close()
			if entry.kind == "panel" then app.show(entry.id)
			elseif entry.kind == "setting" then app.showSettingsDialog(entry.id)
			elseif entry.kind == "conversation" then app.openSession(entry.id)
			elseif entry.id == "new" then app.newConversation()
			elseif entry.id == "search" then app.showSearch()
			elseif entry.id == "folders" then app.manageFolders()
			elseif entry.id == "export" then app.exportConversation()
			elseif entry.id == "focus" then app.focusComposer()
			elseif entry.id == "shortcuts" then app.showShortcuts()
			elseif entry.id == "tutorial" then env.require("ui/tutorial").open() end
			if entry.id == "scriptGoal" then env.require("ui/code/workflow").open() end
		end
		local function paint()
			for index, row in ipairs(rows) do row.setSelected(index == selected) end
			local row = rows[selected]
			if row then
				local top = row.instance.AbsolutePosition.Y - modal.scroll.instance.AbsolutePosition.Y + modal.scroll.instance.CanvasPosition.Y
				local bottom = top + row.instance.AbsoluteSize.Y
				local position = modal.scroll.instance.CanvasPosition.Y
				local height = modal.scroll.instance.AbsoluteSize.Y
				if height > 0 and top < position then modal.scroll.instance.CanvasPosition = Vector2.new(0, math.max(0, top))
				elseif height > 0 and bottom > position + height then modal.scroll.instance.CanvasPosition = Vector2.new(0, math.max(0, bottom - height)) end
			end
		end
		local function render(value)
			if modal.closed then return end
			for _, child in ipairs(results:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local total
			matches, total = catalog.find(value, extra, 40)
			rows, selected = {}, 1
			count.Text = tostring(total) .. " matching destinations" .. (total > #matches and " · refine to see more" or "")
			for index, entry in ipairs(matches) do
				local picked = index
				local row = P.rowButton(results, { name = "Command_" .. entry.kind .. "_" .. entry.id, vertical = true,
					auto = "Y", size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, gap = theme.space.hair,
					layoutOrder = index, selected = index == 1, onClick = function() choose(picked) end })
				P.text(row.row, { text = entry.label, role = "small", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
				P.text(row.row, { text = entry.detail, role = "caption", color = theme.color.textSecondary, auto = "Y", wrap = true,
					size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
				rows[index] = row
			end
			if #matches == 0 then P.text(results, { name = "CommandEmpty", text = "No matches. Try a setting, panel or conversation title.",
				role = "small", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0) }) end
			modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
		end
		local field = P.field(modal.content, { name = "CommandSearch", placeholder = "Search commands and settings",
			text = query or "", layoutOrder = 1, onChange = render, onSubmit = function() choose(selected) end })
		local input = env.uis.InputBegan:Connect(function(event)
			if modal.closed or env.uis:GetFocusedTextBox() ~= field.instance then return end
			if event.KeyCode == Enum.KeyCode.Down then selected = math.min(#matches, selected + 1); paint()
			elseif event.KeyCode == Enum.KeyCode.Up then selected = math.max(1, selected - 1); paint() end
		end)
		modal.scrim.Destroying:Connect(function() input:Disconnect(); if current == modal then current = nil end end)
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		render(query or "")
		task.defer(function() if not modal.closed then field.focus() end end)
		return modal
	end
	return M
end
