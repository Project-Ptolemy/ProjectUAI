-- Apply a library choice to an isolated connection draft. This module owns
-- provider semantics; the form only repaints the resulting fields.
return function(env)
	local util = env.require("runtime/util")
	local catalog = env.require("provider/catalog")
	local M = {}

	function M.apply(record, id)
		local preset = catalog.get(id)
		if not preset then return false, "Choose a provider from the library." end
		local draft = util.deepCopy(record)
		local previous = catalog.get(draft.preset)
		local changed = draft.preset ~= preset.id
		if previous and util.trim(draft.label) == util.trim(previous.label) or util.trim(draft.label) == "" then
			draft.label = preset.label
		end
		if changed then draft.wsUrl = "" end
		draft.preset, draft.baseUrl = preset.id, preset.baseUrl or ""
		draft.authStyle, draft.api, draft.claudeUa = preset.authStyle or "bearer", preset.api or "openai", preset.claudeUa ~= false
		draft.headers, draft.params, draft.query = util.deepCopy(preset.headers or {}), util.deepCopy(preset.params or {}), util.deepCopy(preset.query or {})
		draft.note, draft.requires = preset.note, preset.requires
		for field in pairs(record) do record[field] = nil end
		for field, value in pairs(draft) do record[field] = value end
		return true
	end

	return M
end
