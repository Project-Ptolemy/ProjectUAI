-- Observe actual synthetic request headers; no real credentials or network.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local Z = require("opencode_catalog_fixture")
local suite = F.suite("Provider key rotation")
local check, case = suite.check, suite.case
local function fixture(protocol, proxy)
	local f = F.new()
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank(proxy and "agentrouter" or "custom")
	f.record.id, f.record.label, f.record.model = "key-fixture", "Key fixture", "fixture-model"
	f.record.models, f.record.apiKey = { "fixture-model" }, "key-one\nkey-two, key-three\nkey-one"
	f.record.api = protocol == "gemini" and "gemini" or protocol == "anthropic" and "anthropic" or "openai"
	if protocol == "gemini" then f.record.authStyle = "x-goog-api-key" end
	if not proxy then f.record.baseUrl = "https://keys.fixture/v1" end
	if protocol == "responses" then
		f.record.baseUrl = "https://opencode.ai/zen/v1"
		f.record.repairs = { "responses_protocol" }
	end
	f.seen = {}
	function f.reply()
		local body
		if protocol == "anthropic" then body = { type = "message", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn" }
		elseif protocol == "responses" then body = { status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }
		elseif protocol == "gemini" then body = { candidates = { { content = { role = "model", parts = { { text = "ready" } } }, finishReason = "STOP" } } }
		else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } } end
		return { StatusCode = 200, Body = f.h.json.encode(body) }
	end
	function f.observe(entry)
		local get = f.env.require("net/headers").get
		local auth = get(entry.headers, "x-goog-api-key") or get(entry.headers, "x-api-key") or get(entry.headers, "Authorization") or ""
		f.seen[#f.seen + 1] = auth:gsub("^Bearer ", "")
	end
	function f.complete()
		if protocol == "responses" then Z.responses(f, f.record) end
		local result, why = f.run(function()
			return f.env.require("provider/chat").complete(f.record, {
				messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1,
			})
		end)
		check("completion succeeds: " .. tostring(why), result and result.content == "ready")
	end
	return f
end

for _, protocol in ipairs({ "openai", "anthropic", "responses", "gemini" }) do
	case(protocol .. " rotates successful requests and wraps the pool", function()
		local f = fixture(protocol)
		f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
		for _ = 1, 4 do f.complete() end
		check("every ready credential is used in order", table.concat(f.seen, ",") == "key-one,key-two,key-three,key-one")
		f.healthy(); f.close()
	end)
end

for _, protocol in ipairs({ "openai", "anthropic", "responses", "gemini" }) do
	case(protocol .. " uses only the selected key for successes and quota refusals", function()
		local f = fixture(protocol)
		assert(f.env.require("runtime/provider_keys").setMode(f.record, "single", 2))
		f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
		f.complete(); f.complete()
		check("successful requests keep the selected credential", table.concat(f.seen, ",") == "key-two,key-two")
		f.h.http.handler = function(entry)
			f.observe(entry)
			return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded","status":"RESOURCE_EXHAUSTED"}}' }
		end
		local result = f.run(function()
			return f.env.require("provider/chat").complete(f.record, {
				messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1,
			})
		end)
		check("quota refusal never consumes another key or another pool attempt", result == nil
			and table.concat(f.seen, ",") == "key-two,key-two,key-two" and f.record.keyRotation == nil)
		f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
		f.complete()
		check("the next independent request still uses the selected key", f.seen[4] == "key-two")
		f.healthy(); f.close()
	end)
end

for _, protocol in ipairs({ "openai", "anthropic" }) do
	case(protocol .. " quota recovery selects the next key exactly once", function()
		local f = fixture(protocol)
		f.h.http.handler = function(entry)
			f.observe(entry)
			if entry.index == 1 then return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded"}}' } end
			return f.reply()
		end
		f.complete(); f.complete()
		check("quota retry does not skip the second key", table.concat(f.seen, ",") == "key-one,key-two,key-three")
		check("only the refused key is cooling", f.registry.keyCooldowns(f.record)["key-one"] > f.env.require("runtime/clock").ms()
			and f.registry.keyCooldowns(f.record)["key-two"] == nil)
		f.healthy(); f.close()
	end)
	case(protocol .. " proxy recovery preserves its key and the next request advances", function()
		local f = fixture(protocol, true)
		f.h.http.handler = function(entry)
			f.observe(entry)
			if entry.index == 1 then return { StatusCode = 403, Body = '{"error":{"message":"Unauthorized client"}}' } end
			check("retry uses the authorized proxy route", entry.url:find("https://puai-proxy.davidzk.tech/agentrouter/v1/", 1, true) == 1)
			return f.reply()
		end
		f.complete(); f.complete()
		check("proxy retry neither switches nor skips credentials", table.concat(f.seen, ",") == "key-one,key-one,key-two")
		f.healthy(); f.close()
	end)
end

case("cooling keys are skipped until ready and single-key records stay stable", function()
	local f = fixture("openai")
	f.registry.cooldownKey(f.record, "key-two", 30)
	f.h.http.handler = function(entry) f.observe(entry); return f.reply() end
	f.complete(); f.complete(); f.complete()
	check("round-robin skips the cooling key", table.concat(f.seen, ",") == "key-one,key-three,key-one")
	f.h.sched.advance(31); f.complete()
	check("expired cooldown rejoins at the next slot", f.seen[4] == "key-two")
	f.record.apiKey, f.record.keyRotation = "only-key", nil
	f.complete(); f.complete()
	check("single-key behavior is unchanged", f.seen[5] == "only-key" and f.seen[6] == "only-key" and f.record.keyRotation == nil)
	f.healthy(); f.close()
end)

suite.finish()
