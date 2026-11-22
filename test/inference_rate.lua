-- Synthetic dispatch limits: virtual time only, no provider traffic or secrets.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Inference request rate limits")
local case, check = suite.case, suite.check
local function has(value, part) return tostring(value or ""):find(part, 1, true) ~= nil end

local function fixture()
	local f = F.new()
	f.config, f.clock = f.env.require("runtime/config"), f.env.require("runtime/clock")
	f.rate = f.env.require("runtime/inference_rate")
	function f.context(id, limit, valid, deadline)
		local record = { id = id, requestsPerMinute = limit or 0 }
		local context = f.rate.context({ provider = f.rate.providerKey(record), valid = valid, deadlineMs = deadline,
			limit = function() return record.requestsPerMinute end })
		return context, record
	end
	function f.dispatch(context, options)
		local permit, problem = f.rate.acquire(context, options)
		if not permit then return nil, problem end
		local ok, why, kind = permit.commit(); permit.release()
		return ok and true or nil, why, kind
	end
	return f
end

case("global and provider caps count actual attempts in independent rolling windows", function()
	local f = fixture(); f.config.set("agent.requestsPerMinute", 3)
	local a = f.context("a", 2); local b = f.context("b", 2)
	assert(f.dispatch(a)); assert(f.dispatch(a)); assert(f.dispatch(b))
	local result, time
	f.h.sched.spawn(function() result = f.dispatch(a); time = f.h.sched.now end)
	f.h.sched.advance(59.9)
	check("blocked admission consumes no extra count or permit", result == nil and f.rate.state(a).tracked == 3
		and f.rate.state(a).providerTracked == 2 and f.rate.state().held == 0)
	f.h.sched.advance(0.2)
	check("the oldest dispatch expires after sixty seconds", result and time >= 60 and time < 60.2
		and f.rate.state(a).tracked == 1 and f.rate.state(a).providerTracked == 1)
	f.healthy(); f.close()
end)

case("FIFO admission keeps provider order and lets an eligible provider pass", function()
	local f = fixture(); local a = f.context("a", 1); local b = f.context("b", 0)
	assert(f.dispatch(a))
	local order = {}
	for _, name in ipairs({ "first", "second" }) do
		local label = name
		f.h.sched.spawn(function() assert(f.dispatch(a)); order[#order + 1] = label end)
	end
	f.h.sched.spawn(function() assert(f.dispatch(b)); order[#order + 1] = "other" end)
	check("other provider bypasses the provider-blocked head", table.concat(order, ",") == "other" and f.rate.state().queued == 2)
	f.h.sched.advance(60.1)
	check("oldest waiter is admitted first", table.concat(order, ",") == "other,first" and f.rate.state().queued == 1)
	f.h.sched.advance(60.1)
	check("later waiter cannot steal earlier capacity", table.concat(order, ",") == "other,first,second" and f.rate.state().held == 0)
	f.healthy(); f.close()
end)

case("releasing an unused permit admits the next waiter without a phantom request", function()
	local f = fixture(); f.config.set("agent.requestsPerMinute", 1)
	local context = f.context("release", 1)
	local first = assert(f.rate.acquire(context)); local result
	f.h.sched.spawn(function() result = f.dispatch(context) end)
	check("a held permit reserves both caps without recording a dispatch", f.rate.state(context).held == 1
		and f.rate.state(context).tracked == 0 and result == nil)
	first.release(); first.release(); f.h.sched.advance(0.1)
	check("released capacity is reusable immediately", result and f.rate.state(context).tracked == 1
		and f.rate.state(context).providerTracked == 1 and f.rate.state(context).held == 0 and not first.commit())
	f.healthy(); f.close()
end)

case("a global cap preserves FIFO order across different providers", function()
	local f = fixture(); f.config.set("agent.requestsPerMinute", 1)
	assert(f.dispatch((f.context("primer", 0))))
	local order = {}
	for _, id in ipairs({ "older", "newer" }) do
		local context, label = f.context(id, 0), id
		f.h.sched.spawn(function() assert(f.dispatch(context)); order[#order + 1] = label end)
	end
	f.h.sched.advance(60.1)
	check("the older provider owns the first global slot", table.concat(order, ",") == "older" and f.rate.state().queued == 1)
	f.h.sched.advance(60.1)
	check("a newer provider cannot overtake the global queue", table.concat(order, ",") == "older,newer" and f.rate.state().held == 0)
	f.healthy(); f.close()
end)

case("enabling and changing caps observes recent unlimited dispatches", function()
	local f = fixture(); local context, record = f.context("changes", 0)
	for _ = 1, 3 do assert(f.dispatch(context)) end
	f.config.set("agent.requestsPerMinute", 2); record.requestsPerMinute = 1
	local result
	f.h.sched.spawn(function() result = f.dispatch(context) end)
	f.config.set("agent.requestsPerMinute", 5); f.h.sched.advance(0.1)
	check("provider cap still blocks after global cap is raised", result == nil and f.rate.state().queued == 1)
	record.requestsPerMinute = 4; f.h.sched.advance(0.1)
	check("raising both caps admits without clearing recent history", result and f.rate.state(context).tracked == 4)
	record.requestsPerMinute = 5
	local permit = assert(f.rate.acquire(context)); f.config.set("agent.requestsPerMinute", 4)
	local committed, _, kind = permit.commit()
	check("lowering a cap rejects an unused reservation before dispatch", not committed and kind == "rate"
		and f.rate.state(context).tracked == 4 and f.rate.state().held == 0)
	f.config.set("agent.requestsPerMinute", 0); record.requestsPerMinute = 0
	assert(f.dispatch(context)); check("zero removes both caps", f.rate.state(context).tracked == 5)
	f.healthy(); f.close()
end)

case("cancellation and explicit deadlines work without an optional validity callback", function()
	local f = fixture(); f.config.set("agent.requestsPerMinute", 1)
	local context = f.context("cancel", 0); assert(f.dispatch(context))
	local cancelled, result, problem, notices = false, nil, nil, {}
	f.h.sched.spawn(function()
		result, problem = f.dispatch(context, { aborted = function() return cancelled end,
			onRetry = function(info) notices[#notices + 1] = info.phase end })
	end)
	cancelled = true; f.h.sched.advance(0.1)
	check("optional aborted callback is checked independently", result == nil and problem == "aborted"
		and table.concat(notices, ",") == "waiting,cancelled" and f.rate.state().queued == 0 and f.rate.state().tracked == 1)
	local short = f.context("deadline", 0, nil, f.clock.ms() + 1000)
	local why
	f.h.sched.spawn(function() why = select(2, f.dispatch(short)) end)
	f.h.sched.advance(1.1)
	check("deadline expires while queued without dispatch or reservation", has(why, "deadline:")
		and f.rate.state().queued == 0 and f.rate.state().held == 0 and f.rate.state().tracked == 1)
	f.healthy(); f.close()
end)

case("dispatch timestamps and deadlines include CPU time spent checking ownership", function()
	local f = fixture(); local base, at, slow = f.clock.ms(), f.clock.ms(), false
	f.clock.ms = function() return at end
	local context = f.context("cpu-deadline", 0, function() if slow then at = at + 1001 end; return true end, base + 1000)
	local permit = assert(f.rate.acquire(context)); slow = true
	local committed, why = permit.commit()
	check("an ownership check cannot spend the last budget and then dispatch", not committed and has(why, "deadline:")
		and f.rate.state().tracked == 0 and f.rate.state().held == 0)
	f.close(); f = fixture(); base, at, slow = f.clock.ms(), f.clock.ms(), false
	f.clock.ms = function() return at end
	f.config.set("agent.requestsPerMinute", 1)
	context = f.context("cpu-stamp", 0, function() if slow then at = at + 200 end; return true end)
	permit = assert(f.rate.acquire(context)); slow = true; assert(permit.commit()); slow = false
	at = base + 60000
	check("the rolling window starts at dispatch after the check", f.rate.state(context).tracked == 1)
	at = base + 60200
	check("the actual dispatch timestamp expires sixty seconds later", f.rate.state(context).tracked == 0)
	f.healthy(); f.close()
end)

case("ownership loss, invalid live policy and unload clear queued work", function()
	local f = fixture(); f.config.set("agent.requestsPerMinute", 1)
	local valid = true; local context = f.context("ownership", 0, function() return valid end)
	assert(f.dispatch(context)); local why
	f.h.sched.spawn(function() why = select(2, f.dispatch(context)) end)
	valid = false; f.h.sched.advance(0.1)
	check("lost ownership stops queued inference", why == "aborted" and f.rate.state().held == 0)
	valid = true; why = nil
	f.h.sched.spawn(function() why = select(2, f.dispatch(context)) end)
	f.config.data.agent.requestsPerMinute = 0.5; f.h.sched.advance(0.1)
	check("invalid live policy fails closed", has(why, "malformed:") and f.rate.state().tracked == 1 and f.rate.state().queued == 0)
	f.config.set("agent.requestsPerMinute", 2)
	local held = assert(f.rate.acquire(context)); why = nil
	f.h.sched.spawn(function() why = select(2, f.dispatch(context)) end)
	f.close(); f.h.sched.advance(0.1)
	check("unload releases queued and held capacity", why == "aborted" and not held.commit()
		and not f.rate.state().alive and f.rate.state().held == 0 and f.rate.state().queued == 0 and f.rate.state().buckets == 0)
	f.healthy()
end)

case("draft snapshots share a cap while separate drafts remain independent", function()
	local f = fixture(); local registry = f.env.require("provider/registry")
	local draft = registry.blank("custom"); draft.requestsPerMinute = 1
	local first = registry.requestSnapshot(draft); local second = registry.requestSnapshot(draft)
	local a = registry.inferenceContext(first, function() return true end)
	local b = registry.inferenceContext(second, function() return true end)
	assert(f.dispatch(a)); local result
	f.h.sched.spawn(function() result = f.dispatch(b) end)
	local separate = registry.blank("custom"); separate.requestsPerMinute = 1
	assert(f.dispatch(registry.inferenceContext(separate, function() return true end)))
	check("snapshot cannot reset the draft's cap", result == nil and f.rate.state(b).providerTracked == 1 and f.rate.state().tracked == 2)
	draft.requestsPerMinute = 2; f.h.sched.advance(0.1)
	check("draft policy changes reach its snapshots", result and f.rate.state(b).providerTracked == 2)
	f.healthy(); f.close()
end)

case("unlimited counters coalesce and scope and pending bounds fail before dispatch", function()
	local f = fixture(); local context = f.context("unlimited", 0)
	for _ = 1, 10000 do assert(f.dispatch(context)) end
	check("same-instant unlimited traffic uses two bounded buckets", f.rate.state(context).buckets == 2 and f.rate.state(context).tracked == 10000)
	f.close(); f = fixture()
	local permits = {}; local same = f.context("pending", 0)
	for index = 1, 512 do permits[index] = assert(f.rate.acquire(same)) end
	local extra, why = f.rate.acquire(same)
	check("pending overflow returns a terminal capacity reason", extra == nil and has(why, "capacity:") and f.rate.state().tracked == 0)
	for _, permit in ipairs(permits) do permit.release() end
	for index = 1, 512 do assert(f.dispatch((f.context("scope-" .. tostring(index), 0)))) end
	extra, why = f.rate.acquire((f.context("scope-overflow", 0)))
	check("scope overflow cannot dispatch or allocate beyond its bound", extra == nil and has(why, "capacity:") and f.rate.state().scopes == 512)
	f.h.sched.advance(60.1)
	assert(f.dispatch((f.context("scope-after-expiry", 0))))
	check("expired histories are reclaimed for future scopes", f.rate.state().scopes == 1 and f.rate.state().buckets == 2)
	f.healthy(); f.close()
end)

case("the shared timestamp storage bound fails closed and recovers after expiry", function()
	local f = fixture(); local base = f.clock.ms(); local at = base
	f.clock.ms = function() return at end
	local contexts = {}; for index = 1, 32 do contexts[index] = f.context("bucket-" .. tostring(index), 0) end
	local stopped, reason
	for tick = 1, 2000 do
		at = base + tick
		for _, context in ipairs(contexts) do
			local ok, why = f.dispatch(context)
			if not ok then stopped, reason = true, why; break end
		end
		if stopped then break end
	end
	check("timestamp overflow neither dispatches nor exceeds its bound", stopped and has(reason, "capacity:")
		and f.rate.state().buckets <= f.rate.state().limits.buckets and f.rate.state().held == 0)
	at = base + 62001; assert(f.dispatch(contexts[1]))
	check("storage becomes available once its events expire", f.rate.state().buckets == 2 and f.rate.state().tracked == 1)
	f.healthy(); f.close()
end)

case("RPM settings, provider validation and imports reject invalid whole-number values", function()
	local f = fixture(); local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.id, record.label, record.baseUrl = "rate-settings", "Rate settings", "https://rate.fixture/v1"
	record.authStyle, record.model, record.models = "none", "fixture-model", { "fixture-model" }
	check("default limits are unlimited", f.config.get("agent.requestsPerMinute") == 0 and record.requestsPerMinute == 0)
	assert(registry.save(record)); local transfer = f.env.require("runtime/config_transfer")
	for _, value in ipairs({ -1, 0.5, 1000001, math.huge, -math.huge, 0 / 0, "10", false }) do
		local before = f.config.get("agent.requestsPerMinute")
		check("invalid global value is rejected", f.config.set("agent.requestsPerMinute", value) == nil and f.config.get("agent.requestsPerMinute") == before)
		local candidate = f.env.require("runtime/util").deepCopy(record); candidate.requestsPerMinute = value
		check("provider validation and forced save reject invalid RPM", not registry.validate(candidate) and not registry.save(candidate, { force = true }))
		local snapshot = f.env.require("runtime/util").deepCopy(f.config.data); snapshot.providers.list[1].requestsPerMinute = value
		check("invalid import leaves the live configuration unchanged", transfer.validate(snapshot) == nil and f.config.get("providers.list")[1] == record)
	end
	local agent = f.env.require("runtime/util").deepCopy(f.config.get("agent")); agent.requestsPerMinute = 1.5
	check("section replacement and nested numeric edits cannot bypass validation", f.config.set("agent", agent) == nil
		and f.config.set("agent.requestsPerMinute.child", 1) == nil and f.config.set("providers.list.1.requestsPerMinute", 1.5) == nil)
	f.config.set("agent.requestsPerMinute", 17); record.requestsPerMinute = 9
	local body = assert(transfer.export()); local preview = assert(transfer.preview(body))
	check("public export and import retain both rate settings", preview.config.agent.requestsPerMinute == 17 and preview.config.providers.list[1].requestsPerMinute == 9)
	local duplicate = assert(f.env.require("provider/connection_actions").duplicate(record))
	check("duplicate retains its rate setting with independent identity", duplicate.requestsPerMinute == 9 and duplicate.id == "")
	local older = f.env.require("runtime/util").deepCopy(f.config.data); older.agent.requestsPerMinute, older.providers.list[1].requestsPerMinute = nil, nil
	local accepted = assert(transfer.validate(older))
	check("older copies default to unlimited", accepted.agent.requestsPerMinute == 0 and accepted.providers.list[1].requestsPerMinute == nil)
	f.healthy(); f.close()
end)

local function providerFixture(protocol)
	local f = fixture(); f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank("custom")
	f.record.id, f.record.label, f.record.baseUrl = "rate-provider", "Rate provider", "https://rate.fixture/v1"
	f.record.apiKey, f.record.model, f.record.models = "fixture-key-one\nfixture-key-two", "fixture-model", { "fixture-model" }
	f.record.api = protocol == "anthropic" and "anthropic" or protocol == "gemini" and "gemini" or "openai"
	if protocol == "gemini" then f.record.authStyle = "x-goog-api-key" end
	if protocol == "responses" then
		f.record.baseUrl, f.record.model, f.record.models = "https://api.openai.com/v1", "gpt-6.1-sol", { "gpt-6.1-sol" }
	end
	f.times = {}
	function f.reply()
		local body
		if protocol == "anthropic" then body = { type = "message", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn" }
		elseif protocol == "gemini" then body = { candidates = { { content = { role = "model", parts = { { text = "ready" } } }, finishReason = "STOP" } } }
		elseif protocol == "responses" then body = { object = "response", status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }
		else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } } end
		return { StatusCode = 200, Body = f.h.json.encode(body) }
	end
	f.h.http.handler = function() f.times[#f.times + 1] = f.h.sched.now; return f.reply() end
	function f.complete(options, seconds)
		return f.run(function()
			local request = { messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1 }
			for name, value in pairs(options or {}) do request[name] = value end
			return f.env.require("provider/chat").complete(f.record, request)
		end, seconds or 0.2)
	end
	return f
end

for _, protocol in ipairs({ "openai", "responses", "anthropic", "gemini" }) do
	case(protocol .. " quota rotation spends one rate slot per actual inference attempt", function()
		local f = providerFixture(protocol); f.config.set("agent.requestsPerMinute", 1)
		f.h.http.handler = function()
			f.times[#f.times + 1] = f.h.sched.now
			if #f.times == 1 then return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded"}}' } end
			return f.reply()
		end
		local notices = {}
		local result = f.complete({ timeout = 90, onRetry = function(info) if info.rateLimit then notices[#notices + 1] = info.phase end end }, 61)
		check("the rotated key waits for its own inference slot", result and result.content == "ready" and #f.times == 2
			and f.times[2] - f.times[1] >= 60 and table.concat(notices, ",") == "waiting,admitted" and f.rate.state().held == 0)
		f.healthy(); f.close()
	end)
end

case("transport retries are counted while model discovery and general HTTP are excluded", function()
	local f = providerFixture("openai"); f.config.set("agent.requestsPerMinute", 1); f.record.apiKey = "fixture-single-key"
	f.h.http.handler = function(entry)
		if entry.method == "GET" then return { StatusCode = 200, Body = '{"data":[{"id":"fixture-model"}]}' } end
		f.times[#f.times + 1] = f.h.sched.now
		if #f.times == 1 then return { StatusCode = 500, Body = '{"error":{"message":"server busy"}}' } end
		return f.reply()
	end
	local result
	f.h.sched.spawn(function() result = f.env.require("provider/chat").complete(f.record,
		{ messages = { { role = "user", content = "hi" } }, timeout = 90, stream = false, attempts = 2 }) end)
	f.h.sched.advance(2)
	local http = f.env.require("net/http")
	check("rate wait has no native HTTP worker", result == nil and #f.times == 1 and http.workers() == 0)
	assert(f.run(function() return f.env.require("provider/models").discover(f.record, { force = true }) end, 0.4))
	assert(f.run(function() return http.request({ url = "https://rate.fixture/general", method = "GET" }) end))
	check("discovery and general HTTP remain usable and uncounted", f.rate.state().tracked == 1 and f.h.http.requestCount >= 3)
	f.h.sched.advance(59)
	check("HTTP retry spends the next dispatch slot", result and #f.times == 2 and f.times[2] - f.times[1] >= 60)
	f.healthy(); f.close()
end)

case("protocol handoffs share both provider history and the original deadline", function()
	local f = providerFixture("openai"); f.record.baseUrl = "https://opencode.ai/zen/v1"
	f.record.requestsPerMinute = 1
	f.h.http.handler = function(entry)
		f.times[#f.times + 1] = f.h.sched.now
		if not entry.url:find("/responses", 1, true) then
			return { StatusCode = 400, Body = '{"error":{"type":"ModelProtocolUnsupported","message":"Model does not support this protocol"}}' }
		end
		return { StatusCode = 200, Body = f.h.json.encode({ object = "response", status = "completed",
			output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }) }
	end
	local result = f.complete({ timeout = 90 }, 61)
	check("Responses dispatch cannot bypass its preceding Chat attempt", result and #f.times == 2 and f.times[2] - f.times[1] >= 60)
	f.healthy(); f.close(); f = providerFixture("openai")
	f.record.baseUrl, f.record.requestsPerMinute = "https://opencode.ai/zen/v1", 1
	f.h.http.handler = function()
		f.times[#f.times + 1] = f.h.sched.now
		return { StatusCode = 400, Body = '{"error":{"type":"ModelProtocolUnsupported","message":"Model does not support this protocol"}}' }
	end
	local failed, why = f.complete({ timeout = 1 }, 1.2)
	check("reactive protocol change cannot restart a short caller budget", failed == nil and has(why, "deadline:") and #f.times == 1 and f.rate.state().held == 0)
	f.healthy(); f.close()
end)

case("socket setup releases unused permits and socket Send counts without HTTP replay", function()
	local f = providerFixture("openai"); f.config.set("agent.requestsPerMinute", 1)
	f.record.wsUrl = "wss://rate.fixture/stream"
	local caps = f.env.require("runtime/caps"); caps.ws = true
	caps.fn.websocket = function() error("synthetic setup failure") end
	assert(f.complete({ stream = true }))
	check("socket setup failure counts only its HTTP fallback", f.rate.state().tracked == 1 and f.h.http.requestCount == 1 and f.rate.state().held == 0)
	local connects, sends = 0, 0; local signal = require("instance").newSignal
	caps.fn.websocket = function()
		connects = connects + 1
		local socket = { OnMessage = signal("rate socket message"), OnClose = signal("rate socket close") }
		function socket:Send()
			sends = sends + 1
			self.OnMessage:Fire(f.h.json.encode({ choices = { { delta = { content = "ready" }, finish_reason = "stop" } } }))
			self.OnMessage:Fire("[DONE]")
		end
		function socket:Close() self.OnClose:Fire() end
		return socket
	end
	local result
	f.h.sched.spawn(function() result = f.env.require("provider/chat").complete(f.record,
		{ messages = { { role = "user", content = "hi" } }, timeout = 90, stream = true, attempts = 1 }) end)
	f.h.sched.advance(1)
	check("queued socket admission holds no native connection", connects == 0 and f.env.require("net/ws").state().workers == 0
		and f.env.require("net/ws").state().connections == 0)
	f.h.sched.advance(60)
	check("socket Send owns one attempt", result and connects == 1 and sends == 1 and f.h.http.requestCount == 1 and f.rate.state().held == 0)
	f.h.sched.advance(60)
	caps.fn.websocket = function()
		local socket = { OnMessage = signal("throwing socket message"), OnClose = signal("throwing socket close") }
		function socket:Send() sends = sends + 1; error("uncertain send") end
		function socket:Close() end
		return socket
	end
	local failed, why = f.complete({ stream = true })
	check("a throwing Send is counted and never replayed through HTTP", failed == nil and has(why, "deadline:")
		and sends == 2 and f.h.http.requestCount == 1 and f.rate.state().tracked == 1)
	f.healthy(); f.close()
end)

case("cancelled delayed workers and preparation exceptions release unused permits", function()
	local f = providerFixture("openai"); local spawn = f.clock.spawn
	f.clock.spawn = function(fn) return f.h.sched.delay(2, fn) end
	local result, why = f.complete({ timeout = 1 }, 1.1)
	check("caller timeout releases its undispatched permit", result == nil and has(why, "deadline:") and f.rate.state().tracked == 0
		and f.rate.state().held == 0 and f.env.require("net/http").workers() == 1)
	f.h.sched.advance(1.1)
	check("late worker cannot commit after its caller relinquished ownership", f.h.http.requestCount == 0 and f.env.require("net/http").workers() == 0)
	f.clock.spawn = function() error("synthetic spawn failure") end
	result, why = f.complete()
	check("spawn failure releases the permit and unused native slot", result == nil and has(why, "malformed:")
		and f.rate.state().held == 0 and f.rate.state().tracked == 0 and f.env.require("net/http").workers() == 0)
	f.record.wsUrl = "wss://rate.fixture/stream"
	local caps = f.env.require("runtime/caps"); caps.ws, caps.fn.websocket = true, function() error("unused socket") end
	result, why = f.complete({ stream = true })
	check("socket spawn failure also releases its unused worker and permit", result == nil and has(why, "malformed:")
		and f.rate.state().held == 0 and f.env.require("net/ws").state().workers == 0 and f.env.require("net/ws").state().connections == 0)
	f.record.wsUrl = ""
	f.clock.spawn = spawn; assert(f.complete())
	f.healthy(); f.close()
end)

case("relay admission waits outside short exchange timeouts and receipt recovery counts once", function()
	local f = providerFixture("openai"); f.config.set("agent.requestsPerMinute", 1)
	assert(f.complete())
	f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
	local submissions, polls, id, payload, budget = 0, 0, nil, nil, nil
	local token = string.rep("a", 64)
	local function reply(body, status) return { StatusCode = status or 200, Body = f.h.json.encode(body) } end
	f.h.http.relay = function(entry)
		if entry.url:find("/api/hello", 1, true) then return reply({ ok = true, server = "uai-relay", protocol = 2, instance = "rate-relay",
			capabilities = { inference = { schema = 1, unlimited = true } } }) end
		if entry.url:find("/api/pair", 1, true) then return reply({ ok = true, protocol = 2, instance = "rate-relay", token = token }) end
		if entry.url:find("/api/status", 1, true) then return reply({ ok = true, server = "uai-relay", protocol = 2, instance = "rate-relay" }) end
		if entry.method == "POST" then
			submissions = submissions + 1; local input = f.h.json.decode(entry.body)
			if not id then id, payload, budget = input.id, entry.body, input.timeout
			else check("receipt recovery preserves ID and original bytes", input.id == id and entry.body == payload) end
			if submissions == 1 then return reply({ error = "temporary receipt failure" }, 500) end
			return reply({ id = id, state = "running" }, 202)
		end
		polls = polls + 1; return reply({ id = id, state = "completed", status = 200, body = f.reply().Body })
	end
	assert(f.run(f.env.require("net/relay_link").scan, 1))
	local result
	f.h.sched.spawn(function() result = f.env.require("provider/chat").complete(f.record,
		{ messages = { { role = "user", content = "hi" } }, timeout = 90, stream = false, attempts = 1 }) end)
	f.h.sched.advance(2)
	check("relay hello and rate waiting occupy no native exchange slot", result == nil and submissions == 0
		and f.env.require("net/http").workers() == 0 and f.rate.state().tracked == 1)
	f.h.sched.advance(63)
	check("receipt recovery and polls spend only one inference slot", result and submissions == 2 and polls == 1
		and budget >= 29 and budget <= 33 and f.rate.state().tracked == 1 and f.rate.state().held == 0)
	f.healthy(); f.close()
end)

case("Cowork unlimited mode respects explicit relative and absolute caller deadlines", function()
	local f = providerFixture("openai"); f.config.set("agent.requestsPerMinute", 1); assert(f.complete())
	local endpoint = { target = "cowork", base = "http://127.0.0.1:8787", token = "fixture-bridge-token", instance = "rate-cowork" }
	f.loaded["net/transport"] = { endpoint = function() return endpoint end, unlimited = function() return true end,
		shouldRelay = function() return true end, streamForced = function() return true end, prepare = function() end }
	local submissions = 0
	f.h.http.handler = function(entry)
		if entry.url:find("/api/hello", 1, true) then return { StatusCode = 200,
			Body = f.h.json.encode({ protocol = 2, instance = endpoint.instance }) } end
		if entry.method == "POST" then submissions = submissions + 1 end
		return { StatusCode = 200, Body = "{}" }
	end
	local result, why = f.complete({ timeout = 1 }, 1.2)
	check("explicit timeout expires before relayed inference admission", result == nil and has(why, "deadline:") and submissions == 0)
	result, why = f.complete({ deadlineMs = f.clock.ms() + 1500 }, 1.7)
	check("absolute deadline survives every unlimited relay handoff", result == nil and has(why, "deadline:")
		and submissions == 0 and f.rate.state().held == 0 and f.rate.state().queued == 0)
	f.healthy(); f.close()
end)

suite.finish()
