-- Offline quota signaling and optional capability lifecycle.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local desktop = require("automatic_bridge_fixture")
local suite = F.suite("Kilo recovery")
local case, check = suite.case, suite.check

case("provider no-retry headers prevent transport retries", function()
	local f = F.new()
	local http, caps = f.env.require("net/http"), f.env.require("runtime/caps")
	local calls = 0
	caps.fn.request = function()
		calls = calls + 1
		return { StatusCode = 429, Body = '{"error":{"code":"PROMOTION_MODEL_LIMIT_REACHED"}}', Headers = { ["X-Should-Retry"] = "FALSE" } }
	end
	local result = f.run(function() return http.send({ url = "https://api.kilo.ai/api/gateway/chat/completions",
		method = "POST", body = "{}", identity = "none", attempts = 4 }) end, 1)
	check("the original refusal is retained after one send", result and result.status == 429 and calls == 1)
	check("ordinary overload can still be retried", http.shouldRetry({ status = 429, body = "busy", headers = {} }) == true)
	f.healthy(); f.close()
end)

case("capabilities reject unknown versions and bound presentation", function()
	local f = F.new()
	local status = f.env.require("net/kilo_status")
	check("old helpers may omit the capability", status.read(nil) == nil)
	check("unknown schemas remain unavailable", status.read({ schema = 2 }) == nil)
	local value = status.read({ schema = 1, enabled = true, available = true, state = "standby", message = ("a"):rep(1000) })
	check("standby is enabled but not an established tunnel", value.enabled and not value.available and #value.message <= 410)
	local limited = status.read({ schema = 1, enabled = true, available = true, state = "limited", message = "Shared exits are limited; try later." })
	check("an exhausted tunnel retains its limited state without implying readiness", limited.state == "limited" and not limited.available)
	check("unrecognized state cannot imply readiness", status.read({ schema = 1, available = true, state = "unknown" }).available == false)
	f.healthy(); f.close()
end)

case("bridge refreshes and clears its Kilo capability", function()
	local f = F.new()
	local state = "standby"
	f.h.http.handler = function(req)
		if req.url:find("/api/hello", 1, true) then return { StatusCode = 200, Body = f.h.json.encode({ protocol = 2,
			capabilities = { kilo = { schema = 1, enabled = true, available = state == "ready", state = state } } }) } end
		if req.url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}' } end
		return { StatusCode = 204, Body = "" }
	end
	local bridge, config = f.env.require("net/bridge"), f.env.require("runtime/config")
	desktop.connect(f.h, { config = config, bridge = bridge })
	check("hello exposes standby", bridge.status().kilo and bridge.status().kilo.state == "standby")
	state = "ready"; f.h.settle(5)
	check("later hello exposes readiness", bridge.status().kilo and bridge.status().kilo.available)
	bridge.stop()
	check("stop clears helper status", bridge.status().kilo == nil)
	f.healthy(); f.close()
end)

case("companion refreshes and clears its Kilo capability", function()
	local f = F.new()
	local state, online, advertise = "standby", true, true
	local token, instance = ("a"):rep(64), "kilo-phone"
	f.h.http.relay = function(req)
		if not online then return { StatusCode = 503, Body = "unavailable" } end
		if req.url:find("/api/hello", 1, true) then return { StatusCode = 200, Body = f.h.json.encode({
			server = "uai-relay", protocol = 2, instance = instance,
			capabilities = { kilo = advertise and { schema = 1, enabled = true, available = state == "ready", state = state } or nil },
		}) } end
		if req.url:find("/api/pair", 1, true) then return { StatusCode = 200, Body = f.h.json.encode({
			ok = true, protocol = 2, instance = instance, token = token,
		}) } end
		return { StatusCode = 200, Body = f.h.json.encode({ ok = true, server = "uai-relay", protocol = 2, instance = instance }) }
	end
	local link, config = f.env.require("net/relay_link"), f.env.require("runtime/config")
	local function probe() return f.run(link.probe, 0.5) end
	check("initial authenticated pairing exposes standby", probe() and link.status().kilo and link.status().kilo.state == "standby")
	state = "ready"
	check("later hello exposes readiness", probe() and link.status().kilo and link.status().kilo.available)
	local copy = link.status().kilo
	copy.state = "tampered"
	check("presentation cannot mutate retained helper state", link.status().kilo.state == "ready")
	online = false
	check("failed health check clears exposed helper state", not probe() and link.status().kilo == nil)
	online, advertise = true, false
	check("a legacy helper cannot resurrect an old capability", probe() and link.status().kilo == nil)
	advertise, state = true, "limited"
	check("reconnected helper reports exhaustion", probe() and link.status().kilo and link.status().kilo.state == "limited")
	config.set("relay.mode", "off")
	check("disabling the companion clears helper state", link.status().kilo == nil)
	f.healthy(); f.close()
end)

suite.finish()
