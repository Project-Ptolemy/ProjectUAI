-- Truthful runtime context for OpenCode Zen's request compatibility check.
-- This describes the client environment without granting host tool access.
return function(env)
	local CONTEXT = "<env>\nWorking directory: Roblox runtime\nPlatform: Roblox\n</env>"
	local M = {}

	function M.text() return CONTEXT end

	local function contains(content)
		if type(content) == "string" then return content:find(CONTEXT, 1, true) ~= nil end
		if type(content) == "table" then
			for _, block in ipairs(content) do
				if type(block) == "table" and type(block.text) == "string" and block.text:find(CONTEXT, 1, true) then return true end
			end
		end
		return false
	end

	function M.chat(messages)
		local first = messages and messages[1]
		if first and (first.role == "system" or first.role == "developer") and contains(first.content) then return messages end
		local out = { { role = "system", content = CONTEXT } }
		for _, message in ipairs(messages or {}) do out[#out + 1] = message end
		return out
	end

	function M.instructions(instructions)
		local text = tostring(instructions or "")
		if contains(text) then return text end
		return CONTEXT .. (text ~= "" and ("\n\n" .. text) or "")
	end

	return M
end
