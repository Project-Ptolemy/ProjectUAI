-- Observed inference sends are distinct from messages, discovery and relay polls.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Per-key and conversation request accounting")
local case, check = suite.case, suite.check

local function fixture(protocol)
	local f = F.new()
	f.stats = f.env.require("agent/stats"); f.stats.load(); f.stats.observe()
	f.keys = f.env.require("runtime/provider_keys")
	f.accounting = f.env.require("runtime/request_accounting")
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank("custom")
	f.record.id, f.record.label, f.record.baseUrl = "usage-provider", "Usage fixture", "https://usage.fixture/v1"
	f.record.apiKey, f.record.model, f.record.models = "fixture-first-1111\nfixture-second-2222", "fixture-model", { "fixture-model" }
	f.record.api = protocol == "anthropic" and "anthropic" or protocol == "gemini" and "gemini" or "openai"
	if protocol == "gemini" then f.record.authStyle = "x-goog-api-key" end
	if protocol == "responses" then f.record.baseUrl, f.record.repairs = "https://opencode.ai/zen/v1", { "responses_protocol" } end
	f.keys.ensureIds(f.record)
	f.session = { id = "usage-conversation", depth = 0 }
	function f.reply()
		local usage, body = { prompt_tokens = 11, completion_tokens = 7 }
		if protocol == "anthropic" then
			body = { type = "message", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn", usage = { input_tokens = 11, output_tokens = 7 } }
		elseif protocol == "responses" then
			body = { status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } }, usage = { input_tokens = 11, output_tokens = 7 } }
		elseif protocol == "gemini" then
			body = { candidates = { { content = { role = "model", parts = { { text = "ready" } } }, finishReason = "STOP" } },
				usageMetadata = { promptTokenCount = 11, candidatesTokenCount = 7, totalTokenCount = 18 } }
		else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } }, usage = usage } end
		return { StatusCode = 200, Body = f.h.json.encode(body) }
	end
	f.h.http.handler = function() return f.reply() end
	function f.complete(options, seconds)
		return f.run(function()
			local request = { messages = { { role = "user", content = "hello" } }, session = f.session, stream = false, attempts = 1 }
			for name, value in pairs(options or {}) do request[name] = value end
			return f.env.require("provider/chat").complete(f.record, request)
		end, seconds or 0.3)
	end
	return f
end

for _, protocol in ipairs({ "openai", "anthropic", "responses", "gemini" }) do
	case(protocol .. " credits the actual rotated keys and normalized tokens once", function()
		local f = fixture(protocol)
		local first = assert(f.complete()); assert(f.complete())
		for index = 1, 2 do
			local row = f.stats.keyUsage(f.record, index)
			check("one dispatch and its usage belong to key " .. index, row.requests == 1 and row.tokensIn == 11 and row.tokensOut == 7 and not row.estimated)
		end
		f.env.require("agent/usage").record(first.usage, "fixture-model", { accounting = first.accounting, prompt = 100, completion = 50 }, f.record)
		check("existing aggregate usage does not double count key tokens", f.stats.keyUsage(f.record, 1).tokensIn == 11)
		local conversation = f.stats.conversationUsage(f.session)
		check("conversation counter includes both sends", conversation.requests == 2 and conversation.tokensIn == 22 and conversation.tokensOut == 14)
		check("references never carry credentials or names", not f.h.json.encode(first.accounting):find("fixture-first", 1, true)
			and first.accounting.providerId == f.record.id and first.accounting.keyId == f.record.keyIds[1])
		f.healthy(); f.close()
	end)
end

case("quota rotation and ordinary transport retries count every inference send", function()
	local f = fixture("openai")
	f.h.http.handler = function(entry)
		if entry.index == 1 then return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded"}}' } end
		return f.reply()
	end
	assert(f.complete())
	check("quota refusal and replacement key are separate requests", f.stats.conversationUsage(f.session).requests == 2
		and f.stats.keyUsage(f.record, 1).requests == 1 and f.stats.keyUsage(f.record, 1).tokensIn == 0
		and f.stats.keyUsage(f.record, 2).requests == 1 and f.stats.keyUsage(f.record, 2).tokensIn == 11)
	assert(f.keys.setMode(f.record, "single", 2))
	local attempts = 0
	f.h.http.handler = function()
		attempts = attempts + 1
		if attempts == 1 then return { StatusCode = 500, Body = '{"error":{"message":"server busy"}}' } end
		return f.reply()
	end
	assert(f.complete({ attempts = 2 }, 15))
	check("transport retry stays on its key and counts both sends", attempts == 2 and f.stats.keyUsage(f.record, 2).requests == 3
		and f.stats.conversationUsage(f.session).requests == 4 and f.stats.keyUsage(f.record, 2).tokensIn == 22)
	f.healthy(); f.close()
end)

case("cancelled, unavailable and discovery requests never become inference counts", function()
	local f = fixture("openai")
	local result = f.complete({ aborted = function() return true end })
	check("pre-cancelled request dispatches nothing", result == nil and f.h.http.requestCount == 0 and f.stats.conversationUsage(f.session).requests == 0)
	local caps = f.env.require("runtime/caps")
	caps.fn.request, caps.http = nil, "none"
	result = f.complete()
	check("missing transport has no dispatched request", result == nil and f.stats.conversationUsage(f.session).requests == 0)
	f.close()
	f = fixture("openai")
	f.h.http.handler = function() return { StatusCode = 200, Body = '{"data":[{"id":"fixture-model"}]}' } end
	local result = f.run(function() return f.env.require("provider/models").discover(f.record, { force = true }) end, 0.4)
	check("discovery makes network requests without inference usage", result ~= nil and f.h.http.requestCount > 0
		and f.stats.keyUsage(f.record, 1).requests == 0 and f.stats.conversationUsage(f.session).requests == 0)
	f.healthy(); f.close()
end)

case("key identity and conversation ownership remain fixed for in-flight results", function()
	local f = fixture("openai")
	local original = f.env.require("runtime/util").deepCopy(f.record)
	local parent = f.session
	local child = { id = "child", headless = true, depth = 1, accountingParent = function() return parent end }
	local tracker = f.accounting.new(original, { session = child })
	tracker.dispatch("fixture-first-1111")
	parent = { id = "second-conversation", depth = 0 }
	assert(f.keys.rename(f.record, 1, "Renamed")); assert(f.keys.remove(f.record, 2))
	check("rename and unrelated removal keep historical key usage", f.stats.keyUsage(f.record, 1).requests == 1)
	local prepared = f.accounting.new(f.record, { session = f.session })
	assert(f.keys.replace(f.record, 1, "fixture-replacement-3333"))
	prepared.dispatch("fixture-first-1111")
	check("a prepared send retains its original key identity across live replacement", f.stats.keyUsage(original, 1).requests == 2)
	tracker.attach({ usage = { prompt_tokens = 8, completion_tokens = 4 } })
	check("replacement gets new usage while old result stays with old identity", f.stats.keyUsage(f.record, 1).requests == 0
		and f.stats.keyUsage(original, 1).tokensIn == 8 and f.stats.conversationUsage(f.session).tokensOut == 4)
	local nextTracker = f.accounting.new(f.record, { session = child }); nextTracker.dispatch("fixture-replacement-3333")
	check("future subagent calls follow the new parent", f.stats.conversationUsage(parent).requests == 1
		and f.stats.conversationUsage(f.session).requests == 2)
	f.healthy(); f.close()
end)

case("missing usage is estimated once and complete reports remain measured", function()
	local f = fixture("openai")
	local tracker = f.accounting.new(f.record, { session = f.session }); tracker.dispatch("fixture-first-1111")
	local result = tracker.attach({ usage = { prompt_tokens = 10 } })
	local usage = f.env.require("agent/usage")
	usage.record(result.usage, "fixture-model", { accounting = result.accounting, prompt = 100, completion = 3 }, f.record)
	usage.record(result.usage, "fixture-model", { accounting = result.accounting, prompt = 100, completion = 3 }, f.record)
	local row = f.stats.keyUsage(f.record, 1)
	check("missing output alone uses one labeled estimate", row.tokensIn == 10 and row.tokensOut == 3 and row.estimated and row.requests == 1)
	local second = f.accounting.new(f.record, { session = f.session }); second.dispatch("fixture-second-2222")
	local result2 = second.attach({ usage = { prompt_tokens = 8 } })
	f.accounting.report(result2.accounting, { completion_tokens = 4 }, { prompt = 99 })
	check("unused estimated fields never label a measured new field", not f.stats.keyUsage(f.record, 2).estimated)
	f.healthy(); f.close()
end)

case("usage survives reload without storing keys or private names", function()
	local f = fixture("openai")
	assert(f.keys.rename(f.record, 1, "Private account name"))
	assert(f.complete())
	local since = f.stats.conversationUsage(f.session).trackedSince
	assert(f.stats.saveNow())
	local text = f.h.files["UAI/stats.json"]
	check("stats contains only opaque key identities", text and text:find(f.record.keyIds[1], 1, true)
		and not text:find("fixture-first-1111", 1, true) and not text:find("Private account name", 1, true))
	f.stats.load()
	check("conversation requests and token counts persist", f.stats.conversationUsage(f.session).requests == 1
		and f.stats.conversationUsage(f.session).trackedSince == since and f.stats.keyUsage(f.record, 1).tokensOut == 7)
	local copy = f.env.require("runtime/util").deepCopy(f.record); copy.id = "duplicate-provider"
	check("another provider cannot inherit usage from copied key IDs", f.stats.keyUsage(copy, 1).requests == 0)
	local data = f.h.json.decode(text)
	data.conversationUsage[f.session.id] = { requests = 1e100, tokensIn = -1, tokensOut = 1.5 }
	data.keyUsage[f.record.id][f.record.keyIds[1]] = { requests = 7, tokensIn = 1e100, tokensOut = -4 }
	f.h.files["UAI/stats.json"] = f.h.json.encode(data); f.stats.load()
	check("malformed persisted counters become safe zeroes", f.stats.conversationUsage(f.session).requests == 0
		and f.stats.conversationUsage(f.session).tokensIn == 0 and f.stats.conversationUsage(f.session).tokensOut == 0
		and f.stats.keyUsage(f.record, 1).tokensIn == 0 and f.stats.keyUsage(f.record, 1).tokensOut == 0)
	-- The mock JSON encoder intentionally rounds large numbers to 14 digits;
	-- exercise arithmetic saturation without making that an encoding assertion.
	f.stats.data.keyUsage[f.record.id][f.record.keyIds[1]].requests = 9007199254740991
	local tracker = f.accounting.new(f.record, { session = f.session }); tracker.dispatch("fixture-first-1111")
	check("safe-integer counters saturate without overflow", f.stats.keyUsage(f.record, 1).requests == 9007199254740991)
	f.healthy(); f.close()
end)

case("explicit authentication overrides do not falsely attribute a saved key", function()
	local f = fixture("openai")
	f.record.headers = { Authorization = "Bearer separately-configured-credential" }
	assert(f.complete())
	check("inference still counts for its conversation", f.stats.conversationUsage(f.session).requests == 1)
	check("a configured key absent from final headers receives no usage", f.stats.keyUsage(f.record, 1).requests == 0)
	f.healthy(); f.close()
end)

case("relay hello, submission receipt recovery and result polls count one inference", function()
	local f = fixture("openai")
	f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
	local submissions, polls, id, token = 0, 0, nil, string.rep("a", 64)
	local function reply(value, status) return { StatusCode = status or 200, Body = f.h.json.encode(value) } end
	f.h.http.relay = function(request)
		if request.url:find("/api/hello", 1, true) then return reply({ ok = true, server = "uai-relay", protocol = 2, instance = "usage-relay" }) end
		if request.url:find("/api/pair", 1, true) then return reply({ ok = true, protocol = 2, instance = "usage-relay", token = token }) end
		if request.method == "POST" then
			submissions = submissions + 1
			local input = f.h.json.decode(request.body)
			if id then check("receipt recovery retains the same inference ID", input.id == id) else id = input.id end
			if submissions == 1 then return reply({ error = "temporary receipt failure" }, 500) end
			return reply({ id = id, state = "running" }, 202)
		end
		polls = polls + 1
		return reply({ id = id, state = "completed", status = 200, body = f.reply().Body })
	end
	assert(f.run(f.env.require("net/relay_link").scan, 1))
	assert(f.complete(nil, 5))
	check("two submissions and one poll are one logical relay inference", submissions == 2 and polls == 1
		and f.stats.conversationUsage(f.session).requests == 1 and f.stats.keyUsage(f.record, 1).requests == 1
		and f.stats.keyUsage(f.record, 1).tokensIn == 11)
	f.healthy(); f.close()
end)

case("synthetic Free probes count against their key without any conversation", function()
	local f = fixture("openai")
	f.env.require("runtime/clock").ms = function() return 1767268800000 + f.h.sched.now * 1000 end -- 20:00 UTC+8.
	local record = f.registry.blank("projectuai-free"); assert(f.registry.save(record))
	local posts = 0
	f.h.http.handler = function(entry)
		if entry.url:find("/models", 1, true) then return { StatusCode = 200, Body = '{"data":[{"id":"auto"}]}' } end
		posts = posts + 1
		local body = f.h.json.decode(entry.body)
		local replay = body.messages[#body.messages].role == "tool"
		local message = { role = "assistant", content = replay and "PONG" or "" }
		if not replay then message.tool_calls = { { id = "probe", type = "function", ["function"] = { name = "uai_ping", arguments = '{"nonce":"ok"}' } } } end
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = message, finish_reason = replay and "stop" or "tool_calls" } },
			usage = { prompt_tokens = 3, completion_tokens = 2 } }) }
	end
	f.env.require("provider/free_route").refresh(record); f.h.sched.advance(2)
	check("probe and tool replay count as two inference sends", posts == 2 and f.stats.keyUsage(record, 1).requests == 2 and f.stats.keyUsage(record, 1).tokensIn == 6)
	check("synthetic checks never enter conversation counters", next(f.stats.data.conversationUsage) == nil)
	f.healthy(); f.close()
end)

case("socket setup failure counts only HTTP fallback and socket Send counts once", function()
	local f = fixture("openai")
	local caps = f.env.require("runtime/caps")
	caps.ws, caps.fn.websocket = true, function() error("connection failed before send") end
	f.record.wsUrl = "wss://usage.fixture/stream"
	assert(f.complete({ stream = true }))
	check("failed socket setup creates no extra request", f.stats.conversationUsage(f.session).requests == 1 and f.h.http.requestCount == 1)
	local signal = require("instance").newSignal
	caps.fn.websocket = function()
		local socket = { OnMessage = signal("usage message"), OnClose = signal("usage close") }
		function socket:Send()
			self.OnMessage:Fire(f.h.json.encode({ choices = { { delta = { content = "ready" }, finish_reason = "stop" } }, usage = { prompt_tokens = 5, completion_tokens = 2 } }))
			self.OnMessage:Fire("[DONE]")
		end
		function socket:Close() self.OnClose:Fire() end
		return socket
	end
	assert(f.complete({ stream = true }))
	check("socket Send contributes exactly one request and its own tokens", f.stats.conversationUsage(f.session).requests == 2
		and f.stats.keyUsage(f.record, 2).requests == 1 and f.stats.keyUsage(f.record, 2).tokensIn == 5 and f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

suite.finish()
