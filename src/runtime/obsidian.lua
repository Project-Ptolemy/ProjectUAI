-- Pure vault contracts; local bridge transport belongs to net/obsidian.
return function(env)
	local util = env.require("runtime/util")
	local M = { MAX_BYTES = 1048576 }
	function M.path(value, folder)
		if folder and (value == nil or value == "") then return "" end
		if type(value) ~= "string" or value == "" or #value > 1024 or value:find("\\", 1, true) or value:sub(1, 1) == "/" then return nil, "Use a vault-relative path with forward slashes." end
		if not util.validUtf8(value) then return nil, "Vault paths must contain valid UTF-8." end
		if value:find("//", 1, true) or value:sub(-1) == "/" then return nil, "Vault paths must name complete components." end
		for part in value:gmatch("[^/]+") do
			if part:sub(1, 1) == "." or part:find('[<>:"|?*%z\1-\31\127]') or part:find("[. ]$") then return nil, "Hidden, parent and unsupported vault paths are unavailable." end
			local base = part:lower():match("^[^.]+")
			local prefix, suffix = base:sub(1, 3), base:sub(4)
			local device = (prefix == "com" or prefix == "lpt") and (suffix:match("^[1-9]$") or suffix == "¹" or suffix == "²" or suffix == "³")
			if base == "con" or base == "prn" or base == "aux" or base == "nul" or base == "conin$" or base == "conout$" or device then return nil, "Reserved device names cannot be used as vault paths." end
		end
		if not folder and not value:lower():match("%.md$") then return nil, "Obsidian notes must end in .md." end
		return value
	end
	function M.page(value, budget)
		if type(value) ~= "table" or type(value.data) ~= "table" then return nil, "The bridge returned an invalid vault listing." end
		if type(budget) ~= "number" or budget < 448 then return nil, "Increase the tool result budget to at least 448 bytes before listing vault results." end
		local parts, rows, bytes = {}, {}, 0
		for _, row in ipairs(value.data) do
			local encoded = util.encode(row)
			if bytes + #encoded + 1 > budget - 300 then break end
			parts[#parts + 1], rows[#rows + 1], bytes = encoded, row, bytes + #encoded + 1
		end
		if #rows == 0 and #value.data > 0 then return nil, "This vault entry exceeds the current tool result budget. Increase Tool result limit in Agent settings." end
		local nextOffset = value.nextOffset
		if #rows < #value.data then nextOffset = (value.offset or 1) + #rows end
		local suffix = nextOffset and ("\nContinue with offset=" .. tostring(nextOffset)) or "\nEnd of results."
		if value.incomplete then suffix = suffix .. "\nSearch coverage is incomplete; narrow the folder or query." end
		return { text = (#parts > 0 and table.concat(parts, "\n") or "No results.") .. suffix,
			data = { count = #rows, offset = value.offset or 1, nextOffset = nextOffset, total = value.total, incomplete = value.incomplete == true } }
	end
	return M
end
