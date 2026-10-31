-- Attachment descriptions distinguish an existing file from inline draft text.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	function M.describe(entry)
		local label = util.ellipsis(tostring(entry.label or entry.name or "Attachment"), 160)
		local details = {}
		if entry.file then
			details[#details + 1] = tostring(entry.path or "")
			details[#details + 1] = tostring(entry.bytes or 0) .. " bytes / " .. tostring(entry.lines or 0) .. " lines"
			details[#details + 1] = entry.sha256 and "Content fingerprint will be checked before sending." or "Legacy reference: file size will be checked before sending."
		else
			local text = tostring(entry.text or "")
			details[#details + 1] = tostring(#text) .. " bytes of draft context"
			details[#details + 1] = util.ellipsis(text:gsub("%s+", " "), 240)
		end
		return { label = label, detail = table.concat(details, "\n"), path = entry.file and entry.path or nil }
	end
	return M
end
