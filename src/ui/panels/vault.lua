-- The native Master Vault presents local notes and the bundled starter collection.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local place = env.require("runtime/place")
	local vault = env.require("runtime/master_vault")
	local editor = env.require("ui/vault_editor")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local M = {}
	local SEARCH_LIMIT = 256
	local retained = { query = "", scope = "relevant", project = "", kind = "", status = "", origin = "all", offset = 1, back = {} }
	local SCOPES = {
		{ value = "relevant", label = "Global and current game" }, { value = "all", label = "All scopes" },
		{ value = "global", label = "Global" }, { value = "game", label = "Current game" },
		{ value = "project", label = "Project" },
	}
	local ORIGINS = {
		{ value = "all", label = "All notes" }, { value = "notes", label = "My Vault" },
		{ value = "starters", label = "Starter library" },
	}
	local KINDS = {
		{ value = "", label = "All types" }, { value = "recipe", label = "Recipes" },
		{ value = "bugfix", label = "Bug fixes" }, { value = "remote", label = "Remote contracts" },
		{ value = "instance", label = "Instance configurations" }, { value = "project", label = "Projects" },
		{ value = "reference", label = "References" },
	}
	local STATUSES = {
		{ value = "", label = "All statuses" }, { value = "draft", label = "Draft" },
		{ value = "verified", label = "Verified" }, { value = "outdated", label = "Outdated" },
	}
	local function labelOf(options, value)
		for _, option in ipairs(options) do if option.value == value then return option.label end end
		return tostring(value)
	end
	local function scopeLabel(document)
		if document.scope == "game" then return "Game " .. tostring(document.placeId) end
		if document.scope == "project" then return "Project: " .. tostring(document.project) end
		return "Global"
	end
	function M.new(parent)
		local panel = {}
		local state = util.deepCopy(retained)
		local destroyed, visible, dirty, loading = false, true, true, false
		local generation, openGeneration = 0, 0
		local nextOffset, pending, resetPending
		local load, queueLoad, previous, more, refresh, create, import
		local info = vault.stats()
		local writable = info.writable == true
		local scroll = P.scroll(parent, { name = "MasterVaultPanel", size = UDim2.fromScale(1, 1),
			padding = { x = theme.space.lg, top = theme.space.lg, bottom = theme.space.lg }, gap = theme.space.sm })
		P.text(scroll.instance, { name = "MasterVaultTitle", text = "Master Vault", role = "heading", layoutOrder = 1 })
		P.text(scroll.instance, { text = "Keep working recipes, fixes, remote contracts and project knowledge in searchable Markdown notes.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		local controls = P.column(scroll.instance, { name = "VaultBrowseControls", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 3 })
		local status = P.text(scroll.instance, { name = "VaultBrowseStatus", text = "Loading notes...", role = "small",
			color = theme.color.textSecondary, auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 4 })
		local rows = P.column(scroll.instance, { name = "VaultNotes", auto = "Y", size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.sm, layoutOrder = 5 })
		local query = P.field(controls, { name = "VaultSearch", placeholder = "Search titles, tags and note text", text = state.query, layoutOrder = 1,
			onChange = function(text, field)
				if #text > SEARCH_LIMIT or not util.validUtf8(text) or text:find("%z") then
					field.set(state.query); status.Text = "Search text must be valid UTF-8 within 256 bytes."; return
				end
				state.query = text
				state.offset, state.back, nextOffset = 1, {}, nil
				if loading then pending, resetPending = true, true end
				if queueLoad then queueLoad(true) end
			end, onSubmit = function() if load then load(true) end end })
		local filters = P.row(controls, { name = "VaultBrowseFilters", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 2 })
		local project = P.field(controls, { name = "VaultProjectFilter", placeholder = "Exact project name", text = state.project, layoutOrder = 3,
			onChange = function(text, field)
				if #text > 160 or not util.validUtf8(text) or text:find("%z") then
					field.set(state.project); status.Text = "Project names must be valid UTF-8 within 160 bytes."; return
				end
				state.project = text; state.offset, state.back, nextOffset = 1, {}, nil
				if loading then pending, resetPending = true, true end
				if queueLoad then queueLoad(true) end
			end,
			onSubmit = function() if load then load(true) end end })
		project.shell.Visible = state.scope == "project"
		local function filter(name, key, options)
			return P.button(filters, { name = name, text = labelOf(options, state[key]), variant = "secondary", size = "sm",
				onClick = function(button)
					overlay.menu({ target = button.instance, options = options, onSelect = function(value)
						if destroyed then return end
						state[key] = value; button.setText(labelOf(options, value))
						project.shell.Visible = state.scope == "project"; load(true)
					end })
				end })
		end
		filter("VaultScopeFilter", "scope", SCOPES)
		filter("VaultOriginFilter", "origin", ORIGINS)
		filter("VaultKindFilter", "kind", KINDS)
		filter("VaultStatusFilter", "status", STATUSES)
		local function syncBusy()
			if previous then previous.setEnabled(not loading and #state.back > 0) end
			if more then more.setEnabled(not loading and nextOffset ~= nil) end
			if refresh then refresh.setEnabled(not loading) end
			if create then create.setEnabled(writable) end
			if import then import.setEnabled(writable) end
		end
		local function open(id)
			if destroyed then return end
			openGeneration = openGeneration + 1; local mine = openGeneration
			status.Text = "Reading note..."
			clock.spawn(function()
				local document, why = vault.read(id)
				if destroyed or not visible or mine ~= openGeneration then return end
				if not document then status.Text = tostring(why); return end
				editor.open(document, function() if not destroyed then queueLoad(true) end end)
			end)
		end
		local function paint(page)
			for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			nextOffset = page.nextOffset
			status.Text = tostring(page.total) .. " matching notes" .. (page.total > 0 and " / showing " .. tostring(state.offset)
				.. "–" .. tostring(state.offset + #page.items - 1) or "")
				.. (page.incomplete and ". Some notes could not be searched; narrow your filters." or ".")
			if not info.filesystem then status.Text = status.Text .. " This host can browse starters but cannot read local notes." end
			if not writable then status.Text = status.Text .. " Saving needs executor filesystem support." end
			if #page.items == 0 then
				P.text(rows, { name = "VaultEmpty", text = state.origin == "notes" and state.query == ""
					and "My Vault is ready for your knowledge. Create a note, import Markdown, or copy a starter."
					or "No notes match these filters. Try a broader scope or a different search.", role = "body",
					wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) })
			end
			for index, document in ipairs(page.items) do
				local id = document.id
				local row = P.rowButton(rows, { name = "VaultNote_" .. tostring(index), vertical = true, auto = "Y",
					size = UDim2.new(1, 0, 0, 0), padding = theme.space.md, gap = theme.space.xs,
					bg = theme.color.surface, radius = theme.radius.md, layoutOrder = index, onClick = function() open(id) end })
				P.text(row.row, { text = document.title, role = "label", auto = "Y", wrap = true,
					size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
				P.text(row.row, { text = (document.readOnly and "Starter library" or "My Vault") .. " / " .. scopeLabel(document)
					.. " / " .. labelOf(KINDS, document.kind) .. " / " .. labelOf(STATUSES, document.status),
					role = "small", color = theme.color.textSecondary, auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
				if document.description and document.description ~= "" then P.text(row.row, { text = document.description,
					role = "caption", color = theme.color.textSecondary, auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 }) end
				if document.tags and #document.tags > 0 then P.text(row.row, { text = table.concat(document.tags, ", "),
					role = "caption", color = theme.color.textTertiary, auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 4 }) end
			end
		end
		load = function(reset)
			if destroyed then return end
			if reset then state.offset, state.back = 1, {}; nextOffset = nil end
			dirty = true
			if not visible then return end
			if loading then pending, resetPending = true, resetPending or reset; return end
			if #state.query > SEARCH_LIMIT then status.Text = "Search text must fit within 256 bytes."; return end
			if #state.project > 160 then status.Text = "Project names must fit within 160 bytes."; return end
			if state.scope == "project" and util.trim(state.project) == "" then status.Text = "Enter a project name to search its notes."; return end
			if state.scope == "game" and (not place.id or place.id <= 0) then status.Text = "A current Place ID is unavailable on this host."; return end
			generation = generation + 1; local mine = generation
			local searchScope = state.scope == "relevant" and (not place.id or place.id <= 0) and "global" or state.scope
			local options = { query = state.query ~= "" and state.query or nil, scope = searchScope,
				placeId = place.id and place.id > 0 and place.id or nil,
				project = state.scope == "project" and state.project or nil, origin = state.origin,
				kind = state.kind ~= "" and state.kind or nil, status = state.status ~= "" and state.status or nil,
				offset = state.offset, limit = 12 }
			loading, dirty = true, false; syncBusy(); status.Text = "Searching notes..."
			clock.spawn(function()
				local page, why = vault.list(options)
				if destroyed or mine ~= generation then return end
				loading = false
				if pending then local resetNext = resetPending; pending, resetPending = nil, nil; load(resetNext); return end
				if not visible then dirty = true; syncBusy(); return end
				if not page and options.offset > 1 and why == "offset is past the end of this vault listing" then load(true); return end
				if page and page.total > 0 and state.offset > page.total then load(true); return end
				if page then paint(page) else status.Text = tostring(why) end
				syncBusy()
			end)
		end
		local stopQueue
		queueLoad, stopQueue = clock.debounce(load, 0.15)
		local actions = P.row(scroll.instance, { name = "VaultBrowseActions", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 6 })
		refresh = P.button(actions, { name = "VaultRefresh", text = "Refresh", variant = "secondary", size = "sm", onClick = function() load(true) end })
		create = P.button(actions, { name = "VaultNewNote", text = "New note", variant = "primary", size = "sm", onClick = function()
			if writable then editor.open({ scope = state.scope == "game" and "game" or state.scope == "project" and "project" or "global",
				placeId = place.id, project = state.scope == "project" and state.project or nil }, function() if not destroyed then queueLoad(true) end end) end
		end })
		import = P.button(actions, { name = "VaultImport", text = "Import Markdown", variant = "secondary", size = "sm", onClick = function()
			if writable then editor.import(function() if not destroyed then queueLoad(true) end end) end
		end })
		P.button(actions, { name = "VaultRecoverDrafts", text = "Recover drafts", variant = "ghost", size = "sm", onClick = function(button)
			local options = {}
			for _, draft in ipairs(editor.listDrafts()) do options[#options + 1] = { label = draft.title,
				value = draft.key, detail = draft.busy and "Operation in progress" or draft.blocked and "Review needed" or "Unsaved draft" } end
			if #options == 0 then status.Text = "No unsaved vault drafts in this client run."; return end
			overlay.menu({ target = button.instance, options = options, onSelect = function(key)
				editor.reopen(key, function() if not destroyed then queueLoad(true) end end)
			end })
		end })
		local pagination = P.row(scroll.instance, { name = "VaultPagination", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0),
			gap = theme.space.xs, layoutOrder = 7 })
		previous = P.button(pagination, { name = "VaultPrevious", text = "Previous", variant = "secondary", size = "sm", onClick = function()
			if not loading and #state.back > 0 then state.offset = table.remove(state.back); load(); scroll.instance.CanvasPosition = Vector2.new(0, 0) end
		end })
		more = P.button(pagination, { name = "VaultNext", text = "Next", variant = "secondary", size = "sm", onClick = function()
			if not loading and nextOffset then state.back[#state.back + 1] = state.offset; state.offset = nextOffset; load(); scroll.instance.CanvasPosition = Vector2.new(0, 0) end
		end })
		local unsubscribe = vault.changed:connect(function()
			dirty = true; state.offset, state.back, nextOffset = 1, {}, nil
			if loading then pending, resetPending = true, true end
			if visible then queueLoad(true) end
		end)
		local cleanup = dispose.add(function()
			if destroyed then return end
			destroyed = true; generation, openGeneration = generation + 1, openGeneration + 1
			retained = util.deepCopy(state); unsubscribe(); stopQueue()
		end, "master vault panel")
		parent.Destroying:Connect(cleanup)
		function panel.destroy() cleanup() end
		function panel.setVisible(value)
			visible = value == true
			if not visible then openGeneration = openGeneration + 1 end
			if visible and dirty and not destroyed then load() end
		end
		panel.scroll, panel.open = scroll, open
		function panel.refresh() load(true) end
		load(); syncBusy()
		return panel
	end
	return M
end
