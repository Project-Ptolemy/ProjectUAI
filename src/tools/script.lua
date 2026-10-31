-- Running and reading Luau.
--
-- Execution stays behind the danger permission, with captured output, cooperative
-- loop checkpoints and a deadline shared by the script and its spawned tasks.
return function(env)
	local util = env.require("runtime/util")
	local caps = env.require("runtime/caps")
	local H = env.require("tools/helpers")
	local execution = env.require("tools/execution")

	local tools = {
		{
			name = "scripting_docs",
			risk = "read",
			description = "Read the offline guide to the live Roblox environment and script development. Start with quickstart; select environment/capabilities, native workflows, shared state/concurrency, executor APIs with sUNC references, paths, inspection, Luau, cleanup, UI, debugging, projects, editor or verification as needed. Reuse retained sections. No network, filesystem access or execution required.",
			parameters = {
				type = "object",
				properties = {
					section = { type = "string", enum = { "index", "quickstart", "environment_model", "capabilities_and_permissions", "task_routing", "paths_and_tool_calls", "inspection", "native_workflows", "shared_state_and_concurrency", "luau", "executor_apis", "execution_and_cleanup", "ui_scripts", "debugging", "projects", "editor_and_actions", "verification", "tool_reference", "maintaining_the_guide" }, description = "index lists topics; quickstart supplies the normal workflow. Read relevant sections and their continuations, not the whole guide as setup." },
					offset = { type = "integer", minimum = 1, description = "Continue the same section from the returned nextOffset until eof." },
					limit = { type = "integer", minimum = 256, maximum = 16000, description = "Bytes in this page, also bounded by the result budget. Default 3500." },
				},
				required = {},
			},
			run = function(args)
				local docs = env.require("runtime/script_development_docs")
				local section = args.section or "index"
				if section == "index" then
					local rows = { "Project UAI environment and scripting guide", "Guide: " .. docs.url,
						"Read quickstart once, then select only sections needed for this task. Reuse retained instructions.", "Sections:" }
					for _, key in ipairs(docs.order) do rows[#rows + 1] = key .. " - " .. docs.titles[key] end
					rows[#rows + 1] = "Pages use one-based UTF-8 byte offsets. Continue with nextOffset as offset until eof; do not read all topics by default."
					local result = H.readSlice("Scripting guide / index", table.concat(rows, "\n"), args, 3500)
					if result.data then result.data.sections, result.data.url = util.copy(docs.order), docs.url end
					return result
				end
				local source = docs.sections[section]
				if not source then return H.fail("unknown scripting guide section; request index") end
				return H.readSlice("Scripting guide / " .. section, source, args, 3500)
			end,
		},
		{
			name = "run_luau",
			risk = "danger",
			needs = { "exec" },
			description = "Run bounded Luau on the local client. Provide inline source in 'code', or 'path' to run a workspace file directly without reading it back first. Captures print/warn, tables and all return values; waits for functions started with task.spawn/defer/delay. Stop or the deadline cancels managed tasks. Loop checkpoints yield automatically. Prefer a specific tool when one exists. This is not a security sandbox; dynamically loaded code and engine calls can bypass cooperative guards.",
			timeout = function(args) return execution.timeout(args) + 5 end,
			parameters = {
				type = "object",
				properties = {
					code = { type = "string", minLength = 1, maxLength = 256000, description = "The source to run inline. Use print() for output; return values or tables to report results. Provide this or 'path', not both." },
					path = { type = "string", minLength = 1, description = "Use the same files/... or pastes/... path returned by file tools, unchanged (up to 2 MiB). Runs the saved source locally without reading it into the conversation. Provide this or code, not both." },
					timeout = { type = "number", minimum = 1, maximum = 60, description = "Execution deadline in seconds, including spawned tasks. Default 10. Use managed chat tools for persistent chat automation." },
				},
				required = {},
			},
			run = execution.run,
		},
		{
			name = "check_luau",
			examples = { { title = "Compile saved source", arguments = { path = "files/MyProject/main.lua" },
				note = "Use the exact saved path. A successful compile does not execute or verify the requested behavior." } },
			risk = "read",
			needs = { "exec" },
			description = "Check Luau syntax without executing code or changing the game. Provide inline 'code' or a saved file 'path', not both. Prefer path for scripts you wrote or edited so their source need not be sent again. Returns compile errors for correction before run_luau.",
			parameters = {
				type = "object",
				properties = {
					code = { type = "string", minLength = 1, maxLength = 256000, description = "Inline Luau source to compile without running it. Provide this or path." },
					path = { type = "string", minLength = 1, description = "Use the same files/... or pastes/... path returned by file tools, unchanged. Provide this or code." },
				},
				required = {},
			},
			run = execution.checkSource,
		},
		{
			name = "script_list",
			risk = "read",
			description = "List script instances in the place, with their paths. Useful for finding where behaviour lives before reading it.",
			parameters = {
				type = "object",
				properties = {
					root = { type = "string", description = "Where to search. Defaults to game." },
					kind = { type = "string", enum = { "any", "Script", "LocalScript", "ModuleScript" } },
					limit = { type = "integer", minimum = 1, maximum = 100 },
				},
				required = {},
			},
			run = function(args)
				local root, err = H.resolve(args.root or "game")
				if not root then return H.fail(err) end
				local wanted = args.kind
				if not wanted or wanted == "any" then wanted = "LuaSourceContainer" end

				local ok, descendants = pcall(function() return root:GetDescendants() end)
				if not ok then return H.fail("could not read that subtree") end

				local hits = {}
				for _, node in ipairs(descendants) do
					local okA, isA = pcall(function() return node:IsA(wanted) end)
					if okA and isA then hits[#hits + 1] = node end
				end
				if #hits == 0 then return "No scripts found under " .. H.pathOf(root) .. "." end
				return string.format("%d script(s):\n%s", #hits,
					H.list(hits, H.limit(args.limit, 30, 100), function(node)
						return H.pathOf(node) .. " [" .. node.ClassName .. "]"
					end))
			end,
		},
		{
			name = "script_source",
			risk = "read",
			description = "Read a script's source. Works when the host can read or decompile it; when the host has no decompiler or it fails, the bundled luacid client and then the ByteFall service are tried. Many live scripts still cannot be read at all.",
			parameters = {
				type = "object",
				properties = {
					path = { type = "string", description = "Dotted path to the script instance." },
					limit = { type = "integer", description = "Maximum bytes in this slice. Default 3000; also bounded by the tool result budget.", minimum = 200, maximum = 64000 },
					offset = { type = "integer", minimum = 1, description = "1-based byte offset. Use the continuation offset from the previous result to read the next slice." },
				},
				required = { "path" },
			},
			run = function(args, ctx)
				local instance, err = H.resolve(args.path)
				if not instance then return H.fail(err) end
				local sources = env.require("runtime/script_sources")
				local item, why = sources.inspect(env.require("runtime/instance_refs").id(instance), ctx)
				if not item then return H.fail(why) end
				return H.readSlice(item.name, item.source, args, 3000)
			end,
		},
	}
	for _, tool in ipairs(tools) do env.require("tools/script_native").extend(tool) end
	env.require("tools/native_helpers").addReader(tools, "script")
	return tools
end
