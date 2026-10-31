-- Searchable application destinations, independent of presentation and execution.
return function(env)
	local search = env.require("runtime/search")
	local M = {}
	M.items = {
		{ id = "scriptGoal", label = "Script-making goal", detail = "Define, inspect, plan, build, validate and review script progress", kind = "action" },
		{ id = "chat", label = "Open Chat", detail = "Conversations and the message composer", kind = "panel" },
		{ id = "code", label = "Open Code", detail = "Editor, files, explorer, remotes, history and scripts", kind = "panel" },
		{ id = "providers", label = "Providers library", detail = "Add a provider, endpoint, API key or model", kind = "panel" },
		{ id = "tools", label = "Review tools", detail = "Search capabilities and tool permissions", kind = "panel" },
		{ id = "agents", label = "Monitor subagents", detail = "Background tasks, progress and reports", kind = "panel" },
		{ id = "cowork", label = "Open Cowork", detail = "Browser workspace and local bridge connection", kind = "panel" },
		{ id = "logs", label = "Open Logs", detail = "Requests, transport failures and diagnostics", kind = "panel" },
		{ id = "new", label = "New conversation", detail = "Choose a title and folder", kind = "action" },
		{ id = "search", label = "Search conversations", detail = "Find retained messages and replies", kind = "action" },
		{ id = "folders", label = "Manage conversation folders", detail = "Organize chats without changing their game context", kind = "action" },
		{ id = "export", label = "Export conversation", detail = "Copy or save retained dialogue as Markdown", kind = "action" },
		{ id = "focus", label = "Focus message", detail = "Return to your current composer draft", kind = "action" },
		{ id = "shortcuts", label = "Keyboard shortcuts", detail = "Keys for commands, search, settings and focus", kind = "action" },
		{ id = "tutorial", label = "Open Tutorial", detail = "Getting started and choosing a provider", kind = "action" },
	}
	function M.find(query, extra, limit)
		local match, rows = search.compile(query), {}
		local function add(items)
			for _, entry in ipairs(items or {}) do
				local score = match(entry.label, entry.detail, entry.keywords, entry.id)
				if score then rows[#rows + 1] = { entry = entry, score = score, order = #rows + 1 } end
			end
		end
		add(M.items); add(extra)
		table.sort(rows, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			return a.order < b.order
		end)
		local cap = tonumber(limit) or 40
		if cap ~= cap or cap == math.huge or cap == -math.huge then cap = 40 end
		cap = math.max(1, math.min(100, math.floor(cap)))
		local result = {}
		for index = 1, math.min(cap, #rows) do result[index] = rows[index].entry end
		return result, #rows
	end
	return M
end
