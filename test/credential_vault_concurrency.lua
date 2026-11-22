-- Yielding executor-write ownership across legacy storage and vault transitions.
-- Files and credentials are synthetic. The real cipher uses a cheap test KDF;
-- independent password-derivation vectors remain in credential_crypto.lua.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Credential vault concurrency")
local case, check = suite.case, suite.check
local PASSWORD, KEY = "concurrent fixture master phrase", "concurrent-fixture-key"
local FILE = "UAI/config.json"

local function cheapKdf(env)
	local crypto, sha = env.require("runtime/credential_crypto"), env.require("runtime/credential_sha256")
	crypto.derive = function(password, salt, _, progress)
		if progress and progress(0, 1) == false then return nil, crypto.error end
		local key = sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
		if progress and progress(1, 1) == false then return nil, crypto.error end
		return key
	end
end
local function run(h, fn, duration)
	local result
	h.sched.spawn(function() result = { fn() } end)
	h.sched.advance(duration or 1)
	assert(result, h.errors()[1] and h.errors()[1].traceback or "pending fixture operation")
	return unpack(result)
end
local function setup()
	local f = F.new()
	cheapKdf(f.env)
	f.config, f.util = f.env.require("runtime/config"), f.env.require("runtime/util")
	f.config.load()
	local snapshot = f.util.deepCopy(f.config.defaults)
	snapshot.providers = { active = "concurrent-fixture", list = { {
		id = "concurrent-fixture", label = "Concurrent fixture", preset = "custom", api = "openai", authStyle = "bearer",
		baseUrl = "https://concurrent.fixture/v1", apiKey = KEY, model = "fixture-model", models = { "fixture-model" },
		keyIds = { "11111111-1111-4111-8111-111111111111" }, keyMode = "single", selectedKey = 1,
	} } }
	snapshot.ui.tutorial.seen, snapshot.ui.communityInvite.disabled = true, true
	f.config.data = snapshot
	assert(f.config.saveNow(true))
	return f
end
local function delayPrimary(h, env)
	local caps, entered = env.require("runtime/caps"), false
	local original = caps.fn.writefile
	caps.fn.writefile = function(path, body)
		if path == FILE and not entered then entered = true; h.sched.wait(0.25) end
		return original(path, body)
	end
	return function() return entered end, function() caps.fn.writefile = original end
end

case("a yielding legacy save blocks vault activation and preserves later preference edits", function()
	local f = setup(); local config = f.config
	local entered, restore = delayPrimary(f.h, f.env)
	local saved, original = nil, config.data
	f.h.sched.spawn(function() saved = { config.saveNow(true) } end)
	check("native write retains busy ownership until return", entered() and saved == nil and config.vaultStatus().busy)
	local enabled = config.enableVault(PASSWORD)
	check("vault activation cannot overtake a legacy writer", enabled == false and not config.vaultStatus().enabled)
	check("reload and import cannot replace the writer's live state", config.load() == nil and config.replace(f.util.deepCopy(original)) == false
		and config.data == original)
	check("credential edits are rejected while their old snapshot is being written", config.set("identity.extraHeaders", { Authorization = "concurrent-new-secret" }) == nil
		and next(config.data.identity.extraHeaders) == nil)
	check("unrelated preferences can still be edited", config.set("ui.fontScale", 1.15) == 1.15)
	f.h.sched.advance(0.3)
	check("completion releases ownership but keeps the newer preference dirty", saved and saved[1] and not config.vaultStatus().busy
		and config.dirty and config.get("ui.fontScale") == 1.15)
	f.h.sched.advance(1)
	check("a follow-up save persists preferences changed during the native write", f.util.decode(f.h.files[FILE]).ui.fontScale == 1.15 and not config.dirty)
	restore()
	assert(run(f.h, function() return config.enableVault(PASSWORD) end))
	f.h.sched.advance(1)
	local disk = f.util.decode(f.h.files[FILE])
	check("retry encrypts the existing key with no late legacy overwrite", disk.credentialVault ~= nil and disk.providers.list[1].storedCredentials == nil
		and not f.h.files[FILE]:find(KEY, 1, true))
	config.load(); assert(run(f.h, function() return config.unlockVault(PASSWORD) end))
	check("encrypted cold reload retains the original key and later preference", config.data.providers.list[1].apiKey == KEY and config.get("ui.fontScale") == 1.15)
	f.healthy(); f.close()
end)

case("legacy storage changes and imports own their complete native write", function()
	for _, kind in ipairs({ "storage", "import" }) do
		local f = setup(); local config = f.config
		local snapshot = f.util.deepCopy(config.data)
		snapshot.providers.list[1].apiKey = "imported-concurrent-fixture-key"
		local entered, restore = delayPrimary(f.h, f.env)
		local result
		f.h.sched.spawn(function()
			if kind == "storage" then result = { config.setRememberCredentials(false) }
			else result = { config.replace(snapshot) } end
		end)
		check("pending " .. kind .. " write exposes ownership", entered() and result == nil and config.vaultStatus().busy)
		check("pending " .. kind .. " cannot race an encrypted save", config.enableVault(PASSWORD) == false and config.saveNow() == false
			and config.setRememberCredentials(true) == false and config.load() == nil)
		if kind == "import" then
			check("an in-progress import rejects preferences outside its complete snapshot", config.set("ui.fontScale", 1.2) == nil
				and config.get("ui.fontScale") == 1)
		else
			check("a storage transition permits unrelated preference edits", config.set("ui.fontScale", 1.2) == 1.2)
		end
		f.h.sched.advance(0.4); restore()
		check("completed " .. kind .. " releases the persistence owner", result and result[1] and not config.vaultStatus().busy)
		f.h.sched.advance(1)
		check("completed " .. kind .. " preserves its accepted preference policy", f.util.decode(f.h.files[FILE]).ui.fontScale == (kind == "storage" and 1.2 or 1))
		assert(run(f.h, function() return config.enableVault(PASSWORD) end))
		config.load(); assert(run(f.h, function() return config.unlockVault(PASSWORD) end))
		local expected = kind == "storage" and KEY or "imported-concurrent-fixture-key"
		check("encryption after " .. kind .. " retains the accepted credentials", config.data.providers.list[1].apiKey == expected
			and f.util.decode(f.h.files[FILE]).credentialVault ~= nil)
		f.healthy(); f.close()
	end
end)

case("a yielding encrypted save blocks lock and password changes until completion", function()
	local f = setup(); local config = f.config
	assert(run(f.h, function() return config.enableVault(PASSWORD) end))
	local entered, restore = delayPrimary(f.h, f.env)
	local saved
	f.h.sched.spawn(function() saved = { config.saveNow(true) } end)
	check("encrypted native write holds the same persistence owner", entered() and saved == nil and config.vaultStatus().busy)
	check("lock, disable and password changes cannot overtake encrypted persistence", config.lockVault() == false
		and config.disableVault() == false and config.changeVaultPassword("replacement fixture phrase") == false)
	check("rejected transitions retain the live key and unlocked state", config.data.providers.list[1].apiKey == KEY and not config.vaultStatus().locked)
	f.h.sched.advance(0.4); restore()
	check("the encrypted save completes before lock retries", saved and saved[1] and not config.vaultStatus().busy)
	assert(run(f.h, config.lockVault))
	check("successful lock clears the live key after its verified write", config.vaultStatus().locked and config.data.providers.list[1].apiKey == "")
	assert(run(f.h, function() return config.unlockVault(PASSWORD) end))
	check("unlock after serialized save and lock restores the key", config.data.providers.list[1].apiKey == KEY)
	f.healthy(); f.close()
end)

case("a yielding configuration read owns the load before its verified rewrite", function()
	local f = setup(); local config, caps = f.config, f.env.require("runtime/caps")
	local read, entered, loaded = caps.fn.readfile, false, nil
	caps.fn.readfile = function(path)
		if path == FILE and not entered then entered = true; f.h.sched.wait(0.25) end
		return read(path)
	end
	f.h.sched.spawn(function() loaded = { config.load() } end)
	check("loading advertises ownership before its first file read returns", entered and loaded == nil and config.vaultStatus().busy)
	check("vault activation and writes cannot overtake an old configuration load", config.enableVault(PASSWORD) == false
		and config.saveNow() == false and config.replace(f.util.deepCopy(config.data)) == false and config.load() == nil)
	check("pending load rejects preferences that its replacement would otherwise lose", config.set("ui.fontScale", 1.3) == nil)
	f.h.sched.advance(0.4); caps.fn.readfile = read
	check("the load finishes its verified rewrite and releases ownership", loaded and loaded[1] == config.data
		and not config.vaultStatus().busy and config.data.providers.list[1].apiKey == KEY)
	assert(run(f.h, function() return config.enableVault(PASSWORD) end))
	check("vault activation can safely retry after the load", config.vaultStatus().enabled and not config.vaultStatus().locked
		and f.util.decode(f.h.files[FILE]).credentialVault ~= nil)
	f.healthy(); f.close()
end)

case("reexecution during password derivation requires a fresh authentication afterward", function()
	for _, kind in ipairs({ "setup", "cold unlock", "warm unlock" }) do
		local f = setup(); local config = f.config
		config.requireVault()
		if kind ~= "setup" then
			assert(run(f.h, function() return config.enableVault(PASSWORD) end))
			if kind == "cold unlock" then assert(run(f.h, config.lockVault)) end
			config.requireVault()
		end
		local crypto = f.env.require("runtime/credential_crypto")
		local derive, entered, result = crypto.derive, false, nil
		crypto.derive = function(...)
			entered = true; f.h.sched.wait(0.25)
			return derive(...)
		end
		f.h.sched.spawn(function()
			if kind == "setup" then result = { config.enableVault(PASSWORD) }
			else result = { config.unlockVault(PASSWORD) } end
		end)
		check(kind .. " owns its pending derivation", entered and result == nil and config.vaultStatus().busy)
		config.requireVault()
		check("new execution blocks access during " .. kind, not config.vaultStatus().ready and config.accessProblem() ~= nil)
		f.h.sched.advance(0.4); crypto.derive = derive
		check("completed " .. kind .. " retains keys without satisfying the newer execution", result and result[1]
			and config.data.providers.list[1].apiKey == KEY and config.vaultStatus().enabled and not config.vaultStatus().ready)
		check("a wrong password cannot satisfy the newer execution after " .. kind,
			run(f.h, function() return config.unlockVault("wrong concurrent master phrase") end) == false and not config.vaultStatus().ready)
		assert(run(f.h, function() return config.unlockVault(PASSWORD) end))
		check("new password entry after " .. kind .. " releases access", config.vaultStatus().ready and config.accessProblem() == nil
			and config.data.providers.list[1].apiKey == KEY)
		f.healthy(); f.close()
	end
end)

case("reexecution during the encrypted setup commit preserves storage but requires another password", function()
	local f = setup(); local config = f.config
	config.requireVault()
	local entered, restore = delayPrimary(f.h, f.env)
	local result
	f.h.sched.spawn(function() result = { config.enableVault(PASSWORD) } end)
	check("setup reaches its owned primary write", entered() and result == nil and config.vaultStatus().busy)
	config.requireVault()
	f.h.sched.advance(0.4); restore()
	check("the accepted commit completes without granting the later execution access", result and result[1]
		and config.vaultStatus().enabled and not config.vaultStatus().ready and not config.vaultStatus().busy)
	check("rechallenge does not damage the verified encrypted save", f.util.decode(f.h.files[FILE]).credentialVault ~= nil
		and not f.h.files[FILE]:find(KEY, 1, true) and config.data.providers.list[1].apiKey == KEY)
	assert(run(f.h, function() return config.unlockVault(PASSWORD) end))
	check("fresh authentication opens the successfully committed vault", config.vaultStatus().ready)
	f.healthy(); f.close()
end)

case("bootstrap refuses unload and changed-build replacement during a native write", function()
	local f = setup(); local body = f.h.files[FILE]; f.close()
	local h = require("env").new({ context = { ui = false, reuse = true } })
	h.files[FILE] = body
	local handle = assert(h.boot("dist/uai.lua")); cheapKdf(handle.env)
	assert(run(h, function() return handle.config.enableVault(PASSWORD) end))
	local entered, restore = delayPrimary(h, handle.env)
	local result
	h.sched.spawn(function() result = { handle.config.saveNow(true) } end)
	check("the bundled client exposes its pending native write", entered() and result == nil and handle.config.vaultStatus().busy)
	check("unload reports failure and retains the active client while saving", handle.destroy() == false and handle.alive
		and h.sandbox.UAI == handle)
	local file = assert(io.open("dist/uai.lua", "rb")); local source = file:read("*a"); file:close()
	source = source:gsub('local __UAI_BUILD = "[^"]+"', 'local __UAI_BUILD = "concurrency-fixture-next-build"', 1)
	local chunk = assert(require("luau").load(source, "vault-concurrency-reload", { entry = true })); setfenv(chunk, h.sandbox)
	check("a changed build waits for the native write instead of replacing its owner", chunk({ ui = false, reuse = true }) == handle
		and handle.alive and handle.pendingBuild == "concurrency-fixture-next-build")
	h.sched.advance(0.4); restore()
	check("write completion permits authentication and unload", result and result[1] and not handle.config.vaultStatus().busy
		and not handle.config.vaultStatus().ready)
	assert(run(h, function() return handle.config.unlockVault(PASSWORD) end))
	check("authentication retains the original encrypted key after rejected unload", handle.config.data.providers.list[1].apiKey == KEY
		and h.json.decode(h.files[FILE]).credentialVault ~= nil)
	check("unload succeeds once persistence is idle", handle.destroy() ~= false and not handle.alive)
	local cold = assert(h.boot("dist/uai.lua"))
	check("the next cold boot stays encrypted and locked", cold.config.vaultStatus().locked and cold.config.data.providers.list[1].apiKey == "")
	cold.destroy()
	check("the full lifecycle has no scheduler errors", #h.errors() == 0)
end)

suite.finish()
