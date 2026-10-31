-- Model edits settle atomically and preserve the existing catalog on rejection.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider model edits")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new(); f.registry, f.models = f.env.require("provider/registry"), f.env.require("provider/models")
	f.record = f.registry.blank("ollama"); f.record.model, f.record.models = "first", { "first", "second" }
	assert(f.registry.save(f.record)); f.events = 0
	f.models.changed:connect(function() f.events = f.events + 1 end)
	return f
end

case("all entry paths reject malformed model identifiers", function()
	local f = fixture(); local before = f.record.models
	for _, id in ipairs({ "", "two\nmodels", "null\0id", "invalid\255", "line\226\128\168break", string.rep("m", 161), 45, {} }) do
		check("manual entry is rejected without mutation", not f.models.add(f.record, id) and f.record.models == before)
		check("direct selection is rejected without mutation", not f.registry.setModel(f.record.id, id)
			and f.record.model == "first" and f.record.models == before)
	end
	check("rejections send no network requests or model events", f.h.http.requestCount == 0 and f.events == 0)
	f.healthy(); f.close()
end)

case("choosing a known ID persists its selection without duplicating the entry", function()
	local f = fixture()
	local ok, id = f.models.add(f.record, " second ", { select = true })
	check("a different existing model is selected successfully", ok and id == "second" and f.record.model == "second"
		and #f.record.models == 2 and f.events == 1)
	check("selecting it again is a no-op", not f.models.add(f.record, "second", { select = true }) and f.events == 1)
	local before = f.record.models
	check("removing an absent model retains the list identity", not f.models.remove(f.record, "missing") and f.record.models == before)
	f.healthy(); f.close()
end)

case("vault admission rejects saved changes while isolated drafts remain editable", function()
	local f = fixture(); local config = f.env.require("runtime/config")
	config.accessProblem = function() return "Unlock first" end
	local before = f.record.models
	check("gated operations do not mutate a live record", not f.models.add(f.record, "blocked")
		and not f.models.remove(f.record, "first") and f.record.models == before and f.record.model == "first")
	local draft = f.env.require("runtime/util").deepCopy(f.record)
	check("draft entry stays isolated", f.models.add(draft, "draft-model", { persist = false })
		and draft.model == "draft-model" and f.record.model == "first")
	f.healthy(); f.close()
end)

case("a failed save restores model selection and catalog references", function()
	local f = fixture(); local before = f.record.models
	f.registry.save = function() return false, { "Storage changed" } end
	for _, change in ipairs({ function() return f.models.add(f.record, "new") end,
		function() return f.models.add(f.record, "second", { select = true }) end,
		function() return f.models.remove(f.record, "first") end,
		function() return f.registry.setModel(f.record.id, "third") end }) do
		local ok, why = change()
		check("failed persistence cannot leave a half-applied model edit", not ok and why == "Storage changed"
			and f.record.models == before and f.record.model == "first" and f.events == 0)
	end
	f.healthy(); f.close()
end)

suite.finish()
