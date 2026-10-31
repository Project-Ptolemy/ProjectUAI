package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Source conveniences")
local check, case = suite.check, suite.case
case("line actions preserve Unicode, CRLF and neighboring lines", function()
	local f = F.new(); local t = f.env.require("runtime/code_transform"); local text = f.env.require("runtime/code_text")
	local source = "local café = 1\r\n\tprint(café)  \r\nreturn café"
	check("clamps invalid positions", text.clamp(source, 0/0) == 1 and text.clamp(source, math.huge) == 1)
	check("go to Unicode column", text.position("éx\nnext", 1, 2) == 3 and text.position(source, 99) == nil)
	check("whole document trailing spaces", t.apply(source, "trim", 1) == "local café = 1\r\n\tprint(café)\r\nreturn café")
	local first = assert(text.position(source, 2, 1))
	local commented = assert(t.apply(source, "comment", first))
	check("comment one line with indentation", commented == "local café = 1\r\n\t-- print(café)  \r\nreturn café")
	check("comment toggles back", t.apply(commented, "comment", first) == source)
	check("duplicate final line uses CRLF", t.apply(source, "duplicate", #source) == source .. "\r\nreturn café")
	check("delete final line removes separator", t.apply(source, "delete", #source) == "local café = 1\r\n\tprint(café)  ")
	local facts = f.env.require("runtime/code_summary").describe(source, 1, #source + 1)
	check("summary distinguishes characters from bytes", facts.characters < facts.bytes and facts.lines == 3 and facts.lineEnding == "CRLF" and facts.selectionBytes == #source)
	f.healthy(); f.close()
end)
case("scaffolds are valid new files with separately testable domain code", function()
	local f = F.new(); local scaffold = f.env.require("runtime/project_scaffold")
	for _, kind in ipairs({ "basic", "interface" }) do
		local files, manifest = assert(scaffold.files("Example", kind)); local names = {}
		for _, file in ipairs(files) do
			check("new-file proposal", file.create and not file.expected_hash and not names[file.path]); names[file.path] = file.content
			if file.path:sub(-4) == ".lua" then check("starter parses under LuaJIT", loadstring(file.content) ~= nil) end
		end
		check("manifest lists the entry", names[manifest] and f.h.json.decode(names[manifest]).entry == "main")
		if kind == "interface" then
			check("view owns model cleanup", names["Example/interface.lua"]:find("window:OnDestroy(model.stop)", 1, true))
			local make = assert(loadstring(names["Example/logic.lua"]))(); local model = make()
			model.increment(); model.stop(); model.increment(); check("domain lifetime survives stopped calls", model.count == 1)
		end
	end
	check("invalid starter kinds rejected", scaffold.files("Example", "unknown") == nil)
	f.healthy(); f.close()
end)
case("unavailable file probes never authorize a new write", function()
	local f = F.new(); local fs = f.env.require("runtime/fsx"); local store = f.env.require("runtime/code_store")
	store.init(); local doc = store.active(); local files = f.env.require("runtime/code_files")
	local caps = f.env.require("runtime/caps")
	local isfile, calls = caps.fn.isfile, 0
	caps.fn.isfile = function() calls = calls + 1; if calls == 1 then return false end; error("probe unavailable") end
	local result = files.save(doc.id, "Unverified.lua")
	check("uncertain absence preserves draft and disk", not result and f.h.files["UAI/Unverified.lua"] == nil)
	caps.fn.isfile = isfile; f.healthy(); f.close()
end)
suite.finish()
