-- Provider setup regressions through real controls and synthetic responses.
-- No running model, credentials or executor workspace is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider editor")
local case, check = suite.case, suite.check

local function click(f, name, root)
	local control = assert(f.h.byName(name, root), "missing control: " .. name)
	f.h.click(control)
	return control
end

local function field(f, name, value)
	local row = assert(f.h.byName(name), "missing field: " .. name)
	f.h.type(assert(row:FindFirstChildOfClass("TextBox")), value)
end

local function closeMenu(f)
	if f.h.byName("MenuLayer") then f.h.press("Escape") end
end

local function auth(f, value)
	click(f, "AuthStyle")
	click(f, "Option_" .. value)
end

-- The preset control opens the provider gallery now, so a preset is chosen by
-- clicking its card in the tier it belongs to. Custom is appended to every tier.
local function preset(f, id)
	closeMenu(f)
	click(f, "Preset")
	local target = assert(f.env.require("provider/catalog").get(id), "missing preset " .. id)
	if target.tier == "free" or target.tier == "paid" or target.tier == "local" then
		click(f, "Segment_" .. target.tier, f.h.byName("ProviderTier"))
		f.h.settle(0.2)
	end
	click(f, "Choice_" .. id)
	f.h.settle(0.2)
end

-- Adding starts at the gallery; most cases want the custom endpoint.
local function chooseCustom(f)
	f.h.settle(0.2)
	click(f, "Choice_custom")
	f.h.settle(0.2)
end

local function key(f, value)
	click(f, "ManageKeys")
	click(f, f.h.byName("ReplaceKey_1") and "ReplaceKey_1" or "AddKey")
	assert(f.h.byName("PromptField")):FindFirstChildOfClass("TextBox").Text = value
	f.h.settle(0.1)
	for _, node in ipairs(f.env.root:GetDescendants()) do
		if node.ClassName == "TextLabel" and node.Text == "Save key" then
			local button = node.Parent
			while button and button.ClassName ~= "TextButton" do button = button.Parent end
			assert(button, "missing key confirmation")
			f.h.click(button)
			click(f, "ApplyKeys")
			return
		end
	end
	error("missing Save key button")
end

local function fixture(initialPreset)
	local f = F.ui(1000, 850)
	local registry = f.env.require("provider/registry")
	local record = registry.blank(initialPreset or "custom")
	record.label, record.baseUrl, record.apiKey = "My connection", "https://editor.fixture/v1", "fixture-key"
	record.model, record.models = "manual-model", { "manual-model" }
	record.wsUrl = "wss://gateway.fixture/old-upstream"
	f.original = record
	f.env.require("ui/panels/providers").editor(record, function(id) f.saved = registry.get(id) end)
	f.h.settle(0.2)
	return f
end

local function fetch(f)
	closeMenu(f)
	click(f, "ActiveModel")
	click(f, "Option_fetch")
end

local function response(f, model, delay)
	return { StatusCode = 200, Body = f.h.json.encode({ data = { { id = model } } }), delay = delay }
end

for _, setting in ipairs({
	{ name = "protocol", control = "Protocol", value = "anthropic", field = "api" },
	{ name = "auth", control = "AuthStyle", value = "x-api-key", field = "authStyle" },
}) do
	case("a dismissed " .. setting.name .. "-only draft survives reopening Add", function()
		local f = F.ui(1000, 850)
		local providers = f.env.require("ui/panels/providers")
		local registry = f.env.require("provider/registry")
		providers.add()
		chooseCustom(f)
		if setting.control == "AuthStyle" then auth(f, setting.value)
		else click(f, "Segment_" .. setting.value, f.h.byName(setting.control)) end
		if setting.field == "api" then
			f.h.press("Escape")
		else
			local surfaces = f.env.require("ui/overlay").open
			click(f, "Dismiss", surfaces[#surfaces].scrim)
		end
		check("dismissing setup does not save an incomplete provider", registry.count() == 0)
		providers.add(function(id) f.saved = registry.get(id) end)
		field(f, "ProviderName", "Resumed connection")
		field(f, "BaseUrl", "https://resumed.fixture/v1")
		key(f, "fixture-resumed-key")
		click(f, "ActiveModel")
		click(f, "Option_add")
		field(f, "PromptField", "resumed-model")
		click(f, "SaveProvider")
		check("the saved connection retains the dismissed selection", f.saved and f.saved[setting.field] == setting.value)
		check("finishing the draft keeps its new fields", f.saved.label == "Resumed connection"
			and f.saved.apiKey == "fixture-resumed-key" and f.saved.model == "resumed-model")
		check("resuming and saving never contacts the endpoint", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end)
end

case("Start over discards a retained key and connection without saving", function()
	local f = fixture()
	local providers = f.env.require("ui/panels/providers")
	f.h.press("Escape")
	providers.add()
	check("Add resumes the dismissed connection", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == f.original.baseUrl
		and f.h.byName("KeyState").Text:find("-key", 1, true) ~= nil)
	click(f, "StartOverProvider")
	chooseCustom(f)
	check("Start over opens one empty connection", #f.h.allByName("SaveProvider") == 1
		and f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "")
	check("the old key and model are removed", f.h.byName("KeyState").Text == "not set"
		and f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model")
	f.h.press("Escape")
	providers.add()
	chooseCustom(f)
	check("closing the empty form cannot restore the discarded draft", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == ""
		and f.h.byName("KeyState").Text == "not set")
	check("discarding leaves the source record intact", f.original.apiKey == "fixture-key" and f.original.model == "manual-model")
	check("discarding neither saves nor contacts a provider", f.env.require("provider/registry").count() == 0
		and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("saving a resumed draft leaves the next Add empty", function()
	local f = fixture()
	local providers = f.env.require("ui/panels/providers")
	local registry = f.env.require("provider/registry")
	f.h.press("Escape")
	providers.add(function(id) f.saved = registry.get(id) end)
	click(f, "SaveProvider")
	check("the retained connection is saved once", f.saved and registry.count() == 1
		and f.saved.apiKey == "fixture-key" and f.saved.model == "manual-model")
	providers.add()
	chooseCustom(f)
	check("the next Add starts without the saved key or URL", f.h.byName("KeyState").Text == "not set"
		and f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "")
	check("the next Add has no previous model", f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model")
	check("the saved connection remains intact", registry.get(f.saved.id).apiKey == "fixture-key" and registry.count() == 1)
	check("saving performs no inference", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

for _, id in ipairs({ "ollama", "lmstudio", "vllm", "llamacpp", "sglang" }) do
	case(id .. " applies local defaults when chosen inside Add Provider", function()
		local f = fixture()
		preset(f, id)
		local expected = f.env.require("provider/catalog").get(id)
		check("local setup documentation is shown", f.h.byName("KeyLinkUrl").Text == expected.docs)
		check("setup link is not described as a key vendor", f.h.textOf():find("Server setup and API documentation", 1, true) ~= nil)
		click(f, "SaveProvider")
		local saved = assert(f.saved, "provider was not saved")
		check("chosen server/protocol saved", saved.preset == id and saved.baseUrl == expected.baseUrl and saved.api == "openai")
		check("neutral identity and optional auth survive the UI", saved.claudeUa == false and saved.authStyle == "none")
		check("another upstream's gateway is cleared", saved.wsUrl == "")
		check("typed name, key and model survive", saved.label == "My connection" and saved.apiKey == "fixture-key"
			and saved.model == "manual-model" and #saved.models == 1)
		check("editing did not mutate the original record", f.original.preset == "custom" and f.original.wsUrl ~= "")
		check("setup never performs inference", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end)
end

case("reselecting the current preset preserves its gateway", function()
	local f = fixture("openai")
	preset(f, "openai")
	click(f, "SaveProvider")
	check("same preset keeps its gateway", f.saved and f.saved.wsUrl == f.original.wsUrl)
	check("no connection test was dispatched", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

local changes = {
	{ "URL", function(f, changed) field(f, "BaseUrl", changed and "https://other.fixture/prefix/v1" or f.original.baseUrl) end },
	{ "protocol", function(f, changed) click(f, "Segment_" .. (changed and "anthropic" or "openai"), f.h.byName("Protocol")) end },
	{ "auth header", function(f, changed) auth(f, changed and "x-api-key" or "bearer") end },
	{ "key", function(f, changed) key(f, changed and "fixture-replacement" or "fixture-key") end },
	{ "preset", function(f, changed)
		preset(f, changed and "ollama" or "custom")
		if not changed then field(f, "BaseUrl", f.original.baseUrl) end
	end },
}

for _, change in ipairs(changes) do
	case(change[1] .. " edits discard fetched choices and supersede pending discovery", function()
		local f = fixture()
		local requests = 0
		f.h.http.handler = function(entry)
			check("discovery only makes GET requests", entry.method == "GET")
			requests = requests + 1
			return response(f, ({ "before-edit", "obsolete-pending", "current-model" })[requests], requests == 2 and 20 or 0)
		end
		fetch(f)
		check("successful discovery opens its choices", f.h.byName("Option_model:before-edit") ~= nil)
		check("manual choice stays available", f.h.byName("Option_model:manual-model") ~= nil)
		closeMenu(f)
		change[2](f, true)
		click(f, "ActiveModel")
		check("previous fetched choice expires", f.h.byName("Option_model:before-edit") == nil)
		check("connection edit preserves manual choice", f.h.byName("Option_model:manual-model") ~= nil)
		click(f, "Option_fetch")
		check("fetch is pending", not f.h.byName("ActiveModel").Active and requests == 2)
		change[2](f, false)
		check("edited connection can fetch without waiting for the old server", f.h.byName("ActiveModel").Active)
		fetch(f)
		check("new connection's result is offered", f.h.byName("Option_model:current-model") ~= nil)
		f.h.sched.advance(22)
		check("late old response cannot replace the choices", f.h.byName("Option_model:current-model") ~= nil
			and f.h.byName("Option_model:obsolete-pending") == nil)
		closeMenu(f)
		click(f, "SaveProvider")
		check("manual selection survives all connection edits", f.saved and f.saved.model == "manual-model" and #f.saved.models == 1)
		check("exactly three requested discoveries", requests == 3)
		f.healthy(); f.close()
	end)
end

case("an open menu cannot select a model fetched for a previous connection", function()
	local f = fixture()
	f.h.http.handler = function() return response(f, "previous-connection-model", 0) end
	fetch(f)
	check("old connection's menu is open", f.h.byName("Option_model:previous-connection-model") ~= nil)
	field(f, "BaseUrl", "https://changed.fixture/v1")
	click(f, "Option_model:previous-connection-model")
	click(f, "SaveProvider")
	check("obsolete menu selection cannot change the model", f.saved and f.saved.model == "manual-model" and #f.saved.models == 1)
	f.healthy(); f.close()
end)

case("changing away and back cannot revive the original pending fetch", function()
	local f = fixture()
	f.h.http.handler = function() return response(f, "obsolete-round-trip", 10) end
	fetch(f)
	field(f, "BaseUrl", "https://temporary.fixture/v1")
	field(f, "BaseUrl", f.original.baseUrl)
	f.h.sched.advance(12)
	check("a matching URL does not revive an old request", f.h.byName("MenuLayer") == nil)
	click(f, "ActiveModel")
	check("obsolete models stay absent", f.h.byName("Option_model:obsolete-round-trip") == nil)
	check("manual model remains available", f.h.byName("Option_model:manual-model") ~= nil)
	check("no unrequested refetch", f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

case("an uncooperative old discovery cannot unlock or overwrite a newer fetch", function()
	local f = fixture()
	local requests = 0
	-- Deliberately ignore cancellation to exercise the editor's final publication
	-- check independently of the transport's cooperative abort handling.
	f.env.require("provider/models").discover = function()
		requests = requests + 1
		local index = requests
		f.h.sched.wait(index == 1 and 4 or 10)
		return { index == 1 and "late-old" or "latest" }, "1 model from synthetic discovery"
	end
	fetch(f)
	field(f, "BaseUrl", "https://new.fixture/v1")
	fetch(f)
	f.h.sched.advance(3)
	check("older completion cannot enable the newer pending picker", not f.h.byName("ActiveModel").Active)
	check("older completion cannot open a menu", f.h.byName("MenuLayer") == nil)
	f.h.sched.advance(10)
	check("newest completion enables the picker", f.h.byName("ActiveModel").Active)
	check("only newest choices are shown", f.h.byName("Option_model:latest") ~= nil and f.h.byName("Option_model:late-old") == nil)
	check("exactly the requested operations ran", requests == 2)
	f.healthy(); f.close()
end)

case("discovery adopts its proxy into the current draft without saving it", function()
	local f = fixture(); preset(f, "agentrouter")
	local proxy = "https://puai-proxy.davidzk.tech/agentrouter/v1"
	f.h.http.handler = function(entry)
		if entry.index == 1 then return { StatusCode = 403, Body = '{"error":{"code":"unauthorized_client","message":"Unauthorized client"}}' } end
		check("discovery uses the designated proxy", entry.url == proxy .. "/models")
		return response(f, "proxy-model", 0)
	end
	fetch(f)
	check("the new URL is visible", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == proxy)
	check("the fetched models survive URL adoption", f.h.byName("Option_model:proxy-model") ~= nil)
	check("draft migration cannot create a saved provider", f.env.require("provider/registry").count() == 0)
	check("the proxy domain and cap are explained", f.h.byName("ProxyFallbackNotice").Text:find("90,000", 1, true) ~= nil)
	closeMenu(f); click(f, "SaveProvider")
	check("Save commits the displayed URL", f.saved and f.saved.baseUrl == proxy)
	f.healthy(); f.close()
end)

case("a completed connection test cannot replace a newer endpoint edit", function()
	local f = fixture(); preset(f, "agentrouter")
	f.env.require("provider/chat").complete = function(candidate)
		f.h.sched.wait(3)
		candidate.baseUrl = "https://puai-proxy.davidzk.tech/agentrouter/v1"
		return { ms = 10 }
	end
	click(f, "TestConnection")
	field(f, "BaseUrl", "https://new-choice.fixture/v1")
	f.h.sched.advance(4)
	check("the current field survives the late migration", f.h.byName("BaseUrl"):FindFirstChildOfClass("TextBox").Text == "https://new-choice.fixture/v1")
	click(f, "SaveProvider")
	check("the user choice is saved", f.saved and f.saved.baseUrl == "https://new-choice.fixture/v1")
	f.healthy(); f.close()
end)

suite.finish()
