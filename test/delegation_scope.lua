-- Real child dispatch and follow-up cannot enlarge caller tool authorization.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Delegation scope")
local check, case = suite.check, suite.case
case("full-preset children retain parent exclusions and request-local scope", function()
	local f = F.new(); local registry = f.tools({ "fs" })
	local sessions, agents = f.env.require("agent/session"), f.env.require("agent/subagent")
	local parent = assert(sessions.newThread({ id = "scoped-parent", toolGroups = { fs = true },
		toolFilter = { file_read = true, file_list = true, file_write = true }, toolExclude = { file_write = true } }))
	assert(f.env.require("runtime/fsx").write("scope.txt", "Readable content", { scope = "files" }))
	local runs = 0
	f.env.require("agent/loop").run = function(child)
		runs = runs + 1
		local context = child.toolContext()
		local read = registry.dispatch({ id = "read", name = "file_read", arguments = f.h.json.encode({ path = "scope.txt" }) }, context)
		local write = registry.dispatch({ id = "write", name = "file_write", arguments = f.h.json.encode({ path = "scope.txt", content = "Replaced" }) }, context)
		local list = registry.dispatch({ id = "list", name = "file_list", arguments = "{}" }, context)
		check("allowed read works on run " .. runs, read.ok and read.text:find("Readable content", 1, true) ~= nil)
		check("parent write exclusion survives run " .. runs, not write.ok)
		check("request-local list exclusion survives run " .. runs, not list.ok)
		return "Inspected allowed file"
	end
	assert(f.run(function() return agents.dispatch({ parent = parent, task = "Inspect file", preset = "full",
		requestToolNames = { file_read = true, file_write = true } }) end))
	local record = assert(agents.records[1])
	parent.toolExclude = nil
	assert(f.run(function() return agents.followUp({ id = record.id, parent = parent, task = "Inspect again",
		requestToolNames = { file_read = true, file_write = true, file_list = true } }) end))
	check("follow-up keeps prior narrower scope", runs == 2)
	check("rejected writes leave the file intact", f.env.require("runtime/fsx").readUser("scope.txt") == "Readable content")
	f.healthy(); f.close()
end)
suite.finish()
