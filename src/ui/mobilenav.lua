-- Touch navigation keeps destinations and searchable history in one scrollable
-- surface. A conversation opens directly; its separate menu owns rename/delete.
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
		local dialog = overlay.dialog({ name = "MobileNavigation", width = theme.size.dialog,
			height = theme.size.dialogTall + theme.size.controlLarge * 2 })
		if not dialog then return end
		opened = dialog
		local target = responsive.minTarget()
		local pad = theme.space.sm
		local chrome = target + pad * 2
		local body = P.frame(dialog.card, { name = "NavigationBody", position = UDim2.fromOffset(0, chrome),
			size = UDim2.new(1, 0, 1, -chrome * 2) })
		local scroll = P.scroll(body, { name = "NavigationScroll", size = UDim2.fromScale(1, 1), gap = theme.space.sm,
			padding = { left = pad, right = pad, bottom = pad } })
		local filter, limit, renderHistory, folderFilter = "", 40, nil, nil
		local search = P.field(dialog.card, { name = "ConversationFilter", placeholder = "Search conversations or folders",
			size = UDim2.new(1, -dialog.closeInset - pad * 2, 0, target),
			onChange = function(text)
				filter, limit = util.trim(text):lower(), 40
				if renderHistory then renderHistory() end
			end })
		search.shell.Position = UDim2.fromOffset(pad, pad)
		local destinations = P.scroll(scroll.instance, { name = "Destinations", horizontal = true,
			size = UDim2.new(1, 0, 0, target + theme.size.scrollbar), gap = theme.space.xxs, layoutOrder = 2 })
		local destinationButtons = {}
		for index, entry in ipairs(panels) do
			local button = P.rowButton(destinations.instance, { name = "MobileNav_" .. entry.id,
				auto = "X", height = target, size = UDim2.fromOffset(0, target),
				selected = app.panel == entry.id, padding = { x = pad }, layoutOrder = index,
				onClick = function()
					dialog.close()
					if entry.id == "settings" then app.showSettingsDialog() else app.show(entry.id) end
				end })
			button.icon(entry.icon, 1)
			button.label(entry.label, 2, nil, "small")
			destinationButtons[#destinationButtons + 1] = button
		end
		local lastWide, count, footer, footerCorner, footerEdge
		local function reflow()
			if dialog.closed then return end
			-- Keep search pinned above the results. Short keyboards return the
			-- footer band to history while keeping its actions reachable by scroll.
			local compact = dialog.card.AbsoluteSize.Y < chrome * 2 + target * 3
			body.Size = UDim2.new(1, 0, 1, -chrome * (compact and 1 or 2))
			if footer then
				footer.Parent = compact and scroll.instance or dialog.card
				footer.AnchorPoint = Vector2.new(0, compact and 0 or 1)
				footer.Position = compact and UDim2.fromOffset(0, 0) or UDim2.fromScale(0, 1)
				footer.LayoutOrder = 6
				-- Round only while the footer sits on the card's bottom edge; in
				-- the scroll body it is an ordinary bar, and the edge fill that
				-- squares its inner corners does not belong there either.
				footerCorner.CornerRadius = UDim.new(0, compact and 0 or theme.radius.xl)
				footerEdge.Visible = not compact
			end
			if count then count.Visible = not compact end
			local wide = responsive.orientation == "landscape" and dialog.card.AbsoluteSize.X >= theme.size.dialogNav * 3
			if wide == lastWide then return end
			lastWide = wide
			local navWidth = theme.size.dialogNav
			destinations.instance.Parent = wide and body or scroll.instance
			destinations.instance.Position = UDim2.fromOffset(0, 0)
			destinations.instance.Size = wide and UDim2.new(0, navWidth, 1, 0)
				or UDim2.new(1, 0, 0, target + theme.size.scrollbar)
			destinations.layout.FillDirection = wide and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal
			destinations.instance.ScrollingDirection = wide and Enum.ScrollingDirection.Y or Enum.ScrollingDirection.X
			destinations.instance.AutomaticCanvasSize = wide and Enum.AutomaticSize.Y or Enum.AutomaticSize.X
			destinations.instance.VerticalScrollBarInset = wide and Enum.ScrollBarInset.ScrollBar or Enum.ScrollBarInset.None
			destinations.instance.CanvasPosition = Vector2.new(0, 0)
			for _, button in ipairs(destinationButtons) do
				button.instance.AutomaticSize = wide and Enum.AutomaticSize.None or Enum.AutomaticSize.X
				button.instance.Size = wide and UDim2.new(1, 0, 0, target) or UDim2.fromOffset(0, target)
			end
			scroll.instance.Position = UDim2.fromOffset(wide and navWidth + pad or 0, 0)
			scroll.instance.Size = UDim2.new(1, wide and -(navWidth + pad) or 0, 1, 0)
		end
		dialog.card:GetPropertyChangedSignal("AbsoluteSize"):Connect(reflow)
		local unbindLayout = responsive.changed:connect(reflow)
		dialog.scrim.Destroying:Connect(unbindLayout)
		reflow()
		local folderLabel
		local folderPicker = P.rowButton(scroll.instance, { name = "HistoryFolder", height = target, layoutOrder = 3,
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
						renderHistory()
					end })
			end })
		folderLabel = folderPicker.label("All folders", 1)
		count = P.text(scroll.instance, { name = "HistoryCount", text = "Conversations", role = "caption",
			color = theme.color.textTertiary, size = UDim2.new(1, 0, 0, theme.text.caption.height + pad), layoutOrder = 4 })
		local history = P.column(scroll.instance, { name = "MobileHistory", auto = "Y",
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xxs, layoutOrder = 5 })

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

		renderHistory = function()
			if dialog.closed then return end
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
						open.icon(session.busy and "circle" or "circleHollow", 1,
							session.busy and theme.color.accent or theme.color.textTertiary)
						local label = P.column(open.row, { size = UDim2.new(0, 0, 1, 0),
							flex = "Fill", gap = 0, alignY = "Center", layoutOrder = 2 })
						P.text(label, { name = "ConversationTitle", text = session.title, role = "small",
							size = UDim2.new(1, 0, 0, theme.text.small.height), truncate = true, layoutOrder = 1 })
						P.text(label, { text = sessions.folderLabel(session) .. (session.ephemeral and " (not saved)" or ""),
							role = "caption", color = theme.color.textTertiary, truncate = true,
							size = UDim2.new(1, 0, 0, theme.text.caption.height), layoutOrder = 2 })
						P.iconButton(row, { name = "HistoryActions_" .. session.id, icon = "ellipsis",
							diameter = target, anchor = Vector2.new(1, 0.5), position = UDim2.fromScale(1, 0.5),
							onClick = function(button) sessionMenu(session, button.instance) end })
					end
				end
			end
			count.Text = util.pluralise(matches, "conversation")
			if matches == 0 then
				P.text(history, { name = "NoConversations", text = filter == "" and "No conversations in this folder yet."
					or "No matches. Try a title, folder, or game name.", role = "small", wrap = true, auto = "Y",
					color = theme.color.textSecondary })
			elseif matches > shown then
				P.button(history, { name = "MoreConversations", text = "Show more conversations", variant = "ghost",
					layoutOrder = shown + 1, onClick = function() limit = limit + 40; renderHistory() end })
			end
		end

		-- UICorner rounds a frame's own fill, not its descendants, so the footer
		-- carries the dialog's radius on the corners it exposes at the card's bottom.
		-- The straight fill above it keeps the inner edge square.
		footerEdge = P.frame(dialog.card, {
			name = "NavigationActionsEdgeFill",
			size = UDim2.new(1, 0, 0, theme.radius.xl),
			position = UDim2.new(0, 0, 1, -chrome),
			bg = theme.color.surface,
		})
		footer = P.frame(dialog.card, { name = "NavigationActions", anchor = Vector2.new(0, 1),
			position = UDim2.fromScale(0, 1), size = UDim2.new(1, 0, 0, chrome), bg = theme.color.surface })
		footerCorner = P.corner(footer, theme.radius.xl)
		P.divider(footer, {})
		P.button(footer, { name = "MobileNewChat", text = "New conversation", icon = "plus", variant = "primary",
			width = 0, height = target, position = UDim2.fromOffset(pad, pad),
			onClick = function()
				dialog.close(); app.newConversation(folderFilter)
			end }).instance.Size =
			UDim2.new(1, -target - pad * 3, 0, target)
		P.iconButton(footer, { name = "MobileMore", icon = "ellipsis", diameter = target,
			anchor = Vector2.new(1, 0), position = UDim2.new(1, -pad, 0, pad), onClick = function(button)
				overlay.menu({ target = button.instance, title = "Workspace", options = {
					{ label = "Search message history", value = "search", icon = "search" },
					{ label = "Conversation folders", value = "folders" },
					{ label = "Settings", value = "settings", icon = "gear" },
					{ label = "About UAI", value = "about", icon = "document" },
					{ label = "Join Discord", value = "discord", icon = "globe" },
					{ label = "Unload UAI", value = "unload", icon = "signOut", tone = "bad" },
				}, onSelect = function(value)
					dialog.close()
					if value == "search" then app.showSearch()
					elseif value == "folders" then app.manageFolders()
					elseif value == "settings" then app.showSettingsDialog()
					elseif value == "about" then app.showAbout()
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
