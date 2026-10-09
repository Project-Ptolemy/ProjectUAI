-- Focused source-only agent request, repeat detection and workspace prompt checks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Agent efficiency")
local check, case = suite.check, suite.case
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end

local function fixture(handler, model)
	local f = F.new()
	f.tools({})
	local config = f.env.require("runtime/config")
	local providers = f.env.require("provider/registry")
	local record = providers.blank("custom")
	record.model, record.models = model or "efficiency-fixture", { model or "efficiency-fixture" }
	record.baseUrl, record.apiKey = "https://efficiency.test/v1", "fixture-key"
	assert(providers.save(record))
	f.loaded["provider/chat"] = { complete = handler, contextOverflow = function() return false end }
	local session = assert(f.env.require("agent/session").create({ ephemeral = true, maxTurns = 6 }))
	session.systemPrompt = "Fixture instructions."
	return f, config, session, providers.active()
end

local function reply(record, content, calls)
	return { model = record.model, content = content or "Done", reasoning = "", toolCalls = calls or {}, finish = calls and "tool_calls" or "stop" }
end

case("equivalent JSON batches cannot evade repeat detection", function()
	local requests, runs = 0, 0
	local variants = { '{"query":"boat","path":"files/Harbor (42)"}',
		'{"path":"files/Harbor (42)","query":"boat"}', '{ "query" : "boat", "path" : "files/Harbor (42)" }' }
	local f, _, session = fixture(function(record)
		requests = requests + 1
		if requests > #variants then return reply(record) end
		return reply(record, "", { { id = "search_" .. requests,
			["function"] = { name = "file_search", arguments = variants[requests] } } })
	end)
	f.registry.register({ name = "file_search", group = "fs", risk = "read", description = "Fixture search",
		parameters = { type = "object", properties = { query = { type = "string" }, path = { type = "string" } }, required = { "query", "path" } },
		run = function() runs = runs + 1; return "files/Harbor (42)/boat.lua:8: boat found" end })
	f.run(function() return f.env.require("agent/loop").run(session, "Find the boat") end, 1)
	check("only the first two equivalent batches execute", runs == 2 and requests == 4)
	check("the third call receives a usable repeat explanation", has(session.ctx.messages[#session.ctx.messages - 1].content, "same arguments"))
	f.healthy(); f.close()
end)

case("known context windows leave room for the requested reply", function()
	for _, known in ipairs({ true, false }) do
		local captured
		local f, config, session, record = fixture(function(provider, request)
			captured = request
			return reply(provider)
		end)
		config.set("agent.maxTokens", 128000)
		if known then config.set("agent.forceContext", { [record.model] = 4000 }) end
		f.run(function() return f.env.require("agent/loop").run(session, "Make a boat") end)
		local used = f.env.require("agent/usage").estimateMessages(captured.messages)
		if known then
			check("reply budget fits beside the prepared prompt", captured.maxTokens > 0 and used + captured.maxTokens <= 4000)
			check("the adapter receives the temporary context ceiling", captured.outputCeiling and captured.maxTokens <= captured.outputCeiling)
			check("a per-request ceiling never becomes a learned provider cap", record.maxTokensCap == nil)
		else
			check("unknown models retain the configured reply budget", captured.maxTokens == 128000 and captured.outputCeiling == nil)
		end
		f.healthy(); f.close()
	end
end)

case("different JSON array and object arguments remain different operations", function()
	for _, variants in ipairs({
		{ '{"value":["x"]}', '{"value":{"1":"x"}}', '{"value":["x"]}' },
		{ '{"value":[]}', '{"value":{}}', '{"value":[]}' },
	}) do
		local steps, runs = 0, 0
		local f, _, session = fixture(function(record)
			steps = steps + 1
			if steps > #variants then return reply(record) end
			return reply(record, "", { { id = "inspect_" .. steps, ["function"] = { name = "inspect_json", arguments = variants[steps] } } })
		end)
		f.registry.register({ name = "inspect_json", group = "fs", risk = "read", description = "Inspect JSON fixture",
			parameters = { type = "object", properties = { value = {} } }, run = function() runs = runs + 1; return "Inspected" end })
		f.run(function() return f.env.require("agent/loop").run(session, "Inspect these values") end, 1)
		check("different JSON container shapes do not trigger a false repeat refusal", runs == 3)
		f.healthy(); f.close()
	end
end)

case("an irreducible prompt is explained without sending impossible requests", function()
	local calls = 0
	local f, config, session, record = fixture(function(provider) calls = calls + 1; return reply(provider) end)
	config.set("agent.forceContext", { [record.model] = 4000 })
	session.systemPrompt = ("Required instructions. "):rep(1000)
	local result = f.run(function() return f.env.require("agent/loop").run(session, "Continue") end)
	check("no repeated transport calls for an oversized fixed prompt", calls == 0 and has(result, "prepared prompt exceeds"))
	f.healthy(); f.close()
end)

case("a smaller fallback compacts once before its first request", function()
	local primaryCalls, fallbackCalls, summaries = 0, 0, 0
	local f, config, session, primary = fixture(function(provider, request)
		if provider.model == "efficiency-fixture" then primaryCalls = primaryCalls + 1; return nil, "fixture provider unavailable" end
		if request.tools == nil then summaries = summaries + 1; return reply(provider, "Keep the dock. Boat source was inspected.") end
		fallbackCalls = fallbackCalls + 1
		check("fallback receives reduced context and a matching output allowance", request.maxTokens > 0
			and #request.messages < 12)
		return reply(provider)
	end)
	local providers = f.env.require("provider/registry")
	local fallback = providers.blank("custom")
	fallback.model, fallback.models = "small-fallback", { "small-fallback" }
	fallback.baseUrl, fallback.apiKey = "https://small.test/v1", "fixture-key"
	assert(providers.save(fallback)); providers.setActive(primary.id)
	config.set("agent.fallback", true)
	config.set("agent.forceContext", { [fallback.model] = 4000 })
	for index = 1, 8 do session.ctx.pushUser("Inspect " .. index); session.ctx.pushAssistant({ content = ("Evidence. "):rep(500) }) end
	f.run(function() return f.env.require("agent/loop").run(session, "Continue") end)
	check("recovery is bounded and uses the refusing/fallback provider", primaryCalls == 1 and fallbackCalls == 1 and summaries == 1)
	f.healthy(); f.close()
end)

case("compaction sends smaller history and accounts for its own request", function()
	local summaryRequest, mainRequest
	local f, config, session = fixture(function(record, request)
		if request.tools == nil then
			summaryRequest = request
			local result = reply(record, "Inspected files/Harbor (42)/boat.lua; preserve the dock. Continue the requested repair.")
			result.usage = { prompt_tokens = 80, completion_tokens = 20 }
			return result
		end
		mainRequest = request
		local result = reply(record)
		result.usage = { prompt_tokens = 100, completion_tokens = 10 }
		return result
	end)
	config.set("agent.contextTokens", 3000)
	for index = 1, 10 do
		session.ctx.pushUser("Earlier request " .. index)
		session.ctx.pushAssistant({ content = ("Established evidence. "):rep(300) })
	end
	local before = session.ctx.tokens()
	f.run(function() return f.env.require("agent/loop").run(session, "Continue repairing the boat") end)
	check("one bounded summary request precedes the main request", summaryRequest and mainRequest and summaryRequest.maxTokens <= 512
		and summaryRequest.outputCeiling == summaryRequest.maxTokens)
	check("the main request has the merged note and reduced context", has(mainRequest.messages[2].content, "preserve the dock")
		and f.env.require("agent/usage").estimateMessages(mainRequest.messages) < before * 0.5)
	local usage = f.env.require("agent/usage")
	check("the extra call is visible in usage accounting", usage.session.requests == 2 and usage.session.prompt == 180
		and usage.session.completion == 30)
	f.healthy(); f.close()
end)

case("manual compaction failure reports its reason and retains the conversation", function()
	local f, _, session = fixture(function() return nil, "offline" end)
	for index = 1, 6 do session.ctx.pushUser("Request " .. index); session.ctx.pushAssistant({ content = ("Evidence "):rep(100) }) end
	local messages, result = session.ctx.messages, nil
	assert(session.compact(function(changed, summary, reason) result = { changed = changed, summary = summary, reason = reason } end))
	f.h.sched.advance(0.3)
	check("manual failure is a non-destructive explained no-op", result and not result.changed and result.summary == nil
		and has(result.reason, "preserved") and session.ctx.messages == messages and not session.busy)
	f.healthy(); f.close()
end)

case("main and child prompts share the canonical workspace without synchronous name lookups", function()
	local f = F.new()
	local marketplace = f.env.services.MarketplaceService
	local calls = 0
	marketplace.GetProductInfo = function() calls = calls + 1; error("prompt must use cached place metadata") end
	local place = f.env.require("runtime/place")
	place.id, place.name, place.resolved = 42, "Harbor \240\159\154\162", true
	local workspace = f.env.require("runtime/workspace").describe()
	local prompt = f.env.require("agent/prompt")
	for index = 1, 3 do
		local main, child = prompt.build(), prompt.subagent("Repair the boat")
		check("both agents receive the same verbatim path", has(main, "Current game files: " .. workspace.path .. "/")
			and has(child, "Current game files: " .. workspace.path .. "/"))
		check("both prompts replace obsolete prefix workarounds", has(main, "supersedes old path-workaround memories") and has(child, "supersedes old path-workaround memories")
			and has(main, "check_luau and run_luau uses the SAME") and has(child, "real legacy folder"))
		check("pace applies to parent and child", has(main, "Reserve deeper reasoning") and has(child, "Reserve deeper reasoning"))
		check("both agents can choose bulk reads without broad game setup", has(main, "file_read_many") and has(child, "file_read_many")
			and has(main, "Do not inventory or decompile an entire game") and has(child, "do not dump/decompile a whole game"))
	end
	check("rebuilding prompts makes no Marketplace requests", calls == 0)
	f.healthy(); f.close()
end)

case("changing live environment leaves all standing rules in the reusable prefix", function()
	local f = F.new()
	local prompt, place = f.env.require("agent/prompt"), f.env.require("runtime/place")
	local first, child = prompt.build({ model = "first" }), prompt.subagent("First task")
	local boundary, childBoundary = assert(first:find("Environment:", 1, true)), assert(child:find("Environment:", 1, true))
	place.id, place.name = 987, "Different game"
	local nextPrompt, nextChild = prompt.build({ model = "second" }), prompt.subagent("Second task")
	check("main prefix remains byte-identical", first:sub(1, boundary - 1) == nextPrompt:sub(1, boundary - 1))
	check("child prefix remains byte-identical", child:sub(1, childBoundary - 1) == nextChild:sub(1, childBoundary - 1))
	check("dynamic facts still refresh", has(nextPrompt, "Different game") and has(nextPrompt, "model second") and has(nextChild, "Second task"))
	check("working rules precede metadata", has(first:sub(1, boundary - 1), "Do not inventory or decompile an entire game"))
	f.healthy(); f.close()
end)

suite.finish()
