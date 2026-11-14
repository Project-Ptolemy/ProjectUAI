-- Model-facing data workflows, result budgets and revision-bound full-source sharing.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("UI mods tools")
local case, check = suite.case, suite.check
local function spec(id, source)
	return { version = 1, kind = "script", id = id or "shared-workbench", name = "Shared workbench", source = source or "return function(context) return function() end end" }
end
case("data tools and the direct apply helper use ordinary permissions", function()
	local f = F.new(); local registry = f.tools({ "ui_mods" })
	for _, name in ipairs({ "ui_mod_list", "ui_mod_read", "ui_mod_export" }) do check(name .. " is read risk", registry.get(name).risk == "read" and registry.get(name).needs == nil) end
	check("apply is registered through the root helper", registry.get("ui_mod_apply") ~= nil)
	check("deletion uses high-impact permission", registry.get("ui_mod_delete").risk == "danger")
	f.env.require("runtime/config").set("permissions.mode", "readonly")
	check("readonly mode denies persistent staging", not f.dispatch("ui_mod_save", { spec = spec() }).ok)
	check("readonly listings stay available", f.dispatch("ui_mod_list", {}).ok)
	f.healthy(); f.close()
end)
case("import and export share exact source without client state or execution", function()
	local f = F.new(); f.tools({ "ui_mods" })
	local code = "-- 界\r\nreturn function(ctx) error('must not execute during sharing') end\r\n"
	local mods = f.env.require("runtime/ui_mods"); local before = #f.h.http.log
	local imported = f.dispatch("ui_mod_import", { json = assert(mods.format(spec(nil, code))) })
	check("import stages disabled", imported.ok and imported.data.active == false)
	local exported = f.dispatch("ui_mod_export", { id = imported.data.id, limit = 12000 })
	check("portable export succeeds without activation metadata", exported.ok and not exported.text:find('"active"', 1, true) and not exported.text:find('"selected"', 1, true)
		and not exported.text:find('"history"', 1, true) and not exported.text:find("UAI/ui_mods", 1, true))
	local json = assert(exported.text:match("\n(.*)")); local decoded = assert(mods.parse(json))
	check("export includes full original source", decoded.source == code)
	check("imports/exports make no HTTP", #f.h.http.log == before)
	check("import cannot overwrite an existing ID", not f.dispatch("ui_mod_import", { json = json }).ok)
	f.healthy(); f.close()
end)
case("UTF-8 source and portable JSON pages require unchanged revisions", function()
	local f = F.new(); f.tools({ "ui_mods" })
	local code = "-- " .. string.rep("界", 800) .. "\nreturn 1\n"
	local saved = f.dispatch("ui_mod_save", { spec = spec(nil, code) }); check("script saved through registry", saved.ok)
	f.env.require("runtime/config").set("agent.resultCap", 1600)
	local offset, revision, parts = 1, nil, {}
	repeat
		local page = f.dispatch("ui_mod_read", { id = saved.data.id, section = "source", offset = offset, limit = 301, revision = revision })
		check("source page stays valid UTF-8", page.ok and f.env.require("runtime/util").validUtf8(page.text))
		parts[#parts + 1] = assert(page.text:match("\n(.*)")); revision, offset = page.data.revision, page.data.nextOffset
	until not offset
	check("source pages contain every byte once", table.concat(parts) == code)
	check("unguarded continuation is refused", not f.dispatch("ui_mod_export", { id = saved.data.id, offset = 2 }).ok)
	local current = assert(f.env.require("runtime/ui_mods").read(saved.data.id)); current.spec.source = "return 2"
	assert(f.env.require("runtime/ui_mods").save(current.spec, current.revision))
	check("old source continuation is refused", not f.dispatch("ui_mod_read", { id = saved.data.id, section = "source", offset = 2, revision = revision }).ok)
	f.env.require("runtime/config").set("agent.resultCap", 950)
	local small = f.dispatch("ui_mod_read", { id = saved.data.id })
	check("minimum result budget is achievable and explicit", not small.ok and small.text:find("956", 1, true))
	f.healthy(); f.close()
end)
case("unconfirmed saves expose recovery without replacing known resident source", function()
	local f = F.new(); f.tools({ "ui_mods" })
	local saved = f.dispatch("ui_mod_save", { spec = spec(nil, "return 1") }); check("initial save succeeded", saved.ok)
	local caps = f.env.require("runtime/caps"); local baseWrite = caps.fn.writefile
	caps.fn.writefile = function(path, bytes) if path == "UAI/ui_mods/store.json" then return false end; return baseWrite(path, bytes) end
	local replacement = spec(nil, "return 2")
	local failed = f.dispatch("ui_mod_save", { spec = replacement, expected_revision = saved.data.revision })
	check("uncertain failure preserves structured identity", not failed.ok and failed.data and failed.data.uncertain and failed.data.id == saved.data.id)
	local resident = f.dispatch("ui_mod_read", { id = saved.data.id, section = "source" })
	check("resident source remains known good and uncertain", resident.ok and resident.text:find("return 1", 1, true) and resident.data.uncertain)
	caps.fn.writefile = baseWrite
	local reviewed = f.dispatch("ui_mod_read", { id = saved.data.id, refresh = true })
	check("explicit current-storage refresh resolves uncertainty", reviewed.ok and not reviewed.data.uncertain)
	f.healthy(); f.close()
end)
case("conversation tool filtering and disabled groups cannot be widened by a mod", function()
	local f = F.new(); local registry = f.tools({ "ui_mods" })
	local saved = f.dispatch("ui_mod_save", { spec = spec() }); check("record exists", saved.ok)
	local ctx = { env = f.env, session = { toolFilter = { ui_mod_list = true } }, aborted = function() return false end }
	check("unoffered reads stay excluded", not f.dispatch("ui_mod_read", { id = saved.data.id }, ctx).ok)
	registry.setGroupEnabled("ui_mods", false)
	check("group disable keeps tools unavailable", not f.dispatch("ui_mod_list", {}, ctx).ok)
	f.healthy(); f.close()
end)
suite.finish()
