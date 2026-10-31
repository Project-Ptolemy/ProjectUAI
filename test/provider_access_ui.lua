-- Actual setup controls keep community and personal credentials separate.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider access UI")
local case, check = suite.case, suite.check
local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.2)
end
local function field(f, name, text)
	f.h.type(assert(f.h.byName(name)):FindFirstChildOfClass("TextBox"), text); f.h.settle(0.2)
end
local function choose(f, id)
	click(f, "Preset")
	local tier = f.env.require("provider/catalog").get(id).tier
	if tier ~= "custom" then click(f, "Segment_" .. tier) end
	click(f, "Choice_" .. id)
end

case("choosing Free in the library waits for Save before installing", function()
	local f = F.ui(390, 700); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").add(function(id) f.saved = registry.get(id) end)
	click(f, "Choice_projectuai-free")
	check("library selection opens a separate unsaved draft", f.h.textOf(f.h.byName("Preset")) == "Project UAI Free"
		and registry.count() == 0 and f.h.http.requestCount == 0)
	click(f, "SaveProvider")
	check("Save installs only the selected access type", f.saved and f.saved.preset == "projectuai-free" and registry.count() == 1
		and f.env.require("provider/community_key").isApplied(f.saved))
	f.healthy(); f.close()
end)

case("changing an edited Free endpoint to custom discards its community key", function()
	local f = F.ui(900, 750); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("projectuai-free"))
	field(f, "BaseUrl", "https://changed.fixture/v1")
	choose(f, "custom")
	check("custom setup has no inherited community credential", f.h.byName("KeyState").Text == "not set"
		and f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model")
	check("switching providers remains a draft", registry.count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("adding a personal key changes to HCNSEC without retaining the community key", function()
	local f = F.ui(900, 800); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("projectuai-free"), function(id) f.saved = registry.get(id) end)
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
	check("personal access is clearly named", f.h.textOf(f.h.byName("Preset")) == "HCNSEC"
		and not f.h.byName("CommunityKey").Visible and f.h.textOf(f.h.byName("ActiveModel")) == "Choose a model")
	click(f, "TypeSetupModel"); field(f, "PromptField", "my-account-model")
	click(f, "SaveProvider")
	check("personal Save contains exactly the supplied key", f.saved and f.saved.preset == "hcnsec"
		and f.saved.apiKey == "synthetic-personal-key" and #registry.keysOf(f.saved) == 1 and f.saved.model == "my-account-model")
	check("setup sends no discovery or inference automatically", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

suite.finish()
