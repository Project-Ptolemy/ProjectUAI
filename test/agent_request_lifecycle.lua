-- Provider attempt identity, isolated request hooks and prompt cancellation.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Agent request lifecycle")
local check, case = suite.check, suite.case
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end
local function answer(content)
	return { content = content or "Done", reasoning = "", toolCalls = {}, finish = "stop" }
end
local function fixture()
	local f = F.new(); f.tools({})
	f.env.require("runtime/config").set("agent.fallback", true)
	local providers = f.env.require("provider/registry")
	local records = {}
	for index, name in ipairs({ "Primary", "Fallback" }) do
		local record = providers.blank("custom")
		record.label, record.model = name, name:lower() .. "-fixture-model"
		record.models, record.baseUrl, record.apiKey = { record.model }, "https://" .. name:lower() .. ".test/v1", "fixture-key"
		record.order = index
		assert(providers.save(record)); records[index] = record
	end
	providers.setActive(records[1].id)
	f.records, f.providers = records, providers
	f.session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.chat = { contextOverflow = function() return false end }
	f.loaded["provider/chat"] = f.chat
	function f.turn(text)
		return f.run(function() return f.env.require("agent/loop").run(f.session, text or "Inspect the boat") end)
	end
	return f
end

case("each provider attempt receives its actual model and provider identity", function()
	for _, mode in ipairs({ "main", "worker", "literal" }) do
		local f, requests = fixture(), {}
		if mode == "worker" then
			f.session.headless = true
			f.session.systemPrompt = function(options) return f.env.require("agent/prompt").subagent("Inspect boat", options) end
		elseif mode == "literal" then f.session.systemPrompt = "A host-authored literal prompt." end
		f.chat.complete = function(record, request)
			requests[#requests + 1] = { record = record, text = request.messages[1].content }
			if record.id == f.records[1].id then return nil, "primary unavailable" end
			return answer()
		end
		check(mode .. " reaches the fallback", f.turn() == "Done" and #requests == 2)
		for _, request in ipairs(requests) do
			check(mode .. " prompt belongs to the receiving provider", mode == "literal" and request.text == f.session.systemPrompt
				or mode ~= "literal" and has(request.text, "model " .. request.record.model .. " via " .. request.record.label))
		end
		f.healthy(); f.close()
	end
end)

case("request hook edits cannot change saved messages or registered tool schemas", function()
	local f, requests = fixture(), {}
	local definition = { name = "fixture_read", risk = "read", group = "fixture", description = "Inspect fixture",
		parameters = { type = "object", properties = { target = { type = "string", description = "Original target" } } },
		run = function() return "Read" end }
	assert(f.registry.register(definition))
	f.session.ctx.pushUser("Earlier question")
	f.session.ctx.pushAssistant({ content = "Earlier answer", toolCalls = {} })
	local off = f.env.require("agent/hooks").register("preRequest", function(payload)
		payload.request.messages[1].content = payload.request.messages[1].content .. "\nHOOK"
		payload.request.messages[2].content = payload.request.messages[2].content .. " transformed"
		payload.request.tools[1]["function"].parameters.properties.target.description = "Hook target"
	end)
	f.chat.complete = function(record, request)
		requests[#requests + 1] = f.env.require("runtime/util").deepCopy({ messages = request.messages, tools = request.tools })
		if record.id == f.records[1].id then return nil, "primary unavailable" end
		return answer()
	end
	f.turn()
	check("fallback transforms start from the original history", #requests == 2
		and requests[1].messages[2].content == "Earlier question transformed"
		and requests[2].messages[2].content == "Earlier question transformed")
	for _, request in ipairs(requests) do
		local _, count = request.messages[1].content:gsub("HOOK", "")
		check("each attempt receives one hook instruction", count == 1)
		check("nested schema edits reach only this request", request.tools[1]["function"].parameters.properties.target.description == "Hook target")
	end
	check("conversation history remains original", f.session.ctx.messages[1].content == "Earlier question")
	check("the registered schema remains original", definition.parameters.properties.target.description == "Original target")
	off(); requests = {}; f.turn("Continue")
	check("later requests retain no previous hook edits", not has(requests[1].messages[1].content, "HOOK")
		and requests[1].tools[1]["function"].parameters.properties.target.description == "Original target")
	f.healthy(); f.close()
end)

case("context recovery reapplies hooks to fresh compacted history", function()
	local f, requests, summaries = fixture(), {}, 0
	for index = 1, 8 do
		f.session.ctx.pushUser("Old question " .. index .. (" detail"):rep(100))
		f.session.ctx.pushAssistant(answer(("Old answer "):rep(100)))
	end
	f.chat.contextOverflow = function(err) return err == "fixture context overflow" end
	f.env.require("agent/hooks").register("preRequest", function(payload)
		payload.request.messages[1].content = payload.request.messages[1].content .. "\nHOOK"
	end)
	f.chat.complete = function(_, request)
		if request.tools == nil then summaries = summaries + 1; return answer("The boat inspection is unfinished.") end
		requests[#requests + 1] = request
		if #requests == 1 then return nil, "fixture context overflow" end
		return answer()
	end
	check("recovery succeeds once on the same provider", f.turn() == "Done" and #requests == 2 and summaries == 1)
	check("the recovered attempt has compacted messages", #requests[2].messages < #requests[1].messages
		and has(requests[2].messages[2].content, "boat inspection"))
	local _, count = requests[2].messages[1].content:gsub("HOOK", "")
	check("compaction does not duplicate hook edits", count == 1)
	f.healthy(); f.close()
end)

case("cancellation inside a request hook prevents dispatch and fallback", function()
	local f, calls, started = fixture(), 0, 0
	f.session.events:connect(function(event) if event.kind == "request:start" then started = started + 1 end end)
	f.env.require("agent/hooks").register("preRequest", function() f.session.abort() end)
	f.chat.complete = function() calls = calls + 1; return answer() end
	check("the turn stops before any provider call", f.turn() == "Stopped." and calls == 0 and started == 0)
	f.healthy(); f.close()
end)

case("a request replacement supplies the frame callback used for that attempt", function()
	local f, original, replacement = fixture(), 0, 0
	f.session.onFrame = function() original = original + 1 end
	f.env.require("agent/hooks").register("preRequest", function(payload)
		payload.request = { messages = payload.request.messages, tools = payload.request.tools,
			onFrame = function() replacement = replacement + 1 end }
	end)
	f.chat.complete = function(_, request)
		request.onFrame({ choices = { { delta = { content = "Done" } } } })
		return answer()
	end
	check("the dispatched callback honors the replacement", f.turn() == "Done" and replacement == 1 and original == 0)
	f.healthy(); f.close()
end)

suite.finish()
