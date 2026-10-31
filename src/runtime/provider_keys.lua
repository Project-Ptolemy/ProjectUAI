-- Ordered provider credentials and their user-owned labels/request policy.
-- This data-only module is shared by configuration transfer and presentation.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	local issuedIds = {}

	local function validId(value)
		return type(value) == "string" and #value == 36 and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
			and value == value:lower()
	end

	local function newId()
		local ok, value = pcall(function() return env.hs:GenerateGUID(false) end)
		if ok and validId(value) and not issuedIds[value] then issuedIds[value] = true; return value end
		-- GUIDs identify local accounting only. Hosts without GenerateGUID still
		-- receive opaque identifiers, never a hash or fragment of a credential.
		repeat
			value = string.format("%04x%04x-%04x-4%03x-8%03x-%04x%04x%04x", math.random(0, 65535), math.random(0, 65535),
				math.random(0, 65535), math.random(0, 4095), math.random(0, 4095), math.random(0, 65535), math.random(0, 65535), math.random(0, 65535))
		until not issuedIds[value]
		issuedIds[value] = true
		return value
	end

	function M.keys(record)
		local keys, seen = {}, {}
		for token in tostring(record and record.apiKey or ""):gmatch("[^\r\n,]+") do
			local key = util.trim(token)
			if key ~= "" and not seen[key] then
				seen[key] = true
				keys[#keys + 1] = key
			end
		end
		return keys
	end

	function M.keyId(record, index)
		local ids = record and record.keyIds
		return type(ids) == "table" and validId(ids[index]) and ids[index] or nil
	end

	function M.ensureIds(record)
		local ids, seen, changed = {}, {}, type(record.keyIds) ~= "table"
		local saved = type(record.keyIds) == "table" and record.keyIds or {}
		-- Reserve saved IDs before creating any new entries, including a later
		-- valid slot in a partially damaged legacy array.
		for _, value in pairs(saved) do if validId(value) then issuedIds[value] = true end end
		for index in ipairs(M.keys(record)) do
			local value = saved[index]
			if not validId(value) or seen[value] then value = newId(); changed = true end
			ids[index], seen[value] = value, true
		end
		for index in pairs(saved) do if ids[index] == nil then changed = true end end
		if changed then record.keyIds = ids end
		return changed
	end

	function M.mode(record)
		return record and record.keyMode == "single" and "single" or "rotate"
	end

	local function validIndex(value, count)
		return type(value) == "number" and value >= 1 and value <= count and value % 1 == 0
	end

	function M.selected(record)
		local value = record and record.selectedKey
		if value == nil then return 1 end
		return value
	end

	function M.paused(record, index)
		return type(record and record.keyPaused) == "table" and record.keyPaused[index] == true
	end

	function M.pauseFlags(record)
		local flags = {}
		for index in ipairs(M.keys(record)) do flags[index] = M.paused(record, index) end
		return flags
	end

	local function nameProblem(name)
		if type(name) ~= "string" then return "API key names must be text." end
		if not util.validUtf8(name) then return "API key names must contain valid UTF-8 text." end
		if name:find("[%z\1-\31\127]") or name:find("\194[\128-\159]")
			or name:find("\226\128\168", 1, true) or name:find("\226\128\169", 1, true) then
			return "API key names must use one line without control characters."
		end
		if #util.trim(name) > 120 then return "API key names must be at most 120 UTF-8 bytes." end
	end

	function M.entries(record)
		local entries, names = {}, type(record and record.keyNames) == "table" and record.keyNames or {}
		for index, key in ipairs(M.keys(record)) do
			entries[index] = { key = key, name = type(names[index]) == "string" and util.trim(names[index]) or "",
				paused = M.paused(record, index), id = M.keyId(record, index) }
		end
		return entries
	end

	function M.requestKeys(record)
		local keys = M.keys(record)
		if M.mode(record) == "single" then
			local selected = M.selected(record)
			local key = validIndex(selected, #keys) and not M.paused(record, selected) and keys[selected] or nil
			return key and { key } or {}
		end
		local active = {}
		for index, key in ipairs(keys) do
			if not M.paused(record, index) then active[#active + 1] = key end
		end
		return active
	end

	-- Counts never expose secrets and do not consume a rotation slot.
	function M.summary(record)
		local pool, active = M.keys(record), 0
		for index in ipairs(pool) do if not M.paused(record, index) then active = active + 1 end end
		local single, selected = M.mode(record) == "single", M.selected(record)
		local selectedActive = validIndex(selected, #pool) and not M.paused(record, selected)
		return { total = #pool, active = active, paused = #pool - active, mode = M.mode(record),
			available = single and (selectedActive and 1 or 0) or active,
			selected = single and validIndex(selected, #pool) and selected or nil }
	end

	function M.validate(record)
		if type(record) ~= "table" then return false, "provider must be an object" end
		local count = #M.keys(record)
		if record.keyMode ~= nil and record.keyMode ~= "rotate" and record.keyMode ~= "single" then
			return false, "keyMode must be rotate or single"
		end
		if record.selectedKey ~= nil and not validIndex(record.selectedKey, math.max(1, count)) then
			return false, "selectedKey must identify an existing API key"
		end
		if record.keyMode == "single" and count == 0 then return false, "single key mode requires an API key" end
		if record.keyIds ~= nil then
			if type(record.keyIds) ~= "table" then return false, "keyIds must be an array of identifiers" end
			local found, seen = 0, {}
			for index, value in pairs(record.keyIds) do
				if not validIndex(index, count) or not validId(value) or seen[value] then
					return false, "keyIds must contain one unique GUID for each API key"
				end
				found, seen[value] = found + 1, true
			end
			if found ~= count then return false, "keyIds must contain one unique GUID for each API key" end
		end
		if record.keyPaused ~= nil then
			if type(record.keyPaused) ~= "table" then return false, "keyPaused must be an array of booleans" end
			local found = 0
			for index, paused in pairs(record.keyPaused) do
				if not validIndex(index, count) or type(paused) ~= "boolean" then
					return false, "keyPaused must contain one boolean for each API key"
				end
				found = found + 1
			end
			if found ~= count then return false, "keyPaused must contain one boolean for each API key" end
		end
		if record.keyNames ~= nil then
			if type(record.keyNames) ~= "table" then return false, "keyNames must be an array of strings" end
			local found = 0
			for index, name in pairs(record.keyNames) do
				if not validIndex(index, count) or type(name) ~= "string" then
					return false, "keyNames must contain one string for each API key"
				end
				local problem = nameProblem(name)
				if problem then return false, "keyNames: " .. problem end
				if name ~= util.trim(name) then return false, "keyNames must not start or end with whitespace" end
				found = found + 1
			end
			if found ~= count then return false, "keyNames must contain one string for each API key" end
		end
		return true
	end

	local function namesOf(record, count)
		local names, saved = {}, type(record.keyNames) == "table" and record.keyNames or {}
		for index = 1, count do names[index] = type(saved[index]) == "string" and util.trim(saved[index]) or "" end
		return names
	end

	local function write(record, keys, names, mode, selected, paused)
		M.ensureIds(record)
		local ids, previous = {}, {}
		for index, key in ipairs(M.keys(record)) do previous[key] = record.keyIds[index] end
		for index, key in ipairs(keys) do ids[index] = previous[key] or newId() end
		local changedKeys = table.concat(M.keys(record), "\n") ~= table.concat(keys, "\n")
		local changedPause = false
		for index = 1, #keys do
			if M.paused(record, index) ~= paused[index] then changedPause = true end
		end
		if changedKeys or changedPause or M.mode(record) ~= mode or M.selected(record) ~= selected then record.keyRotation = nil end
		-- Renaming an entry must not invalidate an in-flight request or model cache.
		if changedKeys then record.apiKey = table.concat(keys, "\n") end
		record.keyNames, record.keyMode, record.selectedKey, record.keyPaused = names, mode, selected, paused
		record.keyIds = ids
		return true
	end

	function M.add(record, text)
		local ok, err = M.validate(record)
		if not ok then return false, err end
		local incoming, keys = M.keys({ apiKey = text }), M.keys(record)
		if #incoming == 0 then return false, "Enter at least one API key." end
		local names, paused, seen, added = namesOf(record, #keys), M.pauseFlags(record), {}, 0
		for _, key in ipairs(keys) do seen[key] = true end
		for _, key in ipairs(incoming) do
			if not seen[key] then
				keys[#keys + 1], names[#names + 1], seen[key], added = key, "", true, added + 1
				paused[#keys] = false
			end
		end
		write(record, keys, names, M.mode(record), M.selected(record), paused)
		return true, added
	end

	-- Replacing a pasted pool retains names, pauses and accounting identities for
	-- exact surviving keys. A removed pinned key returns the connection to rotation.
	function M.setPool(record, text)
		if type(text) ~= "string" then return false, "API keys must be pasted as text." end
		local valid, why = M.validate(record)
		if not valid then return false, why end
		local incoming, old, names, paused = M.keys({ apiKey = text }), {}, {}, {}
		local original = M.keys(record)
		local selectedSecret = original[M.selected(record)]
		for _, entry in ipairs(M.entries(record)) do old[entry.key] = entry end
		local selected
		for index, key in ipairs(incoming) do
			local prior = old[key]
			names[index], paused[index] = prior and prior.name or "", prior and prior.paused or false
			if key == selectedSecret then selected = index end
		end
		local mode = M.mode(record)
		if mode == "single" and not selected then mode = "rotate" end
		return write(record, incoming, names, mode, selected or 1, paused)
	end

	function M.replace(record, index, text)
		local ok, err = M.validate(record)
		if not ok then return false, err end
		local keys, incoming = M.keys(record), M.keys({ apiKey = text })
		if not validIndex(index, #keys) then return false, "That API key no longer exists." end
		if #incoming ~= 1 then return false, "Enter one replacement API key." end
		for position, key in ipairs(keys) do
			if position ~= index and key == incoming[1] then return false, "That API key is already in another entry." end
		end
		keys[index] = incoming[1]
		return write(record, keys, namesOf(record, #keys), M.mode(record), M.selected(record), M.pauseFlags(record))
	end

	function M.remove(record, index)
		local ok, err = M.validate(record)
		if not ok then return false, err end
		local keys = M.keys(record)
		if not validIndex(index, #keys) then return false, "That API key no longer exists." end
		local names, selected, mode, paused = namesOf(record, #keys), M.selected(record), M.mode(record), M.pauseFlags(record)
		table.remove(keys, index)
		table.remove(names, index)
		table.remove(paused, index)
		if selected == index then
			selected = 1
			if mode == "single" then mode = "rotate" end
		elseif selected > index then selected = selected - 1 end
		return write(record, keys, names, mode, selected, paused)
	end

	function M.rename(record, index, name)
		local ok, err = M.validate(record)
		if not ok then return false, err end
		local keys = M.keys(record)
		if not validIndex(index, #keys) then return false, "That API key no longer exists." end
		local problem = nameProblem(name)
		if problem then return false, problem end
		local names = namesOf(record, #keys)
		names[index] = util.trim(name)
		return write(record, keys, names, M.mode(record), M.selected(record), M.pauseFlags(record))
	end

	function M.setPaused(record, index, value)
		local ok, err = M.validate(record)
		if not ok then return false, err end
		local keys = M.keys(record)
		if not validIndex(index, #keys) then return false, "That API key no longer exists." end
		if type(value) ~= "boolean" then return false, "Choose Pause or Resume for this API key." end
		local paused = M.pauseFlags(record)
		paused[index] = value
		return write(record, keys, namesOf(record, #keys), M.mode(record), M.selected(record), paused)
	end

	function M.setMode(record, mode, selected)
		local keys = M.keys(record)
		if mode ~= "rotate" and mode ~= "single" then return false, "Choose Rotate keys or Use one key." end
		if selected == nil then
			selected = M.selected(record)
			if mode == "rotate" and not validIndex(selected, math.max(1, #keys)) then selected = 1 end
		end
		if not validIndex(selected, math.max(1, #keys)) then return false, "Choose an existing API key." end
		if mode == "single" and #keys == 0 then return false, "Add an API key before choosing Use one key." end
		if mode == "single" and M.paused(record, selected) then return false, "Resume this API key before choosing it." end
		return write(record, keys, namesOf(record, #keys), mode, selected, M.pauseFlags(record))
	end

	return M
end
