-- Focused workspace identity, Unicode, canonical paths and migration regressions.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local fixture = require("workspace_fixture")
local suite = fixture.suite("Workspace paths")
local check, case = suite.check, suite.case
local function setup()
	local f = fixture.new()
	f.tools({ "fs", "script" })
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
	check("compiler uses the exact file-tool path", f.dispatch("check_luau", { path = path }).ok)
	local ran = f.dispatch("run_luau", { path = path })
	check("runner reads the same edited source", ran.ok and ran.text:find("3", 1, true))
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

case("generated folders use ASCII while explicit Unicode paths stay exact", function()
	local f, fs = setup()
	local w, util = f.env.require("runtime/workspace"), f.env.require("runtime/util")
	local accent, cjk, emoji = "Caf\195\169", "\230\184\184\230\136\143", "\240\159\142\174"
	local joined = "\240\159\145\169\226\128\141\240\159\146\187"
	for _, name in ipairs({ accent, cjk, emoji, emoji .. emoji, joined, "Cafe\204\129", "symbols + = !", "COM\194\185.txt", "LPT\194\178.txt", "CON.txt", "a<>:\"/\\|?* .", ".", "<>?*", (cjk .. joined):rep(50), "bad\255name" }) do
		local folder = w.folderName(name, 555)
		check("folder is valid UTF-8 and a safe path", util.validUtf8(folder) and fs.sanitise(folder) ~= nil)
		check("generated folder is portable ASCII", not folder:find("[\128-\255]"))
		check("folder remains bounded and retains PlaceId", #folder < 100 and folder:sub(-6) == " (555)")
	end
	check("ASCII words remain readable beside emoji", w.folderName(emoji .. " Harbor", 1) == "Harbor (1)")
	check("Unicode-only display names use place identity", w.folderName(cjk .. joined, 1) == "Place (1)")
	check("only unsafe symbols get readable fallback", w.folderName("<>?*", 1) == "Place (1)")
	check("superscript Windows devices are rejected", fs.sanitise("COM\194\185.txt") == nil and fs.sanitise("LPT\194\179.txt") == nil)
	check("PlaceId disambiguates identical sanitization", w.folderName("a/b", 1) ~= w.folderName("a\\b", 2))
	local path = "files/" .. joined .. "/" .. accent .. ".lua"
	check("existing Unicode remains writable when the host supports it", f.dispatch("file_write", { path = path, content = "return 1" }).ok)
	local listed = f.dispatch("file_list", { path = "files/" .. joined })
	check("explicit Unicode round-trips without normalization", listed.ok and listed.data.entries[1].path == path and fs.readUser(path) == "return 1")
end)

case("host listing bases preserve real nested roots and directory-relative descendants", function()
	for _, style in ipairs({ "absolute", "scope", "directory", "app" }) do
		local f, fs = setup()
		local path = "files/files/Game (77)/nested/main.lua"
		assert(f.dispatch("file_write", { path = path, content = "return 77" }).ok)
		local caps = f.env.require("runtime/caps")
		local original = caps.fn.listfiles
		caps.fn.listfiles = function(dir)
			local items = original(dir)
			for index, item in ipairs(items) do
				if style == "absolute" then items[index] = ("C:/executor/workspace/" .. item):gsub("/", "\\")
				elseif style == "scope" then items[index] = item:sub(#"UAI/files/" + 1)
				elseif style == "directory" then items[index] = item:sub(#dir + 2)
				elseif style == "app" then items[index] = item:sub(#"UAI/" + 1) end
			end
			return items
		end
		local listed = f.dispatch("file_list", { path = "files/files/Game (77)" })
		check(style .. " listing retains reusable paths", listed.ok and listed.data.complete)
		for _, item in ipairs(listed.data.entries) do
			check(style .. " stays inside requested folder", item.path:sub(1, #"files/files/Game (77)/") == "files/files/Game (77)/")
		end
		local found = f.dispatch("file_search", { path = "files/files/Game (77)", query = "77" })
		check(style .. " recursive search reaches exact file", found.ok and found.data.complete and found.data.matches[1].path == path)
		check(style .. " execution shares that path", f.dispatch("run_luau", { path = path }).ok)
		f.healthy(); f.close()
	end
end)

case("incomplete listings retain usable paths without guessing corrupt or ambiguous entries", function()
	local f, fs = setup()
	assert(fs.write("safe.lua", "return 1", { scope = "files" }))
	assert(fs.write("dup.lua", "outer", { scope = "files" }))
	assert(fs.write("files/dup.lua", "inner", { scope = "files" }))
	f.env.require("runtime/caps").fn.listfiles = function()
		return { "UAI/files/safe.lua", "UAI/files/safe.lua", "files/dup.lua", "bad\255name", "../config.json" }
	end
	local result = f.dispatch("file_list", {})
	check("valid entries survive with an explicit warning", result.ok and not result.data.complete and result.data.warning ~= nil)
	check("duplicates and ambiguous paths are not returned", #result.data.entries == 1 and result.data.entries[1].path == "files/safe.lua")
	check("both ambiguous files remain untouched", fs.readUser("files/dup.lua") == "outer" and fs.readUser("files/files/dup.lua") == "inner")
end)

case("leading spaces in explicit paths are significant for listing and search", function()
	local f = setup()
	assert(f.dispatch("file_write", { path = "files/ Game/main.lua", content = "return 1" }).ok)
	local listed = f.dispatch("file_list", { path = "files/ Game" })
	check("listing preserves leading space", listed.ok and listed.data.entries[1].path == "files/ Game/main.lua")
	local found = f.dispatch("file_search", { path = "files/ Game", query = "return" })
	check("search preserves leading space", found.ok and found.data.matches[1].path == "files/ Game/main.lua")
end)

case("an inaccessible saved Unicode game folder cannot keep poisoning the prompt", function()
	local f, fs = setup()
	local old = "\226\154\153\239\184\143 Harbor (77)"
	assert(fs.write(old .. "/keep.lua", "kept", { scope = "files" }))
	assert(fs.writeJson("workspace.json", { version = 1, games = { ["77"] = old } }))
	local place = f.env.require("runtime/place")
	place.id, place.name = 77, "\226\154\153\239\184\143 Harbor"
	local caps, original = f.env.require("runtime/caps"), f.env.require("runtime/caps").fn.isfolder
	caps.fn.isfolder = function(path) if path:find("[\128-\255]") then return false end; return original(path) end
	local selected = f.env.require("runtime/workspace").describe()
	check("new default is portable and stable", selected.path == "files/Harbor (77)")
	check("inaccessible original content is preserved", f.h.files["UAI/files/" .. old .. "/keep.lua"] == "kept")
	check("selected path immediately works across tools", f.dispatch("file_write", { path = selected.path .. "/main.lua", content = "return 1" }).ok)
end)

case("damaged or unsupported workspace identity files are never overwritten", function()
	for _, body in ipairs({ "{broken", '{"version":2,"games":{}}', '{"version":1,"games":"invalid"}' }) do
		local f, fs = setup()
		assert(fs.write("workspace.json", body))
		local place = f.env.require("runtime/place")
		place.id, place.name = 77, "Harbor"
		check("current work still receives a usable path", f.env.require("runtime/workspace").describe().path == "files/Harbor (77)")
		check("original identity file remains intact", fs.read("workspace.json") == body)
		f.healthy(); f.close()
	end
end)

case("recursive discovery probes an unreadable game folder only once", function()
	local f, fs = setup()
	local old = "Legacy (77)"
	for index = 1, 30 do assert(fs.write(old .. "/part" .. index .. ".lua", "kept", { scope = "files" })) end
	local caps = f.env.require("runtime/caps")
	local original, probes = caps.fn.listfiles, 0
	caps.fn.listfiles = function(path)
		if path == "UAI/files/" .. old then probes = probes + 1; error("host cannot list this folder") end
		return original(path)
	end
	local place = f.env.require("runtime/place")
	place.id, place.name = 77, "Current"
	local workspace = f.env.require("runtime/workspace")
	check("failed folder is probed once despite recursive children", workspace.describe().path == "files/Current (77)" and probes == 1)
	check("later prompt builds reuse the selected path", workspace.describe().path == "files/Current (77)" and probes == 1)
	check("old files remain intact", fs.readUser("files/" .. old .. "/part30.lua") == "kept")
	f.healthy(); f.close()
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
