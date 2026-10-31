-- Small conversation-owned preferences. The enclosing history owns persistence.
return function(env)
	local M = {}
	local function count(value)
		return type(value) == "number" and value == value and math.max(0, math.min(999, math.floor(value))) or 0
	end
	function M.restore(value)
		value = type(value) == "table" and value.version == 1 and value or {}
		return { version = 1, pinned = value.pinned == true, unread = count(value.unread), failures = count(value.failures) }
	end
	function M.snapshot(value) return M.restore(value) end
	function M.read(value)
		local changed = value.unread > 0 or value.failures > 0
		value.unread, value.failures = 0, 0
		return changed
	end
	function M.observe(value, event, visible)
		if visible then return M.read(value) end
		if event.kind == "assistant:text" and type(event.text) == "string" and event.text ~= "" then value.unread = count(value.unread + 1); return true end
		if event.kind == "error" then value.failures = count(value.failures + 1); return true end
		return false
	end
	function M.label(value)
		local parts = {}
		if value.pinned then parts[#parts + 1] = "Pinned" end
		if value.unread > 0 then parts[#parts + 1] = tostring(value.unread) .. " new" end
		if value.failures > 0 then parts[#parts + 1] = tostring(value.failures) .. " failed" end
		return table.concat(parts, " / ")
	end
	return M
end
