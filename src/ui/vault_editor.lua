-- Native vault forms retain drafts independently of a refreshed application panel.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local vault = env.require("runtime/master_vault")
	local place = env.require("runtime/place")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	local entries, alive = {}, true
	local DRAFT_LIMIT = 8
	local FIELD_LIMITS = { title = 160, description = 500, content = 64000, placeId = 32, project = 160, tags = 800, verification = 4000 }
	local KINDS = {
		{ value = "recipe", label = "Recipe" }, { value = "bugfix", label = "Bug fix" },
		{ value = "remote", label = "Remote contract" }, { value = "instance", label = "Instance configuration" },
		{ value = "project", label = "Project" }, { value = "reference", label = "Reference" },
	}
	local SCOPES = {
		{ value = "global", label = "Global" }, { value = "game", label = "Game" },
		{ value = "project", label = "Project" },
	}
	local STATUSES = {
		{ value = "draft", label = "Draft" }, { value = "verified", label = "Verified" },
		{ value = "outdated", label = "Outdated" },
	}
	local function labelOf(options, value)
		for _, option in ipairs(options) do if option.value == value then return option.label end end
		return tostring(value)
	end
	local function formOf(document)
		return {
			title = document.title or "", description = document.description or "", content = document.content or "",
			kind = document.kind or "recipe", scope = document.scope or "global", status = document.status or "draft",
			placeId = tostring(document.placeId or place.id or ""), project = document.project or "",
			tags = table.concat(document.tags or {}, "\n"), sources = util.deepCopy(document.sources or {}),
			verification = document.verification or "",
		}
	end
	local function documentOf(entry)
		local form, tags, sources = entry.form, {}, {}
		for line in form.tags:gmatch("[^\r\n]+") do
			local tag = util.trim(line); if tag ~= "" then tags[#tags + 1] = tag end
		end
		for _, source in ipairs(form.sources) do
			local label, url = util.trim(source.label or ""), util.trim(source.url or "")
			if label ~= "" or url ~= "" then sources[#sources + 1] = { label = label, url = url ~= "" and url or nil } end
		end
		return {
			id = entry.document.id, title = form.title, description = form.description, content = form.content,
			kind = form.kind, scope = form.scope, status = form.status, tags = tags, sources = sources,
			placeId = form.scope == "game" and tonumber(form.placeId) or nil,
			project = form.scope == "project" and form.project or nil,
			verification = form.verification ~= "" and form.verification or nil,
			updatedAt = entry.document.updatedAt,
		}
	end
	local function forget(entry)
		if entries[entry.key] == entry then entries[entry.key] = nil end
	end
	local function adopt(entry, document, useFile)
		local other = document.id and entries[document.id]
		if other and other ~= entry then
			entry.blocked, entry.recoveryId = true, document.id
			return false, "This note has another editor or retained draft. Close that editor or resolve its draft, then read the current note again."
		end
		forget(entry)
		entry.document = util.deepCopy(document)
		entry.key = document.id or util.uid("vault-draft")
		entries[entry.key] = entry
		entry.blocked, entry.recoveryId = false, nil
		if useFile then entry.form, entry.dirty = formOf(document), false end
		return true
	end
	local function releaseClean(entry)
		if not entry.owner and not entry.dirty and not entry.blocked and not entry.busy then forget(entry) end
	end
	local function reserve(document)
		local key = document.id
		if key and entries[key] then return entries[key] end
		if key then for _, entry in pairs(entries) do if entry.recoveryId == key then return entry end end end
		if util.count(entries) >= DRAFT_LIMIT then return nil, "Eight vault editors or drafts are already kept. Save or discard one before opening another." end
		key = key or util.uid("vault-draft")
		local populated = not document.id and ((document.title or "") ~= "" or (document.content or "") ~= "")
		local entry = { key = key, document = util.deepCopy(document), form = formOf(document), dirty = populated, blocked = false, busy = false }
		entries[key] = entry
		return entry
	end
	local clear = dispose.add(function()
		alive = false
		for _, entry in pairs(entries) do if entry.owner and not entry.owner.closed then entry.owner.close() end end
		entries = {}
	end, "master vault drafts")
	if env.root then env.root.Destroying:Connect(clear) end

	function M.listDrafts()
		local list = {}
		for _, entry in pairs(entries) do
			if entry.dirty or entry.blocked or entry.busy then
				list[#list + 1] = { key = entry.key, title = entry.form.title ~= "" and entry.form.title or "Untitled note",
					blocked = entry.blocked, busy = entry.busy, id = entry.document.id }
			end
		end
		table.sort(list, function(a, b) return a.key < b.key end)
		return list
	end
	local function copyMarkdown(document, status)
		local markdown, why = vault.format(document)
		if not markdown then status(tostring(why)); return end
		local ok, problem = env.require("runtime/clipboard").write(markdown)
		status(ok and "Markdown copied with its metadata." or tostring(problem))
		if ok then return end
		local modal = overlay.modal({ title = "Export Markdown", description = "Select and copy the note below.", width = theme.size.modalWide, scroll = true, fitContent = true })
		if not modal then return end
		local field = P.field(modal.content, { name = "VaultExportText", text = markdown, multiline = true,
			height = theme.size.controlLarge * 6, role = "mono", syntax = false, readOnly = true })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		P.button(modal.footer, { text = "Select all", variant = "secondary", size = "sm", onClick = field.selectAll })
	end
	local function review(entry, latest, missing, onChoose)
		local modal = overlay.modal({ title = "Review current note", description = missing
			and "The note is confirmed absent. Your draft is kept."
			or "Review the saved note before choosing which version to keep.", width = theme.size.modalWide, scroll = true, fitContent = true })
		if not modal then return end
		if not missing then
			local markdown, why = vault.format(latest)
			if not markdown then modal.close(); overlay.toast(tostring(why), "warn"); return end
			P.field(modal.content, { name = "VaultCurrentNote", text = markdown, multiline = true,
				height = theme.size.controlLarge * 6, role = "mono", syntax = false, readOnly = true })
		end
		P.text(modal.content, { text = missing
			and "Save as new note prepares a new identity for your next explicit Save. It does not write a file."
			or "Keep draft adopts this saved revision for your next explicit Save. Use file replaces your local draft with the version shown above.",
			role = "small", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
		P.button(modal.footer, { text = "Cancel", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "VaultKeepDraft", text = missing and "Save as new note" or "Keep draft", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() modal.close(); onChoose(false, missing) end })
		if not missing then P.button(modal.footer, { name = "VaultUseFile", text = "Use file", variant = "primary", size = "sm", layoutOrder = 3,
			onClick = function() modal.close(); onChoose(true, false) end }) end
	end

	function M.open(document, onSaved, retained)
		if not alive or dispose.draining then return nil end
		local entry, problem = retained, nil
		if not entry then entry, problem = reserve(document) end
		if not entry then overlay.toast(problem, "warn"); return nil end
		if entry.owner and not entry.owner.closed then overlay.toast("This note is already open.", "info"); return entry.owner end
		if entry.busy then overlay.toast("This note has an operation in progress. Reopen it after completion.", "info"); return nil end
		local readOnly = entry.document.readOnly == true
		local writable = vault.stats().writable == true
		local locked = readOnly or not writable
		local modal = overlay.modal({ title = entry.form.title ~= "" and entry.form.title or "New vault note",
			description = readOnly and "Starter library / Read-only" or not writable and "My Vault / Read-only on this host"
				or "My Vault / Markdown editor", width = theme.size.modalWide, scroll = true, fitContent = true })
		if not modal then releaseClean(entry); return nil end
		entry.owner = modal
		local painting, fields, choices = false, {}, {}
		local status, save, reload, remove, details, gameField, projectField, sourcesRows, addSource
		local sync, paint, buildSources
		local function report(message)
			if not modal.closed and status then status.Text = message end
		end
		local function changed()
			entry.dirty = true
			if sync then sync() end
		end
		local function field(parent, name, label, key, props)
			props = props or {}
			local group = P.column(parent, { name = name .. "Group", auto = "Y", size = UDim2.new(1, 0, 0, 0),
				gap = theme.space.hair, layoutOrder = props.order })
			P.text(group, { text = label, role = "label", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
			local control = P.field(group, { name = name, text = entry.form[key], placeholder = props.placeholder,
				multiline = props.multiline, height = props.height, role = props.role, syntax = false, readOnly = locked,
				onChange = function(value, handle)
					if painting then return end
					if entry.busy or locked then painting = true; handle.set(entry.form[key]); painting = false; return end
					if #value > FIELD_LIMITS[key] or not util.validUtf8(value) or value:find("%z") then
						painting = true; handle.set(entry.form[key]); painting = false
						report(label .. " must be valid UTF-8 within " .. tostring(FIELD_LIMITS[key]) .. " bytes."); return
					end
					entry.form[key] = value; changed()
				end })
			fields[key] = control
			return group, control
		end
		local function choice(parent, name, label, key, options, order)
			local button = P.button(parent, { name = name, text = label .. ": " .. labelOf(options, entry.form[key]),
				variant = "secondary", size = "sm", fill = true, layoutOrder = order, onClick = function(control)
					if entry.busy or locked then return end
					overlay.menu({ target = control.instance, options = options, onSelect = function(value)
						if modal.closed or entry.busy or locked then return end
						entry.form[key] = value; control.setText(label .. ": " .. labelOf(options, value)); changed()
					end })
				end })
			choices[key] = { control = button, options = options, label = label }
			return button
		end
		field(modal.content, "VaultNoteTitle", "Title", "title", { order = 1 })
		field(modal.content, "VaultNoteDescription", "Summary", "description", { order = 2 })
		field(modal.content, "VaultNoteContent", "Markdown", "content", { order = 3, multiline = true,
			height = theme.size.controlLarge * 7, role = "mono" })
		status = P.text(modal.content, { name = "VaultEditorStatus", text = "", role = "small", wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), color = theme.color.textSecondary, layoutOrder = 4 })
		P.button(modal.content, { name = "VaultNoteDetails", text = "Details and sources", variant = "ghost", size = "sm", layoutOrder = 5,
			onClick = function(control) details.Visible = not details.Visible; control.setText(details.Visible and "Hide details" or "Details and sources") end })
		details = P.column(modal.content, { name = "VaultNoteMetadata", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, visible = false, layoutOrder = 6 })
		choice(details, "VaultNoteKind", "Type", "kind", KINDS, 1)
		choice(details, "VaultNoteScope", "Scope", "scope", SCOPES, 2)
		gameField = field(details, "VaultNotePlaceId", "Place ID", "placeId", { order = 3 })
		projectField = field(details, "VaultNoteProject", "Project name", "project", { order = 4 })
		field(details, "VaultNoteTags", "Tags (one per line)", "tags", { order = 5, multiline = true, height = theme.size.controlLarge * 2 })
		choice(details, "VaultNoteStatus", "Verification status", "status", STATUSES, 6)
		field(details, "VaultNoteVerification", "Verification evidence", "verification", { order = 7, multiline = true,
			height = theme.size.controlLarge * 3, placeholder = "What was checked, where, and what the result establishes" })
		P.text(details, { text = "Sources", role = "label", layoutOrder = 8 })
		sourcesRows = P.column(details, { name = "VaultNoteSources", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, layoutOrder = 9 })
		local sourceFields = {}
		buildSources = function()
			for _, child in ipairs(sourcesRows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			sourceFields = {}
			for index, source in ipairs(entry.form.sources) do
				local row = P.column(sourcesRows, { name = "VaultSourceGroup" .. tostring(index), auto = "Y", size = UDim2.new(1, 0, 0, 0),
					gap = theme.space.hair, layoutOrder = index })
				local item = source
				local function sourceField(key, caption)
					local control = P.field(row, { name = "VaultSource" .. caption .. tostring(index), text = item[key] or "",
						placeholder = caption == "Label" and "Source name" or "URL or document reference (optional)", readOnly = locked,
						onChange = function(value, handle)
							if painting then return end
							if entry.busy or locked then painting = true; handle.set(item[key] or ""); painting = false; return end
							local maximum = key == "label" and 160 or 500
							if #value > maximum or not util.validUtf8(value) or value:find("%z") then
								painting = true; handle.set(item[key] or ""); painting = false
								report("Source " .. key .. " must be valid UTF-8 within " .. tostring(maximum) .. " bytes."); return
							end
							item[key] = value; changed()
						end })
					sourceFields[#sourceFields + 1] = control
				end
				sourceField("label", "Label"); sourceField("url", "Reference")
				if not locked then P.button(row, { name = "VaultRemoveSource" .. tostring(index), text = "Remove source", variant = "ghost", size = "sm",
					onClick = function() if not entry.busy then table.remove(entry.form.sources, index); buildSources(); changed() end end }) end
			end
		end
		addSource = P.button(details, { name = "VaultAddSource", text = "Add source", variant = "secondary", size = "sm", layoutOrder = 10,
			onClick = function() if not entry.busy and not locked and #entry.form.sources < 8 then entry.form.sources[#entry.form.sources + 1] = { label = "", url = "" }; buildSources(); changed() end end })
		P.text(details, { text = "Notes read by an agent enter its conversation with the selected model.", role = "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), color = theme.color.textSecondary, layoutOrder = 11 })
		local actions = P.column(modal.content, { name = "VaultEditorActions", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 7 })
		P.button(actions, { name = "VaultCopyMarkdown", text = "Copy Markdown", variant = "ghost", size = "sm", onClick = function() copyMarkdown(documentOf(entry), report) end })
		P.button(actions, { name = "VaultCopyBody", text = "Copy text", variant = "ghost", size = "sm", onClick = function()
			local ok, why = env.require("runtime/clipboard").write(entry.form.content); report(ok and "Note text copied." or tostring(why))
		end })
		if readOnly then
			P.button(modal.footer, { name = "VaultCopyStarter", text = "Copy to My Vault", variant = "primary", size = "sm", enabled = writable, layoutOrder = 2, onClick = function()
				if not writable then return end
				local copy = documentOf(entry); copy.id, copy.status = nil, "draft"; M.open(copy, onSaved)
			end })
		else
			reload = P.button(actions, { name = "VaultReadCurrent", text = "Read current note", variant = "secondary", size = "sm", onClick = function()
				local id = entry.recoveryId or entry.document.id
				if entry.busy or not id then return end
				entry.busy = true; sync("Reading current note...")
				clock.spawn(function()
					local latest, why, detail = vault.read(id)
					if not alive then return end
					entry.busy = false
					if modal.closed then releaseClean(entry); return end
					sync(why and tostring(why) or nil)
					local missing = not latest and type(detail) == "table" and detail.missing == true and detail.id == id
					if not latest and not missing then return end
					review(entry, latest, missing, function(useFile, useNew)
						if modal.closed or entry.busy then return end
						local accepted, problem = adopt(entry, useNew and {} or latest, useFile)
						if not accepted then sync(problem); return end
						if useNew then entry.dirty = true end
						paint(); sync(useNew and "A new note is prepared. Save explicitly to write it." or nil)
					end)
				end)
			end })
			remove = P.button(actions, { name = "VaultDeleteNote", text = "Delete note", variant = "ghost", size = "sm", onClick = function()
				if not writable or entry.busy or entry.blocked or entry.dirty or not entry.document.id then return end
				overlay.confirm({ title = "Delete this vault note?", description = "The saved Markdown file will be removed. This cannot be undone.", confirmText = "Delete", danger = true,
					onConfirm = function()
						if modal.closed or entry.busy or entry.blocked or entry.dirty then return end
						entry.busy = true; sync("Deleting note...")
						clock.spawn(function()
							local ok, why = vault.delete(entry.document.id, entry.document.revision)
							if not alive then return end
							entry.busy = false
							if ok then forget(entry); modal.close(); if onSaved then onSaved() end
							else entry.blocked = true; entry.recoveryId = entry.document.id; sync(tostring(why) .. " Read the current note before another change.") end
						end)
					end })
			end })
			P.button(modal.footer, { name = "VaultDiscardDraft", text = "Discard draft", variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
				if entry.busy then return end
				overlay.confirm({ title = "Discard this vault draft?", description = "Your local unsaved text and metadata will be removed.", confirmText = "Discard",
					onConfirm = function() if not modal.closed and not entry.busy then forget(entry); modal.close() end end })
			end })
			save = P.button(modal.footer, { name = "VaultSaveNote", text = "Save", variant = "primary", size = "sm", layoutOrder = 3, onClick = function()
				if not writable or entry.busy or entry.blocked then return end
				local proposal = documentOf(entry)
				local valid, why = vault.format(proposal)
				if not valid then sync(tostring(why)); return end
				entry.busy, entry.blocked = true, true; sync("Saving note...")
				clock.spawn(function()
					local saved, problem, detail = vault.save(proposal, entry.document.revision)
					if not alive then return end
					entry.busy = false
					if saved then
						local accepted, why = adopt(entry, saved, true)
						if accepted then paint(); sync("Note saved.") else sync(why) end
						if onSaved then onSaved() end
					else
						entry.recoveryId = type(detail) == "table" and detail.id or entry.document.id
						-- A rejected create without any dispatched write can be corrected and retried.
						entry.blocked = entry.recoveryId ~= nil
						sync(tostring(problem) .. (entry.blocked and " Your draft is kept. Read the current note before saving again." or " Your draft is kept."))
					end
					releaseClean(entry)
				end)
			end })
		end
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		sync = function(message)
			if modal.closed then return end
			status.Text = message or (not writable and "This host can browse notes but cannot save them. Copy Markdown to keep a portable version."
				or readOnly and "Copy this starter to create an editable note in My Vault."
				or entry.blocked and "Your draft is kept. Read the current note before saving again."
				or entry.dirty and "Unsaved draft kept for this client run. Save or copy it before unloading."
				or entry.document.id and "Saved note loaded." or "New draft. Save writes a new Markdown note.")
			for _, control in pairs(fields) do control.setReadOnly(locked or entry.busy) end
			for _, control in ipairs(sourceFields) do control.setReadOnly(locked or entry.busy) end
			for _, item in pairs(choices) do item.control.setEnabled(not locked and not entry.busy) end
			gameField.Visible, projectField.Visible = entry.form.scope == "game", entry.form.scope == "project"
			addSource.setEnabled(not locked and not entry.busy and #entry.form.sources < 8)
			if save then save.setEnabled(writable and not entry.busy and not entry.blocked and (entry.dirty or not entry.document.id)) end
			if reload then reload.setEnabled(not entry.busy and (entry.recoveryId ~= nil or entry.document.id ~= nil)) end
			if remove then remove.setEnabled(writable and not entry.busy and not entry.blocked and not entry.dirty and entry.document.id ~= nil) end
		end
		paint = function()
			if modal.closed then return end
			painting = true
			for key, control in pairs(fields) do control.set(entry.form[key]) end
			for key, item in pairs(choices) do item.control.setText(item.label .. ": " .. labelOf(item.options, entry.form[key])) end
			painting = false; buildSources()
		end
		modal.scrim.Destroying:Connect(function() if entry.owner == modal then entry.owner = nil end; releaseClean(entry) end)
		buildSources(); sync()
		return modal
	end
	function M.reopen(key, onSaved)
		local entry = entries[key]
		if not entry then overlay.toast("This vault draft is no longer available.", "info"); return nil end
		if entry.import then return M.import(onSaved, entry) end
		return M.open(entry.document, onSaved, entry)
	end
	function M.import(onSaved, retained)
		if not alive or dispose.draining then return nil end
		local entry, problem = retained, nil
		if not entry then entry, problem = reserve({}) end
		if not entry then overlay.toast(problem, "warn"); return nil end
		if entry.owner and not entry.owner.closed then overlay.toast("This import is already open.", "info"); return entry.owner end
		entry.import, entry.form.title = true, "Markdown import"
		local modal = overlay.modal({ title = "Import Markdown", description = "Paste a note, review its fields, then Save to add it to My Vault.", width = theme.size.modalWide, scroll = true, fitContent = true })
		if not modal then releaseClean(entry); return nil end
		entry.owner = modal
		local status = P.text(modal.content, { name = "VaultImportStatus", text = "", role = "small", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
		local accepted, painting = entry.form.content, false
		local field = P.field(modal.content, { name = "VaultImportText", text = accepted, multiline = true, height = theme.size.controlLarge * 7, role = "mono", syntax = false,
			onChange = function(value, control)
				if painting then return end
				if #value > 80000 or not util.validUtf8(value) or value:find("%z") then
					painting = true; control.set(accepted); painting = false
					status.Text = "Imported Markdown must be valid UTF-8 within 80,000 bytes."; return
				end
				accepted, entry.form.content, entry.dirty = value, value, value ~= ""
				status.Text = entry.dirty and "Import text is kept for this client run. Review it before saving." or ""
			end })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		P.button(modal.footer, { name = "VaultDiscardImport", text = "Discard draft", variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
			overlay.confirm({ title = "Discard this Markdown import?", description = "Your pasted or typed Markdown will be removed from this client run.", confirmText = "Discard",
				onConfirm = function() if not modal.closed then forget(entry); modal.close() end end })
		end })
		P.button(modal.footer, { name = "VaultReviewImport", text = "Review import", variant = "primary", size = "sm", layoutOrder = 3, onClick = function()
			local document, why = vault.parse(field.get())
			if not document then status.Text = tostring(why); return end
			document.id, document.revision, document.readOnly = nil, nil, false
			document.status = "draft"
			local formerDocument, formerForm, formerDirty = entry.document, entry.form, entry.dirty
			entry.document, entry.form, entry.dirty, entry.import, entry.owner = document, formOf(document), true, false, nil
			local opened = M.open(document, onSaved, entry)
			if opened then modal.close()
			else entry.document, entry.form, entry.dirty, entry.import, entry.owner = formerDocument, formerForm, formerDirty, true, modal end
		end })
		modal.scrim.Destroying:Connect(function() if entry.owner == modal then entry.owner = nil end; releaseClean(entry) end)
		if entry.dirty then status.Text = "Import text is kept for this client run. Review it before saving." end
		return modal
	end
	return M
end
