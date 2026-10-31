-- Pure note paths and result continuation cannot skip hidden or truncated data.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Obsidian runtime")
local check, case = suite.check, suite.case
case("note path validation matches bridge boundaries", function()
	local f = F.new(); local vault = f.env.require("runtime/obsidian")
	for _, path in ipairs({ "../secret.md", "C:/secret.md", "a\\b.md", "a//b.md", ".obsidian/config.md", "COM1.md", "aux/note.md", "a/../b.md", "not.txt" }) do check(path .. " rejected", vault.path(path) == nil) end
	check("Unicode note paths preserved", vault.path("Folder/界.md") == "Folder/界.md")
	check("empty root folder accepted", vault.path("", true) == "")
	check("invalid UTF-8 cannot be silently repaired into a different path", vault.path(string.char(255) .. ".md") == nil)
	f.close()
end)
case("budgeted listings continue at the first omitted row without duplicate structured content", function()
	local f = F.new(); local vault = f.env.require("runtime/obsidian")
	local entries = {}; for index = 1, 15 do entries[index] = { path = string.rep("n", 50) .. index .. ".md" } end
	local page = assert(vault.page({ data = entries, offset = 20, total = 100, nextOffset = 35, incomplete = true }, 600))
	check("text fits configured budget", #page.text < 600)
	check("continuation preserves unprinted rows", page.data.nextOffset == 20 + page.data.count and page.data.count < #entries)
	check("structured data does not duplicate rows", page.data.items == nil)
	check("coverage limitations retained", page.data.incomplete)
	check("too-small budget refuses before issuing unusable offsets", vault.page({ data = entries }, 100) == nil)
	f.close()
end)
suite.finish()
