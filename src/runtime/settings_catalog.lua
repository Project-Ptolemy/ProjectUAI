-- Search public setting names only. Current values, drafts and credentials never
-- enter this catalog, including when a query names a private field.
return function(env)
	local M = {}
	local groups = {
		{ "general", "General", "appearance text notifications conversation", {
			{ "ui.fontScale", "Text scale", "size accessibility zoom" },
			{ "ui.showReasoning", "Show reasoning", "thinking" },
			{ "ui.showToolCode", "Show the code a tool was given", "scripts" },
			{ "ui.showToolDetail", "Expand tool detail", "results show" },
			{ "ui.showUsage", "Show token counts", "usage cost" },
			{ "ui.showActivity", "Show the activity card", "progress" },
			{ "ui.notifications", "Notify while minimized", "notifications alerts" },
		} },
		{ "privacy", "Privacy", "credentials password vault storage logging", {
			{ "logs.mirror", "Mirror the log to the console", "diagnostics" },
		} },
		{ "usage", "Usage", "cost tokens requests accounting budget", {} },
		{ "claude_code", "Project UAI", "appearance code editor theme", {
			{ "ui.codeFont", "Code font", "monospace" },
			{ "ui.interfaceFont", "Interface font", "typeface accessibility" },
			{ "ui.transcriptWidth", "Transcript width", "reading narrow wide" },
		} },
		{ "cowork", "Cowork", "bridge desktop browser connection relay", {} },
		{ "import_export", "Import & export", "backup restore configuration", {} },
		{ "agent", "Behaviour", "agent model requests response limits", {
			{ "agent.maxTurns", "Step limit", "tool rounds" },
			{ "agent.unlimitedTurns", "Unlimited tool calls", "step limit deadline" },
			{ "agent.toolConcurrency", "Parallel tools", "concurrency" },
			{ "agent.toolProfile", "Tool profile", "discovery search" },
			{ "agent.evidence", "Tool evidence", "durable results" },
			{ "agent.toolTimeout", "Tool timeout", "deadline seconds" },
			{ "agent.resultCap", "Tool result cap", "bytes limit" },
			{ "agent.autoFreeRouting", "Automatic free routing", "HCNSEC included" },
			{ "agent.requestTimeout", "Request timeout", "deadline wait seconds" },
			{ "agent.requestUnlimited", "Maximum request wait", "timeout deadline" },
			{ "agent.retries", "Retries", "attempts recovery" },
			{ "agent.stream", "Ask for streams", "streaming reasoning" },
			{ "agent.fallback", "Provider fallback", "recovery" },
			{ "agent.subagentBudget", "Subagent budget", "delegation seconds" },
			{ "agent.subagentUnlimited", "Unlimited subagents", "delegation limits" },
			{ "agent.subagentConcurrency", "Parallel subagents", "delegation concurrency" },
			{ "agent.subagentTurns", "Subagent steps", "delegation rounds" },
			{ "agent.subagentDepth", "Delegation depth", "subagent levels" },
			{ "agent.contextTokens", "Context budget", "memory tokens" },
			{ "agent.contextFraction", "Compact at", "memory fraction" },
			{ "agent.compaction", "Summarise old turns", "memory compaction" },
			{ "agent.maxTokens", "Reply ceiling", "output tokens length" },
			{ "agent.effort", "Effort", "reasoning thinking" },
			{ "agent.temperature", "Temperature", "sampling creativity" },
			{ "agent.replyLanguage", "Reply language", "translation" },
			{ "agent.customInstructions", "Custom instructions", "system prompt" },
		} },
		{ "permissions", "Permissions", "tools allow deny approval", {
			{ "permissions.remember", "Offer to remember", "permissions approvals" },
		} },
		{ "desktop_general", "Desktop general", "window sidebar layout", {
			{ "ui.panel", "Open on", "default panel startup" },
			{ "ui.sidebarCollapsed", "Start with the sidebar collapsed", "navigation collapse" },
			{ "ui.sidebarExpanded", "Keep the panel list open", "navigation expand sidebar" },
		} },
		{ "developer", "Developer", "identity diagnostics executor", {
			{ "identity.claudeUa", "Send the Claude Code identity", "user agent headers" },
			{ "identity.version", "Identity version", "user agent" },
		} },
		{ "skills", "Skills", "knowledge memory", {
			{ "memory.enabled", "Memory enabled", "remember facts" },
		} },
		{ "connectors", "Connectors", "integration tools external", {} },
		{ "obsidian", "Obsidian", "vault notes markdown links", {} },
		{ "infinite_yield", "Infinite Yield", "commands IY", {} },
		{ "plugins", "Plugins", "extensions install", {} },
	}

	function M.search(query, limit)
		query = type(query) == "string" and query:sub(1, 160):lower():match("^%s*(.-)%s*$") or ""
		limit = math.max(1, math.min(50, math.floor(tonumber(limit) or 30)))
		local found = {}
		if query == "" then return found, 0 end
		local function add(group, path, label, keywords)
			local haystack = (label .. " " .. (path or "") .. " " .. group[2] .. " " .. group[3] .. " " .. keywords):lower()
			for word in query:gmatch("%S+") do if not haystack:find(word, 1, true) then return end end
			found[#found + 1] = { category = group[1], categoryLabel = group[2], path = path, label = label,
				score = label:lower() == query and 0 or (label:lower():find(query, 1, true) and 1 or 2) }
		end
		for _, group in ipairs(groups) do
			add(group, nil, group[2], group[3])
			for _, item in ipairs(group[4]) do add(group, item[1], item[2], item[3]) end
		end
		table.sort(found, function(a, b)
			if a.score ~= b.score then return a.score < b.score end
			if a.label ~= b.label then return a.label < b.label end
			return (a.path or a.category) < (b.path or b.category)
		end)
		local total = #found
		while #found > limit do table.remove(found) end
		for _, item in ipairs(found) do item.score = nil end
		return found, total
	end

	return M
end
