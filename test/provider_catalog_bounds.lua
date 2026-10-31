-- Remote catalogs are bounded and malformed entries cannot become selections.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider catalog boundaries")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new(); f.models = f.env.require("provider/models")
	f.record = f.env.require("provider/registry").blank("ollama")
	f.record.model, f.record.models = "saved", { "saved" }
	f.rows = {}
	f.h.http.handler = function() return { StatusCode = 200, Body = f.h.json.encode({ data = f.rows }) } end
	function f.fetch() return f.run(function() return f.models.discover(f.record, { force = true }) end) end
	return f
end

case("catalogs reject control characters and bound model-ID length", function()
	local f = fixture()
	f.rows = { { id = "valid/model" }, { id = "broken\nmodel" }, { id = string.rep("x", 161) }, { id = "valid/model" }, { id = "line\226\128\168break" } }
	local found, note = f.fetch()
	check("only valid distinct IDs reach the menu", #found == 1 and found[1] == "valid/model")
	check("the note identifies omissions without copying bad data", note:find("3 invalid model ids hidden", 1, true)
		and not note:find("broken", 1, true))
	check("remote data does not replace a saved selection", f.record.model == "saved" and f.record.models[1] == "saved")
	f.healthy(); f.close()
end)

case("a successful empty refresh clears stale discovery and remains retryable", function()
	local f = fixture(); f.rows = { { id = "previous" } }; assert(#f.fetch() == 1)
	f.rows = {}; local found, note = f.fetch()
	check("an empty reply is explained and is not cached", #found == 0 and note:find("empty list", 1, true) and f.models.cached(f.record) == nil)
	f.rows = { { id = "restored" } }
	local retry = f.run(function() return f.models.discover(f.record) end)
	check("the next request can recover immediately", #retry == 1 and retry[1] == "restored" and f.h.http.requestCount == 3)
	f.healthy(); f.close()
end)

case("oversized catalogs publish an explicit bounded partial result", function()
	local f = fixture()
	for index = 1, 10001 do f.rows[index] = { id = string.format("model-%05d", index) } end
	local found, note = f.fetch()
	check("one catalog cannot create more than ten thousand choices", #found == 10000 and found[#found] == "model-10000")
	check("omissions keep manual entry discoverable", note:find("page limit reached", 1, true) and note:find("entered manually", 1, true))
	f.healthy(); f.close()
end)

suite.finish()
