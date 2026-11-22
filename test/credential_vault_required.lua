-- Required password access through the shipping bootstrap; synthetic keys only.
-- AES/envelopes are real. Derivation is shortened only inside these fixtures;
-- full production KDF vectors and native timing have separate coverage.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F, envMock, luau = require("workspace_fixture"), require("env"), require("luau")
local suite = F.suite("Required credential vault")
local case, check = suite.case, suite.check
local PASSWORD = "required fixture master password"
local NEXT_PASSWORD = "replacement fixture master password"
local FILE = "UAI/config.json"
local file = assert(io.open("dist/uai.lua", "rb")); local source = file:read("*a"); file:close()
local compiled = {}
local function boot(h, context, build)
	local id = build or "current"
	if not compiled[id] then
		local body = source
		if build then body = body:gsub('local __UAI_BUILD = "[^"]+"', 'local __UAI_BUILD = "' .. build .. '"', 1) end
		compiled[id] = assert(luau.load(body, "required-vault-" .. id, { entry = true }))
	end
	setfenv(compiled[id], h.sandbox)
	local handle = assert(compiled[id](context))
	h.settle(1)
	return handle
end
local function cheapKdf(env)
	local crypto, sha = env.require("runtime/credential_crypto"), env.require("runtime/credential_sha256")
	crypto.derive = function(password, salt, _, progress)
		if progress and progress(0, 1) == false then return nil, crypto.error end
		local key = sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
		if progress and progress(1, 1) == false then return nil, crypto.error end
		return key
	end
end
local function run(h, method, ...)
	local result, args = nil, { ... }
	h.sched.spawn(function() result = { method(unpack(args)) } end)
	h.sched.advance(1)
	assert(result, h.errors()[1] and h.errors()[1].traceback or "required-vault operation did not finish")
	return unpack(result)
end
local function seed(plaintext, sessionOnly)
	local f = F.new(); local config, util = f.env.require("runtime/config"), f.env.require("runtime/util")
	local data = util.deepCopy(config.defaults)
	data.ui.tutorial.seen, data.ui.communityInvite.disabled = true, true
	data.bridge.autoDiscover = false
	data.security.rememberCredentials = not sessionOnly
	data.providers = { active = "required-fixture", list = { {
		id = "required-fixture", label = "Required fixture", preset = "custom", api = "openai", authStyle = "bearer",
		baseUrl = "https://required.fixture/v1?route=required-url-secret", apiKey = "required-first-key\nrequired-second-key",
		keyNames = { "First", "Selected" }, keyPaused = { true, false }, keyMode = "single", selectedKey = 2,
		keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" },
		model = "fixture-model", models = { "fixture-model" }, headers = { ["X-Fixture"] = "required-header-secret" },
		query = { route = "required-query-secret" }, params = { custom_auth = "required-body-secret" },
	} } }
	data.identity.extraHeaders = { ["X-Identity"] = "required-identity-secret" }
	local record = util.deepCopy(data.providers.list[1])
	local body = util.encode(plaintext and data or assert(f.env.require("runtime/credentials").persistent(data)))
	f.close()
	return body, record
end
local function healthy(h)
	check("fixture has no asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
end
local function named(h, name)
	return h.find(h.coreGui, function(node) return node.Name == name end)[1]
end

case("legacy startup opens mandatory setup and blocks inference and tools before password entry", function()
	local h = envMock.new(); local body, expected = seed(false)
	h.files[FILE] = body
	local handle = boot(h)
	local status = handle.config.vaultStatus()
	check("bootstrap requires a vault before admitting work", status.required == true and status.ready == false and not status.enabled
		and type(handle.config.accessProblem()) == "string")
	check("the required password controls open automatically", named(h, "CredentialVault") ~= nil and named(h, "VaultPassword") ~= nil)
	local provider = assert(handle.providers.get(expected.id))
	check("legacy live keys are retained for migration", provider.apiKey == expected.apiKey and provider.keyIds[2] == expected.keyIds[2])
	check("startup preserves the existing encoded file until password setup", h.files[FILE] == body)
	local transfer = handle.env.require("runtime/config_transfer")
	local imported = { config = assert(transfer.validate(handle.config.defaults)) }
	local importBody = h.json.encode({ format = transfer.FORMAT, version = transfer.VERSION, config = imported.config })
	check("configuration transfers and replacement cannot bypass required setup", transfer.export() == nil
		and transfer.export({ includeCredentials = true }) == nil and transfer.preview(importBody) == nil
		and transfer.apply(imported) == false and handle.config.replace(imported.config) == false
		and not handle.config.vaultStatus().ready and h.files[FILE] == body)
	local accepted, why = handle.ask("Must wait for password")
	check("normal chat admission requires the password", accepted == false and type(why) == "string")
	local executed = false
	handle.tools.register({ name = "required_probe", description = "Synthetic required gate probe", group = "fixture", risk = "read",
		parameters = { type = "object", properties = {} }, run = function() executed = true; return "ran" end })
	local result = run(h, handle.tools.dispatch, { id = "required-probe", name = "required_probe", arguments = "{}" },
		{ env = handle.env, session = {}, aborted = function() return false end })
	check("direct tool dispatch cannot bypass startup", result.ok == false and result.error == "vault required" and not executed)
	local requests = 0
	h.http.handler = function() requests = requests + 1; return { StatusCode = 500, Body = "must not send" } end
	local reply = run(h, handle.env.require("provider/chat").complete, provider,
		{ messages = { { role = "user", content = "Must wait" } }, stream = false, attempts = 1 })
	check("direct provider completion is refused before HTTP", reply == nil and requests == 0)
	assert(h.click(assert(named(h, "VaultCancel"))))
	check("Cancel cannot dismiss required access", handle.config.vaultStatus().ready == false and named(h, "CredentialVault") ~= nil)
	cheapKdf(handle.env)
	assert(run(h, handle.config.enableVault, PASSWORD))
	h.settle(0.6)
	check("verified setup releases the access gate", handle.config.vaultStatus().ready == true and handle.config.accessProblem() == nil)
	check("setup retains exact selected key and metadata", provider.apiKey == expected.apiKey and provider.keyNames[2] == "Selected"
		and provider.keyPaused[1] and provider.selectedKey == 2 and provider.headers["X-Fixture"] == "required-header-secret"
		and handle.config.get("identity.extraHeaders")["X-Identity"] == "required-identity-secret")
	check("required setup persists encrypted credentials", h.json.decode(h.files[FILE]).credentialVault ~= nil
		and not h.files[FILE]:find("required-first-key", 1, true) and not h.files[FILE]:find(PASSWORD, 1, true))
	healthy(h); handle.destroy()
end)

case("same-build execution, changed-build replacement and cold restart require the password again", function()
	local h = envMock.new(); h.files[FILE] = seed(false)
	local context = { ui = false, reuse = true }
	local handle = boot(h, context); cheapKdf(handle.env)
	assert(run(h, handle.config.enableVault, PASSWORD))
	local transfer = handle.env.require("runtime/config_transfer")
	local importBody = assert(transfer.export())
	local imported = assert(transfer.preview(importBody))
	local live = handle.providers.get("required-fixture")
	live.apiKey, live.keyNames[2] = "required-first-key\nchanged-unsaved-key", "Unsaved name"
	local repeated = boot(h, context)
	check("same-build reuse keeps the instance but requires another unlock", repeated == handle and handle.config.vaultStatus().required
		and not handle.config.vaultStatus().ready)
	check("same-build execution opens the password prompt even with UI disabled", named(h, "CredentialVault") ~= nil)
	check("configuration transfers and replacement cannot bypass warm authentication", transfer.export() == nil
		and transfer.export({ includeCredentials = true }) == nil and transfer.preview(importBody) == nil
		and transfer.apply(imported) == false and handle.config.replace(imported.config) == false
		and not handle.config.vaultStatus().ready and live.apiKey == "required-first-key\nchanged-unsaved-key")
	check("wrong password cannot satisfy repeated execution", run(h, handle.config.unlockVault, NEXT_PASSWORD) == false
		and handle.config.vaultStatus().ready == false)
	assert(run(h, handle.config.unlockVault, PASSWORD))
	check("warm authentication preserves the live credential edits", handle.providers.get("required-fixture") == live
		and live.apiKey == "required-first-key\nchanged-unsaved-key" and live.keyNames[2] == "Unsaved name")
	handle.config.save()
	local updated = boot(h, context, "required-vault-next-build")
	check("changed build retains encrypted data and asks for the password", updated ~= handle and not handle.alive
		and updated.config.vaultStatus().required and not updated.config.vaultStatus().ready)
	cheapKdf(updated.env); assert(run(h, updated.config.unlockVault, PASSWORD))
	check("password restores the latest keys after replacement", updated.providers.get("required-fixture").apiKey == "required-first-key\nchanged-unsaved-key"
		and updated.providers.get("required-fixture").keyNames[2] == "Unsaved name")
	updated.destroy()
	local cold = boot(h, context, "required-vault-next-build")
	check("genuine restart also requires unlock", cold.config.vaultStatus().required and cold.config.vaultStatus().locked
		and cold.providers.get("required-fixture").apiKey == "")
	healthy(h); cold.destroy()
end)

case("embedding with UI disabled still prompts and keeps the app hidden after setup", function()
	local h = envMock.new(); local body, expected = seed(true); h.files[FILE] = body
	local handle = boot(h, { ui = false, reuse = true })
	check("embedding mounts the required password UI", handle.uiMounted and named(h, "CredentialVault") ~= nil)
	check("startup preserves a legacy plaintext file until encrypted setup succeeds", h.files[FILE] == body)
	check("embedding retains required access enforcement", handle.config.vaultStatus().required and not handle.config.vaultStatus().ready
		and handle.ask("Headless bypass") == false)
	cheapKdf(handle.env); assert(run(h, handle.config.enableVault, PASSWORD))
	h.settle(0.6)
	check("password setup keeps the normal application hidden", handle.config.vaultStatus().ready and not handle.app.window.root.Visible
		and named(h, "CredentialVault") == nil)
	check("plaintext migration preserves its exact key pool", handle.providers.get(expected.id).apiKey == expected.apiKey
		and handle.providers.get(expected.id).keyIds[2] == expected.keyIds[2]
		and not h.files[FILE]:find("required-first-key", 1, true))
	assert(handle.config.lockVault()); assert(handle.show())
	h.settle(0.6)
	check("show cannot bypass a locked client's required prompt", handle.uiMounted and named(h, "CredentialVault") ~= nil
		and handle.config.vaultStatus().ready == false)
	healthy(h); handle.destroy()
end)

case("legacy preferences, failed setup and forgotten-password reset cannot bypass required access", function()
	local h = envMock.new(); h.files[FILE] = seed(false, true)
	local handle = boot(h, { ui = false, reuse = true }); cheapKdf(handle.env)
	check("an old session-only preference still requires password setup", handle.config.vaultStatus().required and not handle.config.vaultStatus().ready)
	check("the legacy remembering API cannot disable protection", handle.config.setRememberCredentials(false) == false
		and not handle.config.vaultStatus().ready)
	local ok, why = run(h, handle.config.enableVault, PASSWORD, { cancelled = function() return true end })
	check("cancelled setup leaves access blocked", ok == false and why == "Cancelled" and not handle.config.vaultStatus().ready)
	local caps = handle.env.require("runtime/caps"); local write = caps.fn.writefile
	caps.fn.writefile = function() return false end
	check("failed save cannot satisfy required access", run(h, handle.config.enableVault, PASSWORD) == false and not handle.config.vaultStatus().ready)
	caps.fn.writefile = write
	assert(run(h, handle.config.enableVault, PASSWORD))
	check("an unlocked required vault cannot be disabled", handle.config.disableVault() == false and handle.config.setRememberCredentials(false) == false
		and handle.config.vaultStatus().enabled and handle.config.vaultStatus().ready)
	assert(handle.config.lockVault()); assert(handle.config.resetVault())
	check("forgotten-password reset returns to required setup", handle.config.vaultStatus().required and not handle.config.vaultStatus().enabled
		and not handle.config.vaultStatus().ready and handle.ask("Reset bypass") == false)
	assert(run(h, handle.config.enableVault, NEXT_PASSWORD))
	check("a replacement password reopens access without recovering discarded keys", handle.config.vaultStatus().ready
		and handle.providers.get("required-fixture").apiKey == "")
	healthy(h); handle.destroy()
end)

case("missing filesystem and public no-key providers cannot avoid password setup", function()
	local h = envMock.new()
	h.sandbox.readfile, h.sandbox.writefile, h.sandbox.isfile = nil, nil, nil
	local handle = boot(h, { ui = false, reuse = true }); cheapKdf(handle.env)
	check("an executor without persistence stays gated", handle.env.require("runtime/fsx").enabled == false
		and handle.config.vaultStatus().required and not handle.config.vaultStatus().ready)
	check("setup cannot pretend to persist a vault without a filesystem", run(h, handle.config.enableVault, PASSWORD) == false
		and not handle.config.vaultStatus().ready)
	local public = handle.providers.blank("kilo")
	check("public provider routing still requires the password", type(handle.providers.protocolProblem(public)) == "string")
	check("provider setup cannot bypass required access", handle.providers.save(public) == false
		and handle.config.vaultStatus().ready == false)
	healthy(h); handle.destroy()
end)

case("required Exit unloads the client even without getgenv", function()
	local h = envMock.new(); h.sandbox.getgenv = nil
	local handle = boot(h, { ui = false })
	assert(h.click(assert(named(h, "VaultExit")))); h.settle(0.6)
	check("Exit destroys the gated instance without a global handle", not handle.alive and named(h, "CredentialVault") == nil)
	healthy(h)
end)

case("explicit unprotected choice survives same-build reuse, replacement and cold restart", function()
	local h = envMock.new(); local body, expected = seed(false); h.files[FILE] = body
	local context = { ui = false, reuse = true }
	local handle = boot(h, context)
	assert(run(h, handle.config.continueWithoutEncryption)); h.settle(0.6)
	check("verified optout releases the gate while keeping the normal UI hidden", handle.config.vaultStatus().ready
		and handle.config.vaultStatus().protection == "unprotected" and named(h, "CredentialVault") == nil and not handle.app.window.root.Visible)
	check("saved optout retains the original key pool", handle.providers.get(expected.id).apiKey == expected.apiKey
		and h.json.decode(h.files[FILE]).security.credentialProtection == "unprotected")
	local repeated = boot(h, context)
	check("same-build reuse honors explicit optout", repeated == handle and repeated.config.accessProblem() == nil and named(h, "CredentialVault") == nil)
	local updated = boot(h, context, "unprotected-next-build")
	check("replacement honors optout without creating a password challenge", updated ~= handle and not handle.alive
		and updated.config.vaultStatus().ready and named(h, "CredentialVault") == nil)
	updated.destroy()
	local cold = boot(h, context, "unprotected-next-build")
	check("cold restart restores unprotected credentials without a prompt", cold.config.accessProblem() == nil
		and cold.providers.get(expected.id).apiKey == expected.apiKey and cold.providers.get(expected.id).keyIds[2] == expected.keyIds[2]
		and named(h, "CredentialVault") == nil)
	healthy(h); cold.destroy()
end)

suite.finish()
