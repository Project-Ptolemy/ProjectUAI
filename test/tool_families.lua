-- Compact declarations must preserve exact action validation and request scope.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Tool families")
local check, case = suite.check, suite.case
case("full catalogue fits sixteen declarations without losing actions", function()
	local f = F.new(); local registry = f.tools({}); registry.loaded = false; registry.load()
	local all, focused = registry.definitions({ profile = "all" }), registry.definitions({ profile = "focused" })
	local seen = {}
	for _, declaration in ipairs(focused) do
		local tool = declaration["function"]
		if tool.name:sub(1, 4) == "uai_" then
			check("families are non-strict dynamic calls", tool.strict == false)
			for _, name in ipairs(tool.parameters.properties.name.enum) do check("action has one owner", not seen[name]); seen[name] = true end
		else check("direct tools have one owner", not seen[tool.name]); seen[tool.name] = true end
	end
	check("compact declaration bound", #focused <= 16 and #all > 100)
	for _, declaration in ipairs(all) do check("every allowed action remains discoverable", seen[declaration["function"].name]) end
	check("schemas are substantially smaller", #f.env.require("runtime/util").encode(focused) < #f.env.require("runtime/util").encode(all) / 2)
	f.healthy(); f.close()
end)
case("family dispatch retains validation, deny rules and per-request exclusions", function()
	local f = F.new(); local registry = f.tools({}); local ran = 0
	assert(registry.register({ name = "family_fixture", group = "fs", risk = "write", description = "Fixture action",
		parameters = { type = "object", properties = { value = { type = "string", enum = { "exact" } } }, required = { "value" } },
		run = function(args) ran = ran + 1; return args.value end }))
	local ctx = { session = { id = "families" }, aborted = function() return false end, requestToolNames = { family_fixture = true } }
	local function call(args) return f.dispatch("uai_files", args, ctx) end
	check("description does not execute", call({ action = "describe", name = "family_fixture" }).ok and ran == 0)
	check("invalid arguments fail at original schema", not call({ action = "call", name = "family_fixture", arguments = { value = "wrong" } }).ok and ran == 0)
	local result = call({ action = "call", name = "family_fixture", arguments = { value = "exact" } })
	check("exact action returns its result and identity", result.ok and result.text == "exact" and result.targetName == "family_fixture" and ran == 1)
	ctx.requestToolNames = {}
	check("request exclusions block family calls", not call({ action = "call", name = "family_fixture", arguments = { value = "exact" } }).ok and ran == 1)
	ctx.requestToolNames = nil; ctx.session.toolGroups = { script = true }
	check("conversation groups block family calls", not call({ action = "list" }).ok)
	ctx.session.toolGroups = nil; f.env.require("agent/permissions").setRule("family_fixture", "deny")
	check("denied actions stay unavailable", not call({ action = "describe", name = "family_fixture" }).ok and ran == 1)
	f.healthy(); f.close()
end)
case("published help examples validate and never execute", function()
	local f = F.new(); local registry = f.tools({}); registry.loaded = false; registry.load()
	local examples = f.env.require("agent/tool_examples"); local total = 0
	-- Validate help even for a group disabled on this fixture's current host.
	for _, tool in pairs(registry.tools) do
		if tool.examples then
			local items, omitted = examples.read(tool)
			check(tool.name .. " examples conform to schema", #items > 0 and omitted == 0)
			items[1].title = "changed"; check("help snapshots are detached", tool.examples[1].title ~= "changed")
			total = total + #items
		end
	end
	check("core workflows have useful examples", total >= 25)
	f.healthy(); f.close()
end)
suite.finish()
