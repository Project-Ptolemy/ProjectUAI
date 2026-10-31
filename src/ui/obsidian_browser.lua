-- Native vault browsing shares the authenticated note transport with tools.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local clock = env.require("runtime/clock")
	local transport = env.require("net/obsidian")
	local notes = env.require("runtime/obsidian")
	local M = {}
	function M.open(vault)
		local modal = overlay.modal({ title = vault.name, description = "Browse and search Markdown notes on the bridge computer.", width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local epoch, loading, offset, nextOffset = 0, false, 1, nil
		local backStack = {}
		local loadedQuery, loadedFolder
		local load, previous, more, refresh, create
		local folder = P.field(modal.content, { name = "ObsidianFolder", placeholder = "Folder (optional)", layoutOrder = 1 })
		local query = P.field(modal.content, { name = "ObsidianSearch", placeholder = "Search note paths and text", layoutOrder = 2,
			onSubmit = function() if load then offset, backStack = 1, {}; load() end end })
		local status = P.text(modal.content, { name = "ObsidianBrowseStatus", text = "Loading notes...", role = "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
		local rows = P.column(modal.content, { name = "ObsidianNotes", auto = "Y", gap = theme.space.xs, layoutOrder = 4 })
		local function busy(value)
			loading = value
			if previous then previous.setEnabled(not value and #backStack > 0) end
			if more then more.setEnabled(not value and nextOffset ~= nil) end
			if refresh then refresh.setEnabled(not value) end
			if create then create.setEnabled(not value and not vault.readOnly) end
		end
		local function openNote(path)
			if loading then return end
			local retained = env.require("runtime/obsidian_drafts").get(vault.id, path)
			if retained then env.require("ui/obsidian_editor").open(vault, retained.document, load); return end
			busy(true); status.Text = "Reading " .. path .. "..."
			local mine = epoch
			clock.spawn(function()
				local document, why = transport.readNote(vault.id, path, { aborted = function() return modal.closed or epoch ~= mine end })
				if modal.closed or epoch ~= mine then return end
				busy(false)
				if not document then status.Text = tostring(why); return end
				status.Text = "Note loaded."
				env.require("ui/obsidian_editor").open(vault, document, load)
			end)
		end
		load = function()
			if modal.closed or loading then return end
			local prefix, invalid = notes.path(folder.get(), true)
			if not prefix then status.Text = invalid; return end
			local needle = env.require("runtime/util").trim(query.get())
			if #needle > 300 then status.Text = "Search text must fit within 300 bytes."; return end
			if needle ~= loadedQuery or prefix ~= loadedFolder then offset, backStack = 1, {} end
			loadedQuery, loadedFolder = needle, prefix
			epoch = epoch + 1; local mine = epoch
			busy(true); status.Text = "Loading notes..."
			clock.spawn(function()
				local result, why = transport.request({ action = needle ~= "" and "search" or "list", vault = vault.id,
					folder = prefix, query = needle ~= "" and needle or nil, offset = offset, limit = 30 },
					{ aborted = function() return modal.closed or mine ~= epoch end })
				if modal.closed or mine ~= epoch then return end
				local page
				if result then page, why = env.require("runtime/obsidian_listing").validate(result, offset) end
				if not page then busy(false); status.Text = tostring(why); return end
				for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
				nextOffset = page.nextOffset
				status.Text = tostring(page.total) .. " notes" .. (page.total > 0 and " / showing from " .. tostring(offset) or "")
					.. (page.incomplete and ". Coverage is incomplete; narrow the folder or search." or ".")
				for index, entry in ipairs(page.rows) do
					local row = P.rowButton(rows, { name = "ObsidianNote_" .. tostring(index), vertical = true, auto = "Y",
						size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, bg = theme.color.surfaceRaised,
						radius = theme.radius.md, gap = theme.space.xxs, layoutOrder = index, onClick = function() openNote(entry.path) end })
					P.text(row.row, { text = entry.path, role = "label", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
					if entry.detail ~= "" then P.text(row.row, { text = entry.detail, role = "small", color = theme.color.textSecondary,
						auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 }) end
				end
				busy(false)
			end)
		end
		local actions = P.column(modal.content, { auto = "Y", gap = theme.space.xs, layoutOrder = 5 })
		refresh = P.button(actions, { name = "ObsidianSearchNotes", text = "Search or refresh", variant = "secondary", size = "sm", onClick = function() offset, backStack = 1, {}; load() end })
		create = P.button(actions, { name = "ObsidianNewNote", text = "New note", variant = "secondary", size = "sm", onClick = function()
			if vault.readOnly or loading then return end
			overlay.prompt({ title = "New Markdown note", description = "Use a vault-relative path ending in .md. Existing files cannot be overwritten.",
				placeholder = "Folder/Note.md", confirmText = "Create draft", onConfirm = function(value)
					local path, why = notes.path(value)
					if not path then overlay.toast(why, "warn"); return end
					env.require("ui/obsidian_editor").open(vault, { vault = vault.id, path = path, content = "", bytes = 0 }, load)
				end })
		end })
		P.button(actions, { name = "ObsidianDrafts", text = "Recover note drafts", variant = "ghost", size = "sm", onClick = function(button)
			local options = {}
			for _, entry in ipairs(env.require("runtime/obsidian_drafts").list(vault.id)) do options[#options + 1] = { label = entry.document.path, value = entry.document.path } end
			if #options == 0 then status.Text = "No unsaved note drafts in this client run."; return end
			overlay.menu({ target = button.instance, options = options, onSelect = openNote })
		end })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		previous = P.button(modal.footer, { name = "ObsidianPrevious", text = "Previous", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() if not loading and #backStack > 0 then offset = table.remove(backStack); load() end end })
		more = P.button(modal.footer, { name = "ObsidianNext", text = "Next", variant = "secondary", size = "sm", layoutOrder = 3,
			onClick = function() if not loading and nextOffset then backStack[#backStack + 1] = offset; offset = nextOffset; load() end end })
		load()
		return modal
	end
	return M
end
