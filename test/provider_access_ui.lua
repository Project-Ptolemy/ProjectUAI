-- Actual setup controls support no-key routes and personal custom credentials.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local Z = require("opencode_catalog_fixture")
local suite = F.suite("Provider access UI")
local case, check = suite.case, suite.check
local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.2)
end
local function field(f, name, text)
	f.h.type(assert(f.h.byName(name)):FindFirstChildOfClass("TextBox"), text); f.h.settle(0.2)
end
case("choosing a no-key route waits for a reviewed model and Save", function()
	local f = F.ui(390, 700); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").add(function(id) f.saved = registry.get(id) end)
	click(f, "Choice_kilo")
	check("library selection opens a separate unsaved draft", f.h.textOf(f.h.byName("Preset")) == "Kilo Code"
		and registry.count() == 0 and f.h.http.requestCount == 0)
	click(f, "SaveProvider")
	check("saving without a model remains blocked", registry.count() == 0 and f.h.byName("Problem").Visible)
	click(f, "TypeSetupModel"); field(f, "PromptField", "fixture/model:free")
	click(f, "SaveProvider")
	check("Save installs only the selected route and model", f.saved and f.saved.preset == "kilo" and registry.count() == 1
		and f.saved.model == "fixture/model:free" and f.saved.authStyle == "none" and f.saved.apiKey == "")
	check("setup never performs a provider request", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("adding a personal key keeps the chosen custom connection and explicit model", function()
	local f = F.ui(900, 800); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("custom"), function(id) f.saved = registry.get(id) end)
	field(f, "BaseUrl", "https://personal.fixture/v1")
	click(f, "ManageKeys"); click(f, "AddKey")
	field(f, "PromptField", "synthetic-personal-key")
	local overlays = f.env.require("ui/overlay").open
	local confirm
	for _, node in ipairs(overlays[#overlays].footer:GetDescendants()) do
		if node.ClassName == "TextLabel" and node.Text == "Save key" then
			confirm = node.Parent
			while confirm and confirm.ClassName ~= "TextButton" do confirm = confirm.Parent end
		end
	end
	f.h.click(assert(confirm, "missing key confirmation")); f.h.settle(0.2)
	click(f, "ApplyKeys")
	check("adding a key does not select a different provider or model", f.h.textOf(f.h.byName("Preset")) == "Custom endpoint"
		and f.h.byName("CommunityKey") == nil and f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model"
		and registry.count() == 0)
	click(f, "TypeSetupModel"); field(f, "PromptField", "my-account-model")
	click(f, "SaveProvider")
	check("personal Save contains exactly the supplied key", f.saved and f.saved.preset == "custom"
		and f.saved.apiKey == "synthetic-personal-key" and #registry.keysOf(f.saved) == 1 and f.saved.model == "my-account-model")
	check("saving retains the chosen endpoint", f.saved and f.saved.baseUrl == "https://personal.fixture/v1")
	check("setup sends no discovery or inference automatically", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("reviewed Zen public Chat access saves without a personal key or connected desktop", function()
	local f = F.ui(390, 700); local registry = f.env.require("provider/registry")
	local draft = registry.blank("zen")
	Z.observe(f, draft, { Z.row("hy4-flash-free") })
	f.env.require("ui/panels/providers").editor(draft, function(id) f.saved = registry.get(id) end)
	click(f, "TypeSetupModel"); field(f, "PromptField", "hy4-flash-free")
	check("the key summary identifies official public authentication", f.h.byName("KeyState").Text == "Official public authentication"
		and not f.env.require("net/bridge").opencodeStatus().available)
	click(f, "SaveProvider")
	check("Save keeps the explicit public model without storing a token", f.saved and f.saved.preset == "zen"
		and f.saved.model == "hy4-flash-free" and f.saved.apiKey == "" and registry.count() == 1)
	local picker = f.env.require("ui/panels/providerpicker")
	check("the saved picker shows public access without requesting a key", picker.describe(f.saved).detail:find("Public free Chat API", 1, true)
		and f.env.require("provider/availability").describe(f.saved).ready)
	local util = f.env.require("runtime/util")
	for _, change in ipairs({ { model = "fixture-paid-model" }, { baseUrl = "https://opencode.ai/private/v1" }, { credentialsOmitted = true } }) do
		local other = util.deepCopy(f.saved)
		for name, value in pairs(change) do other[name] = value end
		check("paid custom and guarded routes do not claim public access", not picker.describe(other).detail:find("Public free Chat API", 1, true)
			and not f.env.require("provider/availability").describe(other).ready)
	end
	local bridge = f.env.require("net/bridge")
	local transport = f.env.require("net/transport")
	local previousStatus, previousModel, previousCowork = bridge.opencodeStatus, bridge.opencodeHasModel, transport.coworkWeb
	bridge.opencodeStatus = function() return { available = true, state = "ready" } end
	bridge.opencodeHasModel = function(id) return id == "hy4-flash-free" end
	transport.coworkWeb = function() return true end
	local personal = util.deepCopy(f.saved); personal.apiKey = "fixture-zen-personal-key"
	check("an advertised CLI does not label a personal-key API connection as native", not picker.describe(personal).detail:find("Desktop CLI", 1, true)
		and f.env.require("provider/availability").describe(personal).ready)
	local unlisted = util.deepCopy(f.saved); unlisted.model = "fixture-unlisted:free"
	check("an advertised CLI does not admit a model absent from the current official catalog", not picker.describe(unlisted).detail:find("Desktop CLI", 1, true)
		and not f.env.require("provider/availability").describe(unlisted).ready)
	bridge.opencodeStatus, bridge.opencodeHasModel, transport.coworkWeb = previousStatus, previousModel, previousCowork
	local imported = util.deepCopy(f.saved); imported.credentialsOmitted = true
	f.env.require("runtime/config").set("providers.list", { imported })
	f.env.require("ui/panels/providers").editor(imported, function(id) f.saved = registry.get(id) end); f.h.settle(0.3)
	check("a guarded import requires connection review before public access", f.h.byName("RestoreProviderCredentials") ~= nil
		and not f.env.require("provider/availability").describe(imported).ready)
	click(f, "SaveProvider")
	check("full Save restores review without adding a personal key", f.saved and f.saved.credentialsOmitted == nil
		and f.saved.apiKey == "" and f.saved.model == "hy4-flash-free" and f.env.require("provider/availability").describe(f.saved).ready)
	Z.observe(f, f.saved)
	check("confirmed access returns after the reviewed catalog is refreshed", picker.describe(f.saved).detail:find("Public free Chat API", 1, true))
	check("public setup sends no discovery or inference automatically", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("a saved unknown Zen model shows verification pending without guessing free access", function()
	local f = F.ui(900, 800); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("zen"), function(id) f.saved = registry.get(id) end)
	click(f, "TypeSetupModel"); field(f, "PromptField", "fixture-new-chat-model")
	check("setup labels missing facts as pending", f.h.byName("KeyState").Text == "Catalog verification pending")
	click(f, "SaveProvider")
	local public = f.env.require("provider/opencode_public")
	local picker = f.env.require("ui/panels/providerpicker")
	check("pending setup preserves the exact selected ID", f.saved and f.saved.model == "fixture-new-chat-model"
		and public.pending(f.saved) and not public.available(f.saved))
	check("pending saved details do not claim free or CLI access", picker.describe(f.saved).detail:find("Catalog verification pending", 1, true)
		and not picker.describe(f.saved).detail:find("Public free", 1, true) and not f.env.require("provider/models").isFree(f.saved, f.saved.model))
	Z.observe(f, f.saved, { Z.row(f.saved.model) })
	check("explicit zero-price Chat facts confirm an ID without a free suffix", public.available(f.saved)
		and picker.describe(f.saved).detail:find("Public free Chat API", 1, true))
	Z.observe(f, f.saved, { Z.row(f.saved.model, { kind = "decision", protocol = "systemone",
		api = { systemone = { base_url = "https://opencode.ai/inference/systemone/v1" } } }) })
	check("decision-only facts remove the public claim", not public.available(f.saved) and not public.pending(f.saved)
		and not picker.describe(f.saved).detail:find("Public free", 1, true) and not f.env.require("provider/availability").describe(f.saved).ready)
	check("presentation and Save never send automatic requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

suite.finish()
