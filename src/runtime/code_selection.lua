-- Shared byte-safe line selections for editor actions and source tools.
return function(env)
	local text = env.require("runtime/code_text")
	local M = {}
	function M.range(source, cursor, selection)
		cursor = text.clamp(source, cursor)
		selection = type(selection) == "number" and selection > 0 and text.clamp(source, selection) or cursor
		return math.min(cursor, selection), math.max(cursor, selection)
	end
	function M.lines(source, cursor, selection, wholeWhenEmpty)
		local first, after = M.range(source, cursor, selection)
		if first == after and wholeWhenEmpty then return 1, #source + 1 end
		local lastByte = after > first and after - 1 or first
		local previous = source:sub(1, first - 1):match(".*()\n")
		first = previous and previous + 1 or 1
		local newline = source:find("\n", lastByte, true)
		return first, newline and newline + 1 or #source + 1
	end
	function M.replace(source, first, after, replacement)
		if not text.boundary(source, first) or not text.boundary(source, after) or after < first then return nil, "Selection splits a character or is outside the source" end
		return source:sub(1, first - 1) .. replacement .. source:sub(after), first + #replacement, first
	end
	return M
end
