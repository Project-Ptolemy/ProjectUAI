-- Reach hidden profile tools without granting new scope.
--
-- A profile only changes the declarations sent to the provider. Dispatch still
-- checks the same group, permission and conversation scope, so this tool is a
-- discovery surface rather than a permission bypass.
return function(env)
	local registry = env.require("agent/registry")
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")
	local search = env.require("runtime/search")

	local function scope(ctx)
		local owner = ctx and ctx.session or {}
		local definitions = registry.available({ only = owner.toolFilter, groups = owner.toolGroups, exclude = owner.toolExclude })
		local byName, order = {}, {}
		for _, definition in ipairs(definitions) do
			local fn = definition
			if fn.name and not byName[fn.name] then
				byName[fn.name] = registry.get(fn.name)
				order[#order + 1] = fn.name
			end
		end
		return byName, order
	end

	return {
		{
			name = "tool_search",
			risk = "read",
			description = "Find tools hidden by the active tool profile. action=list returns names and one-line descriptions; action=describe returns a tool's exact schema pages; action=call runs that tool with its declared arguments. Hidden tools keep their normal permissions and conversation scope. Core tools are already declared; use this only when the needed tool is absent.",
			parameters = {
				type = "object",
				properties = {
					action = { type = "string", enum = { "list", "describe", "call" } },
					query = { type = "string", maxLength = 256, description = "Words, quoted phrases and -excluded terms across name, description and group; exact names rank first." },
					group = { type = "string", description = "Exact tool group for list." },
					name = { type = "string", description = "Exact tool name for describe or call." },
					arguments = { type = "object", description = "The target tool's exact arguments for call." },
					offset = { type = "integer", minimum = 1, description = "1-based result or schema byte offset." },
					limit = { type = "integer", minimum = 1, maximum = 20000, description = "List rows (max 100) or schema bytes (max 20000, within the result budget); default 20 rows or 6000 bytes." },
				},
				required = { "action" },
			},
			run = function(args, ctx)
				local byName, order = scope(ctx)
				if args.action == "list" then
					local query = util.trim(tostring(args.query or "")):lower()
					local group = util.trim(tostring(args.group or ""))
					local match = search.compile(query)
					local rows = {}
					for _, name in ipairs(order) do
						local tool = byName[name]
						local score = tool and match(name, tool.description, tool.group)
						if score and (group == "" or tool.group == group) then
							rows[#rows + 1] = { name = name, group = tool.group, risk = tool.risk, score = score,
								description = util.ellipsis(tostring(tool.description or ""), 160) }
						end
					end
					if query ~= "" then table.sort(rows, function(a, b)
						if a.score ~= b.score then return a.score > b.score end
						return a.name < b.name
					end) end
					local page = H.page(rows, { offset = args.offset, limit = args.limit }, "Toolbox",
						function(row) return string.format("%s [%s/%s] %s", row.name, tostring(row.group), tostring(row.risk), row.description) end, 20, 100)
					if page.data then page.data.tools = page.data.count end
					return page
				elseif args.action == "describe" then
					local name = tostring(args.name or "")
					if name == "" then return H.fail("name is required for describe") end
					local tool = byName[name]
					if not tool then return H.fail("No tool named '" .. name .. "' is available in this conversation.") end
					local schema = util.encode({ name = tool.name, group = tool.group, risk = tool.risk,
						description = tool.description, examples = env.require("agent/tool_examples").read(tool), parameters = registry.definition(tool)["function"].parameters })
					local page = H.readSlice("Tool schema " .. name, schema, { offset = args.offset, limit = args.limit }, 6000)
					if page.data then page.data.tool = { name = tool.name, group = tool.group, risk = tool.risk, bytes = #schema } end
					return page
				elseif args.action == "call" then
					local name = tostring(args.name or "")
					if name == "" then return H.fail("name is required for call") end
					if name == "tool_search" then return H.fail("tool_search cannot call itself") end
					if not byName[name] then return H.fail("No tool named '" .. name .. "' is available in this conversation.") end
					if args.arguments ~= nil and type(args.arguments) ~= "table" then return H.fail("arguments must be an object") end
					local result = registry.dispatch({ id = "tool_search_call", name = name, arguments = util.encode(args.arguments or util.emptyObject()) }, ctx)
					return { ok = result.ok, text = result.text, data = result.data }
				end
				return H.fail("unknown action")
			end,
		},
	}
end
