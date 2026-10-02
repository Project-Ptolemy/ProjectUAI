-- Focused native script-project workflows; no network, desktop or live game.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Script projects")
local check = suite.check
local function fixture()
	local f = F.new(); f.tools({ "coding", "script" })
	f.ctx = { env = f.env, session = {}, aborted = function() return false end }
	function f.call(name, args) return f.dispatch(name, args, f.ctx, 1) end
	function f.write(path, text) assert(f.env.require("runtime/fsx").write(path, text, { scope = "files" })) end
	function f.read(path) return f.h.files["UAI/files/" .. path] end
	function f.hash(text) return f.env.require("runtime/project_source").hash(text) end
	function f.start()
		local staged = f.call("project_scaffold", { directory = "Example" }); assert(staged.ok, staged.text)
		local applied = f.call("project_patch_apply", { patch_id = staged.data.patchId }); assert(applied.ok, applied.text)
		return staged.data.patchId
	end
	return f
end

suite.case("scaffold, map, review, apply, compile, build and test a complete project", function()
	local f = fixture()
	local staged = f.call("project_scaffold", { directory = "Example" })
	check("stage does not write", staged.ok and f.read("Example/main.lua") == nil)
	local id = staged.data.patchId
	local preview = f.call("project_patch_read", { patch_id = id, path = "Example/main.lua", section = "after" })
	check("preview contains actual source", preview.ok and preview.text:find('require("settings")', 1, true))
	check("apply creates files", f.call("project_patch_apply", { patch_id = id }).ok and f.read("Example/uai.project.json"))
	check("one-shot apply", not f.call("project_patch_apply", { patch_id = id }).ok)
	local map = f.call("project_map", { manifest = "files/Example/uai.project.json" })
	check("map has hashes and imports", map.ok and #map.data.items == 3 and map.data.items[1].hash and #map.data.items[1].imports == 1)
	local analyzed = f.call("script_analyze", { manifest = "Example/uai.project.json" })
	check("analysis reports real coverage", analyzed.ok and analyzed.data.errors == 0 and analyzed.data.compilerAvailable and analyzed.data.typeChecked == false)
	local built = f.call("project_build", { manifest = "Example/uai.project.json", output = "Example/dist.lua" })
	check("build exports source and locations", built.ok and f.read("Example/dist.lua") and #built.data.locations == 3)
	local fn = assert(f.h.sandbox.loadstring(f.read("Example/dist.lua")))
	local value = fn()
	check("export runs independently", value.name == "My script" and value.enabled == true)
	local tested = f.call("script_test", { manifest = "Example/uai.project.json" })
	check("behavioral tests run", tested.ok and tested.data.passed == 1 and tested.data.failed == 0 and tested.data.sourcesCurrent)
	local reb = f.call("project_build", { manifest = "Example/uai.project.json", output = "Example/dist.lua", expected_hash = built.data.hash })
	check("build is deterministic", reb.ok and reb.data.hash == built.data.hash)
	f.healthy(); f.close()
end)

suite.case("multi-file exact patches preserve bytes and support conditional restore", function()
	local f = fixture(); f.write("a.lua", "return 1\n"); f.write("b.lua", "return 2\n")
	local staged = f.call("project_patch", { operations = {
		{ path = "a.lua", expected_hash = f.hash("return 1\n"), edits = { { old_text = "1", new_text = "3" } } },
		{ path = "b.lua", expected_hash = f.hash("return 2\n"), content = "return 4\n" },
		{ path = "empty.lua", create = true, content = "" },
	} })
	check("stage keeps originals", staged.ok and f.read("a.lua") == "return 1\n")
	local id = staged.data.patchId
	local diff = f.call("project_patch_read", { patch_id = id, path = "a.lua", section = "diff" })
	check("diff describes source changes", diff.ok and diff.data.added == 1 and diff.data.removed == 1)
	check("apply changes all three", f.call("project_patch_apply", { patch_id = id }).ok and f.read("a.lua") == "return 3\n" and f.read("b.lua") == "return 4\n" and f.read("empty.lua") == "")
	check("restore recovers originals and removes created file", f.call("project_patch_restore", { patch_id = id }).ok and f.read("a.lua") == "return 1\n" and f.read("b.lua") == "return 2\n" and f.read("empty.lua") == nil)
	f.healthy(); f.close()
end)

suite.case("stale and ambiguous changes cause zero writes", function()
	local f = fixture(); f.write("a.lua", "return 1"); f.write("b.lua", "return 2")
	local staged = f.call("project_patch", { operations = {
		{ path = "a.lua", expected_hash = f.hash("return 1"), content = "return 3" },
		{ path = "b.lua", expected_hash = f.hash("return 2"), content = "return 4" },
	} })
	check("proposal staged", staged.ok)
	f.write("b.lua", "external")
	check("preflight checks all files", not f.call("project_patch_apply", { patch_id = staged.data.patchId }).ok and f.read("a.lua") == "return 1" and f.read("b.lua") == "external")
	f.write("repeat.lua", "x x")
	check("ambiguous edit refused", not f.call("project_patch", { operations = { { path = "repeat.lua", expected_hash = f.hash("x x"), edits = { { old_text = "x", new_text = "y" } } } } }).ok)
	check("stale replacement hash refused", not f.call("project_patch", { operations = { { path = "a.lua", expected_hash = "wrong", content = "lost" } } }).ok)
	f.close()
end)

suite.case("proposals are conversation-owned and expire", function()
	local f = fixture()
	local staged = f.call("project_scaffold", { directory = "Example" }); local id = staged.data.patchId
	local other = f.dispatch("project_patch_read", { patch_id = id }, { session = {}, aborted = function() return false end })
	check("another conversation cannot inspect", not other.ok)
	local item = assert(f.env.require("runtime/project_patch").get(id, f.ctx)); item.expires = -1
	check("expired proposal cannot apply", not f.call("project_patch_apply", { patch_id = id }).ok and f.read("Example/main.lua") == nil)
	f.close()
end)

suite.case("permission revocation and cancellation block mutations", function()
	local f = fixture(); local staged = f.call("project_scaffold", { directory = "Example" })
	local registry = f.registry; registry.setGroupEnabled("coding", false)
	check("disabled coding group blocks apply", not f.call("project_patch_apply", { patch_id = staged.data.patchId }).ok and f.read("Example/main.lua") == nil)
	registry.setGroupEnabled("coding", true)
	f.ctx.aborted = function() return true end
	check("cancelled call writes nothing", not f.call("project_patch_apply", { patch_id = staged.data.patchId }).ok and f.read("Example/main.lua") == nil)
	f.close()
end)

suite.case("partial host failure retains recovery source without claiming atomicity", function()
	local f = fixture(); f.write("a.lua", "a"); f.write("b.lua", "b")
	local staged = f.call("project_patch", { operations = {
		{ path = "a.lua", expected_hash = f.hash("a"), content = "new-a" },
		{ path = "b.lua", expected_hash = f.hash("b"), content = "new-b" },
	} })
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	caps.fn.writefile = function(path, content) if path == "UAI/files/b.lua" then return false end; return write(path, content) end
	local applied = f.call("project_patch_apply", { patch_id = staged.data.patchId })
	check("partial failure is explicit", not applied.ok and applied.data.status == "partial" and applied.data.atomic == false and f.read("a.lua") == "new-a" and f.read("b.lua") == "b")
	caps.fn.writefile = write
	check("untouched plus applied versions can restore", f.call("project_patch_restore", { patch_id = staged.data.patchId }).ok and f.read("a.lua") == "a" and f.read("b.lua") == "b")
	f.close()
end)

suite.case("read-back mismatch and external edits never get blindly restored", function()
	local f = fixture(); f.write("a.lua", "original")
	local staged = f.call("project_patch", { operations = { { path = "a.lua", expected_hash = f.hash("original"), content = "replacement" } } })
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	caps.fn.writefile = function(path) return write(path, "partial") end
	local applied = f.call("project_patch_apply", { patch_id = staged.data.patchId })
	check("unverified bytes fail", not applied.ok and applied.data.status == "partial" and f.read("a.lua") == "partial")
	caps.fn.writefile = write
	check("unknown partial bytes prevent restore", not f.call("project_patch_restore", { patch_id = staged.data.patchId }).ok and f.read("a.lua") == "partial")
	local original = f.call("project_patch_read", { patch_id = staged.data.patchId, path = "a.lua", section = "before" })
	check("original bytes remain inspectable", original.ok and original.text:find("original", 1, true))
	f.close()
end)

suite.case("patches cannot clobber unsaved editor documents", function()
	local f = fixture(); f.write("a.lua", "return 1")
	local store, files = f.env.require("runtime/code_store"), f.env.require("runtime/code_files")
	local doc = assert(store.create("a.lua", "return 9", {}))
	files.bindings[doc.id] = { path = "files/a.lua", base = "return 1" }
	local staged = f.call("project_patch", { operations = { { path = "a.lua", expected_hash = f.hash("return 1"), content = "return 2" } } })
	check("dirty draft blocks apply", not f.call("project_patch_apply", { patch_id = staged.data.patchId }).ok and f.read("a.lua") == "return 1" and doc.source == "return 9")
	f.close()
end)

suite.case("path traversal, aliases, directories and oversized sources are rejected", function()
	local f = fixture()
	for _, path in ipairs({ "../config.json", "pastes/a.lua", "C:/a.lua", "x/../a.lua", "NUL.lua" }) do
		check("invalid path rejected " .. path, not f.call("project_patch", { operations = { { path = path, create = true, content = "" } } }).ok)
	end
	check("case alias rejected", not f.call("project_patch", { operations = { { path = "a.lua", create = true, content = "" }, { path = "A.lua", create = true, content = "" } } }).ok)
	check("parent/child destinations rejected", not f.call("project_patch", { operations = { { path = "a", create = true, content = "" }, { path = "a/b.lua", create = true, content = "" } } }).ok)
	check("oversized source rejected", not f.call("project_patch", { operations = { { path = "a.lua", create = true, content = string.rep("x", 256001) } } }).ok)
	check("binary source rejected", not f.call("project_patch", { operations = { { path = "a.lua", create = true, content = "a\0b" } } }).ok)
	f.close()
end)

suite.case("lexical maps skip strings/comments and retain source locations", function()
	local f = fixture()
	local scan = f.run(function() return f.env.require("runtime/project_source").scan('-- require("fake")\nlocal text = [[require("fake2")]]\nlocal settings = require("settings")\nfunction M.run() return text end\n', f.ctx) end)
	check("only real literal require is listed", #scan.imports == 1 and scan.imports[1].id == "settings" and scan.imports[1].line == 3)
	check("qualified function and locals are outlined", scan.symbols[#scan.symbols].name == "M.run" and scan.symbols[#scan.symbols].line == 4)
	f.close()
end)

suite.case("analysis reports syntax, missing imports and cycles without executing", function()
	local f = fixture(); f.start()
	f.write("Example/main.lua", '_G.projectWasExecuted = true\nlocal missing = require("missing")\nreturn missing')
	local missing = f.call("script_analyze", { manifest = "Example/uai.project.json" })
	check("missing dependency diagnosed without effects", not missing.ok and missing.data.diagnostics[1].code == "missing_module" and not f.h.sandbox._G.projectWasExecuted)
	check("bad project does not build", not f.call("project_build", { manifest = "Example/uai.project.json", output = "out.lua" }).ok and f.read("out.lua") == nil)
	f.write("Example/main.lua", 'return require("settings")'); f.write("Example/settings.lua", 'return require("main")')
	local cycle = f.call("script_analyze", { manifest = "Example/uai.project.json" })
	check("cycle diagnosed", not cycle.ok and cycle.data.errors > 0)
	f.write("broken.lua", "local =")
	local broken = f.call("script_analyze", { path = "broken.lua" })
	check("compiler reports source syntax", not broken.ok and broken.data.diagnostics[1].code == "syntax" and broken.data.hash)
	f.close()
end)

suite.case("compiler absence is explicit and build cannot overwrite inputs", function()
	local f = fixture(); f.start()
	check("source output rejected", not f.call("project_build", { manifest = "Example/uai.project.json", output = "Example/main.lua" }).ok)
	local caps = f.env.require("runtime/caps"); caps.fn.loadstring = nil
	local analyzed = f.call("script_analyze", { path = "Example/main.lua" })
	check("analysis does not claim type/compiler success", analyzed.data.compilerAvailable == false and analyzed.data.typeChecked == false)
	check("build fails without compiler", not f.call("project_build", { manifest = "Example/uai.project.json", output = "Example/out.lua" }).ok and f.read("Example/out.lua") == nil)
	f.close()
end)

suite.case("tests return failures, fixtures and fresh module state", function()
	local f = fixture(); f.start()
	f.write("Example/settings.lua", "return { count = 0 }")
	f.write("Example/tests/settings.lua", [[local settings = require("settings")
return {
	a = function(t, fixtures) settings.count = 1; fixtures.number = 9; t.truthy(true) end,
	b = function(t, fixtures) t.equal(settings.count, 0); t.equal(fixtures.number, 4); t.raises(function() error("expected") end, "expected") end,
	c = function(t) t.equal(1, 2, "deliberate failure") end,
}
]])
	local tested = f.call("script_test", { manifest = "Example/uai.project.json", fixtures = { number = 4 } })
	check("fresh caches/fixtures and failed assertions", not tested.ok and tested.data.passed == 2 and tested.data.failed == 1)
	check("failure has named case and error", tested.data.cases[3].name == "c" and tested.data.cases[3].error:find("deliberate failure", 1, true))
	f.healthy(); f.close()
end)

suite.case("test preparation binds source across approval", function()
	local f = fixture(); f.start()
	local tool = f.registry.get("script_test")
	local prepared = f.run(function() return tool.prepare({ manifest = "Example/uai.project.json" }, f.ctx) end)
	f.write("Example/main.lua", "error('changed after approval')")
	local result = f.run(function() return tool.run({ manifest = "Example/uai.project.json" }, f.ctx, prepared) end)
	check("changed approved source is not run", not result.ok and result.text:find("changed", 1, true))
	f.close()
end)

suite.case("main and subagent prompts explain the project workflow and limits", function()
	local f = fixture(); local prompt = f.env.require("agent/prompt")
	for _, text in ipairs({ prompt.build(), prompt.subagent("Build a script") }) do
		check("project workflow is present", text:find("project_scaffold", 1, true) and text:find("project_patch_read", 1, true) and text:find("script_test", 1, true))
		check("review and coverage limits are present", text:find("Review source changes before checks", 1, true) and text:find("not Luau type inference", 1, true) and text:find("shared native game state", 1, true))
	end
	f.close()
end)

suite.finish()
