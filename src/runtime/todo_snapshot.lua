-- Bounded task plans can be saved without retaining arbitrary tool arguments.
return function(env)
	local util = env.require("runtime/util")
	local M = { limit = 24 }
	local statuses = { pending = true, active = true, done = true, dropped = true }
	function M.items(items, restored)
		local out = {}
		for index, item in ipairs(type(items) == "table" and items or {}) do
			if index > M.limit then break end
			local raw = type(item) == "table" and (item.text or item.title) or item
			local text = type(raw) == "string" and util.trim(raw) or ""
			if text ~= "" then
				local status = type(item) == "table" and tostring(item.status or "pending"):lower() or "pending"
				if not statuses[status] or restored and status == "active" then status = "pending" end
				out[#out + 1] = { id = index, text = util.ellipsis(util.sanitise(text), 160), status = status,
					note = type(item) == "table" and type(item.note) == "string" and util.ellipsis(util.sanitise(item.note), 600) or nil }
			end
		end
		return out
	end
	function M.snapshot(items) return { version = 1, items = M.items(items) } end
	function M.restore(value)
		if type(value) ~= "table" or value.version ~= 1 then return {} end
		return M.items(value.items, true)
	end
	function M.text(items)
		local lines, marks = {}, { pending = "[ ]", active = "[>]", done = "[x]", dropped = "[-]" }
		for _, item in ipairs(M.items(items)) do
			lines[#lines + 1] = (marks[item.status] or "[ ]") .. " " .. item.text
			if item.note and item.note ~= "" then lines[#lines + 1] = "  " .. item.note end
		end
		return table.concat(lines, "\n")
	end
	return M
end
