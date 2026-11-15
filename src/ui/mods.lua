-- Portable UI mod management. One unfinished JSON form survives panel refreshes.
-- Applying and disabling use the session controller; this module never runs source.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local mods = env.require("runtime/ui_mods")
	local document = env.require("runtime/ui_mod_document")
	local preview = env.require("ui/mod_preview")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	local alive, opened, draft, controllerBusy = true, nil, nil, false
	local refreshOpen, refreshDraft, openEditor
	local function label(parent, name, text, order, role)
		return P.text(parent, { name = name, text = text or "", role = role or "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = order })
	end
	local function message(value)
		return util.ellipsis(util.sanitise(tostring(value or "The operation could not finish.")), 1600)
	end
	local function changed()
		if refreshDraft then refreshDraft() end
		if refreshOpen then refreshOpen() end
	end
	local function unfinished(entry) return entry and (entry.dirty or entry.blocked or entry.busy) end
	function M.hasDrafts() return alive and unfinished(draft) == true end
	local function release(entry)
		if draft == entry and not entry.owner and not unfinished(entry) then draft = nil end
	end
	local function copySpec(spec, report)
		local json, why = document.format(spec)
		if not json then report(message(why)); return end
		local ok, reason = env.require("runtime/clipboard").write(json)
		if ok then report("Portable JSON copied, including source and attribution."); return end
		report(message(reason))
		local modal = overlay.modal({ title = "Export UI mod", description = "Select and copy the complete portable definition.",
			width = theme.size.modalWide, scroll = true, fitContent = true })
		if not modal then return end
		modal.card.Name = "UiModExport"
		local field = P.field(modal.content, { name = "UiModExportJson", text = json, multiline = true,
			height = theme.size.controlLarge * 7, role = "mono", syntax = false, readOnly = true })
		P.button(modal.footer, { name = "UiModExportClose", text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		P.button(modal.footer, { name = "UiModExportSelect", text = "Select all", variant = "secondary", size = "sm", layoutOrder = 2, onClick = field.selectAll })
		return modal
	end
	local function begin(mode, record, spec, report)
		if not alive then return nil end
		if draft and unfinished(draft) then
			if record and draft.id == record.id and draft.owner and not draft.owner.closed then return draft.owner end
			report("Resume or discard the unfinished JSON form before opening another one."); return nil
		end
		if draft and draft.owner and not draft.owner.closed then draft.owner.close() end
		local json, why
		if spec then json, why = document.format(spec) else json = "" end
		if not json then report(message(why)); return nil end
		draft = { mode = mode, id = record and record.id, revision = record and record.revision,
			json = json, baseline = json, dirty = mode == "edit" and record and spec ~= record.spec or false,
			blocked = false, busy = false }
		return openEditor(draft, report)
	end
	local function template(kind)
		local spec = { version = 1, kind = kind, id = "my-ui-mod", name = "My UI mod", description = "", sources = {} }
		if kind == "script" then
			spec.source = "-- Return a startup factory; UAI calls it when this mod is applied.\nreturn function(context)\n"
				.. "\tlocal panel = assert(context:CreatePanel({ id = \"workspace\", title = \"My workspace\" }))\n"
				.. "\tlocal section = assert(panel:Section({ id = \"actions\", title = \"Actions\" }))\n"
				.. "\tsection:Text({ id = \"welcome\", text = \"Your native Project UAI panel.\" })\n"
				.. "\tsection:Button({ id = \"chat\", text = \"Open Chat\", callback = function() context.app.show(\"chat\") end })\n"
				.. "\tpanel:Show()\nend"
		else
			spec.appearance = { density = "compact" }
			spec.panels = { { id = "overview", title = "My workspace", description = "", widgets = {
				{ id = "session-tokens", type = "metric", label = "Session tokens", selector = "tokens" },
				{ id = "open-vault", type = "action", label = "Open Master Vault", action = "vault" },
			} } }
		end
		return spec
	end
	openEditor = function(entry, parentReport)
		if not alive or draft ~= entry then return nil end
		if entry.owner and not entry.owner.closed then return entry.owner end
		if entry.busy then parentReport("This form has an operation in progress. Resume it after completion."); return nil end
		local modal, feedback, field, bytes, save, readCurrent, previewButton, discard, copy
		local painting = false
		local function report(text)
			if modal and not modal.closed and feedback then feedback.Text = message(text) end
		end
		local function cleanup()
			entry.owner = nil
			refreshDraft = nil
			if entry.review and not entry.review.closed then entry.review.close() end
			if entry.export and not entry.export.closed then entry.export.close() end
			release(entry); changed()
		end
		modal = overlay.modal({ title = entry.mode == "edit" and "Edit UI mod" or entry.mode == "import" and "Import UI mod" or "New UI mod",
			description = "Edit the complete portable JSON. Save stages a disabled definition; Apply starts its exact saved version.",
			width = theme.size.modalWide, scroll = true, fitContent = true, onClose = cleanup })
		if not modal then release(entry); return nil end
		entry.owner = modal; modal.card.Name = "UiModEditor"
		label(modal.content, "UiModJsonLabel", "Portable JSON / up to " .. tostring(document.limits.json) .. " UTF-8 bytes", 1, "label")
		local function sync()
			if modal.closed then return end
			local state = mods.state()
			bytes.Text = tostring(#entry.json) .. " / " .. tostring(document.limits.json) .. " bytes"
				.. (entry.blocked and " / current storage must be reviewed" or entry.dirty and " / unsaved" or "")
			field.setEnabled(not entry.busy)
			save.setEnabled(not entry.busy and not controllerBusy and not entry.blocked and state.writable == true and util.trim(entry.json) ~= "")
			readCurrent.setEnabled(not entry.busy)
			previewButton.setEnabled(not entry.busy and util.trim(entry.json) ~= "")
			discard.setEnabled(not entry.busy)
			copy.setEnabled(not entry.busy and util.trim(entry.json) ~= "")
		end
		field = P.field(modal.content, { name = "UiModJson", text = entry.json, multiline = true,
			height = theme.size.controlLarge * 7, role = "mono", syntax = false, layoutOrder = 2,
			onChange = function(value, control)
				if painting then return end
				if entry.busy or #value > document.limits.json or not util.validUtf8(value) or value:find("[%z\1-\8\11\12\14-\31\127]") then
					painting = true; control.set(entry.json); painting = false
					report(entry.busy and "Wait for the current operation to finish." or "The previous text was kept. JSON must be valid UTF-8 within its byte limit."); return
				end
				if value ~= entry.json then entry.json, entry.dirty = value, true; sync(); changed() end
			end })
		bytes = label(modal.content, "UiModJsonBytes", "", 3, "caption")
		feedback = label(modal.content, "UiModEditorNotice", "Visual definitions support appearance, panels, text, metrics and navigation. Script definitions carry full Lua source. Imports remain disabled, including after restart.", 4, "caption")
		local actions = P.row(modal.content, { name = "UiModEditorActions", wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 5 })
		local function parse()
			local spec, why = document.parse(entry.json)
				if not spec then report(why) end
			return spec
		end
		local function reviewSpec(record, description)
			if entry.review and not entry.review.closed then entry.review.close() end
			local reviewing = overlay.modal({ title = "UI mod preview", description = description,
				width = theme.size.modalWide, scroll = true, fitContent = true })
			if not reviewing then return end
			entry.review = reviewing; reviewing.card.Name = "UiModDraftPreview"
			preview.render(reviewing.content, record, { sourceLabel = "Unsaved JSON form" })
			P.button(reviewing.footer, { name = "UiModPreviewClose", text = "Close", variant = "ghost", size = "sm", onClick = reviewing.close })
			return reviewing
		end
		previewButton = P.button(actions, { name = "UiModPreviewDraft", text = "Preview", variant = "secondary", size = "sm",
			onClick = function() if entry.busy or modal.closed then return end; local spec = parse(); if spec then reviewSpec({ spec = spec }, "This preview does not activate the mod or run its source.") end end })
		copy = P.button(actions, { name = "UiModCopyDraft", text = "Export JSON", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function()
				if entry.busy or modal.closed then return end
				local spec = parse()
				if spec then
					if entry.export and not entry.export.closed then entry.export.close() end
					entry.export = copySpec(spec, report)
				end
			end })
		readCurrent = P.button(actions, { name = "UiModReadCurrent", text = "Read current", variant = "ghost", size = "sm", layoutOrder = 3,
			onClick = function()
				if entry.busy or modal.closed then return end
				local spec = document.parse(entry.json)
				local id = entry.id or spec and spec.id
				if not id then report("Provide a valid portable ID before reading current storage."); return end
				entry.busy = true; sync(); changed()
				clock.spawn(function()
					local ok, latest, why, detail = pcall(mods.read, id, { refresh = true, aborted = function() return not alive or modal.closed end })
					entry.busy = false
					if not alive then return end
					if modal.closed then release(entry); changed(); return end
					sync()
					local missing = ok and latest == nil and detail and detail.missing == true
					if not ok or not latest and not missing then report(ok and why or "Current storage could not be read. The draft is kept."); return end
					if entry.review and not entry.review.closed then entry.review.close() end
					local reviewing = overlay.modal({ title = "Review current UI mod", description = missing
						and "This ID is confirmed absent. The draft is kept until your next explicit Save."
						or "Review this saved definition before adopting its revision or replacing your form.",
						width = theme.size.modalWide, scroll = true, fitContent = true })
					if not reviewing then return end
					entry.review = reviewing; reviewing.card.Name = "UiModCurrentReview"
					if latest then
						preview.render(reviewing.content, latest, { sourceLabel = "Current executor storage" })
						local json = assert(document.format(latest.spec))
						P.field(reviewing.content, { name = "UiModCurrentJson", text = json, multiline = true,
							height = theme.size.controlLarge * 4, role = "mono", syntax = false, readOnly = true, layoutOrder = 2 })
					end
					label(reviewing.content, "UiModReviewEffect", missing
						and "Save as new prepares a create against this confirmed absence. It does not write storage."
						or "Keep draft adopts this exact revision for the next Save. Use file replaces the unsaved form with the definition shown.", 3, "caption")
					P.button(reviewing.footer, { text = "Cancel", variant = "ghost", size = "sm", onClick = reviewing.close })
					P.button(reviewing.footer, { name = "UiModKeepDraft", text = missing and "Save as new" or "Keep draft",
						variant = "secondary", size = "sm", layoutOrder = 2, onClick = function()
							if modal.closed or reviewing.closed or entry.busy then return end
							entry.id, entry.revision = latest and latest.id or nil, latest and latest.revision or nil
							entry.mode, entry.blocked, entry.dirty = latest and "edit" or "new", false, true
							reviewing.close(); report("Draft kept. Save will use the reviewed storage state."); sync(); changed()
						end })
					if latest then P.button(reviewing.footer, { name = "UiModUseFile", text = "Use file", variant = "primary", size = "sm", layoutOrder = 3,
						onClick = function()
							if modal.closed or reviewing.closed or entry.busy then return end
							entry.id, entry.revision, entry.mode = latest.id, latest.revision, "edit"
							entry.json, entry.baseline = assert(document.format(latest.spec)), assert(document.format(latest.spec))
							entry.dirty, entry.blocked = false, false
							painting = true; field.set(entry.json); painting = false
							reviewing.close(); report("The reviewed file is in the form."); sync(); changed()
						end }) end
				end)
			end })
		P.button(modal.footer, { name = "UiModEditorClose", text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		discard = P.button(modal.footer, { name = "UiModDiscardDraft", text = "Discard draft", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function()
				if entry.busy or modal.closed then return end
				if entry.review and not entry.review.closed then entry.review.close() end
				entry.review = overlay.confirm({ title = "Discard the unfinished form?", description = "This removes the JSON draft kept in memory. Saved definitions remain available.",
					confirmText = "Discard draft", danger = true, onConfirm = function()
						if not alive or entry.busy or modal.closed then return end
						if draft == entry then draft = nil end
						entry.dirty, entry.blocked = false, false; modal.close(); changed()
					end })
			end })
		save = P.button(modal.footer, { name = "UiModSaveDraft", text = "Save disabled", variant = "primary", size = "sm", layoutOrder = 3,
			onClick = function()
				if entry.busy or controllerBusy or entry.blocked or modal.closed or not mods.state().writable then return end
				local spec = parse(); if not spec then return end
				if entry.mode == "edit" and spec.id ~= entry.id then report("Keep this mod's ID while editing. Use a new form to save another identity."); return end
				entry.busy = true; sync(); changed()
				local json, revision, mode = entry.json, entry.revision, entry.mode
				clock.spawn(function()
					local options = { aborted = function() return not alive or dispose.draining end }
					local ok, saved, why, detail
					if mode == "import" then ok, saved, why, detail = pcall(mods.import, json, options)
					else ok, saved, why, detail = pcall(mods.save, spec, revision, options) end
					entry.busy = false
					if not alive then return end
					if ok and saved then
						entry.id, entry.revision, entry.mode = saved.id, saved.revision, "edit"
						entry.json = assert(document.format(saved.spec)); entry.baseline = entry.json
						entry.dirty, entry.blocked = false, false
						if not modal.closed then painting = true; field.set(entry.json); painting = false; report("Saved version " .. tostring(saved.version) .. " disabled. Apply it from UI Mods when ready.") end
					else
						entry.blocked, entry.dirty = true, true
						report((ok and message(why) or "The save stopped unexpectedly.") .. " Draft kept. Read current before retrying.")
					end
					if not modal.closed then sync() end
					release(entry); changed()
				end)
			end })
		refreshDraft = sync
		sync()
		return modal
	end
	function M.open(props)
		props = props or {}
		if not alive or dispose.draining then return nil end
		if opened and not opened.closed then return opened end
		local modal, notice, summary, rows, queryField, details, exported, disableButton, syncDetails
		local pending, queued, needRefresh, query = false, false, false, ""
		local buttons, rowButtons, cached = {}, {}, { writable = false }
		local refresh, schedule
		local function report(text) if modal and not modal.closed and notice then notice.Text = message(text) end end
		local function currentSession()
			if type(props.getSession) == "function" then return props.getSession() end
			return props.session or env.require("agent/session").current()
		end
		local function cleanup()
			if opened == modal then opened, refreshOpen = nil, nil end
			if details and not details.closed then details.close() end
			if exported and not exported.closed then exported.close() end
			if draft and draft.owner and not draft.owner.closed then draft.owner.close() end
		end
		modal = overlay.modal({ title = "UI Mods", description = "Build and share a personal client workspace. Visual specifications and unrestricted Lua source are stored with their own saved versions.",
			width = theme.size.modalWide, scroll = true, fitContent = true, onClose = cleanup })
		if not modal then return nil end
		opened = modal; modal.card.Name = "UiModsManager"
		summary = label(modal.content, "UiModsSummary", "Reading saved definitions...", 1, "caption")
		queryField = P.field(modal.content, { name = "UiModsSearch", placeholder = "Search mod names and IDs", layoutOrder = 2,
			onChange = function(value, control)
				if #value > 160 or not util.validUtf8(value) or value:find("[%z\1-\31\127]") then control.set(query); report("Search accepts one line within 160 UTF-8 bytes."); return end
				query = value; if schedule then schedule() end
			end })
		local actions = P.row(modal.content, { name = "UiModsActions", wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 3 })
		notice = label(modal.content, "UiModsNotice", "", 4, "caption")
		rows = P.column(modal.content, { name = "UiModRecords", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, layoutOrder = 5 })
		local function sync()
			if modal.closed then return end
			for _, button in ipairs(buttons) do button.setEnabled(not pending) end
			for _, item in ipairs(rowButtons) do item.button.setEnabled(not pending and (not item.write or not controllerBusy and cached.writable == true)) end
			buttons.resume.setEnabled(not pending and unfinished(draft) == true and not draft.busy)
			if disableButton then disableButton.setEnabled(not pending and not controllerBusy) end
			queryField.setEnabled(not pending)
			if syncDetails then syncDetails() end
		end
		local function run(operation, finish, controlsClient)
			if modal.closed or pending or not alive or controlsClient and controllerBusy then return false end
			if controlsClient then controllerBusy = true; changed() end
			pending = true; sync()
			clock.spawn(function()
				local ok, value, why, detail = pcall(operation)
				pending = false
				if controlsClient then controllerBusy = false; changed() end
				if modal.closed or not alive then return end
				if not ok then report("The operation stopped unexpectedly."); sync()
				else if finish then finish(value, why, detail) end; sync() end
				if needRefresh then needRefresh = false; schedule() end
			end)
			return true
		end
		local function apply(record)
			if pending or controllerBusy or modal.closed then return end
			local session = currentSession()
			if not session or type(session.applyUiMod) ~= "function" then report("The current session cannot apply UI mods."); return end
			report("Applying the exact saved version...")
			run(function() return session.applyUiMod(record.id, record.revision) end, function(value, why)
				local failed = value == nil or value == false or type(value) == "table" and
					(value.ok == false or type(value.data) == "table" and value.data.applied == false)
				report(type(value) == "table" and value.text or why or (failed and "The UI mod was not applied." or "UI mod applied."))
				schedule()
			end, true)
		end
		local function showDetails(record)
			if details and not details.closed then details.close() end
			local viewing, selected, rendered, jsonField, applyButton, detailExport, update = nil, record, nil, nil, nil, nil, nil
			viewing = overlay.modal({ title = record.name, description = "Read the complete definition and its retained versions. Export preserves source and attribution.",
				width = theme.size.modalWide, scroll = true, fitContent = true, onClose = function()
					if syncDetails == update then syncDetails = nil end
					if rendered then rendered.destroy() end
					if detailExport and not detailExport.closed then detailExport.close() end
				end })
			if not viewing then return end
			details = viewing; viewing.card.Name = "UiModDetails"
			local versions = P.row(viewing.content, { name = "UiModVersions", wrap = true, auto = "Y",
				size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 1 })
			local body = P.column(viewing.content, { name = "UiModVersionBody", auto = "Y", size = UDim2.new(1, 0, 0, 0),
				gap = theme.space.sm, layoutOrder = 2 })
			local detailNotice = label(viewing.content, "UiModDetailsNotice", "", 3, "caption")
			local function paint(value)
				if viewing.closed then return end
				selected = value
				if rendered then rendered.destroy() end
				if jsonField then jsonField.shell:Destroy() end
				rendered = preview.render(body, selected, { sourceLabel = selected == record and "Current saved definition" or "Retained saved version", layoutOrder = 1 })
				jsonField = P.field(body, { name = "UiModDetailsJson", text = assert(document.format(selected.spec)), multiline = true,
					height = theme.size.controlLarge * 4, role = "mono", syntax = false, readOnly = true, layoutOrder = 2 })
				if update then update() end
				detailNotice.Text = selected == record and "Apply starts this exact saved revision."
					or "Restore this version as a draft, then Save and Apply."
			end
			P.button(versions, { name = "UiModVersionCurrent", text = "Current version", variant = "secondary", size = "sm", onClick = function() paint(record) end })
			for index, previous in ipairs(record.history or {}) do
				local version = { spec = previous.spec, version = previous.version }
				P.button(versions, { name = "UiModVersion_" .. tostring(previous.version), text = "Version " .. tostring(previous.version),
					variant = "ghost", size = "sm", layoutOrder = index + 1, onClick = function() paint(version) end })
			end
			P.button(viewing.footer, { name = "UiModDetailsClose", text = "Close", variant = "ghost", size = "sm", onClick = viewing.close })
			P.button(viewing.footer, { name = "UiModExportVersion", text = "Export JSON", variant = "ghost", size = "sm", layoutOrder = 2,
				onClick = function()
					if viewing.closed then return end
					if detailExport and not detailExport.closed then detailExport.close() end
					detailExport = copySpec(selected.spec, function(text) if not viewing.closed then detailNotice.Text = message(text) end end)
				end })
			P.button(viewing.footer, { name = "UiModRestoreVersion", text = "Restore as draft", variant = "secondary", size = "sm", layoutOrder = 3,
				onClick = function() if viewing.closed then return end; local editor = begin("edit", record, selected.spec, report); if editor then viewing.close() end end })
			applyButton = P.button(viewing.footer, { name = "UiModApplyVersion", text = "Apply", variant = "primary", size = "sm", layoutOrder = 4,
				onClick = function()
					if not viewing.closed and not pending and not controllerBusy and selected == record then viewing.close(); apply(record) end
				end })
			update = function() if not viewing.closed then applyButton.setEnabled(selected == record and cached.writable == true and not pending and not controllerBusy) end end
			syncDetails = update
			paint(record)
		end
		local function rowAction(parent, name, text, write, callback)
			local button = P.button(parent, { name = name, text = text, variant = "ghost", size = "sm", onClick = callback })
			rowButtons[#rowButtons + 1] = { button = button, write = write }
		end
		local function paint(page)
			cached = page.state or mods.state()
			for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			rowButtons = {}
			summary.Text = tostring(page.total) .. " saved mod" .. (page.total == 1 and "" or "s")
				.. " / " .. (cached.writable and "Executor storage ready" or "Storage read-only")
				.. (cached.activeId and (" / active: " .. cached.activeId) or " / no active mod")
				.. (controllerBusy and " / application or cleanup in progress" or "")
			if cached.error then report(cached.error) end
			if #page.items == 0 then label(rows, "UiModsEmpty", query ~= "" and "No saved definitions match this search." or "Create a visual workspace or import a portable UI mod to begin.", 1) end
			for index, item in ipairs(page.items) do
				local record = item
				local card = P.card(rows, { name = "UiModRecord_" .. record.id, layoutOrder = index, padding = theme.space.md, gap = theme.space.xs })
				label(card, "UiModName_" .. record.id, record.name, 1, "bodyStrong")
				label(card, "UiModMetadata_" .. record.id, record.id .. " / " .. (record.kind == "script" and "Lua script" or "Visual")
					.. " / version " .. tostring(record.version) .. " / " .. (record.active and "Active" or "Disabled")
					.. (record.selected and not record.active and " / previously selected; Apply to run" or ""), 2, "caption")
				if record.description ~= "" then label(card, "UiModDescription_" .. record.id, record.description, 3) end
				local row = P.row(card, { name = "UiModActions_" .. record.id, wrap = true, auto = "Y",
					size = UDim2.new(1, 0, 0, 0), gap = theme.space.xxs, layoutOrder = 4 })
				local function read(finish)
					run(function() return mods.read(record.id, { refresh = true, aborted = function() return not alive or modal.closed end }) end,
						function(value, why) if value then finish(value) else report(why); schedule() end end)
				end
				rowAction(row, "UiModRead_" .. record.id, "Details", false, function() read(showDetails) end)
				rowAction(row, "UiModEdit_" .. record.id, "Edit", false, function() read(function(value) begin("edit", value, value.spec, report) end) end)
				rowAction(row, "UiModExport_" .. record.id, "Export", false, function()
					read(function(value) if exported and not exported.closed then exported.close() end; exported = copySpec(value.spec, report) end)
				end)
				rowAction(row, "UiModApply_" .. record.id, "Apply", true, function() apply(record) end)
				rowAction(row, "UiModDelete_" .. record.id, "Delete", true, function()
					if pending or controllerBusy or modal.closed then return end
					if unfinished(draft) and draft.id == record.id then report("Save or discard this mod's unfinished form before deleting it."); return end
					details = overlay.confirm({ title = "Delete this UI mod?", description = record.name .. " / " .. record.id .. ". Its saved definition and retained versions will be removed.",
						confirmText = "Delete", danger = true, onConfirm = function()
							run(function() return mods.delete(record.id, record.revision, { aborted = function() return not alive or dispose.draining end }) end,
								function(value, why) report(value and "UI mod deleted." or why); schedule() end)
						end })
				end)
			end
		end
		refresh = function(force)
			if pending then needRefresh = true; return end
			run(function() return mods.list({ query = query, limit = 16, refresh = force == true,
				aborted = function() return not alive or modal.closed end }) end,
				function(value, why) if value then paint(value) else cached = mods.state(); summary.Text = "Saved definitions could not be refreshed."; report(why) end end)
		end
		schedule = function()
			if modal.closed or queued then return end
			queued = true
			clock.delay(0.05, function() queued = false; if not modal.closed then refresh(false) end end)
		end
		local function action(name, text, callback)
			local button = P.button(actions, { name = name, text = text, variant = "secondary", size = "sm", onClick = callback })
			buttons[#buttons + 1] = button; return button
		end
		action("UiModsNewVisual", "New visual", function() if not pending then begin("new", nil, template("visual"), report) end end)
		action("UiModsNewScript", "New script", function() if not pending then begin("new", nil, template("script"), report) end end)
		action("UiModsImport", "Import JSON", function() if not pending then begin("import", nil, nil, report) end end)
		buttons.resume = action("UiModsResume", "Resume draft", function() if draft then openEditor(draft, report) end end)
		action("UiModsRefresh", "Refresh", function() refresh(true) end)
		disableButton = P.button(modal.footer, { name = "UiModsDisable", text = "Disable mods", variant = "secondary", size = "sm", layoutOrder = 1,
			onClick = function()
				if pending or controllerBusy or modal.closed then return end
				local session = currentSession()
				local stop = type(props.disable) == "function" and props.disable or session and session.disableUiMods
				if type(stop) ~= "function" then report("The current session cannot disable UI mods."); return end
				run(function() return stop() end, function(value, why)
					report(type(value) == "table" and value.text or why or (value and "UI mods disabled." or "UI mods could not be disabled.")); schedule()
				end, true)
			end })
		buttons[#buttons + 1] = disableButton
		P.button(modal.footer, { name = "UiModsClose", text = "Close", variant = "ghost", size = "sm", layoutOrder = 2, onClick = modal.close })
		refreshOpen = schedule
		local unsubscribe = dispose.add(mods.changed:connect(function() if not modal.closed then schedule() end end), "UI mod manager")
		modal.scrim.Destroying:Connect(unsubscribe)
		sync(); refresh(false)
		return modal
	end
	local clear = dispose.add(function()
		alive = false
		if opened and not opened.closed then opened.close() end
		if draft and draft.owner and not draft.owner.closed then draft.owner.close() end
		opened, draft, refreshOpen, refreshDraft, controllerBusy = nil, nil, nil, nil, false
	end, "UI mod forms")
	if env.root then env.root.Destroying:Connect(clear) end
	return M
end
