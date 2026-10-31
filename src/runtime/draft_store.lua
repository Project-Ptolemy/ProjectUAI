-- Draft payloads live inside their conversation file, never in a second store.
return function(env)
	local util = env.require("runtime/util")
	local M = { maxBytes = 1024 * 1024, maxAttachments = 16 }
	function M.snapshot(value)
		if type(value) ~= "table" then return nil end
		local text = type(value.text) == "string" and value.text or ""
		if #text > M.maxBytes then return nil, "Draft exceeds the 1 MiB recovery limit. Copy it before closing." end
		local entries, bytes = {}, #text
		for _, entry in ipairs(type(value.attachments) == "table" and value.attachments or {}) do
			if #entries >= M.maxAttachments then return nil, "Draft has too many attachments to recover." end
			if type(entry) ~= "table" then return nil, "Draft contains an invalid attachment." end
			local copy = { label = util.truncate(tostring(entry.label or entry.name or "Attachment"), 160) }
			if entry.file == true then
				if type(entry.path) ~= "string" or #entry.path > 1000 or type(entry.bytes) ~= "number"
					or entry.bytes ~= entry.bytes or entry.bytes < 0 or entry.bytes % 1 ~= 0 or entry.bytes > 10 * 1024 * 1024 then
					return nil, "Draft contains an invalid file reference."
				end
				copy.file, copy.path, copy.bytes = true, entry.path, math.floor(entry.bytes)
				if entry.sha256 ~= nil then
					if not env.require("runtime/attachment_identity").valid(entry.sha256) then return nil, "Draft contains an invalid attachment digest." end
					copy.sha256 = entry.sha256
				end
				local lines = tonumber(entry.lines) or 0
				copy.name, copy.lines = copy.label, lines == lines and math.max(0, math.min(10 * 1024 * 1024, math.floor(lines))) or 0
			else
				if type(entry.text) ~= "string" then return nil, "Draft contains an invalid text attachment." end
				bytes = bytes + #entry.text
				if bytes > M.maxBytes then return nil, "Draft attachments exceed the 1 MiB recovery limit." end
				copy.text = entry.text
			end
			entries[#entries + 1] = copy
		end
		if text == "" and #entries == 0 then return nil end
		return { version = 1, text = text, attachments = entries, expanded = value.expanded == true }
	end
	function M.restore(value)
		if type(value) ~= "table" or value.version ~= 1 then return nil end
		return M.snapshot(value)
	end
	return M
end
