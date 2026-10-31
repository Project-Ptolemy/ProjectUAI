-- Pause policy and opaque key ownership through synthetic provider traffic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider key pause")
local case, check = suite.case, suite.check

local function fixture(protocol)
	local f = F.new()
	f.registry, f.keys = f.env.require("provider/registry"), f.env.require("runtime/provider_keys")
	f.record = f.registry.blank("custom")
	f.record.id, f.record.label, f.record.model = "pause-fixture", "Pause fixture", "fixture-model"
	f.record.models, f.record.apiKey = { "fixture-model" }, "key-one\nkey-two\nkey-three"
	f.record.baseUrl, f.record.api = "https://keys.fixture/v1", protocol == "anthropic" and "anthropic" or protocol == "gemini" and "gemini" or "openai"
	if protocol == "gemini" then f.record.authStyle = "x-goog-api-key" end
	if protocol == "responses" then f.record.baseUrl, f.record.repairs = "https://opencode.ai/zen/v1", { "responses_protocol" } end
	f.seen = {}
	function f.observe(entry)
		local get = f.env.require("net/headers").get
		local key = get(entry.headers, "Authorization") or get(entry.headers, "x-api-key") or get(entry.headers, "x-goog-api-key") or ""
		f.seen[#f.seen + 1] = key:gsub("^Bearer ", "")
	end
	function f.reply()
		local body
		if protocol == "anthropic" then body = { type = "message", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn" }
		elseif protocol == "gemini" then body = { candidates = { { content = { role = "model", parts = { { text = "ready" } } }, finishReason = "STOP" } } }
		elseif protocol == "responses" then body = { status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }
		else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } } end
		return { StatusCode = 200, Body = f.h.json.encode(body) }
	end
	function f.complete(record)
		return f.run(function() return f.env.require("provider/chat").complete(record or f.record, {
			messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1 }) end)
	end
	return f
end

case("pause metadata follows credentials through rename, replace, append and removal", function()
	local f = fixture("openai")
	check("legacy keys are active without rewriting their configuration", not f.keys.paused(f.record, 2) and f.record.keyPaused == nil)
	assert(f.keys.setPaused(f.record, 2, true))
	local id = f.keys.keyId(f.record, 2)
	assert(f.keys.rename(f.record, 2, "Work"))
	check("pause and rename retain the same credential identity", f.keys.keyId(f.record, 2) == id and f.keys.entries(f.record)[2].paused)
	assert(f.keys.replace(f.record, 2, "replacement"))
	check("replacement stays paused but owns new usage history", f.keys.paused(f.record, 2) and f.keys.keyId(f.record, 2) ~= id
		and f.keys.entries(f.record)[2].name == "Work")
	id = f.keys.keyId(f.record, 2)
	assert(f.keys.remove(f.record, 1)); assert(f.keys.add(f.record, "fourth\nfifth"))
	check("shifting keys preserves pause and identity while added keys start active", f.keys.paused(f.record, 1)
		and f.keys.keyId(f.record, 1) == id and not f.keys.paused(f.record, 3) and not f.keys.paused(f.record, 4)
		and table.concat(f.keys.requestKeys(f.record), ",") == "key-three,fourth,fifth" and f.keys.validate(f.record))
	f.healthy(); f.close()
end)

case("saved keys acquire opaque stable IDs before snapshots and preserve them on reload", function()
	local f = fixture("openai")
	local config = f.env.require("runtime/config")
	config.set("providers.list", { f.record }); config.saveNow()
	local live = assert(f.registry.get(f.record.id))
	local snapshot = f.registry.requestSnapshot(live)
	check("reading a legacy provider seeds each key and schedules persistence", config.dirty and #live.keyIds == 3
		and snapshot.keyIds[2] == live.keyIds[2] and snapshot.keyIds ~= live.keyIds)
	local ids = f.env.require("runtime/util").deepCopy(live.keyIds)
	check("new identifiers contain no credential material", #ids[1] == 36 and ids[1] ~= ids[2] and not ids[1]:find("key-one", 1, true))
	config.saveNow(); config.load()
	local restored = assert(f.registry.get(f.record.id))
	check("a config reload retains the same accounting identities", restored.keyIds[1] == ids[1] and restored.keyIds[3] == ids[3]
		and not f.keys.ensureIds(restored))
	local cursor = restored.keyRotation
	assert(f.keys.rename(restored, 1, "Personal"))
	check("naming a key does not replace IDs or the current cursor", restored.keyIds[1] == ids[1] and restored.keyRotation == cursor)
	f.healthy(); f.close()
end)

case("a paused selected key remains selected and is a valid saved setup", function()
	local f = fixture("openai")
	assert(f.keys.setMode(f.record, "single", 2)); assert(f.keys.setPaused(f.record, 2, true))
	check("pausing never switches to another credential", f.keys.mode(f.record) == "single" and f.keys.selected(f.record) == 2
		and f.registry.nextKey(f.record) == nil and f.registry.save(f.record))
	local result, why = f.complete()
	check("a paused selection stops before network work with a clear reason", result == nil and tostring(why):find("paused", 1, true)
		and f.h.http.requestCount == 0)
	check("explicitly choosing a paused key is rejected", not f.keys.setMode(f.record, "single", 2))
	assert(f.keys.setPaused(f.record, 2, false))
	f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
	result = f.complete()
	check("resuming restores the original selected credential", result and f.seen[1] == "key-two" and f.keys.selected(f.record) == 2)
	f.healthy(); f.close()
end)

for _, protocol in ipairs({ "openai", "anthropic", "responses", "gemini" }) do
	case(protocol .. " excludes paused keys from rotation and quota retries", function()
		local f = fixture(protocol)
		assert(f.keys.setPaused(f.record, 2, true))
		f.h.http.handler = function(entry)
			f.observe(entry)
			if #f.seen == 1 then return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded","status":"RESOURCE_EXHAUSTED"}}' } end
			return f.reply()
		end
		local result = f.complete()
		check("quota recovery uses the next active key", result and result.content == "ready" and table.concat(f.seen, ",") == "key-one,key-three")
		assert(f.keys.setPaused(f.record, 1, true)); assert(f.keys.setPaused(f.record, 3, true))
		check("all-paused provider settings can still be saved", f.registry.save(f.record))
		result = f.complete()
		check("an all-paused pool cannot dispatch anonymously", result == nil and #f.seen == 2)
		assert(f.keys.setPaused(f.record, 2, false))
		result = f.complete()
		check("resuming one key makes only that key available", result and f.seen[3] == "key-two")
		f.healthy(); f.close()
	end)
end

case("discovery obeys pause changes and an older cache cannot bypass them", function()
	local f = fixture("openai")
	local models = f.env.require("provider/models")
	f.h.http.handler = function(entry)
		f.observe(entry)
		return { StatusCode = 200, Body = '{"data":[{"id":"fixture-model"}]}' }
	end
	local found = f.run(function() return models.discover(f.record) end)
	check("initial discovery caches the catalog", found[1] == "fixture-model" and models.cached(f.record) ~= nil)
	assert(f.keys.setPaused(f.record, 1, true)); assert(f.keys.setPaused(f.record, 2, true))
	check("pause changes supersede a discovery scope", models.cached(f.record) == nil)
	found = f.run(function() return models.discover(f.record) end)
	check("uncached discovery selects an active key", found[1] == "fixture-model" and f.seen[2] == "key-three")
	assert(f.keys.setPaused(f.record, 3, true))
	local note
	found, note = f.run(function() return models.discover(f.record) end)
	check("all-paused discovery blocks before network or cache reuse", #found == 0 and tostring(note):find("paused", 1, true) and #f.seen == 2)
	f.healthy(); f.close()
end)

case("accepted snapshots retain their pause policy while future snapshots use the edit", function()
	local f = fixture("openai")
	local accepted = f.registry.requestSnapshot(f.record)
	assert(f.keys.setPaused(f.record, 1, true)); assert(f.keys.setPaused(f.record, 2, true))
	local future = f.registry.requestSnapshot(f.record)
	f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
	local first, second = f.complete(accepted), f.complete(future)
	check("older accepted work retains its selected pool", first and second and table.concat(f.seen, ",") == "key-one,key-three")
	check("pause edits do not replace accounting identities", accepted.keyIds[1] == future.keyIds[1] and accepted.keyIds[3] == future.keyIds[3])
	f.healthy(); f.close()
end)

case("a pause edit revokes proxy recovery belonging to an older policy", function()
	local f = fixture("anthropic")
	f.record.baseUrl = "https://agentrouter.org/v1"
	local recovery = f.env.require("provider/proxy").new(f.record)
	assert(f.keys.setPaused(f.record, 2, true))
	check("late recovery cannot adopt an old operation's endpoint", not recovery.recover({ status = 403,
		body = '{"error":{"message":"Unauthorized client"}}' }) and f.record.baseUrl == "https://agentrouter.org/v1")
	f.healthy(); f.close()
end)

case("paused included access cannot start anonymous background model probes", function()
	local f = fixture("openai")
	f.env.require("runtime/clock").ms = function() return 1767268800000 + f.h.sched.now * 1000 end -- Test pause during open hours.
	local record = f.registry.blank("projectuai-free")
	record.id, record.label, record.model = "included-pause", "Included pause", "auto"
	assert(f.registry.save(record)); assert(f.keys.setPaused(record, 1, true))
	local route = f.env.require("provider/free_route")
	check("paused access is not advertised as available", not route.status(record).available)
	check("paused included access is not eligible for background measurements", not route.eligible(record))
	route.refresh(record); f.h.sched.advance(1)
	check("background refresh dispatches neither discovery nor anonymous inference", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("invalid metadata is rejected without leaking keys and included access resets it", function()
	local f = fixture("openai")
	for _, flags in ipairs({ true, { true }, { true, false, "false" }, { [1] = true, [3] = false } }) do
		f.record.keyPaused = flags
		local valid, why = f.keys.validate(f.record)
		check("pause metadata requires one boolean per key", not valid and not tostring(why):find("key-one", 1, true))
	end
	f.record.keyPaused = nil; f.keys.ensureIds(f.record)
	f.record.keyIds[2] = f.record.keyIds[1]
	check("duplicate usage identities are invalid", not f.keys.validate(f.record))
	f.record = f.registry.blank("projectuai-free")
	f.record.apiKey = "key-one\nkey-two"; f.record.keyIds = nil
	assert(f.keys.setPaused(f.record, 1, true))
	assert(f.env.require("provider/community_key").apply(f.record))
	check("included access clears prior pause and accounting metadata", f.record.keyPaused == nil and f.record.keyIds == nil and f.keys.validate(f.record))
	f.healthy(); f.close()
end)

suite.finish()
