-- Shared native conversation organization flows. Session ownership and storage
-- stay in agent/session; these forms only collect and display user choices.
return function(env)
	local util = env.require("runtime/util")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local M = {}

	local function errorLabel(parent, order)
		return P.text(parent, { name = "FolderError", text = "", role = "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), color = theme.color.danger,
			visible = false, layoutOrder = order })
	end

	local function showError(label, why)
		label.Text, label.Visible = tostring(why or "Could not save this change."), true
	end

	function M.editFolder(folder, onSaved)
		local modal = overlay.modal({ title = folder and "Rename folder" or "New folder", width = theme.size.modal })
		if not modal then return nil end
		local field = P.field(modal.content, { name = "FolderName", placeholder = "Folder name",
			text = folder and folder.label or "", layoutOrder = 1 })
		local errorText = errorLabel(modal.content, 2)
		P.button(modal.footer, { text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "SaveFolder", text = folder and "Rename" or "Create",
			variant = "primary", size = "sm", layoutOrder = 2, onClick = function()
				if modal.closed then return end
				local result, why
				if folder then result, why = sessions.renameFolder(folder.id, field.get())
				else result, why = sessions.createFolder(field.get()) end
				if not result then showError(errorText, why); return end
				modal.close()
				if onSaved then onSaved(result) end
			end })
		return modal
	end

	-- A title is optional; changing the destination never replaces the transcript
	-- or the game's runtime context. Invalid input leaves the complete form intact.
	function M.choose(app, session, folderId)
		local moving = session ~= nil
		local modal = overlay.modal({ title = moving and "Move conversation" or "New conversation",
			description = moving and "Choose a folder for this conversation." or "Choose where to keep this conversation.",
			width = theme.size.modal })
		if not modal then return nil end
		local selected = folderId or (session and (session.folderId or ("game:" .. tostring(session.placeId))))
		local title
		if not moving then
			title = P.field(modal.content, { name = "ConversationName", placeholder = "Conversation title (optional)", layoutOrder = 1 })
		end
		P.text(modal.content, { text = "Folder", role = "label", layoutOrder = 2 })
		local picker, selectionLabel, menu, nameField
		local function refreshSelection()
			local fallback, found
			for _, folder in ipairs(sessions.folders()) do
				if folder.current then fallback = folder end
				if folder.id == selected then found = folder end
			end
			if not selected then selected = fallback and fallback.id or "universal"; found = fallback end
			selectionLabel.Text = selected == "__new" and "New folder" or (found and found.label or "Universal")
			if not found and selected ~= "__new" then selected = "universal" end
			nameField.shell.Visible = selected == "__new"
		end
		picker = P.rowButton(modal.content, { name = "ConversationFolder", stroke = true,
			bg = theme.color.surfaceRaised, layoutOrder = 3, onClick = function()
				if menu and not menu.closed then menu.close(); return end
				local options = {}
				for _, folder in ipairs(sessions.folders()) do
					options[#options + 1] = { label = folder.label, value = folder.id, selected = folder.id == selected,
						detail = folder.current and "Current game" or (folder.kind == "game" and "Game" or nil) }
				end
				options[#options + 1] = { divider = true }
				options[#options + 1] = { label = "New folder", value = "__new" }
				menu = overlay.menu({ target = picker.instance, title = "Choose folder", options = options,
					onSelect = function(value)
						if modal.closed then return end
						selected = value; refreshSelection()
						if value == "__new" then nameField.focus() end
					end })
			end })
		selectionLabel = picker.label("", 1)
		nameField = P.field(modal.content, { name = "NewFolderName", placeholder = "New folder name", layoutOrder = 4 })
		local errorText = errorLabel(modal.content, 5)
		refreshSelection()
		P.button(modal.footer, { text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "ConfirmConversation", text = moving and "Move" or "Create",
			variant = "primary", size = "sm", layoutOrder = 2, onClick = function()
				if modal.closed then return end
				if moving and sessions.get(session.id) ~= session then
					showError(errorText, "This conversation is no longer available."); return
				end
				if selected == "__new" then
					local folder, why = sessions.createFolder(nameField.get())
					if not folder then showError(errorText, why); return end
					selected = folder.id; refreshSelection()
				end
				local result, why
				if moving then result, why = sessions.moveToFolder(session, selected)
				else
					local name = util.trim(title.get())
					result, why = sessions.newThread({ folderId = selected, title = name ~= "" and name or nil })
					if result and name ~= "" then result.rename(name) end
				end
				if not result then showError(errorText, why); return end
				modal.close()
				if not moving then app.openSession(result.id) end
			end })
		modal.scrim.Destroying:Connect(function() if menu and not menu.closed then menu.close() end end)
		return modal
	end

	function M.manage(app)
		local modal = overlay.modal({ title = "Conversation folders", width = theme.size.modal,
			description = "Keep chats in a game, Universal, or a folder you name." })
		if not modal then return nil end
		local menu
		local function render()
			if modal.closed then return end
			if menu and not menu.closed then menu.close() end
			for _, child in ipairs(modal.content:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			for index, folder in ipairs(sessions.folders()) do
				local row = P.rowButton(modal.content, { name = "Folder_" .. folder.id, layoutOrder = index,
					onClick = function(button)
						local options = { { label = "New conversation", value = "new" } }
						if folder.kind == "custom" then
							options[#options + 1] = { label = "Rename folder", value = "rename" }
							options[#options + 1] = { label = "Remove folder", value = "remove" }
						end
						menu = overlay.menu({ target = button.instance, title = folder.label, options = options,
							onSelect = function(value)
								modal.close()
								if value == "new" then M.choose(app, nil, folder.id)
								elseif value == "rename" then M.editFolder(folder, function() M.manage(app) end)
								elseif value == "remove" then
									overlay.confirm({ title = "Remove folder?",
										description = "Conversations in this folder will move to Universal. Their messages will be kept.",
										confirmText = "Remove", onConfirm = function()
											local ok, why = sessions.removeFolder(folder.id)
											if not ok then overlay.toast(tostring(why), "warn") end
											M.manage(app)
										end })
								end
							end })
					end })
				row.label(folder.label, 1)
			end
		end
		P.button(modal.footer, { text = "Done", variant = "ghost", size = "sm", layoutOrder = 1,
			onClick = function() modal.close() end })
		P.button(modal.footer, { name = "NewFolder", text = "New folder", variant = "primary", size = "sm", layoutOrder = 2,
			onClick = function() modal.close(); M.editFolder(nil, function() M.manage(app) end) end })
		local unsubscribe = sessions.listChanged:connect(render)
		modal.scrim.Destroying:Connect(function()
			unsubscribe()
			if menu and not menu.closed then menu.close() end
		end)
		render()
		return modal
	end

	return M
end
