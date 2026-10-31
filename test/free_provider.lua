-- Explicit library installation, separated access, migration and discovery.
-- All inference responses are synthetic; no private credential is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Project UAI Free")
local case, check = suite.case, suite.check
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end

-- The exact previous public bundle credential, encoded to avoid a raw copy.
local function previousCommunityCredential()
	local bytes = { 198, 227, 202, 59, 90, 97, 146, 170, 234, 24, 58, 50, 127, 137, 210, 197, 229, 59, 94, 138, 154, 190, 195, 20, 48, 40, 141, 113, 212, 184, 250, 64, 42, 100, 115, 217, 200, 15, 61, 72, 92, 135, 151, 224, 36, 60, 70, 79, 175, 221, 230 }
	local out = {}
	for index, value in ipairs(bytes) do out[index] = string.char((value - ((83 + (index - 1) * 37) % 256)) % 256) end
	return table.concat(out)
end

case("an empty setup stays empty until free access is explicitly installed", function()
	local f = F.new()
	-- 12:00 UTC is 20:00 at the fixed UTC+8 opening, independent of host time.
	f.env.require("runtime/clock").ms = function() return 1767268800000 + f.h.sched.now * 1000 end
	local registry = f.env.require("provider/registry")
	local free = f.env.require("provider/free")
	free.start()
	check("startup leaves provider selection to the user", registry.count() == 0 and registry.active() == nil)
	check("selection repair cannot install a provider", free.ensure() == nil and registry.count() == 0)
	assert(free.use())
	local record = registry.active()
	check("free provider is active", record and record.label == "Project UAI Free" and registry.count() == 1)
	check("included credential and supported router are ready", f.env.require("provider/community_key").isApplied(record)
		and record.model == "auto" and record.models[1] == "auto" and registry.validate(record))
	check("explicit installation sends no traffic", f.h.http.requestCount == 0)
	free.start(); free.use()
	check("restarting and choosing free access do not duplicate it", registry.count() == 1)
	f.h.http.handler = function(entry)
		local body = f.h.json.decode(entry.body)
		check("first inference uses official endpoint and auto", entry.url == "https://api.hcnsec.cn/v1/chat/completions" and body.model == "auto")
		check("included access authenticates", f.env.require("net/headers").get(entry.headers, "Authorization") == "Bearer " .. record.apiKey)
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "Ready" }, finish_reason = "stop" } } }) }
	end
	local reply = f.run(function()
		return f.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "Hello" } }, stream = false })
	end)
	check("first conversation completes without configuration", reply and reply.content == "Ready")
	free.stop(); f.healthy(); f.close()
end)

case("included access follows a fixed UTC+8 schedule from 20:00 to noon", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free"); local community = f.env.require("provider/community_key")
	local base, hour = 1767225600000, 3600000 -- 08:00 UTC+8 on 1 January.
	for _, sample in ipairs({ { 4 * hour - 1, true }, { 4 * hour, false }, { 8 * hour, false },
		{ 12 * hour - 1, false }, { 12 * hour, true }, { 16 * hour, true }, { 24 * hour - 1, true },
		{ 28 * hour, false }, { 36 * hour, true } }) do
		local status = community.availability(record, base + sample[1])
		check("opening, midday, midnight and closing boundaries honor UTC+8", status.applies and status.open == sample[2])
	end
	local closed = community.availability(record, base + 8 * hour)
	check("closed guidance names the fixed zone and next opening", has(closed.message, "20:00-12:00 UTC+8 (Beijing/Singapore)")
		and closed.nextOpenMs == base + 12 * hour and closed.nextCloseMs == base + 28 * hour)
	local waiting = community.countdown(record, base + 8 * hour)
	check("the countdown reports the wait until opening", waiting and not waiting.open and waiting.ms == 4 * hour
		and waiting.text == "Opens in 4h 00m")
	local open = community.countdown(record, base + 16 * hour)
	check("the countdown reports the time until closing", open and open.open and open.ms == 12 * hour
		and open.text == "Closes in 12h 00m")
	check("remaining time reads as seconds, minutes and hours",
		community.remaining(59000) == "59s" and community.remaining(61000) == "1m 01s"
		and community.remaining(3 * hour + 12 * 60000) == "3h 12m")
	record.apiKey = "personal-schedule-fixture"
	check("personal HCNSEC credentials have no community schedule", not community.availability(record, base).applies
		and community.problem(record, base) == nil and community.countdown(record, base) == nil)
	community.apply(record); record.headers.Authorization = "Bearer personal-header-fixture"
	check("a personal auth-header override has no community schedule", not community.availability(record, base).applies)
	check("schedule inspection is entirely offline", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("the retired included credential migrates without changing personal access", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local community = f.env.require("provider/community_key")
	local credential = f.env.require("runtime/community_credential")
	local previous = previousCommunityCredential()
	check("only the actual previous public credential is retired", credential.isRetired(previous)
		and not credential.isRetired(credential.key) and not credential.isRetired("personal-migration-fixture"))
	local record = registry.blank("projectuai-free")
	record.preset = "hcnsec"
	record.id, record.apiKey = "retired-community-fixture", previous
	record.headers = { Authorization = "Bearer " .. previous, ["x-api-key"] = previous, ["X-Route"] = "preserved" }
	record.keyIds = { "11111111-1111-4111-8111-111111111111" }
	record.keyNames, record.keyPaused, record.keyMode, record.selectedKey = { "Included label" }, { true }, "single", 1
	record.keyRotation = { fixture = true }
	f.env.require("runtime/config").set("providers.list", { record })
	check("normal registry migration replaces the retired included credential", registry.migrate() == 1
		and record.apiKey == credential.key and community.isApplied(record))
	check("matching auth copies migrate and unrelated headers survive", record.headers.Authorization == "Bearer " .. credential.key
		and record.headers["x-api-key"] == credential.key and record.headers["X-Route"] == "preserved")
	check("credential replacement resets accounting identity but preserves key preferences", record.keyIds == nil and record.keyRotation == nil
		and record.keyNames[1] == "Included label" and record.keyPaused[1] and record.keyMode == "single" and record.selectedKey == 1)
	check("community credential migration is idempotent", registry.migrate() == 0)
	for _, change in ipairs({ function(item) item.apiKey = "personal-migration-fixture" end,
		function(item) item.apiKey = previous .. "\npersonal-migration-fixture" end,
		function(item) item.baseUrl = "https://custom.fixture/v1" end,
		function(item) item.preset = "custom" end }) do
		local other = registry.blank("projectuai-free"); other.apiKey = previous; change(other)
		local expected = other.apiKey
		check("personal pools and unrelated endpoints are never migrated", not community.migrate(other) and other.apiKey == expected)
	end
	local overridden = registry.blank("hcnsec"); overridden.apiKey = previous
	overridden.headers = { Authorization = "Bearer personal-override-fixture", ["api-key"] = previous }
	check("migration preserves explicit personal auth overrides", community.migrate(overridden)
		and overridden.apiKey == credential.key and overridden.headers.Authorization == "Bearer personal-override-fixture"
		and overridden.headers["api-key"] == credential.key and not community.isApplied(overridden))
	check("community credential migration is offline", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("a saved community reference restores only its included key", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local community = f.env.require("provider/community_key")
	local record = registry.blank("projectuai-free")
	record.apiKey, record.communityCredential, record.authStyle = "", true, "x-api-key"
	record.headers = { ["x-api-key"] = "personal-restoration-fixture" }
	record.keyIds = { "11111111-1111-4111-8111-111111111111" }
	record.keyNames, record.keyPaused, record.keyMode, record.selectedKey = { "Saved label" }, { true }, "single", 1
	local headers, ids, names, pauses = record.headers, record.keyIds, record.keyNames, record.keyPaused
	check("included reference restores the current credential", community.restore(record)
		and record.apiKey == f.env.require("runtime/community_credential").key)
	check("restoration preserves explicit personal headers, auth and metadata", record.headers == headers
		and headers["x-api-key"] == "personal-restoration-fixture" and record.authStyle == "x-api-key"
		and record.keyIds == ids and record.keyNames == names and record.keyPaused == pauses
		and record.keyMode == "single" and record.selectedKey == 1 and not community.isApplied(record))
	check("restoration cannot overwrite an existing credential", not community.restore(record))
	record.apiKey, record.baseUrl = "", "https://custom.fixture/v1"
	check("a reference cannot supply the included key to another endpoint", not community.restore(record) and record.apiKey == "")
	check("reference restoration sends no requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("community references retain pause and accounting metadata across cold reload", function()
	for _, remember in ipairs({ false, true }) do
		local f = F.new(); local registry = f.env.require("provider/registry")
		local config, credentials = f.env.require("runtime/config"), f.env.require("runtime/credentials")
		local community, credential = f.env.require("provider/community_key"), f.env.require("runtime/community_credential")
		local record = registry.blank("projectuai-free")
		record.id = "paused-community-reference"
		record.keyIds = { "11111111-1111-4111-8111-111111111111" }
		record.keyNames, record.keyPaused, record.keyMode, record.selectedKey = { "Paused included label" }, { true }, "single", 1
		assert(registry.save(record)); assert(config.setRememberCredentials(remember)); assert(config.saveNow())
		local diskText = assert(f.h.files["UAI/config.json"])
		local stored = credentials.restore(f.h.json.decode(diskText)).providers.list[1]
		check("disk stores a versioned community reference with no raw credential", stored.apiKey == "" and stored.communityCredential
			and stored.communityKeyState.revision == credential.revision and not has(diskText, credential.key))
		check("reference retains private metadata in both storage modes", stored.communityKeyState.keyPaused[1]
			and stored.communityKeyState.keyNames[1] == "Paused included label"
			and stored.communityKeyState.keyIds[1] == record.keyIds[1])
		config.load()
		local restored = registry.get(record.id)
		check("cold reload keeps paused single-key access and its accounting identity", restored.apiKey == credential.key
			and restored.keyPaused[1] and restored.keyMode == "single" and restored.selectedKey == 1
			and restored.keyNames[1] == "Paused included label" and restored.keyIds[1] == record.keyIds[1]
			and restored.communityKeyState == nil and #registry.requestKeys(restored) == 0)
		local safe = credentials.sanitise({ providers = { list = { stored } } }).providers.list[1]
		check("default export removes nested private community metadata", safe.communityKeyState == nil and safe.keyNames == nil and safe.keyIds == nil)
		local private = credentials.restore(assert(credentials.privateCopy(config.data))).providers.list[1]
		check("private transfer preserves community pause and labels as a reference", private.apiKey == "" and private.communityKeyState.keyPaused[1]
			and private.communityKeyState.keyNames[1] == "Paused included label")
		stored.communityKeyState.revision = "previous-revision"
		stored.keyRotation = { fixture = true }
		check("a changed community revision preserves preferences but resets accounting", community.restore(stored)
			and stored.keyPaused[1] and stored.keyNames[1] == "Paused included label" and stored.keyMode == "single"
			and stored.keyIds == nil and stored.keyRotation == nil and stored.communityKeyState == nil)
		f.healthy(); f.close()
	end
end)

case("retired community references cannot retain old accounting IDs", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free")
	record.apiKey = previousCommunityCredential()
	record.keyIds = { "11111111-1111-4111-8111-111111111111" }
	record.keyNames, record.keyPaused = { "Preserved label" }, { true }
	local referenced = f.env.require("runtime/credentials").referenceCommunity({ providers = { list = { record } } }).providers.list[1]
	check("retired raw credentials become current references without old IDs", referenced.apiKey == "" and referenced.communityKeyState.keyIds == nil
		and referenced.communityKeyState.keyPaused[1] and referenced.communityKeyState.keyNames[1] == "Preserved label")
	check("a malformed reference cannot silently resume included access", not f.env.require("provider/community_key").restore({
		preset = "projectuai-free", baseUrl = "https://api.hcnsec.cn/v1", apiKey = "", communityCredential = true,
		communityKeyState = { revision = "2026-10-29", keyPaused = { "invalid" } } }))
	f.healthy(); f.close()
end)

case("closed included access can be saved but cannot start inference or discovery", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	-- 16:00 UTC+8: after the midday close and before the evening opening.
	f.env.require("runtime/clock").ms = function() return 1767225600000 + 8 * 3600000 + f.h.sched.now * 1000 end
	local record = registry.blank("projectuai-free")
	check("closed included access remains a valid saved provider", registry.validate(record) and registry.save(record))
	local reply, why = f.run(function()
		return f.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "Hello" } }, stream = false })
	end)
	check("closed inference explains its next opening", reply == nil and has(why, "20:00-12:00 UTC+8") and has(why, "choose another provider"))
	local found, note = f.run(function() return f.env.require("provider/models").discover(record) end)
	check("closed discovery explains its schedule", #found == 0 and has(note, "20:00-12:00 UTC+8"))
	check("closed admissions send no network requests", f.h.http.requestCount == 0)
	record.apiKey = "personal-schedule-fixture"
	record.preset = "hcnsec"
	check("personal HCNSEC requests remain eligible during daytime", registry.protocolProblem(record) == nil)
	f.healthy(); f.close()
end)

case("an admitted free inference can settle after closing", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	f.env.require("runtime/clock").ms = function() return 1767326400000 - 1000 + f.h.sched.now * 1000 end
	local record = registry.blank("projectuai-free"); registry.save(record)
	f.h.http.handler = function()
		f.h.sched.wait(2)
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "Finished" }, finish_reason = "stop" } } }) }
	end
	local reply = f.run(function()
		return f.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "Hello" } }, stream = false })
	end, 3)
	check("closing does not cancel an accepted response", reply and reply.content == "Finished" and f.h.http.requestCount == 1)
	check("the next inference is outside the schedule", has(registry.protocolProblem(record), "20:00-12:00 UTC+8"))
	f.healthy(); f.close()
end)

case("saved providers and deliberately disabled selections are preserved", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("hcnsec")
	record.label, record.apiKey, record.model, record.enabled = "My account", "personal-fixture-key", "chosen-model", false
	assert(registry.save(record))
	f.env.require("provider/free").start()
	check("existing selection is not replaced", registry.count() == 1 and registry.active() == record)
	check("personal settings stay intact", record.apiKey == "personal-fixture-key" and record.model == "chosen-model" and record.enabled == false)
	check("personal account models are not mislabeled free", not f.env.require("provider/models").isFree(record, "chosen-model"))
	f.env.require("provider/free").stop(); f.healthy(); f.close()
end)

case("missing selection adopts an existing enabled provider", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("ollama"); record.model = "existing-model"; assert(registry.save(record))
	f.env.require("runtime/config").set("providers.active", "missing-id")
	f.env.require("provider/free").start()
	check("existing provider gets the selection", registry.count() == 1 and f.env.require("runtime/config").get("providers.active") == record.id)
	f.env.require("provider/free").stop(); f.healthy(); f.close()
end)

case("removal, imports, reset and future startup never reinstall community access", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local config, free = f.env.require("runtime/config"), f.env.require("provider/free")
	free.start(); assert(free.use()); registry.remove(registry.active().id)
	check("explicit removal stays removed in this session", registry.count() == 0)
	free.stop(); free.start()
	check("next start keeps an otherwise empty setup", registry.count() == 0 and registry.active() == nil)
	config.replace({ providers = { active = "", list = {} } })
	check("an empty import stays empty", registry.count() == 0 and registry.active() == nil)
	config.reset("providers")
	check("provider reset stays empty", registry.count() == 0)
	free.stop(); config.reset("providers")
	check("stopped bootstrap releases its listener", registry.count() == 0)
	free.start(); assert(free.use()); registry.remove(registry.active().id)
	f.env.require("runtime/dispose").drain(); config.reset("providers")
	check("client unload releases the free provider listener", registry.count() == 0)
	f.healthy(); f.close()
end)

case("retired OpenCode endpoints migrate on list and normalize pasted variants", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local config = f.env.require("runtime/config")
	local variants = {
		"https://puai-proxy.davidzk.tech/opencode/v1",
		"puai-proxy.davidzk.tech/opencode",
		"https://PUAI-PROXY.DAVIDZK.TECH:443/opencode/v1/chat/completions?old=route",
		"https://puai-free-gateway.renern.workers.dev/opencode/v1/models",
		"http://puai-proxy.davidzk.tech/opencode/v1/",
	}
	local records = {}
	for index, base in ipairs(variants) do
		check("pasted route normalizes " .. index, registry.normaliseBaseUrl(base) == "https://opencode.ai/zen/v1")
		records[index] = { id = "retired-" .. index, baseUrl = base, apiKey = "preserved-key", model = "saved-model", wsUrl = "wss://old-gateway.fixture" }
	end
	local custom = { id = "custom", baseUrl = "https://custom.fixture/opencode/v1", apiKey = "custom-key" }
	records[#records + 1] = custom
	config.set("providers.list", records)
	registry.list()
	for index = 1, #variants do
		local record = records[index]
		check("saved route migrates without credentials/model loss " .. index,
			record.baseUrl == "https://opencode.ai/zen/v1" and record.apiKey == "preserved-key" and record.model == "saved-model" and record.wsUrl == "")
		check("retired route never becomes a proxy candidate " .. index, not registry.proxyProvider(record) and not registry.proxyTarget(record))
	end
	check("custom route stays intact", custom.baseUrl == "https://custom.fixture/opencode/v1")
	check("migration is idempotent", registry.migrate() == 0)
	for _, base in ipairs({ "https://puai-proxy.davidzk.tech.evil.test/opencode/v1", "https://puai-proxy.davidzk.tech:8443/opencode/v1", "https://puai-proxy.davidzk.tech/opencode-other/v1" }) do
		check("unrelated endpoint stays intact", registry.normaliseBaseUrl(base) == base)
	end
	local worker = { baseUrl = "https://puai-free-gateway.renern.workers.dev/agentrouter/v1" }
	check("Workers.dev is not a supported proxy or recovery target", registry.proxyProvider(worker) == nil and registry.proxyTarget(worker) == nil)
	check("only the proper proxy domain inherits AgentRouter identity", registry.proxyProvider({ baseUrl = "https://puai-proxy.davidzk.tech/agentrouter/v1" }) == "agentrouter")
	f.healthy(); f.close()
end)

case("OpenCode discovery uses the connected CLI and expires when connection changes", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local connection = { enabled = true, source = "desktop", port = 28791, token = "fixture-one", instance = "fixture-instance" }
	local available, calls, delayed = true, 0, false
	f.loaded["net/bridge_connection"] = { get = function() return connection end }
	f.loaded["net/bridge"] = {
		opencodeStatus = function() return { available = available, state = available and "ready" or "disconnected" } end,
		opencodeModels = function()
			calls = calls + 1
			if delayed then f.h.sched.wait(2) end
			return { data = { { id = "cat-jam-free" }, { id = "big-pickle" }, { id = "cat-jam-free" } } }
		end,
	}
	local models = f.env.require("provider/models"); local record = registry.blank("zen")
	local found, note = models.discover(record)
	check("current native models are deduplicated and sorted", #found == 2 and found[1] == "big-pickle" and found[2] == "cat-jam-free")
	check("source is disclosed with no direct API request", has(note, "OpenCode CLI") and f.h.http.requestCount == 0)
	models.discover(record)
	check("current connection can use its cache", calls == 1)
	connection.token = "fixture-two"
	check("connection changes invalidate model cache", models.cached(record) == nil)
	delayed = true
	local late
	f.h.sched.spawn(function() late = { models.discover(record) } end)
	f.h.sched.advance(0.1); connection.token = "fixture-three"; f.h.sched.advance(3)
	check("late old connection results cannot publish", late and #late[1] == 0 and has(late[2], "connection changed") and models.cached(record) == nil)
	check("superseded discovery includes support", has(late[2], "https://discord.gg/9xYyyYuKap"))
	available = false
	f.h.http.handler = function() return { StatusCode = 403, Body = '{"error":{"type":"FreeTierError","message":"OpenCode free tier can only be used from within OpenCode"}}' } end
	local rejected, why = f.run(function() return models.discover(record) end)
	check("unavailable mobile route reports the relay requirement", #rejected == 0 and has(why, "UAI Relay app") and has(why, "https://discord.gg/9xYyyYuKap"))
	check("failure never targets the retired proxy", f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

case("only verified native free models waive personal key entry", function()
	local f = F.ui(900, 800); local registry = f.env.require("provider/registry")
	local available, state, cowork = true, "ready", true
	f.loaded["net/bridge"] = {
		opencodeStatus = function() return { available = available, state = state } end,
		opencodeHasModel = function(id) return id == "cat-jam-free" or id == "big-pickle" or id == "paid-model" end,
	}
	f.loaded["net/transport"] = { coworkWeb = function() return cowork end }
	local record = registry.blank("zen"); record.model = "cat-jam-free"
	check("a discovered native free model needs no personal key", registry.validate(record))
	record.model = "big-pickle"
	check("the verified unsuffixed free model is supported", registry.validate(record))
	for _, model in ipairs({ "paid-model", "unknown-free" }) do
		record.model = model
		check("unverified or paid model keeps normal auth", not registry.validate(record))
	end
	record.model = "cat-jam-free"
	for _, base in ipairs({ "https://custom.fixture/zen/v1", "http://opencode.ai/zen/v1", "https://opencode.ai:8443/zen/v1", "https://opencode.ai/custom/v1" }) do
		record.baseUrl = base
		check("unrelated routes keep normal auth", not registry.validate(record))
	end
	record.baseUrl = "https://opencode.ai/zen/v1"
	record.api = "anthropic"
	check("the Messages adapter keeps normal auth", not registry.validate(record))
	record.api = "openai"; available = false
	check("a disconnected backend keeps normal auth", not registry.validate(record))
	available = true; state = "starting"
	check("a backend still starting keeps normal auth", not registry.validate(record))
	state = "ready"; cowork = false
	check("direct desktop keeps normal auth", not registry.validate(record))
	cowork = true
	f.env.require("ui/panels/providers").editor(record, function(id) f.saved = registry.get(id) end)
	check("the editor explains native authentication", f.h.byName("KeyState").Text == "Provided by connected OpenCode CLI")
	f.h.click(assert(f.h.byName("SaveProvider")))
	check("the verified CLI model saves without a personal key", f.saved and f.saved.apiKey == "" and f.saved.model == "cat-jam-free")
	check("validation never makes network requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("free library setup is available without personal key entry", function()
	local f = F.ui(390, 760); local registry = f.env.require("provider/registry")
	f.env.require("ui/panels/providers").editor(registry.blank("projectuai-free"), function(id) f.saved = registry.get(id) end)
	check("free setup explains included access", has(f.h.textOf(), "No account, payment or personal API key") and has(f.h.textOf(), "https://discord.gg/9xYyyYuKap"))
	f.h.click(assert(f.h.byName("SaveProvider")))
	check("Save needs no key or model edits", f.saved and f.saved.model == "auto" and registry.validate(f.saved))
	check("the installed access type has its own preset", f.saved.preset == "projectuai-free")
	check("all managed-provider models qualify for free filtering", f.env.require("provider/models").isFree(f.saved, "auto"))
	check("setup and introduction send no inference", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

suite.finish()
