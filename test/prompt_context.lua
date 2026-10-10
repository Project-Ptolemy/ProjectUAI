-- Prompt pressure, scoped request assembly and lossless on-demand memory reads.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Prompt context")
local check, case = suite.check, suite.case
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end

case("prompt size stays bounded and workflows follow the offered tools", function()
	local f = F.new()
	local prompt = f.env.require("agent/prompt")
	local main, child = prompt.build(), prompt.subagent("Repair the boat")
	check("full main and child prompts fit the fixed instruction budget", #main < 12000 and #child < 12500)
	for _, text in ipairs({ main, child }) do
		check("routine Roblox operations do not invite a blanket refusal", has(text, "ordinary client tasks")
			and has(text, "risk label selects its permission handling") and has(text, "not a reason to refuse"))
		check("game rules and replication limits are not blanket prohibitions", has(text, "In-game rules or anticheat are not by themselves a reason to refuse")
			and has(text, "Server authority can limit persistence or replication") and has(text, "effects are local and which the server confirmed"))
	end
	local readOnly = prompt.build({ tools = { { ["function"] = { name = "file_read" } } } })
	check("read tools keep exact file conventions without authoring workflows", has(readOnly, "share one namespace")
		and not has(readOnly, "Script interfaces:") and not has(readOnly, "Modular projects:")
		and not has(readOnly, "Delegation:") and not has(readOnly, "Background chat:"))
	local noTools = prompt.subagent("Explain the result", { tools = {} })
	check("empty tool catalogue is distinct from an unscoped preview", #noTools < #child / 2
		and not has(noTools, "Skills:") and not has(noTools, "Files and source"))
	local author = prompt.build({ tools = { { name = "file_write" }, { name = "project_build" } } })
	check("source authors retain UI and project requirements", has(author, "Project UAI UI LIB")
		and has(author, "project_patch_read") and has(author, "window:OnDestroy"))
	print(string.format("Prompt bytes: main=%d child=%d read-only=%d no-tools-child=%d", #main, #child, #readOnly, #noTools))
	f.healthy(); f.close()
end)

case("memory indices exclude historical prose and never reorder stored entries", function()
	local f = F.new()
	local state, config = f.env.require("agent/state"), f.env.require("runtime/config")
	local entries = {}
	for index = 60, 1, -1 do
		entries[#entries + 1] = { key = string.format("project_%02d_", index) .. ("k"):rep(60), value = ("old_path_workaround "):rep(25), at = index }
	end
	config.set("memory.entries", entries)
	local before = f.h.json.encode(config.get("memory.entries"))
	local index = state.memoryIndex()
	check("key index is bounded and omissions are discoverable", #index <= 2048 and has(index, "more keys") and has(index, "memory_read"))
	check("listing does not mutate stored order", before == f.h.json.encode(config.get("memory.entries")) and state.memoryList()[1].at == 1)
	local prompt = f.env.require("agent/prompt")
	for _, text in ipairs({ prompt.build(), prompt.subagent("Continue") }) do
		check("old prose never becomes prompt instructions", not has(text, "old_path_workaround") and has(text, "Saved memory keys"))
	end
	check("an unavailable memory tool gets no unresolvable index", not has(prompt.build({ tools = {} }), "Saved memory keys"))
	config.set("memory.enabled", false)
	check("disabled memory stays out of prompts", state.memoryIndex() == nil and not has(prompt.build(), "Saved memory keys"))
	f.healthy(); f.close()
end)

case("memory search and exact reads paginate without silent UTF-8 loss", function()
	local f = F.new(); f.tools({ "agentself" })
	local state, config, util = f.env.require("agent/state"), f.env.require("runtime/config"), f.env.require("runtime/util")
	config.set("agent.resultCap", 600)
	local longKey = "legacy_" .. ("key"):rep(900)
	assert(state.remember(longKey, ("\231\149\140\240\159\153\130"):rep(100)))
	assert(state.remember("other", "unrelated"))
	assert(state.remember("target", "Boat[42] " .. ("\231\149\140"):rep(170)))
	local function readAll(args)
		local pieces, offset = {}, 1
		repeat
			args.offset = offset
			local result = f.dispatch("memory_read", args)
			check("memory pages fit the configured result budget", result.ok and not result.truncated and #result.text <= 600)
			check("memory pages preserve UTF-8", util.validUtf8(result.text))
			pieces[#pieces + 1] = assert(result.text:match("^[^\n]*\n(.*)$"))
			local nextOffset = result.data.nextOffset
			check("memory continuation advances or finishes", nextOffset == nil or nextOffset > offset)
			offset = nextOffset
			assert(#pieces < 40, "memory paging stalled")
		until not offset
		return table.concat(pieces)
	end
	check("exact-key pagination preserves even legacy oversized keys", readAll({ key = longKey }) == longKey .. ": " .. state.recall(longKey))
	check("literal search is case insensitive and matches values", readAll({ query = "bOAT[42]" }) == "- target: " .. state.recall("target"))
	check("a key omitted from the prompt remains searchable", readAll({ query = "legacy_" }) == "- " .. longKey .. ": " .. state.recall(longKey))
	local expected = {}
	for _, entry in ipairs(state.memoryList()) do expected[#expected + 1] = "- " .. entry.key .. ": " .. entry.value end
	check("all entries can be read without registry truncation", readAll({}) == table.concat(expected, "\n"))
	check("ambiguous selectors are refused", not f.dispatch("memory_read", { key = "target", query = "boat" }).ok)
	check("invalid continuation is refused", not f.dispatch("memory_read", { key = "target", offset = 10000 }).ok)
	check("missing search matches are explicit", has(f.dispatch("memory_read", { query = "absent" }).text, "No memories match"))
	f.healthy(); f.close()
end)

case("the loop scopes prompt guidance to the same catalogue sent to the provider", function()
	local f = F.new(); f.tools({ "agentself", "skills", "fs" })
	local providers = f.env.require("provider/registry")
	local record = providers.blank("custom")
	record.model, record.models, record.baseUrl, record.apiKey = "prompt-fixture", { "prompt-fixture" }, "https://prompt.test/v1", "fixture-key"
	assert(providers.save(record))
	local captured
	f.loaded["provider/chat"] = { contextOverflow = function() return false end, complete = function(_, request)
		captured = request
		return { model = record.model, content = "Done", reasoning = "", toolCalls = {}, finish = "stop" }
	end }
	local session = assert(f.env.require("agent/session").create({ ephemeral = true, toolFilter = { memory_read = true } }))
	assert(f.env.require("agent/state").remember("boat", "Private historical detail"))
	f.run(function() return f.env.require("agent/loop").run(session, "What is remembered?") end)
	check("the wire catalogue honors the session filter", #captured.tools == 1 and captured.tools[1]["function"].name == "memory_read")
	local system = captured.messages[1].content
	check("the same filter controls specialized prompt text", has(system, "Saved memory keys") and not has(system, "Private historical detail")
		and not has(system, "Skills:") and not has(system, "Files and source") and not has(system, "Modular projects:"))
	f.healthy(); f.close()
end)

case("delegated briefs inherit live settings and their own plan", function()
	local f = F.new(); f.tools({})
	local config, state = f.env.require("runtime/config"), f.env.require("agent/state")
	config.set("agent.replyLanguage", "Spanish")
	config.set("agent.customInstructions", "Keep the dock intact.")
	f.env.context.prompt = "Host owns the dock controller."
	local child, brief
	f.env.require("agent/loop").run = function(session)
		child = session
		state.setTodos({ { text = "Inspect child boat", status = "active" } }, child)
		brief = child.systemPrompt({ tools = {}, model = "worker-model", provider = "Fixture" })
		return "Boat inspected"
	end
	local result = f.run(function() return f.env.require("agent/subagent").dispatch({ task = "Inspect boat", preset = "read" }) end)
	check("dispatch completes with a scoped worker brief", result ~= nil and child ~= nil and not has(brief, "Modular projects:"))
	check("worker inherits host and user instructions and reply language", has(brief, "Host owns the dock controller.")
		and has(brief, "Keep the dock intact.") and has(brief, "Write replies in Spanish"))
	check("worker receives permission mode, identity and its own plan", has(brief, "Permission mode: full")
		and has(brief, "model worker-model via Fixture") and has(brief, "Inspect child boat"))
	check("follow-ups can supersede the original assignment", has(brief, "latest parent request defines the current task"))
	f.healthy(); f.close()
end)

suite.finish()
