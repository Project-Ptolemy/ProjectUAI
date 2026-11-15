-- Focused behavioral regressions for validated agent/transport audit findings.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Agent audit")
local case, check = suite.case, suite.check

case("read preset cannot acquire mutations from an allowed group", function()
	local f = F.new(); f.tools({})
	local calls = 0
	for _, risk in ipairs({ "read", "write", "danger" }) do
		f.registry.register({ name = "fixture_" .. risk, group = "fs", risk = risk,
			description = "Scope fixture", run = function() calls = calls + 1; return "done" end })
	end
	local agents = f.env.require("agent/subagent")
	f.loaded["agent/loop"] = { run = function() f.h.sched.wait(1); return "done" end }
	local record = assert(agents.start({ task = "Inspect files" }))
	local child = record.session
	local definitions = f.registry.definitions({ only = child.toolFilter, groups = child.toolGroups, exclude = child.toolExclude })
	check("read catalogue contains only the inspection", #definitions == 1 and definitions[1]["function"].name == "fixture_read")
	for _, risk in ipairs({ "write", "danger" }) do
		local result = f.dispatch("fixture_" .. risk, {}, { session = child, aborted = function() return false end }, 0)
		check("direct dispatch also enforces " .. risk .. " exclusion", not result.ok and result.error == "tool disabled" and calls == 0)
	end
	local before = #agents.records
	local invalid, why = agents.start({ task = "Inspect", preset = "raed" })
	check("unknown presets fail before registration", invalid == nil and tostring(why):find("unknown subagent preset", 1, true) and #agents.records == before)
	agents.stop(record.id)
	f.healthy(); f.close()
end)

case("memory key normalization agrees across write read and delete", function()
	local f = F.new(); f.tools({ "agentself" })
	local state = f.env.require("agent/state")
	assert(state.remember(" my  key ", "retained value"))
	check("runtime reads normalize spaces", state.recall("my key") == "retained value" and state.recall("my_key") == "retained value")
	local result = f.dispatch("memory_read", { key = " my key " })
	check("tool exact-key reads use the same key", result.ok and result.text:find("retained value", 1, true))
	check("delete normalizes the original key", state.forget(" my key ") and state.recall("my_key") == nil)
	f.env.require("runtime/config").set("memory.entries", { { key = "legacy key", value = "legacy value", at = 1 } })
	check("literal legacy keys remain readable", state.recall("legacy key") == "legacy value"
		and f.dispatch("memory_read", { key = "legacy key" }).text:find("legacy value", 1, true))
	check("literal legacy keys remain removable", state.forget("legacy key"))
	f.healthy(); f.close()
end)

case("truncated read arguments never drop a target or filter", function()
	local f = F.new(); f.tools({})
	local calls = 0
	f.registry.register({ name = "fixture_read", group = "fs", risk = "read", description = "Read fixture",
		parameters = { type = "object", properties = { path = { type = "string" }, filter = { type = "string" } } },
		run = function() calls = calls + 1; return "done" end })
	for _, raw in ipairs({ '{"path":"files/target.lua", "filter":', '{"path":"files/target.lua"' }) do
		local result = f.run(function()
			return f.registry.dispatch({ id = "partial", name = "fixture_read", arguments = raw })
		end)
		check("incomplete call rejected without execution", not result.ok and result.error == "bad arguments" and calls == 0)
	end
	local result = f.run(function()
		return f.registry.dispatch({ id = "complete", name = "fixture_read", arguments = '{"path":"files/target.lua",}' })
	end)
	check("complete formatting repairs still work", result.ok and calls == 1)
	f.healthy(); f.close()
end)

case("successful reply metadata cannot supply a retry reason", function()
	local f = F.new()
	local http, encode = f.env.require("net/http"), f.h.json.encode
	for _, body in ipairs({
		{ choices = { { message = { content = "please try again" } } } },
		{ error = { message = "Invalid request", code = "bad_input" }, help = "please try again" },
		{ error = false, message = "Done", help = "server_error" },
	}) do
		check("benign/error metadata does not trigger a retry", not http.shouldRetry({ ok = true, status = 200, body = encode(body) }))
	end
	for _, problem in ipairs({ { message = "temporarily unavailable" }, { code = "rate_limit" }, { type = "overloaded_error" } }) do
		check("actual structured transient error remains retryable", http.shouldRetry({ ok = true, status = 200, body = encode({ error = problem }) }))
	end
	f.healthy(); f.close()
end)

case("OpenCode compatibility declarations coexist with UAI tools", function()
	local f = F.new()
	local registry = f.env.require("provider/registry")
	local record = registry.blank("zen")
	local adapter = f.env.require("provider/openai")
	local tools = { { type = "function", ["function"] = { name = "file_read", parameters = { type = "object" } } } }
	local body = adapter.buildBody(record, { messages = {}, tools = tools, stream = false })
	local names = {}
	for _, tool in ipairs(body.tools or {}) do names[tool["function"].name] = true end
	check("workaround declarations remain alongside authorized tools", names.file_read and names.bash and names.read and names.edit and names.glob and names.grep and names.list and #tools == 1)
	check("OpenCode workaround retains streaming", body.stream and body.stream_options.include_usage)
	check("tool-free requests retain the OpenCode workaround", #adapter.buildBody(record, { messages = {}, tools = {} }).tools > 0)
	record.baseUrl = "https://fixture.test/v1"
	check("other endpoints receive only UAI tools", #adapter.buildBody(record, { messages = {}, tools = tools }).tools == 1)
	f.healthy(); f.close()
end)

case("prompt exact tool names do not match unrelated prefixes", function()
	local f = F.new()
	local prompt = f.env.require("agent/prompt")
	local scoped = prompt.build({ tools = { { name = "memory_read" } } })
	check("memory-only scope has no unavailable mutations", not scoped:find("todo_write", 1, true) and not scoped:find("conversation_rename", 1, true))
	check("similarly named tool cannot enable delegation", not prompt.build({ tools = { { name = "agent_status_extra" } } }):find("Delegation:", 1, true))
	check("source workflow explains Lua and compilation limits", prompt.build({ tools = { { name = "run_luau" } } }):find("check_luau compiles without API/type checks", 1, true))
	f.healthy(); f.close()
end)

suite.finish()
