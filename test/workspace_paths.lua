-- Focused workspace identity, Unicode, canonical paths and migration regressions.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local fixture = require("workspace_fixture")
local suite = fixture.suite("Workspace paths")
local check, case = suite.check, suite.case
local function setup()
	local f = fixture.new()
	f.tools({ "fs" })
	return f, f.env.require("runtime/fsx")
end

case("all file tools reuse canonical paths without nesting the root", function()
	local f, fs = setup()
	local path = "files/Game (77)/main.lua"
	local wrote = f.dispatch("file_write", { path = path, content = "local x = 1\n" })
	check("write reports canonical path", wrote.ok and wrote.data.path == path)
	check("prefix applied once", f.h.files["UAI/" .. path] == "local x = 1\n" and f.h.files["UAI/files/" .. path] == nil)
	check("physical legacy path is accepted", f.dispatch("file_append", { path = "UAI/" .. path, content = "return x\n" }).ok)
	check("canonical edit works", f.dispatch("file_edit", { path = path, old_text = "x = 1", new_text = "x = 2" }).ok)
	check("bulk edits use same namespace", f.dispatch("file_edit_many", { path = path, edits = { { old_text = "x = 2", new_text = "x = 3" } } }).ok)
	local read = f.dispatch("file_read", { path = path })
	check("read identifies real file", read.ok and read.data.path == path and read.text:find("x = 3", 1, true))
	local listed = f.dispatch("file_list", { path = "UAI/files/Game (77)" })
	check("list path is directly reusable", listed.ok and listed.data.entries[1].path == path)
	local search = f.dispatch("file_search", { query = "x = 3", path = "files/Game (77)" })
	check("search uses same path", search.ok and search.data.matches[1].path == path)
	check("delete uses same path", f.dispatch("file_delete", { path = path }).ok and f.h.files["UAI/" .. path] == nil)
	check("workspace root cannot be deleted", not f.dispatch("file_delete", { path = "files/" }).ok)
	check("absolute paths stay rejected", not f.dispatch("file_write", { path = "/files/main.lua", content = "x" }).ok)
	local longPath = ("x"):rep(170) .. "/a.lua"
	check("canonical prefixes do not consume the legacy relative-path budget", fs.userPath("UAI/files/" .. longPath) == longPath)
	check("pastes cannot be accidentally written into another scope", not f.dispatch("file_write", { path = "pastes/x.txt", content = "x" }).ok)
	check("client state remains separate", fs.exists("config.json") and not fs.exists("config.json", { scope = "files" }))
end)

case("real nested files directories and app-named directories remain addressable", function()
	local f, fs = setup()
	for _, path in ipairs({ "files/files/files/keep.lua", "files/UAI/deep/keep.lua", "files/pastes/keep.lua" }) do
		check("nested write succeeds", f.dispatch("file_write", { path = path, content = path }).ok)
		local found = f.dispatch("file_search", { path = path, query = "keep" })
		check("nested search returns exact location", found.ok and found.data.matches[1].path == path)
		check("nested read is unchanged", fs.readUser(path) == path)
	end
	local listed = f.dispatch("file_list", { path = "files/UAI/deep" })
	check("inner UAI segment is not mistaken for app root", listed.data.entries[1].path == "files/UAI/deep/keep.lua")
	fs.migrate(); fs.migrate()
	check("boot migration leaves existing recursion intact", fs.readUser("files/files/files/keep.lua") == "files/files/files/keep.lua")
end)

case("file list pages and bulk reads avoid needless follow-up reads", function()
	local f, fs = setup()
	for index = 1, 75 do assert(fs.write(string.format("many/%02d.lua", index), "x", { scope = "files" })) end
	f.env.require("runtime/config").set("agent.resultCap", 600)
	local nextOffset, seen, count = 1, {}, 0
	repeat
		local page = f.dispatch("file_list", { path = "files/many", offset = nextOffset })
		check("listing remains bounded with a continuation", page.ok and not page.truncated and #page.text <= 600)
		for _, entry in ipairs(page.data.entries) do check("each file appears once", not seen[entry.path]); seen[entry.path] = true; count = count + 1 end
		nextOffset = page.data.nextOffset
	until not nextOffset
	check("all list entries are reachable", count == 75)
	f.env.require("runtime/config").set("agent.resultCap", 6000)
	assert(fs.write("one.lua", ("a"):rep(1500), { scope = "files" }))
	assert(fs.write("two.lua", ("b"):rep(1500), { scope = "files" }))
	local both = f.dispatch("file_read_many", { reads = { { path = "one.lua" }, { path = "files/two.lua" } } })
	check("two modest sources fit one default batch", both.ok and both.data.results[1].slice.eof and both.data.results[2].slice.eof)
	local caps, reads = f.env.require("runtime/caps"), 0
	local original = caps.fn.readfile
	caps.fn.readfile = function(...) reads = reads + 1; return original(...) end
	local aliases = f.dispatch("file_read_many", { reads = { { path = "one.lua", limit = 64 }, { path = "files/one.lua", offset = 65, limit = 64 }, { path = "UAI/files/one.lua", offset = 129, limit = 64 } } })
	check("aliases share one native read in the batch", aliases.ok and reads == 1)
	assert(fs.write("saved.txt", "paste", { scope = "pastes" }))
	local distinct = f.dispatch("file_read_many", { reads = { { path = "saved.txt" }, { path = "files/saved.txt" } } })
	check("bare paste fallback does not poison explicit workspace cache", distinct.data.results[1].ok and not distinct.data.results[2].ok)
end)

case("Unicode folder names remain readable and valid", function()
	local f, fs = setup()
	local w, util = f.env.require("runtime/workspace"), f.env.require("runtime/util")
	local accent, cjk, emoji = "Caf\195\169", "\230\184\184\230\136\143", "\240\159\142\174"
	local joined = "\240\159\145\169\226\128\141\240\159\146\187"
	for _, name in ipairs({ accent, cjk, emoji, emoji .. emoji, joined, "Cafe\204\129", "symbols + = !", "COM\194\185.txt", "LPT\194\178.txt", "CON.txt", "a<>:\"/\\|?* .", ".", "<>?*", (cjk .. joined):rep(50), "bad\255name" }) do
		local folder = w.folderName(name, 555)
		check("folder is valid UTF-8 and a safe path", util.validUtf8(folder) and fs.sanitise(folder) ~= nil)
		check("folder remains bounded and retains PlaceId", #folder < 100 and folder:sub(-6) == " (555)")
	end
	check("accented letters preserved", w.folderName(accent, 1) == accent .. " (1)")
	check("CJK preserved", w.folderName(cjk, 1) == cjk .. " (1)")
	check("emoji ZWJ sequence preserved", w.folderName(joined, 1) == joined .. " (1)")
	check("only unsafe symbols get readable fallback", w.folderName("<>?*", 1) == "Place (1)")
	check("superscript Windows devices are rejected", fs.sanitise("COM\194\185.txt") == nil and fs.sanitise("LPT\194\179.txt") == nil)
	check("PlaceId disambiguates identical sanitization", w.folderName("a/b", 1) ~= w.folderName("a\\b", 2))
	f.h.sandbox.utf8 = { nfcnormalize = function(name) return name:gsub("e\204\129", "\195\169") end }
	local composed, method = w.folderName("Cafe\204\129", 1)
	check("host NFC capability is used when available", composed == accent .. " (1)" and method == "NFC")
	f.h.sandbox.utf8 = nil
	local fallback, fallbackMethod = w.folderName("Cafe\204\129", 1)
	check("fallback preserves combining Unicode without claiming normalization", fallback == "Cafe\204\129 (1)" and fallbackMethod == "preserved UTF-8")
end)

case("PlaceId reuses existing and legacy folders across changing display names", function()
	local f, fs = setup()
	local p = f.env.require("runtime/place")
	p.id, p.name = 77, "New name"
	assert(fs.write("Old name (77)/main.lua", "kept", { scope = "files" }))
	local w = f.env.require("runtime/workspace")
	check("existing name wins by PlaceId", w.describe().path == "files/Old name (77)")
	p.name = "Another name"
	check("display-name changes cannot move the workspace", w.describe().path == "files/Old name (77)" and w.describe().displayName == "Another name")
	f.loaded["runtime/workspace"] = nil
	check("selection survives reload", f.env.require("runtime/workspace").describe().path == "files/Old name (77)")
	p.id, p.name = 88, "New"
	assert(fs.write("files/files/Original (88)/script.lua", "legacy", { scope = "files" }))
	check("existing recursive folder stays accessible without flattening", f.env.require("runtime/workspace").describe().path == "files/files/files/Original (88)")
	p.id, p.name = 99, ""
	local fallback = f.env.require("runtime/workspace").describe().path
	p.name = "Eventually resolved"
	check("late metadata cannot fork an already advertised folder", fallback == f.env.require("runtime/workspace").describe().path)
	fs.migrate()
	check("workspace identity is client state", fs.exists("workspace.json") and not fs.exists("workspace.json", { scope = "files" }))
end)

case("migration preserves sources on failed writes, conflicts and incomplete listings", function()
	local f, fs = setup()
	assert(fs.write("conflict.txt", "source")); assert(fs.write("conflict.txt", "destination", { scope = "files" }))
	assert(fs.write("fail.txt", "source")); assert(fs.write("partial.txt", "source"))
	assert(fs.write("deep/nested/safe.lua", "kept"))
	assert(fs.write("skills/existing.md", "displaced", { scope = "files" })); assert(fs.write("existing.md", "installed", { scope = "skills" }))
	local caps = f.env.require("runtime/caps")
	local original = caps.fn.writefile
	caps.fn.writefile = function(path, content)
		if path == "UAI/files/fail.txt" then return false end
		if path == "UAI/files/partial.txt" then return original(path, "partial") end
		return original(path, content)
	end
	fs.migrate()
	check("conflicting originals remain", fs.read("conflict.txt") == "source" and fs.read("conflict.txt", { scope = "files" }) == "destination")
	check("failed and partial writes retain originals", fs.read("fail.txt") == "source" and fs.read("partial.txt") == "source")
	check("skill conflicts never overwrite installed skills", fs.read("existing.md", { scope = "skills" }) == "installed" and fs.read("skills/existing.md", { scope = "files" }) == "displaced")
	check("nested migration keeps structure", fs.read("deep/nested/safe.lua", { scope = "files" }) == "kept" and not fs.exists("deep/nested/safe.lua"))
	assert(fs.ensure("UAI/unsupported"))
	f.h.files["UAI/unsupported/invalid?.txt"] = "do not delete"
	fs.migrate()
	check("unsupported filenames prevent recursive directory deletion", f.h.files["UAI/unsupported/invalid?.txt"] == "do not delete" and fs.isDir("unsupported"))
end)

case("shallow host migration does not discard nested files", function()
	local f, fs = setup()
	assert(fs.write("legacy/a/b/keep.lua", "keep"))
	local caps, original = f.env.require("runtime/caps"), f.env.require("runtime/caps").fn.listfiles
	caps.fn.listfiles = function(path)
		local out = {}
		for _, entry in ipairs(original(path)) do
			local name = entry:sub(#path + 2)
			if not name:find("/", 1, true) then out[#out + 1] = name end
		end
		return out
	end
	fs.migrate(); fs.migrate()
	check("shallow directory recursion preserves original structure", fs.readUser("files/legacy/a/b/keep.lua") == "keep")
	check("migration remains idempotent", f.h.files["UAI/files/files/legacy/a/b/keep.lua"] == nil)
end)

suite.finish()
