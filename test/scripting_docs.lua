-- The detailed guide stays offline and paged, with a short scoped prompt pointer.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h = require("env").new()
local client, why = h.boot("dist/uai.lua")
assert(client, why)
require("password_fixture")(h, client)
h.settle(0.5)
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local tool
for _, candidate in ipairs(client.env.require("tools/script")) do
	if candidate.name == "scripting_docs" then tool = candidate end
end
check("scripting reference is read-only without host capability requirements", tool and tool.risk == "read" and tool.needs == nil)
local docs = client.env.require("runtime/script_development_docs")
local allowed = {}
for _, section in ipairs(tool.parameters.properties.section.enum) do allowed[section] = true end
local index = tool.run({})
for _, name in ipairs(docs.order) do
	check(name .. " is discoverable and accepted by the schema", allowed[name] and docs.sections[name] and index.text:find(name, 1, true))
	allowed[name] = nil
end
allowed.index = nil
check("schema has no stale section names", next(allowed) == nil)
local requests, roots = #h.http.log, #h.coreGui:GetChildren()
for _, name in ipairs({ "quickstart", "environment_model", "native_workflows", "executor_apis", "paths_and_tool_calls", "ui_scripts" }) do
	local offset, count, parts = 1, 0, {}
	repeat
		local result = tool.run({ section = name, offset = offset, limit = 257 })
		assert(result.data and result.data.offset == offset, "unexpected pagination offset")
		parts[#parts + 1] = assert(result.text:match("^[^\n]*\n(.*)$"))
		offset, count = result.data.nextOffset, count + 1
		assert(count < 100, "guide pagination did not finish")
	until not offset
	check(name .. " pages preserve the full UTF-8 guide text", table.concat(parts) == docs.sections[name])
end
check("guide reads perform no network calls or UI mounting", #h.http.log == requests and #h.coreGui:GetChildren() == roots)
check("unknown sections fail clearly", tool.run({ section = "unknown" }).ok == false)
check("offset beyond a section fails clearly", tool.run({ section = "quickstart", offset = #docs.sections.quickstart + 2 }).ok == false)
local config = client.env.require("runtime/config")
local registry = client.env.require("agent/registry")
local previousCap = config.get("agent.resultCap")
config.set("agent.resultCap", 600)
local function dispatchPage(args)
	local result
	h.sched.spawn(function()
		result = registry.dispatch({ id = "guide-page", name = "scripting_docs", arguments = h.json.encode(args) },
			{ session = {}, aborted = function() return false end })
	end)
	h.sched.advance(0.2)
	return assert(result, "guide dispatch did not settle")
end
local indexParts, indexOffset = {}, 1
repeat
	local result = dispatchPage({ section = "index", offset = indexOffset })
	check("index pages fit a small result budget without registry truncation", result.ok and not result.truncated and #result.text <= 600)
	indexParts[#indexParts + 1] = assert(result.text:match("^[^\n]*\n(.*)$"))
	indexOffset = result.data.nextOffset
	assert(#indexParts < 20, "index pagination did not finish")
until not indexOffset
config.set("agent.resultCap", previousCap)
check("small-budget index retains every discoverable section", table.concat(indexParts) == index.text:match("^[^\n]*\n(.*)$"))
local prompt = client.env.require("agent/prompt")
local offered = { { type = "function", ["function"] = { name = "scripting_docs" } } }
local main = prompt.build({ tools = offered })
local child = prompt.subagent("Create a simple script", { tools = offered })
check("both agents discover the on-demand quickstart", main:find("read scripting_docs quickstart", 1, true) and child:find("read scripting_docs quickstart", 1, true))
check("the complete guide is not injected into default prompts", not main:find(docs.sections.quickstart, 1, true) and not child:find(docs.sections.quickstart, 1, true))
check("unavailable guide is not suggested", not prompt.build({ tools = {} }):find("scripting_docs", 1, true))
check("client has no uncaught asynchronous errors", #h.errors() == 0)
client.unload()
print("Scripting guide integration: " .. passed .. " checks passed")
