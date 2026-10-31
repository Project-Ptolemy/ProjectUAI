-- Search ranking and shortcut admission without native UI dependencies.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Command catalog")
local check, case = suite.check, suite.case

case("commands combine keywords, rank exact matches and keep stable ties", function()
	local f = F.new()
	local catalog = f.env.require("runtime/command_catalog")
	local entries = { { id = "one", label = "Vault", detail = "local notes" },
		{ id = "two", label = "Vault", detail = "local notes" } }
	local result, total = catalog.find("vault", entries)
	check("exact labels rank first", result[1].id == "one" and result[2].id == "two" and total == 2)
	result = catalog.find("notes local", entries)
	check("word order is independent", #result == 2)
	check("unmatched queries have no results", #catalog.find("nonexistent destination", entries) == 0)
	check("empty query lists the catalog", #catalog.find("") == #catalog.items)
	result, total = catalog.find("", entries, 1)
	check("limit does not hide total count", #result == 1 and total == #catalog.items + 2)
	check("invalid limits are bounded", #catalog.find("", entries, 0/0) == total)
	f.healthy(); f.close()
end)

case("shortcuts respect focus, modifier collisions and application lifetime", function()
	local f = F.new()
	local shortcuts = f.env.require("runtime/shortcuts")
	check("command shortcut", shortcuts.resolve("K", { control = true }) == "commands")
	check("search shortcut", shortcuts.resolve("P", { control = true, shift = true }) == "search")
	check("focus shortcut", shortcuts.resolve("L", { control = true }) == "focus")
	check("settings shortcut", shortcuts.resolve("Comma", { control = true }) == "settings")
	for _, state in ipairs({ { focused = true }, { overlay = true }, { processed = true }, { gated = true }, { disposed = true } }) do
		check("blocked context retains its input", shortcuts.resolve("K", { control = true }, state) == nil)
	end
	for _, modifiers in ipairs({ {}, { shift = true }, { control = true, alt = true }, { control = true, shift = true } }) do
		check("extra or missing modifiers do not trigger commands", shortcuts.resolve("K", modifiers) == nil)
	end
	f.healthy(); f.close()
end)

suite.finish()
