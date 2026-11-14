-- Official direct Responses contracts. Routes, credentials and output are synthetic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Direct OpenAI Responses")
local case, check = suite.case, suite.check
local function has(value, part) return tostring(value):find(part, 1, true) ~= nil end
local function includes(values, wanted)
	for _, value in ipairs(values or {}) do if value == wanted then return true end end
	return false
end
local function message(text)
	return { type = "message", id = "msg-fixture", role = "assistant", status = "completed",
		content = { { type = "output_text", text = text or "Fixture complete" } } }
end
local function fixture()
	local f = F.new()
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank("openai")
	f.record.id, f.record.model, f.record.apiKey = "openai-fixture", "gpt-6.1-terra", "fixture-bearer-key"
	f.responses, f.chat, f.config = f.env.require("provider/responses"), f.env.require("provider/chat"), f.env.require("runtime/config")
	f.sent = {}
	function f.response(output, status)
		return { object = "response", id = "resp-fixture", model = f.record.model, status = status or "completed",
			output = output or { message() }, usage = { input_tokens = 12, output_tokens = 3, total_tokens = 15 } }
	end
	function f.reply(output, status)
		return { StatusCode = 200, Body = f.h.json.encode(f.response(output, status)) }
	end
	function f.handler(callback)
		f.h.http.handler = function(entry)
			f.sent[#f.sent + 1] = entry
			return callback(entry, #f.sent)
		end
	end
	function f.request(options)
		options = options or {}
		options.messages = options.messages or { { role = "user", content = "Inspect the fixture" } }
		options.attempts, options.timeout = options.attempts or 1, options.timeout or 5
		return options
	end
	function f.complete(options, seconds)
		return f.run(function() return f.chat.complete(f.record, f.request(options)) end, seconds or 0.3)
	end
	function f.direct(options)
		return f.run(function() return f.responses.complete(f.record, f.request(options)) end, 0.3)
	end
	function f.done() f.healthy(); f.close() end
	return f
end
local function tools()
	return {
		{ type = "function", ["function"] = { name = "read_fixture", description = "Read one fixture",
			parameters = { type = "object", properties = { path = { type = "string" }, label = { type = "string" } }, required = { "path" } } } },
		{ type = "function", name = "strict_fixture", description = "Explicit strict schema", strict = true,
			parameters = { type = "object", properties = { path = { type = "string" } }, required = { "path" }, additionalProperties = false } },
	}
end

case("only exact supported IDs and official HTTPS routes select Responses", function()
	local f = fixture(); local util = f.env.require("runtime/util")
	for _, id in ipairs({ "gpt-6-astra", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-sol", "gpt-6-luna" }) do
		for _, base in ipairs({ "https://api.openai.com/v1", "https://api.openai.com:443/v1/chat/completions?tenant=old",
			"https://api.openai.com/v1/responses?tenant=old" }) do
			local record = util.copy(f.record); record.model, record.baseUrl, record.query = id, base, { tenant = "new" }
			check("exact direct predicate " .. id .. " " .. base, f.registry.isDirectOpenaiResponses(record) and f.responses.wantsResponses(record))
			check("direct protocol guard and socket boundary " .. id .. " " .. base,
				f.registry.protocolProblem(record) == nil and f.chat.protocolOf(record) == "responses" and not f.chat.supportsSocket(record))
			check("full inference suffix and query are preserved " .. id .. " " .. base,
				f.responses.endpointFor(record) == (base:find(":443", 1, true) and "https://api.openai.com:443" or "https://api.openai.com") .. "/v1/responses?tenant=new")
		end
	end
	local legacy = util.copy(f.record); legacy.api = nil
	check("the legacy default API remains OpenAI", f.registry.isDirectOpenaiResponses(legacy))
	for _, edit in ipairs({
		{ model = "gpt-6.1-terra-2099-01-01" }, { model = "openai/gpt-6.1-terra" }, { model = "GPT-6.1-TERRA" },
		{ model = "not-gpt-6.1-terra" }, { model = "gpt-5.6-sol" }, { api = "anthropic" }, { api = "gemini" },
		{ baseUrl = "https://gateway.example/v1/responses" }, { baseUrl = "https://api.openai.com/custom/v1/responses" },
		{ baseUrl = "https://api.openai.com:8443/v1/responses" }, { baseUrl = "http://api.openai.com/v1/responses" },
		{ baseUrl = "https://api.openai.com.example/v1/responses" },
		{ baseUrl = "" },
	}) do
		local record = util.copy(f.record)
		record.baseUrl = "https://api.openai.com/v1/responses"
		for key, value in pairs(edit) do record[key] = value end
		check("unsupported identity cannot inherit direct routing", not f.registry.isDirectOpenaiResponses(record) and not f.responses.wantsResponses(record))
		if has(record.baseUrl, "/responses") then check("full unsupported Responses route is still rejected", f.registry.protocolProblem(record) ~= nil) end
	end
	local invalid = util.copy(f.record); invalid.baseUrl = "https://user:pass@api.openai.com/v1/responses"
	check("URL userinfo never qualifies for direct routing", not f.registry.isDirectOpenaiResponses(invalid))
	f.done()
end)

case("direct JSON dispatch retains the full Responses URL and query", function()
	local f = fixture()
	f.record.baseUrl, f.record.query = "https://api.openai.com/v1/responses?tenant=old", { tenant = "new", version = "fixture" }
	f.handler(function(entry)
		check("the full route never sends a Chat probe", entry.url == "https://api.openai.com/v1/responses?tenant=new&version=fixture")
		check("direct JSON uses its normal bearer and accept headers", entry.headers.Authorization == "Bearer fixture-bearer-key" and entry.headers.Accept == "application/json")
		return f.reply()
	end)
	local result = assert(f.complete({ stream = false }))
	check("one native Responses request returns a normalized reply", #f.sent == 1 and result.content == "Fixture complete" and not result.streamed)
	check("default direct requests remain stateless", f.h.json.decode(f.sent[1].body).store == false)
	f.done()
end)

case("custom gateways preserve Chat and explicit unsupported Responses never dispatches", function()
	local f = fixture(); f.record.baseUrl = "https://gateway.example/v1"
	f.handler(function(entry)
		check("custom model spelling keeps the configured Chat route", entry.url == "https://gateway.example/v1/chat/completions")
		return { StatusCode = 200, Body = f.h.json.encode({ model = f.record.model,
			choices = { { message = { role = "assistant", content = "Custom answer" }, finish_reason = "stop" } } }) }
	end)
	local result = assert(f.complete({ stream = false }))
	check("custom Chat returns its ordinary reply", result.content == "Custom answer" and result.responsesScope == nil and #f.sent == 1)
	local rejected, why = f.direct()
	check("explicit unsupported Responses fails before another send", not rejected and has(why, "Responses is unavailable") and #f.sent == 1)
	f.done()
end)

case("direct bodies preserve optional schemas, effort and compatible includes", function()
	local f = fixture(); local source = tools()
	f.config.set("ui.showReasoning", false)
	f.record.params = { max_output_tokens = 1000000, temperature = 0.8, top_p = 0.9, top_logprobs = 4, logprobs = true,
		include = { "file_search_call.results", "reasoning.encrypted_content", "reasoning.encrypted_content", "message.output_text.logprobs" } }
	local request = { messages = { { role = "system", content = "System fixture" }, { role = "user", content = "Hello" } },
		tools = source, toolChoice = { type = "function", ["function"] = { name = "read_fixture" } },
		effort = "high", stream = false, maxTokens = 128000, outputCeiling = 1024, extra = { max_output_tokens = 999999 } }
	local body = f.responses.buildBody(f.record, request)
	check("native effort and hidden reasoning summary use Responses fields", body.reasoning.effort == "high" and body.reasoning.summary == nil and body.reasoning_effort == nil)
	check("encrypted reasoning remains requested while display is hidden", includes(body.include, "reasoning.encrypted_content") and #body.include == 2)
	check("compatible raw includes survive and unsupported logprobs do not", includes(body.include, "file_search_call.results") and not includes(body.include, "message.output_text.logprobs")
		and body.temperature == nil and body.top_p == nil and body.top_logprobs == nil and body.logprobs == nil)
	check("optional schema properties stay optional", body.tools[1].strict == false and #body.tools[1].parameters.required == 1
		and body.tools[1].parameters.required[1] == "path" and body.tools[1].parameters.properties.label.type == "string")
	check("explicit strict choice and flat named tool choice are retained", body.tools[2].strict == true
		and body.tool_choice.type == "function" and body.tool_choice.name == "read_fixture" and body.tool_choice["function"] == nil)
	check("post-override output ceiling and instructions remain effective", body.max_output_tokens == 1024 and body.instructions == "System fixture" and #body.input == 1)
	body.tools[1].parameters.properties.label.type = "number"
	check("building or editing a body does not mutate caller schemas", source[1]["function"].strict == nil
		and source[1]["function"].parameters.properties.label.type == "string" and f.record.params.max_output_tokens == 1000000)
	request.outputCeiling = nil
	check("documented output limit also clamps raw overrides", f.responses.buildBody(f.record, request).max_output_tokens == 128000)
	request.effort = "none"
	local none = f.responses.buildBody(f.record, request)
	check("documented none retains intentional sampling and logprob fields", none.reasoning.effort == "none" and none.temperature == 0.8
		and none.top_p == 0.9 and includes(none.include, "message.output_text.logprobs") and includes(none.include, "reasoning.encrypted_content"))
	f.record.model = "gpt-6.1-sol"
	local mandatory = f.responses.buildBody(f.record, request)
	check("Sol clamps none to low and removes unsupported sampling", mandatory.reasoning.effort == "low" and mandatory.temperature == nil)
	f.config.set("agent.forceSampling", { ["gpt-6.1-sol"] = true })
	local manual = f.responses.buildBody(f.record, request)
	check("explicit manual sampling remains an override", manual.temperature == 0.8 and includes(manual.include, "message.output_text.logprobs"))
	request.stream = nil; f.config.set("agent.stream", false); f.record.stream = true
	check("global stream preference reaches direct Responses", f.responses.buildBody(f.record, request).stream == false)
	f.config.set("agent.stream", true); f.record.stream = false
	check("record stream preference reaches direct Responses", f.responses.buildBody(f.record, request).stream == false)
	f.env.require("net/transport").streamForced = function() return true end
	request.stream = false
	check("transport streaming overrides a direct nonstreaming preference", f.responses.buildBody(f.record, request).stream == true)
	f.done()
end)

case("direct raw model overrides cannot attach foreign state to the selected scope", function()
	local f = fixture()
	f.record.params = { model = "gpt-6-sol" }
	local result, why = f.direct({ stream = false })
	check("provider model mismatch fails before dispatch", not result and has(why, "model override must match") and #f.sent == 0)
	f.record.params = { model = f.record.model }
	local extra, detail = f.direct({ stream = false, extra = { model = "gpt-6-luna" } })
	check("request model mismatch fails before dispatch", not extra and has(detail, "model override must match") and #f.sent == 0)
	local body = f.responses.buildBody(f.record, { messages = {}, extra = { model = f.record.model } })
	check("matching raw model overrides remain valid", body.model == f.record.model)
	f.record.baseUrl = "https://gateway.example/v1"
	check("custom gateway model override behavior remains available",
		f.responses.buildBody(f.record, { messages = {}, extra = { model = "custom-model" } }).model == "custom-model")
	f.done()
end)

case("direct declaration-limit repair preserves the catalog and explicit strict defaults", function()
	local f = fixture(); local source = tools()
	source[#source + 1] = { type = "function", ["function"] = { name = "extra_fixture", parameters = { type = "object", properties = {} } } }
	f.handler(function(entry, index)
		local body = f.h.json.decode(entry.body)
		if index == 1 then return { StatusCode = 400, Body = '{"error":{"message":"tools array too long: maximum length 2"}}' } end
		check("one repaired request retains the original catalog", #body.tools == 2 and has(entry.body, "uai_tool_catalog"))
		for _, tool in ipairs(body.tools) do check("repaired function strict setting stays explicit", type(tool.strict) == "boolean") end
		check("repaired requests retain stateless encrypted reasoning", body.store == false and includes(body.include, "reasoning.encrypted_content"))
		return f.reply()
	end)
	local result = assert(f.complete({ stream = false, tools = source }))
	check("safe explicit refusal repairs only once", result.content == "Fixture complete" and #f.sent == 2)
	check("repair never edits the offered source catalog", #source == 3 and source[1]["function"].strict == nil and source[2].strict == true)
	f.done()
end)

case("JSON and SSE preserve encrypted reasoning through context reload without credentials", function()
	for _, mode in ipairs({ "json", "sse" }) do
		local f = fixture(); local util = f.env.require("runtime/util")
		f.record.baseUrl = "https://api.openai.com/v1?api_key=fixture-url-credential"
		f.record.query = { token = "fixture-query-credential" }
		local ciphertext = string.rep("opaque-ciphertext-", 2000)
		local output = {
			{ type = "reasoning", id = "rs-fixture", encrypted_content = ciphertext, summary = { { type = "summary_text", text = "Visible summary" } } },
			{ type = "function_call", id = "fc-fixture", call_id = "call-fixture", name = "read_fixture", arguments = '{"path":"fixture"}', status = "completed" },
			message("Reading fixture"),
		}
		f.handler(function(entry, index)
			if index > 1 then return f.reply() end
			if mode == "json" then return f.reply(output) end
			check("SSE uses the streaming accept header", entry.headers.Accept == "text/event-stream")
			local events = {}
			local function event(kind, value)
				value.type = kind; events[#events + 1] = "event: " .. kind .. "\ndata: " .. f.h.json.encode(value) .. "\n\n"
			end
			event("response.output_item.added", { output_index = 1, item = { type = "function_call", id = "fc-fixture", call_id = "call-fixture", name = "read_fixture", arguments = "" } })
			event("response.function_call_arguments.delta", { item_id = "fc-fixture", output_index = 1, delta = '{"path":' })
			event("response.function_call_arguments.done", { item_id = "fc-fixture", output_index = 1, arguments = '{"path":"fixture"}' })
			event("response.output_text.delta", { delta = "Earlier partial" })
			event("response.completed", { response = f.response(output) })
			return { StatusCode = 200, Body = table.concat(events), Headers = { ["content-type"] = "text/event-stream" } }
		end)
		local first = assert(f.complete({ stream = mode == "sse", tools = tools() }))
		check("authoritative output replaces partials " .. mode, first.content == "Reading fixture" and #first.toolCalls == 1 and first.toolCalls[1].id == "call-fixture")
		check("opaque reasoning exceeds display retention without truncation " .. mode, first.responsesItems[1].encrypted_content == ciphertext and #ciphertext > 24000)
		check("persisted scope is an opaque SHA-256 comparison token " .. mode,
			#first.responsesScope == 71 and first.responsesScope:match("^sha256:[a-f0-9]+$") ~= nil)
		local ctx = f.env.require("agent/context").new(); ctx.pushUser("Read fixture"); ctx.pushAssistant(first)
		ctx.pushToolResult("call-fixture", "read_fixture", "Fixture result")
		first.responsesItems[1].encrypted_content = "caller mutation"
		check("context owns a detached signed-state copy " .. mode, ctx.messages[2].responsesItems[1].encrypted_content == ciphertext)
		local encoded = util.encode(ctx.serialise())
		check("serialization never stores query or provider credentials " .. mode, not has(encoded, "fixture-url-credential")
			and not has(encoded, "fixture-query-credential") and not has(encoded, "fixture-bearer-key") and not has(encoded, "api.openai.com"))
		local restored = f.env.require("agent/context").new(); assert(restored.restore(util.decode(encoded)))
		local body = f.responses.buildBody(f.record, { messages = restored.wire("System fixture"), stream = false })
		check("reload preserves original output-item order " .. mode, #body.input == 5 and body.input[2].type == "reasoning"
			and body.input[3].id == "fc-fixture" and body.input[4].id == "msg-fixture" and body.input[5].type == "function_call_output")
		check("reload preserves full ciphertext and call/result identity " .. mode, body.input[2].encrypted_content == ciphertext
			and body.input[3].call_id == body.input[5].call_id and body.input[5].output == "Fixture result")
		body.input[2].encrypted_content = "wire mutation"
		check("request body edits cannot alter restored history " .. mode, restored.messages[2].responsesItems[1].encrypted_content == ciphertext)
		local second = assert(f.complete({ messages = restored.wire("System fixture"), stream = false }))
		local replay = f.h.json.decode(f.sent[2].body)
		check("complete dispatch actually replays signed state " .. mode, replay.input[2].encrypted_content == ciphertext and second.responsesScope == ctx.messages[2].responsesScope)
		local changed = util.copy(f.record); changed.model = "gpt-6-sol"
		local migrated = f.responses.buildBody(changed, { messages = restored.wire("System fixture") })
		check("a different model cannot replay opaque state " .. mode, not has(util.encode(migrated), ciphertext) and migrated.input[2].type == nil
			and migrated.input[3].type == "function_call" and migrated.input[4].type == "function_call_output")
		changed = util.copy(f.record); changed.query = { token = "different-query-credential" }
		check("a changed query also changes the scope " .. mode, not has(util.encode(f.responses.buildBody(changed, { messages = restored.wire("System fixture") })), ciphertext))
		f.done()
	end
end)

case("malformed signed replay is rejected before another native dispatch", function()
	local f = fixture()
	f.handler(function() return f.reply({ { type = "reasoning", encrypted_content = "valid-cipher", summary = {} }, message() }) end)
	local first = assert(f.complete({ stream = false }))
	local invalid = {
		{ "item type", { { type = "Invalid-Type" } } },
		{ "UTF-8", { { type = "reasoning", encrypted_content = "\255" } } },
		{ "bytes", { { type = "reasoning", encrypted_content = string.rep("c", f.responses.limits.historyBytes) } } },
	}
	local count = {}; for index = 1, f.responses.limits.historyItems + 1 do count[index] = { type = "reasoning" } end
	invalid[#invalid + 1] = { "items", count }
	local cyclic = { type = "reasoning" }; cyclic.self = cyclic; invalid[#invalid + 1] = { "cycle", { cyclic } }
	local nested, cursor = { type = "reasoning" }; cursor = nested
	for _ = 1, 17 do cursor.child = {}; cursor = cursor.child end
	invalid[#invalid + 1] = { "depth", { nested } }
	local wide = { type = "reasoning" }; for index = 1, 257 do wide["field" .. index] = true end
	invalid[#invalid + 1] = { "fields", { wide } }
	local nodes = {}
	for index = 1, 128 do
		local item = { type = "reasoning", summary = {} }
		for child = 1, 128 do item.summary[child] = { type = "summary_text", text = "fixture" } end
		nodes[index] = item
	end
	invalid[#invalid + 1] = { "nodes", nodes }
	for _, entry in ipairs(invalid) do
		local result, why = f.direct({ messages = { { role = "user", content = "Hello" }, { role = "assistant", content = "Previous",
			responsesScope = first.responsesScope, responsesItems = entry[2] } } })
		check("invalid signed " .. entry[1] .. " is refused during preparation", not result and has(why, "Unable to prepare Responses request") and #f.sent == 1)
	end
	f.done()
end)

case("invalid final history cannot return tools or a successful completion", function()
	for _, mode in ipairs({ "missing", "missing-status", "wrong-object", "oversized", "invalid-type", "too-many" }) do
		local f = fixture()
		f.handler(function()
			local response = f.response({ { type = "function_call", call_id = "call-fixture", name = "read_fixture", arguments = "{}" }, message() })
			if mode == "missing" then response.output = nil
			elseif mode == "missing-status" then response.status = nil
			elseif mode == "wrong-object" then response.object = "chat.completion"
			elseif mode == "oversized" then table.insert(response.output, 1, { type = "reasoning", encrypted_content = string.rep("c", f.responses.limits.historyBytes) })
			elseif mode == "invalid-type" then table.insert(response.output, 1, { type = "Invalid-Type" })
			else for _ = 1, f.responses.limits.historyItems do response.output[#response.output + 1] = { type = "reasoning" } end end
			return { StatusCode = 200, Body = f.h.json.encode(response) }
		end)
		local result, why = f.complete({ stream = false, attempts = 4 })
		check("malformed authoritative output rejects tools " .. mode, not result and has(why, "malformed_stream") and #f.sent == 1)
		f.done()
	end
end)

case("incomplete streams, partial tools and quota errors remain terminal", function()
	for _, mode in ipairs({ "incomplete-json", "unfinished-sse", "quota-sse" }) do
		local f = fixture()
		f.handler(function()
			if mode == "incomplete-json" then return f.reply({ { type = "function_call", call_id = "call-fixture", name = "read_fixture", arguments = "{}" } }, "incomplete") end
			local body = 'event: response.output_item.added\ndata: {"type":"response.output_item.added","output_index":0,"item":{"type":"function_call","id":"fc-fixture","call_id":"call-fixture","name":"read_fixture","arguments":"{}"}}\n\n'
			if mode == "quota-sse" then body = body .. 'event: error\ndata: {"type":"error","code":"rate_limit_exceeded","message":"Fixture quota exceeded"}\n\n' end
			return { StatusCode = 200, Body = body }
		end)
		local result, why = f.complete({ attempts = 4 })
		check("incomplete response cannot execute its available tool JSON " .. mode, not result and why ~= nil and #f.sent == 1)
		if mode == "quota-sse" then check("quota detail remains visible", has(why, "rate_limit_exceeded")) end
		f.done()
	end
end)

case("in-flight route changes and missing hashing prevent mis-scoped replay", function()
	local f = fixture()
	f.handler(function()
		f.record.query = { token = "changed-during-send" }
		return f.reply({ { type = "reasoning", encrypted_content = "old-route-cipher" }, message() })
	end)
	local result, why = f.complete({ stream = false })
	check("a route edit cannot attach a new scope to an old response", not result and why == "aborted" and #f.sent == 1)
	f.done()
	local missing = fixture()
	missing.loaded["runtime/credential_sha256"] = { digest = function() return nil end }
	local rejected, detail = missing.direct({ stream = false })
	check("scope hashing failure rejects before network use", not rejected and has(detail, "Could not fingerprint Responses history scope") and #missing.sent == 0)
	missing.done()
end)

suite.finish()
