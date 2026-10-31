-- Registry permissions and tool budgets also apply to local vault notes.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Obsidian tools")
local check, case = suite.check, suite.case
case("read and write tools use separate permission risks and no connection-mutating tools", function()
	local f = F.new(); local calls = 0
	f.loaded["net/obsidian"] = { request = function(input)
		calls = calls + 1
		if input.action == "vaults" then return { vaults = { { id = "notes", name = "Notes", readOnly = true } } } end
		return { path = input.path, bytes = 4, offset = 1, eof = true, revision = string.rep("a", 64), content = "note" }
	end }
	f.tools({ "obsidian" })
	check("read tools classified", f.registry.tools.obsidian_read.risk == "read")
	check("write tools classified", f.registry.tools.obsidian_update.risk == "write")
	check("agent cannot connect arbitrary folders", f.registry.tools.obsidian_configure == nil)
	check("vault ids reach tools", f.dispatch("obsidian_vaults", {}).ok)
	check("valid note read works", f.dispatch("obsidian_read", { vault = "notes", path = "Note.md" }).ok)
	local before = calls; check("invalid paths rejected", not f.dispatch("obsidian_read", { vault = "notes", path = "../Secret.md" }).ok)
	check("invalid paths never leave the client", calls == before)
	f.env.require("runtime/config").set("permissions.mode", "readonly")
	check("read-only mode denies writes", not f.dispatch("obsidian_create", { vault = "notes", path = "New.md", content = "new" }).ok)
	check("denied writes do not dispatch", calls == before); f.healthy(); f.close()
end)
case("small read budgets refuse before fetching a page that would lose its cursor", function()
	local f = F.new(); local calls = 0
	f.loaded["net/obsidian"] = { request = function() calls = calls + 1; return {} end }
	f.tools({ "obsidian" }); f.env.require("runtime/config").set("agent.resultCap", 100)
	check("small budget refused", not f.dispatch("obsidian_read", { vault = "notes", path = "Note.md" }).ok)
	check("no pointless page fetch", calls == 0); f.close()
end)
suite.finish()
