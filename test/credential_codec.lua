-- Reversible packaging and restoration tests with synthetic credentials only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Credential byte codec")
local case, check = suite.case, suite.check
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end
local function snapshot(remember)
	return { security = remember ~= nil and { rememberCredentials = remember } or nil,
		providers = { active = "fixture", list = { {
			id = "fixture", label = "Visible provider", baseUrl = "https://codec.fixture/v1?token=dummy-url-secret",
			wsUrl = "wss://codec.fixture/socket?auth=dummy-socket-secret", authStyle = "bearer", model = "fixture-model",
			apiKey = "dummy-key-first\ndummy-key-second", keyNames = { "dummy-name-first", "dummy-name-second" },
			keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" },
			keyPaused = { true, false }, keyMode = "single", selectedKey = 2,
			headers = { Authorization = "Bearer dummy-header-secret", ["X-Private"] = "dummy-custom-secret" },
			query = { token = "dummy-query-secret" }, params = { secret = "dummy-body-secret", temperature = 0.25 },
			health = { ok = 2, lastError = "dummy-provider-error-secret" },
			repairs = { "dummy-repair-secret" }, repairScope = "dummy-repair-scope-secret",
			maxTokensCap = { model = "fixture-model", tokens = 100, scope = "dummy-output-scope-secret" },
			toolsCap = { model = "fixture-model", limit = 2, scope = "dummy-tools-scope-secret" },
			opencodeSession = "dummy-session-secret",
		} } }, identity = { claudeUa = true, extraHeaders = { ["X-Global-Auth"] = "dummy-identity-secret" } },
		bridge = { enabled = true, port = 8790, token = "bridge-fixture-kept", autoDiscover = true }, relay = { token = "relay-fixture-kept" } }
end

case("JSON values and every byte value roundtrip through bounded byte arrays", function()
	local f = F.new(); local codec = f.env.require("runtime/credential_codec")
	local values, text = {}, {}
	for byte = 0, 255 do
		values[#values + 1] = byte
		text[#text + 1] = byte < 128 and string.char(byte) or string.char(192 + math.floor(byte / 64), 128 + byte % 64)
	end
	local input = { values = values, text = table.concat(text), empty = {}, flags = { true, false } }
	local envelope = assert(codec.encode(input))
	check("codec identifies the supported packaging", envelope.version == 1 and envelope.encoding == "uai-bytes-v1")
	for _, byte in ipairs(envelope.data) do assert(type(byte) == "number" and byte % 1 == 0 and byte >= 0 and byte <= 255) end
	check("all byte values, control text and UTF-8 survive", same(codec.decode(envelope), input))
	f.healthy(); f.close()
end)

case("corruption, truncation, invalid bytes and future formats return a fixed error", function()
	local f = F.new(); local codec, util = f.env.require("runtime/credential_codec"), f.env.require("runtime/util")
	local original = assert(codec.encode({ apiKey = "dummy-corruption-secret" }))
	for _, damage in ipairs({
		function(item) item.data[1] = (item.data[1] + 1) % 256 end,
		function(item) item.data[#item.data] = nil end,
		function(item) item.data[1] = 256 end,
		function(item) item.data[1] = 1.5 end,
		function(item) item.data[1] = "5" end,
		function(item) item.data[0] = 0 end,
		function(item) item.data[#item.data + 2] = 0 end,
		function(item) item.version = 2 end,
		function(item) item.encoding = "future-codec" end,
		function(item) item.checksum = (item.checksum + 1) % 4294967296 end,
	}) do
		local damaged = util.deepCopy(original); damage(damaged)
		local decoded, why = codec.decode(damaged)
		check("malformed data is rejected without echoing credentials", decoded == nil and why == codec.error and not why:find("dummy-corruption-secret", 1, true))
	end
	local oversized, why = codec.encode({ value = string.rep("x", codec.maxBytes) })
	check("oversized payloads fail before writing an envelope", oversized == nil and why == codec.error)
	f.healthy(); f.close()
end)

case("remembered provider configuration reconstructs exact connection data", function()
	local f = F.new(); local credentials, util = f.env.require("runtime/credentials"), f.env.require("runtime/util")
	local input = snapshot()
	local preserved = util.deepCopy(input)
	local encoded = assert(credentials.persistent(input))
	check("missing preference remembers byte-encoded credentials", type(encoded.providers.list[1].storedCredentials) == "table"
		and type(encoded.identity.storedCredentials) == "table")
	local body = util.encode(encoded)
	for _, secret in ipairs({ "dummy-key-first", "dummy-key-second", "dummy-name-first", "dummy-name-second", "dummy-url-secret",
		"dummy-socket-secret", "dummy-header-secret", "dummy-custom-secret", "dummy-query-secret", "dummy-body-secret",
		"dummy-provider-error-secret", "dummy-repair-secret", "dummy-repair-scope-secret", "dummy-output-scope-secret",
		"dummy-tools-scope-secret", "dummy-session-secret", "dummy-identity-secret" }) do
		assert(not body:find(secret, 1, true), "stored provider data must not contain a raw dummy secret")
	end
	check("all authentication, key metadata and learned fields roundtrip exactly", same(credentials.restore(encoded), input))
	check("projection leaves live credentials and connector pairing unchanged", same(input, preserved)
		and encoded.bridge.token == input.bridge.token and encoded.relay.token == input.relay.token)
	local safe = credentials.sanitise(encoded)
	check("sanitised exports remove both credential envelopes and pairing secrets", safe.providers.list[1].storedCredentials == nil
		and safe.identity.storedCredentials == nil and safe.bridge.enabled == nil and safe.bridge.port == nil and safe.bridge.token == nil
		and safe.bridge.autoDiscover == true and safe.relay.token == "")
	f.healthy(); f.close()
end)

case("session-only is optional and private copies remain restorable", function()
	local f = F.new(); local credentials = f.env.require("runtime/credentials")
	local input = snapshot(false)
	local sessionOnly = assert(credentials.persistent(input))
	check("explicit session-only storage removes provider credentials", sessionOnly.providers.list[1].apiKey == ""
		and sessionOnly.providers.list[1].storedCredentials == nil and sessionOnly.providers.list[1].credentialsOmitted)
	local private = assert(credentials.privateCopy(input))
	check("private copies encode independently of the local preference", private.security.rememberCredentials == false
		and private.providers.list[1].storedCredentials and same(credentials.restore(private), input))
	f.healthy(); f.close()
end)

case("unreadable envelopes remain intact and blocked across normal saves", function()
	local f = F.new(); local credentials, util = f.env.require("runtime/credentials"), f.env.require("runtime/util")
	local damaged = assert(credentials.persistent(snapshot(true)))
	damaged.providers.list[1].storedCredentials.version = 99
	damaged.identity.storedCredentials.data[1] = (damaged.identity.storedCredentials.data[1] + 1) % 256
	local original = util.deepCopy(damaged)
	local restored = credentials.restore(damaged)
	check("unreadable credentials stay blocked instead of becoming anonymous", restored.providers.list[1].credentialsOmitted
		and restored.providers.list[1].credentialStorageError and restored.identity.credentialStorageError)
	local saved = assert(credentials.persistent(restored))
	check("failed envelopes are preserved byte for byte", same(saved.providers.list[1].storedCredentials, original.providers.list[1].storedCredentials)
		and same(saved.identity.storedCredentials, original.identity.storedCredentials))
	local booleanEnvelope = snapshot(true); booleanEnvelope.providers.list[1].storedCredentials = false
	check("even an invalid envelope value is not replaced with empty credentials", credentials.persistent(booleanEnvelope).providers.list[1].storedCredentials == false)
	local safe = credentials.sanitise(saved)
	check("default export excludes unreadable encoded secrets", safe.providers.list[1].storedCredentials == nil and safe.identity.storedCredentials == nil)
	f.healthy(); f.close()
end)

case("identity-only corruption does not permanently taint provider credentials", function()
	local f = F.new(); local credentials = f.env.require("runtime/credentials")
	local config, registry = f.env.require("runtime/config"), f.env.require("provider/registry")
	local input = snapshot(true)
	local damaged = assert(credentials.persistent(input)); damaged.identity.storedCredentials.version = 99
	config.load(damaged)
	local record = registry.get("fixture")
	check("provider credentials remain valid when only identity data is unreadable", record.apiKey == input.providers.list[1].apiKey
		and record.credentialsOmitted == nil and record.credentialStorageError == nil)
	check("the global identity error blocks requests", registry.protocolProblem(record) ~= nil)
	config.set("identity.extraHeaders", input.identity.extraHeaders)
	check("restoring identity authentication immediately releases the global guard", registry.protocolProblem(record) == nil
		and record.credentialsOmitted == nil and record.credentialStorageError == nil)
	local restored = credentials.restore(assert(credentials.persistent(config.data))).providers.list[1]
	check("a subsequent save does not retain a false provider error", restored.apiKey == record.apiKey
		and restored.credentialsOmitted == nil and restored.credentialStorageError == nil)
	f.healthy(); f.close()
end)

case("checksum-valid unsupported payloads remain intact without replacing fields", function()
	local f = F.new(); local credentials, codec = f.env.require("runtime/credentials"), f.env.require("runtime/credential_codec")
	for _, fields in ipairs({ { apiKey = {} }, { baseUrl = {} }, { wsUrl = false }, { headers = "invalid" },
		{ query = false }, { params = "invalid" }, { health = "invalid" }, { opencodeSession = {} },
		{ apiKey = "dummy-one", keyPaused = { "invalid" } }, { apiKey = "dummy-one", selectedKey = 2 },
		{ apiKey = "dummy-one", futureCredential = "future-secret-fixture" } }) do
		local envelope = assert(codec.encode({ kind = "provider", fields = fields }))
		local input = { providers = { list = { { apiKey = "unchanged-fixture", headers = { ["X-Existing"] = "kept" }, storedCredentials = envelope } } } }
		local restored = credentials.restore(input).providers.list[1]
		check("invalid field types and unknown fields preserve the original envelope", restored.credentialsOmitted
			and restored.credentialStorageError == codec.error and same(restored.storedCredentials, envelope)
			and restored.apiKey == "unchanged-fixture" and restored.headers["X-Existing"] == "kept")
	end
	local partial = assert(codec.encode({ kind = "provider", fields = { headers = { ["X-Partial"] = "kept" } } }))
	local restored = credentials.restore({ providers = { list = { { storedCredentials = partial } } } }).providers.list[1]
	check("valid partial records may omit credentials and optional fields", restored.storedCredentials == nil and restored.credentialStorageError == nil
		and restored.apiKey == nil and restored.headers["X-Partial"] == "kept")
	f.healthy(); f.close()
end)

case("encoding failure returns no plaintext fallback", function()
	local f = F.new(); local credentials, codec = f.env.require("runtime/credentials"), f.env.require("runtime/credential_codec")
	local input = snapshot(true)
	codec.encode = function() return nil, "fixture encoding failure" end
	local encoded, why = credentials.persistent(input)
	check("failed persistence produces no writable plaintext projection", encoded == nil and why == "fixture encoding failure")
	encoded, why = credentials.privateCopy(input)
	check("failed private copy produces no plaintext transfer", encoded == nil and why == "fixture encoding failure")
	check("encoding failure leaves live credentials intact", input.providers.list[1].apiKey == "dummy-key-first\ndummy-key-second")
	f.healthy(); f.close()
end)

suite.finish()
