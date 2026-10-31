-- Validate native note-browser rows before constructing controls from bridge data.
return function(env)
	local vault = env.require("runtime/obsidian")
	local util = env.require("runtime/util")
	local M = {}
	function M.validate(value, offset)
		if type(value) ~= "table" or type(value.data) ~= "table" or #value.data > 100
			or value.offset ~= offset or type(value.total) ~= "number" or value.total < 0 or value.total > 5000
			or value.total ~= math.floor(value.total) then return nil, "The bridge returned an invalid note listing." end
		local rows = {}
		for _, row in ipairs(value.data) do
			if type(row) ~= "table" or not vault.path(row.path) then return nil, "The bridge returned an invalid note path." end
			local detail = type(row.bytes) == "number" and tostring(math.max(0, math.floor(row.bytes))) .. " bytes" or ""
			local matches = type(row.matches) == "table" and row.matches or {}
			if matches[1] and type(matches[1]) == "table" and type(matches[1].excerpt) == "string" then detail = util.ellipsis(matches[1].excerpt, 220) end
			rows[#rows + 1] = { path = row.path, detail = detail }
		end
		if value.nextOffset ~= nil and (type(value.nextOffset) ~= "number" or #rows == 0 or value.nextOffset ~= offset + #rows) then
			return nil, "The note listing did not advance safely."
		end
		return { rows = rows, offset = offset, nextOffset = value.nextOffset, total = value.total, incomplete = value.incomplete == true }
	end
	return M
end
