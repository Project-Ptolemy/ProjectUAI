-- Native settings retain stable control identities and own async lifecycle.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Obsidian settings")
local check, case = suite.check, suite.case
case("native settings discover vaults and update read-only policy", function()
	local f = F.ui(900, 750)
	local current = { id = "fixture", name = "Notes", readOnly = true, available = true, obsidian = true }
	f.loaded["net/bridge"] = { status = function() return { online = true } end }
	f.loaded["net/obsidian"] = {
		list = function() return { vaults = { current } } end,
		configure = function(input) check("only vault policy changes", input.action == "policy" and input.id == "fixture"); current.readOnly = input.readOnly; return { vaults = { current } } end,
	}
	f.env.require("ui/obsidian").build(f.host); f.h.settle(0.2)
	check("native panel shows configured vault", f.h.textOf(f.host):find("Notes", 1, true) ~= nil)
	f.h.click(assert(f.h.byName("ObsidianPolicy_fixture"))); f.h.settle(0.2)
	check("explicit action enables editing", current.readOnly == false)
	check("disconnect remains available", f.h.byName("ObsidianDisconnect_fixture") ~= nil)
	f.healthy(); f.close()
end)
case("destroyed settings do not paint late network results", function()
	local f = F.ui(900, 750)
	f.loaded["net/bridge"] = { status = function() return { online = true } end }
	f.loaded["net/obsidian"] = { list = function(options) f.h.sched.wait(0.2); check("request observes destruction", options.aborted()); return { vaults = {} } end }
	f.env.require("ui/obsidian").build(f.host); f.h.settle(0.05); f.host:Destroy(); f.h.settle(0.4)
	f.healthy(); f.close()
end)
suite.finish()
