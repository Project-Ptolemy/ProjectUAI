-- Declared-tool profiles. A profile changes what the model is shown; it never
-- removes a capability. Hidden tools stay callable through tool_search with the
-- same permissions and conversation scope as if they had been declared.
return function(env)
	local M = {}

	local CORE = {
		"ask_user", "notify",
		"file_read", "file_read_many", "file_list", "file_search", "file_write", "file_edit", "file_edit_many", "file_append", "file_delete", "file_find",
		"run_luau", "check_luau", "script_list", "script_source",
		"instance_query", "instance_get", "instance_get_many", "instance_set", "instance_create", "instance_destroy", "instance_clone", "instance_parent", "instance_tagged", "instance_tree",
		"todo_read", "todo_write", "memory_read", "memory_write",
		"skills_list", "skills_read",
		"dispatch_agent", "agent_status", "agent_followup",
		"conversation_search", "conversation_read", "context_archive",
		"tool_search", "evidence", "evidence_clear", "support_bundle",
	}

	local PROFILES = {
		focused = {
			label = "Focused families", hint = "A small set of tool families. Discover exact actions and arguments when needed; permissions stay unchanged.",
		},
		all = {
			label = "All tools", hint = "Every tool is declared, exactly as before.",
		},
		lean = {
			label = "Lean", hint = "Core files, execution and instance tools only; the rest is one tool_search away.",
		},
		inspect = {
			label = "Inspect", hint = "Core plus remotes, screen, diagnostics and web inspection.",
			groups = { remotes = true, screen = true, perf = true, meta = true, web = true, net_capture = true },
		},
		build = {
			label = "Build", hint = "Core plus the code workspace, interface and project tools.",
			groups = { coding = true, gui = true, templates = true, skills = true },
		},
		ui = {
			label = "Script UI", hint = "Core plus the code workspace and interface tools.",
			groups = { coding = true, gui = true, skills = true },
		},
		integrate = {
			label = "Integrations", hint = "Core plus Obsidian vaults, Gravity, Infinite Yield, players, character and world tools.",
			groups = { gravity = true, iy = true, chat = true, players = true, character = true, world = true, input = true, remotes = true, meta = true, obsidian = true },
		},
		chat = {
			label = "Chat", hint = "Core plus in-game chat and player tools.",
			groups = { chat = true, players = true, meta = true },
		},
	}

	local order = { "focused", "all", "lean", "inspect", "build", "ui", "integrate", "chat" }

	local function copy(list)
		local out = {}
		for index, value in ipairs(list) do out[index] = value end
		return out
	end

	for _, name in ipairs(order) do
		local profile = PROFILES[name]
		profile.id = name
		profile.groups = profile.groups or {}
		profile.tools = {}
		if name == "all" then profile.all = true
		else for _, tool in ipairs(CORE) do profile.tools[tool] = true end end
	end

	function M.get(name)
		local profile = PROFILES[tostring(name or "")]
		if not profile or profile.all then return nil end
		return profile
	end

	function M.describe()
		local out = {}
		for _, name in ipairs(order) do
			local profile = PROFILES[name]
			out[#out + 1] = { id = name, label = profile.label, hint = profile.hint }
		end
		return out
	end

	function M.options()
		local out = {}
		for _, item in ipairs(M.describe()) do out[#out + 1] = { value = item.id, label = item.label, detail = item.hint } end
		return out
	end

	function M.core() return copy(CORE) end

	return M
end
