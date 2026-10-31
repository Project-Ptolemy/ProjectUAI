-- Credential policy, migration and leak regressions with synthetic data only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Credential storage")
local case, check = suite.case, suite.check

local function setup()
	local f = F.new()
	local config = f.env.require("runtime/config")
	local util = f.env.require("runtime/util")
	local snapshot = util.deepCopy(config.defaults)
	snapshot.providers = { active = "private", list = { {
		id = "private", label = "Test provider", preset = "custom", api = "openai", authStyle = "bearer",
		baseUrl = "https://url-user:url-password@example.invalid/v1?opaque=url-secret#fragment-secret",
		wsUrl = "wss://socket-user:socket-password@example.invalid/ws?opaque=socket-secret",
		apiKey = "first-private-key\nsecond-private-key", keyNames = { "Primary", "Backup" }, keyPaused = { false, true },
		keyMode = "single", selectedKey = 2,
		keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" },
		headers = { ["X-Arbitrary"] = "header-secret" }, query = { opaque = "query-secret" },
		params = { opaque = "body-secret", nested = { ["body-map-secret"] = true } },
		keyRotation = { index = 2, cooldowns = { ["first-private-key"] = 12345 } },
		repairScope = "https://example.invalid?opaque=scope-secret", repairs = { sample = true },
		maxTokensCap = { tokens = 1234, scope = "cap-scope-secret" }, toolsCap = { limit = 4, scope = "tools-scope-secret" },
		health = { lastError = "raw-error-secret", ok = 1 }, model = "test-model", models = { "test-model" },
	} } }
	snapshot.identity.extraHeaders = { ["X-Arbitrary"] = "identity-secret" }
	snapshot.bridge.token, snapshot.relay.token = "bridge-secret", "relay-secret"
	snapshot.memory.entries = { { key = "preference", value = "Keep ordinary settings", at = 123 } }
	snapshot.extension = { token = "extension-secret", enabled = true }
	return f, config, util, snapshot
end

local PRIVATE = { "first-private-key", "second-private-key", "url-user", "url-password", "url-secret", "fragment-secret",
	"socket-user", "socket-password", "socket-secret", "header-secret", "query-secret", "body-secret", "body-map-secret",
	"scope-secret", "cap-scope-secret", "tools-scope-secret", "raw-error-secret", "identity-secret" }
local function excludes(body, values)
	for _, value in ipairs(values) do if body:find(value, 1, true) then return false end end
	return true
end
local function same(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in pairs(left) do if not same(value, right[key]) then return false end end
	for key in pairs(right) do if left[key] == nil then return false end end
	return true
end
local function saveProvider(registry, record, options)
	local ok, why = registry.save(record, options)
	assert(ok, type(why) == "table" and table.concat(why, "; ") or tostring(why))
end

case("new installs remember encoded credentials and reconstruct them on cold load", function()
	local f, config, util, snapshot = setup()
	config.load()
	check("fresh default remembers provider credentials", config.get("security.rememberCredentials") == true)
	config.data = snapshot
	assert(config.saveNow())
	local raw = f.h.files["UAI/config.json"]
	local stored = util.decode(raw)
	check("remembered provider and identity fields use encoded envelopes", type(stored.providers.list[1].storedCredentials) == "table"
		and type(stored.identity.storedCredentials) == "table" and stored.providers.list[1].apiKey == "")
	check("raw JSON omits all credential strings including duplicate scopes", excludes(raw, PRIVATE))
	local expected = util.deepCopy(snapshot)
	expected.providers.list[1].keyRotation = nil
	config.load()
	check("cold load reconstructs exact keys, pool metadata and custom connection settings", same(config.data, expected)
		and config.storageError == nil and config.data.providers.list[1].storedCredentials == nil)
	check("cold-load rewrite stays encoded", excludes(f.h.files["UAI/config.json"], PRIVATE))
	check("bridge and relay pairing are unchanged", config.data.bridge.token == "bridge-secret" and config.data.relay.token == "relay-secret")
	f.healthy(); f.close()
end)

case("optional session-only storage omits connection credentials", function()
	local f, config, util, snapshot = setup()
	config.load()
	snapshot.security.rememberCredentials = false
	config.data = snapshot
	assert(config.saveNow())
	local raw = f.h.files["UAI/config.json"]
	local saved = util.decode(raw)
	check("disk contains no private provider credential copies", excludes(raw, PRIVATE))
	check("connector pairing is unchanged", saved.bridge.token == "bridge-secret" and saved.relay.token == "relay-secret")
	check("live keys, policy and custom connection values survive", config.data == snapshot and snapshot.providers.list[1].apiKey:find("first-private-key", 1, true)
		and snapshot.providers.list[1].selectedKey == 2 and snapshot.providers.list[1].headers["X-Arbitrary"] == "header-secret")
	check("stripped provider remains valid to import", f.env.require("runtime/config_transfer").validate(saved) ~= nil)
	check("stripped provider clearly requires credentials", saved.providers.list[1].credentialsOmitted == true)
	check("ordinary settings remain intact", saved.memory.entries[1].key == "preference" and saved.providers.list[1].model == "test-model")
	config.load()
	local record = config.data.providers.list[1]
	check("cold restart cannot restore session credentials", record.apiKey == "" and record.keyIds == nil and record.selectedKey == 1)
	local registry = f.env.require("provider/registry")
	check("missing credentials fail before transport", registry.protocolProblem(record):find("not saved", 1, true) ~= nil)
	registry.save(record, { force = true })
	check("background saves cannot clear the omission guard", record.credentialsOmitted == true)
	assert(f.env.require("runtime/provider_keys").add(record, "replacement-key"))
	saveProvider(registry, record, { credentialsRestored = true })
	check("explicit credential entry restores admission", record.credentialsOmitted == nil and registry.protocolProblem(record) == nil)
	f.healthy(); f.close()
end)

case("legacy migration encodes existing pools before optional session-only choice", function()
	local f, config, util, snapshot = setup()
	snapshot.security = nil
	f.h.files["UAI/config.json"] = util.encode(snapshot)
	config.load()
	local record = config.data.providers.list[1]
	check("legacy saved credentials remain remembered", config.get("security.rememberCredentials") == true)
	check("legacy ordered pool metadata is intact", record.apiKey == snapshot.providers.list[1].apiKey and record.selectedKey == 2
		and record.keyIds[2] == snapshot.providers.list[1].keyIds[2] and record.keyPaused[2] and record.keyNames[2] == "Backup")
	check("legacy load automatically rewrites raw credentials as encoded data", excludes(f.h.files["UAI/config.json"], PRIVATE)
		and type(util.decode(f.h.files["UAI/config.json"]).providers.list[1].storedCredentials) == "table" and config.storageError == nil)
	assert(config.saveNow())
	check("remembered mode removes duplicate transient rotation secrets", util.decode(f.h.files["UAI/config.json"]).providers.list[1].keyRotation == nil)
	assert(config.setRememberCredentials(false))
	check("switch removes saved copies without replacing live record", excludes(f.h.files["UAI/config.json"], PRIVATE)
		and config.data.providers.list[1] == record and record.apiKey == snapshot.providers.list[1].apiKey)
	config.set("ui.fontScale", 1.1)
	f.h.settle(1)
	check("later debounced saves never reintroduce credentials", excludes(f.h.files["UAI/config.json"], PRIVATE))
	assert(config.setRememberCredentials(true))
	check("remembering encodes the still-live keys without literal copies", f.env.require("runtime/credentials").restore(util.decode(f.h.files["UAI/config.json"])).providers.list[1].apiKey == record.apiKey
		and excludes(f.h.files["UAI/config.json"], PRIVATE))
	f.healthy(); f.close()
end)

case("failed or unverifiable storage changes never report success", function()
	local f, config, util, snapshot = setup()
	snapshot.security.rememberCredentials = true
	config.data = snapshot
	assert(config.saveNow())
	local fsx = f.env.require("runtime/fsx")
	local write = fsx.writeJson
	fsx.writeJson = function() return false, "private failure detail" end
	local ok, err = config.setRememberCredentials(false)
	check("write failure retains previous policy and live key", not ok and config.get("security.rememberCredentials") and config.data == snapshot
		and not err:find("private failure detail", 1, true))
	fsx.writeJson = function() return true end
	ok = config.setRememberCredentials(false)
	check("no-op host write is detected by readback", not ok and config.get("security.rememberCredentials"))
	fsx.writeJson = write
	fsx.enabled = false
	ok, err = config.setRememberCredentials(false)
	check("no filesystem cannot claim old files were cleared", not ok and err:find("Cannot verify", 1, true) ~= nil)
	f.healthy(); f.close()
end)

case("unreadable encoded credentials survive ordinary saves until explicit replacement", function()
	local f, config, util, snapshot = setup()
	local credentials = f.env.require("runtime/credentials")
	local stored = assert(credentials.persistent(snapshot))
	stored.providers.list[1].storedCredentials.version = 999
	local envelope = util.deepCopy(stored.providers.list[1].storedCredentials)
	f.h.files["UAI/config.json"] = util.encode(stored)
	config.load()
	local registry = f.env.require("provider/registry")
	local record = registry.list()[1]
	check("unsupported envelope blocks requests without exposing or deleting its bytes", record.credentialsOmitted == true
		and type(record.credentialStorageError) == "string" and same(record.storedCredentials, envelope)
		and registry.protocolProblem(record) ~= nil)
	local disabled, disableWhy = config.setRememberCredentials(false)
	check("session-only choice cannot claim unreadable data was removed", not disabled and type(disableWhy) == "string"
		and config.get("security.rememberCredentials") == true and same(record.storedCredentials, envelope))
	config.set("ui.fontScale", 1.1)
	f.h.settle(1)
	local saved = util.decode(f.h.files["UAI/config.json"])
	check("ordinary settings save preserves unsupported credential data exactly", same(saved.providers.list[1].storedCredentials, envelope)
		and excludes(f.h.files["UAI/config.json"], PRIVATE))
	local transfer = f.env.require("runtime/config_transfer")
	local before = config.data
	local beforeDisk = f.h.files["UAI/config.json"]
	local preview, why = transfer.preview(util.encode({ format = transfer.FORMAT, version = transfer.VERSION, config = saved }))
	check("unsupported encoded import is rejected without changing live or stored configuration", preview == nil and type(why) == "string"
		and config.data == before and f.h.files["UAI/config.json"] == beforeDisk)
	assert(f.env.require("runtime/provider_keys").add(record, "explicit-replacement-key"))
	saveProvider(registry, record, { credentialsRestored = true })
	assert(config.saveNow())
	local restored = credentials.restore(util.decode(f.h.files["UAI/config.json"]))
	check("explicit connection save replaces failed envelope with newly supplied credentials", record.storedCredentials == nil
		and record.credentialStorageError == nil and record.credentialsOmitted == nil
		and restored.providers.list[1].apiKey == "explicit-replacement-key"
		and restored.providers.list[1].credentialStorageError == nil)
	f.healthy(); f.close()
end)

case("encoding failures never fall back to plaintext writes", function()
	local f, config, util, snapshot = setup()
	config.data = snapshot
	assert(config.saveNow())
	local previous = f.h.files["UAI/config.json"]
	local codec = f.env.require("runtime/credential_codec")
	local encode = codec.encode
	codec.encode = function() return nil, "synthetic encoding failure" end
	local replacementPool = "never-write-this-private-key\nsecond-private-key"
	snapshot.providers.list[1].apiKey = replacementPool
	local ok, why = config.saveNow()
	check("failed encoding keeps the previous file and the newly entered live key", not ok and type(why) == "string"
		and f.h.files["UAI/config.json"] == previous and snapshot.providers.list[1].apiKey == replacementPool)
	local legacy = util.deepCopy(snapshot)
	legacy.security = nil
	local rawLegacy = util.encode(legacy)
	f.h.files["UAI/config.json"] = rawLegacy
	config.load()
	check("failed legacy migration retains its only file copy and reports the limitation", type(config.storageError) == "string"
		and f.h.files["UAI/config.json"] == rawLegacy and config.data.providers.list[1].apiKey == replacementPool)
	codec.encode = encode
	assert(config.saveNow())
	check("later successful save completes encoding without losing the key", not f.h.files["UAI/config.json"]:find("never-write-this-private-key", 1, true)
		and f.env.require("runtime/credentials").restore(util.decode(f.h.files["UAI/config.json"])).providers.list[1].apiKey == replacementPool)
	f.healthy(); f.close()
end)

case("default exports strip all connection credentials and imports keep local storage policy", function()
	local f, config, util, snapshot = setup()
	snapshot.security.rememberCredentials = true
	config.data = snapshot
	local transfer = f.env.require("runtime/config_transfer")
	local body, summary = assert(transfer.export())
	local exported = util.decode(body)
	check("default export strips provider and connector credentials", excludes(body, PRIVATE) and not body:find("bridge-secret", 1, true)
		and not body:find("relay-secret", 1, true) and not body:find("extension-secret", 1, true))
	check("default export declares exclusion and is importable", exported.credentialsIncluded == false and summary.credentialsIncluded == false
		and transfer.preview(body) ~= nil)
	check("export cannot mutate live settings", config.data == snapshot and config.data.providers.list[1].headers["X-Arbitrary"] == "header-secret")
	local private = assert(transfer.export({ includeCredentials = true }))
	check("explicit private transfer reconstructs key pool metadata from bytes", excludes(private, PRIVATE)
		and assert(transfer.preview(private)).config.providers.list[1].keyNames[2] == "Backup")
	assert(config.setRememberCredentials(false))
	local preview = assert(transfer.preview(private))
	check("preview reports this device storage policy", preview.summary.rememberCredentials == false)
	assert(transfer.apply(preview))
	check("private import keeps keys live without changing the session-only preference", config.get("security.rememberCredentials") == false
		and config.data.providers.list[1].apiKey:find("first-private-key", 1, true) and excludes(f.h.files["UAI/config.json"], PRIVATE))
	exported.config.providers.list[1].apiKey = "forged-key"
	local forged = assert(transfer.preview(util.encode(exported)))
	check("excluded label cannot smuggle credentials through preview", forged.config.providers.list[1].apiKey == "")
	f.healthy(); f.close()
end)

case("public included access survives storage and credential-free transfer", function()
	local f = F.new(); local config = f.env.require("runtime/config"); config.load()
	local registry = f.env.require("provider/registry")
	local community = f.env.require("provider/community_key")
	local free = registry.blank("projectuai-free"); saveProvider(registry, free)
	assert(config.saveNow()); config.load()
	check("public credential is available after cold restart", community.isApplied(registry.list()[1]))
	local transfer = f.env.require("runtime/config_transfer")
	local preview = assert(transfer.preview(assert(transfer.export())))
	check("export contains public reference without a key", preview.config.providers.list[1].apiKey == "" and preview.config.providers.list[1].communityCredential)
	assert(transfer.apply(preview))
	check("public reference restores included access", community.isApplied(registry.list()[1]))
	f.healthy(); f.close()
end)

case("URL cleaning handles imported noncanonical authorities", function()
	local f = F.new(); local credentials = f.env.require("runtime/credentials")
	for _, pair in ipairs({
		{ "  https://user:password@example.invalid/v1?opaque=secret#fragment  ", "https://example.invalid/v1" },
		{ "//user:password@example.invalid/v1?opaque=secret", "//example.invalid/v1" },
		{ "user:password@example.invalid/v1?opaque=secret", "example.invalid/v1" },
	}) do check("credentials removed from imported authority", credentials.cleanUrl(pair[1]) == pair[2]) end
	f.healthy(); f.close()
end)

case("global-header-only authentication cannot become an anonymous request after restart", function()
	local f = F.new(); local config = f.env.require("runtime/config"); config.load()
	assert(config.setRememberCredentials(false))
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.baseUrl, record.model, record.models, record.authStyle = "https://identity.fixture/v1", "test-model", { "test-model" }, "none"
	saveProvider(registry, record)
	config.set("identity.extraHeaders", { Authorization = "Bearer identity-only-secret" })
	assert(config.saveNow()); config.load()
	local loaded = registry.list()[1]
	check("global authentication omission blocks requests until connection review", loaded.credentialsOmitted == true
		and registry.protocolProblem(loaded):find("not saved", 1, true))
	check("global authentication is absent on disk", not f.h.files["UAI/config.json"]:find("identity-only-secret", 1, true))
	f.healthy(); f.close()
end)

case("included references at nonofficial endpoints never dispatch anonymously", function()
	local f = F.new(); local config = f.env.require("runtime/config"); config.load()
	local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free")
	record.baseUrl = "https://custom.fixture/v1"
	-- Simulate an older saved record; current setup rejects this combination.
	saveProvider(registry, record, { force = true })
	assert(config.setRememberCredentials(true))
	config.load()
	local loaded = registry.list()[1]
	check("a nonofficial reference cannot restore or send an empty key", loaded.apiKey == "" and loaded.communityCredential == true
		and registry.protocolProblem(loaded):find("official", 1, true))
	assert(f.env.require("runtime/provider_keys").add(loaded, "personal-custom-key"))
	loaded.preset = "custom"
	saveProvider(registry, loaded, { credentialsRestored = true })
	check("explicit personal credentials clear an unusable reference", not loaded.communityCredential and registry.protocolProblem(loaded) == nil)
	f.healthy(); f.close()
end)

case("encoded cold load supplies exact credentials to a real provider adapter", function()
	local f = F.new()
	local config = f.env.require("runtime/config"); config.load()
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.id, record.label = "encoded-request", "Encoded request fixture"
	record.baseUrl = "https://encoded-request.fixture/v1?route=request-url-value"
	record.model, record.models = "fixture-model", { "fixture-model" }
	record.apiKey = "request-paused-key\nrequest-selected-key\nrequest-other-key"
	record.keyNames, record.keyPaused = { "Paused", "Selected", "Other" }, { true, false, false }
	record.keyMode, record.selectedKey, record.stream = "single", 2, false
	record.headers = { ["X-Private-Header"] = "request-header-value" }
	record.query = { opaque = "request-query-value" }
	record.params = { custom_auth = "request-body-value", temperature = 0.27 }
	saveProvider(registry, record)
	config.set("identity.extraHeaders", { ["X-Private-Identity"] = "request-identity-value" })
	assert(config.saveNow())
	check("request fixture credentials are encoded on disk", excludes(f.h.files["UAI/config.json"], {
		"request-paused-key", "request-selected-key", "request-other-key", "request-header-value", "request-query-value",
		"request-body-value", "request-identity-value", "request-url-value" }))
	config.load()
	local restored = assert(registry.get(record.id))
	local requests = {}
	f.h.http.handler = function(entry)
		requests[#requests + 1] = entry
		return { StatusCode = 200, Body = f.h.json.encode({ choices = {
			{ message = { role = "assistant", content = "encoded credentials work" }, finish_reason = "stop" },
		} }) }
	end
	local response, why = f.run(function()
		return f.env.require("provider/chat").complete(restored, {
			messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1, maxTokens = 16,
		})
	end)
	check("restored provider completes one synthetic request", response and response.content == "encoded credentials work" and #requests == 1)
	local entry = requests[1]
	local get = f.env.require("net/headers").get
	local payload = assert(f.h.json.decode(entry.body))
	check("restored selection sends only the selected unpaused key", get(entry.headers, "Authorization") == "Bearer request-selected-key"
		and restored.keyPaused[1] == true and restored.selectedKey == 2)
	check("restored custom and identity headers reach the adapter", get(entry.headers, "X-Private-Header") == "request-header-value"
		and get(entry.headers, "X-Private-Identity") == "request-identity-value")
	check("restored URL and query fields reach the adapter", entry.url:find("/chat/completions?", 1, true) ~= nil
		and entry.url:find("route=request-url-value", 1, true) ~= nil and entry.url:find("opaque=request-query-value", 1, true) ~= nil)
	check("restored body overrides reach the adapter", payload.custom_auth == "request-body-value" and payload.temperature == 0.27)
	f.healthy(); f.close()
end)

suite.finish()
