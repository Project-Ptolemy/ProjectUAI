-- Reviewable connection copies and explicit cleanup of learned compatibility.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local registry = env.require("provider/registry")
	local M = {}
	local learned = { "maxTokensCap", "toolsCap", "repairs", "repairScope" }
	function M.duplicate(record)
		local problem = config.accessProblem()
		if problem then return nil, problem end
		if type(record) ~= "table" then return nil, "Choose a saved connection first." end
		if record.preset == "projectuai-free" then return nil, "Add optional community access from the provider library." end
		local draft = registry.blank(record.preset)
		local cleanUrl = env.require("runtime/credentials").cleanUrl
		for _, name in ipairs({ "api", "authStyle", "stream", "claudeUa" }) do draft[name] = record[name] end
		draft.label = util.ellipsis(tostring(record.label or "Connection") .. " copy", 100)
		draft.baseUrl, draft.wsUrl = cleanUrl(record.baseUrl), cleanUrl(record.wsUrl)
		draft.model, draft.models = record.model, util.deepCopy(record.models or {})
		-- Custom maps can carry credentials under arbitrary names. A connection
		-- copy retains only fresh preset defaults and explicit public fields.
		draft.apiKey, draft.keyNames, draft.keyPaused, draft.keyIds = "", {}, {}, {}
		draft.keyMode, draft.selectedKey, draft.id = "rotate", 1, ""
		draft.communityCredential, draft.communityKeyState = nil, nil
		return draft
	end
	function M.hasLearned(record)
		for _, name in ipairs(learned) do if record and record[name] ~= nil then return true end end
		return false
	end
	function M.resetLearned(record)
		local problem = config.accessProblem()
		if problem then return false, problem end
		if not record or registry.get(record.id) ~= record then return false, "Reopen the saved connection before resetting compatibility." end
		local previous = {}
		for _, name in ipairs(learned) do previous[name], record[name] = record[name], nil end
		local ok, why = registry.save(record, { force = true })
		if not ok then
			for _, name in ipairs(learned) do record[name] = previous[name] end
			return false, type(why) == "table" and table.concat(why, "; ") or why
		end
		-- Health, quota cooldowns and accepted request ownership stay intact.
		return true
	end
	return M
end
