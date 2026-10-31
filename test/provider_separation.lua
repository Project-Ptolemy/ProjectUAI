-- Upgrade and draft boundaries for optional community and personal access.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider access separation")
local case, check = suite.case, suite.check

case("personal and community presets start with independent access", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local personal, free = registry.blank("hcnsec"), registry.blank("projectuai-free")
	check("personal access starts without a credential or invented model", personal.label == "HCNSEC" and personal.apiKey == ""
		and personal.model == "" and #personal.models == 0 and not registry.validate(personal))
	check("community access is a separate valid draft", free.label == "Project UAI Free" and registry.validate(free)
		and free.preset ~= personal.preset and free.model == "auto")
	check("creating drafts neither installs providers nor sends traffic", registry.count() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("legacy included access migrates identity while preserving user settings", function()
	local f = F.new(); local registry, config = f.env.require("provider/registry"), f.env.require("runtime/config")
	local included = registry.blank("projectuai-free")
	included.preset, included.id, included.label, included.enabled = "hcnsec", "legacy-free", "My evening account", false
	included.keyNames, included.keyPaused, included.keyMode, included.selectedKey = { "Community" }, { true }, "single", 1
	included.keyIds = { "11111111-1111-4111-8111-111111111111" }
	local personal = registry.blank("hcnsec")
	personal.id, personal.label, personal.apiKey, personal.model = "personal", "Project UAI Free", "synthetic-personal-key", "personal-model"
	config.set("providers", { active = personal.id, list = { included, personal } })
	check("both legacy identities are repaired once", registry.migrate() == 2 and registry.migrate() == 0)
	check("included identity preserves user choices", included.preset == "projectuai-free" and included.label == "My evening account"
		and included.enabled == false and included.keyPaused[1] and included.keyNames[1] == "Community"
		and included.keyMode == "single" and included.keyIds[1] == "11111111-1111-4111-8111-111111111111")
	check("personal credentials and selection remain independent", personal.preset == "hcnsec" and personal.label == "HCNSEC"
		and personal.apiKey == "synthetic-personal-key" and registry.active() == personal)
	f.healthy(); f.close()
end)

case("legacy reference restoration and separation happen in the same migration", function()
	local f = F.new(); local registry, config = f.env.require("provider/registry"), f.env.require("runtime/config")
	local legacy = registry.blank("hcnsec")
	legacy.id, legacy.label, legacy.model, legacy.communityCredential = "legacy-reference", "HCNSEC", "auto", true
	config.set("providers.list", { legacy })
	check("one pass restores the reference into its separate preset", registry.migrate() == 1
		and legacy.preset == "projectuai-free" and legacy.label == "Project UAI Free"
		and f.env.require("provider/community_key").isApplied(legacy))
	check("migration has no network side effects", registry.migrate() == 0 and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("a personal choice removes public keys from a mixed draft without losing metadata", function()
	local f = F.new(); local registry, keys = f.env.require("provider/registry"), f.env.require("runtime/provider_keys")
	local record = registry.blank("projectuai-free")
	assert(keys.add(record, "synthetic-personal-key")); assert(keys.rename(record, 2, "Work")); assert(keys.setMode(record, "single", 2))
	local personalId = record.keyIds[2]
	record.label, record.baseUrl, record.authStyle = "Keep my name", "https://changed.fixture/v1", "none"
	assert(f.env.require("provider/preset").apply(record, "hcnsec"))
	check("only the personal key remains", record.apiKey == "synthetic-personal-key" and record.keyNames[1] == "Work"
		and record.keyIds[1] == personalId and record.keyMode == "single" and record.selectedKey == 1 and keys.validate(record))
	check("personal setup keeps the name and requires an account model", record.label == "Keep my name"
		and record.preset == "hcnsec" and record.model == "" and record.communityCredential == nil)
	f.healthy(); f.close()
end)

case("public credentials cannot follow an edited draft into a custom endpoint", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free")
	record.baseUrl, record.authStyle, record.wsUrl = "https://edited.fixture/v1", "x-api-key", "wss://edited.fixture/socket"
	assert(f.env.require("provider/preset").apply(record, "custom"))
	check("community credentials and their reference are removed", record.apiKey == "" and record.communityCredential == nil
		and record.communityKeyState == nil and record.wsUrl == "" and record.baseUrl == "")
	check("a custom connection must be completed explicitly", not registry.validate(record))
	f.healthy(); f.close()
end)

case("reselecting Free preserves pauses and rejected transitions leave the draft intact", function()
	local f = F.new(); local registry, keys = f.env.require("provider/registry"), f.env.require("runtime/provider_keys")
	local record = registry.blank("projectuai-free")
	assert(keys.setPaused(record, 1, true)); local id = record.keyIds[1]
	assert(f.env.require("provider/preset").apply(record, "projectuai-free"))
	check("reselecting never silently resumes access", record.keyPaused[1] and record.keyIds[1] == id)
	record.keyPaused = { "damaged" }; local previous = record.apiKey
	local ok = f.env.require("provider/preset").apply(record, "hcnsec")
	check("invalid key metadata cannot partially apply another preset", not ok and record.preset == "projectuai-free"
		and record.apiKey == previous and record.keyPaused[1] == "damaged")
	check("unknown choices cannot mutate a draft", not f.env.require("provider/preset").apply(record, "missing") and record.apiKey == previous)
	f.healthy(); f.close()
end)

case("invalid device clocks return actionable countdowns without throwing", function()
	local f = F.new(); local record = f.env.require("provider/registry").blank("projectuai-free")
	local community = f.env.require("provider/community_key")
	for _, now in ipairs({ math.huge, -math.huge, 0 / 0, "invalid" }) do
		local status = community.countdown(record, now)
		check("invalid clock cannot claim access or a remaining duration", status and not status.open
			and status.text == "Check device clock" and status.ms == nil)
	end
	f.healthy(); f.close()
end)

suite.finish()
