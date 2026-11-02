-- OpenCode Zen context preserves instruction/history and explicit wire overrides.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("OpenCode Zen runtime context")
local check, case = suite.check, suite.case
local function recordFor(f, base)
	local record = f.env.require("provider/registry").blank("zen")
	record.baseUrl = base or "https://opencode.ai/inference/openai/v1"
	record.model, record.apiKey = "deepseek-v4.1-flash-free", "fixture-zen-key"
	return record
end
local function history()
	return {
		{ role = "system", content = "Keep the user's original instructions." },
		{ role = "developer", content = "Use only the supplied Roblox tools." },
		{ role = "user", content = "Look up health" },
		{ role = "assistant", content = "", reasoning_content = "I need the supplied tool.", toolCalls = {
			{ id = "call-fixture", type = "function", ["function"] = { name = "fixture_lookup", arguments = '{"key":"health"}' } },
		} },
		{ role = "tool", tool_call_id = "call-fixture", content = "TOOL_OK" },
	}
end

case("Chat adds a first system message only on exact official Zen routes", function()
	local f = F.new(); local openai = f.env.require("provider/openai")
	local context = f.env.require("provider/opencode_context").text()
	local messages = history(); local before = f.h.json.encode(messages)
	for _, base in ipairs({ "https://opencode.ai/zen/v1", "https://opencode.ai/inference/v1",
		"https://opencode.ai/inference/openai/v1/chat/completions?tenant=fixture", "https://opencode.ai:443/inference/openai/v1" }) do
		local record = recordFor(f, base)
		local body = openai.buildBody(record, { messages = messages, maxTokens = 512, stream = true })
		check("context is truthful and first", body.messages[1].role == "system" and body.messages[1].content == context)
		check("original instruction and developer priority remain", body.messages[2].content == messages[1].content and body.messages[3].content == messages[2].content)
		check("user and tool history remain in order", #body.messages == #messages + 1 and body.messages[4].content == "Look up health"
			and body.messages[5].tool_calls[1].id == "call-fixture" and body.messages[5].reasoning_content == messages[4].reasoning_content
			and body.messages[6].tool_call_id == "call-fixture" and body.messages[6].content == "TOOL_OK")
		check("compatibility declarations and model stay unchanged", #body.tools == 7 and body.model == "deepseek-v4.1-flash-free")
		check("saved history is not mutated", f.h.json.encode(messages) == before)
	end
	f.healthy(); f.close()
end)

case("context attachment is idempotent and retains existing message content", function()
	local f = F.new(); local context = f.env.require("provider/opencode_context")
	local messages = history(); local first = context.chat(messages); local second = context.chat(first)
	check("repeated preparation adds no second context", second == first and #second == #messages + 1)
	check("preparation does not edit caller-owned messages", first ~= messages and first[2] == messages[1] and #messages == 5)
	local original = "Keep every original instruction.\n\n" .. context.text()
	local prepared = { { role = "system", content = original }, { role = "user", content = "hello" } }
	check("an existing context is not duplicated or rewritten", context.chat(prepared) == prepared and prepared[1].content == original)
	check("Responses retains original instructions exactly", context.instructions("ORIGINAL") == context.text() .. "\n\nORIGINAL")
	check("Responses context is idempotent", context.instructions(context.instructions("ORIGINAL")) == context.instructions("ORIGINAL"))
	local plain = f.env.require("provider/openai").buildBody(recordFor(f), { messages = { { role = "user", content = "PONG" } } })
	check("requests without system instructions receive context", #plain.messages == 2 and plain.messages[1].content == context.text() and plain.messages[2].content == "PONG")
	f.healthy(); f.close()
end)

case("Responses adds context to instructions without changing its input history", function()
	local f = F.new(); local responses = f.env.require("provider/responses")
	local context = f.env.require("provider/opencode_context").text()
	local record = recordFor(f, "https://opencode.ai/inference/v1/responses"); record.model = "muse-spark-1.3-contributor-free"
	local messages = history(); local before = f.h.json.encode(messages)
	local input, instructions = responses.inputFor(messages)
	local body = responses.buildBody(record, { messages = messages, maxTokens = 512 })
	check("original system and developer instructions remain exact", body.instructions == context .. "\n\n" .. instructions)
	check("input items and tool replay remain exact", f.h.json.encode(body.input) == f.h.json.encode(input)
		and body.input[#body.input].type == "function_call_output" and body.input[#body.input].call_id == "call-fixture")
	check("source history remains exact", f.h.json.encode(messages) == before)
	check("Responses compatibility declarations stay unchanged", #body.tools == 7 and body.model == record.model)
	f.healthy(); f.close()
end)

case("Go, AgentRouter and unrelated hosts and routes receive no context", function()
	local f = F.new(); local openai, responses = f.env.require("provider/openai"), f.env.require("provider/responses")
	for _, base in ipairs({ "https://opencode.ai/inference/go/v1", "https://opencode.ai/zen/go/v1",
		"https://agentrouter.org/v1", "https://other.example/inference/openai/v1", "https://opencode.ai/custom/v1",
		"http://opencode.ai/inference/openai/v1", "https://opencode.ai:8443/inference/openai/v1",
		"https://opencode.ai/inference/openai/v1-other" }) do
		local record = recordFor(f, base); local messages = { { role = "system", content = "ORIGINAL" }, { role = "user", content = "hello" } }
		local chatBody = openai.buildBody(record, { messages = messages })
		local responsesBody = responses.buildBody(record, { messages = messages })
		check("non-Zen Chat instructions are unchanged", #chatBody.messages == 2 and chatBody.messages[1].content == "ORIGINAL")
		check("non-Zen Responses instructions are unchanged", responsesBody.instructions == "ORIGINAL")
	end
	f.healthy(); f.close()
end)

case("explicit provider and request body overrides remain authoritative", function()
	local f = F.new(); local openai, responses = f.env.require("provider/openai"), f.env.require("provider/responses")
	local record = recordFor(f)
	local providerMessages, requestMessages = { { role = "system", content = "PROVIDER OVERRIDE" } }, { { role = "system", content = "REQUEST OVERRIDE" } }
	record.params = { messages = providerMessages, instructions = "PROVIDER INSTRUCTIONS", max_tokens = 123 }
	local body = openai.buildBody(record, { messages = history() })
	check("provider messages are not replaced", body.messages == providerMessages and body.max_tokens == 123)
	body = openai.buildBody(record, { messages = history(), extra = { messages = requestMessages, max_tokens = 321 } })
	check("request messages retain precedence", body.messages == requestMessages and body.max_tokens == 321)
	local responsesBody = responses.buildBody(record, { messages = history() })
	check("provider instructions are not replaced", responsesBody.instructions == "PROVIDER INSTRUCTIONS")
	responsesBody = responses.buildBody(record, { messages = history(), extra = { instructions = "REQUEST INSTRUCTIONS" } })
	check("request instructions retain precedence", responsesBody.instructions == "REQUEST INSTRUCTIONS")
	check("override tables remain unmodified", #providerMessages == 1 and #requestMessages == 1 and record.params.instructions == "PROVIDER INSTRUCTIONS")
	f.healthy(); f.close()
end)

case("the actual Zen model dispatch retains key, identity and tool result replay", function()
	local f = F.new(); local record = recordFor(f); local calls, session = 0, nil
	local openai, getHeader = f.env.require("provider/openai"), f.env.require("net/headers").get
	local tools = { { type = "function", ["function"] = { name = "fixture_lookup", description = "Read a synthetic fixture",
		parameters = { type = "object", properties = { key = { type = "string" } }, required = { "key" } } } } }
	f.h.http.handler = function(entry)
		calls = calls + 1
		local body = f.h.json.decode(entry.body)
		check("official model and keyed endpoint remain", body.model == "deepseek-v4.1-flash-free" and entry.url == "https://opencode.ai/inference/openai/v1/chat/completions"
			and getHeader(entry.headers, "Authorization") == "Bearer fixture-zen-key")
		check("existing desktop identity remains", getHeader(entry.headers, "User-Agent") == "opencode/latest/2.0.27/desktop" and getHeader(entry.headers, "x-opencode-client") == "desktop")
		local current = getHeader(entry.headers, "x-opencode-session")
		check("request session remains stable", current and (not session or current == session)); session = current
		check("truthful context reaches the dispatch without replacing instructions", body.messages[1].content == f.env.require("provider/opencode_context").text()
			and body.messages[2].content == "Keep the user's original instructions.")
		check("UAI tool and compatibility tools are declared", #body.tools == 8 and body.tools[1]["function"].name == "fixture_lookup")
		local message = calls == 1 and { role = "assistant", tool_calls = {
			{ id = "call-live-fixture", type = "function", ["function"] = { name = "fixture_lookup", arguments = '{"key":"health"}' } },
		} } or { role = "assistant", content = "PONG" }
		if calls == 2 then check("tool feedback replays with its original identity", body.messages[#body.messages].tool_call_id == "call-live-fixture" and body.messages[#body.messages].content == "PONG") end
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = message, finish_reason = calls == 1 and "tool_calls" or "stop" } } }) }
	end
	local messages = { { role = "system", content = "Keep the user's original instructions." }, { role = "user", content = "Read health" } }
	local first = f.run(function() return openai.complete(record, { messages = messages, tools = tools, stream = true, maxTokens = 512 }) end)
	check("tool call is returned to the normal caller", first and first.toolCalls[1].id == "call-live-fixture")
	messages[#messages + 1] = { role = "assistant", content = first.content, toolCalls = first.toolCalls }
	messages[#messages + 1] = { role = "tool", tool_call_id = "call-live-fixture", content = "PONG" }
	local final = f.run(function() return openai.complete(record, { messages = messages, tools = tools, stream = true, maxTokens = 512 }) end)
	check("tool result returns text without extra dispatches", final and final.content == "PONG" and calls == 2)
	f.healthy(); f.close()
end)

suite.finish()
