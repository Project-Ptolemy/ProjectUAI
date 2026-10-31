-- Saved provider workflows use exact identities and never send inference.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider quality of life")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new()
	f.config, f.registry = f.env.require("runtime/config"), f.env.require("provider/registry")
	f.record = f.registry.blank("ollama")
	f.record.model, f.record.models = "first", { "first", "second", "third" }
	assert(f.registry.save(f.record))
	return f
end

case("favorite and recent shortcuts belong to each saved connection", function()
	local f = fixture(); local prefs = f.env.require("provider/model_preferences")
	assert(prefs.setFavorite(f.record, "third", true))
	assert(f.registry.setModel(f.record.id, "second"))
	local ordered = prefs.ordered(f.record, f.record.models)
	check("favorites lead recents without changing the saved catalog", ordered[1] == "third" and ordered[2] == "second" and f.record.models[1] == "first")
	check("another connection has independent favorites", not prefs.favorite({ id = "another" }, "third"))
	for index = 1, 15 do assert(f.registry.setModel(f.record.id, "recent-" .. index)) end
	local recent = f.config.get("ui.recentModels")[f.record.id]
	check("recent history stays bounded and newest first", #recent == 12 and recent[1] == "recent-15" and recent[12] == "recent-4")
	assert(f.registry.remove(f.record.id))
	check("removal cleans both shortcut buckets", f.config.get("ui.modelFavorites")[f.record.id] == nil and f.config.get("ui.recentModels")[f.record.id] == nil)
	check("shortcuts send no requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("favorite limits and malformed model settings do not mutate preferences", function()
	local f = fixture(); local prefs = f.env.require("provider/model_preferences")
	local favorites = {}; for index = 1, 100 do favorites["model-" .. index] = true end
	f.config.set("ui.modelFavorites", { [f.record.id] = favorites })
	check("the limit keeps existing favorites editable", not prefs.setFavorite(f.record, "overflow", true) and prefs.setFavorite(f.record, "model-1", false))
	check("a released favorite slot can be reused", prefs.setFavorite(f.record, "new", true))
	local overrides = f.env.require("provider/model_overrides")
	assert(overrides.context("first", "200000")); assert(overrides.sampling("first", "omit"))
	for _, value in ipairs({ "nan", "-1", "10000001", "infinity" }) do check("bad context leaves the previous claim", not overrides.context("first", value) and f.config.get("agent.forceContext").first == 200000) end
	check("invalid model text cannot write a capability claim", not overrides.reasoning("bad\0id", true))
	assert(overrides.sampling("first", "auto")); assert(overrides.context("first", ""))
	check("automatic settings remove explicit overrides", f.config.get("agent.forceSampling").first == nil and f.config.get("agent.forceContext").first == nil)
	f.healthy(); f.close()
end)

case("bulk key replacement keeps surviving metadata and accounting", function()
	local f = fixture(); local keys = f.env.require("runtime/provider_keys")
	assert(keys.add(f.record, "fixture-a\nfixture-b"))
	assert(keys.rename(f.record, 2, "Work")); assert(keys.setMode(f.record, "single", 2)); assert(keys.setPaused(f.record, 1, true))
	local id = keys.keyId(f.record, 2)
	assert(keys.setPool(f.record, "fixture-b\nfixture-c\nfixture-b"))
	check("deduplication retains the pinned surviving key", #keys.keys(f.record) == 2 and keys.selected(f.record) == 1 and keys.mode(f.record) == "single")
	check("retained key keeps name and accounting", keys.entries(f.record)[1].name == "Work" and keys.keyId(f.record, 1) == id)
	check("new keys start active with distinct accounting", not keys.paused(f.record, 2) and keys.keyId(f.record, 2) ~= id)
	assert(keys.setPool(f.record, "fixture-c"))
	check("removing a pinned key returns to rotation", keys.mode(f.record) == "rotate")
	f.healthy(); f.close()
end)

case("duplicate setup omits credentials and remains an unsaved draft", function()
	local f = fixture(); local actions = f.env.require("provider/connection_actions")
	f.record.baseUrl = "https://copy.fixture/v1?private=fixture-url-secret"
	f.record.apiKey = "fixture-personal-secret"
	f.record.headers, f.record.params, f.record.query = { opaque = "fixture-header-secret" }, { opaque = "fixture-body-secret" }, { opaque = "fixture-query-secret" }
	local draft = assert(actions.duplicate(f.record))
	local text = f.h.json.encode(draft)
	check("draft retains endpoint and model with a new identity", draft.id == "" and draft.model == f.record.model and draft.baseUrl == "https://copy.fixture/v1")
	check("all custom credential containers are absent", draft.apiKey == "" and next(draft.headers) == nil and next(draft.params) == nil and next(draft.query) == nil and not text:find("secret", 1, true))
	check("copying never installs or edits the source", f.registry.count() == 1 and f.record.apiKey == "fixture-personal-secret" and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("compatibility reset preserves quota cooldowns and accepted ownership", function()
	local f = fixture(); local actions = f.env.require("provider/connection_actions")
	f.record.repairs, f.record.repairScope = { "temperature" }, f.registry.compatibilityKey(f.record)
	f.record.maxTokensCap, f.record.toolsCap = { model = "first", tokens = 100 }, { model = "first", limit = 4 }
	f.record.keyRotation = { index = 2, cooldowns = { ["fixture-key"] = 9999999999999 } }
	f.record.health.cooldownUntil = 9999999999999
	local rotation, health = f.record.keyRotation, f.record.health
	local owner = f.env.require("provider/sampling").owner(f.record)
	assert(actions.resetLearned(f.record))
	check("only learned request repairs are cleared", not actions.hasLearned(f.record) and f.record.keyRotation == rotation and f.record.health == health)
	check("cooldown and accepted record ownership remain intact", f.registry.cooling(f.record) and owner() and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("browser provider saves keep key metadata and reject removed connections", function()
	local f = fixture(); local keys = f.env.require("runtime/provider_keys")
	assert(keys.add(f.record, "fixture-a\nfixture-b")); assert(keys.rename(f.record, 2, "Work"))
	assert(keys.setMode(f.record, "single", 2)); local keyId = keys.keyId(f.record, 2)
	f.loaded["agent/session"] = { current = function() return {} end }
	local commands = f.env.require("net/bridge_commands")
	commands.run({ type = "provider:save", provider = { id = f.record.id, apiKey = "fixture-b\nfixture-c" } })
	local saved = f.registry.get(f.record.id)
	check("browser saves preserve retained key identity and name", keys.keyId(saved, 1) == keyId and keys.entries(saved)[1].name == "Work" and keys.mode(saved) == "single")
	assert(f.registry.remove(saved.id))
	local ok, why = pcall(commands.run, { type = "provider:save", provider = { id = saved.id, preset = "ollama", model = "first" } })
	check("a stale browser form cannot recreate a removed provider", not ok and tostring(why):find("removed", 1, true) and f.registry.count() == 0)
	f.healthy(); f.close()
end)

case("authorization scheme case does not lose key usage attribution", function()
	local f = fixture(); local keys = f.env.require("runtime/provider_keys")
	f.record.authStyle = "bearer"; assert(keys.add(f.record, "fixture-counted-key"))
	local accounting = f.env.require("runtime/request_accounting")
	local tracker = accounting.new(f.record)
	tracker.dispatch("fixture-counted-key", { authorization = "bEaReR fixture-counted-key" })
	check("the actual matching key receives the request", tracker.latest.keyId == keys.keyId(f.record, 1))
	tracker.dispatch("fixture-counted-key", { Authorization = "Bearer different-key" })
	check("overridden authentication never attributes the wrong key", tracker.latest.keyId == nil)
	f.healthy(); f.close()
end)

suite.finish()
