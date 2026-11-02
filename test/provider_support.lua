-- All HTTP statuses and common failure surfaces retain their useful error + help.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider support")
suite.case("provider statuses, transport and streamed failures include one invite", function()
	local f = F.new(); local adapter = f.env.require("provider/openai")
	local support = f.env.require("runtime/support")
	for _, status in ipairs({ 400, 401, 402, 403, 404, 408, 410, 413, 422, 429, 500, 502, 503, 529 }) do
		local text = adapter.errorText({ status = status, body = '{"error":{"message":"fixture refusal"}}' })
		suite.check("status and provider detail survive", text:find(tostring(status), 1, true) and text:find("fixture refusal", 1, true))
		suite.check("support attached once", text:find(support.invite, 1, true) and support.error(text) == text)
	end
	for _, failure in ipairs({ "deadline: fixture timeout", "malformed_stream: incomplete", "response_limit: too large" }) do
		local text = adapter.errorText(nil, failure)
		suite.check("terminal classification survives support text", f.env.require("net/http").terminal(text) and text:find(support.invite, 1, true))
	end
	suite.check("cancellation keeps its exact control signal", adapter.errorText(nil, "aborted") == "aborted" and support.error("aborted") == "aborted")
	for _, field in ipairs({ "name", "code" }) do
		local text = adapter.errorText({ status = 403, body = f.h.json.encode({ error = {
			type = "invalid_request_error", [field] = "FreeTierError", message = "Access denied",
		} }) })
		suite.check("mixed error fields retain workaround guidance", text:find("Access denied", 1, true) and text:find("UAI Relay app", 1, true))
	end
	suite.check("stream failures also show mobile guidance", support.error("stream error: FreeTierError"):find("UAI Relay app", 1, true))
	for _, field in ipairs({ "type", "name", "code" }) do
		local text = adapter.errorText({ status = 429, body = f.h.json.encode({ error = {
			type = "invalid_request_error", [field] = "FreeUsageLimitError", message = "Access denied",
		} }) })
		suite.check("free usage status and detail survive", text:find("429", 1, true) and text:find("Access denied", 1, true))
		suite.check("direct refusal preserves the working CLI option", text:find("installed CLI can still have access", 1, true)
			and text:find("installed OpenCode tunnel", 1, true))
		suite.check("direct refusal explains the bridge API-key fix", text:find("Desktop Bridge for API-key access", 1, true))
		suite.check("key replacement makes no free-access promise", text:find("Changing keys may not restore it", 1, true))
		suite.check("free usage guidance is idempotent", support.error(text) == text)
	end
	local streamed = support.error("stream error: RateLimit.FreeUsageLimitError: Access denied")
	suite.check("stream error shows direct-refusal guidance once", streamed:find("installed OpenCode tunnel", 1, true)
		and support.error(streamed) == streamed)
	local log = f.env.require("runtime/log")
	log.error("fixture", "E_FIXTURE: failed")
	suite.check("diagnostic error codes include invite", log.entries[#log.entries].message:find(support.invite, 1, true))
	local session = f.env.require("agent/session").newThread({ ephemeral = true })
	local event
	session.events:connect(function(value) event = value end)
	session.emit("error", { message = "E_FIXTURE: failed" })
	suite.check("conversation failure includes invite", event.message:find(support.invite, 1, true))
	local payload = { text = "E_TOOL: failed", ok = false }
	session.emit("tool:error", payload)
	suite.check("tool error display includes invite without mutating tool result", event.text:find(support.invite, 1, true) and payload.text == "E_TOOL: failed")
	f.healthy(); f.close()
end)
suite.finish()
