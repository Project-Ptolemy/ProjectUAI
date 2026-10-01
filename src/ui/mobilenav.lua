-- Mobile navigation opens on conversations. Workspace destinations have their
-- own page, leaving the full width and height below search for readable history.
return function(env)
	local util = env.require("runtime/util")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local sessions = env.require("agent/session")
	local M = {}
	local opened

	function M.open(app, panels)
		if opened and not opened.closed then return opened end
		local dialog = overlay.dialog({ name = "MobileNavigation", width = theme.size.modalWide + theme.size.dialogNav,
			height = theme.size.dialogTall })
		if not dialog then return end
		opened = dialog
		local target = responsive.minTarget()
		local pad = theme.space.sm
		local chromePad = theme.space.xxs
		local chrome = target + chromePad * 2
		local body = P.frame(dialog.card, { name = "NavigationBody", position = UDim2.fromOffset(0, chrome),
			size = UDim2.new(1, 0, 1, -chrome), clip = true })
		local chats = P.frame(body, { name = "Conversations", size = UDim2.fromScale(1, 1) })
		local scroll = P.scroll(chats, { name = "NavigationScroll", size = UDim2.fromScale(1, 1), gap = theme.space.xxs,
			padding = { left = pad, right = pad, bottom = pad } })
		local filter, limit, renderHistory, folderFilter = "", 40, nil, nil
		local showingWorkspace = false
		local header = P.row(dialog.card, { name = "NavigationHeader", position = UDim2.fromOffset(pad, chromePad),
			size = UDim2.new(1, -dialog.closeInset - pad, 0, target), gap = theme.space.xxs })
		local switchView
		local menu = P.button(header, { name = "WorkspaceMenu", text = "Menu", size = "sm", variant = "ghost",
			padX = pad, layoutOrder = 1, onClick = function() switchView(not showingWorkspace) end })
		local search = P.field(header, { name = "ConversationFilter", placeholder = "Search chats or folders",
			size = UDim2.new(0, 0, 0, target), flex = "Fill", layoutOrder = 2, padX = pad,
			onChange = function(text)
				filter, limit = util.trim(text):lower(), 40
				if renderHistory then renderHistory(true) end
			end })
		local workspaceTitle = P.text(header, { name = "WorkspaceTitle", text = "Workspace", role = "bodyStrong",
			size = UDim2.new(0, 0, 0, target), flex = "Fill", alignY = "Center", visible = false, layoutOrder = 3 })
		local workspace = P.scroll(body, { name = "WorkspaceDestinations", visible = false, gap = pad,
			padding = { left = pad, right = pad, bottom = pad } })
		local destinations = P.frame(workspace.instance, { name = "Destinations", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
		local destinationButtons, widestLabel = {}, 0
		for index, entry in ipairs(panels) do
			local button = P.rowButton(destinations, { name = "MobileNav_" .. entry.id, height = target,
				selected = app.panel == entry.id, padding = { x = pad }, stroke = true,
				onClick = function()
					dialog.close()
					if entry.id == "settings" then app.showSettingsDialog() else app.show(entry.id) end
				end })
			button.label(entry.label, 1, theme.color.text, "small")
			widestLabel = math.max(widestLabel, P.measureText(entry.label, { role = "small" }).X)
			destinationButtons[#destinationButtons + 1] = button
		end
		local toolbar = P.row(chats, { name = "ConversationActions", position = UDim2.fromOffset(pad, 0),
			size = UDim2.new(1, -pad * 2, 0, target), gap = theme.space.xs })
		local count, history, folderPicker
		local function reflow()
			if dialog.closed then return end
			-- Search keeps its TextBox when rotating or opening the menu. When the
			-- keyboard is short on space, results precede the folder/new-chat row.
			local compact = dialog.card.AbsoluteSize.Y < chrome + target * 4
			toolbar.Parent = compact and scroll.instance or chats
			toolbar.Position = UDim2.fromOffset(compact and 0 or pad, 0)
			toolbar.Size = UDim2.new(1, compact and 0 or -pad * 2, 0, target)
			toolbar.LayoutOrder = 3
			scroll.instance.Position = UDim2.fromOffset(0, compact and 0 or target + chromePad)
			scroll.instance.Size = UDim2.new(1, 0, 1, compact and 0 or -(target + chromePad))
			if count then count.Visible = not compact end
			local width = math.max(0, dialog.card.AbsoluteSize.X - pad * 2 - theme.size.scrollbar)
			local columns = width >= (widestLabel + pad * 2) * 2 + pad and 2 or 1
			local cell = math.floor((width - pad * (columns - 1)) / columns)
			for index, button in ipairs(destinationButtons) do
				button.instance.Position = UDim2.fromOffset(((index - 1) % columns) * (cell + pad),
					math.floor((index - 1) / columns) * (target + theme.space.xs))
				button.instance.Size = UDim2.fromOffset(cell, target)
			end
			destinations.Size = UDim2.new(1, 0, 0, math.ceil(#destinationButtons / columns) * (target + theme.space.xs) - theme.space.xs)
		end
		switchView = function(value)
			showingWorkspace = value == true
			if showingWorkspace then pcall(function() search.instance:ReleaseFocus(false) end) end
			chats.Visible, workspace.instance.Visible = not showingWorkspace, showingWorkspace
			search.shell.Visible, workspaceTitle.Visible = not showingWorkspace, showingWorkspace
			menu.setText(showingWorkspace and "Back" or "Menu")
			reflow()
		end
		dialog.card:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
		local unbindLayout = responsive.changed:connect(reflow)
		dialog.scrim.Destroying:Connect(unbindLayout)
		reflow()
		local folderLabel
		folderPicker = P.rowButton(toolbar, { name = "HistoryFolder", height = target, layoutOrder = 1,
			size = UDim2.new(0, 0, 0, target), flex = "Fill", padding = { x = theme.space.xxs },
			onClick = function(button)
				local options = { { label = "All folders", value = "all", selected = folderFilter == nil } }
				for _, folder in ipairs(sessions.folders()) do
					options[#options + 1] = { label = folder.label, value = folder.id, selected = folderFilter == folder.id }
				end
				options[#options + 1] = { divider = true }
				options[#options + 1] = { label = "Manage folders", value = "manage" }
				overlay.menu({ target = button.instance, title = "Conversation folders", options = options,
					onSelect = function(value)
						if value == "manage" then dialog.close(); app.manageFolders(); return end
						folderFilter, limit = value ~= "all" and value or nil, 40
						renderHistory(true)
					end })
			end })
		folderLabel = folderPicker.label("All folders", 1, nil, "small")
		count = P.text(folderPicker.row, { name = "HistoryCount", text = "", role = "caption", auto = "X",
			color = theme.color.textTertiary, layoutOrder = 2 })
		folderPicker.icon("chevron", 3)
		P.button(toolbar, { name = "MobileNewChat", text = "New chat", variant = "primary", size = "sm",
			padX = pad, layoutOrder = 2, onClick = function() dialog.close(); app.newConversation(folderFilter) end })
		history = P.column(scroll.instance, { name = "MobileHistory", auto = "Y",
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xxs, layoutOrder = 1 })

		local function sessionMenu(session, anchor)
			overlay.menu({ target = anchor, title = "Conversation", options = {
				{ isHeader = true, title = session.title, subtitle = sessions.folderLabel(session) },
				{ label = "Rename", value = "rename", icon = "document" },
				{ label = "Move to folder", value = "move" },
				{ label = "Delete", value = "delete", icon = "trash", tone = "bad" },
			}, onSelect = function(value)
				dialog.close()
				if value == "rename" then
					overlay.prompt({ title = "Rename conversation", value = session.title,
						placeholder = "Conversation title", confirmText = "Rename", onConfirm = function(text)
							local ok, why = session.rename(text)
							if not ok then overlay.toast(tostring(why), "warn", 2) end
						end })
				elseif value == "move" then
					app.moveConversation(session)
				elseif value == "delete" then
					overlay.confirm({ title = "Delete this conversation?",
						description = "The transcript and its file are both removed. This cannot be undone.",
						confirmText = "Delete", danger = true, onConfirm = function()
							sessions.remove(session.id)
							app.openSession(sessions.current().id)
						end })
				end
			end })
		end

		renderHistory = function(resetScroll)
			if dialog.closed then return end
			if resetScroll == true then scroll.instance.CanvasPosition = Vector2.new(0, 0) end
			for _, child in ipairs(history:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local folderBySession, selectedLabel = {}, nil
			for _, group in ipairs(sessions.groups()) do
				if group.id == folderFilter then selectedLabel = group.label end
				for _, session in ipairs(group.sessions) do folderBySession[session.id] = group.id end
			end
			if folderFilter and not selectedLabel then folderFilter = nil end
			folderLabel.Text = selectedLabel or "All folders"
			local matches, shown = 0, 0
			for _, session in ipairs(sessions.list()) do
				local searchable = (tostring(session.title) .. " " .. sessions.folderLabel(session) .. " " .. tostring(session.placeName or "")):lower()
				if (not folderFilter or folderBySession[session.id] == folderFilter)
					and (filter == "" or searchable:find(filter, 1, true)) then
					matches = matches + 1
					if shown < limit then
						shown = shown + 1
						local height = math.max(target, theme.text.small.height + theme.text.caption.height + pad)
						local row = P.frame(history, { name = "History_" .. session.id,
							size = UDim2.new(1, 0, 0, height), layoutOrder = shown })
						local selected = session.id == sessions.activeId
						local open = P.rowButton(row, { name = "Open_" .. session.id,
							size = UDim2.new(1, -target - theme.space.xxs, 1, 0), selected = selected,
							padding = { x = pad }, onClick = function() dialog.close(); app.openSession(session.id) end })
						if selected then
							P.frame(open.instance, { name = "CurrentConversation", bg = theme.color.accent,
								size = UDim2.new(0, theme.stroke.focus, 1, -pad * 2), position = UDim2.fromOffset(0, pad) })
						end
						local label = P.column(open.row, { size = UDim2.new(0, 0, 1, 0),
							flex = "Fill", gap = 0, alignY = "Center", layoutOrder = 2 })
						P.text(label, { name = "ConversationTitle", text = session.title, role = "small",
							size = UDim2.new(1, 0, 0, theme.text.small.height), truncate = true, layoutOrder = 1 })
						P.text(label, { text = sessions.folderLabel(session) .. (session.ephemeral and " (not saved)" or ""),
							role = "caption", color = theme.color.textTertiary, truncate = true,
								size = UDim2.new(1, 0, 0, theme.text.caption.height), layoutOrder = 2 })
						if session.busy then
							P.text(open.row, { text = "Running", role = "caption", auto = "X",
								color = theme.color.accent, layoutOrder = 3 })
						end
						P.iconButton(row, { name = "HistoryActions_" .. session.id, icon = "ellipsis",
							diameter = target, anchor = Vector2.new(1, 0.5), position = UDim2.fromScale(1, 0.5),
							onClick = function(button) sessionMenu(session, button.instance) end })
					end
				end
			end
			count.Text = tostring(matches)
			if matches == 0 then
				P.text(history, { name = "NoConversations", text = filter == "" and "No conversations in this folder yet."
					or "No matches. Try a title, folder, or game name.", role = "small", wrap = true, auto = "Y",
					color = theme.color.textSecondary })
			elseif matches > shown then
				P.button(history, { name = "MoreConversations", text = "Show more conversations", variant = "ghost",
					layoutOrder = shown + 1, onClick = function() limit = limit + 40; renderHistory() end })
			end
		end

		P.button(workspace.instance, { name = "MobileHistorySearch", text = "Search message history", fill = true,
			variant = "ghost", align = "Left", size = "sm", padX = pad, layoutOrder = 2,
			onClick = function() dialog.close(); app.showSearch() end })
		P.button(workspace.instance, { name = "MobileFolders", text = "Conversation folders", fill = true,
			variant = "ghost", align = "Left", size = "sm", padX = pad, layoutOrder = 3,
			onClick = function() dialog.close(); app.manageFolders() end })
		P.button(workspace.instance, { name = "MobileMore", text = "More options", fill = true,
			variant = "ghost", align = "Left", size = "sm", padX = pad, layoutOrder = 4, onClick = function(button)
				overlay.menu({ target = button.instance, title = "Workspace", options = {
					{ label = "About UAI", value = "about" },
					{ label = "Join Discord", value = "discord" },
					{ label = "Unload UAI", value = "unload", tone = "bad" },
				}, onSelect = function(value)
					dialog.close()
					if value == "about" then app.showAbout()
					elseif value == "discord" then app.joinDiscord()
					elseif value == "unload" then
						overlay.confirm({ title = "Unload UAI?", description = "Saves your settings and removes the interface.",
							confirmText = "Unload", danger = true, onConfirm = function()
								local globals = type(getgenv) == "function" and getgenv() or nil
								local live = globals and globals.UAI
								if live and live.destroy then live.destroy()
								else env.require("runtime/dispose").drain(); app.screen:Destroy() end
							end })
					end
				end })
			end })
		local unsubscribe = sessions.listChanged:connect(renderHistory)
		dialog.scrim.Destroying:Connect(unsubscribe)
		dialog.filter = search
		reflow()
		renderHistory()
		return dialog
	end

	return M
end
