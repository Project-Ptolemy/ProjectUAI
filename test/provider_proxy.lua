-- Synthetic unauthorized-client recovery. No live endpoint or credential is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider proxy")
local case, check = suite.case, suite.check
local function has(value, part) return tostring(value):find(part, 1, true) ~= nil end
local PROXY = "https://puai-proxy.davidzk.tech/"
local function fixture(preset, protocol)
	local f = F.new()
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank(preset or "zen")
	f.record.id, f.record.label = "proxy-fixture", "Proxy fixture"
	f.record.model, f.record.models = "fixture-model", { "fixture-model" }
	f.record.apiKey = "fixture-key"
	if protocol then f.record.api = protocol end
	function f.refusal(status, message)
		return { StatusCode = status or 403, Body = f.h.json.encode({ error = { code = "unauthorized_client", message = message or "Unauthorized client" } }) }
	end
	function f.reply()
		if f.record.api == "anthropic" then
			return { StatusCode = 200, Body = f.h.json.encode({ type = "message", content = { { type = "text", text = "recovered" } }, stop_reason = "end_turn" }) }
		end
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "recovered" }, finish_reason = "stop" } } }) }
	end
	function f.complete(options, seconds)
		options = options or {}
		options.messages = options.messages or { { role = "user", content = "hello" } }
		if options.stream == nil then options.stream = false end
		options.attempts = options.attempts or 1
		return f.run(function() return f.env.require("provider/chat").complete(f.record, options) end, seconds)
	end
	return f
end

for _, preset in ipairs({ "zen", "agentrouter" }) do
	for _, protocol in ipairs({ "openai", "anthropic" }) do
		case(preset .. " " .. protocol .. " switches once and persists the provider", function()
			local f = fixture(preset, protocol); local record = f.record
			local vendor = preset == "zen" and "opencode" or "agentrouter"
			record.baseUrl = f.registry.normaliseBaseUrl(record.baseUrl) .. "?tenant=one"
			record.query = { region = "test" }; record.headers["X-Fixture"] = "preserved"
			f.registry.save(record)
			f.env.require("runtime/config").set("identity.claudeUa", false)
			local retries = 0
			f.h.http.handler = function(entry)
				if entry.index == 1 then return f.refusal() end
				local suffix = protocol == "anthropic" and "/messages" or "/chat/completions"
				check("correct proxy and protocol", entry.url == PROXY .. vendor .. "/v1" .. suffix .. "?tenant=one&region=test")
				local get = f.env.require("net/headers").get
				local auth = get(entry.headers, preset == "zen" and "Authorization" or "x-api-key")
				check("same credential and custom header", auth == (preset == "zen" and "Bearer fixture-key" or "fixture-key") and get(entry.headers, "X-Fixture") == "preserved")
				check("same model", f.h.json.decode(entry.body).model == "fixture-model")
				if preset == "zen" then
					check("OpenCode identity retained", has(get(entry.headers, "User-Agent"), "opencode/") and get(entry.headers, "x-opencode-session") ~= nil)
					check("Claude identity stays absent", get(entry.headers, "x-app") == nil)
				else
					check("required Claude identity survives the proxy", get(entry.headers, "x-app") == "cli" and has(get(entry.headers, "User-Agent"), "claude-cli/"))
				end
				return f.reply()
			end
			local result, why = f.complete({ onRetry = function(info) retries = retries + 1; check("visible proxy recovery", info.proxy and has(info.reason, "Project UAI proxy")) end })
			check("completion recovered: " .. tostring(why), result and result.content == "recovered" and f.h.http.requestCount == 2 and retries == 1)
			check("saved record changed", f.registry.get(record.id).baseUrl == PROXY .. vendor .. "/v1?tenant=one")
			check("no key rotation or failed health for the recovered refusal", record.keyRotation == nil and record.health.fail == 0)
			f.env.require("runtime/config").saveNow()
			f.env.require("runtime/config").load()
			check("URL survives config reload", f.registry.get(record.id).baseUrl == PROXY .. vendor .. "/v1?tenant=one")
			f.healthy(); f.close()
		end)
	end
end

case("only explicit client refusals qualify", function()
	local f = fixture(); local proxy = f.env.require("provider/proxy")
	for _, value in ipairs({ "Unauthorized client", "unauthorized_client", "UnauthorizedClientError", "Unauthorised client", "Client is not authorized" }) do
		check(value, proxy.isClientRefusal({ status = 403, body = f.h.json.encode({ error = { message = value } }) }))
	end
	check("short plain text", proxy.isClientRefusal({ status = 401, body = "Unauthorized client" }))
	check("structured 200 error", proxy.isClientRefusal({ status = 200, body = f.h.json.encode({ error = "Unauthorized client" }) }))
	for _, response in ipairs({
		{ status = 401, body = "Unauthorized" },
		{ status = 401, body = '{"error":{"code":"invalid_api_key","message":"API key rejected"}}' },
		{ status = 401, body = '{"error":{"code":"invalid_api_key","message":"Unauthorized client"}}' },
		{ status = 401, body = 'Unauthorized client: invalid API key' },
		{ status = 403, body = '{"error":{"message":"insufficient permissions"}}' },
		{ status = 403, body = '{"error":{"type":"FreeTierError","message":"OpenCode free tier can only be used from within OpenCode"}}' },
		{ status = 403, body = "<html>Unauthorized client</html>" },
		{ status = 429, body = '{"error":"Unauthorized client"}' },
		{ status = 500, body = '{"error":"Unauthorized client"}' },
		{ status = 200, body = '{"choices":[{"message":{"content":"Unauthorized client"}}]}' },
		{ status = 200, body = "Unauthorized client" },
		{ status = 200, body = 'data: {"error":"Unauthorized client"}\n\n' },
		{ status = 403, body = string.rep(" ", 65536) .. "Unauthorized client" },
	}) do check("refusal cannot be inferred from status or arbitrary content", not proxy.isClientRefusal(response)) end
	f.healthy(); f.close()
end)

case("fallback eligibility follows exact official hosts and routes", function()
	local f = fixture(); local registry = f.registry
	local accepted = {
		{ "https://opencode.ai/zen/v1/chat/completions", "opencode" },
		{ "HTTPS://OPENCODE.AI.:443/zen/v1/", "opencode" },
		{ "https://agentrouter.org", "agentrouter" },
		{ "https://api.agentrouter.org/v1/messages", "agentrouter" },
	}
	for _, item in ipairs(accepted) do check(item[1], registry.proxyTarget({ baseUrl = item[1] }) == PROXY .. item[2] .. "/v1") end
	for _, url in ipairs({ "https://opencode.ai.evil.test/zen/v1", "https://evil.test/opencode.ai/zen/v1",
		"https://opencode.ai@evil.test/zen/v1", "https://opencode.ai:8443/zen/v1", "https://opencode.ai/custom/v1",
		"https://opencode.ai/zen/v1/models/messages",
		"https://agentrouter.org.evil.test/v1", "https://agentrouter.org/custom/v1", "https://custom.test/v1",
		PROXY .. "opencode/v1", PROXY .. "agentrouter/v1" }) do
		check("preserves custom or already proxied URL", registry.proxyTarget({ baseUrl = url, preset = "zen" }) == nil)
	end
	for _, url in ipairs({ "https://puai-proxy.davidzk.tech.evil.test/opencode/v1", PROXY .. "opencode/v1/other",
		PROXY .. "custom/v1?provider=opencode", "http://puai-proxy.davidzk.tech/opencode/v1",
		"https://puai-proxy.davidzk.tech:8443/agentrouter/v1" }) do check("proxy identity is scoped", registry.proxyProvider({ baseUrl = url }) == nil) end
	f.healthy(); f.close()
end)

for _, preset in ipairs({ "zen", "agentrouter" }) do
	case(preset .. " proxy rejection cannot cause a loop", function()
		local f = fixture(preset); f.h.http.handler = function() return f.refusal() end
		local result, why = f.complete()
		check("at most two requests and actual error remains visible", not result and has(why, "Unauthorized client") and f.h.http.requestCount == 2)
		check("proxy stays selected", has(f.record.baseUrl, PROXY))
		result = f.complete()
		check("next request starts on proxy without another migration", not result and f.h.http.requestCount == 3)
		f.healthy(); f.close()
	end)
end

case("invalid keys and custom endpoints never send credentials to the proxy", function()
	for _, mode in ipairs({ "invalid-key", "custom", "free-tier" }) do
		local f = fixture()
		if mode == "custom" then f.record.baseUrl = "https://custom.test/v1" end
		local original = f.record.baseUrl
		f.h.http.handler = function()
			if mode == "custom" then return f.refusal() end
			return { StatusCode = 401, Body = f.h.json.encode({ error = { message = mode == "invalid-key" and "Invalid API key" or "OpenCode free tier can only be used from within OpenCode" } }) }
		end
		check("request fails without redirect", not f.complete() and f.h.http.requestCount == 1 and f.record.baseUrl == original)
		f.healthy(); f.close()
	end
end)

case("draft discovery switches locally without creating or changing saved providers", function()
	for _, editingSaved in ipairs({ false, true }) do
		local f = fixture(); local saved = f.record; local direct = saved.baseUrl
		if editingSaved then f.registry.save(saved) end
		local draft = f.env.require("runtime/util").deepCopy(saved); if not editingSaved then draft.id = "" end
		local models = f.env.require("provider/models")
		f.h.http.handler = function(entry)
			if entry.index == 1 then return { StatusCode = 403, Body = "Unauthorized client" } end
			check("discovery retries correct proxy route", entry.url == PROXY .. "opencode/v1/models")
			return { StatusCode = 200, Body = '{"data":[{"id":"discovered-model"}]}' }
		end
		local ids, why = f.run(function() return models.discover(draft) end)
		check("models recovered: " .. tostring(why), ids[1] == "discovered-model" and f.h.http.requestCount == 2)
		check("new connection owns cache", models.cached(draft)[1] == "discovered-model" and draft.baseUrl == PROXY .. "opencode/v1")
		check("draft did not create or overwrite saved entry", f.registry.count() == (editingSaved and 1 or 0) and saved.baseUrl == direct)
		f.healthy(); f.close()
	end
end)

case("live discovery persists its switch and refuses stale discovery responses", function()
	local f = fixture("agentrouter"); f.registry.save(f.record)
	f.h.http.handler = function(entry)
		if entry.index == 1 then return f.refusal() end
		return { StatusCode = 200, Body = '{"data":[{"id":"proxy-model"}]}' }
	end
	local ids = f.run(function() return f.env.require("provider/models").discover(f.record) end)
	check("live discovery persisted", ids[1] == "proxy-model" and f.registry.get(f.record.id).baseUrl == PROXY .. "agentrouter/v1")
	f.record.baseUrl = "https://agentrouter.org/v1"
	f.h.http.handler = function() local res = f.refusal(); res.delay = 0.1; return res end
	f.h.sched.delay(0.05, function() f.record.apiKey = "edited-key" end)
	local before = f.h.http.requestCount
	local stale, why = f.run(function() return f.env.require("provider/models").discover(f.record, { force = true }) end)
	check("changed connection stays unchanged", #stale == 0 and has(why, "changed") and f.h.http.requestCount == before + 1 and f.record.baseUrl == "https://agentrouter.org/v1")
	f.healthy(); f.close()
end)

case("cancelled and timed out inference never switch or dispatch again", function()
	for _, protocol in ipairs({ "openai", "anthropic" }) do
		for _, mode in ipairs({ "cancel", "timeout" }) do
			local f = fixture("zen", protocol); local original = f.record.baseUrl; local stopped = false
			f.h.http.handler = function() local res = f.refusal(); res.delay = mode == "cancel" and 0.2 or 2; return res end
			if mode == "cancel" then f.h.sched.delay(0.05, function() stopped = true end) end
			local result, why = f.complete({ timeout = 1, aborted = function() return stopped end }, 1.2)
			check("terminal response does not recover", not result and f.env.require("net/http").terminal(why) and f.h.http.requestCount == 1 and f.record.baseUrl == original)
			f.h.sched.advance(2); check("late refusal is ignored", f.h.http.requestCount == 1 and f.record.baseUrl == original)
			f.healthy(); f.close()
		end
	end
end)

case("proxy retry shares the HTTP request deadline", function()
	for _, protocol in ipairs({ "openai", "anthropic" }) do
		local f = fixture("zen", protocol)
		f.h.http.handler = function(entry)
			local res = entry.index == 1 and f.refusal() or f.reply(); res.delay = 0.65; return res
		end
		local result, why = f.complete({ timeout = 1 }, 1.2)
		check("second request cannot reset the budget", not result and has(why, "deadline") and f.h.http.requestCount == 2)
		f.h.sched.advance(1); f.healthy(); f.close()
	end
end)

case("in-flight edits or removal cannot be overwritten by recovery", function()
	for _, mode in ipairs({ "url", "auth", "replace", "remove" }) do
		local f = fixture(); f.registry.save(f.record); local original = f.record.baseUrl
		f.h.http.handler = function() local res = f.refusal(); res.delay = 0.1; return res end
		f.h.sched.delay(0.05, function()
			if mode == "url" then f.record.baseUrl = "https://custom.test/v1"
			elseif mode == "auth" then f.record.apiKey = "edited-key"
			elseif mode == "replace" then
				local updated = f.env.require("runtime/util").deepCopy(f.record); updated.label = "Updated"; f.registry.save(updated)
			else f.registry.remove(f.record.id) end
		end)
		check("old request stops without proxy", not f.complete() and f.h.http.requestCount == 1)
		check("does not replace the current URL", f.record.baseUrl == (mode == "url" and "https://custom.test/v1" or original))
		check("removed provider stays removed", mode ~= "remove" or f.registry.count() == 0)
		check("new record stays selected", mode ~= "replace" or f.registry.get(f.record.id).label == "Updated")
		f.healthy(); f.close()
	end
end)

case("recovery callbacks cannot force another send after cancellation or changes", function()
	for _, mode in ipairs({ "cancel", "edit", "raise" }) do
		local f = fixture(); local stopped = false
		f.h.http.handler = function(entry) return entry.index == 1 and f.refusal() or f.reply() end
		local result = f.complete({ aborted = function() return stopped end, onRetry = function()
			if mode == "cancel" then stopped = true elseif mode == "edit" then f.record.baseUrl = "https://custom.test/v1" else error("fixture callback") end
		end })
		if mode == "raise" then check("callback exception is contained", result and f.h.http.requestCount == 2)
		else check("callback cancellation or editing stops dispatch", not result and f.h.http.requestCount == 1) end
		f.healthy(); f.close()
	end
end)

case("known proxy inference bypasses a gateway with its own upstream origin", function()
	local f = fixture(); f.record.baseUrl = PROXY .. "opencode/v1"; f.record.wsUrl = "wss://custom-gateway.test/stream"
	local caps = f.env.require("runtime/caps"); caps.ws = true
	local connects = 0; caps.fn.websocket = function() connects = connects + 1; error("must use proxy HTTP") end
	f.h.http.handler = function() return f.reply() end
	check("proxy used HTTP without connecting to old gateway", f.complete({ stream = true }) ~= nil and connects == 0 and f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

suite.finish()
