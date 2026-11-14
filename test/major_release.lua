-- 4.0.0 integration: local knowledge, compact discovery, migration and questions.
-- Synthetic filesystem/scheduler fixtures; no provider or game traffic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Major release")
local check, case = suite.check, suite.case
local function has(text, needle) return tostring(text or ""):find(needle, 1, true) ~= nil end

case("workspace migration preserves Master Vault notes", function()
	local f = F.new()
	local fs = f.env.require("runtime/fsx")
	local content = "# Kept knowledge\nAn externally edited note.\n"
	assert(fs.write("vault/notes/kept.md", content))
	assert(fs.write("legacy.lua", "return 42"))
	local moved = f.run(function() return fs.migrate() end)
	check("ordinary legacy files still migrate", moved > 0 and fs.read("legacy.lua", { scope = "files" }) == "return 42")
	check("vault stays in its own namespace", fs.read("vault/notes/kept.md") == content
		and not fs.exists("vault/notes/kept.md", { scope = "files" }))
	f.run(function() return fs.migrate() end)
	check("later migration also preserves the exact note bytes", fs.read("vault/notes/kept.md") == content)
	f.healthy(); f.close()
end)

case("knowledge and goals are available through the existing context family", function()
	local f = F.new(); local registry = f.tools({}); registry.loaded = false; registry.load()
	local definitions = registry.definitions({ profile = "focused" })
	local context
	for _, item in ipairs(definitions) do if item["function"].name == "uai_context" then context = item["function"] end end
	local offered = {}
	for _, name in ipairs(context.parameters.properties.name.enum) do offered[name] = true end
	check("new capabilities fit the existing compact declaration budget", #definitions <= 16 and offered.vault_list
		and offered.vault_read and offered.micro_goals_read and offered.micro_goals_update)
	local result = f.dispatch("uai_context", { action = "call", name = "vault_list", arguments = { origin = "starters" } })
	check("bundled knowledge is reachable without HTTP", result.ok and has(result.text, "starter:") and f.h.http.requestCount == 0)
	f.env.require("agent/permissions").setRule("vault_list", "deny")
	check("a denial remains authoritative through the family", not f.dispatch("uai_context", {
		action = "call", name = "vault_list", arguments = {} }).ok)
	f.healthy(); f.close()
end)

case("bounded host listings stop probing beyond the selected inventory", function()
	local f = F.new(); local fs, caps = f.env.require("runtime/fsx"), f.env.require("runtime/caps")
	assert(fs.ensure("UAI/vault/notes"))
	for index = 1, 600 do f.h.files[string.format("UAI/vault/notes/%04d.md", index)] = "# Reference\n\nRetained facts.\n" end
	local probes, original = 0, caps.fn.isfile
	caps.fn.isfile = function(path) probes = probes + 1; return original(path) end
	local bounded, warning = fs.list("vault/notes", { maxEntries = 8 })
	check("only admitted entries are normalized and probed", #bounded == 8 and probes == 8 and has(warning, "incomplete"))
	local complete, why = fs.list("vault/notes")
	check("legacy listings retain their complete behavior", #complete == 600 and why == nil)
	local invalid = fs.list("vault/notes", { maxEntries = math.huge })
	check("an invalid bound does not fall back to unlimited work", #invalid == 0)
	probes = 0
	local vault = f.env.require("runtime/master_vault")
	local page = assert(f.run(function() return vault.list({ origin = "notes" }) end, 2))
	check("Vault discovery reports its capped coverage", page.incomplete and page.total == vault.MAX_NOTES
		and probes <= vault.MAX_ENTRIES + vault.MAX_NOTES)
	check("an incomplete inventory cannot admit a new note", not f.run(function()
		return vault.save({ title = "Extra note", content = "An explicit new note." })
	end, 2))
	f.healthy(); f.close()
end)

case("the main agent delegates Read only or Full access without bypassing denials", function()
	local f = F.new(); local registry = f.tools({ "agentself", "fs", "script", "master_vault", "goals", "ui_mods" })
	local sessions, agents = f.env.require("agent/session"), f.env.require("agent/subagent")
	local parent = assert(sessions.newThread({ id = "access-parent", title = "Access fixture" }))
	local fs = f.env.require("runtime/fsx"); assert(fs.write("delegated.txt", "Original", { scope = "files" }))
	local results = {}
	f.env.require("agent/loop").run = function(child)
		local ctx = child.toolContext()
		local function call(name, args)
			return registry.dispatch({ id = name, name = name, arguments = f.h.json.encode(args or {}) }, ctx)
		end
		local workerIndex = #results + 1
		results[workerIndex] = {
			read = call("file_read", { path = "delegated.txt" }),
			vault = call("vault_list", { origin = "starters" }),
			goals = call("micro_goals_read"),
			mods = call("ui_mod_list"),
			guide = call("scripting_docs", { section = "native_ui_mods", limit = 800 }),
			write = call("file_write", { path = "delegated.txt", content = "Worker " .. workerIndex .. " edit" }),
			execute = call("run_luau", { code = "return 'Executed delegated code'" }),
		}
		return "Access checked"
	end
	local dispatchedIds = {}
	local function delegate(preset)
		local result = f.dispatch("dispatch_agent", { task = "Inspect access and attempt the explicitly assigned fixture edit.",
			preset = preset, background = false }, parent.toolContext(), 1)
		if result.ok then dispatchedIds[#dispatchedIds + 1] = assert(result.text:match("^Subagent report from (%S+)")) end
		return result
	end
	assert(delegate("read").ok)
	check("a read worker can inspect files, knowledge and goals", results[1].read.ok and results[1].vault.ok and results[1].goals.ok)
	check("read access spans mod and source topics without a topic filter", results[1].mods.ok and results[1].guide.ok)
	check("read scope refuses writes and code execution in full permission mode", not results[1].write.ok
		and not results[1].execute.ok and fs.readUser("delegated.txt") == "Original")
	assert(delegate("full").ok)
	check("a full worker can actually apply an authorized file edit", results[2].write.ok and fs.readUser("delegated.txt") == "Worker 2 edit")
	check("full access can run explicitly assigned code", results[2].execute.ok and has(results[2].execute.text, "Executed delegated code"))
	f.env.require("agent/permissions").setRule("file_write", "deny")
	assert(delegate("full").ok)
	check("a full worker still honors tool denials", not results[3].write.ok and results[3].execute.ok and fs.readUser("delegated.txt") == "Worker 2 edit")
	check("delegation retains the selected access by its actual dispatched ID", agents.get(dispatchedIds[1]).preset == "read"
		and agents.get(dispatchedIds[2]).preset == "full" and agents.get(dispatchedIds[3]).preset == "full")
	f.healthy(); f.close()
end)

case("Allow everything still delivers a real question and waits for its answer", function()
	local f = F.new(); f.tools({ "agentself" })
	local shown, answer, done = 0, nil, false
	local ctx = { session = {}, aborted = function() return false end, emit = function(kind, event)
		if kind == "ask:user" then shown = shown + 1; answer = event.resolve end
	end }
	local result
	f.h.sched.spawn(function()
		result = f.registry.dispatch({ id = "question", name = "ask_user", arguments = f.h.json.encode({
			question = "Which configuration should the project use?", options = { "Existing", "New" },
		}) }, ctx)
		done = true
	end)
	f.h.sched.advance(0.2)
	check("full mode presents a question without inventing an answer", shown == 1 and answer ~= nil and not done)
	answer("Existing"); answer("New")
	f.h.sched.advance(0.2)
	check("only the first actual answer settles the question", done and result.ok and result.text == "The user answered: Existing")
	local prompt = f.env.require("agent/prompt").build({ tools = { { name = "ask_user" } } })
	check("system rules retain question handling under full mode", has(prompt, "ask_user") and has(prompt, "Allow everything"))
	f.healthy(); f.close()
end)

case("unanswered required questions provide no answer or consent", function()
	for _, dismiss in ipairs({ false, true }) do
		local f = F.new(); f.tools({ "agentself" })
		local resolve
		local result = f.dispatch("ask_user", { question = "Which target should be changed?" }, {
			session = {}, aborted = function() return false end, emit = function(kind, event)
				if kind == "ask:user" then resolve = event.resolve; if dismiss then resolve("") end end
			end,
		}, dismiss and 0.2 or 602)
		check("absence is explicit and never labelled an answer", result.ok and has(result.text, "No answer or consent was given")
			and not has(result.text, "The user answered:"))
		local original = result.text
		resolve("Late choice"); f.h.sched.advance(0.2)
		check("a late answer cannot replace the delivered result", result.text == original)
		f.healthy(); f.close()
	end
end)

case("question access still respects scope and subagent restrictions", function()
	local f = F.new(); f.tools({ "agentself" })
	local emitted = 0
	local ctx = { session = { headless = true }, aborted = function() return false end,
		emit = function() emitted = emitted + 1 end }
	local result = f.dispatch("ask_user", { question = "Which target?" }, ctx)
	check("workers report missing decisions to their parent", not result.ok and has(result.text, "parent") and emitted == 0)
	ctx.session = { toolGroups = { fs = true } }
	check("full mode does not widen a conversation scope", not f.dispatch("ask_user", { question = "Which target?" }, ctx).ok and emitted == 0)
	f.healthy(); f.close()
end)

suite.finish()
