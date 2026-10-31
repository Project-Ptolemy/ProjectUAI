-- Explicit, bounded Markdown export of retained dialogue, without request internals.
return function(env)
	local util = env.require("runtime/util")
	local pending = {}
	local M = { maxBytes = 1024 * 1024 }
	local function line(value)
		return util.sanitise(tostring(value or "")):gsub("[%z\1-\31\127]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	end
	function M.markdown(session)
		if type(session) ~= "table" or type(session.id) ~= "string" then return nil, "A conversation is required." end
		local title = util.truncate(line(session.title), 512, "")
		local out = { "# " .. (title ~= "" and title or "Conversation"), "", "Exported from Project UAI.", "" }
		local bytes, count, limited = #table.concat(out, "\n"), 0, false
		for _, event in ipairs(type(session.log) == "table" and session.log or {}) do
			local heading
			if type(event) == "table" then
				if event.kind == "user" then heading = "You"
				elseif event.kind == "assistant:text" and event.final ~= false then heading = "Assistant" end
			end
			if heading and type(event.text) == "string" and event.text ~= "" then
				local text = util.sanitise(event.text)
				local block = "## " .. heading .. "\n\n" .. text .. "\n"
				if bytes + #block + 256 > M.maxBytes then limited = true; break end
				out[#out + 1] = block
				bytes, count = bytes + #block + 1, count + 1
			end
		end
		if count == 0 then out[#out + 1] = "No retained dialogue." end
		if limited then out[#out + 1] = "Export stopped at the 1 MiB limit; remaining dialogue is omitted." end
		out[#out + 1] = "Only retained dialogue is exported. Earlier content may have been removed by history limits."
		return table.concat(out, "\n") .. "\n", { messages = count, limited = limited, sessionId = session.id }
	end

	function M.save(text)
		if type(text) ~= "string" or #text > M.maxBytes or not util.validUtf8(text) then
			return nil, "Export must be valid UTF-8 within 1 MiB."
		end
		local fsx = env.require("runtime/fsx")
		local caps = env.require("runtime/caps")
		if not fsx.enabled then return nil, "File storage is unavailable in this executor." end
		if type(caps.fn.isfile) ~= "function" then return nil, "The executor cannot verify a new export filename." end
		-- Never replace an earlier export, even when the host reuses GUIDs.
		for _ = 1, 8 do
			local ok, guid = pcall(function() return env.hs:GenerateGUID(false) end)
			local id = ok and type(guid) == "string" and guid:gsub("[^%w%-]", "") or ""
			if id == "" then id = util.uid("conversation"):gsub("[^%w%-]", "") end
			local path = "export/conversation-" .. id:sub(1, 80) .. ".md"
			local full = fsx.resolve(path)
			local checked, exists = pcall(caps.fn.isfile, full)
			if not checked or type(exists) ~= "boolean" then return nil, "The executor could not check the export filename." end
			if not exists and not pending[path] then
				pending[path] = true
				local saved, why = fsx.write(path, text)
				if not saved then pending[path] = nil; return nil, why end
				local actual, readWhy = fsx.read(path)
				pending[path] = nil
				if actual ~= text then return nil, readWhy or "Export verification failed." end
				return fsx.root .. "/" .. path
			end
		end
		return nil, "Could not choose a new export filename. Try again."
	end
	return M
end
