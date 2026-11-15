-- Long-history estimates and repeated JSON repair against the real source modules.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Long context performance")
local check, case = suite.check, suite.case

case("250K-token history reuses estimates through UI, bridge and request accounting", function()
	local f = F.new()
	local context, usage = f.env.require("agent/context"), f.env.require("agent/usage")
	local ctx, original, visited = context.new(), usage.estimateMessages, 0
	for index = 1, 100 do ctx.push({ role = index % 2 == 0 and "assistant" or "user",
		content = string.format("%04d:", index) .. string.rep("x", 9995) }) end
	local expected = original(ctx.messages)
	check("fixture occupies about one quarter of a million-token context", expected >= 250000 and expected < 251000)
	usage.estimateMessages = function(messages) visited = visited + #(messages or {}); return original(messages) end
	check("the first read measures the whole retained history", ctx.tokens() == expected and visited == 100)
	local record = { id = "fixture", model = "long-context-fixture", baseUrl = "https://fixture.test/v1" }
	local wire = ctx.wire("Standing instructions.")
	local observed = ctx.observeRequest(wire, {}, record)
	ctx.calibrate(observed.history + observed.estimate + 2000, observed)
	visited = 0
	for _ = 1, 30 do
		local values = ctx.breakdown(record)
		check("shared inspector pressure remains exact", values.used == ctx.pressure(record) and values.messages == expected)
		local stats = ctx.stats()
		check("statistics retain their measured categories", stats.turns == 50 and stats.messages == 100 and stats.tokens == expected)
	end
	check("unchanged UI/bridge refreshes do not re-estimate the history", visited == 0)
	visited = 0; observed = ctx.observeRequest(wire, {}, record)
	check("request preparation only measures its new instruction message", visited == 1 and observed.history == expected)
	local copy = f.env.require("runtime/util").deepCopy(wire)
	copy[#copy].content = "A hook replacement."
	visited = 0; local hooked = ctx.observeRequest(copy, {}, record)
	check("detached hook messages get fresh estimates without changing stored history", visited == #copy
		and hooked.history == expected and ctx.messages[#ctx.messages].content ~= copy[#copy].content)
	usage.estimateMessages = original; f.healthy(); f.close()
end)

case("public in-place edits and mutable content invalidate the correct estimate", function()
	local f = F.new(); local usage = f.env.require("agent/usage")
	local ctx = f.env.require("agent/context").new()
	ctx.pushUser("Original user request")
	local call = { id = "c1", ["function"] = { name = "inspect", arguments = '{"path":"old"}' } }
	ctx.pushAssistant({ content = "Original answer", toolCalls = { call }, reasoning = "Original reasoning" })
	ctx.pushToolResult("c1", "inspect", "Original evidence")
	ctx.tokens()
	local function exact(label) check(label, ctx.tokens() == usage.estimateMessages(ctx.messages)) end
	ctx.messages[1].content = string.rep("Edited user wording ", 100); exact("replacing an existing prose string is observed")
	ctx.messages[2].reasoning = string.rep("Edited reasoning ", 90); exact("reasoning edits are observed")
	call["function"].arguments = '{"path":"new longer path"}'; exact("JSON call argument edits are observed")
	call["function"].name = "a_different_tool"; exact("tool name edits are observed")
	ctx.messages[1].images = { { url = "fixture-one" } }; exact("image count edits are observed")
	ctx.messages[1].images[2] = { url = "fixture-two" }; exact("in-place image additions are observed")
	call["function"].arguments = { path = "Nested table" }; ctx.tokens()
	call["function"].arguments.path = string.rep("A much longer nested path ", 50); exact("mutable argument tables cannot reuse a stale estimate")
	ctx.messages[1].content = { { type = "text", text = "Structured content" } }; ctx.tokens()
	ctx.messages[1].content[1].text = string.rep("Changed structured content ", 100); exact("mutable content blocks cannot reuse a stale estimate")
	ctx.messages[1].role = "assistant"
	check("role changes update statistics", ctx.stats().turns == 0)
	ctx.messages = { { role = "user", content = "Replaced history" } }; exact("a replaced public history releases older estimates")
	ctx.clear(); check("clear releases all cached totals", ctx.tokens() == 0 and ctx.stats().messages == 0)
	f.healthy(); f.close()
end)

case("tool repair, trimming, compaction and restore preserve accurate cached totals", function()
	local f = F.new(); local context, usage = f.env.require("agent/context"), f.env.require("agent/usage")
	local ctx = context.new()
	ctx.pushUser("Inspect the fixture")
	ctx.pushAssistant({ content = "", toolCalls = {
		{ id = "present", ["function"] = { name = "inspect", arguments = "{}" } },
		{ id = "missing", ["function"] = { name = "inspect", arguments = "{}" } },
	} })
	ctx.pushToolResult("present", "inspect", "Observed evidence")
	ctx.pushUser("Continue")
	ctx.tokens(); local wire = ctx.wire("Instructions")
	check("repair adds its missing outcome to the next estimate", #wire == 6 and ctx.tokens() == usage.estimateMessages(ctx.messages))
	for index = 1, 20 do ctx.pushUser("Request " .. index); ctx.pushAssistant({ content = string.rep("Retained evidence ", 500) }) end
	local before = ctx.tokens()
	assert(ctx.compact(function() return "Earlier evidence was reviewed. Continue the latest request." end, { tokenLimit = 8000 }))
	check("committed compaction retires removed estimates", ctx.tokens() < before and ctx.tokens() == usage.estimateMessages(ctx.messages) + usage.estimateText(ctx.summary))
	local restored = context.new(); assert(restored.restore(ctx.serialise()))
	check("restore reconstructs the exact reduced context", restored.tokens() == ctx.tokens())
	restored.trim(1000, 1, false)
	check("legacy trimming invalidates replaced and shortened evidence", restored.tokens() == usage.estimateMessages(restored.messages) + usage.estimateText(restored.summary))
	f.healthy(); f.close()
end)

case("repeated JSON encoding reuses bounded UTF-8 repair and cleanup releases it", function()
	local f = F.new(); local util = f.env.require("runtime/util")
	local find, scanned = string.find, 0
	string.find = function(source, pattern, ...)
		if #source >= 256 and pattern == "[\128-\255]" then scanned = scanned + 1 end
		return find(source, pattern, ...)
	end
	local ok, why = pcall(function()
		util.clearTextCache()
		local source = string.rep("caf\195\169 data ", 4000)
		local invalid = string.rep("invalid-byte-" .. string.char(255), 2000)
		local payload = { messages = { { role = "user", content = source }, { role = "tool", content = invalid } } }
		local first = util.encode(payload)
		check("first encoding validates and repairs the actual strings", scanned > 0)
		scanned = 0; check("cached encoding preserves exact JSON bytes", util.encode(payload) == first and scanned == 0)
		local decoded = util.decode(first)
		check("cache retains Unicode and repaired output", decoded.messages[1].content == source and decoded.messages[2].content == (util.sanitise(invalid)))
		for index = 1, 300 do util.sanitise(string.format("%04d:", index) .. string.rep("record ", 50)) end
		scanned = 0; util.sanitise(source)
		check("the count bound evicts older immutable strings", scanned > 0)
		local large = {}; for index = 1, 3 do large[index] = string.rep("z", 2 * 1024 * 1024 - 8) .. tostring(index); util.sanitise(large[index]) end
		scanned = 0; util.sanitise(large[1])
		check("the byte bound evicts long strings before count capacity", scanned > 0)
		util.sanitise(source); scanned = 0; util.clearTextCache(); util.sanitise(source)
		check("lifecycle cleanup releases retained repair outcomes", scanned > 0)
	end)
	string.find = find
	assert(ok, why); f.healthy(); f.close()
end)

suite.finish()
