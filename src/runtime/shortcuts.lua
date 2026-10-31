-- Pure key policy; the app owns native listeners and lifetime.
return function(env)
	local M = {}
	M.items = {
		{ key = "K", id = "commands", label = "Find a command", display = "Ctrl+K" },
		{ key = "P", id = "search", label = "Search conversations", display = "Ctrl+Shift+P", shift = true },
		{ key = "Comma", id = "settings", label = "Open settings", display = "Ctrl+," },
		{ key = "L", id = "focus", label = "Focus message", display = "Ctrl+L" },
	}
	function M.resolve(key, modifiers, state)
		modifiers, state = modifiers or {}, state or {}
		if not modifiers.control or modifiers.alt or state.gated or state.disposed then return nil end
		if state.focused or state.processed or state.overlay then return nil end
		for _, entry in ipairs(M.items) do
			if entry.key == key and (modifiers.shift == true) == (entry.shift == true) then return entry.id end
		end
		return nil
	end
	return M
end
