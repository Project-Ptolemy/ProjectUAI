-- Tool registry and dispatch.
--
-- Owns the whole path from "the model asked for a tool" to "here is a string it
-- can read": argument repair, schema validation, capability gating, the
-- permission prompt, hooks, a timeout, error capture and truncation. The loop
-- calls runAll and gets results; it never touches a handler directly.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local schema = env.require("agent/schema")
	local permissions = env.require("agent/permissions")
	local hooks = env.require("agent/hooks")

	local M = {
		tools = {},
		order = {},
		loaded = false,
	}
	local registrations, sequence = {}, 0
	local HOST_ACTION_TOOL = "opencode_host_action"

	function M.register(tool)
		if type(tool) ~= "table" or type(tool.name) ~= "string" or util.trim(tool.name) == "" or type(tool.run) ~= "function" then
			log.warn("tools", "ignored a malformed tool definition")
			return false
		end
		if tool.name == HOST_ACTION_TOOL then
			log.warn("tools", "reserved tool name: " .. tool.name)
			return false
		end
		if env.require("agent/tool_families").isFamily(tool.name) then
			log.warn("tools", "reserved tool family name: " .. tool.name); return false
		end
		if M.tools[tool.name] then
			log.warn("tools", "duplicate tool name: " .. tool.name)
			return false
		end
		tool.risk = tool.risk or "write"
		tool.group = tool.group or "misc"
		tool.parameters = tool.parameters or { type = "object", properties = util.emptyObject(), required = {} }
		M.tools[tool.name] = tool
		sequence = sequence + 1
		registrations[tool.name] = sequence
		M.order[#M.order + 1] = tool.name
		return true
	end

	-- The optional identity protects an owner's cleanup from removing a later
	-- replacement. Revocation also settles prompts for this exact definition.
	function M.unregister(name, expectedDefinition)
		if type(name) ~= "string" then return false end
		M.load()
		local tool = M.tools[name]
		if not tool or (expectedDefinition ~= nil and tool ~= expectedDefinition) then return false end
		M.tools[name], registrations[name] = nil, nil
		for index, candidate in ipairs(M.order) do
			if candidate == name then table.remove(M.order, index); break end
		end
		local pending = {}
		for _, entry in pairs(permissions.pending) do
			if entry.tool == tool then pending[#pending + 1] = entry end
		end
		for _, entry in ipairs(pending) do entry.cancel() end
		return true
	end

	function M.load()
		if M.loaded then return M end
		M.loaded = true
		local groups = env.require("tools/init")
		for _, tool in ipairs(groups.all()) do M.register(tool) end
		log.info("tools", util.pluralise(#M.order, "tool") .. " registered")
		return M
	end

	function M.get(name)
		M.load()
		return M.tools[name]
	end

	function M.list()
		M.load()
		local out = {}
		for _, name in ipairs(M.order) do out[#out + 1] = M.tools[name] end
		return out
	end

	function M.missingCapability(tool)
		for _, key in ipairs(tool.needs or {}) do
			if not caps.has(key) then return key end
		end
		return nil
	end

	-- Groups the user has switched off.
	--
	-- A whole family of tools is a coarser thing to turn off than a permission rule
	-- and it answers a different question: a rule decides whether a call is allowed,
	-- this decides whether the model is told the tool exists at all. Somebody who does
	-- not want the agent touching remotes in this game wants the second one.
	local GROUP_LABELS = {
		agentself = "Agent",
		instance = "Instance tree",
		script = "Code",
		coding = "Code workspace",
		fs = "Files",
		obsidian = "Obsidian vaults",
		net = "HTTP",
		web = "Web",
		players = "Players",
		character = "Character",
		world = "World",
		remotes = "Remotes",
		net_capture = "Network capture",
		evidence = "Evidence",
		support_bundle = "Support",
		gui = "Interface",
		perf = "Diagnostics",
		meta = "Metadata",
		chat = "In-game chat",
		input = "Virtual input",
		templates = "Templates",
		screen = "Screen & aiming",
		iy = "Infinite Yield",
		gravity = "Project Gravity",
		skills = "Skills",
	}

	M.GROUP_LABELS = GROUP_LABELS

	function M.groupLabel(group)
		return GROUP_LABELS[group] or tostring(group)
	end

	local function disabledGroups()
		local stored = config.get("agent.disabledGroups", {})
		if type(stored) ~= "table" then return {} end
		return stored
	end

	function M.groupEnabled(group)
		return disabledGroups()[tostring(group)] ~= true
	end

	function M.setGroupEnabled(group, enabled)
		local list = util.copy(disabledGroups())
		if enabled == false then
			list[tostring(group)] = true
		else
			list[tostring(group)] = nil
		end
		config.set("agent.disabledGroups", list)
		return enabled ~= false
	end

	-- Every group the registry knows about, with what is in it and whether it is on.
	function M.groups()
		M.load()
		local byGroup, order = {}, {}
		for _, tool in ipairs(M.list()) do
			local entry = byGroup[tool.group]
			if not entry then
				entry = {
					id = tool.group,
					label = M.groupLabel(tool.group),
					total = 0,
					unavailable = 0,
					enabled = M.groupEnabled(tool.group),
				}
				byGroup[tool.group] = entry
				order[#order + 1] = entry
			end
			entry.total = entry.total + 1
			if M.missingCapability(tool) then entry.unavailable = entry.unavailable + 1 end
		end
		table.sort(order, function(a, b) return a.label < b.label end)
		return order
	end

	-- Keywords whose value is a JSON array. Everything else in a schema that is an
	-- empty table wants to encode as {}, not [].
	local SCHEMA_ARRAYS = {
		required = true, enum = true, examples = true,
		allOf = true, anyOf = true, oneOf = true, prefixItems = true,
	}

	-- An empty Luau table encodes as [], and a strict validator -- draft 2020-12,
	-- which Anthropic-on-Bedrock enforces and which answers with a bare
	-- TOOL_SCHEMA_INVALID -- rejects [] anywhere a schema or a property map belongs.
	-- Marking the empty table fixes it, but doing that only for a top-level
	-- `properties` leaves `items` and every nested schema broken, and relies on each
	-- of sixty-odd tool authors remembering. So the whole tree is walked here once,
	-- on the way out, and the tools stay free to write the obvious `{}`.
	local function normaliseSchema(node, depth)
		depth = (depth or 0) + 1
		if depth > 32 or type(node) ~= "table" or util.isEmptyObject(node) then return node end
		local out = {}
		for key, value in pairs(node) do
			if type(value) ~= "table" or util.isEmptyObject(value) then
				out[key] = value
			elseif util.count(value) == 0 and not SCHEMA_ARRAYS[key] then
				out[key] = util.emptyObject()
			else
				out[key] = normaliseSchema(value, depth)
			end
		end
		return out
	end

	-- The definition list the provider sees.
	--
	-- Tools the host cannot run are omitted rather than described-and-refused: a
	-- model shown a tool will use it, and a turn spent learning that writefile does
	-- not exist here is a wasted turn. Discovery and dispatch share one permission
	-- decision, including explicit rules overriding the base mode.
	function M.available(opts)
		opts = opts or {}
		M.load()
		local profile
		if opts.profile and opts.profile ~= "all" then
			profile = env.require("agent/tool_profiles").get(opts.profile)
		end
		local out = {}
		for _, name in ipairs(M.order) do
			local tool = M.tools[name]
			local allow = true
			-- The toolbox is the one declared tool a preset may add without gaining
			-- the rest of the agent family. Its own calls still use the target's
			-- groups and scope, so this does not widen a subagent's access.
			local toolbox = name == "tool_search"
			if profile and not toolbox and not profile.tools[name] and not profile.groups[tool.group] then allow = false end
			if M.missingCapability(tool) then allow = false end
			if permissions.check(tool) == "deny" then allow = false end
			if not M.groupEnabled(tool.group) then allow = false end
			if opts.only and not opts.only[name] then allow = false end
			-- A tool that must not exist for this conversation at all -- ask_user in a
			-- subagent, which has no user to ask. Omission rather than refusal: a model
			-- shown a tool will use it, and a turn spent learning the tool says no is a
			-- wasted turn, which is the same reasoning as a missing capability.
			if opts.exclude and opts.exclude[name] then allow = false end
			if opts.groups and not opts.groups[tool.group] and not toolbox then allow = false end
			if allow then
				out[#out + 1] = tool
			end
		end
		return out
	end

	-- Materialize only requested schemas. Discovery can use available() without
	-- cloning every nested declaration merely to read names and descriptions.
	function M.definition(tool)
		return { type = "function", ["function"] = {
			name = tool.name, description = tool.description,
			parameters = normaliseSchema(tool.parameters),
		} }
	end
	function M.examples(tool) return env.require("agent/tool_examples").text(tool) end

	function M.definitions(opts)
		if opts and opts.profile == "focused" then
			local scope = util.copy(opts); scope.profile = nil
			return env.require("agent/tool_families").definitions(M.available(scope), M.definition)
		end
		local out = {}
		for _, tool in ipairs(M.available(opts)) do out[#out + 1] = M.definition(tool) end
		return out
	end

	function M.stats()
		M.load()
		local byGroup, byRisk, unavailable = {}, {}, {}
		for _, tool in ipairs(M.list()) do
			byGroup[tool.group] = (byGroup[tool.group] or 0) + 1
			byRisk[tool.risk] = (byRisk[tool.risk] or 0) + 1
			local missing = M.missingCapability(tool)
			if missing then unavailable[#unavailable + 1] = { name = tool.name, needs = missing } end
		end
		return { total = #M.order, byGroup = byGroup, byRisk = byRisk, unavailable = unavailable }
	end

	-- OpenCode's required declarations are not local aliases. If a model still
	-- calls one, point it at real tools without widening this conversation's scope.
	local COMPATIBILITY_TOOLS = {
		bash = { "run_luau", "check_luau", "code_run" },
		read = { "file_read", "file_read_many", "code_read" },
		edit = { "file_edit", "file_edit_many", "file_write", "code_edit", "code_write" },
		glob = { "file_list", "file_search" },
		grep = { "file_search", "code_search" },
		list = { "file_list", "code_tabs" },
	}
	local HOST_TOOL_SUGGESTIONS = {
		execute = { "run_luau", "check_luau", "code_run" },
		terminal = { "run_luau", "check_luau", "code_run" },
		shell = { "run_luau", "check_luau", "code_run" },
		filesystem = { "file_read", "file_read_many", "file_list", "file_search", "file_edit", "file_write" },
		search = { "file_search", "code_search", "instance_find", "web_search" },
		task = { "dispatch_agent", "agent_status", "agent_followup" },
		web = { "web_search", "web_read", "http_get" },
		websearch = { "web_search" },
		webfetch = { "web_read", "http_get" },
		skill = { "skills_list", "skills_read" },
		question = { "ask_user" },
		permission = { "ask_user" },
		plan = { "todo_write", "todo_read" },
		todowrite = { "todo_write" },
		todoread = { "todo_read" },
	}
	local function unknownToolMessage(name, ctx, hostAction)
		local owner = ctx and ctx.session or {}
		local definitions = M.definitions({ only = owner.toolFilter, groups = owner.toolGroups, exclude = owner.toolExclude })
		local available, names, seen = {}, {}, {}
		for _, definition in ipairs(definitions) do available[definition["function"].name] = true end
		local function add(candidate)
			if available[candidate] and not seen[candidate] and #names < 12 then
				names[#names + 1], seen[candidate] = candidate, true
			end
		end
		local suggestions = COMPATIBILITY_TOOLS[name] or (hostAction and HOST_TOOL_SUGGESTIONS[name]) or {}
		for _, candidate in ipairs(suggestions) do add(candidate) end
		for _, definition in ipairs(definitions) do add(definition["function"].name) end
		local message = hostAction and string.format("OpenCode desktop tool '%s' was blocked before execution. "
			.. "Continue with the available Roblox tools using their declared arguments.", name)
			or string.format("No local tool named '%s'. This call did not run.", name)
		if not hostAction and COMPATIBILITY_TOOLS[name] then
			message = message .. " OpenCode may advertise this name only for provider compatibility."
		end
		if hostAction and (name == "execute" or name == "terminal" or name == "shell" or name == "bash") then
			message = message .. " Desktop commands and host code are not Luau source."
		end
		if #names > 0 then
			return message .. " Available tools include: " .. table.concat(names, ", ")
				.. ". Use their declared arguments."
				.. (not hostAction and name == "bash" and " Shell commands are not Luau source." or "")
		end
		return message .. " No tools are available in this conversation."
	end

	-- One call. Always returns a result table; never raises.
	local function dispatch(call, ctx)
		local fn = call["function"] or {}
		local name = fn.name or call.name or "unknown"
		local started = clock.ms()
		local result = { id = call.id, name = name, ok = false, text = "", ms = 0 }
		local access = config.accessProblem()
		if access then result.error, result.text = "vault required", access; return result end
		M.load()

		-- This is a refusal receipt from the native tunnel, never an executable
		-- tool. Reserve it before lookup even if a host directly mutates the registry.
		if name == HOST_ACTION_TOOL then
			local raw = fn.arguments or call.arguments or "{}"
			local args = type(raw) == "string" and #raw <= 4096 and util.decode(raw) or nil
			local nativeName = type(args) == "table" and type(args.name) == "string"
				and args.name:sub(1, 100):gsub("[^%w_.-]", "") or "unknown"
			if nativeName == "" then nativeName = "unknown" end
			result.text = unknownToolMessage(nativeName, ctx, true)
			result.error = "OpenCode host action"
			result.ms = clock.since(started)
			return result
		end
		if env.require("agent/tool_families").isFamily(name) then return env.require("agent/tool_families").dispatch(call, ctx, M) end

		local tool = M.tools[name]
		local registration = registrations[name]
		if not tool then
			result.text = unknownToolMessage(name, ctx)
			result.error = "unknown tool"
			result.ms = clock.since(started)
			return result
		end
		result.risk = tool.risk
		result.group = tool.group

		-- Advertised tools can become stale while a request or approval is pending.
		-- Enforce the conversation's actual scope at dispatch as well as discovery.
		local function blocked()
			local owner = ctx and ctx.session
			local reason
			local access = config.accessProblem()
			if access then
				result.error, result.text = "vault required", access
			elseif M.tools[name] ~= tool or registrations[name] ~= registration then
				result.error = "tool unregistered"
				result.text = name .. " was unregistered before it ran. Do not retry this call."
			elseif ctx and ctx.aborted and ctx.aborted() then
				result.error = "aborted"
				result.text = "Stopped before " .. name .. " ran."
			elseif not M.groupEnabled(tool.group) then
				reason = "its tool group is disabled"
			elseif owner and ((owner.toolFilter and not owner.toolFilter[name])
				or (owner.toolGroups and not owner.toolGroups[tool.group])
				or (owner.toolExclude and owner.toolExclude[name])) then
				reason = "it is outside this conversation's tool scope"
			elseif ctx and ctx.requestToolNames and not ctx.requestToolNames[name] then
				reason = "it was not available for this request"
			else
				return false
			end
			if reason then
				result.error = "tool disabled"
				result.text = name .. " was not run: " .. reason .. ". Do not retry it in this conversation."
			end
			result.ms = clock.since(started)
			return true
		end
		if blocked() then return result end

		local missing = M.missingCapability(tool)
		if missing then
			result.text = string.format("%s is unavailable: %s. Do not retry this tool.",
				name, caps.reason(missing))
			result.error = "capability missing"
			result.ms = clock.since(started)
			return result
		end

		-- Completing interrupted arguments can drop a target or filter even on
		-- reads. Keep formatting repairs, but never invent a call's missing tail.
		local args, repairNote = schema.repairJson(fn.arguments or call.arguments or "{}", {
			allowTruncated = false,
		})
		if args == nil then
			result.text = string.format("Could not read the arguments for %s: %s. Send valid JSON.",
				name, tostring(repairNote))
			result.error = "bad arguments"
			result.ms = clock.since(started)
			return result
		end
		if repairNote then log.debug("tools", name .. ": " .. repairNote) end

		local coerced, errors = schema.validate(tool.parameters, args)
		if #errors > 0 then
			result.text = string.format("%s was called with invalid arguments: %s",
				name, table.concat(errors, "; "))
			result.error = "invalid arguments"
			result.args = coerced
			result.ms = clock.since(started)
			return result
		end
		result.args = coerced

		-- Read-only target binding before a permission yield. Native operations keep
		-- exact IDs/observations here, never silently resolve a replacement path later.
		local prepared
		if tool.prepare then
			local preparedOk, value, why = pcall(tool.prepare, coerced, ctx)
			if not preparedOk or not value then
				result.text = tostring(preparedOk and why or value)
				result.error = "preflight failed"
				return result
			end
			prepared = value
		end
		if blocked() then return result end

		local payload = { tool = tool, args = coerced, ctx = ctx, reason = nil }
		local allowedByHooks = hooks.run("preTool", payload)
		if blocked() then return result end
		if not allowedByHooks then
			result.text = string.format("%s was blocked by a host hook%s.", name,
				payload.reason and (": " .. tostring(payload.reason)) or "")
			result.error = "vetoed"
			result.ms = clock.since(started)
			return result
		end

		local allowed, source = permissions.request(tool, coerced, ctx)
		if blocked() then return result end
		if not allowed then
			result.error = "denied"
			result.denied = true
			if source == "timeout" then
				result.text = "Approval for " .. name .. " timed out without a user response."
				result.error, result.denied = "approval timeout", nil
			elseif source == "cancelled" or source == "aborted" then
				result.text = "Approval for " .. name .. " was cancelled before a user decision."
				result.error, result.denied = "approval cancelled", nil
			elseif source == "mode" then
				result.text = name .. " is blocked by permission mode " .. permissions.mode() .. "."
			elseif source == "rule" then
				result.text = name .. " is blocked by a saved permission rule."
			else
				result.text = "The user did not approve " .. name .. "."
			end
			result.text = result.text .. " This call did not run. Continue other allowed work; do not repeat or bypass this call."
			result.data = { permission = source, executed = false }
			result.ms = clock.since(started)
			return result
		end
		if M.missingCapability(tool) or permissions.check(tool) == "deny" then
			result.text, result.error = "The tool's capability or permission changed before execution; this call did not run.", "unavailable"
			result.ms = clock.since(started)
			return result
		end

		-- A tool may state its own timeout, as a number or as a function of nothing --
		-- dispatch_agent computes one from the subagent budget, which is a setting and
		-- so cannot be a constant on the definition.
		local timeout = tool.timeout
		if type(timeout) == "function" then
			local okTimeout, value = pcall(timeout, coerced, ctx)
			timeout = okTimeout and tonumber(value) or nil
		end
		local function validTimeout(value)
			value = tonumber(value)
			return value and value > 0 and value < math.huge and value or nil
		end
		timeout = validTimeout(timeout) or validTimeout(config.get("agent.toolTimeout", 25)) or 25
		if blocked() then return result end

		-- The call's id travels with the context so a tool that emits events of its own
		-- can address the row it belongs to. dispatch_agent needs it: its subagent's
		-- live feed has to appear under the call that started it. Shallow, deliberately:
		-- ctx carries the session and the module env, and a deep copy of either would be
		-- both enormous and wrong.
		local scoped = type(ctx) == "table" and util.copy(ctx) or {}
		local expired, settled = false, false
		scoped.callId = call.id
		scoped.aborted = function()
			local owner = ctx and ctx.session
			local outside = owner and ((owner.toolFilter and not owner.toolFilter[name]) or (owner.toolGroups and not owner.toolGroups[tool.group]) or (owner.toolExclude and owner.toolExclude[name]))
			return expired or M.tools[name] ~= tool or registrations[name] ~= registration
				or (ctx and ctx.aborted and ctx.aborted()) or not M.groupEnabled(tool.group)
				or outside or permissions.check(tool) == "deny" or false
		end
		if ctx and ctx.emit then
			scoped.emit = function(kind, value)
				if settled then return end
				if kind == "tool:progress" then
					local payload = type(value) == "table" and util.copy(value) or { text = tostring(value) }
					payload.id, payload.name = call.id, name
					ctx.emit(kind, payload)
				else
					ctx.emit(kind, value)
				end
			end
			scoped.progress = function(text) scoped.emit("tool:progress", { text = tostring(text) }) end
		end
		local finished, ok, value, stoppedWaiting = clock.timeout(timeout, function()
			if scoped.aborted() then return { ok = false, text = "Stopped before " .. name .. " ran." } end
			local access = config.accessProblem()
			if access then return { ok = false, text = access } end
			return tool.run(coerced, scoped, prepared)
		end, scoped.aborted)
		settled = true

		if not finished then
			expired = true
			if stoppedWaiting == "aborted" then
				result.text = "Stopped waiting for " .. name .. ". The call may still be running; cancellation does not undo its effects. Do not retry the same call."
				result.error = "aborted"
			else
				result.text = string.format(
					"%s did not finish within %gs. It may still be running, but nothing will collect its result, so treat it as lost. Do not retry the same call.",
					name, timeout)
				result.error = "timeout"
			end
			result.ms = clock.since(started)
			return result
		end

		if not ok then
			result.text = string.format("%s failed: %s", name, util.ellipsis(tostring(value), 400))
			result.error = "error"
			result.ms = clock.since(started)
			log.warn("tools", name .. " raised", value)
			return result
		end

		local text, data, handlerOk
		if type(value) == "table" then
			text = tostring(value.text or "")
			data = value.data
			-- A handler may report a semantic failure -- a path that does not exist,
			-- a host that cannot do the thing -- without raising. That is not an
			-- error in the tool, but it is not a success either, and the transcript
			-- should say so.
			handlerOk = value.ok ~= false
		else
			text = tostring(value == nil and "Done." or value)
			handlerOk = true
		end

		local formatter = env.require("agent/tool_result")
		local observing = hooks.count("postTool") > 0
		local beforeText, beforeData = text, observing and formatter.signature(data)
		local after = { tool = tool, args = coerced, text = text, data = data, ctx = ctx }
		hooks.run("postTool", after)
		text = tostring(after.text or text)

		local cap = config.get("agent.resultCap", 4000)
		local capped, truncated = util.truncate(text, cap, "ask for a narrower slice if you need the rest")
		result.ok = handlerOk
		if not handlerOk then result.error = "tool reported a failure" end
		result.text = capped
		result.full = truncated and text or nil
		result.truncated = truncated
		result.data = after.data
		local function readerAvailable(readerName)
			local reader = M.tools[readerName]
			local owner = ctx and ctx.session
			return reader ~= nil and M.groupEnabled(reader.group) and not M.missingCapability(reader)
				and permissions.check(reader) ~= "deny"
				and not (owner and ((owner.toolFilter and not owner.toolFilter[readerName])
					or (owner.toolGroups and not owner.toolGroups[reader.group]) or (owner.toolExclude and owner.toolExclude[readerName])))
		end
		local referenceAllowed = not observing or (text == beforeText and beforeData ~= nil and formatter.signature(after.data) == beforeData)
		local modelOk, modelText = pcall(formatter.render, text, after.data, cap, tool.group, readerAvailable, referenceAllowed)
		if modelOk then result.modelText = modelText
		else result.modelText = "Structured tool result could not be formatted. Narrow the original query; the original receipt remains in the UI." end
		result.ms = clock.since(started)
		if ctx and ctx.session and ctx.session.id then
			local okEvidence, evidence = pcall(env.require, "runtime/evidence")
			if okEvidence and evidence and evidence.enabled then
				result.evidenceId = evidence.record(ctx.session, tool.name, text, after.data, { ok = handlerOk, ms = result.ms })
			end
		end
		return result
	end
	function M.dispatch(call, ctx)
		local workflow = env.require("runtime/script_workflow")
		local started = workflow.capture(ctx and ctx.session)
		local result = dispatch(call, ctx)
		-- Family calls already pass here once for their underlying action.
		if ctx and ctx.session and ctx.session.id and not result.targetName then
			local ok, why = pcall(function() workflow.observe(ctx.session, result.name, result, started) end)
			if not ok then log.warn("workflow", "Could not retain tool verification state", why) end
		end
		return result
	end

	-- Runs a batch with a concurrency cap.
	--
	-- The model is told parallel calls are executed together, and they are: each
	-- runs on its own thread, up to `agent.toolConcurrency` at a time. Dispatch
	-- carries its own timeout, so the batch cannot outlive the slowest permitted
	-- call by more than a poll interval.
	function M.runAll(calls, ctx, onResult)
		local total = #calls
		local results = {}
		if total == 0 then return results end

		local cap = tonumber(config.get("agent.toolConcurrency", 8))
		if not cap or cap ~= cap or cap <= 0 or cap == math.huge then cap = 8 end
		cap = math.max(1, math.min(total, math.floor(cap)))
		local launched, completed = 0, 0

		while completed < total do
			while launched < total and (launched - completed) < cap do
				launched = launched + 1
				local index = launched
				task.spawn(function()
					local ok, value = pcall(M.dispatch, calls[index], ctx)
					if ok then
						results[index] = value
					else
						results[index] = {
							id = calls[index].id,
							name = (calls[index]["function"] or {}).name or "unknown",
							ok = false,
							error = "dispatch failed",
							text = "Internal error running the tool: " .. tostring(value),
							ms = 0,
						}
						log.error("tools", "dispatch crashed", value)
					end
					if onResult then
						local notified, err = pcall(onResult, results[index], index)
						if not notified then log.warn("tools", "result subscriber failed", err) end
					end
					completed = completed + 1
				end)
			end
			if completed < total then clock.wait() end
		end

		return results
	end

	return M
end
