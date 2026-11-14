-- The mobile companion relay: pairing, routing, fallback and terminal semantics.
-- A scripted loopback companion stands in for the Android app; no device is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local F = require("workspace_fixture")
local desktop = require("automatic_bridge_fixture")
local passed = 0
local function check(label, value, expected)
	if expected ~= nil then assert(value == expected, label .. ": " .. tostring(value) .. " ~= " .. tostring(expected))
	else assert(value, label) end
	passed = passed + 1; print("ok " .. label)
end
local function completion(text)
	return json.encode({ id = "cmpl_relay", model = "harness-model",
		choices = { { index = 0, message = { role = "assistant", content = text }, finish_reason = "stop" } },
		usage = { prompt_tokens = 5, completion_tokens = 2, total_tokens = 7 } })
end
local function hello(instance)
	return { StatusCode = 200, Body = json.encode({ ok = true, protocol = 2, instance = instance, server = "uai-relay" }) }
end
local function paired(token, instance)
	return { StatusCode = 200, Body = json.encode({ ok = true, token = token, instance = instance, protocol = 2 }) }
end
local function setup(handlers)
	handlers = handlers or {}
	local h = envMock.new()
	h.http.relay = handlers.relay
	h.http.handler = handlers.handler
	local app = assert(h.boot()); require("password_fixture")(h, app)
	h.settle(1)
	local record = app.providers.blank("custom")
	record.label, record.baseUrl, record.apiKey = "Relay", "https://relay.test/v1", "sk-relay-key"
	record.model, record.models = "harness-model", { "harness-model" }
	assert(app.providers.save(record), "provider rejected")
	assert(app.providers.setActive(record.id), "fixture provider was not selected")
	h.settle(1)
	return h, app
end
local function last(session)
	return session.ctx.messages[#session.ctx.messages]
end
local function count(log, needle)
	local n = 0
	for _, entry in ipairs(log) do if tostring(entry.url):find(needle, 1, true) then n = n + 1 end end
	return n
end

do
	-- Companion scripted: hello, pair, then one inference that completes.
	local submissions, relayed, deletes = {}, 0, 0
	local function relay(req)
		if req.url:find("/api/hello", 1, true) then return hello("inst-one") end
		if req.url:find("/api/pair", 1, true) then return paired(("a"):rep(64), "inst-one") end
		if req.url:find("/api/inference/", 1, true) then
			if req.method == "DELETE" then deletes = deletes + 1; return { StatusCode = 200, Body = '{"cancelled":true}' } end
			local id = req.url:match("/api/inference/(.+)$")
			return { StatusCode = 200, Body = json.encode({ id = id, state = "completed", status = 200,
				headers = { ["content-type"] = "application/json" }, body = completion("Relayed answer.") }) }
		end
		if req.url:find("/api/inference", 1, true) then
			local body = json.decode(req.body)
			submissions[#submissions + 1] = body
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		relayed = relayed + 1
		return { StatusCode = 404, Body = "{}" }
	end
	local h, app = setup({ relay = relay })
	local relayLink = app.env.require("net/relay_link")
	check("companion paired at boot", relayLink.usable())
	check("pairing never introduces retired desktop settings", app.config.get("bridge.token") == nil and app.config.get("bridge.enabled") == nil)
	check("the token lives on the relay block only", app.config.get("relay.token") == ("a"):rep(64) and app.config.get("relay.server") == "uai-relay")
	local session = app.sessions.current()
	session.send("hello")
	h.settle(8)
	check("the relayed answer completed the turn", last(session).content, "Relayed answer.")
	check("submitted exactly once", #submissions, 1)
	check("the provider request travelled whole", submissions[1].url == "https://relay.test/v1/chat/completions"
		and submissions[1].headers.Authorization == "Bearer sk-relay-key" and submissions[1].instance == "inst-one")
	check("the executor never called the provider", count(h.http.log, "relay.test") == 0)
	local label
	for _, entry in ipairs(app.env.require("net/http").history) do if entry.via == "relay" then label = entry.via end end
	check("history labels the companion transport", label == "relay")
	check("no thread errors", #h.errors() == 0, h.errors()[1] and h.errors()[1].traceback or nil)
	app.destroy()
end

do
	-- No companion: the request falls through to the executor, and the probe stays silent.
	local direct = 0
	local function handler(req)
		if req.url:find("/chat/completions", 1, true) then
			direct = direct + 1
			return { StatusCode = 200, Body = completion("Direct answer.") }
		end
		return { StatusCode = 404, Body = "{}" }
	end
	local h, app = setup({ handler = handler })
	check("no companion means no relay", not app.env.require("net/relay_link").usable())
	check("the transport target falls through", app.env.require("net/transport").target() == nil)
	local session = app.sessions.current()
	session.send("hello")
	h.settle(6)
	check("the executor called the provider directly", direct, 1)
	check("and the reply arrived", last(session).content, "Direct answer.")
	check("probes stay out of the request history", count(app.env.require("net/http").history, "/api/hello") == 0)
	check("no thread errors", #h.errors() == 0, h.errors()[1] and h.errors()[1].traceback or nil)
	app.destroy()
end

do
	-- Opting out stops the probe and the relay entirely.
	local h, app = setup({})
	h.settle(0.5)
	app.config.set("relay.mode", "off")
	h.settle(0.5)
	local before = count(h.http.log, "/api/hello")
	h.settle(40)
	check("off mode stops probing", count(h.http.log, "/api/hello") == before)
	check("and the relay is not usable", not app.env.require("net/relay_link").usable())
	app.destroy()
end

do
	-- A vanished job answers 404: terminal, one submission, never resubmitted.
	local submissions, polls = 0, 0
	local function relay(req)
		if req.url:find("/api/hello", 1, true) then return hello("inst-two") end
		if req.url:find("/api/pair", 1, true) then return paired(("b"):rep(64), "inst-two") end
		if req.url:find("/api/inference/", 1, true) then
			if req.method == "DELETE" then return { StatusCode = 200, Body = '{"cancelled":true}' } end
			polls = polls + 1
			return { StatusCode = 404, Body = '{"error":"Unknown inference ID; do not resubmit"}' }
		end
		if req.url:find("/api/inference", 1, true) then
			submissions = submissions + 1
			local body = json.decode(req.body)
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		return { StatusCode = 404, Body = "{}" }
	end
	local h, app = setup({ relay = relay })
	local session = app.sessions.current()
	local reported
	session.events:connect(function(event) if event.kind == "error" then reported = event.message end end)
	session.send("hello")
	h.settle(8)
	check("the unknown id was submitted once", submissions, 1)
	check("and polled", polls > 0)
	check("the failure was terminal", reported ~= nil and not session.busy)
	check("the executor never called the provider", count(h.http.log, "relay.test") == 0)
	app.destroy()
end

do
	-- Capacity pressure is a 503: the client retries the same id, never a second job.
	local submissions = 0
	local function relay(req)
		if req.url:find("/api/hello", 1, true) then return hello("inst-three") end
		if req.url:find("/api/pair", 1, true) then return paired(("c"):rep(64), "inst-three") end
		if req.url:find("/api/inference/", 1, true) then
			if req.method == "DELETE" then return { StatusCode = 200, Body = '{"cancelled":true}' } end
			local id = req.url:match("/api/inference/(.+)$")
			return { StatusCode = 200, Body = json.encode({ id = id, state = "completed", status = 200,
				headers = { ["content-type"] = "application/json" }, body = completion("Recovered after busy.") }) }
		end
		if req.url:find("/api/inference", 1, true) then
			submissions = submissions + 1
			if submissions <= 2 then return { StatusCode = 503, Body = '{"error":"at capacity"}' } end
			local body = json.decode(req.body)
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		return { StatusCode = 404, Body = "{}" }
	end
	local h, app = setup({ relay = relay })
	local session = app.sessions.current()
	session.send("hello")
	h.settle(8)
	check("the busy relay was retried with the same subject", submissions, 3)
	check("and the answer landed", last(session).content, "Recovered after busy.")
	app.destroy()
end

do
	-- A connected desktop Cowork route takes precedence over a paired companion.
	local companionInference = 0
	local function relay(req)
		if req.url:find("/api/hello", 1, true) then return hello("inst-four") end
		if req.url:find("/api/pair", 1, true) then return paired(("d"):rep(64), "inst-four") end
		companionInference = companionInference + 1
		return { StatusCode = 500, Body = "{}" }
	end
	local cowork = {}
	local function handler(req)
		local url = tostring(req.url)
		if not url:find(":28791/", 1, true) then return { StatusCode = 404, Body = "{}" } end
		if url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}', delay = 1 } end
		if url:find("/api/agent/", 1, true) then return { StatusCode = 204, Body = "" } end
		if url:find("/api/hello", 1, true) then return { StatusCode = 200, Body = '{"protocol":2,"instance":"bridge-one"}' } end
		if req.method == "POST" then
			local body = json.decode(req.body)
			cowork[#cowork + 1] = body
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		local id = url:match("/api/inference/(.+)$")
		return { StatusCode = 200, Body = json.encode({ id = id, state = "completed", status = 200,
			headers = { ["content-type"] = "application/json" }, body = completion("Cowork answer.") }) }
	end
	local h, app = setup({ relay = relay, handler = handler })
	desktop.connect(h, app, { instance = "bridge-one" })
	h.settle(2)
	check("the companion is still paired", app.env.require("net/relay_link").usable())
	check("connected Cowork wins over the companion", app.env.require("net/transport").target() == "cowork")
	local session = app.sessions.current()
	session.send("hello")
	h.settle(8)
	check("the request used the Cowork link", #cowork, 1)
	check("the companion was not asked to infer", companionInference, 0)
	check("and the answer landed", last(session).content, "Cowork answer.")
	app.destroy()
end

-- Source modules cover the dispatch decision before the generated client builds.
local function sourceRelay(mode)
	local f = F.new()
	f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
	f.available, f.stuckHello, f.direct, f.submissions = false, false, 0, 0
	f.token, f.instance = ("a"):rep(64), "required-relay-fixture"
	f.h.http.handler = function()
		f.direct = f.direct + 1
		return { StatusCode = 200, Body = completion("Direct fixture answer.") }
	end
	f.h.http.relay = function(request)
		if not f.available then return { StatusCode = 503, Body = '{"error":"app stopped"}' } end
		if request.url:find("/api/hello", 1, true) then
			local response = hello(f.instance)
			if f.stuckHello then response.delay = 9 end
			return response
		end
		if request.url:find("/api/pair", 1, true) then return paired(f.token, f.instance) end
		if request.method == "DELETE" then return { StatusCode = 200, Body = '{"cancelled":true}' } end
		if request.method == "POST" then
			f.submissions = f.submissions + 1
			local input = json.decode(request.body)
			return { StatusCode = 202, Body = json.encode({ id = input.id, state = "running" }) }
		end
		local id = request.url:match("/api/inference/(.+)$")
		return { StatusCode = 200, Body = json.encode({ id = id, state = "completed", status = 200,
			body = completion("Required relay answer.") }) }
	end
	f.env.require("runtime/config").set("relay.mode", mode)
	f.link = f.env.require("net/relay_link")
	local record = f.env.require("provider/registry").blank("custom")
	record.id, record.model, record.baseUrl, record.apiKey = "required-relay", "harness-model", "https://relay.test/v1", "fixture-key"
	function f.send()
		return f.run(function()
			return f.env.require("provider/chat").complete(record, {
				messages = { { role = "user", content = "hello" } }, stream = false,
			})
		end, 3)
	end
	return f
end

do
	local f = sourceRelay("always")
	local response, why = f.send()
	check("Always mode fails visibly when the companion is absent", not response and why and why:find("local relay", 1, true))
	check("Always mode never opens a direct provider request while discovery fails", f.direct == 0 and f.submissions == 0)
	f.healthy(); f.close()
end

do
	local f = sourceRelay("auto")
	local response, why = f.send()
	check("Auto mode preserves direct fallback when the companion is absent", response and response.content == "Direct fixture answer." and not why)
	check("Auto fallback dispatches the provider once", f.direct == 1 and f.submissions == 0)
	f.healthy(); f.close()
end

do
	local f = sourceRelay("always")
	f.available = true
	check("Always mode pairs with a healthy companion", f.run(f.link.scan, 1) and f.link.usable())
	f.stuckHello = true
	local healthy = f.run(f.link.probe, 5.2)
	check("a timed-out health check removes readiness while retaining native ownership", not healthy and not f.link.usable() and f.env.require("net/http").workers() == 1)
	local response, why = f.send()
	check("Always mode remains terminal through a failed health check", not response and why and f.direct == 0 and f.submissions == 0)
	f.stuckHello = false
	f.h.sched.advance(4)
	check("the delayed health completion cannot restore readiness", not f.link.usable() and f.env.require("net/http").workers() == 0)
	check("a fresh scan restores the same companion", f.run(f.link.scan, 1) and f.link.usable())
	response, why = f.send()
	check("Always mode resumes relayed inference after recovery", response and response.content == "Required relay answer." and not why and f.submissions == 1 and f.direct == 0)
	f.healthy(); f.close()
end

print(string.format("%d mobile relay checks passed", passed))
