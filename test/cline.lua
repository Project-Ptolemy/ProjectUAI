-- Cline virtual routes must stay on their authenticated desktop owner.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local desktop = require("automatic_bridge_fixture")
local suite = F.suite("Cline desktop route")
local case, check = suite.case, suite.check
local URL = "https://uai-tunnel.invalid/cline/v1/chat/completions"

local function fixture(options)
	options = options or {}
	local f = F.new()
	f.config = f.env.require("runtime/config")
	f.config.set("bridge.autoDiscover", false)
	f.state, f.instance, f.modelDelay = options.state or "ready", "cline-worker-a", 0
	f.sent, f.cancelled, f.catalogCalls, f.nativeTargets, f.virtualCalls = {}, 0, 0, {}, 0
	f.h.http.handler = function(req)
		f.nativeTargets[#f.nativeTargets + 1] = req.url
		if req.url:find("uai-tunnel.invalid", 1, true) then f.virtualCalls = f.virtualCalls + 1 end
		if req.url:find("/api/hello", 1, true) then return { StatusCode = 200, Body = f.h.json.encode({
			protocol = 2, instance = f.instance, capabilities = { cline = not options.legacy and {
				schema = 1, enabled = f.state ~= "disabled", available = f.state == "ready", state = f.state,
				message = f.state == "auth-required" and "Sign in to Cline in Tunnels." or "Cline fixture status", version = "fixture-cli",
			} or nil },
		}) } end
		if req.url:find("/api/tunnels/cline/models", 1, true) then
			f.catalogCalls = f.catalogCalls + 1
			check("catalog is authenticated only to the selected desktop", req.headers.Authorization == "Bearer " .. f.desktop.token and req.url:find(":28791/", 1, true))
			return { StatusCode = 200, Body = '{"data":[{"id":"fixture-model","vision":false,"modalities":{"input":["text"],"output":["text"]}}]}', delay = f.modelDelay }
		end
		if req.url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}' } end
		if req.url:match("/api/inference$") and req.method == "POST" then
			f.sent[#f.sent + 1] = { body = f.h.json.decode(req.body), url = req.url, headers = req.headers }
			return { StatusCode = 202, Body = f.h.json.encode({ id = f.sent[#f.sent].body.id, state = "running" }) }
		end
		local id = req.url:match("/api/inference/([^?]+)")
		if id then
			if req.method == "DELETE" then f.cancelled = f.cancelled + 1; return { StatusCode = 200, Body = '{"cancelled":true}' } end
			return { StatusCode = 200, Body = f.h.json.encode({ id = id, state = f.keepRunning and "running" or "completed",
				status = 200, headers = {}, body = '{"choices":[{"message":{"content":"Fixture reply"},"finish_reason":"stop"}]}' }) }
		end
		return { StatusCode = 204, Body = "" }
	end
	f.bridge = f.env.require("net/bridge")
	f.http, f.models, f.registry = f.env.require("net/http"), f.env.require("provider/models"), f.env.require("provider/registry")
	f.record = f.registry.blank("cline")
	f.record.model = "fixture-model"
	if options.connect ~= false then
		f.desktop = desktop.connect(f.h, f, { instance = f.instance })
	end
	function f.finish() f.healthy(); f.close() end
	return f
end

case("offline Cline rejects native and Android dispatch without retries", function()
	local f = fixture({ connect = false })
	f.h.services.UserInputService.TouchEnabled = true
	f.h.services.UserInputService.MouseEnabled = false
	local before = #f.nativeTargets
	local result = f.run(function() return f.http.send({ url = URL, method = "POST", body = "{}", attempts = 4,
		relay = true, relayEndpoint = { target = "companion", base = "http://127.0.0.1:8790", token = "phone-token", unlimited = true } }) end)
	check("unavailable desktop is terminal", result and result.terminal and result.status == 599 and not f.http.shouldRetry(result))
	check("nothing reaches either native target", #f.nativeTargets == before and #f.sent == 0)
	local models, why = f.run(function() return f.models.discover(f.record) end)
	check("model discovery also fails locally", #models == 0 and why:find("UAI Bridge", 1, true) and #f.nativeTargets == before)
	f.finish()
end)

case("virtual route restrictions reject unsupported requests before transport", function()
	local f = fixture()
	for _, change in ipairs({
		{ url = "http://uai-tunnel.invalid/cline/v1/chat/completions" },
		{ url = URL .. "?private=yes" }, { url = URL .. "#fragment" },
		{ url = " " .. URL }, { url = "https://uai-tunnel.invalid./cline/v1/chat/completions" },
		{ url = "https://user@uai-tunnel.invalid/cline/v1/chat/completions" },
		{ url = "https://uai-tunnel.invalid:invalid/cline/v1/chat/completions" },
		{ url = "https://uai-tunnel.invalid/cline/v1/responses" },
		{ method = "GET" }, { headers = { Authorization = "Bearer fixture-secret" } },
		{ headers = { ["X-API-Key"] = "fixture-secret" } },
	}) do
		local spec = { url = URL, method = "POST", body = "{}", attempts = 4 }
		for key, value in pairs(change) do spec[key] = value end
		local result = f.run(function() return f.http.send(spec) end)
		check("invalid virtual request is terminal before native HTTP", result and result.terminal and f.virtualCalls == 0 and #f.sent == 0)
	end
	f.record.wsUrl = "wss://fixture.invalid"
	check("provider validation prevents socket escape", f.registry.protocolProblem(f.record):find("custom sockets", 1, true))
	f.finish()
end)

case("catalog refresh permits signing in and never invents free models", function()
	local f = fixture({ state = "auth-required" })
	local models, why = f.run(function() return f.models.discover(f.record) end)
	check("auth-required status still allows explicit catalog refresh", #models == 1 and models[1] == "fixture-model" and f.catalogCalls == 1)
	check("status explains sign-in without exposing credentials", f.bridge.status().cline.state == "auth-required" and f.bridge.clineStatus().message:find("Sign in", 1, true))
	f.state = "ready"; f.h.settle(5)
	models = f.run(function() return f.models.discover(f.record, { force = true }) end)
	check("only authenticated discovered IDs are labelled free", f.models.isFree(f.record, "fixture-model") and not f.models.isFree(f.record, "invented:free"))
	local copies = f.bridge.clineStatus(); copies.available = false
	check("presentation receives detached capabilities", f.bridge.clineStatus().available)
	f.instance = "cline-worker-b"; f.h.settle(5)
	check("same-token worker replacement retires the model cache", f.models.cached(f.record) == nil and not f.models.isFree(f.record, "fixture-model"))
	f.bridge.stop()
	check("disconnect clears Cline capability and models", f.bridge.status().cline == nil and not f.bridge.clineStatus().available)
	f.finish()
end)

case("sign-in may finish while the authenticated catalog is refreshing", function()
	local f = fixture({ state = "auth-required" })
	f.modelDelay = 5
	f.h.sched.spawn(function() f.h.sched.wait(1); f.state = "ready" end)
	local models = f.run(function() return f.models.discover(f.record, { force = true }) end, 6)
	check("ready transition does not supersede the same owner's catalog", #models == 1 and f.models.cached(f.record) ~= nil
		and f.models.isFree(f.record, "fixture-model"))
	f.finish()
end)

case("healthy Cline pins inference to Cowork and preserves exact payload", function()
	local f = fixture()
	local body = '{"model":"fixture-model","messages":[{"role":"user","content":"fixture"}],"stream":false}'
	local result = f.run(function() return f.http.send({ url = URL, method = "POST", body = body, attempts = 3, identity = "none",
		relay = true, relayEndpoint = { target = "companion", base = "http://127.0.0.1:8790", token = "phone-token" } }) end, 2)
	check("one completion comes from the bridge", result and result.status == 200 and #f.sent == 1)
	check("selected bridge owns the exact inference payload", f.sent[1].body.body == body and f.sent[1].body.url == URL
		and f.sent[1].url:find(":28791/", 1, true) and f.sent[1].headers.Authorization == "Bearer " .. f.desktop.token)
	for _, target in ipairs(f.nativeTargets) do check("virtual host never reaches executor HTTP", not target:find("uai-tunnel.invalid", 1, true)) end
	f.finish()
end)

case("Stop cancels the accepted Cline job once without replay", function()
	local f = fixture()
	f.keepRunning = true
	local stopped = false
	f.h.sched.spawn(function() f.h.sched.wait(0.4); stopped = true end)
	local result, why = f.run(function() return f.http.send({ url = URL, method = "POST", body = '{"model":"fixture-model"}',
		attempts = 4, aborted = function() return stopped end }) end, 1.5)
	f.h.settle(0.3)
	check("Stop remains terminal", result == nil and why == "aborted")
	check("accepted request is cancelled once", #f.sent == 1 and f.cancelled == 1)
	f.finish()
end)

case("disabled and legacy helpers cannot use Cline", function()
	for _, options in ipairs({ { state = "disabled" }, { legacy = true } }) do
		local f = fixture(options)
		local models = f.run(function() return f.models.discover(f.record) end)
		local result = f.run(function() return f.http.send({ url = URL, method = "POST", body = "{}" }) end)
		check("unsupported helper admits no Cline work", #models == 0 and result.terminal and f.catalogCalls == 0 and #f.sent == 0 and f.virtualCalls == 0)
		f.finish()
	end
end)

case("late catalogs cannot cross a changed bridge token", function()
	local f = fixture()
	f.modelDelay = 1
	local models, why
	f.h.sched.spawn(function() models, why = f.models.discover(f.record, { force = true }) end)
	f.h.settle(0.1)
	f.desktop.token = ("b"):rep(64); f.bridge.sync()
	f.h.settle(1.5)
	check("stale result is rejected and not cached", models and #models == 0 and why:find("connection changed", 1, true) and f.models.cached(f.record) == nil)
	f.finish()
end)

suite.finish()
