-- Provider gallery: tiers, search, descriptions and the seeded editor.
-- Every request is synthetic; no key or endpoint is contacted.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider gallery")
local case, check = suite.case, suite.check

local function click(f, name, root)
	local control = assert(f.h.byName(name, root), "missing control: " .. name)
	f.h.click(control)
	return control
end

local function search(f, text)
	local field = assert(f.h.byName("ProviderSearch"), "missing search field")
	local box = assert(field:FindFirstChildOfClass("TextBox"), "missing search box")
	f.h.type(box, text)
	f.h.sched.advance(0.3)
end

local function cards(f)
	local gallery = assert(f.h.byName("ProviderGallery"), "missing gallery")
	local out = {}
	for _, child in ipairs(gallery:GetChildren()) do
		if child:IsA("TextButton") and child.Name:sub(1, 7) == "Choice_" then out[#out + 1] = child.Name:sub(8) end
	end
	table.sort(out, function(a, b)
		local ao = f.h.byName("Choice_" .. a).LayoutOrder
		local bo = f.h.byName("Choice_" .. b).LayoutOrder
		return ao < bo
	end)
	return out
end

local function open(f)
	f.env.require("ui/panels/providers").add(function(id) f.saved = id end)
	f.h.settle(0.3)
end

case("the recommended tier leads with included access, AgentRouter and the hybrids", function()
	local f = F.ui(1000, 850)
	open(f)
	local order = cards(f)
	check("Project UAI Free is the first card", order[1] == "projectuai-free")
	check("AgentRouter follows", order[2] == "agentrouter")
	check("OpenCode Zen is recommended, not paid-only", order[3] == "zen")
	check("OpenRouter follows", order[4] == "openrouter")
	check("OpenCode Go follows", order[5] == "opencode-go")
	check("LLM7 is gone", f.h.byName("Choice_llm7") == nil)
	check("the custom endpoint is the last card", order[#order] == "custom")
	check("the free tier is selected", f.h.byName("Segment_free").Parent == f.h.byName("ProviderTier"))
	check("the count names the tier", f.h.byName("ProviderCount").Text == "18 free routes")
	check("included access is labelled", f.h.byName("ChoiceBadge", f.h.byName("Choice_projectuai-free")).Text == "Included")
	check("a hybrid says what is free", f.h.byName("ChoiceBadge", f.h.byName("Choice_zen")).Text == "Free models")
	check("the Go route names its free half", f.h.byName("ChoiceBadge", f.h.byName("Choice_opencode-go")).Text == "Free CLI")
	check("no-key routes say so", f.h.byName("ChoiceBadge", f.h.byName("Choice_kilo")).Text == "No key")
	check("Cline identifies its desktop sign-in route", f.h.byName("ChoiceBadge", f.h.byName("Choice_cline")).Text == "Free CLI"
		and f.h.byName("ChoiceDescription", f.h.byName("Choice_cline")).Text:find("UAI Bridge on Windows", 1, true) ~= nil
		and f.h.byName("ChoiceCost", f.h.byName("Choice_cline")).Text:find("desktop bridge", 1, true) ~= nil
		and f.h.byName("ChoiceCost", f.h.byName("Choice_cline")).Text:find("Cline sign-in", 1, true) ~= nil)
	check("the first card is described", f.h.byName("ChoiceDescription", f.h.byName("Choice_agentrouter")).Text
		:find("Claude Messages and GPT Responses gateway", 1, true) ~= nil)
	check("the description no longer recommends a model",
		f.h.byName("ChoiceDescription", f.h.byName("Choice_agentrouter")).Text:find("Recommended model", 1, true) == nil)
	local catalog = f.env.require("provider/catalog")
	check("and neither does the stored note", catalog.get("agentrouter").note:find("Recommended model", 1, true) == nil)
	check("the signup restriction is still highlighted", catalog.get("agentrouter").noteHighlight
		== "a GitHub account at least 1 year old")
	local agentDescription = f.h.byName("ChoiceDescription", f.h.byName("Choice_agentrouter"))
	check("signup eligibility stays highlighted on the compact card", agentDescription.RichText
		and agentDescription.Text:find("a GitHub account at least 1 year old", 1, true) ~= nil)
	check("the mobile relay requirement stays visible before setup", f.h.byName("ChoiceDescription", f.h.byName("Choice_zen")).Text
		:find("Mobile OpenCode requires the UAI Relay app from Discord", 1, true) ~= nil)
	for _, id in ipairs({ "zen", "openrouter", "opencode-go", "cline" }) do
		check(id .. " keeps its complete access limits", f.h.byName("ChoiceCost", f.h.byName("Choice_" .. id)).Text == catalog.get(id).cost)
	end
	check("the card carries the access line", f.h.byName("ChoiceCost", f.h.byName("Choice_agentrouter")).Text
		:find("Free quota", 1, true) ~= nil)
	check("no request was made", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("paid and local tiers list their own providers", function()
	local f = F.ui(1000, 850)
	open(f)
	click(f, "Segment_paid", f.h.byName("ProviderTier"))
	f.h.settle(0.2)
	local paid = cards(f)
	check("OpenAI leads the paid tier", paid[1], "openai")
	check("the paid count is stated", f.h.byName("ProviderCount").Text:find("paid providers", 1, true) ~= nil)
	check("a paid provider is present", f.h.byName("Choice_deepseek") ~= nil)
	check("a hybrid is not left in the paid tier", f.h.byName("Choice_openrouter") == nil
		and f.h.byName("Choice_zen") == nil and f.h.byName("Choice_opencode-go") == nil)
	check("paid routes are labelled paid", f.h.byName("ChoiceBadge", f.h.byName("Choice_openai")).Text == "Paid")
	click(f, "Segment_local", f.h.byName("ProviderTier"))
	f.h.settle(0.2)
	local localCards = cards(f)
	check("Ollama leads the local tier", localCards[1] == "ollama")
	check("the local count is stated", f.h.byName("ProviderCount").Text == "11 local servers")
	check("a local server is present", f.h.byName("Choice_lmstudio") ~= nil)
	check("custom remains reachable in every tier", localCards[#localCards], "custom")
	check("switching tiers makes no request", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("search spans every tier and clears back to the selected one", function()
	local f = F.ui(1000, 850)
	open(f)
	search(f, "claude")
	local results = cards(f)
	check("AgentRouter matches by tag", f.h.byName("Choice_agentrouter") ~= nil)
	check("Anthropic matches by name", f.h.byName("Choice_anthropic-messages") ~= nil)
	check("a local server without the tag is absent", f.h.byName("Choice_ollama") == nil)
	check("the count says it searched everything", f.h.byName("ProviderCount").Text:find("matches in all providers", 1, true) ~= nil)
	check("custom is not appended to a search", results[#results] ~= "custom")
	search(f, "qwen")
	check("a model family finds its hosts", f.h.byName("Choice_dashscope") ~= nil)
	check("and its open-model hosts", f.h.byName("Choice_cerebras") ~= nil)
	search(f, "zzzz-nothing")
	check("an unmatched search says so", f.h.byName("NoProviderMatchTitle") ~= nil)
	click(f, "ClearProviderSearchEmpty")
	f.h.settle(0.2)
	check("clearing restores the tier", f.h.byName("Choice_agentrouter") ~= nil
		and f.h.byName("ProviderCount").Text == "18 free routes")
	search(f, "openai")
	check("a name search puts the vendor first", cards(f)[1] == "openai")
	click(f, "ClearProviderSearch")
	f.h.settle(0.2)
	check("the inline clear empties the field", f.h.byName("ProviderSearch"):FindFirstChildOfClass("TextBox").Text == "")
	check("searching never contacts an endpoint", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("choosing a card opens the editor already seeded", function()
	local f = F.ui(1000, 850)
	open(f)
	click(f, "Choice_agentrouter")
	f.h.settle(0.3)
	check("the gallery closed", f.h.byName("ProviderPicker") == nil)
	check("the preset is named", f.h.textOf(f.h.byName("Preset")) == "AgentRouter")
	check("the URL is filled", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "https://agentrouter.org")
	check("the protocol follows the preset", f.h.byName("Protocol") ~= nil)
	check("the editor repeats what the card said", f.h.byName("PresetDescription").Text
		:find("Claude Messages and GPT Responses gateway", 1, true) ~= nil)
	check("the tier badge is shown", f.h.byName("PresetIntro") ~= nil)
	check("nothing was saved by choosing", f.env.require("provider/registry").count() == 0)
	check("choosing performs no inference", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("the custom card opens an empty endpoint form", function()
	local f = F.ui(1000, 850)
	open(f)
	click(f, "Choice_custom")
	f.h.settle(0.3)
	check("the preset is custom", f.h.textOf(f.h.byName("Preset")) == "Custom endpoint")
	check("the URL starts empty", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "")
	check("no model is chosen for it", f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model")
	f.healthy(); f.close()
end)

case("custom setup remains reachable from an empty search", function()
	local f = F.ui(390, 700)
	open(f)
	search(f, "   ")
	check("whitespace keeps the current tier", f.h.byName("Choice_projectuai-free") ~= nil and f.h.byName("ProviderCount").Text == "18 free routes")
	search(f, "zzzz-nothing")
	click(f, "CustomProviderShortcut")
	check("the custom shortcut opens a blank editable connection", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == ""
		and f.h.byName("Protocol").Parent.Parent == f.h.byName("ConnectionSetup"))
	check("the shortcut never saves or contacts a provider", f.env.require("provider/registry").count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("short gallery layouts keep the original focused search in one scrolling body", function()
	local f = F.ui(1000, 850)
	f.env.require("ui/responsive").init(f.env.root)
	open(f)
	search(f, "claude")
	local box = f.h.byName("ProviderSearch"):FindFirstChildOfClass("TextBox")
	box:CaptureFocus()
	f.h.setViewport(740, 240)
	check("the whole gallery scrolls in short space", f.h.byName("PickerViewport").ScrollingEnabled
		and not f.h.byName("ProviderGallery").ScrollingEnabled
		and f.h.byName("PickerRoot").AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
	check("resizing preserves native search focus and results", f.h.byName("ProviderSearch"):FindFirstChildOfClass("TextBox") == box
		and box:IsFocused() and box.Text == "claude" and f.h.byName("Choice_agentrouter") ~= nil)
	f.h.setViewport(1000, 850)
	check("roomy layouts restore the inner catalog scroll", not f.h.byName("PickerViewport").ScrollingEnabled
		and f.h.byName("ProviderGallery").ScrollingEnabled and box:IsFocused())
	f.healthy(); f.close()
end)

case("the gallery reflows without replacing the search or provider choices", function()
	local f = F.ui(1280, 900)
	f.env.require("ui/responsive").init(f.env.root)
	open(f)
	search(f, "claude")
	local box = f.h.byName("ProviderSearch"):FindFirstChildOfClass("TextBox")
	local card = assert(f.h.byName("Choice_agentrouter"))
	box:CaptureFocus()
	check("wide layouts put two cards on each line", f.h.byName("ProviderGalleryHolder"):GetAttribute("Columns") == 2
		and card.Size.X.Scale == 0.5)
	check("the card offers a clear setup action", f.h.byName("ChoiceAction", card).Text == "Set up")
	f.h.setViewport(500, 850)
	check("narrow layouts keep one readable card per line", f.h.byName("ProviderGalleryHolder"):GetAttribute("Columns") == 1
		and card.Size.X.Scale == 1)
	check("reflow keeps the mounted choices, query and native focus", f.h.byName("Choice_agentrouter") == card
		and f.h.byName("ProviderSearch"):FindFirstChildOfClass("TextBox") == box and box:IsFocused() and box.Text == "claude")
	f.h.setViewport(1280, 900)
	check("restoring width restores the gallery columns", f.h.byName("ProviderGalleryHolder"):GetAttribute("Columns") == 2
		and f.h.byName("Choice_agentrouter") == card and box:IsFocused())
	check("reflow never saves or contacts a provider", f.env.require("provider/registry").count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("the editor can reopen the gallery without losing what was typed", function()
	local f = F.ui(1000, 850)
	open(f)
	click(f, "Choice_custom")
	f.h.settle(0.3)
	local name = f.h.byName("ProviderName"):FindFirstChildOfClass("TextBox")
	f.h.type(name, "Kept name")
	click(f, "Preset")
	f.h.settle(0.3)
	check("the gallery opens above the editor", f.h.byName("ProviderPicker") ~= nil)
	click(f, "Segment_local", f.h.byName("ProviderTier"))
	f.h.settle(0.2)
	click(f, "Choice_ollama")
	f.h.settle(0.3)
	check("the chosen preset is applied in place", f.h.textOf(f.h.byName("Preset")) == "Ollama (local)")
	check("the typed name survives", f.h.byName("ProviderName"):FindFirstChildOfClass("TextBox").Text == "Kept name")
	check("the local URL is filled", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "http://127.0.0.1:11434/v1")
	check("still unsaved", f.env.require("provider/registry").count() == 0)
	f.healthy(); f.close()
end)

case("every preset has what the gallery promises to show", function()
	local f = F.new()
	local catalog = f.env.require("provider/catalog")
	local tiers = { free = true, paid = true, ["local"] = true, custom = true }
	local seen = {}
	for _, preset in ipairs(catalog.presets) do
		check("unique id " .. tostring(preset.id), seen[preset.id] == nil)
		seen[preset.id] = true
		check("tier for " .. preset.id, tiers[preset.tier] == true)
		check("description for " .. preset.id, type(preset.description) == "string" and #preset.description > 40)
		check("access line for " .. preset.id, type(preset.cost) == "string" and #preset.cost > 0)
		check("docs for " .. preset.id, preset.id == "custom"
			or (type(preset.docs) == "string" and preset.docs:sub(1, 4) == "http"))
	end
	check("the free tier leads with included access", catalog.byTier("free")[1].id == "projectuai-free")
	check("AgentRouter follows it", catalog.byTier("free")[2].id == "agentrouter")
	check("the hybrids are recommended", catalog.byTier("free")[3].id == "zen")
	check("search is empty without a query", catalog.search("") == nil)
	check("search finds by company", catalog.search("moonshot")[1].id == "moonshot")
	check("search is case insensitive", catalog.search("AGENTROUTER")[1].id == "agentrouter")
	check("search needs every word", catalog.search("free claude")[1].id == "agentrouter")
	check("search misses cleanly", #catalog.search("no-such-provider") == 0)
	check("quick picks keep their order", catalog.featured()[1].id == "agentrouter"
		and catalog.featured()[2].id == "zen" and catalog.featured()[3].id == "openrouter")
	for _, preset in ipairs(catalog.featured()) do
		check("community access is discovered in the library", preset.id ~= "projectuai-free")
	end
	check("HCNSEC has its own personal-key card", catalog.get("hcnsec").label == "HCNSEC"
		and catalog.get("hcnsec").free == nil and catalog.get("hcnsec").defaultModel == nil)
	f.healthy(); f.close()
end)

suite.finish()
