-- Actual native editor controls preserve drafts after stale or uncertain saves.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Native Obsidian editor")
local check, case = suite.check, suite.case
local vault = { id = "notes", name = "Notes", readOnly = false, available = true }
local function document(content, revision) return { vault = vault.id, path = "Test.md", content = content, bytes = #content, revision = string.rep(revision or "a", 64) } end
case("failed save is not replayed and current-file review is explicit", function()
	local f = F.ui(900, 750); local saves = 0
	f.loaded["net/obsidian"] = {
		saveNote = function() saves = saves + 1; return nil, "The note changed" end,
		readNote = function() return document("External edit", "b") end,
	}
	local modal = assert(f.env.require("ui/obsidian_editor").open(vault, document("Original")))
	local field = f.h.byName("ObsidianNoteText", modal.card):FindFirstChildOfClass("TextBox")
	field.Text = "My unsaved draft"
	f.h.click(assert(f.h.byName("ObsidianSaveNote", modal.card))); f.h.settle(0.2)
	check("failed edit retains exact text", field.Text == "My unsaved draft" and saves == 1)
	f.h.click(assert(f.h.byName("ObsidianSaveNote", modal.card))); f.h.settle(0.2)
	check("blocked Save cannot replay the write", saves == 1)
	f.h.click(assert(f.h.byName("ObsidianReadCurrent", modal.card))); f.h.settle(0.2)
	check("current file appears for review", f.h.textOf(f.env.root):find("External edit", 1, true) ~= nil)
	f.h.click(assert(f.h.byName("KeepVaultDraft"))); f.h.settle(0.2)
	local retained = assert(f.env.require("runtime/obsidian_drafts").get(vault.id, "Test.md"))
	check("explicit keep retains draft against reviewed revision", retained.text == "My unsaved draft" and retained.document.revision == string.rep("b", 64) and not retained.blocked)
	modal.close(); f.h.settle(0.3)
	check("closing keeps unsaved note for recovery", f.env.require("runtime/obsidian_drafts").get(vault.id, "Test.md").text == "My unsaved draft")
	f.healthy(); f.close()
end)
case("read-only native browser can open a note without enabling writes", function()
	local f = F.ui(320, 568); local selected = { id = "notes", name = "Notes", readOnly = true, available = true }
	f.loaded["net/obsidian"] = {
		request = function(input) return { data = { { path = "Test.md", bytes = 8 } }, offset = input.offset, total = 1 } end,
		readNote = function() return document("Read me") end,
	}
	local browser = assert(f.env.require("ui/obsidian_browser").open(selected))
	f.h.settle(0.2); f.h.click(assert(f.h.byName("ObsidianNote_1", browser.card))); f.h.settle(0.2)
	local field = assert(f.h.byName("ObsidianNoteText")):FindFirstChildOfClass("TextBox")
	check("read-only file opens with exact text", field.Text == "Read me" and field.TextEditable == false)
	check("copy and recovery controls remain available", f.h.byName("ObsidianCopyNote") ~= nil and f.h.byName("ObsidianDiscardDraft") ~= nil)
	f.healthy(); f.close()
end)
suite.finish()
