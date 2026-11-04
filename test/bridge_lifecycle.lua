-- Focused connection, mobile discovery and relay deadline regressions.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function count(entries, predicate)
	local n = 0
	for _, entry in ipairs(entries) do if predicate(entry) then n = n + 1 end end
	return n
end
local function hello(instance)
	return { StatusCode = 200, Body = json.encode({ protocol = 2, server = "uai-relay", instance = instance or "phone-one" }) }
end
local function pair()
	return { StatusCode = 200, Body = json.encode({ ok = true, token = ("a"):rep(64), protocol = 2, instance = "phone-one" }) }
end
local function manual(app)
	app.config.set("bridge.port", 8795)
	app.config.set("bridge.token", "lifecycle-token")
	app.config.set("bridge.enabled", true)
end
local function finish(h, app)
	app.destroy(); h.settle(1)
	check("lifecycle callbacks release cleanly", #h.errors() == 0)
end

do
	local h = envMock.new()
	local available, uploads = true, 0
	h.http.handler = function(req)
		if not available then return { StatusCode = 503, Body = "{}" } end
		if req.url:find("/api/agent/inbox", 1, true) then
			return { StatusCode = 200, Body = '{"commands":[]}', delay = req.headers["X-UAI-Poll-Wait-Ms"] == "0" and 0 or 18 }
		end
		if req.url:find("/api/agent/events", 1, true) then uploads = uploads + 1; return { StatusCode = 204, Body = "" } end
		return { StatusCode = 404, Body = "{}" }
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.2)
	app.config.set("bridge.runtime", "web")
	check("offline saved/runtime writes cannot force Web", app.config.get("bridge.runtime") == "game")
	manual(app); h.settle(0.3)
	check("first authenticated upload selects Web before the long poll returns", uploads > 0 and app.bridge.online and app.config.get("bridge.runtime") == "web")
	app.config.set("bridge.runtime", "game")
	check("connected runtime stays automatic", app.config.get("bridge.runtime") == "web")
	app.bridge.stop()
	check("explicit disconnect selects Game synchronously", not app.bridge.online and app.config.get("bridge.runtime") == "game")
	available = false
	app.bridge.sync(); h.settle(1)
	check("a configured but unreachable bridge keeps Game", app.bridge.running and not app.bridge.online and app.config.get("bridge.runtime") == "game")
	available = true; h.settle(3)
	check("recovery selects Web automatically", app.bridge.online and app.config.get("bridge.runtime") == "web")
	finish(h, app)
end

do
	local h = envMock.new()
	h.services.UserInputService.TouchEnabled, h.services.UserInputService.MouseEnabled = true, false
	local probes = 0
	h.http.relay = function() probes = probes + 1; return { StatusCode = 599, Body = "{}" } end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(1)
	app.env.require("runtime/log").setLevel("debug")
	h.settle(180)
	check("absent companion discovery backs off", probes >= 3 and probes <= 4)
	check("optional mobile discovery does not repeat log entries", count(app.env.require("runtime/log").entries, function(entry) return entry.source == "relay" end) == 0)
	check("phones do not probe the Windows desktop port", count(h.http.log, function(entry) return entry.url:find("28791", 1, true) end) == 0)
	local inbox, available = 0, true
	h.http.handler = function(req)
		if not available then return { StatusCode = 503, Body = "{}" } end
		if req.url:find("/api/hello", 1, true) then
			return { StatusCode = 200, Body = json.encode({ protocol = 2, instance = "mobile-bridge", capabilities = { agentInbox = { waitHeader = "X-UAI-Poll-Wait-Ms" } } }) }
		end
		if req.url:find("/api/agent/inbox", 1, true) then
			inbox = inbox + 1
			check("mobile inbox requests the bounded one-second hold", req.headers["X-UAI-Poll-Wait-Ms"] == "1000")
			return { StatusCode = 200, Body = '{"commands":[]}', delay = 1 }
		end
		return { StatusCode = 204, Body = "" }
	end
	manual(app); h.settle(8)
	check("mobile polling stays connected without busy polling", app.bridge.online and inbox >= 6 and inbox <= 9)
	check("healthy mobile inbox stays out of requests and warnings", #app.env.require("net/http").history == 0
		and count(app.env.require("runtime/log").entries, function(entry) return entry.source == "bridge" and entry.level == "warn" end) == 0)
	available = false; h.settle(2)
	check("mobile connection loss returns new requests to Game", not app.bridge.online and app.config.get("bridge.runtime") == "game")
	finish(h, app)
end

do
	local h = envMock.new()
	local scans, delay, marker = 0, 0, true
	h.http.relay = function(req)
		if req.url:find("/api/pair", 1, true) then return pair() end
		scans = scans + 1
		local response = hello()
		if not marker then response.Body = '{"protocol":2,"instance":"pc-bridge"}' end
		response.delay = delay
		return response
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(1)
	local link = app.env.require("net/relay_link")
	check("companion initially pairs", link.usable())
	local before = scans
	delay = 0.6
	local one, two
	h.sandbox.task.spawn(function() one = link.scan() end)
	h.sandbox.task.spawn(function() two = link.scan() end)
	h.settle(0.2)
	check("a healthy companion stays usable during its probe", link.usable())
	h.settle(1)
	check("concurrent scans share one request and result", scans == before + 1 and one and two)
	check("successful health checks do not repeat connected logs", count(app.env.require("runtime/log").entries, function(entry) return entry.source == "relay" and entry.level == "info" end) == 1)
	h.http.handler = function() return { StatusCode = 503, Body = "{}" } end
	manual(app); h.settle(0.2)
	check("an unavailable manual bridge cannot steal a healthy companion route", app.env.require("net/transport").target() == "companion"
		and app.env.require("net/transport").endpoint().target == "companion")
	marker, delay = false, 0
	h.sandbox.task.spawn(function() link.scan() end); h.settle(0.2)
	check("saved credentials never bypass the companion server marker", not link.usable() and link.status().error:find("another program", 1, true))
	finish(h, app)
end

for _, pause in ipairs({ 0, 2.5 }) do
	local h = envMock.new()
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.2)
	local sends, completed, pendingAck = 0, false, false
	app.sessions.current().send = function() sends = sends + 1; h.sandbox.task.wait(2); return true end
	h.http.handler = function(req)
		if req.url:find("/api/agent/inbox", 1, true) then
			return { StatusCode = 200, Body = json.encode({ commands = pendingAck and {} or { false, 17,
				{ type = "send", text = "once", commandId = "yielding-command" } } }), delay = 0.1 }
		end
		if req.url:find("/api/agent/ack", 1, true) then
			for _, result in ipairs(json.decode(req.body).results) do
				if result.id == "yielding-command" then
					if result.pending then pendingAck = true end
					if result.ok then completed = true end
				end
			end
		end
		return { StatusCode = 204, Body = "" }
	end
	manual(app); h.settle(0.3)
	check("server collected the pending receipt before reconnect", pendingAck)
	app.bridge.stop(); h.settle(pause); app.bridge.sync(); h.settle(3)
	check("a yielded command reconnects with its original receipt and runs once", sends == 1 and completed)
	finish(h, app)
end

do
	local h = envMock.new()
	local pairing = false
	h.http.relay = function(req)
		-- Authentication settles one second of mock time before this lifecycle case.
		if req.url:find("/api/pair", 1, true) then pairing = true; local response = pair(); response.delay = 2; return response end
		return hello()
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.2)
	check("pairing is in flight", pairing)
	app.config.set("relay.mode", "off"); h.settle(2)
	check("late pairing after opt-out cannot restore credentials", app.config.get("relay.token") == "" and not app.env.require("net/relay_link").usable())
	finish(h, app)
end

do
	local h = envMock.new()
	local companion = true
	h.http.relay = function(req)
		if not companion then return { StatusCode = 599, Body = "{}" } end
		return req.url:find("/api/pair", 1, true) and pair() or hello()
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(1)
	local result, starts, polls = nil, 0, 0
	h.sandbox.task.spawn(function()
		result = app.env.require("net/relay").request({ url = "https://provider.invalid", body = "{}", timeout = 15 }, {}, function(spec)
			if spec.url:find("/api/hello", 1, true) then return { ok = true, body = '{"protocol":2,"instance":"phone-one","server":"uai-relay"}' } end
			if spec.method == "POST" then starts = starts + 1; return { ok = true, body = json.encode({ id = json.decode(spec.body).id, state = "running" }) } end
			polls = polls + 1
			return { ok = true, body = json.encode({ id = spec.url:match("/inference/(.+)$"), state = polls < 3 and "running" or "completed", status = 200, body = "kept job" }) }
		end)
	end)
	h.settle(0.2); companion = false
	h.sandbox.task.spawn(function() app.env.require("net/relay_link").scan() end); h.settle(0.2)
	check("health loss sends future requests directly", not app.env.require("net/relay_link").usable() and app.env.require("net/transport").target() == nil)
	h.settle(5)
	check("an accepted relay job survives health loss on its pinned endpoint", result and result.body == "kept job" and starts == 1)
	finish(h, app)
end

do
	local h = envMock.new()
	h.http.relay = function(req) return req.url:find("/api/pair", 1, true) and pair() or hello() end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(1)
	local submissions, deletes, upstreamTimeout = 0, 0, nil
	h.http.relay = function(req)
		if req.url:find("/api/hello", 1, true) then return hello() end
		if req.method == "DELETE" then deletes = deletes + 1; return { StatusCode = 200, Body = '{}' } end
		if req.method == "POST" then
			submissions = submissions + 1
			local body = json.decode(req.body); upstreamTimeout = body.timeout
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		return { StatusCode = 200, Body = json.encode({ id = req.url:match("/inference/(.+)$"), state = "running" }), delay = 20 }
	end
	local response, err, completedAt
	local clock = app.env.require("runtime/clock")
	local startedAt = clock.ms()
	h.sandbox.task.spawn(function()
		response, err = app.env.require("net/http").send({ url = "https://provider.invalid", method = "POST", body = "{}", relay = true,
			timeout = 120, deadlineMs = clock.ms() + 2000, attempts = 5 })
		completedAt = clock.ms()
	end)
	h.settle(4)
	local deadlineFailure = response and response.terminal and response.body:find("deadline", 1, true)
		or response == nil and tostring(err):find("deadline", 1, true)
	check("companion respects its finite original deadline", deadlineFailure and upstreamTimeout <= 2 and completedAt - startedAt <= 2100)
	check("deadline cancels once without a second inference", submissions == 1 and deletes == 1)
	h.settle(21)
	check("late native completion cannot restart a cancelled relay", submissions == 1 and deletes == 1)
	finish(h, app)
end

do
	-- Cowork owns long requests indefinitely. Even a 34.5-second native poll
	-- failure cannot turn the outer inference into a provider deadline/retry.
	local h = envMock.new()
	local originalRequest = h.sandbox.request
	local maxExchangeTimeout = 0
	h.sandbox.request = function(options)
		if options.Url:find("/api/inference", 1, true) then maxExchangeTimeout = math.max(maxExchangeTimeout, options.Timeout or 0) end
		return originalRequest(options)
	end
	local ready, starts, polls, deletes = false, 0, 0, 0
	h.http.handler = function(req)
		if req.url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}', delay = 18 } end
		if req.url:find("/api/agent/", 1, true) then return { StatusCode = 204, Body = "" } end
		if req.url:find("/api/hello", 1, true) then return { StatusCode = 200, Body = '{"protocol":2,"instance":"unlimited-bridge"}' } end
		if req.method == "DELETE" then deletes = deletes + 1; return { StatusCode = 200, Body = "{}" } end
		if req.method == "POST" then
			starts = starts + 1
			local body = json.decode(req.body)
			local timeoutHeader = false
			for name in pairs(body.headers or {}) do if name:lower() == "x-stainless-timeout" then timeoutHeader = true end end
			check("Cowork does not send a configurable provider timeout", body.timeout == nil and body.unlimited == nil and not timeoutHeader)
			return { StatusCode = 202, Body = json.encode({ id = body.id, state = "running" }) }
		end
		polls = polls + 1
		return { StatusCode = 200, Body = json.encode({ id = req.url:match("/inference/(.+)$"), state = ready and "completed" or "running", status = 200, body = "long answer" }),
			delay = polls == 1 and 34.5 or 0 }
	end
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.2); manual(app); h.settle(0.3)
	local response, err, aborted
	local clock = app.env.require("runtime/clock")
	local function request()
		response, err = app.env.require("net/http").send({ url = "https://provider.invalid", method = "POST", body = "{}", relay = true,
			timeout = 34.5, deadlineMs = clock.ms() + 34500, attempts = 5, aborted = function() return aborted end })
	end
	h.sandbox.task.spawn(request); h.settle(40)
	check("a native 34.5-second poll failure does not end Cowork inference", response == nil and err == nil and starts == 1 and deletes == 0)
	h.settle(280)
	check("Cowork also survives the former 300-second outer limit", response == nil and err == nil and starts == 1)
	ready = true; h.settle(2)
	check("the original unlimited request eventually returns its answer", response and response.body == "long answer" and response.ok and not err and starts == 1)
	check("unlimited Cowork still bounds every native exchange", maxExchangeTimeout > 0 and maxExchangeTimeout <= 5)
	ready, response, err = false, nil, nil
	h.sandbox.task.spawn(request); h.settle(1)
	aborted = true; h.settle(1)
	check("Stop cancels unlimited Cowork once without resubmitting", response == nil and err == "aborted" and starts == 2 and deletes == 1)
	finish(h, app)
end

print(string.format("%d bridge lifecycle checks passed", passed))
