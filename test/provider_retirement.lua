-- Legacy provider migration, using synthetic credentials and real storage codecs.
-- A deterministic digest fixture exercises known-key removal without shipping a key.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider retirement")
local case, check = suite.case, suite.check
local FIXTURE = "sk-" .. string.rep("R", 48)
local PASSWORD = "several unrelated fixture words"
local function setup()
	local f = F.new()
	local sha = f.env.require("runtime/credential_sha256")
	local digest = sha.digest
	local known = ("f232d4b8afbc789840ecf32fabf265c495cf4cafb877dd59c8c583c277392f48"):gsub("..", function(pair) return string.char(tonumber(pair, 16)) end)
	sha.digest = function(value, ...)
		if value == FIXTURE then return known end
		return digest(value, ...)
	end
	local crypto = f.env.require("runtime/credential_crypto")
	crypto.derive = function(password, salt)
		return digest(password .. "\0" .. salt) .. digest(salt .. "\0" .. password)
	end
	f.config, f.util = f.env.require("runtime/config"), f.env.require("runtime/util")
	f.config.load()
	f.retirement, f.providers = f.env.require("runtime/provider_retirement"), f.env.require("provider/registry")
	function f.snapshot() return f.util.deepCopy(f.config.defaults) end
	function f.finish() f.healthy(); f.close() end
	return f
end
local function record(id, preset, key)
	return { id = id, preset = preset, label = "Account " .. id, baseUrl = "https://gateway.fixture/v1",
		api = "openai", authStyle = "bearer", apiKey = key or "", enabled = true, order = 1,
		model = "my-model", models = { "my-model" }, keyMode = "rotate", selectedKey = 1 }
end
local function reference(id, preset)
	local value = record(id, preset or "projectuai-free")
	value.baseUrl = "https://api.hcnsec.cn/v1"
	value.communityCredential = true
	return value
end

case("retired provider cards and provisioning modules are absent", function()
	local f = setup(); local catalog = f.env.require("provider/catalog")
	check("neither retired preset can be selected", catalog.get("projectuai-free") == nil and catalog.get("hcnsec") == nil)
	check("blank fallback contains no bundled authentication or guessed model", f.providers.blank("projectuai-free").preset == "custom"
		and f.providers.blank("custom").apiKey == "" and f.providers.blank("custom").model == "")
	for _, path in ipairs({ "src/provider/free.lua", "src/provider/free_route.lua", "src/provider/community_key.lua", "src/runtime/community_credential.lua" }) do
		local file = io.open(path, "rb"); if file then file:close() end
		check("removed module stays absent " .. path, file == nil)
	end
	check("startup stays empty without contacting providers", #f.providers.list() == 0 and f.h.http.requestCount == 0)
	f.finish()
end)

case("load retires references and repairs only removed provider preferences", function()
	local f = setup(); local snapshot = f.snapshot()
	local community = reference("retired")
	local private = record("personal", "hcnsec", "private-one\nprivate-two")
	private.label, private.enabled, private.order = "My personal account", false, 7
	private.keyNames, private.keyPaused, private.keyMode, private.selectedKey = { "Primary", "Backup" }, { true, false }, "single", 2
	private.keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" }
	local other = record("other", "custom", "other-private-key"); other.order = 3
	snapshot.providers = { active = community.id, list = { community, private, other } }
	snapshot.agent.autoFreeRouting = true
	snapshot.ui.modelFavorites = { retired = { auto = true }, personal = { ["my-model"] = true } }
	snapshot.ui.recentModels = { retired = { "auto" }, other = { "my-model" } }
	f.config.load(snapshot)
	local migrated = assert(f.providers.get("personal"))
	check("community route is removed and next enabled account is selected", f.providers.get("retired") == nil and f.config.get("providers.active") == "other")
	check("personal route becomes custom without changing its owner or policy", migrated.preset == "custom" and migrated.id == "personal"
		and migrated.label == private.label and not migrated.enabled and migrated.order == 7 and migrated.model == private.model)
	check("personal credentials and aligned metadata stay exact", migrated.apiKey == private.apiKey and migrated.keyNames[2] == "Backup"
		and migrated.keyPaused[1] and migrated.selectedKey == 2 and migrated.keyMode == "single" and migrated.keyIds[2] == private.keyIds[2])
	check("only removed shortcuts and routing settings disappear", f.config.get("agent.autoFreeRouting") == nil
		and f.config.data.ui.modelFavorites.retired == nil and f.config.data.ui.recentModels.retired == nil
		and f.config.data.ui.modelFavorites.personal["my-model"] and f.config.data.ui.recentModels.other[1] == "my-model")
	check("migration is idempotent and sends no requests", f.retirement.apply(f.config.data) == 0 and f.h.http.requestCount == 0)
	f.finish()
end)

case("copied known keys are removed from mixed pools and custom credential maps", function()
	local f = setup(); local snapshot = f.snapshot()
	local mixed = record("mixed", "hcnsec", "personal-a\n" .. FIXTURE .. "\npersonal-b")
	mixed.keyNames, mixed.keyPaused, mixed.keyMode, mixed.selectedKey = { "First", "Retired", "Last" }, { true, false, false }, "single", 3
	mixed.keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333" }
	mixed.headers = { Authorization = "Bearer " .. FIXTURE, ["X-Personal"] = "keep" }
	mixed.query = { token = FIXTURE, route = "keep" }
	mixed.params = { auth = { token = FIXTURE, ordinary = true }, temperature = 0.25 }
	mixed.baseUrl = "https://gateway.fixture/v1?key=" .. FIXTURE .. "&route=keep"
	mixed.keyRotation = { index = 2, cooldowns = { [FIXTURE] = 123 } }
	local copied = record("copied", "custom", FIXTURE)
	local pinned = f.util.deepCopy(mixed); pinned.id, pinned.selectedKey = "pinned", 2
	local fragment = record("fragment", "custom", "personal-fragment-key")
	fragment.baseUrl = "https://gateway.fixture/v1?route=keep#token=" .. FIXTURE
	snapshot.providers = { active = "mixed", list = { mixed, copied, pinned, fragment } }
	snapshot.identity.extraHeaders = { Authorization = "Bearer " .. FIXTURE, ["X-Identity"] = "keep" }
	f.config.load(snapshot)
	mixed = assert(f.providers.get("mixed")); pinned = assert(f.providers.get("pinned"))
	check("mixed pool loses only the known credential", mixed.apiKey == "personal-a\npersonal-b" and mixed.keyNames[2] == "Last"
		and mixed.keyPaused[1] and mixed.keyIds[2] == "33333333-3333-4333-8333-333333333333" and mixed.selectedKey == 2 and mixed.keyMode == "single")
	check("a retired selected credential requires reviewed access to surviving keys", pinned.keyMode == "rotate" and pinned.selectedKey == 1
		and pinned.credentialsOmitted == true and f.providers.protocolProblem(pinned) ~= nil)
	check("header query body and URL copies disappear while ordinary fields remain", mixed.headers.Authorization == nil and mixed.headers["X-Personal"] == "keep"
		and mixed.query.token == nil and mixed.query.route == "keep" and mixed.params.auth.token == nil and mixed.params.auth.ordinary
		and mixed.params.temperature == 0.25 and mixed.baseUrl == "https://gateway.fixture/v1?route=keep" and mixed.keyRotation == nil)
	check("removing a copied fragment leaves ordinary URL query settings intact", f.providers.get("fragment").baseUrl == "https://gateway.fixture/v1?route=keep"
		and f.providers.get("fragment").apiKey == "personal-fragment-key")
	check("copied credentials cannot become anonymous inference", f.providers.get("copied").apiKey == "" and f.providers.get("copied").credentialsOmitted
		and f.providers.protocolProblem(f.providers.get("copied")) ~= nil)
	check("identity copies are removed without touching other identity settings", f.config.data.identity.extraHeaders.Authorization == nil
		and f.config.data.identity.extraHeaders["X-Identity"] == "keep")
	check("saved configuration no longer contains a usable copy", f.config.saveNow(true) and not f.h.files["UAI/config.json"]:find(FIXTURE, 1, true)
		and not f.retirement.hasKey(f.env.require("runtime/credentials").restore(f.config.data)))
	check("matching uses exact fingerprints", not f.retirement.retiredKey("sk-" .. string.rep("S", 48)))
	assert(f.providers.save(pinned, { credentialsRestored = true }))
	check("explicit connection Save can authorize the retained personal keys", pinned.credentialsOmitted == nil and f.providers.protocolProblem(pinned) == nil)
	f.finish()
end)

case("encoded imports and direct replacement cannot resurrect retired access", function()
	local f = setup(); local snapshot = f.snapshot()
	local old = reference("old", "hcnsec")
	local fields = { apiKey = "", keyMode = "rotate", selectedKey = 1,
		communityKeyState = { revision = "legacy", keyNames = { "Included" } } }
	old.storedCredentials = assert(f.env.require("runtime/credential_codec").encode({ kind = "provider", fields = fields }))
	snapshot.providers = { active = old.id, list = { old } }
	snapshot.agent.autoFreeRouting = false
	local transfer = f.env.require("runtime/config_transfer")
	local preview = assert(transfer.preview(f.util.encode({ format = transfer.FORMAT, version = transfer.VERSION, config = snapshot, credentialsIncluded = true })))
	check("preview shows an empty provider list after legacy decoding", #preview.config.providers.list == 0 and preview.summary.providers == 0)
	assert(transfer.apply(preview))
	check("import persists an empty setup", #f.providers.list() == 0 and f.config.get("providers.active") == "")
	assert(f.config.replace(snapshot))
	check("raw replacement also decodes and removes legacy records", #f.providers.list() == 0 and f.config.get("agent.autoFreeRouting") == nil)
	local saved = f.h.files["UAI/config.json"]; f.config.load()
	check("restart and repeat migration leave the saved setup unchanged", #f.providers.list() == 0 and f.retirement.apply(f.config.data) == 0 and f.h.files["UAI/config.json"] == saved)
	check("old host settings cannot restore removed behavior", f.config.set("agent.autoFreeRouting", true) == nil)
	f.finish()
end)

case("legacy encrypted vault remains authentic until unlock then migrates atomically", function()
	local f = setup(); local snapshot = f.snapshot()
	local community = reference("vault-community")
	local rawOnly = record("vault-raw", "hcnsec")
	rawOnly.baseUrl = "https://api.hcnsec.cn/v1"
	local private = record("vault-personal", "hcnsec", "private-a\n" .. FIXTURE .. "\nprivate-b")
	private.keyNames, private.keyPaused, private.keyMode, private.selectedKey = { "First", "Included", "Last" }, { false, true, false }, "single", 3
	private.keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333" }
	local vault = f.env.require("runtime/credential_vault")
	local envelope, key = f.run(function() return vault.create(PASSWORD) end)
	local payload = { version = 1, providers = {
		{ id = community.id, fields = { apiKey = "", baseUrl = community.baseUrl, keyMode = "rotate", selectedKey = 1, communityKeyState = { revision = "legacy" } } },
		{ id = rawOnly.id, fields = { apiKey = FIXTURE, baseUrl = rawOnly.baseUrl, keyMode = "rotate", selectedKey = 1 } },
		{ id = private.id, fields = { apiKey = private.apiKey, baseUrl = private.baseUrl, keyNames = private.keyNames, keyPaused = private.keyPaused,
			keyMode = private.keyMode, selectedKey = private.selectedKey, keyIds = private.keyIds } },
	}, identity = {} }
	snapshot.credentialVault = assert(vault.seal(envelope, key, payload))
	private.apiKey, private.keyNames, private.keyPaused, private.keyIds, private.keyMode, private.selectedKey = "", nil, nil, nil, "rotate", 1
	snapshot.providers = { active = community.id, list = { community, private, rawOnly } }
	snapshot.ui.modelFavorites = { [rawOnly.id] = { ["my-model"] = true } }
	local public = f.env.require("runtime/credentials").sanitise(snapshot)
	check("a public encrypted copy removes known references before discarding the vault", public.credentialVault == nil
		and #public.providers.list == 2 and public.providers.active == private.id)
	check("opaque personal payloads remain guarded in a public copy", public.providers.list[1].preset == "custom"
		and public.providers.list[1].credentialsOmitted == true and public.providers.list[2].credentialsOmitted == true)
	f.config.load(snapshot)
	check("locked vault retains all authenticated provider identities", f.config.vaultStatus().locked and #f.config.data.providers.list == 3)
	local before = f.util.encode(f.config.data.credentialVault)
	check("wrong password never filters data or releases keys", not f.run(function() return f.config.unlockVault("wrong unrelated fixture words") end)
		and #f.config.data.providers.list == 3 and f.util.encode(f.config.data.credentialVault) == before)
	assert(f.run(function() return f.config.unlockVault(PASSWORD) end))
	local migrated = assert(f.providers.get(private.id))
	check("successful unlock removes community and retains exact personal credentials", #f.config.data.providers.list == 1 and migrated.preset == "custom"
		and migrated.apiKey == "private-a\nprivate-b" and migrated.baseUrl == private.baseUrl and migrated.keyNames[2] == "Last" and migrated.keyIds[2] == "33333333-3333-4333-8333-333333333333"
		and migrated.keyMode == "single" and migrated.selectedKey == 2)
	check("migrated ciphertext authenticates its current provider identities immediately", f.env.require("runtime/credentials").openVault(f.config.data,
		vault.key(f.config.data.credentialVault)) ~= nil)
	check("raw-only included identities and shortcuts are removed after authentication", f.providers.get(rawOnly.id) == nil
		and f.config.data.ui.modelFavorites[rawOnly.id] == nil)
	assert(f.config.saveNow(true)); f.config.load()
	assert(f.run(function() return f.config.unlockVault(PASSWORD) end))
	check("cold restart restores the migrated vault without a second retirement", #f.config.data.providers.list == 1
		and f.providers.get(private.id).apiKey == "private-a\nprivate-b" and f.retirement.apply(f.config.data) == 0)
	assert(vault.activate(key, snapshot.credentialVault))
	local handoff = assert(vault.handoff(snapshot.credentialVault))
	f.config.requireVault(); f.config.load(snapshot, handoff)
	check("migrated handoff retains its password challenge and matching payload IDs", not f.config.vaultStatus().ready
		and #f.config.data.providers.list == 1 and f.env.require("runtime/credentials").openVault(f.config.data, vault.key(f.config.data.credentialVault)) ~= nil)
	assert(f.run(function() return f.config.unlockVault(PASSWORD) end))
	check("required warm reauthentication succeeds after migration", f.config.vaultStatus().ready and f.providers.get(private.id).apiKey == "private-a\nprivate-b")
	f.finish()
end)

case("personal URL credentials and custom guidance survive while cyclic maps terminate", function()
	local f = setup(); local snapshot = f.snapshot()
	local userinfo, query = reference("userinfo"), reference("url-query")
	userinfo.baseUrl, userinfo.note, userinfo.requires = "https://user:personal-password@gateway.fixture/v1", "My connection guidance", "executor"
	query.baseUrl = "https://gateway.fixture/v1?api_key=personal-url-key"
	query.params = { token = FIXTURE }; query.params.self = query.params
	snapshot.providers = { active = userinfo.id, list = { userinfo, query } }
	check("cyclic credential maps can be migrated without recursion failure", f.retirement.apply(snapshot) > 0 and query.params.token == nil and query.params.self == query.params)
	check("URL-auth-only accounts remain custom with their personal data", #snapshot.providers.list == 2 and userinfo.preset == "custom" and query.preset == "custom"
		and userinfo.baseUrl:find("personal-password", 1, true) and query.baseUrl:find("personal-url-key", 1, true)
		and userinfo.note == "My connection guidance" and userinfo.requires == "executor")
	check("cyclic scan is idempotent", f.retirement.apply(snapshot) == 0 and not f.retirement.hasKey(query))
	f.finish()
end)

case("ambiguous edited authentication is preserved for review while pure known copies disappear", function()
	local f = setup(); local snapshot = f.snapshot()
	local header, body, custom, pure = reference("custom-header"), reference("body-auth"), reference("custom-host"), reference("pure")
	header.headers = { ["X-Auth-Token"] = "personal-header-token" }
	body.params = { credential = { private = "personal-body-token" } }
	custom.baseUrl, custom.authStyle = "http://localhost:11434/v1", "none"
	pure.apiKey, pure.headers, pure.params = FIXTURE, { Authorization = "Bearer " .. FIXTURE }, { credential = { token = FIXTURE } }
	snapshot.providers = { active = pure.id, list = { header, body, custom, pure } }
	f.config.load(snapshot)
	check("known-only credentials do not leave an empty ambiguous body behind", f.providers.get(pure.id) == nil)
	for _, id in ipairs({ header.id, body.id, custom.id }) do
		local value = assert(f.providers.get(id))
		check("edited record is retained as custom pending review " .. id, value.preset == "custom"
			and value.credentialsOmitted == true and f.providers.protocolProblem(value) ~= nil)
	end
	check("unrecognized personal authentication stays exact", f.providers.get(header.id).headers["X-Auth-Token"] == "personal-header-token"
		and f.providers.get(body.id).params.credential.private == "personal-body-token")
	check("migration sends no unreviewed request", f.h.http.requestCount == 0)
	f.finish()
end)

case("malformed sparse lists survive migration until import validation rejects them", function()
	local f = setup(); local snapshot = f.snapshot()
	snapshot.providers.list = { [1] = reference("first"), [3] = record("third", "custom", "personal-key") }
	snapshot.providers.active = "first"
	check("migration does not flatten or delete malformed records", f.retirement.apply(snapshot) == 0 and snapshot.providers.list[3].apiKey == "personal-key")
	check("normal import validation rejects the sparse shape", f.env.require("runtime/config_transfer").validate(snapshot) == nil)
	f.finish()
end)

case("reviewed Save preserves guards on failure and admits supported zero-key Zen on success", function()
	local f = setup(); local failed = record("failed-review", "custom")
	failed.credentialsOmitted = true
	check("failed reviewed validation cannot clear the live admission guard", not f.providers.save(failed, { credentialsRestored = true })
		and failed.credentialsOmitted == true and f.providers.get(failed.id) == nil)
	local zen = f.providers.blank("zen")
	zen.model, zen.models, zen.credentialsOmitted = "hy4-flash-free", { "hy4-flash-free" }, true
	assert(f.providers.save(zen, { credentialsRestored = true }))
	check("successful review can use the supported direct free API without a saved key", zen.apiKey == "" and zen.credentialsOmitted == nil
		and f.providers.protocolProblem(zen) == nil and f.h.http.requestCount == 0)
	f.finish()
end)

case("unreadable legacy envelopes retain recovery data and block requests", function()
	local f = setup(); local snapshot = f.snapshot()
	local old = reference("unreadable")
	old.storedCredentials = { version = 99, bytes = "unreadable-fixture" }
	snapshot.providers = { active = old.id, list = { old } }
	f.config.load(snapshot)
	local saved = assert(f.providers.get(old.id))
	check("future envelope remains recoverable without empty-key replacement", saved.storedCredentials.version == 99
		and saved.credentialStorageError ~= nil and f.providers.protocolProblem(saved) ~= nil)
	check("failed decoding sends no provider requests", f.h.http.requestCount == 0)
	f.finish()
end)

suite.finish()
