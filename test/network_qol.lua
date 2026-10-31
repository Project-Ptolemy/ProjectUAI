-- Bounded malformed-input and retry decisions, without a live server.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Network quality of life")
local case, check = suite.case, suite.check

case("Retry-After accepts GMT dates and rejects impossible dates", function()
	local f = F.new(); local retry = f.env.require("net/retry_after"); local clock = f.env.require("runtime/clock")
	local now = clock.daysFromCivil(2026, 10, 31) * 86400000
	check("HTTP-date waits use UTC rather than the local timezone", retry.seconds("Sat, 31 Oct 2026 00:00:12 GMT", now) == 12)
	check("delay seconds and elapsed dates remain explicit", retry.seconds("2.5", now) == 2.5 and retry.seconds("0", now) == 0 and retry.seconds("Fri, 30 Oct 2026 23:59:59 GMT", now) == 0)
	for _, value in ipairs({ "Sat, 31 Feb 2026 00:00:12 GMT", "Sat, 31 Oct 2026 24:00:00 GMT", "-2", "NaN", "inf", "soon" }) do
		check("invalid retry header falls back to normal policy", retry.seconds(value, now) == nil)
	end
	f.healthy(); f.close()
end)

case("malformed headers and URLs fail before native dispatch", function()
	local f = F.new(); local http = f.env.require("net/http"); local headers = f.env.require("net/headers")
	check("later independent header maps still override case-insensitively", headers.merge({ Authorization = "old" }, { authorization = "new" }).authorization == "new")
	for _, value in ipairs({ { ["Bad Header"] = "value" }, { Authorization = "one", authorization = "two" }, { Authorization = "key\r\nX-Injected: 1" } }) do
		local response, why = f.run(function() return http.send({ url = "https://fixture.test/v1", headers = value, attempts = 2 }) end)
		check("invalid headers produce an actionable terminal result", response == nil and tostring(why):find("malformed:", 1, true) and f.h.http.requestCount == 0)
	end
	check("URL control bytes never become a host request", f.env.require("net/url").parse("https://fixture.test/v1\0hidden") == nil)
	f.healthy(); f.close()
end)

case("socket requests honor an already expired shared deadline", function()
	local f = F.new(); local caps = f.env.require("runtime/caps"); local opened = 0
	caps.ws = true; caps.fn.websocket = function() opened = opened + 1 end
	local clock, budgets = f.env.require("runtime/clock"), f.env.require("net/deadline")
	local now = clock.ms()
	check("NaN falls back to a finite budget", budgets.at(0 / 0, 0 / 0, now) == now + 120000)
	check("a caller's earlier deadline wins", budgets.at(300, now + 50, now) == now + 50)
	local result, why = f.env.require("net/ws").stream({ url = "wss://fixture.test/socket", timeout = 300, deadlineMs = now - 1 })
	check("expired work does not open a socket", not result and tostring(why):find("deadline:", 1, true) and opened == 0)
	f.healthy(); f.close()
end)

case("disabled or unknown helper capabilities cannot retain readiness", function()
	local f = F.new(); local capability = f.env.require("net/capability")
	local states = { ready = true, starting = true, disabled = true }
	check("unsupported schemas are unavailable", capability.read({ schema = 2, state = "ready" }, states) == nil)
	local disabled = capability.read({ schema = 1, state = "ready", enabled = false, available = true }, states)
	check("disabled wins over stale readiness", not disabled.available and disabled.state == "disabled")
	local unknown = capability.read({ schema = 1, state = "future", enabled = true, available = true, message = {} }, states)
	check("unknown state and malformed text cannot look ready", not unknown.available and unknown.state == "unavailable" and unknown.message == "")
	f.healthy(); f.close()
end)

case("a proxy retry observer can stop before another request is admitted", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("agentrouter"); record.apiKey, record.model = "fixture-key", "fixture-model"
	local stopped = false
	local recovery = f.env.require("provider/proxy").new(record, { aborted = function() return stopped end, onRetry = function() stopped = true end })
	local response = { status = 403, body = '{"error":{"code":"unauthorized_client"}}' }
	check("callback cancellation prevents the proposed retry", not recovery.recover(response) and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("price metadata requires the documented HTTPS route", function()
	local f = F.new(); local info = f.env.require("provider/model_info")
	check("documented direct route has a provider", info.provider({ baseUrl = "https://api.openai.com/v1/chat/completions" }) == "openai")
	for _, url in ipairs({ "http://api.openai.com/v1", "https://api.openai.com:8443/v1", "https://api.openai.com/custom/v1", "https://api.openai.com/v1/responses/messages" }) do
		check("custom route cannot inherit an unrelated price", info.provider({ baseUrl = url, preset = "openai" }) == nil)
	end
	f.healthy(); f.close()
end)

suite.finish()
