-- Model-facing knowledge tools preserve permission scope, cursors and mutation evidence.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Master Vault tools")
local check, case = suite.check, suite.case
local function document(content)
	return { title = "Tool fixture", kind = "recipe", scope = "global", status = "draft", content = content or "Observed tool result",
		tags = { "fixture" }, sources = { { label = "External test fixture" } } }
end
case("read tools remain available without executor filesystem writes", function()
	local f = F.new(); local registry = f.tools({ "master_vault" })
	local reads = { vault_list = true, vault_read = true, vault_export = true }
	for name in pairs(reads) do check(name .. " has read risk and no host needs", registry.get(name).risk == "read" and registry.get(name).needs == nil) end
	check("deletion carries the existing high-impact file risk", registry.get("vault_delete").risk == "danger")
	f.env.require("runtime/fsx").enabled = false
	local caps = f.env.require("runtime/caps"); caps.fs, caps.available.fs = false, false
	local listed = f.dispatch("vault_list", { origin = "starters", limit = 2 })
	check("bundled entries still dispatch", listed.ok and listed.data.count > 0)
	check("filesystem capability blocks writes", not f.dispatch("vault_save", { document = document() }).ok)
	check("bundled note is readable", f.dispatch("vault_read", { id = listed.data.items[1].id }).ok)
	f.healthy(); f.close()
end)
case("listing budgets retain usable IDs and continuation cursors", function()
	local f = F.new(); f.tools({ "master_vault" })
	f.env.require("runtime/config").set("agent.resultCap", 1800)
	local seen, offset, count = {}, 1, 0
	repeat
		local listed = f.dispatch("vault_list", { origin = "starters", limit = 50, offset = offset })
		check("budgeted page succeeds", listed.ok and listed.data.count >= 1)
		for _, row in ipairs(listed.data.items) do check("ID is complete and unique", row.id:find("starter:", 1, true) == 1 and not seen[row.id]); seen[row.id] = true; count = count + 1 end
		offset = listed.data.nextOffset
	until not offset
	check("all bundled entries can be discovered", count == f.env.require("runtime/master_vault").stats().starters)
	f.healthy(); f.close()
end)
case("small result budgets report an achievable read and export minimum", function()
	local f = F.new(); f.tools({ "master_vault" })
	f.env.require("runtime/config").set("agent.resultCap", 950)
	local read = f.dispatch("vault_read", { id = "starter:project-knowledge" })
	local exported = f.dispatch("vault_export", { id = "starter:project-knowledge" })
	check("read failure names the true minimum", not read.ok and read.text:find("956", 1, true))
	check("export failure names the true minimum", not exported.ok and exported.text:find("956", 1, true))
	f.env.require("runtime/config").set("agent.resultCap", 956)
	check("the advertised minimum permits a useful page", f.dispatch("vault_read", { id = "starter:project-knowledge" }).ok)
	f.healthy(); f.close()
end)
case("body and metadata pages bind one source revision", function()
	local f = F.new(); f.tools({ "master_vault" })
	local body = string.rep("界", 900) .. "\nlast-line"
	local saved = f.dispatch("vault_save", { document = document(body) })
	check("note saved through registry", saved.ok and saved.data.id)
	local tool = f.registry.get("vault_read")
	f.env.require("runtime/config").set("agent.resultCap", 1600)
	local offset, revision, parts = 1, nil, {}
	repeat
		local page = f.run(function() return tool.run({ id = saved.data.id, offset = offset, revision = revision, limit = 301 }) end)
		check("UTF-8 page remains valid", page.ok ~= false and f.env.require("runtime/util").validUtf8(page.text))
		parts[#parts + 1] = assert(page.text:match("\n(.*)"))
		revision, offset = page.data.revision, page.data.nextOffset
	until not offset
	check("body pages contain every byte once", table.concat(parts) == body)
	check("unguarded continuation is rejected", not f.dispatch("vault_read", { id = saved.data.id, offset = 2 }).ok)
	local metadata = f.dispatch("vault_read", { id = saved.data.id, section = "metadata", limit = 1000 })
	check("source references have a separate readable page", metadata.ok and metadata.text:find("External test fixture", 1, true))
	local current = assert(f.env.require("runtime/master_vault").read(saved.data.id)); current.content = "new"
	assert(f.env.require("runtime/master_vault").save(current, current.revision))
	check("stale read continuation is refused", not f.dispatch("vault_read", { id = saved.data.id, offset = 2, revision = revision }).ok)
	f.healthy(); f.close()
end)
case("Markdown import and export are data operations with no execution", function()
	local f = F.new(); f.tools({ "master_vault" })
	local before, body = #f.h.http.log, "# Imported source\n```lua\nerror('must not execute')\n```\n"
	local imported = f.dispatch("vault_import", { markdown = body, scope = "game", place_id = 123 })
	check("import saves a scoped note", imported.ok and imported.data.scope == "game" and imported.data.placeId == 123)
	local exported = f.dispatch("vault_export", { id = imported.data.id, limit = 12000 })
	check("export carries portable metadata and body", exported.ok and exported.text:find("uai_vault: 1", 1, true) and exported.text:find("must not execute", 1, true))
	check("data operations made no HTTP requests", #f.h.http.log == before)
	check("stale writes fail", not f.dispatch("vault_save", { document = { id = imported.data.id, title = "Replacement", kind = "recipe", scope = "global", status = "draft", content = "new" }, expected_revision = "wrong" }).ok)
	check("unattributed verified status is refused", not f.dispatch("vault_save", { document = { title = "Claim", kind = "recipe", scope = "global", status = "verified", content = "claim" } }).ok)
	f.healthy(); f.close()
end)
case("colliding hashes cannot mix two source versions in a paged read", function()
	local f = F.new(); f.env.require("runtime/vault_document").revision = function() return "collision" end
	f.tools({ "master_vault" })
	local saved = f.dispatch("vault_save", { document = document("original source text") })
	local first = f.dispatch("vault_read", { id = saved.data.id, limit = 4 })
	check("first page provides a continuation token", first.ok and first.data.nextOffset and first.data.revision)
	local path = "UAI/vault/notes/" .. saved.data.id:sub(6) .. ".md"
	f.h.files[path] = f.h.files[path]:gsub("original source text", "replaced source text")
	local second = f.dispatch("vault_read", { id = saved.data.id, limit = 4 })
	check("a second reader gets a new token despite the collision", second.ok and second.data.revision ~= first.data.revision)
	local stale = f.dispatch("vault_read", { id = saved.data.id, offset = first.data.nextOffset, limit = 4, revision = first.data.revision })
	check("old continuation cannot append changed bytes", not stale.ok)
	local current = f.dispatch("vault_read", { id = saved.data.id, offset = second.data.nextOffset, limit = 4, revision = second.data.revision })
	check("unchanged current continuation still works", current.ok)
	f.healthy(); f.close()
end)
case("permission and conversation scope cannot be widened by vault discovery", function()
	local f = F.new(); local registry = f.tools({ "master_vault" })
	f.env.require("runtime/config").set("permissions.mode", "readonly")
	check("ordinary read-only mode denies saving", not f.dispatch("vault_save", { document = document() }).ok)
	check("read-only discovery continues", f.dispatch("vault_list", { origin = "starters" }).ok)
	local ctx = { env = f.env, session = { toolFilter = { vault_list = true } }, aborted = function() return false end }
	check("unoffered note reads stay excluded", not f.dispatch("vault_read", { id = "starter:project-knowledge" }, ctx).ok)
	registry.setGroupEnabled("master_vault", false)
	check("disabled group stays absent", not f.dispatch("vault_list", {}, ctx).ok)
	f.healthy(); f.close()
end)
case("unconfirmed writes preserve structured recovery IDs", function()
	local f = F.new(); f.tools({ "master_vault" })
	local caps = f.env.require("runtime/caps"); caps.fn.writefile = function() return true end
	local saved = f.dispatch("vault_save", { document = document() })
	check("registry retains failed-create recovery identity", not saved.ok and saved.data and saved.data.uncertain and saved.data.id:find("note:", 1, true) == 1)
	local reread = f.dispatch("vault_read", { id = saved.data.id })
	check("confirmed absence remains structured", not reread.ok and reread.data and reread.data.missing)
	f.healthy(); f.close()
end)
suite.finish()
