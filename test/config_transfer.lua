-- Focused full configuration transfer regressions; no network or real credentials.
-- Run from repository root: luajit test/config_transfer.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local harness = require("env").new()
local luau = require("luau")
local cache, writes, events = {}, {}, {}
local failWrite = false
local env = { services = harness.services, hs = harness.services.HttpService, info = { version = "test" } }
function env.require(id)
	if cache[id] then return cache[id] end
	local path = "src/" .. id .. ".lua"
	local file = assert(io.open(path, "rb"))
	local source = file:read("*a")
	file:close()
	local chunk, problems = luau.load(source, path)
	assert(chunk, problems and problems[1] and problems[1].msg)
	setfenv(chunk, harness.sandbox)
	cache[id] = chunk()(env)
	return cache[id]
end
local util = env.require("runtime/util")
local fsx = {
	enabled = true,
	exists = function() return false end,
	readJson = function(_, fallback) return fallback end,
	writeJson = function(path, value)
		writes[#writes + 1] = { path = path, value = util.deepCopy(value) }
		if failWrite then return false, "private-error-must-not-escape" end
		return true
	end,
}
cache["runtime/fsx"] = fsx
cache["runtime/clock"] = { ms = function() return 123456 end, debounce = function() return function() end end }
cache["runtime/log"] = { warn = function() end }
local config = env.require("runtime/config")
local transfer = env.require("runtime/config_transfer")
local keyPolicy = env.require("runtime/provider_keys")
local credentials = env.require("runtime/credentials")
local checks = 0
local function check(label, condition)
	assert(condition, label)
	checks = checks + 1
	print("ok " .. label)
end
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end
local function envelope(snapshot)
	return { format = transfer.FORMAT, version = transfer.VERSION, config = snapshot }
end
local full = util.deepCopy(config.defaults)
full.security.rememberCredentials = true
full.ui.density = "compact"
full.ui.layout = "window"
full.ui.window = { width = 1050, height = 700, x = 30, y = 40, maximised = false, placed = true }
full.ui.showToolDetail = true
full.agent.forceReasoning = { ["model-a"] = true, ["model-b"] = false }
full.agent.forceContext = { ["model-a"] = 64000 }
full.agent.disabledGroups = { remotes = true }
full.agent.customInstructions = "Preserve literal null, quotes \" and backslashes \\."
full.permissions = { mode = "auto", remember = false, rules = { read = "allow", execute = "ask", delete = "deny" } }
full.providers = {
	active = "second",
	list = {
		{
			id = "first", label = "Primary", baseUrl = "https://example.invalid/v1", apiKey = "key-one\nkey-two, key-three\r\nkey-one",
			keyNames = { "Private account label", "", "备用账号" }, keyMode = "single", selectedKey = 2,
			keyPaused = { true, false, true },
			keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222", "33333333-3333-4333-8333-333333333333" },
			model = "model-a", models = { "model-a", "model-b" }, preset = "custom", api = "openai", authStyle = "bearer",
			headers = { Authorization = "header-secret", ["X-Custom"] = false, ["X-Version"] = 3 },
			query = { key = "query-secret", enabled = false },
			params = { token = "param-secret", nested = { array = { 1, false, "three" }, enabled = false } },
			stream = false, claudeUa = false, enabled = false, order = 9, wsUrl = "wss://example.invalid", note = "Offline setup", requires = "bridge",
			opencodeSession = "session-id", health = { ok = 2, fail = 1, streak = 0, lastError = "", cooldownUntil = 50, lastMs = 8 },
			keyRotation = { index = 2, cooldowns = { ["key-one"] = 123999 } },
			extraExtension = { nested = { "custom" } },
		},
		{ id = "second", label = "Secondary", baseUrl = "", apiKey = "another-key", model = "", models = {}, order = 1, enabled = true },
	},
}
full.identity.extraHeaders = { ["X-Identity"] = "identity-secret" }
full.memory.entries = { { key = "preference", value = "concise", at = 123 } }
full.bridge = { enabled = true, autoDiscover = false, port = 8795, token = "bridge-secret", runtime = "web" }
full.logs = { level = "debug", mirror = true }
full.skills.disabled = { ["sample.md"] = true, ["other.md"] = false }
full.extension = { token = "extension-secret", active = false }
config.data = util.deepCopy(full)
config.changed:connect(function(path, value) events[#events + 1] = { path = path, value = value } end)

local body, summary = transfer.export({ includeCredentials = true })
check("full configuration exports to JSON", type(body) == "string")
local decoded = assert(util.decode(body))
local retainedFull = util.deepCopy(full)
retainedFull.bridge.enabled, retainedFull.bridge.port, retainedFull.bridge.token = nil, nil, nil
local exportedFull = util.deepCopy(retainedFull)
exportedFull.providers.list[1].keyRotation = nil
local decodedFull = assert(transfer.preview(body)).config
check("export has a versioned format envelope", decoded.format == transfer.FORMAT and decoded.version == 1 and decoded.exportedAt == 123456 and decoded.appVersion == "test")
check("private export contains encoded provider and identity envelopes", type(decoded.config.providers.list[1].storedCredentials) == "table"
	and type(decoded.config.identity.storedCredentials) == "table" and decoded.config.providers.list[1].apiKey == ""
	and not body:find("key-one", 1, true) and not body:find("header-secret", 1, true) and not body:find("identity-secret", 1, true))
check("private export reconstructs all retained configuration", same(decodedFull, exportedFull))
check("export reconstructs multiline API key pools verbatim", decodedFull.providers.list[1].apiKey == full.providers.list[1].apiKey)
check("export reconstructs names and selected-key policy", same(decodedFull.providers.list[1].keyNames, full.providers.list[1].keyNames)
	and decodedFull.providers.list[1].keyMode == "single" and decodedFull.providers.list[1].selectedKey == 2)
check("export reconstructs each paused and active key", same(decodedFull.providers.list[1].keyPaused, { true, false, true }))
check("export reconstructs opaque usage identities", same(decodedFull.providers.list[1].keyIds, full.providers.list[1].keyIds))
check("summary counts unique keys across multiline/comma pools", summary.keys == 4 and summary.providers == 2 and summary.active == "Secondary")
check("summary includes preferences without credentials", summary.permissionMode == "auto" and summary.rules == 3 and summary.memory == 1 and summary.bridgeAutoDiscover == false and not util.encode(summary):find("secret", 1, true))
check("private transfer strips retired manual connection values", decoded.config.bridge.enabled == nil
	and decoded.config.bridge.port == nil and decoded.config.bridge.token == nil and not body:find("bridge-secret", 1, true))
check("summary excludes private key names", not util.encode(summary):find("Private account label", 1, true) and summary.keyNames == nil)
check("export has no persistence or observer side effects", #writes == 0 and #events == 0)
local preview = assert(transfer.preview(body))
check("preview roundtrips every retained value", same(preview.config, exportedFull))
check("preview does not modify live settings", #writes == 0 and #events == 0 and same(config.data, full))
preview.config.extension.active = true
check("preview is isolated from live settings", config.data.extension.active == false)
preview = assert(transfer.preview(body))
config.data = util.deepCopy(config.defaults)
config.data.security.rememberCredentials = true
config.data.stale = true
config.data.providers.list = { { id = "old" } }
local ok, persisted = transfer.apply(preview)
check("apply succeeds and persists", ok and persisted and #writes == 1 and writes[1].path == "config.json")
check("apply replaces full configuration including old providers", same(config.data, exportedFull) and config.data.stale == nil)
check("persisted snapshot reconstructs state without transient key rotation", same(credentials.restore(writes[1].value), exportedFull)
	and writes[1].value.providers.list[1].keyRotation == nil)
check("apply publishes one complete snapshot and live layout preferences", #events == 2 and events[1].path == nil and events[1].value == config.data and events[2].path == "ui.layout")
check("applied settings do not alias preview", config.data ~= preview.config and config.data.providers.list ~= preview.config.providers.list)
local minimal = { version = 1, ui = {}, agent = {}, providers = {}, permissions = {} }
local normalized = assert(transfer.validate(minimal))
check("empty known sections receive defaults", same(normalized, config.defaults))
check("unknown JSON extension fields survive normalization", normalized.extension == nil and full.extension.token == preview.config.extension.token)
local legacy = util.deepCopy(full)
legacy.ui.reduceMotion = "on"
legacy.bridge.requestTimeout = 35
local migrated = assert(transfer.preview(util.encode(envelope(legacy))))
check("older exports retire motion and manual connection fields", same(migrated.config, retainedFull)
	and legacy.ui.reduceMotion == "on" and legacy.bridge.token == "bridge-secret")
local legacyKeys = util.deepCopy(retainedFull)
local legacyProvider = legacyKeys.providers.list[1]
legacyProvider.keyNames, legacyProvider.keyMode, legacyProvider.selectedKey = nil, nil, nil
legacyProvider.keyPaused = nil
legacyProvider.keyIds = nil
local legacyPreview = assert(transfer.preview(util.encode(envelope(legacyKeys))))
check("legacy key pools import intact and default to rotation", same(legacyPreview.config, legacyKeys)
	and keyPolicy.mode(legacyPreview.config.providers.list[1]) == "rotate" and keyPolicy.selected(legacyPreview.config.providers.list[1]) == 1)
check("legacy imports do not invent pause or usage metadata", legacyPreview.config.providers.list[1].keyPaused == nil
	and legacyPreview.config.providers.list[1].keyIds == nil
	and #keyPolicy.requestKeys(legacyPreview.config.providers.list[1]) == 3)
local rotating = util.deepCopy(retainedFull)
rotating.providers.list[1].keyMode = "rotate"
check("explicit rotation retains its names and preferred single-key selection", same(assert(transfer.preview(util.encode(envelope(rotating)))).config, rotating))
local emptyKeys = util.deepCopy(rotating)
emptyKeys.providers.list[1].apiKey, emptyKeys.providers.list[1].keyNames, emptyKeys.providers.list[1].selectedKey = "", {}, 1
emptyKeys.providers.list[1].keyPaused = {}
emptyKeys.providers.list[1].keyIds = {}
check("an empty rotating pool remains valid for keyless providers", same(assert(transfer.preview(util.encode(envelope(emptyKeys)))).config, emptyKeys))
local allPaused = util.deepCopy(rotating)
allPaused.providers.list[1].keyPaused = { true, true, true }
local pausedPreview = assert(transfer.preview(util.encode(envelope(allPaused))))
check("all-paused pools transfer without silently resuming a key", same(pausedPreview.config, allPaused)
	and #keyPolicy.requestKeys(pausedPreview.config.providers.list[1]) == 0)
local selectedPaused = util.deepCopy(retainedFull)
selectedPaused.providers.list[1].keyPaused[2] = true
local selectedPausedPreview = assert(transfer.preview(util.encode(envelope(selectedPaused))))
check("a paused selected key remains selected and paused after transfer", same(selectedPausedPreview.config, selectedPaused)
	and #keyPolicy.requestKeys(selectedPausedPreview.config.providers.list[1]) == 0)
local maximumName = util.deepCopy(retainedFull)
maximumName.providers.list[1].keyNames[1] = string.rep("界", 40)
check("a valid 120-byte UTF-8 key name transfers intact", same(assert(transfer.preview(util.encode(envelope(maximumName)))).config, maximumName))
local motionEvents, motionWrites = #events, #writes
local motionSet, motionError = config.set("ui.reduceMotion", "on")
check("motion cannot be disabled through the configuration API", motionSet == nil and type(motionError) == "string"
	and config.get("ui.reduceMotion") == nil and #events == motionEvents and #writes == motionWrites)
check("motion cannot be restored as a nested configuration map", config.set("ui.reduceMotion.enabled", false) == nil)
check("motion cannot be toggled through the configuration API", config.toggle("ui.reduceMotion") == nil)
check("bridge duration is not configurable", config.set("bridge.requestTimeout", 35) == nil and config.defaults.bridge.requestTimeout == nil)
check("bridge duration cannot be restored as a nested map", config.set("bridge.requestTimeout.seconds", 35) == nil)

local before, beforeEvents, beforeWrites
local function unchanged()
	return config.data == before and #events == beforeEvents and #writes == beforeWrites
end
local function mark()
	before, beforeEvents, beforeWrites = config.data, #events, #writes
end
local function reject(label, mutate, viaApply)
	local candidate = util.deepCopy(full)
	mutate(candidate)
	mark()
	local value, err
	if viaApply then value, err = transfer.apply({ config = candidate })
	else value, err = transfer.preview(util.encode(envelope(candidate))) end
	check(label, not value and type(err) == "string" and not err:find("key-one", 1, true)
		and not err:find("Private account label", 1, true) and unchanged())
end
reject("reject wrong configuration version", function(c) c.version = 2 end)
reject("reject missing required section", function(c) c.agent = nil end)
reject("reject invalid known preference type", function(c) c.ui.notifications = "true" end)
reject("reject nested known preference type", function(c) c.ui.window.width = "wide" end)
reject("reject invalid appearance choice", function(c) c.ui.density = "very-dense" end)
reject("reject invalid inference runtime", function(c) c.bridge.runtime = "unknown" end)
reject("reject invalid permissions mode", function(c) c.permissions.mode = "sometimes" end)
reject("reject invalid permissions verdict", function(c) c.permissions.rules.read = "maybe" end)
reject("reject non-boolean skill preferences", function(c) c.skills.disabled["sample.md"] = "yes" end)
reject("reject invalid runtime reasoning map", function(c) c.agent.forceReasoning["model-a"] = {} end)
reject("reject provider list object", function(c) c.providers.list = { unexpected = {} } end)
reject("reject duplicate provider ids", function(c) c.providers.list[2].id = "first" end)
reject("reject missing active provider", function(c) c.providers.active = "missing" end)
reject("reject malformed key pool", function(c) c.providers.list[1].apiKey = {} end)
reject("reject non-list key names", function(c) c.providers.list[1].keyNames = "Private account label" end)
reject("reject non-text key names", function(c) c.providers.list[1].keyNames[2] = false end)
reject("reject overlong UTF-8 key names", function(c) c.providers.list[1].keyNames[2] = string.rep("界", 41) end)
reject("reject multiline key names", function(c) c.providers.list[1].keyNames[2] = "Line one\nLine two" end)
reject("reject control characters in key names", function(c) c.providers.list[1].keyNames[2] = "Hidden\0value" end)
reject("reject untrimmed persisted key names", function(c) c.providers.list[1].keyNames[2] = " Padded " end)
reject("reject invalid UTF-8 key names before apply", function(c) c.providers.list[1].keyNames[2] = string.char(255) end, true)
reject("reject extra key names", function(c) c.providers.list[1].keyNames[4] = "Extra" end)
reject("reject incomplete key names", function(c) c.providers.list[1].keyNames = { "Only one" } end)
reject("reject sparse key names before apply", function(c) c.providers.list[1].keyNames[2] = nil end, true)
reject("reject mixed key-name fields before apply", function(c) c.providers.list[1].keyNames.extra = "Unexpected" end, true)
reject("reject non-list pause metadata", function(c) c.providers.list[1].keyPaused = true end)
reject("reject non-boolean pause metadata", function(c) c.providers.list[1].keyPaused[2] = "false" end)
reject("reject incomplete pause metadata", function(c) c.providers.list[1].keyPaused = { true } end)
reject("reject extra pause metadata", function(c) c.providers.list[1].keyPaused[4] = false end)
reject("reject sparse pause metadata before apply", function(c) c.providers.list[1].keyPaused[2] = nil end, true)
reject("reject mixed pause fields before apply", function(c) c.providers.list[1].keyPaused.extra = false end, true)
reject("reject non-list usage identities", function(c) c.providers.list[1].keyIds = "invalid" end)
reject("reject non-text usage identities", function(c) c.providers.list[1].keyIds[2] = false end)
reject("reject malformed usage identities", function(c) c.providers.list[1].keyIds[2] = "account-secret" end)
reject("reject noncanonical usage identities", function(c) c.providers.list[1].keyIds[2] = "ABCDEFAB-2222-4222-8222-222222222222" end)
reject("reject duplicate usage identities", function(c) c.providers.list[1].keyIds[2] = c.providers.list[1].keyIds[1] end)
reject("reject incomplete usage identities", function(c) c.providers.list[1].keyIds = { c.providers.list[1].keyIds[1] } end)
reject("reject extra usage identities", function(c) c.providers.list[1].keyIds[4] = "44444444-4444-4444-8444-444444444444" end)
reject("reject sparse usage identities before apply", function(c) c.providers.list[1].keyIds[2] = nil end, true)
reject("reject mixed usage identity fields before apply", function(c) c.providers.list[1].keyIds.extra = "44444444-4444-4444-8444-444444444444" end, true)
reject("reject unknown key mode", function(c) c.providers.list[1].keyMode = "random" end)
reject("reject non-text key mode", function(c) c.providers.list[1].keyMode = false end)
reject("reject non-number selected key", function(c) c.providers.list[1].selectedKey = "2" end)
reject("reject zero selected key", function(c) c.providers.list[1].selectedKey = 0 end)
reject("reject fractional selected key", function(c) c.providers.list[1].selectedKey = 1.5 end)
reject("reject selected key beyond the deduplicated pool", function(c) c.providers.list[1].selectedKey = 4 end)
reject("reject single-key mode without credentials", function(c)
	c.providers.list[1].apiKey, c.providers.list[1].keyNames, c.providers.list[1].keyPaused = "", {}, {}
	c.providers.list[1].keyIds = {}
	c.providers.list[1].selectedKey = 1
end)
reject("revalidate key metadata in an edited preview", function(c) c.providers.list[1].selectedKey = 20 end, true)
reject("reject malformed model list", function(c) c.providers.list[1].models = { 42 } end)
reject("reject nested header values", function(c) c.providers.list[1].headers.Authorization = {} end)
reject("reject non-object provider params", function(c) c.providers.list[1].params = { "invalid" } end)
reject("reject invalid provider health", function(c) c.providers.list[1].health.fail = "many" end)
reject("reject incomplete rotation state", function(c) c.providers.list[1].keyRotation = {} end)
reject("reject fractional rotation index", function(c) c.providers.list[1].keyRotation.index = 1.5 end)
reject("reject malformed key cooldown", function(c) c.providers.list[1].keyRotation.cooldowns["key-one"] = "soon" end)
reject("reject malformed memory entry", function(c) c.memory.entries[1].value = {} end)
reject("revalidate edited preview before apply", function(c) c.ui.fontScale = "broken" end, true)
reject("reject sparse arrays before apply", function(c) c.extension = { [1] = "a", [3] = "b" } end, true)
reject("reject mixed keys before apply", function(c) c.extension = { [1] = "a", key = "b" } end, true)
reject("reject cycles before apply", function(c) c.extension = c end, true)
reject("reject NaN before apply", function(c) c.ui.fontScale = 0 / 0 end, true)
reject("reject infinity before apply", function(c) c.ui.fontScale = math.huge end, true)
reject("reject excessive nesting before apply", function(c) local v = {}; c.extension = v; for _ = 1, 26 do v.deep = {}; v = v.deep end end, true)
for label, invalid in pairs({
	["reject empty input"] = "",
	["reject invalid JSON without exposing parser content"] = '{"private-value":',
	["reject wrong format"] = '{"format":"other","version":1,"config":{}}',
	["reject future envelope version"] = '{"format":"project-uai-config","version":2,"config":{}}',
	["reject null settings"] = body:gsub('"notifications":true', '"notifications":null'),
	["reject invalid UTF-8 key names in JSON"] = util.encode(envelope(full)):gsub("Private account label", function() return string.char(255) end),
	["reject oversized input"] = string.rep(" ", 8 * 1024 * 1024 + 1),
}) do
	mark()
	local value, err = transfer.preview(invalid)
	check(label, value == nil and type(err) == "string" and not err:find("private-value", 1, true) and unchanged())
end
for _, mutation in ipairs({
	function(candidate) candidate.providers.list[1].storedCredentials.version = 999 end,
	function(candidate) candidate.identity.storedCredentials.checksum = -1 end,
}) do
	local candidate = util.deepCopy(decoded.config)
	mutation(candidate)
	mark()
	local value, err = transfer.preview(util.encode(envelope(candidate)))
	check("unreadable encoded import rejects without changing live configuration", not value and type(err) == "string"
		and not err:find("key-one", 1, true) and unchanged())
	value, err = transfer.apply({ config = candidate })
	check("edited preview cannot bypass encoded import validation", not value and type(err) == "string" and unchanged())
end
mark()
failWrite = true
local value, err = transfer.apply(preview)
check("failed persistence leaves live state and observers unchanged", not value and config.data == before and #events == beforeEvents and #writes == beforeWrites + 1)
check("persistence error hides private transport details", not err:find("private-error", 1, true))
failWrite = false
fsx.enabled = false
mark()
value, persisted = transfer.apply(preview)
check("hosts without filesystem import for current session", value and persisted == false and #writes == beforeWrites and same(config.data, exportedFull))

local clipboardCalls, clipboardBody = 0, nil
check("clipboard export needs an explicit writer", transfer.copyToClipboard(nil) == false)
value = transfer.copyToClipboard(function(text) clipboardCalls = clipboardCalls + 1; clipboardBody = text end, { includeCredentials = true })
check("explicit clipboard action writes once", value and clipboardCalls == 1)
check("private clipboard output reconstructs complete credentials", same(assert(transfer.preview(clipboardBody)).config, exportedFull)
	and not clipboardBody:find("key-one", 1, true))
value, err = transfer.copyToClipboard(function() return false end)
check("clipboard false result is reported as failure", not value and type(err) == "string")
value, err = transfer.copyToClipboard(function() error("private-writer-error") end)
check("clipboard exceptions hide private details", not value and not err:find("private-writer-error", 1, true))
check("no asynchronous errors", #harness.errors() == 0)

-- Exercise the real Settings modal in the shipping bundle as well as the module.
for _, viewport in ipairs({ { 1280, 800 }, { 390, 844 }, { 320, 640 } }) do
	local ui = require("env").new()
	local handle, bootError = ui.boot()
	assert(handle, bootError)
	ui.settle(1)
	require("password_fixture")(ui, handle)
	ui.setViewport(viewport[1], viewport[2])
	local suffix = " at " .. viewport[1] .. "px"
	local initial = handle.config.data
	handle.app.showSettingsDialog("import_export")
	ui.settle(1)
	check("Settings exposes private transfer actions" .. suffix, ui.byName("CopyFullConfig") ~= nil and ui.byName("PasteFullConfig") ~= nil)
	ui.click(ui.byName("PasteFullConfig"))
	local shell = assert(ui.byName("ConfigImportJSON"))
	local input = shell:FindFirstChildWhichIsA("TextBox")
	local review, apply = ui.byName("ReviewConfigImport"), ui.byName("ApplyConfigImport")
	local status = ui.byName("ConfigImportStatus")
	check("import starts with Apply disabled" .. suffix, apply.Active == false)
	local footer = apply.Parent
	-- The headless mock does not resolve AutomaticSize widths. Measure each
	-- label plus its real padding and layout gap to verify narrow footer demand.
	local required, count = 0, 0
	for _, button in ipairs(footer:GetChildren()) do
		if button:IsA("GuiButton") then
			local content = button:FindFirstChild("Content")
			local label = content:FindFirstChildWhichIsA("TextLabel")
			local pad = content:FindFirstChildOfClass("UIPadding")
			local measured = ui.services.TextService:GetTextSize(label.Text, label.TextSize, label.Font, ui.dt.Vector2.new(1000, 1000))
			required = required + measured.X + pad.PaddingLeft.Offset + pad.PaddingRight.Offset
			count = count + 1
		end
	end
	local layout = footer:FindFirstChildOfClass("UIListLayout")
	required = required + layout.Padding.Offset * math.max(count - 1, 0)
	check("import footer controls fit" .. suffix, required <= footer.AbsoluteSize.X and count == 3)
	ui.type(input, "invalid-private-json")
	ui.click(review)
	check("invalid preview keeps current config and permits retry" .. suffix, handle.config.data == initial and apply.Active == false and status.Text:find("JSON", 1, true) ~= nil and input.Parent ~= nil)
	local imported = util.deepCopy(full)
	imported.ui.layout = "auto"
	imported.bridge.enabled = false
	imported.providers.active = "first"
	imported.providers.list[1].enabled = true
	imported.providers.list[1].apiKey = "ui-test-key"
	imported.providers.list[1].keyNames = { "Private imported account" }
	imported.providers.list[1].keyPaused = { true }
	imported.providers.list[1].keyIds = { "11111111-1111-4111-8111-111111111111" }
	imported.providers.list[1].selectedKey = 1
	local uiBody = util.encode(envelope(imported))
	ui.type(input, uiBody)
	ui.click(review)
	check("review enables Apply with credential-free summary" .. suffix, apply.Active and status.Text:find("Ready to import", 1, true)
		and not status.Text:find("ui-test-key", 1, true) and not status.Text:find("Private imported account", 1, true) and handle.config.data == initial)
	ui.type(input, uiBody .. " ")
	check("editing a reviewed import disables Apply" .. suffix, apply.Active == false)
	ui.click(apply)
	check("disabled Apply cannot import edited data" .. suffix, handle.config.data == initial)
	ui.click(review)
	ui.click(apply)
	ui.settle(2)
	check("Apply updates real provider and preference state" .. suffix, handle.config.get("providers.active") == "first" and handle.config.get("providers.list")[1].apiKey == "ui-test-key" and handle.config.get("ui.density") == "compact")
	local appliedProvider = handle.config.get("providers.list")[1]
	check("Apply retains private key name and policy" .. suffix, appliedProvider.keyNames[1] == "Private imported account"
		and appliedProvider.keyMode == "single" and appliedProvider.selectedKey == 1)
	check("Apply retains the selected key pause" .. suffix, appliedProvider.keyPaused[1] == true
		and #handle.env.require("runtime/provider_keys").requestKeys(appliedProvider) == 0)
	check("Apply retains the selected key usage identity" .. suffix, appliedProvider.keyIds[1] == imported.providers.list[1].keyIds[1])
	local logger = handle.env.require("runtime/log")
	check("Apply synchronizes live logging preferences" .. suffix, logger.mirror == true)
	check("Apply dismisses stale import and Settings controls" .. suffix, ui.byName("ConfigImportJSON") == nil and ui.byName("SettingsDialog") == nil)
	check("full imported config is saved on disk" .. suffix, ui.files[handle.env.require("runtime/fsx").root .. "/config.json"] ~= nil)
	check("import flow has no asynchronous or property errors" .. suffix, #ui.errors() == 0 and #ui.instanceState.typeErrors == 0)
end
print("config transfer: " .. checks .. " checks passed")
