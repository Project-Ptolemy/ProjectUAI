-- Native vault workflows against source modules and the external mock client.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Master Vault UI")
local check, case = suite.check, suite.case
local function field(f, name, root)
	return assert(f.h.byName(name, root)):FindFirstChildOfClass("TextBox")
end
local function document(content, revision, id)
	return { id = id or "note:fixture", title = "A working fix", description = "Reusable project knowledge", kind = "bugfix",
		scope = "global", status = "draft", tags = { "testing" }, sources = { { label = "Project guide", url = "docs/SCRIPT_PROJECTS.md" } },
		content = content or "Original", revision = revision or "original", readOnly = false }
end
local function stub(f, overrides)
	local runtime = {
		changed = f.env.require("runtime/signal").new("vault fixture"),
		stats = function() return { notes = 1, starters = 0, total = 1, filesystem = true, writable = true } end,
		format = function(value)
			if value.title == "" or value.content == "" then return nil, "A title and body are required" end
			return f.h.json.encode(value)
		end,
		list = function() return { items = { document() }, total = 1, offset = 1 } end,
		read = function() return document() end,
	}
	for key, value in pairs(overrides or {}) do runtime[key] = value end
	f.loaded["runtime/master_vault"] = runtime
	return runtime
end

case("explicit Save creates a portable local note and leaves verification status unchanged", function()
	local f = F.ui(900, 720)
	local vault = f.env.require("runtime/master_vault")
	local editor = f.env.require("ui/vault_editor")
	local modal = assert(editor.open({}))
	field(f, "VaultNoteTitle", modal.card).Text = "A saved recipe"
	field(f, "VaultNoteContent", modal.card).Text = "# A saved recipe\n\nReuse the checked configuration."
	check("typing does not write a file", f.run(function() return vault.list({ origin = "notes" }) end).total == 0)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.4)
	local page = assert(f.run(function() return vault.list({ origin = "notes" }) end))
	check("one new note is saved", page.total == 1)
	local saved = assert(f.run(function() return vault.read(page.items[1].id) end))
	check("saved body and title match the editor", saved.title == "A saved recipe" and saved.content == field(f, "VaultNoteContent", modal.card).Text)
	check("saving does not claim behavioral verification", saved.status == "draft")
	f.h.click(assert(f.h.byName("VaultCopyMarkdown", modal.card)))
	local imported = assert(vault.parse(f.h.sandbox.__clipboard))
	check("copied Markdown round trips metadata, text and the saved timestamp", imported.title == saved.title
		and imported.content == saved.content and imported.updatedAt == saved.updatedAt)
	modal.close(); f.h.settle(0.3)
	check("a clean closed note needs no recovery slot", #editor.listDrafts() == 0)
	f.healthy(); f.close()
end)

case("conflicted saves retain drafts and only an explicit review adopts a new revision", function()
	local f = F.ui(900, 720); local saves, revisions = 0, {}
	stub(f, {
		save = function(value, revision)
			saves = saves + 1; revisions[saves] = revision
			if saves == 1 then return nil, "The saved note changed" end
			return document(value.content, "saved")
		end,
		read = function() return document("External edit", "external") end,
	})
	local editor = f.env.require("ui/vault_editor")
	local modal = assert(editor.open(document()))
	local body = field(f, "VaultNoteContent", modal.card); body.Text = "My unsaved change"
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("failed Save is not replayed", saves == 1 and body.Text == "My unsaved change")
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	check("the current file is shown before a decision", field(f, "VaultCurrentNote").Text:find("External edit", 1, true) ~= nil and saves == 1)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	check("Keep draft retains text without writing", saves == 1 and body.Text == "My unsaved change")
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("the next explicit Save uses the reviewed revision", saves == 2 and revisions[1] == "original" and revisions[2] == "external")
	modal.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("closing during a pending save retains the draft until recovery can reopen safely", function()
	local f = F.ui(430, 620); local saves, inputs, releaseSave = 0, {}, false
	stub(f, {
		save = function(value, revision)
			saves = saves + 1; inputs[saves] = { id = value.id, revision = revision }
			while not releaseSave do f.h.sched.wait() end
			if saves == 1 then return nil, "Unknown outcome", { id = "note:pending", uncertain = true } end
			return document(value.content, "saved", value.id)
		end,
		read = function(id) return document("Written while closed", "written", id) end,
	})
	local editor = f.env.require("ui/vault_editor")
	local modal = assert(editor.open({ title = "Pending note", content = "Keep my draft" }))
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.1)
	modal.close(); f.h.settle(0.3)
	local retained = editor.listDrafts()
	check("the closed operation retains one busy draft", #retained == 1 and retained[1].busy and saves == 1)
	check("reopening waits for the operation rather than locking a new editor", editor.reopen(retained[1].key) == nil)
	releaseSave = true
	f.h.settle(1)
	retained = editor.listDrafts()
	check("the late uncertain result retains the draft for review", #retained == 1 and retained[1].blocked and not retained[1].busy)
	modal = assert(editor.reopen(retained[1].key))
	check("the recovered form keeps the original text", field(f, "VaultNoteContent", modal.card).Text == "Keep my draft")
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.1)
	check("reopening cannot replay an uncertain create", saves == 1)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(1.2)
	check("the reviewed identity is updated by the next explicit Save", saves == 2 and inputs[2].id == "note:pending" and inputs[2].revision == "written")
	modal.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("unknown create outcomes recover their allocated identity instead of duplicating notes", function()
	local f = F.ui(430, 620); local saves, inputs = 0, {}
	stub(f, {
		save = function(value, revision)
			saves = saves + 1; inputs[saves] = { id = value.id, revision = revision }
			if saves == 1 then return nil, "The write could not be confirmed", { id = "note:allocated", uncertain = true } end
			return document(value.content, "saved", value.id)
		end,
		read = function(id) check("recovery reads the allocated identity", id == "note:allocated"); return document("Already written", "written", id) end,
	})
	local editor = f.env.require("ui/vault_editor")
	local modal = assert(editor.open({ title = "New note", content = "Draft text" }))
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("opening the allocated note keeps the uncertain editor", editor.open(document("Already written", "written", "note:allocated")) == modal
		and #editor.listDrafts() == 1)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("uncertain create cannot be retried immediately", saves == 1)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("recovery updates the existing note", saves == 2 and inputs[1].id == nil and inputs[2].id == "note:allocated" and inputs[2].revision == "written")
	f.healthy(); f.close()
end)

case("recovery cannot replace a second editor opened before the save outcome arrived", function()
	local f = F.ui(900, 720); local saves = 0
	stub(f, {
		save = function(value)
			saves = saves + 1
			if saves == 1 then f.h.sched.wait(1); return nil, "Unknown outcome", { id = "note:race", uncertain = true } end
			return document(value.content, "saved", value.id)
		end,
		read = function(id) return document("Current saved note", "current", id) end,
	})
	local editor = f.env.require("ui/vault_editor")
	local modal = assert(editor.open({ title = "Pending note", content = "My retained draft" }))
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.1)
	local second = assert(editor.open(document("Already written", "written", "note:race")))
	f.h.settle(1)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("identity review preserves both open editors and blocks replay", saves == 1
		and field(f, "VaultNoteContent", modal.card).Text == "My retained draft"
		and field(f, "VaultNoteContent", second.card).Text == "Already written")
	second.close(); f.h.settle(0.3)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("resolving the other editor permits a reviewed explicit Save", saves == 2)
	f.healthy(); f.close()
end)

case("generic read errors do not authorize a new create, while reviewed absence does", function()
	local f = F.ui(430, 620); local saves, reads = 0, 0
	stub(f, {
		save = function(value)
			saves = saves + 1
			if saves == 1 then return nil, "Unknown outcome", { id = "note:missing", uncertain = true } end
			check("confirmed absence prepares a fresh identity", value.id == nil)
			return document(value.content, "new", "note:new")
		end,
		read = function(id)
			reads = reads + 1
			if reads == 1 then return nil, "Filesystem is temporarily unavailable" end
			return nil, "Note is absent", { id = id, missing = true }
		end,
	})
	local modal = assert(f.env.require("ui/vault_editor").open({ title = "New note", content = "Draft text" }))
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	check("a read error offers no overwrite or create decision", f.h.byName("VaultKeepDraft") == nil)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("the original uncertainty still blocks Save", saves == 1)
	f.h.click(assert(f.h.byName("VaultReadCurrent", modal.card))); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("VaultKeepDraft"))); f.h.settle(0.2)
	check("reviewed absence does not write by itself", saves == 1)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.2)
	check("explicit Save creates after review", saves == 2)
	f.healthy(); f.close()
end)

case("closed drafts retain metadata, have bounded capacity, and release on unload", function()
	local f = F.ui(900, 720); stub(f)
	local editor = f.env.require("ui/vault_editor")
	for index = 1, 8 do
		local modal = assert(editor.open({ title = "Draft " .. index, content = "Retained " .. index, tags = { "first, second" } }))
		modal.close(); f.h.settle(0.3)
	end
	local retained = editor.listDrafts()
	check("eight drafts remain available", #retained == 8)
	check("a ninth draft does not evict earlier work", editor.open({ title = "Ninth", content = "New" }) == nil and #editor.listDrafts() == 8)
	local modal = assert(editor.reopen(retained[1].key))
	local tags = field(f, "VaultNoteTags", modal.card)
	check("tags containing commas round trip through the form", tags.Text == "first, second")
	local body = field(f, "VaultNoteContent", modal.card); local original = body.Text
	body.Text = string.rep("x", 64001)
	check("an oversized edit preserves the accepted draft", body.Text == original)
	f.healthy(); f.close()
	check("unload releases every retained draft", #editor.listDrafts() == 0)
end)

case("read-only starters remain usable on a host without filesystem writes", function()
	local f = F.ui(320, 568); local saves = 0
	stub(f, { stats = function() return { notes = 0, starters = 1, total = 1, filesystem = false, writable = false } end,
		save = function() saves = saves + 1 end })
	local starter = document("# Starter\n\nUseful reference", "starter", "starter:fixture"); starter.readOnly = true
	local modal = assert(f.env.require("ui/vault_editor").open(starter))
	for _, name in ipairs({ "VaultNoteTitleGroup", "VaultNoteContentGroup", "VaultNoteMetadata", "VaultNoteSources", "VaultSourceGroup1", "VaultEditorActions" }) do
		local holder = assert(f.h.byName(name, modal.card))
		check("editor groups fill the available mobile width", holder.Size.X.Scale == 1 and holder.Size.X.Offset == 0
			and holder.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
	end
	check("the starter text is selectable but read-only", field(f, "VaultNoteContent", modal.card).TextEditable == false)
	f.h.click(assert(f.h.byName("VaultCopyStarter", modal.card)))
	check("Copy to My Vault cannot write or open a writable form", saves == 0 and f.h.byName("VaultSaveNote") == nil)
	f.h.click(assert(f.h.byName("VaultCopyMarkdown", modal.card)))
	check("portable copy remains available", f.h.sandbox.__clipboard:find("Useful reference", 1, true) ~= nil)
	check("the mobile card stays within the viewport", modal.card.Size.X.Offset <= 320 and modal.card.Size.Y.Offset <= 568)
	f.healthy(); f.close()
end)

case("starter copies require explicit Save and preserve the bundled original", function()
	local f = F.ui(900, 720)
	local vault = f.env.require("runtime/master_vault")
	local editor = f.env.require("ui/vault_editor")
	local starter = assert(vault.read("starter:project-knowledge"))
	local modal = assert(editor.open(starter))
	f.h.click(assert(f.h.byName("VaultCopyStarter", modal.card))); f.h.settle(0.2)
	local opened = f.env.require("ui/overlay").open
	local copied = assert(opened[#opened])
	check("copying prepares an editable draft", copied ~= modal and field(f, "VaultNoteContent", copied.card).TextEditable ~= false)
	check("copying does not write a note", f.run(function() return vault.list({ origin = "notes" }) end).total == 0)
	f.h.click(assert(f.h.byName("VaultSaveNote", copied.card))); f.h.settle(0.4)
	local page = assert(f.run(function() return vault.list({ origin = "notes" }) end))
	local saved = assert(f.run(function() return vault.read(page.items[1].id) end))
	check("the copy saves as a new draft with the starter content", page.total == 1 and saved.id:sub(1, 5) == "note:"
		and saved.status == "draft" and saved.content == starter.content)
	local original = assert(vault.read(starter.id))
	check("the bundled note retains its original revision and status", original.readOnly and original.revision == starter.revision and original.status == starter.status)
	f.healthy(); f.close()
end)

case("Markdown import reviews metadata and waits for explicit Save", function()
	local f = F.ui(430, 620)
	local vault = f.env.require("runtime/master_vault")
	local incoming = document("# Imported fix\n\nThe reviewed body.")
	incoming.scope, incoming.project = "project", "Game tools"
	incoming.status, incoming.verification = "verified", "Reviewed by the external fixture."
	local markdown = assert(vault.format(incoming))
	local editor = f.env.require("ui/vault_editor")
	local importer = assert(editor.import())
	field(f, "VaultImportText", importer.card).Text = markdown
	f.h.click(assert(f.h.byName("VaultReviewImport", importer.card))); f.h.settle(0.3)
	local opened = f.env.require("ui/overlay").open
	local modal = assert(opened[#opened])
	check("import review opens the metadata before writing", importer.closed and modal ~= importer
		and field(f, "VaultNoteProject", modal.card).Text == "Game tools"
		and field(f, "VaultSourceLabel1", modal.card).Text == incoming.sources[1].label)
	check("reviewing import writes no note", f.run(function() return vault.list({ origin = "notes" }) end).total == 0)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.4)
	local page = assert(f.run(function() return vault.list({ origin = "notes" }) end))
	local saved = assert(f.run(function() return vault.read(page.items[1].id) end))
	check("explicit Save creates the imported project note", page.total == 1 and saved.project == incoming.project
		and saved.content == incoming.content and saved.sources[1].url == incoming.sources[1].url)
	check("an import starts as Draft while retaining attributed evidence", saved.status == "draft" and saved.verification == incoming.verification)
	f.healthy(); f.close()
end)

case("unreviewed imports share bounded draft slots and recover without writing", function()
	local f = F.ui(430, 620)
	local vault = f.env.require("runtime/master_vault")
	local editor = f.env.require("ui/vault_editor")
	for index = 1, 7 do
		local modal = assert(editor.open({ title = "Kept " .. index, content = "Draft text" }))
		modal.close(); f.h.settle(0.3)
	end
	local markdown = assert(vault.format(document("# Imported draft\n\nKeep the entire input.")))
	local importer = assert(editor.import())
	field(f, "VaultImportText", importer.card).Text = markdown
	local key
	for _, draft in ipairs(editor.listDrafts()) do if draft.title == "Markdown import" then key = draft.key end end
	check("pasted text counts as a draft while the import is open", key ~= nil and #editor.listDrafts() == 8)
	importer.close(); f.h.settle(0.3)
	check("an import occupies its bounded slot after close", editor.open({ title = "Ninth", content = "New draft" }) == nil)
	importer = assert(editor.reopen(key))
	local raw = field(f, "VaultImportText", importer.card)
	check("recovery restores the full unreviewed Markdown", raw.Text == markdown)
	raw.Text = string.rep("x", 80001)
	check("oversized imported text preserves the accepted draft", raw.Text == markdown)
	f.h.click(assert(f.h.byName("VaultReviewImport", importer.card))); f.h.settle(0.3)
	local opened = f.env.require("ui/overlay").open
	local modal = assert(opened[#opened])
	check("review converts the existing slot at capacity", importer.closed and modal ~= importer
		and field(f, "VaultNoteContent", modal.card).Text:find("Keep the entire input.", 1, true) ~= nil
		and #editor.listDrafts() == 8)
	check("draft recovery and review still write no notes", f.run(function() return vault.list({ origin = "notes" }) end).total == 0)
	f.h.click(assert(f.h.byName("VaultSaveNote", modal.card))); f.h.settle(0.4)
	check("explicit Save resolves only the reviewed import", f.run(function() return vault.list({ origin = "notes" }) end).total == 1 and #editor.listDrafts() == 7)
	f.healthy(); f.close()
end)

case("starter browsing and manual export work without game or host storage capabilities", function()
	local f = F.ui(320, 568)
	f.env.require("runtime/fsx").enabled = false
	f.env.require("runtime/caps").clipboard = false
	f.env.require("runtime/place").id = nil
	local panel = f.env.require("ui/panels/vault").new(f.host); f.h.settle(0.3)
	for _, name in ipairs({ "VaultBrowseControls", "VaultBrowseFilters", "VaultNotes", "VaultBrowseActions", "VaultPagination" }) do
		local holder = assert(f.h.byName(name, f.host))
		check("browse containers fill the available mobile width", holder.Size.X.Scale == 1 and holder.Size.X.Offset == 0
			and holder.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
	end
	local first = f.h.byName("VaultNote_1", f.host)
	check("the default filter falls back to global starters", first ~= nil)
	check("a host without writes keeps New note disabled", f.h.byName("VaultNewNote", f.host).Active == false)
	f.h.click(first); f.h.settle(0.3)
	local opened = f.env.require("ui/overlay").open
	local modal = assert(opened[#opened])
	f.h.click(assert(f.h.byName("VaultCopyMarkdown", modal.card))); f.h.settle(0.2)
	local exported = field(f, "VaultExportText")
	check("clipboard absence offers portable selectable Markdown", exported.TextEditable == false
		and f.env.require("runtime/master_vault").parse(exported.Text) ~= nil)
	check("viewing and export make no HTTP requests", f.h.http.requestCount == 0)
	panel.destroy(); f.healthy(); f.close()
end)

case("paged search preserves input identity and resets its cursor across concurrent changes", function()
	local f = F.ui(430, 620); local calls = {}
	local runtime = stub(f, { list = function(options)
		calls[#calls + 1] = { query = options.query, offset = options.offset }
		f.h.sched.wait(0.1)
		if options.query then return { items = { document("Filtered") }, total = 1, offset = options.offset } end
		local items = {}; for index = options.offset, math.min(25, options.offset + options.limit - 1) do
			local item = document("Body", "revision", "note:" .. index); item.title = "Note " .. index; items[#items + 1] = item
		end
		return { items = items, total = 25, offset = options.offset, nextOffset = options.offset + #items <= 25 and options.offset + #items or nil }
	end })
	local panel = f.env.require("ui/panels/vault").new(f.host); f.h.settle(0.3)
	local search = field(f, "VaultSearch", f.host)
	f.h.click(assert(f.h.byName("VaultNext", f.host))); f.h.settle(0.3)
	check("Next reads the next page", calls[#calls].offset == 13)
	search.Text = "filtered"; runtime.changed:fire(); f.h.settle(0.5)
	check("a changed search restarts at one", calls[#calls].query == "filtered" and calls[#calls].offset == 1)
	check("refresh keeps the same native input", field(f, "VaultSearch", f.host) == search and search.Text == "filtered")
	search.Text = string.rep("x", 257)
	check("the search limit preserves the last accepted query", search.Text == "filtered")
	panel.refresh(); f.h.settle(0.02); f.host:Destroy(); f.h.settle(0.3)
	check("destroyed panels cannot paint late results", f.h.byName("VaultNotes") == nil)
	f.healthy(); f.close()
end)

case("shrinking later pages reset on changes and recover a retained out-of-range cursor", function()
	local f = F.ui(430, 620); local total, calls, failRead = 25, {}, false
	local runtime = stub(f, { list = function(options)
		calls[#calls + 1] = options.offset
		f.h.sched.wait(0.1)
		if failRead then return nil, "Filesystem is temporarily unavailable" end
		if options.offset > total + 1 then return nil, "offset is past the end of this vault listing" end
		local items = {}
		for index = options.offset, math.min(total, options.offset + options.limit - 1) do
			local item = document("Body", "revision", "note:" .. index); item.title = "Note " .. index; items[#items + 1] = item
		end
		return { items = items, total = total, offset = options.offset, nextOffset = options.offset + #items <= total and options.offset + #items or nil }
	end })
	local module = f.env.require("ui/panels/vault")
	local panel = module.new(f.host); f.h.settle(0.3)
	f.h.click(assert(f.h.byName("VaultNext", f.host))); f.h.settle(0.3)
	check("the fixture reaches a later page", calls[#calls] == 13)
	total = 2; runtime.changed:fire(); f.h.settle(0.4)
	check("known changes restart pagination and remove stale rows", calls[#calls] == 1
		and f.h.byName("VaultNote_3", f.host) == nil and f.h.byName("VaultNote_2", f.host) ~= nil
		and f.h.byName("VaultPrevious", f.host).Active == false and f.h.byName("VaultNext", f.host).Active == false)
	total = 25; runtime.changed:fire(); f.h.settle(0.4)
	f.h.click(assert(f.h.byName("VaultNext", f.host))); f.h.settle(0.3)
	total = 2; panel.destroy(); f.host:Destroy(); f.h.settle(0.2)
	f.host = f.env.require("ui/primitives").frame(f.env.root, { size = f.h.sandbox.UDim2.fromOffset(430, 620) })
	panel = module.new(f.host); f.h.settle(0.4)
	check("an invalid retained cursor retries exactly once at the first page", calls[#calls - 1] == 13 and calls[#calls] == 1
		and f.h.byName("VaultBrowseStatus", f.host).Text:find("2 matching notes", 1, true) ~= nil)
	total = 25; runtime.changed:fire(); f.h.settle(0.4)
	local before = #calls; failRead = true
	f.h.click(assert(f.h.byName("VaultNext", f.host))); f.h.settle(0.3)
	check("an unrelated read failure is reported without an automatic retry", #calls == before + 1 and calls[#calls] == 13
		and f.h.byName("VaultBrowseStatus", f.host).Text == "Filesystem is temporarily unavailable")
	panel.destroy(); f.healthy(); f.close()
end)

case("commands expose Master Vault and Micro-goals as real destinations", function()
	local f = F.ui(900, 720); local destination
	local app = { show = function(id) destination = id end, showGoals = function() destination = "microGoals" end }
	local commands = f.env.require("ui/commands")
	local modal = assert(commands.open(app, "Master Vault")); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("Command_panel_vault", modal.card)))
	check("Master Vault opens its native panel", modal.closed and destination == "vault")
	modal = assert(commands.open(app, "Micro-goals")); f.h.settle(0.2)
	f.h.click(assert(f.h.byName("Command_action_microGoals", modal.card)))
	check("Micro-goals opens its board", modal.closed and destination == "microGoals")
	f.healthy(); f.close()
end)

case("the Settings startup choice opens Master Vault through the native application", function()
	local f = F.ui(900, 720); stub(f)
	local panes = f.env.require("ui/settingspanes")
	check("the Desktop general pane renders", panes.render("desktop_general", f.host))
	local option = assert(f.h.byName("Segment_vault", assert(f.h.byName("OpenPanel", f.host))))
	f.h.click(option)
	local config = f.env.require("runtime/config")
	check("Open on stores the real Vault panel ID", config.get("ui.panel") == "vault")
	local app = f.env.require("ui/app")
	f.run(function() app.mount() end, 1); f.h.settle(0.4)
	check("first mount preserves the saved Vault destination", app.panel == "vault" and app.panels.vault ~= nil
		and config.get("ui.panel") == "vault" and f.h.byName("MasterVaultPanel", app.screen) ~= nil)
	local vaultRow = assert(f.h.byName("MasterVault", app.screen))
	check("the Vault navigation keeps its label and requested book icon", f.h.byName("Label", vaultRow).Text == "Master Vault"
		and f.h.byName("IconBook", assert(f.h.byName("IconSlot", vaultRow))) ~= nil)
	f.healthy(); f.close()
end)

suite.finish()
