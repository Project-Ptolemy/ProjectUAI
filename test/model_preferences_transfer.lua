-- Model shortcuts cross configuration boundaries without credentials or aliases.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Model preference transfer")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new()
	f.config, f.util = f.env.require("runtime/config"), f.env.require("runtime/util")
	f.transfer = f.env.require("runtime/config_transfer")
	local registry = f.env.require("provider/registry")
	f.record = registry.blank("ollama")
	f.record.apiKey, f.record.model, f.record.models = "fixture-private-key", "Vendor/Model-A", { "Vendor/Model-A", "Vendor/Model-B" }
	assert(registry.save(f.record))
	f.config.set("ui.modelFavorites", { [f.record.id] = { ["Vendor/Model-A"] = true } })
	f.config.set("ui.recentModels", { [f.record.id] = { "Vendor/Model-B", "Vendor/Model-A" } })
	return f
end

case("public export and import preserve model shortcuts independently of credentials", function()
	local f = fixture()
	local body = assert(f.transfer.export())
	check("public copies keep exact model IDs and omit the provider key", body:find("Vendor/Model-A", 1, true) and not body:find("fixture-private-key", 1, true))
	local preview = assert(f.transfer.preview(body))
	check("preview keeps favorite membership and recent order", preview.config.ui.modelFavorites[f.record.id]["Vendor/Model-A"] == true
		and preview.config.ui.recentModels[f.record.id][1] == "Vendor/Model-B")
	f.config.set("ui.modelFavorites", {}); f.config.set("ui.recentModels", {})
	assert(f.transfer.apply(preview))
	preview.config.ui.recentModels[f.record.id][1] = "host-mutated"
	check("applied shortcuts are detached from the preview", f.config.get("ui.modelFavorites")[f.record.id]["Vendor/Model-A"] == true
		and f.config.get("ui.recentModels")[f.record.id][1] == "Vendor/Model-B")
	check("transfer stays offline", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("invalid shortcut shapes and exact-ID violations reject the whole import", function()
	local f = fixture(); local baseline = f.util.deepCopy(f.config.data)
	local invalid = {
		{ "modelFavorites", "wrong shape" },
		{ "modelFavorites", { absent = { model = true } } },
		{ "modelFavorites", { [f.record.id] = { [" model "] = true } } },
		{ "modelFavorites", { [f.record.id] = { model = false } } },
		{ "recentModels", { [f.record.id] = "wrong shape" } },
		{ "recentModels", { [f.record.id] = { "same", "same" } } },
		{ "recentModels", { [f.record.id] = { "bad\0model" } } },
		{ "recentModels", { [f.record.id] = { "bad\255model" } } },
	}
	local favorites, recent, buckets = {}, {}, {}
	for index = 1, 101 do favorites["model-" .. index] = true end
	for index = 1, 13 do recent[index] = "model-" .. index end
	for index = 1, 257 do buckets["provider-" .. index] = {} end
	invalid[#invalid + 1] = { "modelFavorites", { [f.record.id] = favorites } }
	invalid[#invalid + 1] = { "recentModels", { [f.record.id] = recent } }
	invalid[#invalid + 1] = { "modelFavorites", buckets }
	for _, item in ipairs(invalid) do
		local snapshot = f.util.deepCopy(baseline); snapshot.ui[item[1]] = item[2]
		local value, why = f.transfer.validate(snapshot)
		check("malformed shortcuts are rejected with an explanation", value == nil and type(why) == "string" and why ~= "")
	end
	check("rejected imports leave live preferences unchanged", f.config.get("ui.recentModels")[f.record.id][1] == "Vendor/Model-B"
		and f.config.get("ui.modelFavorites")[f.record.id]["Vendor/Model-A"])
	f.healthy(); f.close()
end)

case("boundary-sized lists and older exports retain the shared model-ID contract", function()
	local f = fixture(); local snapshot = f.util.deepCopy(f.config.data)
	local favorites, recent = {}, {}
	for index = 1, 100 do favorites["model-" .. index] = true end
	for index = 1, 12 do recent[index] = "model-" .. index end
	snapshot.ui.modelFavorites, snapshot.ui.recentModels = { [f.record.id] = favorites }, { [f.record.id] = recent }
	check("documented favorite and recent limits are accepted", f.transfer.validate(snapshot) ~= nil)
	snapshot.ui.modelFavorites, snapshot.ui.recentModels = nil, nil
	local legacy = assert(f.transfer.validate(snapshot))
	check("older exports receive empty model shortcuts", next(legacy.ui.modelFavorites) == nil and next(legacy.ui.recentModels) == nil)
	local parser, providerParser = f.env.require("runtime/model_id"), f.env.require("provider/model_id")
	check("provider and runtime callers share the exact parser", parser == providerParser and parser.parse("  Vendor/Model-A  ") == "Vendor/Model-A")
	check("valid UTF-8 at the byte limit is accepted", parser.parse(string.rep("a", 158) .. "\195\169") ~= nil)
	for _, id in ipairs({ string.rep("a", 159) .. "\195\169", "bad\255", "bad\0id", "two\nmodels", "line\226\128\168break", 42 }) do
		check("invalid model text cannot cross either boundary", parser.parse(id) == nil and providerParser.parse(id) == nil)
	end
	f.healthy(); f.close()
end)

suite.finish()
