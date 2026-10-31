-- Password-vault migration and lifecycle regressions; synthetic credentials only.
-- Storage cases use a deterministic cheap derivation stub with the real envelope
-- and AES-SIV implementation. Primitive/KDF vectors run in credential_crypto.lua.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Credential vault storage")
local case, check = suite.case, suite.check
local PASSWORD = "several unrelated fixture words"
local CHANGED = "different unrelated fixture words"
local PRIVATE = { "vault-key-one", "vault-key-two", "vault-header-secret", "vault-query-secret", "vault-body-secret",
	"vault-url-secret", "vault-socket-secret", "vault-identity-secret", "vault-error-secret", "vault-scope-secret" }
local function same(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in pairs(a) do if not same(value, b[key]) then return false end end
	for key in pairs(b) do if a[key] == nil then return false end end
	return true
end
local function excludes(text)
	for _, value in ipairs(PRIVATE) do if text:find(value, 1, true) then return false end end
	return not text:find(PASSWORD, 1, true) and not text:find(CHANGED, 1, true)
end
local function setup()
	local f = F.new()
	local crypto, sha = f.env.require("runtime/credential_crypto"), f.env.require("runtime/credential_sha256")
	crypto.derive = function(password, salt, _, progress)
		if progress and progress(0, 2) == false then return nil, crypto.error end
		local key = sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
		if progress and progress(2, 2) == false then return nil, crypto.error end
		return key
	end
	local config, util = f.env.require("runtime/config"), f.env.require("runtime/util")
	config.load()
	local snapshot = util.deepCopy(config.defaults)
	snapshot.providers = { active = "vault-fixture", list = { {
		id = "vault-fixture", label = "Vault fixture", preset = "custom", api = "openai", authStyle = "bearer",
		baseUrl = "https://fixture.invalid/v1?route=vault-url-secret", wsUrl = "wss://fixture.invalid/ws?route=vault-socket-secret",
		apiKey = "vault-key-one\nvault-key-two", keyNames = { "Primary", "Backup" }, keyPaused = { true, false },
		keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" },
		keyMode = "single", selectedKey = 2, model = "fixture-model", models = { "fixture-model" },
		headers = { ["X-Fixture"] = "vault-header-secret" }, query = { opaque = "vault-query-secret" },
		params = { custom_auth = "vault-body-secret", temperature = 0.2 },
		health = { ok = 1, lastError = "vault-error-secret" }, repairScope = "vault-scope-secret",
		maxTokensCap = { tokens = 1234, scope = "vault-scope-secret" },
		keyRotation = { index = 2, cooldowns = { ["vault-key-one"] = 123 } },
	} } }
	snapshot.identity.extraHeaders = { ["X-Identity"] = "vault-identity-secret" }
	snapshot.bridge.token, snapshot.relay.token = "bridge-pairing", "relay-pairing"
	snapshot.memory.entries = { { key = "ordinary", value = "Keep this setting", at = 42 } }
	config.data = snapshot
	assert(config.saveNow(true))
	local expected = util.deepCopy(snapshot.providers.list[1]); expected.keyRotation = nil
	f.config, f.util, f.expected = config, util, expected
	function f.call(method, ...) local args = { ... }; return f.run(function() return method(unpack(args)) end, 1) end
	function f.enable() return assert(f.call(config.enableVault, PASSWORD)) end
	function f.disk() return f.h.files["UAI/config.json"] end
	function f.record() return config.data.providers.list[1] end
	function f.finish() f.healthy(); f.close() end
	return f
end

case("the live-tested byte format migrates without losing connection or key-pool data", function()
	local f = setup(); local config = f.config
	local encoded = f.util.decode(f.disk())
	check("fixture starts with the legacy encoded envelope", type(encoded.providers.list[1].storedCredentials) == "table" and encoded.credentialVault == nil)
	config.load()
	local live, identity = f.record(), config.data.identity
	check("old encoded keys load normally before opt-in", same(live, f.expected) and not config.vaultStatus().enabled)
	f.enable()
	local saved = f.util.decode(f.disk())
	check("migration activates an unlocked password vault", config.vaultStatus().enabled and not config.vaultStatus().locked)
	check("migration preserves provider and identity table ownership", live == f.record() and identity == config.data.identity)
	check("migration retains exact pools, names, pauses, ids, selected key and custom authentication", same(live, f.expected)
		and identity.extraHeaders["X-Identity"] == "vault-identity-secret")
	check("saved credentials use one encrypted envelope and omit reversible envelopes", saved.credentialVault.cipher == "aes-256-siv"
		and saved.credentialVault.iterations == 100000 and saved.providers.list[1].storedCredentials == nil and saved.identity.storedCredentials == nil)
	check("saved data omits passwords and every private sentinel", excludes(f.disk()))
	check("ordinary settings and existing pairing survive", saved.memory.entries[1].value == "Keep this setting"
		and saved.bridge.token == "bridge-pairing" and saved.relay.token == "relay-pairing")
	f.finish()
end)

case("setup cancellation and failed verification retain the existing keys and storage choice", function()
	local f = setup(); local config = f.config
	local before, live = f.disk(), f.record()
	local ok, why = f.call(config.enableVault, PASSWORD, { progress = function(done) return done == 0 end })
	check("cancelled derivation reports cancellation", not ok and why == "Cancelled")
	check("cancellation does not replace legacy bytes or live keys", f.disk() == before and f.record() == live and not config.vaultStatus().enabled)
	local write = f.env.require("runtime/caps").fn.writefile
	f.env.require("runtime/caps").fn.writefile = function() return true end
	ok = f.call(config.enableVault, PASSWORD)
	check("lying successful writer cannot activate the vault", not ok and not config.vaultStatus().enabled and f.disk() == before)
	check("failed migration leaves exact live credentials available", same(f.record().keyIds, f.expected.keyIds)
		and f.record().apiKey == f.expected.apiKey and config.get("security.rememberCredentials") == true)
	f.env.require("runtime/caps").fn.writefile = write
	f.enable()
	check("retry after a save failure succeeds without re-entry", config.vaultStatus().enabled and f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("cold startup is locked and wrong passwords or cancellation cannot release credentials", function()
	local f = setup(); local config = f.config; f.enable()
	local envelope = f.util.decode(f.disk()).credentialVault
	config.load()
	local locked = f.record()
	check("cold load removes live keys and keeps encrypted data", config.vaultStatus().locked and locked.apiKey == ""
		and same(config.data.credentialVault, envelope) and next(config.data.identity.extraHeaders) == nil)
	local problem = f.env.require("provider/registry").protocolProblem(locked)
	check("locked credentials cannot dispatch anonymously", type(problem) == "string" and problem:lower():find("unlock", 1, true) ~= nil)
	local ok = f.call(config.unlockVault, "a wrong fixture password")
	check("wrong password leaves the vault locked", not ok and config.vaultStatus().locked and f.record().apiKey == "")
	check("wrong password never alters the saved ciphertext", same(f.util.decode(f.disk()).credentialVault, envelope))
	local cancelled, why = f.call(config.unlockVault, PASSWORD, { cancelled = function() return true end })
	check("cancelled unlock leaves the vault locked", not cancelled and why == "Cancelled" and config.vaultStatus().locked)
	assert(f.call(config.unlockVault, PASSWORD))
	check("correct password restores existing live provider identity and complete protected fields", f.record() == locked and same(f.record(), f.expected))
	check("successful unlock restores identity authentication", config.data.identity.extraHeaders["X-Identity"] == "vault-identity-secret")
	f.finish()
end)

case("an interrupted primary write recovers from verified encrypted staging", function()
	local f = setup(); local config = f.config
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	local before = f.disk()
	caps.fn.writefile = function(path, body)
		if path == "UAI/config.vault.pending.json" then f.h.files[path] = "{"; return true end
		return write(path, body)
	end
	check("unverified staging cannot touch the old primary", not f.call(config.enableVault, PASSWORD) and f.disk() == before)
	caps.fn.writefile = function(path, body)
		if path == "UAI/config.json" then f.h.files[path] = "{"; return true end
		return write(path, body)
	end
	check("primary and rollback failure retain usable live credentials", not f.call(config.enableVault, PASSWORD)
		and not config.vaultStatus().enabled and f.record().apiKey == f.expected.apiKey)
	local pending = f.h.files["UAI/config.vault.pending.json"]
	check("retained recovery file contains verified ciphertext only", type(f.util.decode(pending).credentialVault) == "table" and excludes(pending))
	caps.fn.writefile = write
	-- A torn overwrite can still be syntactically valid JSON.
	f.h.files["UAI/config.json"] = "{}"
	config.load()
	check("startup recovers the interrupted vault as locked", config.vaultStatus().locked and f.record().apiKey == ""
		and type(f.util.decode(f.disk()).credentialVault) == "table")
	assert(f.call(config.unlockVault, PASSWORD))
	check("recovered vault restores the exact original key pool", same(f.record(), f.expected))
	check("successful primary recovery removes stale staging", f.h.files["UAI/config.vault.pending.json"] == nil)
	f.finish()
end)

case("cancellation after staging stops before the primary commit", function()
	local f = setup(); local config = f.config; local before = f.disk()
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	local staged = false
	caps.fn.writefile = function(path, body)
		local result = write(path, body)
		if path == "UAI/config.vault.pending.json" then staged = true end
		return result
	end
	local ok, why = f.call(config.enableVault, PASSWORD, { cancelled = function() return staged end })
	check("staging cancellation reports no committed migration", staged and not ok and why == "Cancelled"
		and not config.vaultStatus().enabled and f.disk() == before)
	check("staging cancellation retains the original live keys", f.record().apiKey == f.expected.apiKey)
	local pending = f.h.files["UAI/config.vault.pending.json"]
	check("cancelled staging cannot become a recoverable vault later", pending == nil or f.util.decode(pending).credentialVault == nil)
	caps.fn.writefile = write; f.finish()
end)

case("primary commits settle once and reentrant reload waits for the save", function()
	local f = setup(); local config = f.config
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	local committed = false
	caps.fn.writefile = function(path, body)
		local result = write(path, body)
		if path == "UAI/config.json" then committed = true end
		return result
	end
	check("cancel after the primary commit cannot undo successful migration", f.call(config.enableVault, PASSWORD, { cancelled = function() return committed end })
		and config.vaultStatus().enabled and not config.vaultStatus().locked)
	caps.fn.writefile = write
	assert(config.disableVault())
	local attempted, deferred = false, false
	caps.fn.writefile = function(path, body)
		local result = write(path, body)
		if path == "UAI/config.json" and not attempted then
			attempted = true
			local loaded, why = config.load()
			deferred = loaded == nil and type(why) == "string" and why ~= ""
		end
		return result
	end
	local ok = f.call(config.enableVault, PASSWORD)
	check("reentrant reload cannot replace state during the primary commit", attempted and deferred and ok
		and config.vaultStatus().enabled and not config.vaultStatus().locked and f.record().apiKey == f.expected.apiKey)
	caps.fn.writefile = write
	config.load()
	assert(f.call(config.unlockVault, PASSWORD))
	check("the committed file remains recoverable with the new password", f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("cancelled staging cleanup failures remain visible and preserve the original configuration", function()
	local f = setup(); local config = f.config; local before = f.disk()
	local caps = f.env.require("runtime/caps"); local write, remove = caps.fn.writefile, caps.fn.delfile
	local stagingWrites = 0
	caps.fn.delfile = function() return false end
	caps.fn.writefile = function(path, body)
		if path == "UAI/config.vault.pending.json" then
			stagingWrites = stagingWrites + 1
			if stagingWrites > 1 then return false end
		end
		return write(path, body)
	end
	local ok, why = f.call(config.enableVault, PASSWORD, { cancelled = function() return stagingWrites > 0 end })
	check("cleanup failure is reported instead of hidden as ordinary cancellation", not ok and tostring(why):find("could not be removed", 1, true)
		and config.storageError == why)
	check("cleanup failure cannot replace the primary or lose live keys", f.disk() == before and not config.vaultStatus().enabled
		and f.record().apiKey == f.expected.apiKey)
	caps.fn.writefile, caps.fn.delfile = write, remove
	f.enable()
	check("successful retry clears the staging failure", config.storageError == nil and config.vaultStatus().enabled
		and f.h.files["UAI/config.vault.pending.json"] == nil)
	f.finish()
end)

case("busy derivation blocks credential mutations and invalidates work after reload", function()
	local f = setup(); local config = f.config
	local before, attempted = f.disk(), false
	local ok, why = f.call(config.enableVault, PASSWORD, { progress = function(done)
		if done == 0 and not attempted then
			attempted = true
			check("busy vault rejects a second setup operation", not config.enableVault(CHANGED))
			check("busy vault rejects credential edits", config.set("identity.extraHeaders", { Authorization = "changed" }) == nil)
			config.load()
		end
		return true
	end })
	check("reload cancels the stale derivation", attempted and not ok and why == "Cancelled")
	check("stale completion cannot enable a vault or replace original credentials", not config.vaultStatus().enabled
		and f.disk() == before and f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("invalid vault options are rejected before claiming operation ownership", function()
	local f = setup(); local before = f.disk()
	for _, options in ipairs({ true, false, 42, function() end, { progress = true }, { cancelled = "invalid" } }) do
		local called, ok = pcall(f.config.enableVault, PASSWORD, options)
		check("invalid options return failure without throwing or retaining busy state", called and ok == false and not f.config.vaultStatus().busy)
		check("invalid options preserve saved and live credentials", f.disk() == before and not f.config.vaultStatus().enabled
			and f.record().apiKey == f.expected.apiKey)
	end
	f.enable()
	check("valid setup still succeeds after rejected options", f.config.vaultStatus().enabled and not f.config.vaultStatus().busy)
	f.finish()
end)

case("encrypted updates save before locking and new startup restores the updated selected key", function()
	local f = setup(); local config = f.config; f.enable()
	local record = f.record()
	record.apiKey = "vault-key-one\nvault-key-two-updated"
	record.keyNames[2] = "Updated backup"
	assert(config.saveNow(true))
	check("ordinary saves continue encrypting updated keys", not f.disk():find("vault-key-two-updated", 1, true) and excludes(f.disk()))
	assert(config.lockVault())
	check("locking clears provider and identity credentials while preserving live table ownership", f.record() == record and record.apiKey == ""
		and config.vaultStatus().locked and next(config.data.identity.extraHeaders) == nil)
	config.set("ui.fontScale", 1.1); f.h.settle(1)
	check("unrelated locked saves retain ciphertext", f.util.decode(f.disk()).credentialVault ~= nil)
	config.load(); assert(f.call(config.unlockVault, PASSWORD))
	check("unlock restores latest selected key and unrelated saved changes", f.record().apiKey == "vault-key-one\nvault-key-two-updated"
		and f.record().selectedKey == 2 and f.record().keyNames[2] == "Updated backup" and config.get("ui.fontScale") == 1.1)
	f.finish()
end)

case("nested resets cannot discard a locked credential vault", function()
	local f = setup(); f.enable(); assert(f.config.lockVault())
	local before = f.disk()
	for _, path in ipairs({ "providers.list", "providers.list.1.apiKey", "identity.extraHeaders", "security.rememberCredentials", "credentialVault.data" }) do
		check("credential reset path is rejected", not f.config.reset(path))
	end
	check("rejected resets keep the same saved vault", f.disk() == before and f.config.vaultStatus().locked)
	assert(f.call(f.config.unlockVault, PASSWORD)); check("keys survive rejected resets", f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("fresh included access keeps its reference and pool settings through same-session locking", function()
	local f = setup(); local registry = f.env.require("provider/registry")
	local community = f.env.require("provider/community_key")
	local record = registry.blank("projectuai-free")
	record.keyNames, record.keyPaused, record.keyMode, record.selectedKey = { "Included fixture" }, { true }, "single", 1
	record.keyIds = { "33333333-3333-4333-8333-333333333333" }
	assert(registry.save(record))
	check("included fixture starts applied without a persisted reference", community.isApplied(record))
	f.enable(); assert(f.config.lockVault()); assert(f.call(f.config.unlockVault, PASSWORD))
	check("included access restores without a cold-load migration", community.isApplied(record) and record.communityCredential == true)
	check("included key metadata and accounting identity remain exact", record.keyNames[1] == "Included fixture" and record.keyPaused[1]
		and record.keyMode == "single" and record.selectedKey == 1 and record.keyIds[1] == "33333333-3333-4333-8333-333333333333")
	check("private provider beside included access remains intact", f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("credential filesystem errors cannot echo raw host details into diagnostics", function()
	local f = setup(); local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	local log = f.env.require("runtime/log"); log.mirror = true
	caps.fn.writefile = function() error("host leaked vault-key-one and " .. PASSWORD) end
	local ok, why = f.call(f.config.enableVault, PASSWORD)
	check("host failure yields a bounded storage explanation", not ok and excludes(tostring(why)))
	check("structured logs exclude arbitrary host credential echoes", excludes(f.util.encode(log.entries)))
	check("console diagnostics exclude arbitrary host credential echoes", excludes(table.concat(f.h.console.warnings, "\n")))
	caps.fn.writefile = write; f.finish()
end)

case("password changes verify the new file before accepting the new password", function()
	local f = setup(); local config = f.config; f.enable()
	local before = f.disk()
	local write = f.env.require("runtime/caps").fn.writefile
	f.env.require("runtime/caps").fn.writefile = function() return false end
	local ok = f.call(config.changeVaultPassword, CHANGED)
	check("failed password change keeps the original vault and unlocked keys", not ok and f.disk() == before and not config.vaultStatus().locked)
	f.env.require("runtime/caps").fn.writefile = write
	assert(config.lockVault()); assert(f.call(config.unlockVault, PASSWORD))
	assert(f.call(config.changeVaultPassword, CHANGED)); config.load()
	check("old password cannot unlock the new envelope", not f.call(config.unlockVault, PASSWORD) and config.vaultStatus().locked)
	assert(f.call(config.unlockVault, CHANGED))
	check("new password restores the original key pool", f.record().apiKey == f.expected.apiKey and same(f.record().keyIds, f.expected.keyIds))
	check("neither password is stored in the file", excludes(f.disk()))
	f.finish()
end)

case("damaged and future vaults stay recoverable without automatic overwrite", function()
	for _, mutate in ipairs({ function(value) value.version = 999 end,
		function(value) value.data = (value.data:sub(1, 1) == "0" and "1" or "0") .. value.data:sub(2) end }) do
		local f = setup(); local config = f.config; f.enable()
		local saved = f.util.decode(f.disk()); mutate(saved.credentialVault)
		f.h.files["UAI/config.json"] = f.util.encode(saved)
		local broken = f.disk()
		config.load()
		check("unreadable vault remains locked", config.vaultStatus().enabled and config.vaultStatus().locked and f.record().apiKey == "")
		check("unreadable vault cannot unlock", not f.call(config.unlockVault, PASSWORD))
		check("failed unlock keeps exact recovery bytes", f.disk() == broken)
		f.finish()
	end
end)

case("private exports preserve encryption and import requires the source password", function()
	local f = setup(); f.enable()
	local transfer = f.env.require("runtime/config_transfer")
	local public = assert(transfer.export())
	local publicData = f.util.decode(public)
	check("ordinary exports omit vault and connection credentials", publicData.config.credentialVault == nil and excludes(public)
		and publicData.credentialsIncluded == false and publicData.config.bridge.token == "")
	local private = assert(transfer.export({ includeCredentials = true }))
	local privateData = f.util.decode(private)
	check("private exports carry an encrypted vault without plaintext keys", type(privateData.config.credentialVault) == "table" and excludes(private))
	local preview, _, reason = transfer.preview(private)
	check("encrypted import asks for its source password", preview == nil and reason == "password")
	check("incorrect source password cannot create a preview", f.call(transfer.preview, private, { password = CHANGED }) == nil)
	preview = assert(f.call(transfer.preview, private, { password = PASSWORD }))
	check("review restores the complete source key pool", preview.config.providers.list[1].apiKey == f.expected.apiKey and preview.summary.keys == 2)
	local receiving = setup(); assert(receiving.config.setRememberCredentials(false))
	local receiver = receiving.env.require("runtime/config_transfer")
	local imported = assert(receiving.call(receiver.preview, private, { password = PASSWORD }))
	assert(receiver.apply(imported))
	check("session-only receiver retains its own storage policy", receiving.config.get("security.rememberCredentials") == false
		and not receiving.config.vaultStatus().enabled and receiving.record().apiKey == f.expected.apiKey)
	check("session-only imported keys never reach disk", excludes(receiving.disk()) and receiving.util.decode(receiving.disk()).credentialVault == nil)
	receiving.finish(); f.finish()
end)

case("imports into an unlocked local vault keep its password and locked imports are rejected", function()
	local source = setup(); source.enable()
	local private = assert(source.env.require("runtime/config_transfer").export({ includeCredentials = true }))
	local f = setup(); assert(f.call(f.config.enableVault, CHANGED))
	local transfer = f.env.require("runtime/config_transfer")
	local preview = assert(f.call(transfer.preview, private, { password = PASSWORD }))
	assert(f.config.lockVault())
	check("locked destination cannot replace its saved credentials", not transfer.apply(preview) and f.config.vaultStatus().locked)
	assert(f.call(f.config.unlockVault, CHANGED)); assert(transfer.apply(preview)); f.config.load()
	check("source password does not replace the destination password", not f.call(f.config.unlockVault, PASSWORD))
	assert(f.call(f.config.unlockVault, CHANGED))
	check("destination password decrypts imported credentials", f.record().apiKey == f.expected.apiKey and f.config.vaultStatus().enabled)
	f.finish(); source.finish()
end)

case("disable keeps live keys session-only and reset explicitly removes locked credentials", function()
	local f = setup(); local config = f.config; f.enable()
	local live = f.record()
	assert(config.disableVault())
	check("disable removes saved vault and selects session-only storage", not config.vaultStatus().enabled and config.get("security.rememberCredentials") == false
		and f.util.decode(f.disk()).credentialVault == nil and excludes(f.disk()))
	check("disable preserves exact live credential ownership", f.record() == live and live.apiKey == f.expected.apiKey)
	f.enable(); assert(config.lockVault())
	check("locked vault cannot silently downgrade storage", not config.setRememberCredentials(false) and config.vaultStatus().locked)
	assert(config.resetVault())
	check("explicit reset removes encrypted data and live keys", not config.vaultStatus().enabled and f.record().apiKey == ""
		and f.util.decode(f.disk()).credentialVault == nil and config.get("security.rememberCredentials") == false)
	check("reset retains ordinary provider settings and marks omitted credentials", f.record().model == "fixture-model"
		and f.record().credentialsOmitted and config.data.memory.entries[1].value == "Keep this setting")
	config.load()
	check("reset cannot restore old credentials after restart", f.record().apiKey == "" and not config.vaultStatus().enabled)
	f.finish()
end)

case("failed removal and unavailable filesystem cannot report successful protection", function()
	local f = setup(); local config = f.config; f.enable()
	local before, live = f.disk(), f.record()
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	caps.fn.writefile = function() return false end
	check("failed disable retains active vault and live keys", not config.disableVault() and config.vaultStatus().enabled
		and f.record() == live and live.apiKey == f.expected.apiKey and f.disk() == before)
	caps.fn.writefile = write
	assert(config.lockVault()); before = f.disk()
	caps.fn.writefile = function() return false end
	check("failed reset retains recoverable locked ciphertext", not config.resetVault() and config.vaultStatus().locked and f.disk() == before)
	caps.fn.writefile = write
	assert(f.call(config.unlockVault, PASSWORD)); assert(config.disableVault())
	f.env.require("runtime/fsx").enabled = false
	check("vault cannot be enabled without verified persistent storage", not f.call(config.enableVault, PASSWORD) and not config.vaultStatus().enabled
		and f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("vault removal verifies retained recovery data when the host cannot delete files", function()
	local f = setup(); f.enable()
	local caps = f.env.require("runtime/caps"); local remove = caps.fn.delfile
	f.h.files["UAI/config.vault.pending.json"] = f.disk()
	caps.fn.delfile = function() return false end
	assert(f.config.disableVault())
	local pending = f.h.files["UAI/config.vault.pending.json"]
	check("undeletable recovery copy is overwritten without protected credentials", type(pending) == "string"
		and f.util.decode(pending).credentialVault == nil and excludes(pending))
	check("session-only live keys remain usable after verified recovery cleanup", not f.config.vaultStatus().enabled
		and f.record().apiKey == f.expected.apiKey)
	caps.fn.delfile = remove; f.finish()
end)

case("failed recovery cleanup rolls back removal and cold startup preserves the last encrypted copy", function()
	for _, discard in ipairs({ false, true }) do
		for _, failRollback in ipairs({ false, true }) do
			local f = setup(); f.enable()
			if discard then assert(f.config.lockVault()) end
			local before = f.disk()
			f.h.files["UAI/config.vault.pending.json"] = before
			local caps = f.env.require("runtime/caps"); local write, remove = caps.fn.writefile, caps.fn.delfile
			local primaryWrites = 0
			caps.fn.delfile = function() return false end
			caps.fn.writefile = function(path, body)
				if path == "UAI/config.vault.pending.json" then return false end
				if path == "UAI/config.json" then
					primaryWrites = primaryWrites + 1
					if failRollback and primaryWrites > 1 then return false end
				end
				return write(path, body)
			end
			local ok
			if discard then ok = f.config.resetVault() else ok = f.config.disableVault() end
			check("failed stage cleanup cannot report successful removal", not ok and f.config.vaultStatus().enabled)
			check("failed removal preserves original encrypted recovery data", f.h.files["UAI/config.vault.pending.json"] == before)
			if failRollback then
				check("rollback failure can leave only the stage encrypted", f.util.decode(f.disk()).security.rememberCredentials == false
					and f.util.decode(f.disk()).credentialVault == nil)
			else check("successful rollback restores the exact primary bytes", f.disk() == before) end
			caps.fn.writefile, caps.fn.delfile = write, remove
			f.config.load()
			check("cold startup keeps the recoverable vault locked", f.config.vaultStatus().locked and f.record().apiKey == "")
			assert(f.call(f.config.unlockVault, PASSWORD))
			check("cold recovery restores keys after failed removal", f.record().apiKey == f.expected.apiKey and same(f.record().keyIds, f.expected.keyIds))
			f.finish()
		end
	end
end)

case("generic security setters and resets cannot bypass verified legacy storage changes", function()
	local f = setup(); local config = f.config; local before = f.disk()
	check("whole security replacement is rejected", not config.set("security", { rememberCredentials = false }))
	check("whole security reset is rejected", not config.reset("security"))
	check("nested storage reset is rejected", not config.reset("security.rememberCredentials"))
	check("rejected generic changes preserve the remembered preference and saved bytes", config.get("security.rememberCredentials") == true and f.disk() == before)
	assert(config.setRememberCredentials(false))
	before = f.disk()
	check("generic replacement cannot re-enable remembering", not config.set("security", { rememberCredentials = true }))
	check("generic reset cannot re-enable remembering", not config.reset("security"))
	check("session-only choice remains after rejected bypasses", config.get("security.rememberCredentials") == false and f.disk() == before
		and f.record().apiKey == f.expected.apiKey)
	f.finish()
end)

case("unlocked migrated credentials reach the real provider adapter with the selected key", function()
	local f = setup(); local config = f.config; f.enable(); config.load(); assert(f.call(config.unlockVault, PASSWORD))
	local requests = {}
	f.h.http.handler = function(entry)
		requests[#requests + 1] = entry
		return { StatusCode = 200, Body = f.h.json.encode({ choices = {
			{ message = { role = "assistant", content = "vault credentials work" }, finish_reason = "stop" },
		} }) }
	end
	local response = f.run(function() return f.env.require("provider/chat").complete(f.record(), {
		messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1, maxTokens = 16,
	}) end)
	check("migrated and unlocked provider completes one synthetic request", response and response.content == "vault credentials work" and #requests == 1)
	local entry = requests[1]; local get = f.env.require("net/headers").get
	check("request uses selected unpaused key and restored private headers", get(entry.headers, "Authorization") == "Bearer vault-key-two"
		and get(entry.headers, "X-Fixture") == "vault-header-secret" and get(entry.headers, "X-Identity") == "vault-identity-secret")
	check("request restores URL query and body authentication", entry.url:find("vault-url-secret", 1, true)
		and entry.url:find("vault-query-secret", 1, true) and f.h.json.decode(entry.body).custom_auth == "vault-body-secret")
	f.finish()
end)

case("only a verified explicit unprotected choice releases initial access", function()
	local f = setup(); local config = f.config
	config.requireVault(); local before, live, identity = f.disk(), f.record(), config.data.identity
	local imported = f.util.deepCopy(config.data); imported.security.credentialProtection = "unprotected"
	check("legacy remembered data is undecided and gated", not config.vaultStatus().ready and config.vaultStatus().protection == "undecided")
	check("generic setter and imported preference cannot opt out", config.set("security.credentialProtection", "unprotected") == nil
		and config.replace(imported) == false and not config.vaultStatus().ready and f.disk() == before)
	for _, path in ipairs({ ".security.credentialProtection", "security..credentialProtection", "security.credentialProtection." }) do
		check("empty path segments cannot bypass verified protection choice", config.set(path, "unprotected") == nil and not config.vaultStatus().ready)
	end
	assert(f.call(config.continueWithoutEncryption))
	local saved = f.util.decode(f.disk())
	check("explicit choice is saved without claiming encryption", config.vaultStatus().ready and config.accessProblem() == nil
		and config.vaultStatus().protection == "unprotected" and not config.vaultStatus().enabled
		and saved.security.credentialProtection == "unprotected" and saved.credentialVault == nil)
	check("unprotected persistence uses reversible bytes", saved.providers.list[1].storedCredentials ~= nil
		and f.env.require("runtime/credential_codec").decode(saved.providers.list[1].storedCredentials).fields.apiKey == f.expected.apiKey)
	check("explicit optout retains live record ownership and identity credentials", f.record() == live and config.data.identity == identity
		and live.apiKey == f.expected.apiKey and identity.extraHeaders["X-Identity"] == "vault-identity-secret")
	config.requireVault()
	check("reexecution honors the saved unprotected choice", config.vaultStatus().ready and config.accessProblem() == nil)
	config.load()
	check("cold restart honors the choice and restores exact protected fields", config.vaultStatus().ready and same(f.record(), f.expected)
		and config.get("security.rememberCredentials") and config.get("identity.extraHeaders")["X-Identity"] == "vault-identity-secret")
	f.finish()
end)

case("unprotected choice cannot succeed after cancellation, failed write or unavailable persistence", function()
	local f = setup(); local config = f.config; config.requireVault()
	local before, live = f.disk(), f.record()
	local ok, why = f.call(config.continueWithoutEncryption, { cancelled = function() return true end })
	check("precommit cancellation retains the gate and original bytes", not ok and why == "Cancelled" and not config.vaultStatus().ready and f.disk() == before)
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	caps.fn.writefile = function() return true end
	check("a lying writer cannot grant unprotected access", not f.call(config.continueWithoutEncryption) and not config.vaultStatus().ready
		and config.get("security.credentialProtection") == "password" and f.disk() == before)
	caps.fn.writefile = write
	f.env.require("runtime/fsx").enabled = false
	check("missing filesystem cannot grant an unsaved optout", not f.call(config.continueWithoutEncryption) and not config.vaultStatus().ready
		and f.record() == live and live.apiKey == f.expected.apiKey)
	f.env.require("runtime/fsx").enabled = true
	assert(f.call(config.continueWithoutEncryption))
	check("verified retry clears the error and admits access", config.vaultStatus().ready and config.storageError == nil)
	f.finish()
end)

case("an existing vault must be authenticated before preserving keys in unprotected storage", function()
	local f = setup(); local config = f.config; config.requireVault(); f.enable()
	local original = config.data.credentialVault
	config.requireVault()
	check("warm password challenge cannot be skipped by opting out", not f.call(config.continueWithoutEncryption)
		and config.vaultStatus().enabled and not config.vaultStatus().ready)
	assert(config.lockVault()); local before = f.disk()
	config.data.security.credentialProtection = "unprotected"
	check("ciphertext wins over a stray unprotected preference", config.vaultStatus().protection == "password"
		and not config.vaultStatus().ready and not f.call(config.continueWithoutEncryption) and f.disk() == before)
	assert(f.call(config.unlockVault, PASSWORD))
	local live = f.record(); live.apiKey, live.keyNames[2] = "vault-key-one\nlatest-unprotected-key", "Latest name"
	assert(f.call(config.continueWithoutEncryption))
	check("authenticated optout preserves latest live edits and releases its session key", f.record() == live and live.apiKey == "vault-key-one\nlatest-unprotected-key"
		and f.env.require("runtime/credential_vault").key(original) == nil and config.vaultStatus().protection == "unprotected")
	config.load()
	check("unprotected restart retains the edited pool and selected key", config.vaultStatus().ready and f.record().apiKey == "vault-key-one\nlatest-unprotected-key"
		and f.record().keyNames[2] == "Latest name" and f.record().selectedKey == 2 and same(f.record().keyIds, f.expected.keyIds))
	f.enable()
	check("reenabling protection removes the old optout from disk", config.vaultStatus().protection == "password"
		and f.util.decode(f.disk()).security.credentialProtection == "password")
	assert(config.resetVault())
	check("explicit vault reset returns to undecided setup", not config.vaultStatus().ready and config.vaultStatus().protection == "undecided")
	f.finish()
end)

case("failed unprotected transitions retain encrypted recovery across primary and rollback failures", function()
	for _, phase in ipairs({ "staging", "primary", "cleanup" }) do
		local f = setup(); local config = f.config; config.requireVault(); f.enable()
		f.record().keyNames[2] = "Unsaved latest name"
		local before = f.disk()
		local caps = f.env.require("runtime/caps"); local write, remove = caps.fn.writefile, caps.fn.delfile
		local primaryWrites, stagingWrites = 0, 0
		caps.fn.delfile = function() return false end
		caps.fn.writefile = function(path, body)
			if path == "UAI/config.vault.pending.json" then
				stagingWrites = stagingWrites + 1
				if phase == "staging" or (phase == "cleanup" and stagingWrites > 1) then return false end
			end
			if path == "UAI/config.json" then
				primaryWrites = primaryWrites + 1
				if phase == "primary" then f.h.files[path] = "{"; return true end
				if phase == "cleanup" and primaryWrites > 1 then return false end
			end
			return write(path, body)
		end
		check("failed " .. phase .. " retains the active vault", not f.call(config.continueWithoutEncryption)
			and config.vaultStatus().enabled and config.vaultStatus().protection == "password" and f.record().apiKey == f.expected.apiKey)
		if phase == "staging" then
			check("unverified recovery cannot touch the primary", f.disk() == before and primaryWrites == 0)
		else
			local pending = f.util.decode(f.h.files["UAI/config.vault.pending.json"])
			check("failed transition retains encrypted recovery", pending and pending.credentialVault ~= nil)
		end
		caps.fn.writefile, caps.fn.delfile = write, remove
		config.load()
		check("cold recovery never honors failed unprotected transition", config.vaultStatus().enabled and not config.vaultStatus().ready)
		assert(f.call(config.unlockVault, PASSWORD))
		check("recovered ciphertext retains its key pool", f.record().apiKey == f.expected.apiKey and same(f.record().keyIds, f.expected.keyIds))
		if phase ~= "staging" then check("recovery includes latest unsaved credential metadata", f.record().keyNames[2] == "Unsaved latest name") end
		f.finish()
	end
end)

case("unprotected transition owns yielding storage and keeps concurrent ordinary preferences", function()
	local f = setup(); local config = f.config; config.requireVault()
	local caps = f.env.require("runtime/caps"); local write = caps.fn.writefile
	local entered, result = false, nil
	caps.fn.writefile = function(path, body)
		if path == "UAI/config.json" and not entered then entered = true; f.h.sched.wait(0.25) end
		return write(path, body)
	end
	f.h.sched.spawn(function() result = { config.continueWithoutEncryption() } end)
	check("pending unprotected save keeps the access gate closed", entered and result == nil and config.vaultStatus().busy and not config.vaultStatus().ready)
	check("concurrent protection and credential edits are rejected", not config.continueWithoutEncryption() and not config.enableVault(PASSWORD)
		and config.set("identity.extraHeaders", {}) == nil and config.load() == nil)
	assert(config.set("ui.fontScale", 1.2))
	f.h.sched.advance(0.3); caps.fn.writefile = write
	check("verified completion opens access and retains newer preferences", result and result[1] and config.vaultStatus().ready
		and config.get("ui.fontScale") == 1.2 and config.dirty)
	f.h.sched.advance(1)
	check("subsequent save persists the latest preference in unprotected mode", f.util.decode(f.disk()).ui.fontScale == 1.2
		and f.util.decode(f.disk()).security.credentialProtection == "unprotected")
	f.finish()
end)

case("a fresh password challenge before optout commit invalidates earlier authentication", function()
	local f = setup(); local config = f.config; config.requireVault(); f.enable()
	local challenged, before = false, f.disk()
	local disconnect = config.changed:connect(function(path, state)
		if path == "security.vault" and state.busy and not challenged then
			challenged = true
			config.requireVault()
		end
	end)
	local ok, why = f.call(config.continueWithoutEncryption)
	disconnect()
	check("reentrant challenge cancels optout before persistence", challenged and not ok and why == "Cancelled" and f.disk() == before)
	check("earlier unlocked key cannot satisfy the new challenge", config.vaultStatus().enabled and not config.vaultStatus().ready)
	assert(f.call(config.unlockVault, PASSWORD)); assert(f.call(config.continueWithoutEncryption))
	check("explicit retry after authentication can select unprotected storage", config.vaultStatus().protection == "unprotected" and config.vaultStatus().ready)
	f.finish()
end)

case("imports preserve this device's protection choice and legacy work factors remain readable", function()
	local f = setup(); local config = f.config
	local imported = f.util.deepCopy(config.data); imported.security.credentialProtection = "unprotected"
	assert(config.replace(imported))
	check("an imported flag cannot choose unprotected storage", config.get("security.credentialProtection") == "password")
	assert(f.call(config.continueWithoutEncryption))
	imported.security.credentialProtection = "password"
	assert(config.replace(imported))
	check("an imported password preference cannot undo local optout", config.vaultStatus().protection == "unprotected")
	local vault = f.env.require("runtime/credential_vault")
	vault.iterations = 600000; f.enable(); vault.iterations = 100000
	config.load(); assert(f.call(config.unlockVault, PASSWORD)); assert(config.saveNow(true))
	check("older work factors survive unlock and ordinary saves", f.util.decode(f.disk()).credentialVault.iterations == 600000)
	assert(f.call(config.changeVaultPassword, PASSWORD))
	check("explicit password rewrite uses the new work factor", f.util.decode(f.disk()).credentialVault.iterations == 100000)
	config.load(); assert(f.call(config.unlockVault, PASSWORD))
	check("the rewritten vault preserves all original credentials", f.record().apiKey == f.expected.apiKey and same(f.record().keyIds, f.expected.keyIds))
	f.finish()
end)

suite.finish()
