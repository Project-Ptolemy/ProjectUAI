-- Support bundle: local diagnostics with credentials and conversations excluded.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Support bundle")
local case, check = suite.case, suite.check

local SECRET = "sk-support-secret-1234"
local KEY_NAME = "Private billing account"
local KEY_ID = "11111111-1111-4111-8111-111111111111"

local function setup()
	local f = F.new(); f.tools({ "support_bundle" })
	local config = f.env.require("runtime/config")
	config.set("providers.list", {
		{ id = "fixture", label = "Fixture provider", baseUrl = "https://fixture.test/v1",
			apiKey = SECRET, model = "fixture-model", api = "openai", enabled = true,
			keyNames = { KEY_NAME }, keyMode = "single", selectedKey = 1, keyPaused = { true },
			keyIds = { KEY_ID },
			params = { headers = { Authorization = "Bearer " .. SECRET, ["X-Custom"] = "custom-secret" } } },
	})
	config.set("agent.customInstructions", "A local preference")
	f.env.require("runtime/log").error("fixture", "request failed with " .. SECRET)
	local ctx = { session = { id = "s-support" }, aborted = function() return false end }
	return f, ctx
end

case("the bundle contains diagnostics but no credentials or conversation text", function()
	local f, ctx = setup()
	local result = f.dispatch("support_bundle", {}, ctx)
	check("bundle writes and verifies", result.ok and result.data.verified == true and result.data.bytes > 0)
	check("bundle reports a workspace path", type(result.data.path) == "string" and result.data.path:find("files/", 1, true) == 1)
	local raw = f.h.sandbox.readfile("UAI/" .. result.data.path)
	check("the secret is absent from the full file", raw:find(SECRET, 1, true) == nil)
	local bundle = f.h.json.decode(raw)
	check("bundle is versioned", bundle.format == "uai-support" and bundle.version == 1)
	check("provider keys are redacted in config", bundle.config.providers.list[1].apiKey == "<redacted>")
	check("private key names are omitted from diagnostics", bundle.config.providers.list[1].keyNames == nil
		and bundle.providers[1].keyNames == nil and raw:find(KEY_NAME, 1, true) == nil)
	check("diagnostics omit empty-pool policy without changing live keys", bundle.config.providers.list[1].keyMode ~= "single"
		and f.env.require("runtime/config").get("providers.list")[1].keyMode == "single"
		and f.env.require("runtime/config").get("providers.list")[1].keyNames[1] == KEY_NAME)
	check("diagnostics exclude key slots without resuming a live key", bundle.config.providers.list[1].keyPaused == nil
		and f.env.require("runtime/config").get("providers.list")[1].keyPaused[1] == true)
	check("usage identities are omitted without changing saved identity", bundle.config.providers.list[1].keyIds == nil
		and bundle.providers[1].keyIds == nil and raw:find(KEY_ID, 1, true) == nil
		and f.env.require("runtime/config").get("providers.list")[1].keyIds[1] == KEY_ID)
	check("custom request-body fields are excluded", next(bundle.config.providers.list[1].params or {}) == nil
		and raw:find("custom-secret", 1, true) == nil)
	check("provider summary contains health but no key", bundle.providers[1].label == "Fixture provider"
		and bundle.providers[1].apiKey == nil and bundle.providers[1].health ~= nil)
	check("capabilities and tools are present", type(bundle.capabilities.summary) == "string"
		and bundle.tools.stats.total > 0 and bundle.tools.profile == "focused")
	check("sessions report metadata only", bundle.sessions.available == true and bundle.sessions.items ~= nil)
	check("conversation text is not collected", raw:find("A local preference", 1, true) == nil)
	check("logs are retained in redacted form", #bundle.logs > 0 and raw:find("sk-...", 1, true) ~= nil)
	f.healthy(); f.close()
end)

case("unrecognized credential names and URL authentication never enter diagnostics", function()
	local f = setup()
	local config = f.env.require("runtime/config")
	local record = config.get("providers.list")[1]
	record.baseUrl = "https://private-user:private-password@fixture.test/v1?unusual=opaque-url-value#opaque-fragment-value"
	record.wsUrl = "wss://socket-user:socket-password@fixture.test/ws?custom=opaque-socket-value"
	record.headers = { ["X-Custom-Access"] = "opaque-header-value" }
	record.query = { unusual = "opaque-query-value" }
	record.params = { custom = "opaque-body-value", nested = { ["opaque-map-key"] = true } }
	record.keyRotation = { index = 1, cooldowns = { ["opaque-cooldown-value"] = 123 } }
	record.repairScope = "openai\nhttps://fixture.test/v1/models?custom=opaque-repair-value\nfixture-model"
	record.maxTokensCap = { model = "fixture-model", tokens = 120, scope = "https://fixture.test/v1/models?custom=opaque-token-cap-value" }
	record.toolsCap = { model = "fixture-model", limit = 12, scope = "https://fixture.test/v1/models?custom=opaque-tool-cap-value" }
	record.health = { lastError = "Invalid credential opaque-provider-error-value" }
	record.storedCredentials = { version = 999, data = "opaque-encoded-provider-value" }
	config.set("identity.extraHeaders", { ["X-Private-Identity"] = "opaque-identity-value" })
	config.data.identity.storedCredentials = { version = 999, data = "opaque-encoded-identity-value" }
	check("retired desktop credentials cannot enter live settings", not config.set("bridge.token", "opaque-bridge-value")
		and config.get("bridge.token") == nil)
	config.set("relay.token", "opaque-relay-value")
	local http = f.env.require("net/http")
	http.history = { { url = "https://history-user:history-password@fixture.test/v1?custom=opaque-history-value#history-fragment", method = "POST", status = 200 } }
	local bundle = f.env.require("runtime/support_bundle").build()
	local raw = f.env.require("runtime/util").encode(bundle)
	for _, value in ipairs({ "private-user", "private-password", "opaque-url-value", "opaque-fragment-value",
		"socket-user", "socket-password", "opaque-socket-value", "opaque-header-value", "opaque-query-value",
		"opaque-body-value", "opaque-map-key", "opaque-cooldown-value", "opaque-identity-value",
		"opaque-repair-value", "opaque-token-cap-value", "opaque-tool-cap-value", "opaque-provider-error-value",
		"opaque-encoded-provider-value", "opaque-encoded-identity-value",
		"opaque-bridge-value", "opaque-relay-value", "history-user", "history-password", "opaque-history-value", "history-fragment" }) do
		check("credential field omitted: " .. value, raw:find(value, 1, true) == nil)
	end
	check("provider endpoints retain their useful host and path", bundle.providers[1].baseUrl == "https://fixture.test/v1"
		and bundle.config.providers.list[1].baseUrl == "https://fixture.test/v1"
		and bundle.config.providers.list[1].wsUrl == "wss://fixture.test/ws")
	check("HTTP diagnostics retain endpoint and result", bundle.http.items[1].url == "https://fixture.test/v1"
		and bundle.http.items[1].status == 200)
	check("raw cooldown map is omitted", bundle.config.providers.list[1].keyRotation == nil)
	check("encoded credentials are excluded even when their version is unknown", bundle.config.providers.list[1].storedCredentials == nil
		and bundle.config.identity.storedCredentials == nil)
	check("diagnostics leave live authentication untouched", record.headers["X-Custom-Access"] == "opaque-header-value"
		and record.keyRotation.cooldowns["opaque-cooldown-value"] == 123
		and config.get("bridge.token") == nil and config.get("relay.token") == "opaque-relay-value")
	f.healthy(); f.close()
end)

case("a host without a filesystem fails without a partial bundle", function()
	local f = F.new()
	local s = f.h.sandbox
	s.writefile, s.readfile, s.isfile, s.listfiles = nil, nil, nil, nil
	f.tools({ "support_bundle" })
	local result = f.dispatch("support_bundle", {}, { session = { id = "s-none" }, aborted = function() return false end })
	check("missing filesystem is reported", not result.ok and result.text:find("not written", 1, true) ~= nil)
	f.healthy(); f.close()
end)

suite.finish()
