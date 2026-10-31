-- Regression for the reported 163-tools / maximum-length-128 refusal.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider tool count")
local case, check = suite.case, suite.check
local function setup()
	local f = F.new()
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.id, record.label, record.model = "tool-count", "Tool count fixture", "unknown-model"
	record.baseUrl, record.apiKey = "https://fixture.test/v1", "fixture-key"
	assert(registry.save(record, { force = true }))
	local tools = {}
	for index = 1, 163 do tools[index] = { type = "function", ["function"] = {
		name = "fixture_" .. index, parameters = { type = "object", properties = {} } } } end
	return f, record, tools
end

case("unknown models and explicit overrides stay within the wire ceiling", function()
	local f, record, tools = setup()
	local openai = f.env.require("provider/openai")
	for _, adapter in ipairs({ openai, f.env.require("provider/responses") }) do
		local wire = adapter.toolsFor and adapter.toolsFor(tools) or tools
		for _, request in ipairs({ { tools = tools }, { tools = tools, extra = { tools = wire } } }) do
			local body = adapter.buildBody(record, request)
			check("163 supplied tools produce at most 128 declarations", #body.tools == 128)
			check("wire shape and first declaration survive", (body.tools[1]["function"] or body.tools[1]).name == "fixture_1")
			local all = {}
			for _, tool in ipairs(body.tools) do
				local fn = tool["function"] or tool
				if fn.name == "uai_tool_catalog" then
					for _, name in ipairs(fn.parameters.properties.name.enum) do all[name] = true end
				else all[fn.name] = true end
			end
			for index = 1, 163 do check("every original tool remains reachable", all["fixture_" .. index]) end
			check("unrelated providers receive no OpenCode shell placeholders", all.bash == nil and all.shell == nil)
		end
		record.params = { tools = wire }
		check("provider parameters cannot bypass the ceiling", #adapter.buildBody(record, {}).tools == 128)
		record.params = nil
	end
	check("caller catalogue remains complete and unmodified", #tools == 163 and tools[163]["function"].name == "fixture_163")
	local message = "Bad request: Invalid 'tools': array too long. Expected an array with maximum length 128, but got an array with length 163 instead."
	check("reported wording extracts the maximum rather than the sent count", openai.toolCeilingFromMessage(message) == 128)
	local body = { tools = tools }
	local note, key = openai.repairForTest(body, message)
	check("existing oversized bodies repair to the stated limit", note and key == "cap_tools" and #body.tools == 128)
	f.healthy(); f.close()
end)

case("both protocols describe and execute overflow tools through the real agent loop", function()
	for _, protocol in ipairs({ "openai", "responses" }) do
		local f, record = setup(); f.tools({})
		f.env.require("runtime/config").set("agent.toolProfile", "all")
		local writes, requests, events = 0, 0, {}
		for index = 1, 163 do
			f.registry.register({ name = "fixture_" .. index, group = "fs", risk = "write", description = "Change the fixture target",
				parameters = { type = "object", properties = { target = { type = "string", enum = { "exact-target" } } }, required = { "target" } },
				run = function(args) writes = writes + 1; return "Changed " .. args.target end })
		end
		f.loaded["provider/chat"] = { complete = f.env.require("provider/" .. protocol).complete, contextOverflow = function() return false end }
		f.h.http.handler = function(req)
			requests = requests + 1
			local body = f.h.json.decode(req.body)
			check("every provider request keeps 128 declarations", #body.tools == 128)
			local router = body.tools[#body.tools]; router = router["function"] or router
			local messages = body.messages or body.input
			if requests == 2 then
				local last = messages[#messages]
				local content = last.content or last.output
				check("schema reaches the model before execution", content:find('"target"', 1, true) and content:find("exact-target", 1, true) and writes == 0)
				local assistant = messages[#messages - 1]
				check("provider history retains the declared wrapper and original call identity", protocol == "openai"
					and assistant.tool_calls[1]["function"].name == router.name and assistant.tool_calls[1].id == "overflow_1"
					or protocol == "responses" and assistant.name == router.name and assistant.call_id == "overflow_1")
			elseif requests == 3 then
				local last = messages[#messages]
				check("native result reaches the next model request", (last.content or last.output) == "Changed exact-target" and writes == 1)
			end
			local args = { action = requests == 1 and "describe" or "call", name = "fixture_163" }
			if requests == 2 then args.arguments = { target = "exact-target" } end
			local complete = requests >= 3
			if protocol == "openai" then
				return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = complete and { content = "Finished" }
					or { content = "", tool_calls = { { id = "overflow_" .. requests, type = "function",
						["function"] = { name = router.name, arguments = f.h.json.encode(args) } } } }, finish_reason = complete and "stop" or "tool_calls" } } }) }
			end
			return { StatusCode = 200, Body = f.h.json.encode({ object = "response", status = "completed", output = complete
				and { { type = "message", content = { { type = "output_text", text = "Finished" } } } }
				or { { type = "function_call", call_id = "overflow_" .. requests, name = router.name, arguments = f.h.json.encode(args) } } }) }
		end
		local session = assert(f.env.require("agent/session").create({ ephemeral = true, maxTurns = 5 }))
		session.systemPrompt = "Use the overflow catalogue to inspect and call fixture_163."
		local emit = session.emit
		session.emit = function(kind, payload) if kind == "tool:call" then events[#events + 1] = payload end; emit(kind, payload) end
		local result = f.run(function() return f.env.require("agent/loop").run(session, "Change exact-target") end, 1)
		check("real loop executes once and finishes", result == "Finished" and writes == 1 and requests == 3)
		check("execution UI keeps native tool identity and arguments", events[2].name == "fixture_163" and events[2].id == "overflow_2"
			and f.h.json.decode(events[2].arguments).target == "exact-target")
		f.healthy(); f.close()
	end
end)

case("catalogue boundaries reject malformed or unavailable calls and retain exact pages", function()
	local f, record, definitions = setup(); f.tools({})
	local util, adapter, catalog = f.env.require("runtime/util"), f.env.require("provider/openai"), f.env.require("provider/tool_catalog")
	definitions[1]["function"].name = "uai_tool_catalog"
	definitions[163]["function"].description = ("schema \231\149\140 "):rep(500)
	local source = util.encode(definitions[163]["function"])
	local body = adapter.buildBody(record, { tools = definitions })
	local router = body.tools[#body.tools]["function"]
	check("real registered router-like names cannot collide", router.name == "uai_tool_catalog_2")
	local function resolve(args, offered)
		local result = catalog.bind({ toolCalls = { { id = "catalogue", ["function"] = { name = router.name,
			arguments = type(args) == "string" and args or f.h.json.encode(args) } } } }, body)
		return catalog.resolve(result, offered or definitions)
	end
	f.env.require("runtime/config").set("agent.resultCap", 500)
	local offset, pieces = 1, {}
	repeat
		local _, immediate = resolve({ action = "describe", name = "fixture_163", offset = offset })
		local page = immediate[1]
		check("schema pages fit the result budget with their cursor", page.ok and #page.modelText <= 500 and util.validUtf8(page.modelText))
		pieces[#pieces + 1] = assert(page.text:match("^[^\n]*\n(.*)$"))
		offset = page.data.nextOffset
	until not offset
	check("complete schema is reconstructed byte for byte", table.concat(pieces) == source)
	for _, args in ipairs({ '{"action":"call","name":"fixture_163","arguments":{',
		{ action = "call", name = "fixture_163" }, { action = "call", name = "not_offered", arguments = {} },
		{ action = "call", name = "fixture_163", arguments = {}, target = "discarded" },
		{ action = "describe", name = "fixture_163", offset = 999999 } }) do
		local calls, immediate = resolve(args)
		check("invalid router input has no executable native call", immediate[1] and not immediate[1].ok and calls[1]["function"].name == router.name)
	end
	local _, denied = resolve({ action = "call", name = "fixture_163", arguments = {} }, {})
	check("a provider override cannot enlarge agent tool scope", denied[1] and not denied[1].ok)
	local ran = 0
	f.registry.register({ name = "fixture_163", group = "fs", risk = "write", run = function() ran = ran + 1; return "changed" end })
	local calls, immediate = resolve({ action = "call", name = "fixture_163", arguments = {} })
	f.env.require("agent/permissions").setRule("fixture_163", "deny")
	local outcomes = f.run(function() return catalog.runAll(calls, immediate, { session = {}, aborted = function() return false end }, f.registry, function() end) end)
	check("translated calls still pass current native permission decisions", not outcomes[1].ok and ran == 0)
	adapter.limitTools(body, 16, false)
	local narrowed = body.tools[#body.tools]["function"]
	check("a stricter repair preserves the original complete catalogue", #body.tools == 16 and #narrowed.parameters.properties.name.enum == 148
		and narrowed.parameters.properties.name.enum[148] == "fixture_163")
	for _, flat in ipairs({ false, true }) do
		local wire = flat and f.env.require("provider/responses").toolsFor(definitions) or definitions
		local forced = { tools = wire, tool_choice = flat and { type = "function", name = "fixture_163" }
			or { type = "function", ["function"] = { name = "fixture_163" } } }
		adapter.limitTools(forced, 16, false)
		local found
		for _, tool in ipairs(forced.tools) do if (tool["function"] or tool).name == "fixture_163" then found = true end end
		check("explicit tool choice keeps its original declaration", found and #forced.tools == 16)
		adapter.limitTools(forced, 1, false)
		local only = forced.tools[1]["function"] or forced.tools[1]
		check("a one-slot limit still has a valid forced choice", #forced.tools == 1 and (forced.tool_choice["function"] or forced.tool_choice).name == only.name
			and only.strict == false)
		local result = catalog.bind({ toolCalls = { { id = "forced", ["function"] = { name = only.name,
			arguments = f.h.json.encode({ action = "call", name = "fixture_162", arguments = {} }) } } } }, forced)
		local _, rejected = catalog.resolve(result, definitions)
		check("routing cannot replace an explicitly selected target", rejected[1] and not rejected[1].ok)
	end
	f.healthy(); f.close()
end)

case("a stricter provider refusal retries once and persists its scoped limit", function()
	for _, protocol in ipairs({ "openai", "responses" }) do
		local f, record, tools = setup()
		local counts = {}
		f.h.http.handler = function(req)
			local body = f.h.json.decode(req.body)
			counts[#counts + 1] = #body.tools
			local router = body.tools[#body.tools]; router = router["function"] or router
			check("every repaired request retains the final original tool", router.parameters.properties.name.enum[#router.parameters.properties.name.enum] == "fixture_163")
			if #counts == 1 then return { StatusCode = 400, Body = f.h.json.encode({ error = { message =
				"Invalid 'tools': array too long. Expected an array with maximum length 64, but got an array with length 128 instead." } }) } end
			if protocol == "responses" then return { StatusCode = 200, Body = f.h.json.encode({ object = "response", status = "completed",
				output = { { type = "message", content = { { type = "output_text", text = "ok" } } } } }) } end
			return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { content = "ok" }, finish_reason = "stop" } } }) }
		end
		local adapter = f.env.require("provider/" .. protocol)
		local request = { messages = { { role = "user", content = "fixture" } }, tools = tools, stream = false }
		local result = f.run(function() return adapter.complete(record, request) end)
		check("explicit smaller limit recovers the rejected request", result and result.content == "ok" and #counts == 2 and counts[1] == 128 and counts[2] == 64)
		local again = f.run(function() return adapter.complete(record, request) end)
		check("next request uses the learned limit immediately", again and counts[3] == 64 and record.toolsCap.limit == 64)
		check("learning does not trim the registered catalogue", #tools == 163)
		f.healthy(); f.close()
	end
end)

suite.finish()
