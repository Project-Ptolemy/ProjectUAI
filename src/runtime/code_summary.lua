-- Document facts shared by status bars, lists and tool output.
return function(env)
	local selection = env.require("runtime/code_selection")
	local M = {}
	function M.describe(source, cursor, anchor)
		local _, newlines = source:gsub("\n", "")
		local _, characters = source:gsub("[^\128-\191]", "")
		local crlf = select(2, source:gsub("\r\n", ""))
		local first, after = selection.range(source, cursor, anchor)
		return { bytes = #source, characters = characters, lines = newlines + 1, selectionBytes = after - first,
			lineEnding = newlines == 0 and "None" or crlf == 0 and "LF" or crlf == newlines and "CRLF" or "Mixed" }
	end
	function M.label(source, cursor, anchor)
		local data = M.describe(source, cursor, anchor)
		return data.lines .. " lines · " .. data.bytes .. " bytes · " .. data.lineEnding
			.. (data.selectionBytes > 0 and (" · " .. data.selectionBytes .. " selected bytes") or "")
	end
	return M
end
