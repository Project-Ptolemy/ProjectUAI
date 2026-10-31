-- TextBox positions and slices use one-based UTF-8 bytes; displayed columns use code points.
return function()
	local M = { columns = "Unicode code points", offsets = "1-based UTF-8 bytes" }
	function M.boundary(text, at)
		return type(at) == "number" and at == math.floor(at) and at >= 1 and at <= #text + 1
			and (not text:byte(at) or text:byte(at) < 128 or text:byte(at) >= 192)
	end
	function M.clamp(text, at, forward)
		at = tonumber(at) or 1
		if at ~= at or math.abs(at) == math.huge then at = 1 end
		at = math.max(1, math.min(#text + 1, math.floor(at)))
		while not M.boundary(text, at) do at = at + (forward and 1 or -1) end
		return at
	end
	function M.slice(text, first, after)
		first, after = M.clamp(text, first), M.clamp(text, after or #text + 1)
		if after < first then first, after = after, first end
		return text:sub(first, after - 1), first, after
	end
	function M.page(text, offset, count)
		if not M.boundary(text, offset) then return nil, "Offset is outside source or splits a UTF-8 character" end
		local after = M.clamp(text, math.min(#text + 1, offset + count))
		if after == offset and offset <= #text then after = M.clamp(text, offset + 1, true) end
		return text:sub(offset, after - 1), after <= #text and after or nil
	end
	function M.column(text, first, offset)
		local _, count = text:sub(first or 1, M.clamp(text, offset) - 1):gsub("[^\128-\191]", "")
		return count + 1
	end
	function M.byteAt(text, column)
		local at = 1
		for _ = 2, math.max(1, math.floor(tonumber(column) or 1)) do
			if at > #text then break end
			at = M.clamp(text, at + 1, true)
		end
		return at
	end
	function M.lineAt(starts, offset)
		local low, high = 1, #starts
		while low < high do local mid = math.ceil((low + high) / 2); if starts[mid] <= offset then low = mid else high = mid - 1 end end
		return low
	end
	function M.position(text, line, column)
		line, column = tonumber(line), tonumber(column or 1)
		if not line or not column or line ~= line or column ~= column or line < 1 or column < 1
			or line == math.huge or column == math.huge or line ~= math.floor(line) or column ~= math.floor(column) then return nil, "Use positive whole line and column numbers" end
		local first, after = M.lineRange(text, line, 1)
		if not first then return nil, after end
		local content = text:sub(first, after - 1):gsub("\r?\n$", "")
		return first + M.byteAt(content, column) - 1
	end
	-- Locate a requested source page without allocating every line of a document.
	function M.lineRange(text, firstLine, count)
		if type(firstLine) ~= "number" or firstLine < 1 or firstLine == math.huge or firstLine ~= math.floor(firstLine) then return nil, "Invalid start line" end
		if count ~= nil and (type(count) ~= "number" or count < 1 or count == math.huge or count ~= math.floor(count)) then return nil, "Invalid line count" end
		local at = 1
		for _ = 2, firstLine do
			local newline = text:find("\n", at, true)
			if not newline then return nil, "Line is outside source" end
			at = newline + 1
		end
		local after = at
		if count then
			for _ = 1, count do
				local newline = text:find("\n", after, true)
				if not newline then after = #text + 1; break end
				after = newline + 1
			end
		else after = #text + 1 end
		return at, after
	end
	local function wordByte(byte) return byte and (byte >= 128 or (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or byte == 95) end
	function M.search(text, query, options)
		options = options or {}
		if type(query) ~= "string" or query == "" then return { items = {}, total = 0, complete = true } end
		local haystack, needle = text, query
		if options.caseSensitive == false then haystack, needle = text:lower(), query:lower() end
		if not pcall(string.find, "", needle, 1, not options.pattern) then return nil, "Invalid Lua pattern" end
		local result, at = { items = {}, total = 0, complete = true }, 1
		local limit = math.max(1, math.min(tonumber(options.limit) or 10000, 10000))
		while at <= #text + 1 do
			local first, last = haystack:find(needle, at, not options.pattern)
			if not first then break end
			if M.boundary(text, first) and M.boundary(text, last + 1)
				and (not options.wholeWord or (not wordByte(text:byte(first - 1)) and not wordByte(text:byte(last + 1)))) then
				result.total = result.total + 1
				if #result.items == limit then result.complete = false; break end
				result.items[#result.items + 1] = { first = first, last = last, after = last + 1 }
			end
			at = math.max(first + 1, last + 1)
		end
		return result
	end
	return M
end
