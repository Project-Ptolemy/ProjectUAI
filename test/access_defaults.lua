-- Access defaults and saved-policy behavior; no external tool effects.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Access defaults")
local case, check = suite.case, suite.check

case("new configurations allow all risk levels without pending approvals", function()
	local f = F.new()
	local config, permissions = f.env.require("runtime/config"), f.env.require("agent/permissions")
	config.load()
	check("new access matches the user-facing default", permissions.mode() == "full" and permissions.MODE_LABELS[permissions.mode()] == "Allow everything")
	for _, risk in ipairs({ "read", "write", "danger" }) do
		local allowed = permissions.request({ name = "fixture_" .. risk, risk = risk }, {})
		check(risk .. " does not require an approval", allowed and permissions.pendingCount() == 0)
	end
	check("prompt advertises the same active mode", f.env.require("agent/prompt").build():find("Permission mode: full", 1, true) ~= nil)
	f.healthy(); f.close()
end)

case("saved access modes and explicit rules survive reload", function()
	for _, mode in ipairs({ "readonly", "ask", "auto", "full" }) do
		local f = F.new()
		local config, permissions = f.env.require("runtime/config"), f.env.require("agent/permissions")
		permissions.setMode(mode); permissions.setRule("fixture_delete", "deny")
		assert(config.saveNow()); config.load()
		check(mode .. " remains the saved choice", permissions.mode() == mode)
		check(mode .. " keeps an explicit deny rule", permissions.check({ name = "fixture_delete", risk = "danger" }) == "deny")
		f.healthy(); f.close()
	end
end)

case("missing access receives defaults while invalid access remains guarded", function()
	local f = F.new()
	local config, permissions, fs = f.env.require("runtime/config"), f.env.require("agent/permissions"), f.env.require("runtime/fsx")
	assert(fs.writeJson("config.json", { version = 1, agent = { effort = "high" } })); config.load()
	check("older settings without access receive full access", permissions.mode() == "full" and config.get("agent.effort") == "high")
	config.set("permissions.mode", "invalid")
	check("an invalid stored value cannot grant access", permissions.check({ name = "fixture_run", risk = "danger" }) == "ask")
	config.reset("permissions")
	check("reset uses the new default", permissions.mode() == "full")
	f.healthy(); f.close()
end)

suite.finish()
