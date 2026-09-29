-- Transport outcomes must agree with their retained request diagnostics.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("HTTP diagnostics")
local case, check = suite.case, suite.check

case("successful responses have no invented transport error", function()
	local f = F.new()
	local http, caps = f.env.require("net/http"), f.env.require("runtime/caps")
	for _, status in ipairs({ 200, 204 }) do
		caps.fn.request = function()
			return { StatusCode = status, Body = status == 200 and '{"reply":"done"}' or "", Headers = { server = "fixture", ["cf-ray"] = "trace-id" } }
		end
		local response, why = http.request({ url = "https://fixture.test/chat", method = "POST", body = "{}", identity = "none" })
		local entry = http.history[#http.history]
		check("HTTP " .. status .. " succeeds without an error", response and response.ok and why == nil and entry.error == nil)
		check("HTTP " .. status .. " retains its actual evidence", entry.status == status and entry.server == "fixture" and entry.trace == "trace-id" and entry.via == "executor")
	end
	f.healthy(); f.close()
end)

case("HTTP refusal remains distinct from transport failure", function()
	local f = F.new()
	local http, caps = f.env.require("net/http"), f.env.require("runtime/caps")
	caps.fn.request = function() return { StatusCode = 403, Body = "Denied", Headers = { server = "fixture" } } end
	local response = http.request({ url = "https://fixture.test/denied", identity = "none" })
	check("a received refusal has an HTTP outcome and no transport error", response and not response.ok and response.status == 403 and response.entry.error == nil)
	caps.fn.request = function() error("fixture network unavailable") end
	local absent, why = http.request({ url = "https://fixture.test/unavailable", identity = "none" })
	local entry = http.history[#http.history]
	check("real transport failures keep their reason", not absent and tostring(why):find("fixture network unavailable", 1, true) and entry.error == why and entry.status == 0)
	caps.fn.request = function() return { StatusCode = 200, Body = {} } end
	absent, why = http.request({ url = "https://fixture.test/malformed", identity = "none" })
	check("invalid response bodies still report a transport error", not absent and tostring(why):find("malformed:", 1, true) and http.history[#http.history].error == why)
	f.healthy(); f.close()
end)

suite.finish()
