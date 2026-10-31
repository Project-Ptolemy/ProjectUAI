-- Setup copy and catalog controls reflect the actual connection and keep secrets out.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider setup")
local case, check = suite.case, suite.check

local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.1)
end
local function typeInto(f, name, text)
	local box = assert(f.h.byName(name)):FindFirstChildOfClass("TextBox")
	box:CaptureFocus(); f.h.type(box, text); f.h.settle(0.1); return box
end

case("no-key and desktop sign-in routes explain how authentication works", function()
	for _, preset in ipairs({ "kilo", "cline" }) do
		local f = F.ui(900, 750); local registry = f.env.require("provider/registry")
		local record = registry.blank(preset)
		f.env.require("ui/panels/providers").editor(record); f.h.settle(0.2)
		local expected = preset == "cline" and "Sign in to Cline in the desktop app" or "No API key required"
		check(preset .. " does not ask for a missing API key", f.h.byName("KeyState").Text == expected)
		click(f, "ActiveModel")
		local menu = f.h.byName("Menu")
		check("setup actions are searchable", f.h.byName("MenuSearch", menu) ~= nil)
		if preset == "cline" then
			local text = f.h.textOf(menu)
			check("Cline menu names desktop catalog", text:find("Cline's free catalog through the desktop bridge", 1, true) ~= nil)
			check("Cline menu does not present virtual marker as a public route", text:find("uai-tunnel.invalid", 1, true) == nil)
		end
		check("opening setup makes no requests", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end
end)

case("route summaries and loading copy omit URL query credentials", function()
	local f = F.ui(1000, 800); local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl, record.authStyle = "Private query", "https://catalog.fixture/v1?secret=fixture-query-secret", "none"
	record.query = { token = "fixture-extra-secret" }; record.model, record.models = "manual", { "manual" }
	assert(registry.save(record)); local panel = f.env.require("ui/panels/providers").new(f.host); f.h.settle(0.2)
	local facts = f.h.textOf(f.h.byName("StatusFacts"))
	check("facts include route without secret query", facts:find("https://catalog.fixture/v1/chat/completions", 1, true) ~= nil
		and not facts:find("fixture-query-secret", 1, true) and not facts:find("fixture-extra-secret", 1, true))
	check("the provider heading also omits query credentials", not f.h.byName("ProviderEndpoint").Text:find("fixture-query-secret", 1, true))
	f.env.require("ui/panels/providers").editor(record); f.h.settle(0.2)
	f.h.http.handler = function() return { StatusCode = 200, delay = 1, Body = f.h.json.encode({ data = { { id = "found" } } }) } end
	click(f, "ActiveModel"); local menuText = f.h.textOf(f.h.byName("Menu"))
	check("menu hides query credentials", not menuText:find("fixture-query-secret", 1, true) and not menuText:find("fixture-extra-secret", 1, true))
	click(f, "Option_fetch"); local note = f.h.byName("ModelNote").Text
	check("loading copy names a safe route", note:find("Loading https://catalog.fixture/v1/models", 1, true) ~= nil
		and not note:find("fixture-query-secret", 1, true) and not note:find("fixture-extra-secret", 1, true))
	f.h.settle(1.2); f.env.require("ui/overlay").closeAll(); f.healthy(); f.close()
end)

case("large saved catalogs can be searched without losing focus on health updates", function()
	local f = F.ui(1000, 850); local registry = f.env.require("provider/registry")
	local record = registry.blank("custom"); record.label, record.baseUrl, record.authStyle = "Many models", "https://models.fixture/v1", "none"
	record.models = {}; for index = 1, 120 do record.models[index] = "vendor/model-" .. index end; record.model = record.models[1]
	assert(registry.save(record)); local panel = f.env.require("ui/panels/providers").new(f.host); f.h.settle(0.2)
	f.h.byName("SavedModelList").CanvasPosition = f.h.dt.Vector2.new(0, 800)
	panel.select(record.id); f.h.settle(0.2)
	check("refreshing the provider preserves catalog reading position", f.h.byName("SavedModelList").CanvasPosition.Y == 800)
	local row = f.h.byName("Model_12"); local search = typeInto(f, "SavedModelSearch", "model-12 vendor")
	check("only matching IDs remain", row.Visible and not f.h.byName("Model_13").Visible and not f.h.byName("Model_112").Visible
		and f.h.byName("Model_120").Visible and f.h.byName("SavedModelCount").Text == "2 of 120 models")
	check("search returns to the matching rows", f.h.byName("SavedModelList").CanvasPosition.Y == 0)
	registry.changed:fire("health", record.id); f.h.settle(0.2)
	check("health preserves search and rows", f.h.byName("Model_12") == row and search:IsFocused()
		and f.h.byName("SavedModelSearch"):FindFirstChildOfClass("TextBox") == search)
	typeInto(f, "SavedModelSearch", "missing-id")
	check("empty result explains recovery without a blank catalog", f.h.byName("NoSavedModelsMatch").Visible and not f.h.byName("SavedModelList").Visible)
	panel.select(record.id); f.h.settle(0.2)
	check("selection refresh keeps search", f.h.byName("SavedModelSearch"):FindFirstChildOfClass("TextBox").Text == "missing-id"
		and f.h.byName("NoSavedModelsMatch").Visible)
	click(f, "Select_ActiveModel")
	check("active-model selector has search too", f.h.byName("MenuSearch") ~= nil)
	f.healthy(); f.close()
end)

case("protocol and authentication stay visible with the connection fields", function()
	local f = F.ui(390, 700)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("openai")
	record.apiKey, record.model, record.models = "fixture-key", "fixture-model", { "fixture-model" }
	f.env.require("ui/panels/providers").editor(record, function(id) f.saved = registry.get(id) end)
	f.h.settle(0.2)
	local name = assert(f.h.byName("ProviderName")):FindFirstChildOfClass("TextBox")
	check("protocol and authentication are in the visible connection section", f.h.byName("Protocol").Parent.Parent == f.h.byName("ConnectionSetup")
		and f.h.byName("AuthStyle").Parent.Parent == f.h.byName("ConnectionSetup"))
	click(f, "AuthStyle"); click(f, "Option_x-api-key")
	check("choosing authentication preserves the original mounted form", f.h.byName("ProviderName"):FindFirstChildOfClass("TextBox") == name)
	click(f, "SaveProvider")
	check("saving retains authentication and basic fields", f.saved and f.saved.authStyle == "x-api-key"
		and f.saved.model == "fixture-model" and f.saved.apiKey == "fixture-key")
	check("editing makes no request", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("custom setup starts with its endpoint, protocol and authentication", function()
	local f = F.ui(390, 700)
	f.env.require("ui/panels/providers").editor(f.env.require("provider/registry").blank("custom"))
	f.h.settle(0.2)
	local connection = f.h.byName("ConnectionSetup")
	check("connection essentials lead the custom form", connection.Parent.LayoutOrder < f.h.byName("AccessSetupGroup").LayoutOrder
		and connection.Parent.LayoutOrder < f.h.byName("ModelSetupGroup").LayoutOrder)
	for _, name in ipairs({ "BaseUrl", "Protocol", "AuthStyle" }) do
		local control = assert(f.h.byName(name))
		check(name .. " is visible without opening help", control.Parent.Parent == connection and control.Visible
			and control.Parent.Visible and connection.Visible and connection.Parent.Visible)
	end
	check("setup guidance starts expanded", f.h.byName("ProviderGuide").Visible)
	f.healthy(); f.close()
end)

case("manual model entry supersedes a pending direct catalog fetch", function()
	local f = F.ui(390, 700)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl, record.authStyle = "Manual setup", "https://setup.fixture/v1", "none"
	f.env.require("ui/panels/providers").editor(record, function(id) f.saved = registry.get(id) end)
	f.env.require("provider/models").discover = function()
		f.h.sched.wait(3)
		return { "late-model" }, "Synthetic catalog"
	end
	click(f, "FetchSetupModels")
	check("a pending fetch disables both catalog actions", not f.h.byName("ActiveModel").Active and not f.h.byName("FetchSetupModels").Active)
	click(f, "TypeSetupModel")
	typeInto(f, "PromptField", "manual-choice")
	f.h.settle(3.2)
	check("late discovery cannot reopen its menu or replace manual entry", f.h.byName("MenuLayer") == nil
		and f.h.textOf(f.h.byName("ActiveModel")) == "manual-choice")
	check("the catalog can be requested again", f.h.byName("ActiveModel").Active and f.h.byName("FetchSetupModels").Active)
	click(f, "SaveProvider")
	check("only the manual model is saved", f.saved and f.saved.model == "manual-choice" and #f.saved.models == 1)
	f.healthy(); f.close()
end)

case("invalid saves reveal the error at the start of the form", function()
	local f = F.ui(390, 700)
	f.env.require("ui/panels/providers").editor(f.env.require("provider/registry").blank("custom"))
	f.h.settle(0.2)
	local surfaces = f.env.require("ui/overlay").open
	local modal = surfaces[#surfaces]
	modal.scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 400)
	click(f, "SaveProvider")
	check("the error is visible before the form", f.h.byName("Problem").Visible
		and f.h.byName("Problem").LayoutOrder < f.h.byName("Form").LayoutOrder and modal.scroll.instance.CanvasPosition.Y == 0)
	check("invalid setup remains unsaved", f.env.require("provider/registry").count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("included setup keeps the model before optional guidance and connection overrides", function()
	local f = F.ui(390, 700)
	local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("projectuai-free"))
	f.h.settle(0.2)
	local model = f.h.byName("ActiveModel")
	check("included access is shown once without asking to reapply it", f.h.byName("AccessSummary").Visible
		and not f.h.byName("CommunityKey").Visible)
	check("the model comes before connection overrides and expanded help", f.h.byName("ModelSetupGroup").LayoutOrder < f.h.byName("ConnectionSetupGroup").LayoutOrder
		and f.h.byName("ProviderGuide").Visible)
	check("the full provider guidance and setup link remain available", f.h.byName("ProviderGuide").Visible
		and f.h.byName("KeyLinkUrl").Text == "https://discord.gg/9xYyyYuKap"
		and f.h.textOf(f.h.byName("ProviderGuide")):find("separate HCNSEC provider", 1, true) ~= nil)
	click(f, "ProviderGuideToggle")
	check("collapsing help never replaces the selected model or persists the draft", not f.h.byName("ProviderGuide").Visible and f.h.byName("ActiveModel") == model
		and f.h.textOf(model) == "auto" and registry.count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

suite.finish()
