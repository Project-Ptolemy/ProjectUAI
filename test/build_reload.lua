-- Build identity and re-execution regressions against the shipping bundle.
-- Run after bundling: luajit test/build_reload.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local luau = require("luau")
local buildId = dofile("tools/build_id.lua")
local passed = 0
local function check(label, value)
	assert(value, label)
	passed = passed + 1
	print("ok " .. label)
end
local fixture = { { id = "ui/test", source = "return function()\nreturn 1\nend\n" } }
local base = buildId("1.0", fixture, "return true\n")
check("fingerprint is reproducible", base == buildId("1.0", fixture, "return true\n"))
check("fingerprint ignores CRLF and trailing whitespace", base == buildId("1.0", { { id = "ui/test", source = "return function()\r\nreturn 1\r\nend\r\n" } }, "return true\r\n"))
check("fingerprint changes with module content", base ~= buildId("1.0", { { id = "ui/test", source = "return 2" } }, "return true"))
check("fingerprint changes with bootstrap", base ~= buildId("1.0", fixture, "return false"))
check("fingerprint changes with version", base ~= buildId("1.1", fixture, "return true"))
check("fingerprint changes with module identity", base ~= buildId("1.0", { { id = "ui/other", source = fixture[1].source } }, "return true"))

local file = assert(io.open("dist/uai.lua", "rb"))
local source = file:read("*a")
file:close()
local identity = assert(source:match('local __UAI_BUILD = "([^"]+)"'))
local manifestFile = assert(io.open("dist/uai.manifest.json", "rb"))
local manifest = require("json").decode(manifestFile:read("*a")); manifestFile:close()
check("module manifest belongs to the generated bundle", manifest.buildId == identity and manifest.hashAlgorithm == "uai-dual32-v1" and #manifest.modules > 0)
local previousId = ""
for _, entry in ipairs(manifest.modules) do
	assert(entry.id > previousId and entry.bytes >= 0 and type(entry.hash) == "string", "manifest modules must be ordered and individually identified")
	previousId = entry.id
end
check("module manifest uses canonical order", previousId ~= "")
local PASSWORD = "reload fixture master password"
local function cheapDerive(client)
	local crypto = client.env.require("runtime/credential_crypto")
	local sha = client.env.require("runtime/credential_sha256")
	crypto.derive = function(password, salt, _, progress)
		if progress and progress(0, 2) == false then return nil, crypto.error end
		local key = sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
		if progress and progress(2, 2) == false then return nil, crypto.error end
		return key
	end
end
local function authenticate(harness, handle)
	cheapDerive(handle)
	local status = handle.config.vaultStatus()
	if status.ready then return end
	local result
	harness.sched.spawn(function()
		result = { (status.enabled and handle.config.unlockVault or handle.config.enableVault)(PASSWORD) }
	end)
	harness.settle(1)
	assert(result and result[1], result and result[2] or "reload fixture password operation did not complete")
end
local function boot(harness, id, hostContext, leaveGated, settleSeconds)
	local body = source
	if id then body = body:gsub('local __UAI_BUILD = "[^"]+"', 'local __UAI_BUILD = "' .. id .. '"', 1) end
	local chunk, errors = luau.load(body, "reload-test", { entry = true })
	assert(chunk, errors and errors[1] and errors[1].msg)
	setfenv(chunk, harness.sandbox)
	local handle = assert(chunk(hostContext))
	harness.settle(settleSeconds or 1)
	-- General reload checks run after real envelope authentication with a cheap
	-- fixture KDF. Dedicated cases below leave the shipping startup gate intact.
	if not leaveGated and handle.alive and not handle.reloadBlocked then authenticate(harness, handle) end
	return handle
end
local function screenCount(harness)
	local count = 0
	for _, item in ipairs(harness.coreGui:GetChildren()) do
		if item:IsA("ScreenGui") and item.Name:match("^UAI_") then count = count + 1 end
	end
	return count
end
local harness = envMock.new()
local originalContext = { prompt = "Embedded instructions", hooks = { preTool = function() return true end } }
local first = boot(harness, nil, originalContext)
check("handle and runtime expose build identity", first.build == identity and first.env.info.build == identity)
local toggles = 0
local toggle = first.toggle
first.toggle = function() toggles = toggles + 1; toggle() end
local same = boot(harness)
check("same build returns the existing handle and toggles once", same == first and toggles == 1 and first.alive)
check("same build leaves exactly one screen", screenCount(harness) == 1)

first.config.set("agent.customInstructions", "Preserve settings on update", { transient = true })
local session = first.sessions.current()
session.title = "Saved across reload"
session.ctx.pushUser("Keep this conversation")
session.emit("user", { text = "Keep this conversation" })
local oldId, oldScreen = session.id, first.app.screen
local nextBuild = identity .. "-changed"
local updated = boot(harness, nextBuild)
check("changed build replaces the idle instance", updated ~= first and updated.build == nextBuild and updated.alive and not first.alive)
check("old screen detaches before replacement", oldScreen.Parent == nil and screenCount(harness) == 1)
check("config survives reload including previously unsaved settings", updated.config.get("agent.customInstructions") == "Preserve settings on update")
local restored = updated.sessions.threads[oldId]
check("conversation identity and title survive reload", restored and restored.title == "Saved across reload")
check("conversation context survives reload", restored.ctx.last("user").content == "Keep this conversation")
check("conversation transcript survives reload", restored.log[1] and restored.log[1].text == "Keep this conversation")
check("reloaded handle becomes global owner", harness.sandbox.UAI == updated)
check("reload preserves embedding context when no new context is provided", updated.env.context == originalContext)

local running = updated.sessions.newThread()
running.busy = true
running.abortFlag = false
local currentBuild = updated.build
local deferred = boot(harness, identity .. "-busy")
check("busy request remains on its existing build", deferred == updated and updated.build == currentBuild and updated.alive)
check("busy reload never aborts running work", running.busy and running.abortFlag == false)
check("busy reload records pending update", updated.pendingBuild == identity .. "-busy")
check("busy reload explains how to apply the update", harness.textOf():find("Let the current work finish", 1, true) ~= nil)
running.busy = false
local replacementContext = { prompt = "Updated embedding" }
local afterWork = boot(harness, identity .. "-busy", replacementContext)
check("rerunning after work finishes applies pending build", afterWork ~= updated and afterWork.build == identity .. "-busy")

check("explicit new embedding context takes precedence", afterWork.env.context == replacementContext)
local children = afterWork.env.require("agent/subagent")
children.records = { { id = "queued-test", status = "queued" } }
check("queued subagent also defers update", boot(harness, identity .. "-children") == afterWork and afterWork.alive)
children.records = {}

local composer = afterWork.app.chatPanel.composer
composer.field.set("Unsent work")
check("composer draft defers a changed build", boot(harness, identity .. "-draft") == afterWork and composer.field.get() == "Unsent work")
check("draft deferral gives a specific explanation", harness.textOf():find("draft and attachments", 1, true) ~= nil)
check("same build still toggles with a pending draft", boot(harness, afterWork.build) == afterWork and composer.field.get() == "Unsent work")
composer.field.clear()
composer.attachments = { { label = "unsent.lua", text = "return 1" } }
check("pending attachments defer a changed build", boot(harness, identity .. "-attachment") == afterWork and #composer.attachments == 1)
composer.attachments = {}
local draftedSession = afterWork.sessions.current()
composer.field.set("Background conversation draft")
local emptySession = afterWork.sessions.newThread()
afterWork.app.openSession(emptySession.id)
check("switching away leaves the active composer empty", composer.field.get() == "")
check("background conversation draft also defers update", boot(harness, identity .. "-background-draft") == afterWork and afterWork.alive)
afterWork.app.openSession(draftedSession.id)
check("deferred background draft stays intact", composer.field.get() == "Background conversation draft")
composer.field.clear()
local quick = afterWork.env.require("ui/quickchat")
quick.field.set("Quick draft")
check("Quick Chat draft defers a changed build", boot(harness, identity .. "-quick") == afterWork and quick.field.get() == "Quick draft")
quick.field.clear()
local chatFixture = require("gamechat")(harness)
afterWork.env.services.TextChatService = harness.services.TextChatService
afterWork.config.set("permissions.mode", "full")
local chatLoops = afterWork.env.require("runtime/chatloops")
assert(chatLoops.start("auto", { messages = { "Live loop" } }, afterWork.sessions.current().toolContext()))
check("live chat loop defers a changed build", boot(harness, identity .. "-chat-loop") == afterWork and afterWork.alive)
chatLoops.stop()
local isolated = afterWork.sessions.newThread()
isolated.setEphemeral(true)
isolated.ctx.pushUser("Private unsaved conversation")
check("populated isolated conversation defers update", boot(harness, identity .. "-isolated") == afterWork and isolated.ephemeral and isolated.ctx.last("user").content == "Private unsaved conversation")
check("isolated deferral gives a specific explanation", harness.textOf():find("isolated conversations", 1, true) ~= nil)
isolated.setEphemeral(false)

local save = afterWork.config.saveNow
afterWork.config.saveNow = function() return false end
check("save failure leaves old client alive", boot(harness, identity .. "-save-failed") == afterWork and afterWork.alive and screenCount(harness) == 1)
afterWork.config.saveNow = save

local dispose = afterWork.env.require("runtime/dispose")
dispose.add(function() error("simulated cleanup failure") end, "reload-test")
local blocked = boot(harness, identity .. "-cleanup-failed")
check("cleanup failure prevents replacement", blocked == afterWork and afterWork.cleanupFailed and afterWork.reloadBlocked)
check("cleanup failure retains a guard without a duplicate screen", harness.sandbox.UAI == afterWork and screenCount(harness) == 0)
check("rerun after failed cleanup cannot mount a duplicate", boot(harness, identity .. "-retry") == afterWork and screenCount(harness) == 0)

local throwingHarness = envMock.new()
local throwing = boot(throwingHarness)
throwing.destroy = function() error("simulated destroy failure") end
check("throwing destroy cannot mount a second instance", boot(throwingHarness, identity .. "-throw") == throwing and throwing.reloadBlocked and screenCount(throwingHarness) == 1)

local legacyHarness = envMock.new()
local legacy = boot(legacyHarness)
legacy.build = nil
local replacedLegacy = boot(legacyHarness)
check("legacy handle without build metadata is replaced", replacedLegacy ~= legacy and replacedLegacy.build == identity and not legacy.alive)

-- Encrypted credentials must survive loader replacement and authenticated restart.
-- The sentinels below are synthetic and are never sent to an upstream service.
local credentialHarness = envMock.new()
local credentialContext = { ui = false, reuse = true }
local credentialClient = boot(credentialHarness, nil, credentialContext)
check("new client requires encrypted remembered credentials", credentialClient.config.get("security.rememberCredentials") == true
	and credentialClient.config.vaultStatus().ready and credentialClient.config.vaultStatus().enabled)
check("required encryption cannot switch to session-only storage", credentialClient.config.setRememberCredentials(false) == false)
local privateRecord = credentialClient.providers.blank("custom")
privateRecord.id, privateRecord.label = "reload-private-fixture", "Reload credential fixture"
privateRecord.baseUrl = "https://reload.fixture/v1?access_token=reload-url-private"
privateRecord.wsUrl = "wss://reload.fixture/socket?session=reload-socket-private"
privateRecord.apiKey = "reload-key-one\nreload-key-two"
privateRecord.keyNames = { "Reload first key", "Reload second key" }
privateRecord.keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" }
privateRecord.keyPaused, privateRecord.keyMode, privateRecord.selectedKey = { true, false }, "single", 2
privateRecord.model, privateRecord.models = "fixture-model", { "fixture-model" }
privateRecord.headers = { Authorization = "Bearer reload-header-key", ["X-Fixture-Auth"] = "reload-header-private" }
privateRecord.query = { token = "reload-query-private", routing = "reload-query-route" }
privateRecord.params = { access_token = "reload-body-private", temperature = 0.2 }
assert(credentialClient.providers.save(privateRecord))
credentialClient.providers.setActive(privateRecord.id)
credentialClient.config.set("identity.extraHeaders", { ["X-Fixture-Identity"] = "reload-identity-private" })
assert(credentialClient.config.saveNow())
local function credentialData(client)
	local record = assert(client.providers.get(privateRecord.id))
	return { apiKey = record.apiKey, keyNames = record.keyNames, keyIds = record.keyIds,
		keyPaused = record.keyPaused, keyMode = record.keyMode, selectedKey = record.selectedKey,
		headers = record.headers, query = record.query, params = record.params,
		baseUrl = record.baseUrl, wsUrl = record.wsUrl, authStyle = record.authStyle,
		identity = client.config.get("identity.extraHeaders") }
end
local function sameCredentialData(left, right)
	if type(left) ~= type(right) then return false end
	if type(left) ~= "table" then return left == right end
	for key, value in pairs(left) do if not sameCredentialData(value, right[key]) then return false end end
	for key in pairs(right) do if left[key] == nil then return false end end
	return true
end
local expectedCredentials = credentialClient.env.require("runtime/util").deepCopy(credentialData(credentialClient))
-- Unloading an encrypted client deliberately clears its live provider objects.
-- Keep an independent fixture template for the separate vault-lifecycle case.
local privateTemplate = credentialClient.env.require("runtime/util").deepCopy(privateRecord)
local privateValues = { "reload-key-one", "reload-key-two", "reload-header-key", "reload-header-private",
	"reload-query-private", "reload-query-route", "reload-body-private", "reload-url-private",
	"reload-socket-private", "reload-identity-private", "Reload first key", "Reload second key",
	"11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" }
local function diskOmitsCredentials()
	local disk = credentialHarness.files["UAI/config.json"]
	if type(disk) ~= "string" then return false end
	for _, value in ipairs(privateValues) do if disk:find(value, 1, true) then return false end end
	return true
end
check("encrypted save excludes every private connection sentinel from disk", diskOmitsCredentials())
local sameCredentials = boot(credentialHarness, nil, credentialContext)
check("same-build reuse preserves the exact key pool and connection metadata", sameCredentials == credentialClient
	and sameCredentialData(credentialData(sameCredentials), expectedCredentials) and diskOmitsCredentials())
local credentialSave = credentialClient.config.saveNow
credentialClient.config.saveNow = function() return false end
local failedCredentials = boot(credentialHarness, identity .. "-credential-save-failed", credentialContext)
check("failed credential replacement keeps the live instance and all session credentials", failedCredentials == credentialClient
	and credentialClient.alive and sameCredentialData(credentialData(credentialClient), expectedCredentials) and diskOmitsCredentials())
credentialClient.config.saveNow = credentialSave
local credentialBuild = identity .. "-credential-handoff"
local handedOff = boot(credentialHarness, credentialBuild, credentialContext)
check("changed-build handoff preserves exact key pool, metadata and custom credentials", handedOff ~= credentialClient
	and handedOff.alive and not credentialClient.alive and sameCredentialData(credentialData(handedOff), expectedCredentials))
check("changed-build handoff never writes plaintext credentials to disk", diskOmitsCredentials())
handedOff.destroy()
check("genuine unload removes the live client owner while retaining ciphertext", not handedOff.alive
	and credentialHarness.sandbox.UAI == nil and diskOmitsCredentials())
local freshCredentials = boot(credentialHarness, credentialBuild, credentialContext, true)
local freshRecord = assert(freshCredentials.providers.get(privateRecord.id))
check("a genuine new boot requires a password before exposing credentials", freshCredentials ~= handedOff
	and freshRecord.apiKey == "" and freshCredentials.config.vaultStatus().locked
	and type(freshCredentials.providers.protocolProblem(freshRecord)) == "string")
authenticate(credentialHarness, freshCredentials)
check("genuine restart restores all encrypted connection fields after authentication", sameCredentialData(credentialData(freshCredentials), expectedCredentials)
	and diskOmitsCredentials())
check("credential replacement scenarios have no asynchronous errors", #credentialHarness.errors() == 0)
freshCredentials.destroy()

-- Private key handoff never grants access to a newly executed build. UI-disabled
-- embedding still mounts the mandatory prompt and authenticates each execution.
local vaultHarness = envMock.new()
local vaultClient = boot(vaultHarness, nil, credentialContext, true)
local vaultPassword = PASSWORD
local function vaultCall(method, ...)
	local args, result = { ... }, nil
	vaultHarness.sched.spawn(function() result = { method(unpack(args)) } end)
	vaultHarness.sched.advance(1)
	assert(result, "vault reload fixture operation did not complete")
	return unpack(result)
end
cheapDerive(vaultClient)
assert(vaultCall(vaultClient.config.enableVault, vaultPassword))
local vaultRecord = vaultClient.env.require("runtime/util").deepCopy(privateTemplate)
assert(vaultClient.providers.save(vaultRecord))
vaultClient.providers.setActive(vaultRecord.id)
vaultClient.config.set("identity.extraHeaders", { ["X-Fixture-Identity"] = "reload-identity-private" })
assert(vaultClient.config.saveNow())
local vaultExpected = vaultClient.env.require("runtime/util").deepCopy(credentialData(vaultClient))
local vaultUpdated = boot(vaultHarness, identity .. "-vault-handoff", credentialContext, true)
check("changed-build replacement retains vault data but requires authentication", vaultUpdated ~= vaultClient and not vaultClient.alive
	and vaultUpdated.config.vaultStatus().enabled and not vaultUpdated.config.vaultStatus().ready)
authenticate(vaultHarness, vaultUpdated)
check("vault handoff retains exact key pool and authentication fields", sameCredentialData(credentialData(vaultUpdated), vaultExpected))
local vaultDisk = vaultHarness.files["UAI/config.json"]
local vaultSaved = vaultHarness.json.decode(vaultDisk)
check("vault handoff persists ciphertext without its password or session key", type(vaultSaved.credentialVault) == "table"
	and vaultSaved.credentialVault.key == nil and not vaultDisk:find(vaultPassword, 1, true)
	and not vaultDisk:find("reload-key-one", 1, true) and not vaultDisk:find("reload-identity-private", 1, true))
vaultUpdated.destroy()
local vaultCold = boot(vaultHarness, identity .. "-vault-handoff", credentialContext, true)
check("genuine vault restart stays locked and mounts required password UI", vaultCold.config.vaultStatus().locked
	and vaultCold.providers.get(privateRecord.id).apiKey == "" and vaultCold.uiMounted
	and vaultCold.env.loadedModules["ui/credentialvault"] ~= nil)
cheapDerive(vaultCold)
assert(vaultCall(vaultCold.config.unlockVault, vaultPassword))
check("explicit unlock after a genuine restart restores exact credentials", sameCredentialData(credentialData(vaultCold), vaultExpected))
check("vault replacement and cold unlock have no asynchronous errors", #vaultHarness.errors() == 0)
local unsavedVault = vaultCold.providers.get(privateRecord.id)
unsavedVault.headers["X-Fixture-Auth"] = "reload-header-before-unload"
unsavedVault.keyNames[2] = "Renamed before unload"
vaultCold.config.save()
vaultCold.destroy()
local finalVaultBoot = boot(vaultHarness, identity .. "-vault-handoff", credentialContext, true)
cheapDerive(finalVaultBoot)
assert(vaultCall(finalVaultBoot.config.unlockVault, vaultPassword))
local finalVaultRecord = finalVaultBoot.providers.get(privateRecord.id)
check("unload before the debounce preserves the newest encrypted credential edits", finalVaultRecord.headers["X-Fixture-Auth"] == "reload-header-before-unload"
	and finalVaultRecord.keyNames[2] == "Renamed before unload" and finalVaultRecord.apiKey == vaultExpected.apiKey)
check("final unload save never exposes unsaved credentials in plaintext", not vaultHarness.files["UAI/config.json"]:find("reload-header-before-unload", 1, true))
finalVaultBoot.destroy()

-- Master Vault native writes and all retained forms participate in replacement.
local knowledgeHarness = envMock.new()
local function confirmKnowledgeDiscard()
	local labels = knowledgeHarness.find(knowledgeHarness.coreGui, function(node) return node:IsA("TextLabel") and node.Text == "Discard" end)
	assert(#labels == 1, "one explicit discard confirmation must be present")
	local button = labels[1].Parent
	while button and not button:IsA("TextButton") do button = button.Parent end
	knowledgeHarness.click(assert(button))
end
local knowledgeClient = boot(knowledgeHarness)
local knowledge = knowledgeClient.env.require("runtime/master_vault")
local knowledgeCaps = knowledgeClient.env.require("runtime/caps")
local nativeWrite = knowledgeCaps.fn.writefile
knowledgeCaps.fn.writefile = function(path, text)
	if path:find("/vault/notes/", 1, true) then knowledgeHarness.sched.wait(5) end
	return nativeWrite(path, text)
end
local knowledgeSaved
knowledgeHarness.sched.spawn(function()
	knowledgeSaved = { knowledge.save({ title = "Pending knowledge", content = "Keep these exact saved bytes." }) }
end)
knowledgeHarness.sched.advance(0.1)
check("a pending native knowledge write owns the runtime", knowledge.isBusy())
local unloaded, unloadWhy = knowledgeClient.destroy()
check("unload waits for the knowledge write", not unloaded and knowledgeClient.alive and unloadWhy:find("Master Vault", 1, true))
check("a knowledge write defers build replacement", boot(knowledgeHarness, identity .. "-knowledge-write") == knowledgeClient
	and knowledgeClient.alive and knowledgeClient.pendingBuild == identity .. "-knowledge-write")
knowledgeHarness.sched.advance(6)
knowledgeCaps.fn.writefile = nativeWrite
check("the pending save finishes before ownership releases", knowledgeSaved and knowledgeSaved[1]
	and knowledgeSaved[1].content == "Keep these exact saved bytes." and not knowledge.isBusy())
local editor = knowledgeClient.env.require("ui/vault_editor")
local noteDraft = assert(editor.open({ title = "Retained draft", content = "Keep the unfinished note." }))
check("open Vault edits defer replacement", boot(knowledgeHarness, identity .. "-knowledge-draft") == knowledgeClient
	and #editor.listDrafts() == 1 and knowledgeClient.alive)
noteDraft.close(); knowledgeHarness.settle(0.3)
check("closed Vault drafts still defer replacement", boot(knowledgeHarness, identity .. "-closed-knowledge-draft") == knowledgeClient
	and #editor.listDrafts() == 1)
noteDraft = assert(editor.reopen(editor.listDrafts()[1].key))
knowledgeHarness.click(assert(knowledgeHarness.byName("VaultDiscardDraft", noteDraft.card)))
confirmKnowledgeDiscard()
knowledgeHarness.settle(0.3)
check("explicit discard releases the Vault form guard", #editor.listDrafts() == 0)
local importDraft = assert(editor.import())
local importField = assert(knowledgeHarness.byName("VaultImportText", importDraft.card)):FindFirstChildOfClass("TextBox")
importField.Text = "# Unreviewed import\n\nKeep this pasted reference."
importDraft.close(); knowledgeHarness.settle(0.3)
check("unreviewed imports defer replacement after closing", boot(knowledgeHarness, identity .. "-knowledge-import") == knowledgeClient
	and #editor.listDrafts() == 1)
importDraft = assert(editor.reopen(editor.listDrafts()[1].key))
knowledgeHarness.click(assert(knowledgeHarness.byName("VaultDiscardImport", importDraft.card)))
confirmKnowledgeDiscard()
knowledgeHarness.settle(0.3)
local planning = knowledgeClient.env.require("ui/goals")
local planBoard = assert(planning.open(knowledgeClient.sessions.current()))
knowledgeHarness.click(assert(knowledgeHarness.byName("EditGoalsObjective", planBoard.card)))
local goalForm = assert(knowledgeHarness.byName("GoalField_objective")):FindFirstChildOfClass("TextBox")
goalForm.Text = "Retain this unfinished objective"
planBoard.close(); knowledgeHarness.settle(0.3)
check("closed Micro-goals forms defer replacement", planning.hasDrafts()
	and boot(knowledgeHarness, identity .. "-goal-draft") == knowledgeClient and knowledgeClient.alive)
planBoard = assert(planning.open(knowledgeClient.sessions.current()))
knowledgeHarness.click(assert(knowledgeHarness.byName("DiscardGoalForm", planBoard.card)))
planBoard.close(); knowledgeHarness.settle(0.3)
check("explicit plan discard releases replacement", not planning.hasDrafts())
local knowledgeUpdated = boot(knowledgeHarness, identity .. "-workspace-reviewed")
check("reviewed workspace applies the pending release", knowledgeUpdated ~= knowledgeClient and knowledgeUpdated.alive and not knowledgeClient.alive)
local savedAfterReload
knowledgeHarness.sched.spawn(function() savedAfterReload = knowledgeUpdated.env.require("runtime/master_vault").read(knowledgeSaved[1].id) end)
knowledgeHarness.settle(0.3)
check("saved Master Vault knowledge survives client replacement", savedAfterReload and savedAfterReload.content == knowledgeSaved[1].content)
check("workspace replacement scenarios have no asynchronous errors", #knowledgeHarness.errors() == 0)
knowledgeUpdated.destroy()

-- UI mods participate in the shipping loader, direct application and resource lifetime.
do
	local storePath = "UAI/ui_mods/store.json"
	local scriptSpec = { version = 1, kind = "script", id = "reload-workspace", name = "Reload workspace",
		author = "Offline reload fixture", sources = { { label = "UI Mods guide", url = "docs/UI_MODS.md" } }, source = [[
local host = getgenv()
host.__reloadUiModRuns = (host.__reloadUiModRuns or 0) + 1
return function(context)
	context:OnDestroy(function() host.__reloadUiModCleanups = (host.__reloadUiModCleanups or 0) + 1 end)
	context:Connect(context.env.run.Heartbeat, function() host.__reloadUiModTicks = (host.__reloadUiModTicks or 0) + 1 end)
	context:OnMount(function(root)
		host.__reloadUiModMounts = (host.__reloadUiModMounts or 0) + 1
		host.__reloadUiModMountsReady = host.__reloadUiModMountsReady ~= false
			and context.app.chatPanel ~= nil and context.app.chatPanel.composer ~= nil
			and type(context.app.window.onShow) == "function"
		context.require("ui/theme").color.text = Color3.fromRGB(7, 11, 17)
		local frame = Instance.new("Frame", root)
		frame.Name = "ReloadOwnedModFrame"
		frame.Size = UDim2.fromOffset(16, 16)
		return function()
			frame:Destroy()
			host.__reloadUiModMountCleanups = (host.__reloadUiModMountCleanups or 0) + 1
		end
	end)
	return function() host.__reloadUiModReturnedCleanup = (host.__reloadUiModReturnedCleanup or 0) + 1 end
end
]] }
	local visualSpec = { version = 1, kind = "visual", id = "reload-appearance", name = "Reload appearance",
		appearance = { density = "compact", fontScale = 1.2 }, panels = {} }
	local function run(h, fn, seconds)
		local result
		h.sched.spawn(function() result = { fn() } end); h.settle(seconds or 0.3)
		assert(result, "mod reload fixture operation did not complete")
		return unpack(result)
	end
	local function field(h, name, root)
		return assert(h.byName(name, root), "missing " .. name):FindFirstChildOfClass("TextBox")
	end
	local function surface(client, name)
		local open = client.env.require("ui/overlay").open
		for index = #open, 1, -1 do
			if not open[index].closed and (not name or open[index].card.Name == name) then return open[index] end
		end
	end
	local function click(h, name, root)
		h.click(assert(h.byName(name, root), "missing " .. name)); h.settle(0.3)
	end
	local function clickLabel(h, text, root)
		local labels = h.find(root, function(node) return node:IsA("TextLabel") and node.Text == text end)
		assert(#labels == 1, "one explicit " .. text .. " action must be present")
		local button = labels[1].Parent
		while button and not button:IsA("TextButton") do button = button.Parent end
		h.click(assert(button)); h.settle(0.3)
	end
	local function save(h, client, spec)
		return assert(run(h, function() return client.env.require("runtime/ui_mods").save(spec) end))
	end
	local function beginApply(h, client, record)
		client.show("chat"); h.settle(0.2)
		local work = { done = false }
		h.sched.spawn(function()
			work.result = client.sessions.current().applyUiMod(record.id, record.revision); work.done = true
		end)
		h.settle(0.3)
		return work
	end
	local function snapshot(h)
		local state = { files = {}, folders = {} }
		for path, text in pairs(h.files) do state.files[path] = text end
		for path, exists in pairs(h.folders) do state.folders[path] = exists end
		return state
	end
	local function seed(h, state)
		for path, text in pairs(state.files) do h.files[path] = text end
		for path, exists in pairs(state.folders) do h.folders[path] = exists end
	end
	local function healthy(h)
		check("bundled mod workflows have no asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	end

	do
		local h = envMock.new(); local client = boot(h)
		client.config.set("permissions.mode", "full")
		local mods, caps = client.env.require("runtime/ui_mods"), client.env.require("runtime/caps")
		local nativeWrite = caps.fn.writefile
		caps.fn.writefile = function(path, text)
			if path == storePath then h.sched.wait(8) end
			return nativeWrite(path, text)
		end
		local saved
		h.sched.spawn(function() saved = { mods.save(scriptSpec) } end); h.sched.advance(0.1)
		check("a pending native mod write owns the runtime", mods.isBusy() and saved == nil)
		local unloaded, why = client.destroy()
		check("unload waits for native mod persistence", unloaded == false and client.alive and why:find("UI mod", 1, true))
		local owner = h.sandbox.UAI; h.sandbox.UAI = nil
		local menu = assert(client.app.showProfileMenu(client.app.window.root))
		clickLabel(h, "Unload UAI", menu.card)
		clickLabel(h, "Unload", assert(surface(client)).footer)
		check("native unload retains mod guards when the global owner is absent", client.alive and mods.isBusy()
			and not client.app.disposed and screenCount(h) == 1)
		h.sandbox.UAI = owner
		check("a native mod write defers build replacement", boot(h, identity .. "-mod-write") == client
			and client.alive and client.pendingBuild == identity .. "-mod-write")
		h.sched.advance(9); caps.fn.writefile = nativeWrite
		check("the exact staged source finishes before write ownership releases", saved and saved[1]
			and saved[1].spec.source == scriptSpec.source and not mods.isBusy() and h.sandbox.__reloadUiModRuns == nil)
		local checkScript, releasePreflight = mods.checkScript, false
		mods.checkScript = function(spec)
			while not releasePreflight do h.sched.wait(0.1) end
			return checkScript(spec)
		end
		local work = beginApply(h, client, saved[1])
		local ask = client.env.require("ui/panels/ask")
		check("yielding compilation owns application without opening a question", not work.done and ask.current == nil
			and client.env.require("agent/ui_mod_activation").isBusy() and h.sandbox.__reloadUiModRuns == nil)
		unloaded, why = client.destroy()
		check("outstanding mod preparation blocks native unload", unloaded == false and client.alive and why:find("UI mod", 1, true))
		check("outstanding mod preparation defers replacement", boot(h, identity .. "-mod-preflight") == client
			and not work.done and client.pendingBuild == identity .. "-mod-preflight")
		local disabled = run(h, client.disableUiMods)
		check("Disable revokes application while retaining outstanding preparation ownership", disabled.ok and not work.done
			and client.env.require("agent/ui_mod_activation").isBusy() and ask.current == nil)
		releasePreflight = true; h.settle(0.4); mods.checkScript = checkScript
		check("the revoked preparation releases its gate after completion without startup", work.done and not work.result.ok
			and ask.current == nil and not client.env.require("agent/ui_mod_activation").isBusy()
			and h.sandbox.__reloadUiModRuns == nil)
		local replacement = boot(h, identity .. "-mod-preflight-complete")
		local retained = assert(replacement.env.require("runtime/ui_mods").read(scriptSpec.id))
		check("cancelled preparation permits replacement while retaining the disabled package", replacement ~= client and not client.alive
			and retained.spec.source == scriptSpec.source and not retained.active and h.sandbox.__reloadUiModRuns == nil)
		client = replacement
		local manager = client.env.require("ui/mods"); local view = assert(manager.open()); h.settle(0.3)
		click(h, "UiModEdit_" .. scriptSpec.id, view.card)
		local editing = assert(surface(client, "UiModEditor")); local input = field(h, "UiModJson", editing.card)
		local draftJson = input.Text .. "\n"; input.Text = draftJson
		editing.close(); view.close(); h.settle(0.3)
		check("a closed dirty mod editor protects build replacement", manager.hasDrafts()
			and boot(h, identity .. "-closed-mod-draft") == client and client.alive)
		view = assert(manager.open()); h.settle(0.3); click(h, "UiModsResume", view.card)
		editing = assert(surface(client, "UiModEditor"))
		check("resuming a blocked mod draft retains the complete JSON", field(h, "UiModJson", editing.card).Text == draftJson)
		click(h, "UiModDiscardDraft", editing.card)
		clickLabel(h, "Discard draft", assert(surface(client)).footer)
		view.close(); h.settle(0.3)
		check("explicit draft discard releases the guard without changing the saved package", not manager.hasDrafts()
			and client.env.require("runtime/ui_mods").read(scriptSpec.id).spec.source == scriptSpec.source)
		local reviewed = boot(h, identity .. "-mod-draft-reviewed")
		check("explicit mod draft discard permits the pending update", reviewed ~= client and reviewed.alive and not client.alive)
		assert(reviewed.destroy() ~= false); h.settle(0.3); healthy(h)
	end

	do
		local h = envMock.new(); local client = boot(h)
		client.config.set("permissions.mode", "full")
		local saved = save(h, client, scriptSpec)
		local theme = client.env.require("ui/theme"); local baseText = theme.color.text:ToHex()
		local work = beginApply(h, client, saved)
		check("direct application needs no dedicated native question", client.env.require("ui/panels/ask").current == nil)
		check("direct application executes the saved source once", work.done and work.result.ok and work.result.data.applied
			and h.sandbox.__reloadUiModRuns == 1 and h.sandbox.__reloadUiModMounts == 1
			and client.env.require("runtime/ui_mod_runner").state().active)
		local oldFrame = assert(h.byName("ReloadOwnedModFrame", client.app.screen))
		client.config.set("ui.fontScale", 1.1, { transient = true }); client.app.flushAppearance(); h.settle(0.5)
		check("a completed appearance rebuild mounts the active source once", h.sandbox.__reloadUiModRuns == 1
			and h.sandbox.__reloadUiModMounts == 2 and h.sandbox.__reloadUiModMountCleanups == 1
			and h.sandbox.__reloadUiModMountsReady and oldFrame.Parent == nil
			and #h.find(client.app.screen, function(node) return node.Name == "ReloadOwnedModFrame" end) == 1)
		check("same-build reuse retains one active script lifetime", boot(h, client.build, { reuse = true }) == client
			and h.sandbox.__reloadUiModRuns == 1 and h.sandbox.__reloadUiModMounts == 2 and h.sandbox.__reloadUiModCleanups == nil)
		local mounts = h.sandbox.__reloadUiModMounts
		check("the script's direct token change is observable before recovery", theme.color.text:ToHex() ~= baseText)
		local recovered = boot(h, client.build, { safeMode = true, reuse = true })
		local ticks = h.sandbox.__reloadUiModTicks; h.settle(0.4)
		check("same-build safe recovery releases the active scope exactly once", recovered == client and client.alive and client.safeMode
			and client.env.context.safeMode and h.sandbox.__reloadUiModRuns == 1 and h.sandbox.__reloadUiModCleanups == 1
			and h.sandbox.__reloadUiModReturnedCleanup == 1 and h.sandbox.__reloadUiModMountCleanups == mounts
			and h.sandbox.__reloadUiModTicks == ticks and h.byName("ReloadOwnedModFrame", client.app.screen) == nil)
		check("safe recovery restores base appearance and retains the source definition", theme.color.text:ToHex() == baseText
			and client.env.require("runtime/ui_mods").getActive() == nil
			and client.env.require("runtime/ui_mods").read(scriptSpec.id).spec.source == scriptSpec.source)
		local denied = run(h, function() return client.sessions.current().applyUiMod(saved.id, saved.revision) end)
		check("same-build safe mode denies Apply before another execution", not denied.ok and denied.text:find("safe-mode", 1, true)
			and client.env.require("ui/panels/ask").current == nil and h.sandbox.__reloadUiModRuns == 1)
		assert(client.destroy() ~= false); h.settle(0.3); healthy(h)
	end

	do
		local h = envMock.new(); local client = boot(h)
		client.config.set("permissions.mode", "full")
		local scriptRecord, visualRecord = save(h, client, scriptSpec), save(h, client, visualSpec)
		local visualWork = beginApply(h, client, visualRecord)
		check("direct visual application selects the stored appearance", visualWork.done and visualWork.result.ok and visualWork.result.data.applied
			and client.env.require("runtime/ui_mods").getActive().id == visualSpec.id and client.env.require("ui/theme").density == "compact")
		local stored = snapshot(h); local coldHarness = envMock.new(); seed(coldHarness, stored)
		local cold = boot(coldHarness, nil, { safeMode = true, reuse = true })
		local coldMods, coldTheme = cold.env.require("runtime/ui_mods"), cold.env.require("ui/theme")
		check("cold safe mode skips the selected appearance and preserves both packages", cold.safeMode and coldMods.getActive() == nil
			and coldMods.state().selectedId == visualSpec.id and coldMods.list().total == 2
			and coldMods.read(scriptSpec.id).spec.source == scriptSpec.source
			and coldMods.read(visualSpec.id).spec.appearance.fontScale == 1.2
			and coldHarness.files[storePath] == stored.files[storePath])
		check("cold safe mode uses base appearance and executes no stored script", coldTheme.density == cold.config.get("ui.density")
			and coldHarness.sandbox.__reloadUiModRuns == nil and not cold.env.require("runtime/ui_mod_runner").state().active)
		assert(cold.destroy() ~= false); coldHarness.settle(0.3); healthy(coldHarness)
		local scriptWork = beginApply(h, client, scriptRecord)
		check("the later script application executes its exact saved revision", scriptWork.done and scriptWork.result.ok
			and scriptWork.result.data.applied and h.sandbox.__reloadUiModRuns == 1)
		local beforeReplacement, oldScreen = h.files[storePath], client.app.screen
		local replacement = boot(h, identity .. "-active-mod-replacement", { reuse = true })
		local nextMods = replacement.env.require("runtime/ui_mods")
		check("fresh replacement retains complete packages without running the selected script", replacement ~= client and replacement.alive
			and not client.alive and oldScreen.Parent == nil and screenCount(h) == 1 and h.sandbox.UAI == replacement
			and nextMods.list().total == 2 and nextMods.read(scriptSpec.id).spec.source == scriptSpec.source
			and nextMods.read(scriptSpec.id).spec.author == scriptSpec.author and nextMods.read(scriptSpec.id).spec.sources[1].url == "docs/UI_MODS.md"
			and nextMods.read(visualSpec.id).spec.appearance.fontScale == 1.2 and nextMods.state().selectedId == scriptSpec.id
			and nextMods.getActive() == nil and h.sandbox.__reloadUiModRuns == 1 and h.files[storePath] == beforeReplacement)
		local ticks = h.sandbox.__reloadUiModTicks; h.settle(0.4)
		check("replacement releases the old script scope and mounts no active script", h.sandbox.__reloadUiModCleanups == 1
			and h.sandbox.__reloadUiModReturnedCleanup == 1 and h.sandbox.__reloadUiModMountCleanups == 1
			and h.sandbox.__reloadUiModTicks == ticks and not replacement.env.require("runtime/ui_mod_runner").state().active
			and h.byName("ReloadOwnedModFrame", replacement.app.screen) == nil)
		assert(replacement.destroy() ~= false); h.settle(0.3); healthy(h)
	end

	do
		local h = envMock.new(); local client = boot(h)
		client.config.set("permissions.mode", "full")
		local yieldingSpec = { version = 1, kind = "script", id = "yielding-cleanup", name = "Yielding cleanup", source = [[
local host = getgenv()
host.__yieldingModRuns = (host.__yieldingModRuns or 0) + 1
return function(context)
	context:OnDestroy(function()
		host.__yieldingModCleanupStarted = true
		host.__yieldingModNestedDestroy, host.__yieldingModNestedReason = context.uai.destroy()
		context.require("runtime/clock").wait(0.6)
		host.__yieldingModCleanupCompleted = true
	end)
end
]] }
		local saved = save(h, client, yieldingSpec)
		local work = beginApply(h, client, saved)
		check("the yielding cleanup fixture starts through direct application", work.done and work.result.ok
			and work.result.data.applied and h.sandbox.__yieldingModRuns == 1)
		local oldScreen, unloaded = client.app.screen, nil
		h.sched.spawn(function() unloaded = { client.destroy() } end); h.sched.advance(0.05)
		check("yielding cleanup retains the unloading owner until it returns", client.unloading and not client.alive
			and unloaded == nil and h.sandbox.UAI == client and h.sandbox.__yieldingModCleanupStarted
			and not h.sandbox.__yieldingModCleanupCompleted)
		check("a nested destroy cannot drain or release the same client early", h.sandbox.__yieldingModNestedDestroy == false
			and h.sandbox.__yieldingModNestedReason:find("cleanup", 1, true))
		local same = boot(h, client.build, { reuse = true }, true, 0.03)
		local changed = boot(h, identity .. "-during-mod-cleanup", { reuse = true }, true, 0.03)
		check("same and changed loaders cannot mount during outstanding cleanup", same == client and changed == client
			and client.unloading and unloaded == nil and h.sandbox.UAI == client and screenCount(h) == 1
			and oldScreen.Parent == h.coreGui and h.sandbox.__yieldingModRuns == 1
			and client.config.vaultStatus().ready)
		local nested, why = client.destroy()
		check("another unload rejects while the original cleanup is suspended", nested == false and why:find("cleanup", 1, true)
			and client.unloading and unloaded == nil)
		h.sched.advance(0.8)
		check("cleanup completion releases the owner and detaches the original screen", h.sandbox.__yieldingModCleanupCompleted
			and unloaded and unloaded[1] ~= false and not client.unloading and not client.alive
			and not client.cleanupFailed and h.sandbox.UAI == nil and oldScreen.Parent == nil and screenCount(h) == 0)
		local replacement = boot(h, identity .. "-after-mod-cleanup", { reuse = true })
		local nextMods = replacement.env.require("runtime/ui_mods")
		check("fresh boot after yielding cleanup preserves the source without executing it", replacement ~= client and replacement.alive
			and h.sandbox.UAI == replacement and screenCount(h) == 1
			and nextMods.read(saved.id).spec.source == yieldingSpec.source and nextMods.state().selectedId == saved.id
			and nextMods.getActive() == nil and not replacement.env.require("runtime/ui_mod_runner").state().active
			and h.sandbox.__yieldingModRuns == 1)
		check("same-build reuse after cleanup retains exactly one fresh client", boot(h, replacement.build, { reuse = true }) == replacement
			and screenCount(h) == 1 and h.sandbox.__yieldingModRuns == 1)
		assert(replacement.destroy() ~= false); h.settle(0.3); healthy(h)
	end
end

local volatileHarness = envMock.new()
local volatile = boot(volatileHarness)
volatile.env.require("runtime/fsx").enabled = false
check("host without persistence keeps in-memory state", boot(volatileHarness, identity .. "-volatile") == volatile and volatile.alive)
check("successful update paths have no asynchronous errors", #harness.errors() == 0 and #legacyHarness.errors() == 0)
print("build reload: " .. passed .. " checks passed")
