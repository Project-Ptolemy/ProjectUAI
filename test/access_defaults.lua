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

local function toolFixture(risk)
	local f = F.new(); f.tools({})
	local calls = 0
	f.registry.register({ name = "fixture_action", risk = risk or "danger", group = "fixture", description = "Fixture action",
		parameters = { type = "object", properties = {} }, run = function() calls = calls + 1; return "changed" end })
	return f, f.env.require("agent/permissions"), function() return calls end
end

case("risk labels do not block full-mode calls or add approvals", function()
	for _, risk in ipairs({ "read", "write", "danger" }) do
		local f, permissions, calls = toolFixture(risk)
		local result = f.dispatch("fixture_action", {}, { session = {}, emit = function() error("unexpected approval") end })
		check(risk .. " executes once under full mode", result.ok and calls() == 1 and permissions.pendingCount() == 0)
		f.healthy(); f.close()
	end
end)

case("catalogue and dispatch honor explicit rules over read-only defaults", function()
	local f, permissions, calls = toolFixture()
	permissions.setMode("readonly")
	check("default read-only decision omits the action", #f.registry.definitions() == 0)
	permissions.setRule("fixture_*", "allow")
	check("an explicit allow is offered and executable", #f.registry.definitions() == 1 and f.dispatch("fixture_action").ok and calls() == 1)
	permissions.setRule("fixture_action", "deny")
	check("exact deny still overrides a broader allow", #f.registry.definitions() == 0 and not f.dispatch("fixture_action").ok and calls() == 1)
	permissions.setRule("fixture_action", "ask")
	local asks = 0
	local result = f.dispatch("fixture_action", {}, { session = {}, emit = function(kind, event)
		if kind == "permission:ask" then asks = asks + 1; event.resolve(true, false) end
	end })
	check("an explicit ask is visible and asks exactly once", #f.registry.definitions() == 1 and result.ok and asks == 1 and calls() == 2)
	check("session exclusions still win over an allow rule", #f.registry.definitions({ exclude = { fixture_action = true } }) == 0)
	local excluded = f.dispatch("fixture_action", {}, { session = { toolExclude = { fixture_action = true } } })
	check("excluded calls cannot execute", not excluded.ok and calls() == 2)
	f.healthy(); f.close()
end)

case("mode and rule refusals identify the actual policy without inventing an answer", function()
	for _, source in ipairs({ "mode", "rule" }) do
		local f, permissions, calls = toolFixture()
		if source == "mode" then permissions.setMode("readonly") else permissions.setRule("fixture_action", "deny") end
		local result = f.dispatch("fixture_action")
		check(source .. " is reported without pretending approval was pending", not result.ok and result.denied
			and result.data.permission == source and result.data.executed == false and calls() == 0
			and not result.text:find("user did not approve", 1, true) and not result.text:find("changed", 1, true))
		check("a refusal does not require a redundant user question", result.text:find("Continue other allowed work", 1, true)
			and not result.text:find("ask what to do", 1, true))
		f.healthy(); f.close()
	end
end)

case("explicit user declines remain declines including remembered decisions", function()
	for _, remember in ipairs({ false, true }) do
		local f, permissions, calls = toolFixture()
		permissions.setMode("ask")
		local result = f.dispatch("fixture_action", {}, { session = {}, emit = function(kind, event)
			if kind == "permission:ask" then event.resolve(false, remember) end
		end })
		check("the actual user denial is preserved", not result.ok and result.denied and calls() == 0
			and result.text:find("user did not approve", 1, true) and result.data.permission == (remember and "remembered" or "asked"))
		check("only an explicitly remembered decision persists", permissions.ruleFor("fixture_action") == (remember and "deny" or nil))
		f.healthy(); f.close()
	end
end)

case("approval expiry and cleanup are not user denials and late answers cannot revive them", function()
	for _, expired in ipairs({ true, false }) do
		local f, permissions, calls = toolFixture()
		permissions.setMode("ask")
		local owner, captured, result = {}, nil, nil
		f.h.sched.spawn(function()
			result = f.registry.dispatch({ id = "pending", name = "fixture_action", arguments = "{}" }, {
				session = owner, emit = function(kind, event) if kind == "permission:ask" then captured = event end end,
			})
		end)
		check("the fixture is awaiting a real approval", captured ~= nil and permissions.pendingCount(owner) == 1 and result == nil)
		if expired then f.h.sched.advance(181) else permissions.denyAll("turn ended", owner); f.h.sched.advance(0.2) end
		check("a missing decision is labelled accurately", result and not result.ok and not result.denied and calls() == 0
			and result.error == (expired and "approval timeout" or "approval cancelled")
			and result.data.permission == (expired and "timeout" or "cancelled") and not result.text:find("user did not approve", 1, true))
		captured.resolve(true, true)
		check("late answers cannot execute or save a rule", permissions.pendingCount() == 0 and permissions.ruleFor("fixture_action") == nil and calls() == 0)
		f.healthy(); f.close()
	end
end)

case("revoked permissions after approval still prevent execution", function()
	local f, permissions, calls = toolFixture()
	permissions.setMode("ask")
	local result = f.dispatch("fixture_action", {}, { session = {}, emit = function(kind, event)
		if kind == "permission:ask" then event.resolve(true, false); permissions.setRule("fixture_action", "deny") end
	end })
	check("a changed policy is rechecked before running", not result.ok and result.error == "unavailable" and calls() == 0)
	f.healthy(); f.close()
end)

suite.finish()
