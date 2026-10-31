-- User-visible model shortcuts and key search through the real controls.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider quality of life UI")
local case, check = suite.case, suite.check
local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.2)
end
local function fixture()
	local f = F.ui(900, 760)
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank("ollama")
	f.record.model, f.record.models = "vendor/smart-model", { "vendor/smart-model", "other/model" }
	assert(f.registry.save(f.record))
	return f
end

case("favorites and multiword search stay usable in the model picker", function()
	local f = fixture(); f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.2)
	local originalRow = f.h.byName("Model_vendor/smart-model")
	click(f, "ModelOptions"); click(f, "Option_favorite")
	check("the selected model becomes a visible favorite", f.env.require("provider/model_preferences").favorite(f.record, f.record.model)
		and f.h.textOf(f.h.byName("Model_vendor/smart-model")):find("Favorite", 1, true))
	check("favorite changes retain the existing model control", f.h.byName("Model_vendor/smart-model") == originalRow)
	local filter = assert(f.h.byName("ModelFilter")):FindFirstChildOfClass("TextBox")
	f.h.type(filter, "smart vendor"); f.h.settle(0.2)
	check("search matches words in either order", f.h.byName("Model_vendor/smart-model").Visible and not f.h.byName("Model_other/model").Visible)
	click(f, "ModelOptions"); click(f, "Option_clear")
	check("clear filters restores the catalog", filter.Text == "" and f.h.byName("Model_other/model").Visible)
	click(f, "ModelOptions"); click(f, "Option_favorites")
	check("favorites-only keeps the saved shortcut", f.h.byName("Model_vendor/smart-model").Visible and not f.h.byName("Model_other/model").Visible)
	check("model browsing stays offline", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("key search finds names and status without searching secret material", function()
	local f = fixture(); local keys = f.env.require("runtime/provider_keys")
	assert(keys.add(f.record, "fixture-work-secret\nfixture-home-secret"))
	assert(keys.rename(f.record, 1, "Work primary")); assert(keys.rename(f.record, 2, "Home")); assert(keys.setPaused(f.record, 2, true))
	f.env.require("ui/providerkeys").open({ record = f.record }); f.h.settle(0.2)
	local filter = assert(f.h.byName("KeyFilter")):FindFirstChildOfClass("TextBox")
	f.h.type(filter, "primary work"); f.h.settle(0.2)
	check("multiword names filter without rebuilding the focused field", f.h.byName("APIKey_1").Visible and not f.h.byName("APIKey_2").Visible
		and f.h.byName("KeyFilter"):FindFirstChildOfClass("TextBox") == filter)
	f.h.type(filter, "paused"); f.h.settle(0.2)
	check("paused keys remain easy to find", not f.h.byName("APIKey_1").Visible and f.h.byName("APIKey_2").Visible)
	f.h.type(filter, "fixture-work-secret"); f.h.settle(0.2)
	check("secret values are not searchable and no-match guidance remains visible", not f.h.byName("APIKey_1").Visible and f.h.byName("NoKeyMatch").Visible)
	check("filtering never changes key policy", keys.mode(f.record) == "rotate" and keys.paused(f.record, 2))
	f.healthy(); f.close()
end)

suite.finish()
