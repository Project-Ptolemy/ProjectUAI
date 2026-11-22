-- Source-level companion lifecycle regressions; no Android device or provider.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local Z = require("opencode_catalog_fixture")
local suite = F.suite("Mobile companion deadlines")
local case, check = suite.case, suite.check

local function fixture(options)
	options = options or {}
	local f = F.new()
	f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
	f.available, f.instance, f.token = true, "phone-fixture", ("a"):rep(64)
	f.helloCount, f.pairs, f.authChecks, f.posts, f.polls, f.deletes, f.direct = 0, 0, 0, 0, 0, 0, 0
	f.inputs, f.jobs, f.maxExchange = {}, {}, 0
	local nativeRequest = f.h.sandbox.request
	f.h.sandbox.request = function(request)
		f.maxExchange = math.max(f.maxExchange, tonumber(request.Timeout) or 0)
		return nativeRequest(request)
	end
	function f.reply(value, status, delay)
		return { StatusCode = status or 200, Body = f.h.json.encode(value), delay = delay }
	end
	function f.hello()
		return f.reply({ ok = true, protocol = 2, server = "uai-relay", instance = f.instance,
			capabilities = options.legacy and {} or { inference = { schema = 1, unlimited = true } } }, 200, options.helloDelay)
	end
	f.h.http.relay = function(request)
		if not f.available then return f.reply({ error = "app stopped" }, 503) end
		if request.url:find("/api/hello", 1, true) then f.helloCount = f.helloCount + 1; return f.hello() end
		if request.url:find("/api/pair", 1, true) then
			f.pairs = f.pairs + 1
			return f.reply({ ok = true, protocol = 2, instance = f.instance, token = f.token })
		end
		if request.url:find("/api/status", 1, true) then
			f.authChecks = f.authChecks + 1
			if request.headers.Authorization ~= "Bearer " .. f.token then return f.reply({ error = "bad token" }, 401) end
			return f.hello()
		end
		if request.method == "DELETE" then f.deletes = f.deletes + 1; return f.reply({ cancelled = true }) end
		if request.method == "POST" then
			f.posts = f.posts + 1
			local input = f.h.json.decode(request.body)
			f.inputs[#f.inputs + 1] = input
			if input.timeout % 1 ~= 0 then return f.reply({ error = "invalid request: integer timeout required" }, 400) end
			f.jobs[input.id] = { at = f.h.sched.now, input = input }
			return f.reply({ id = input.id, state = "running" }, 202)
		end
		local id = request.url:match("/api/inference/(.+)$")
		assert(id and f.jobs[id], "poll must refer to the accepted job")
		f.polls = f.polls + 1
		return f.onPoll(id, f.jobs[id])
	end
	f.h.http.handler = function() f.direct = f.direct + 1; return f.reply({ error = "unexpected direct provider call" }, 400) end
	f.config = f.env.require("runtime/config")
	if options.savedToken then f.config.set("relay.token", options.savedToken) end
	f.link = f.env.require("net/relay_link")
	function f.scan() return f.run(f.link.scan, 1) end
	function f.running(id, delay) return f.reply({ id = id, state = "running" }, 200, delay) end
	function f.completed(id, body) return f.reply({ id = id, state = "completed", status = 200, headers = {}, body = f.h.json.encode(body) }) end
	f.onPoll = function(id) return f.running(id) end
	return f
end

case("finite companion submissions encode integer seconds after a delayed hello", function()
	local f = fixture({ legacy = true, helloDelay = 0.15 })
	check("legacy app pairs", f.scan())
	f.onPoll = function(id) return f.completed(id, { ok = true }) end
	local response, why = f.run(function()
		return f.env.require("net/http").send({ url = "https://provider.fixture/v1/chat/completions", method = "POST",
			body = "{}", relay = true, timeout = 12.75 })
	end, 3)
	check("Kotlin-compatible request reaches its result", response and response.ok and not why and f.posts == 1)
	check("finite timeout is a positive integer", f.inputs[1].timeout > 0 and f.inputs[1].timeout % 1 == 0)
	check("old companion never receives unlimited zero", f.inputs[1].timeout ~= 0 and not f.link.status().unlimited)
	f.healthy(); f.close()
end)

case("saved pairing is authenticated and repaired before inference", function()
	local f = fixture({ savedToken = ("b"):rep(64) })
	check("reinstalled companion becomes usable", f.scan() and f.link.usable())
	check("stale token is checked then replaced once", f.authChecks == 1 and f.pairs == 1 and f.config.get("relay.token") == f.token)
	check("new capability belongs to verified pairing", f.link.status().unlimited and f.env.require("net/transport").endpoint().unlimited)
	f.scan()
	check("healthy scan does not repeatedly pair", f.authChecks == 1 and f.pairs == 1 and f.posts == 0)
	f.healthy(); f.close()
end)

case("a mobile send finds an app started during the idle discovery backoff", function()
	local f = fixture(); f.available = false
	check("initial absence is observed", not f.scan())
	f.h.sched.advance(6); f.available = true
	f.onPoll = function(id) return f.completed(id, { choices = { { message = { role = "assistant", content = "connected" }, finish_reason = "stop" } } }) end
	local record = f.env.require("provider/registry").blank("custom")
	record.id, record.model, record.baseUrl, record.apiKey = "mobile", "fixture-model", "https://provider.fixture/v1", "fixture"
	local result = f.run(function() return f.env.require("provider/chat").complete(record, {
		messages = { { role = "user", content = "hello" } }, stream = false,
	}) end, 3)
	check("next send discovers and uses the companion", result and result.content == "connected" and f.posts == 1 and f.direct == 0)
	check("default policy is negotiated as unlimited", f.inputs[1].timeout == 0)
	f.healthy(); f.close()
end)

for _, lane in ipairs({ "chat", "responses", "messages", "gemini" }) do
	case(lane .. " default companion request survives 300 seconds and poll loss", function()
		local f = fixture(); check("app pairs", f.scan())
		local record = f.env.require("provider/registry").blank(lane == "responses" and "zen" or lane == "gemini" and "google" or "custom")
		record.id, record.model, record.apiKey = "mobile", lane == "responses" and "fixture-response-model" or "fixture-model", "fixture"
		if lane == "messages" then record.api = "anthropic" end
		if record.baseUrl == "" then record.baseUrl = "https://provider.fixture/v1" end
		if lane == "responses" then Z.responses(f, record) end
		f.onPoll = function(id, job)
			if f.polls == 1 then return f.running(id, 34.5) end
			if f.h.sched.now - job.at < 302 then return f.running(id) end
			local body
			if lane == "responses" then body = { object = "response", status = "completed", output = {
				{ type = "message", content = { { type = "output_text", text = "finished" } } } } }
			elseif lane == "messages" then body = { type = "message", role = "assistant", content = { { type = "text", text = "finished" } }, stop_reason = "end_turn" }
			elseif lane == "gemini" then body = { candidates = { { content = { role = "model", parts = { { text = "finished" } } }, finishReason = "STOP" } } }
			else body = { choices = { { message = { role = "assistant", content = "finished" }, finish_reason = "stop" } } } end
			return f.completed(id, body)
		end
		local result, why = f.run(function() return f.env.require("provider/chat").complete(record, {
			messages = { { role = "user", content = "hello" } }, stream = false,
		}) end, 306)
		check("one long answer survives: " .. tostring(why), result and result.content == "finished" and result.via == "relay")
		check("no second inference or direct provider fallback", f.posts == 1 and f.deletes == 0 and f.direct == 0 and f.inputs[1].timeout == 0)
		check("native exchanges remain bounded", f.maxExchange > 0 and f.maxExchange <= 5)
		check("polling does not exhaust native slots", f.env.require("net/http").workers() == 0)
		f.healthy(); f.close()
	end)
end

case("explicit companion deadlines still cancel once", function()
	local f = fixture(); check("app pairs", f.scan())
	local response, why = f.run(function() return f.env.require("net/http").send({
		url = "https://provider.fixture/v1/chat/completions", method = "POST", body = "{}", relay = true,
		timeout = 2, attempts = 5,
	}) end, 3)
	f.h.sched.advance(1)
	check("explicit deadline remains terminal", response and response.terminal and response.body:find("deadline", 1, true)
		or not response and tostring(why):find("deadline", 1, true))
	check("finite job is cancelled without resubmission", f.inputs[1].timeout > 0 and f.posts == 1 and f.deletes == 1)
	f.healthy(); f.close()
end)

for _, lane in ipairs({ "chat", "responses", "messages", "gemini" }) do
	case(lane .. " preserves an explicit absolute provider deadline", function()
		local f = fixture(); check("app pairs", f.scan())
		local record = f.env.require("provider/registry").blank(lane == "responses" and "zen" or lane == "gemini" and "google" or "custom")
		record.id, record.model, record.apiKey = "mobile", lane == "responses" and "fixture-response-model" or "fixture-model", "fixture"
		if lane == "messages" then record.api = "anthropic" end
		if record.baseUrl == "" then record.baseUrl = "https://provider.fixture/v1" end
		if lane == "responses" then Z.responses(f, record) end
		local deadline = f.env.require("runtime/clock").ms() + 1000
		local result, why = f.run(function() return f.env.require("provider/chat").complete(record, {
			messages = { { role = "user", content = "hello" } }, timeout = 100, deadlineMs = deadline,
		}) end, 2)
		check("absolute deadline ends the request", not result and tostring(why):lower():find("deadline", 1, true))
		check("provider keeps a finite job and cancels it once", f.posts == 1 and f.inputs[1].timeout > 0 and f.deletes == 1)
		f.healthy(); f.close()
	end)
end

case("a finite Responses handoff cannot become an unlimited companion request", function()
	local f = fixture(); check("app pairs", f.scan())
	local record = f.env.require("provider/registry").blank("zen")
	record.id, record.model, record.apiKey = "mobile", "muse-spark-fixture", "fixture"
	local deadline = f.env.require("runtime/clock").ms() + 1000
	local result, why = f.run(function() return f.env.require("provider/responses").complete(record, {
		messages = { { role = "user", content = "hello" } },
	}, { deadlineMs = deadline, key = "fixture" }) end, 2)
	check("handoff retains its original deadline", not result and tostring(why):lower():find("deadline", 1, true))
	check("finite handoff never negotiates zero", f.posts == 1 and f.inputs[1].timeout > 0 and f.deletes == 1)
	f.healthy(); f.close()
end)

case("single-attempt HTTP preserves default unlimited negotiation", function()
	local f = fixture(); check("app pairs", f.scan())
	local transport, decisions = f.env.require("net/transport"), {}
	local unlimited = transport.unlimited
	transport.unlimited = function(request, endpoint)
		local result = unlimited(request, endpoint)
		if #decisions < 4 then decisions[#decisions + 1] = result end
		return result
	end
	f.onPoll = function(id) return f.completed(id, { ok = true }) end
	local response = f.run(function() return f.env.require("net/http").request({
		url = "https://provider.fixture/v1/chat/completions", method = "POST", body = "{}", relay = true,
	}) end, 3)
	check("single attempt sends the negotiated policy (response=" .. tostring(response and response.ok)
		.. ", timeout=" .. tostring(f.inputs[1] and f.inputs[1].timeout) .. ", first=" .. tostring(decisions[1])
		.. ", second=" .. tostring(decisions[2]) .. ")", response and response.ok and f.inputs[1].timeout == 0)
	f.healthy(); f.close()
end)

case("Stop cancels a default unlimited companion job", function()
	local f = fixture(); check("app pairs", f.scan())
	local response, why, stopped
	f.h.sched.spawn(function() response, why = f.env.require("net/http").send({
		url = "https://provider.fixture/v1/chat/completions", method = "POST", body = "{}", relay = true,
		aborted = function() return stopped end,
	}) end)
	f.h.sched.advance(3); stopped = true; f.h.sched.advance(1)
	check("Stop settles the unlimited request", response == nil and why == "aborted" and f.inputs[1].timeout == 0)
	check("Stop reaches the original job exactly once", f.posts == 1 and f.deletes == 1)
	f.healthy(); f.close()
end)

suite.finish()
