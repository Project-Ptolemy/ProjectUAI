-- A compact declaration surface over the existing tools. Calls re-enter the exact
-- target's dispatch pipeline, preserving revisions, hooks, permissions and timeouts.
return function(env)
	local util = env.require("runtime/util")
	local schema = env.require("agent/schema")
	local M = {}
	local families = {
		{ name = "uai_files", label = "Read, search and edit workspace files", groups = { fs = true } },
		{ name = "uai_code", label = "Author scripts, manage projects, analyze and test source", groups = { script = true, coding = true, templates = true } },
		{ name = "uai_instances", label = "Inspect and edit the Roblox instance tree and interfaces", groups = { instance = true, gui = true } },
		{ name = "uai_game", label = "Players, character, world, input and screen actions", groups = { players = true, character = true, world = true, input = true, screen = true } },
		{ name = "uai_inspect", label = "Inspect remotes, network captures, performance and evidence", groups = { remotes = true, net_capture = true, perf = true, meta = true, evidence = true, support_bundle = true } },
		{ name = "uai_connect", label = "Web, HTTP, Obsidian vaults and external integrations", groups = { net = true, web = true, obsidian = true } },
		{ name = "uai_automate", label = "In-game chat, chat loops, Infinite Yield and Gravity", groups = { chat = true, iy = true, gravity = true } },
		{ name = "uai_context", label = "Conversations, memory, task lists and skills", groups = { agentself = true, skills = true } },
		{ name = "uai_other", label = "Additional tools registered by the host", groups = {} },
	}
	local direct = { ask_user = true, notify = true, dispatch_agent = true, agent_status = true, agent_followup = true,
		tool_search = true, script_workflow = true }
	local byName = {}; for _, family in ipairs(families) do byName[family.name] = family end
	function M.isFamily(name) return byName[name] ~= nil end
	local function classify(tool)
		for _, family in ipairs(families) do if family.groups[tool.group] then return family.name end end
		return "uai_other"
	end
	local function parameters(names)
		return { type = "object", properties = {
			action = { type = "string", enum = { "list", "describe", "call" }, description = "List actions, inspect an exact schema, or invoke one action." },
			name = { type = "string", enum = names, description = "Exact action name for describe or call." },
			arguments = { type = "object", additionalProperties = true, description = "Arguments matching the action's described schema; required for call." },
			query = { type = "string", maxLength = 256, description = "Optional words, quoted phrases or -exclusions for list." },
			offset = { type = "integer", minimum = 1, description = "Continue a list or schema page at nextOffset." },
		}, required = { "action" }, additionalProperties = false }
	end
	local function buckets(available)
		local grouped = {}
		for _, tool in ipairs(available) do
			if not direct[tool.name] then
				local name = classify(tool); grouped[name] = grouped[name] or {}; grouped[name][#grouped[name] + 1] = tool
			end
		end
		return grouped
	end
	function M.definitions(available, definition)
		local result, grouped = {}, buckets(available)
		for _, tool in ipairs(available) do if direct[tool.name] then result[#result + 1] = definition(tool) end end
		for _, family in ipairs(families) do
			local tools = grouped[family.name]
			if tools then
				local names = {}; for _, tool in ipairs(tools) do names[#names + 1] = tool.name end; table.sort(names)
				result[#result + 1] = { type = "function", ["function"] = { name = family.name, strict = false,
					description = family.label .. ". Use list to find an action, describe for its exact arguments, then call. Reuse schemas already read. Each action retains its normal permissions and conversation scope.", parameters = parameters(names) } }
			end
		end
		return result
	end
	function M.dispatch(call, ctx, registry)
		local fn = call["function"] or call
		local family = byName[fn.name]
		local result = { id = call.id, name = fn.name, ok = false, text = "", ms = 0, risk = "read" }
		local function fail(message) result.text, result.error = message, "invalid family action"; return result end
		if not family then return fail("Unknown tool family") end
		if ctx and ctx.aborted and ctx.aborted() then return fail("Stopped before reading the tool family") end
		local owner = ctx and ctx.session or {}
		if owner.toolExclude and owner.toolExclude[family.name] then return fail("This tool family is excluded from the conversation") end
		local excluded = util.copy(owner.toolExclude or {})
		if owner.named or owner.headless then excluded.conversation_rename = true end
		local available = registry.available({ only = owner.toolFilter, groups = owner.toolGroups, exclude = excluded })
		if ctx and ctx.requestToolNames then
			local scoped = {}; for _, tool in ipairs(available) do if ctx.requestToolNames[tool.name] then scoped[#scoped + 1] = tool end end; available = scoped
		end
		local tools, names, known = buckets(available)[family.name] or {}, {}, {}
		for _, tool in ipairs(tools) do names[#names + 1], known[tool.name] = tool.name, tool end
		if #names == 0 then return fail("No actions in this family are currently available in this conversation") end
		local args, why = schema.repairJson(fn.arguments or call.arguments or "{}", { allowTruncated = false })
		if not args then return fail("Correct the family action JSON: " .. tostring(why)) end
		local errors; args, errors = schema.validate(parameters(names), args)
		if #errors > 0 then return fail(table.concat(errors, "; ")) end
		local H = env.require("tools/helpers")
		if args.action == "call" then
			if not known[args.name] or type(args.arguments) ~= "table" then return fail("call requires an available action name and its arguments object") end
			local target = registry.dispatch({ id = call.id, name = args.name, arguments = util.encode(args.arguments) }, ctx)
			target.targetName, target.name = args.name, family.name
			return target
		elseif args.action == "describe" then
			local tool = known[args.name]; if not tool then return fail("Choose an available action name to describe") end
			local body = util.encode({ name = tool.name, description = tool.description, risk = tool.risk,
				parameters = registry.definition(tool)["function"].parameters, examples = env.require("agent/tool_examples").read(tool) })
			local page = H.readSlice("Action " .. tool.name, body, { offset = args.offset }, 6000)
			result.ok, result.text, result.data = page.ok ~= false, page.text, page.data
		else
			local match, rows = env.require("runtime/search").compile(args.query), {}
			for _, tool in ipairs(tools) do if match(tool.name, tool.description) then rows[#rows + 1] = tool end end
			table.sort(rows, function(a, b) return a.name < b.name end)
			local page = H.page(rows, { offset = args.offset }, family.label, function(tool) return tool.name .. " [" .. tool.risk .. "] " .. util.ellipsis(tool.description, 140) end, 16, 32)
			result.ok, result.text, result.data = page.ok ~= false, page.text, page.data
		end
		return result
	end
	return M
end
