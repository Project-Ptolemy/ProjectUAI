-- Exercise actual admission paths under a synthetic setup/unlock policy.
-- Password derivation, bootstrap policy and storage are covered separately.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Credential vault admission")
local case, check = suite.case, suite.check
local MESSAGE = "Enter the master password before using UAI."
local function fixture()
	local f = F.new(); f.tools({})
	f.config = f.env.require("runtime/config")
	f.config.set("agent.fallback", false)
	f.config.set("agent.compaction", false)
	f.providers = f.env.require("provider/registry")
	f.record = f.providers.blank("custom")
	f.record.baseUrl, f.record.model, f.record.models = "https://admission.fixture/v1", "fixture-model", { "fixture-model" }
	f.record.authStyle, f.record.apiKey = "none", ""
	assert(f.providers.save(f.record)); assert(f.providers.setActive(f.record.id))
	f.sessions = f.env.require("agent/session")
	f.session = assert(f.sessions.newThread({ id = "admission-fixture", ephemeral = true }))
	f.config.accessProblem = function() return f.denied and MESSAGE or nil end
	return f
end
local function call(f, name)
	return f.registry.dispatch({ id = "fixture-call", name = name, arguments = "{}" }, f.session.toolContext())
end

case("free, anonymous and private providers cannot bypass password admission", function()
	local f = fixture()
	local free = f.providers.blank("projectuai-free")
	local private = f.providers.blank("custom")
	private.baseUrl, private.model, private.apiKey = "https://private.fixture/v1", "fixture-model", "synthetic-private-key"
	f.denied = true
	for _, record in ipairs({ f.record, free, private }) do
		local reply, why = f.run(function()
			return f.env.require("provider/chat").complete(record, { messages = { { role = "user", content = "hello" } }, attempts = 1 })
		end)
		check("every inference route requires access before dispatch", reply == nil and why:find(MESSAGE, 1, true))
		local models, note = f.run(function() return f.env.require("provider/models").discover(record, { force = true }) end)
		check("model discovery requires the same access", #models == 0 and note:find(MESSAGE, 1, true))
	end
	local route = f.env.require("provider/free_route")
	route.refresh(free); f.h.sched.advance(0.2)
	check("included free probes remain unavailable", not route.eligible(free) and not route.status(free).available)
	check("refused admissions send no HTTP requests", f.h.http.requestCount == 0)
	local original = f.record.model
	check("gated model and provider edits cannot mutate live records", not f.providers.setModel(f.record.id, "blocked-model")
		and not f.providers.remove(f.record.id) and f.record.model == original and f.providers.get(f.record.id) == f.record)
	check("Free provisioning cannot create or select an unsaved provider", not f.env.require("provider/free").use()
		and f.env.require("provider/free").ensure() == f.record and #f.providers.list() == 1)
	f.healthy(); f.close()
end)

case("every adapter refuses another native request after a challenged refusal", function()
	for _, adapter in ipairs({ "openai", "anthropic", "responses", "gemini" }) do
		local f = fixture()
		f.record.authStyle, f.record.apiKey = "bearer", "synthetic-first-key"
		f.record.apiKeys = { "synthetic-first-key", "synthetic-second-key" }
		f.record.api = adapter == "anthropic" and "anthropic" or adapter == "gemini" and "gemini" or "openai"
		f.h.http.handler = function()
			f.denied = true
			return { StatusCode = 429, Body = '{"error":{"message":"rate limited"}}' }
		end
		local reply, why = f.run(function()
			return f.env.require("provider/" .. adapter).complete(f.record,
				{ messages = { { role = "user", content = "hello" } }, attempts = 2 })
		end, 2)
		check(adapter .. " blocks retry and key fallback", not reply and tostring(why):find(MESSAGE, 1, true)
			and f.h.http.requestCount == 1)
		f.healthy(); f.close()
	end
end)

case("accepted native inference finishes but later model pages stay gated", function()
	local f = fixture()
	f.h.http.handler = function()
		f.h.sched.wait(0.2)
		return { StatusCode = 200, Body = '{"choices":[{"message":{"content":"accepted"},"finish_reason":"stop"}]}' }
	end
	f.h.sched.delay(0.05, function() f.denied = true end)
	local reply = f.run(function()
		return f.env.require("provider/chat").complete(f.record, { messages = { { role = "user", content = "hello" } }, attempts = 1 })
	end, 1)
	check("accepted HTTP completion remains observable", reply and reply.content == "accepted" and f.h.http.requestCount == 1)
	f.denied = false; f.record.api = "gemini"
	f.h.http.handler = function()
		f.denied = true
		return { StatusCode = 200, Body = '{"models":[{"name":"models/first","supportedGenerationMethods":["generateContent"]}],"nextPageToken":"next"}' }
	end
	local found = f.run(function() return f.env.require("provider/models").discover(f.record, { force = true }) end, 1)
	check("the next authenticated catalog page is not dispatched", #found == 0 and f.h.http.requestCount == 2)
	f.healthy(); f.close()
end)

case("socket setup rechecks admission but an accepted stream keeps its completion", function()
	for _, beforeSend in ipairs({ true, false }) do
		local f = fixture(); local sends, closes = 0, 0
		local signal = require("instance").newSignal
		local socket = { OnMessage = signal("gate message"), OnClose = signal("gate close") }
		function socket:Close() closes = closes + 1; self.OnClose:Fire() end
		function socket:Send()
			sends = sends + 1; f.denied = true; f.h.sched.wait(0.1)
			self.OnMessage:Fire('{"choices":[{"delta":{"content":"accepted"},"finish_reason":"stop"}]}')
			self.OnMessage:Fire("[DONE]")
		end
		local caps = f.env.require("runtime/caps")
		caps.ws, caps.fn.websocket = true, function()
			if beforeSend then f.h.sched.wait(0.05); f.denied = true end
			return socket
		end
		local body, why = f.run(function() return f.env.require("net/ws").stream({ url = "wss://admission.fixture/stream", timeout = 1 }) end, 1)
		if beforeSend then check("challenge during connect prevents Send", not body and tostring(why):find(MESSAGE, 1, true) and sends == 0)
		else check("an accepted stream can deliver its final reply", body and f.env.require("net/sse").parse(body).content == "accepted" and sends == 1) end
		check("both socket paths release their connection", closes == 1 and f.env.require("net/ws").state().connections == 0)
		f.healthy(); f.close()
	end
end)

case("native slot waiting rechecks admission before any dispatch", function()
	local f = fixture(); local http = f.env.require("net/http")
	local owner = { pending = {} }
	f.h.sched.delay(0.05, function() f.denied = true end)
	local result, why, _, kind = f.run(function()
		return http.request({ url = "https://admission.fixture/v1/models", requiresAccess = true,
			nativeOwner = owner, timeout = 1, identity = "none" })
	end, 1)
	check("a queued native request fails without opening a connection", not result and tostring(why):find(MESSAGE, 1, true)
		and kind == "terminal" and http.terminal(why) and f.h.http.requestCount == 0 and http.workers() == 0)
	f.healthy(); f.close()
end)

case("relay checks first admission and retains receipt recovery after dispatch", function()
	for _, beforeSubmit in ipairs({ true, false }) do
		local f = fixture()
		f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
		local submissions, polls, id, testing = 0, 0, nil, false
		local function reply(value, status) return { StatusCode = status or 200, Body = f.h.json.encode(value) } end
		f.h.http.relay = function(request)
			if request.url:find("/api/hello", 1, true) then
				if testing and beforeSubmit then f.denied = true end
				return reply({ ok = true, server = "uai-relay", protocol = 2, instance = "admission-relay" })
			end
			if request.url:find("/api/pair", 1, true) then return reply({ ok = true, protocol = 2, instance = "admission-relay", token = string.rep("a", 64) }) end
			if request.method == "POST" then
				submissions = submissions + 1
				local input = f.h.json.decode(request.body)
				if id then check("recovery keeps its accepted job identity", input.id == id) else id = input.id end
				f.denied = true
				if submissions == 1 then return reply({ error = "temporary receipt failure" }, 500) end
				return reply({ id = id, state = "running" }, 202)
			end
			polls = polls + 1
			return reply({ id = id, state = "completed", status = 200, body = '{"choices":[{"message":{"content":"relay accepted"},"finish_reason":"stop"}]}' })
		end
		assert(f.run(f.env.require("net/relay_link").scan, 1)); testing = true
		local result = f.run(function()
			return f.env.require("provider/chat").complete(f.record, { messages = { { role = "user", content = "hello" } }, attempts = 1 })
		end, 5)
		if beforeSubmit then check("challenge after hello blocks the first inference POST", not result and submissions == 0)
		else check("accepted relay reply survives challenge and receipt recovery", result and result.content == "relay accepted" and submissions == 2 and polls == 1) end
		f.healthy(); f.close()
	end
end)

case("bridge and companion discovery cannot start before password admission", function()
	local f = fixture(); f.denied = true
	local bridge = f.env.require("net/bridge")
	local relay = f.env.require("net/relay_link")
	f.env.require("net/bridge_connection").startDiscovery()
	check("bridge sync and direct start both refuse", not bridge.sync() and not bridge.start())
	relay.ensure(); check("explicit companion probe refuses", not f.run(relay.probe))
	f.h.sched.advance(1)
	check("discovery sends no requests while gated", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("session entry refuses work and retains previously queued messages across relock", function()
	local f = fixture(); local requests = 0
	f.loaded["provider/chat"] = { contextOverflow = function() return false end, complete = function()
		requests = requests + 1; f.h.sched.wait(0.2)
		return { content = "Accepted reply", reasoning = "", toolCalls = {}, finish = "stop" }
	end }
	f.denied = true
	local accepted, why = f.session.send("blocked input")
	check("direct sends refuse before reserving input", not accepted and why == MESSAGE and f.session.queueSnapshot().count == 0)
	check("resume and compaction cannot start alternate inference", not f.session.resumeQueue() and not f.session.compact())
	f.denied = false
	assert(f.session.send("original")); assert(f.session.send("queued follow-up"))
	f.denied = true; f.h.sched.advance(1)
	check("the accepted reply can finish without consuming a follow-up", requests == 1 and not f.session.busy
		and f.session.queueSnapshot().count == 1 and f.session.queueSnapshot().held)
	check("locked resume retains the queued message", not f.session.resumeQueue() and f.session.queueSnapshot().items[1].text == "queued follow-up")
	f.denied = false; assert(f.session.resumeQueue()); f.h.sched.advance(1)
	check("explicit resume after unlock runs the preserved follow-up", requests == 2 and f.session.queueSnapshot().count == 0)
	f.healthy(); f.close()
end)

case("direct tool dispatch rechecks admission after a pending permission", function()
	local f = fixture(); local effects, result = 0, nil
	assert(f.registry.register({ name = "admission_write", risk = "write", parameters = { type = "object", properties = {} },
		run = function() effects = effects + 1; return "completed" end }))
	f.denied = true
	local denied = f.run(function() return call(f, "admission_write") end)
	check("direct dispatch cannot bypass the password", not denied.ok and denied.error == "vault required" and effects == 0)
	f.denied = false
	local permissions = f.env.require("agent/permissions"); permissions.setMode("ask")
	f.h.sched.spawn(function() result = call(f, "admission_write") end); f.h.sched.advance(0.1)
	local _, pending = next(permissions.pending)
	check("the normal permission path is awaiting a decision", pending ~= nil and result == nil)
	f.denied = true; pending.resolve(true, false); f.h.sched.advance(0.2)
	check("permission approval cannot revive work after relock", result and not result.ok and result.error == "vault required" and effects == 0)
	f.healthy(); f.close()
end)

case("already accepted native tool completion remains observable after relock", function()
	local f = fixture(); local result, started, retained = nil, false, false
	assert(f.registry.register({ name = "admission_native", risk = "read", parameters = { type = "object", properties = {} },
		run = function(_, context)
			started = true; f.h.sched.wait(0.2); retained = not context.aborted(); return "native completed"
		end }))
	f.h.sched.spawn(function() result = call(f, "admission_native") end); f.h.sched.advance(0.05)
	check("native work was admitted before relock", started and result == nil)
	f.denied = true; f.h.sched.advance(0.3)
	check("relock does not discard accepted native completion", result and result.ok and retained and result.text:find("native completed", 1, true))
	f.healthy(); f.close()
end)

case("MCP and browser commands refuse new work while cancellation remains available", function()
	local f = fixture(); local effects = 0
	assert(f.registry.register({ name = "admission_remote", risk = "read", run = function() effects = effects + 1; return "remote completed" end }))
	local mcp = f.env.require("net/mcp")
	local count = #f.sessions.list()
	f.denied = true
	local reply = mcp.run({ type = "mcp:call", mcpSessionId = "locked-owner", callId = "locked-call", name = "admission_remote", arguments = {} })
	check("MCP refuses before creating a conversation or running a tool", not reply.ok and reply.error == "vault required"
		and effects == 0 and #f.sessions.list() == count)
	check("MCP cancellation and close remain usable", mcp.run({ type = "mcp:cancel", mcpSessionId = "locked-owner", callId = "locked-call" }).cancelled
		and mcp.run({ type = "mcp:close", mcpSessionId = "locked-owner" }).closed)
	local previous = f.config.get("agent.temperature")
	local ok, why = pcall(f.env.require("net/bridge_commands").run, { type = "setting", path = "agent.temperature", value = previous == 0.7 and 0.8 or 0.7 })
	check("browser settings cannot bypass the gate", not ok and why:find(MESSAGE, 1, true) and f.config.get("agent.temperature") == previous)
	f.healthy(); f.close()
end)

suite.finish()
