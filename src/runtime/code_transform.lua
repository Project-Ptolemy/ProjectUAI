-- Explicit, undoable source conveniences. Never execute or save a transformed file.
return function(env)
	local selection = env.require("runtime/code_selection")
	local M = {}
	function M.apply(source, action, cursor, anchor)
		if type(source) ~= "string" then return nil, "Open a source document first" end
		local whole = action == "trim" or action == "tabs" or action == "spaces"
		local first, after = selection.lines(source, cursor, anchor, whole)
		local selected = source:sub(first, after - 1)
		local newline = source:find("\r\n", 1, true) and "\r\n" or "\n"
		local replacement
		if action == "duplicate" then
			replacement = selected .. (selected:sub(-1) == "\n" and "" or newline) .. selected
		elseif action == "delete" then
			if after == #source + 1 and first > 1 and selected:sub(-1) ~= "\n" then
				first = first - 1; if source:sub(first - 1, first - 1) == "\r" then first = first - 1 end
			end
			replacement = ""
		elseif action == "comment" or whole then
			local rows, endings, at, allCommented = {}, {}, 1, true
			repeat
				local finish = selected:find("\n", at, true)
				local row = selected:sub(at, finish and finish - 1 or #selected)
				local ending = finish and "\n" or ""
				if row:sub(-1) == "\r" and finish then row, ending = row:sub(1, -2), "\r\n" end
				rows[#rows + 1], endings[#endings + 1] = row, ending
				if row:find("%S") and not row:match("^%s*%-%-") then allCommented = false end
				at = finish and finish + 1 or #selected + 1
			until at > #selected
			for i, row in ipairs(rows) do
				if action == "trim" then row = row:gsub("[ \t]+$", "")
				elseif action == "spaces" then row = row:gsub("^[ \t]*", function(indent) return indent:gsub("\t", "    ") end)
				elseif action == "tabs" then row = row:gsub("^[ \t]*", function(indent) return indent:gsub("    ", "\t") end)
				elseif allCommented then row = row:gsub("^(%s*)%-%- ?", "%1", 1)
				elseif row:find("%S") then row = row:gsub("^(%s*)", "%1-- ", 1) end
				rows[i] = row .. endings[i]
			end
			replacement = table.concat(rows)
		else return nil, "Unknown source action" end
		return selection.replace(source, first, after, replacement)
	end
	return M
end
