-- Declared-tool profiles and the toolbox. A profile changes declarations, not
-- dispatch scope: every hidden tool stays reachable through tool_search.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Tool profiles")
local case, check = suite.case, suite.check

local function setup()
	local f = F.new(); f.tools({})
	local registry = f.env.require("agent/registry")
	registry.loaded = false
	registry.load()
	return f, registry
end

case("lean profiles cut schema bytes and keep the toolbox", function()
	local f, registry = setup()
	local util = f.env.require("runtime/util")
	check("new installations use compact families", f.env.require("runtime/config").get("agent.toolProfile", "all") == "focused")
	local all, lean = registry.definitions({}), registry.definitions({ profile = "lean" })
	local allBytes, leanBytes = #util.encode(all), #util.encode(lean)
	check("the default catalogue is unchanged", #all > 100 and #registry.definitions({ profile = "all" }) == #all)
	check("lean declares a substantially smaller catalogue", #lean < #all / 2)
	check("lean cuts schema bytes below half", leanBytes < allBytes / 2)
	local function names(definitions)
		local out = {}
		for _, definition in ipairs(definitions) do out[definition["function"].name] = true end
		return out
	end
	local allNames, leanNames = names(all), names(lean)
	check("tool_search is always declared", leanNames.tool_search == true and allNames.tool_search == true)
	check("hidden tools are absent from lean declarations", leanNames.web_search == nil and allNames.web_search == true)
	check("core workflow tools remain declared", leanNames.file_read and leanNames.run_luau and leanNames.instance_query and leanNames.todo_write)
	f.healthy(); f.close()
end)

case("tool_search lists, describes and calls a hidden tool with the same scope", function()
	local f, registry = setup()
	local util = f.env.require("runtime/util")
	local ran = 0
	assert(registry.register({ name = "fixture_hidden", group = "fs", risk = "read",
		description = "A focused hidden fixture.",
		parameters = { type = "object", properties = { target = { type = "string", enum = { "exact" } } }, required = { "target" } },
		run = function(args) ran = ran + 1; return "hidden " .. args.target end }))
	local ctx = { session = {}, aborted = function() return false end }
	local function call(args)
		return f.run(function()
			return registry.dispatch({ id = "profile-call", name = "tool_search",
				arguments = util.encode(args) }, ctx)
		end)
	end
	local listed = call({ action = "list", query = "fixture_hidden" })
	check("hidden tools are discoverable", listed.ok and listed.text:find("fixture_hidden", 1, true) ~= nil)
	local described = call({ action = "describe", name = "fixture_hidden" })
	check("the exact schema is available", described.ok and described.text:find("exact", 1, true) ~= nil
		and described.data and described.data.tool and described.data.tool.name == "fixture_hidden")
	local called = call({ action = "call", name = "fixture_hidden", arguments = { target = "exact" } })
	check("a hidden tool runs through the toolbox", called.ok and called.text == "hidden exact" and ran == 1)
	ctx.session.toolGroups = { agentself = true }
	local blocked = call({ action = "call", name = "fixture_hidden", arguments = { target = "exact" } })
	check("conversation scope still blocks the hidden tool", not blocked.ok and ran == 1)
	ctx.session.toolGroups = nil
	registry.setGroupEnabled("fs", false)
	local disabled = call({ action = "call", name = "fixture_hidden", arguments = { target = "exact" } })
	check("a disabled group still blocks the hidden tool", not disabled.ok and ran == 1)
	registry.setGroupEnabled("fs", true)
	f.healthy(); f.close()
end)

case("a denied hidden tool is neither listed nor callable", function()
	local f, registry = setup()
	local util = f.env.require("runtime/util")
	registry.register({ name = "fixture_denied", group = "fs", risk = "write", description = "Denied fixture.",
		parameters = { type = "object", properties = {}, required = {} }, run = function() return "should not run" end })
	f.env.require("agent/permissions").setRule("fixture_denied", "deny")
	local ctx = { session = {}, aborted = function() return false end }
	local listed = f.run(function()
		return registry.dispatch({ name = "tool_search", arguments = util.encode({ action = "list", query = "fixture_denied" }) }, ctx)
	end)
	check("denied tools stay out of the toolbox listing", not listed.text:find("fixture_denied", 1, true))
	local called = f.run(function()
		return registry.dispatch({ name = "tool_search", arguments = util.encode({ action = "call", name = "fixture_denied", arguments = {} }) }, ctx)
	end)
	check("denied tools cannot be called through the toolbox", not called.ok)
	f.healthy(); f.close()
end)

suite.finish()
