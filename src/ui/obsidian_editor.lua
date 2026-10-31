-- Revision-safe native Markdown editing with retained, bounded local drafts.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local clock = env.require("runtime/clock")
	local transport = env.require("net/obsidian")
	local drafts = env.require("runtime/obsidian_drafts")
	local documents = env.require("runtime/obsidian_document")
	local M = {}
	function M.open(vault, document, onSaved)
		local entry, problem = drafts.reserve(vault.id, document.path, document)
		if not entry then overlay.toast(problem, "warn"); return nil end
		if entry.owner then overlay.toast("This note is already open in an editor.", "info"); return nil end
		local modal = overlay.modal({ title = document.path, description = vault.name .. (vault.readOnly and " / Read-only" or " / Markdown editor"),
			width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		entry.owner = modal
		local loading, painting = false, false
		local field, status, save, reload
		local function sync(message)
			if modal.closed then return end
			status.Text = message or (entry.blocked and "Check the current file before saving again. Your draft is kept."
				or entry.dirty and "Unsaved draft kept in memory. Save or copy it before unloading the client."
				or "Current file loaded.")
			if save then save.setEnabled(not loading and not vault.readOnly and not entry.blocked and (entry.dirty or not entry.document.revision)) end
			if reload then reload.setEnabled(not loading and (entry.document.revision ~= nil or entry.blocked)) end
			if field then field.instance.TextEditable = not loading and not vault.readOnly end
		end
		field = P.field(modal.content, { name = "ObsidianNoteText", text = entry.text, multiline = true, height = 300,
			role = "mono", syntax = false, layoutOrder = 1, onChange = function(text)
				if painting or modal.closed then return end
				local ok, why = drafts.update(entry, text)
				if not ok then painting = true; field.set(entry.text); painting = false end
				sync(why)
			end })
		status = P.text(modal.content, { name = "ObsidianEditorStatus", text = "", role = "small", wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), color = theme.color.textSecondary, layoutOrder = 2 })
		local actions = P.column(modal.content, { auto = "Y", gap = theme.space.xs, layoutOrder = 3 })
		P.button(actions, { name = "ObsidianCopyNote", text = "Copy text", variant = "ghost", size = "sm", onClick = function()
			local ok, why = env.require("runtime/clipboard").write(entry.text); sync(ok and "Note text copied." or tostring(why))
		end })
		P.button(actions, { name = "ObsidianNoteDetails", text = "Details", variant = "ghost", size = "sm", onClick = function()
			env.require("ui/obsidian_metadata").open(entry.document)
		end })
		P.button(actions, { name = "ObsidianNoteLinks", text = "Links", variant = "ghost", size = "sm", onClick = function()
			env.require("ui/obsidian_links").open(vault, entry.document.path)
		end })
		reload = P.button(actions, { name = "ObsidianReadCurrent", text = "Read current file", variant = "secondary", size = "sm", onClick = function()
			if loading then return end
			loading = true; sync("Reading current file...")
			clock.spawn(function()
				local latest, why = transport.readNote(vault.id, entry.document.path, { aborted = function() return modal.closed end })
				if modal.closed then return end
				loading = false; sync(why)
				if not latest then return end
				env.require("ui/obsidian_recovery").open(entry, latest, function(useFile)
					if modal.closed then return end
					entry.document, entry.blocked = latest, false
					if useFile then entry.text = documents.editorText(latest.content) end
					drafts.update(entry, entry.text)
					painting = true; field.set(entry.text); painting = false; sync()
				end)
			end)
		end })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "ObsidianDiscardDraft", text = "Discard draft", variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
			if loading then return end
			overlay.confirm({ title = "Discard this note draft?", description = "The file stays unchanged. This removes the local unsaved text.", confirmText = "Discard",
				onConfirm = function() if not modal.closed then entry.dirty = false; drafts.remove(vault.id, document.path); modal.close() end end })
		end })
		save = P.button(modal.footer, { name = "ObsidianSaveNote", text = "Save", variant = "primary", size = "sm", layoutOrder = 3, onClick = function()
			if loading or vault.readOnly or entry.blocked then return end
			loading, entry.blocked = true, true; sync("Saving note...")
			clock.spawn(function()
				local saved, why = transport.saveNote(entry.document, entry.text, { aborted = function() return modal.closed end })
				if modal.closed then return end
				loading = false
				if saved then entry.document, entry.blocked, entry.dirty = saved, false, false; sync("Note saved and verified."); if onSaved then onSaved() end
				else sync(tostring(why) .. " Your draft is kept. Read the current file before saving again.") end
			end)
		end })
		modal.scrim.Destroying:Connect(function()
			entry.owner = nil
			if not entry.dirty and not entry.blocked then drafts.remove(vault.id, document.path) end
		end)
		sync()
		return modal
	end
	return M
end
