-- Conversation folders are labels, never filesystem paths or execution context.
-- Two small verified snapshots keep a failed executor write from losing names.
return function(env)
	local util = env.require("runtime/util")
	local fsx = env.require("runtime/fsx")
	local log = env.require("runtime/log")
	local LIMIT, NAME_BYTES = 64, 120
	local paths = { "sessions/.folders.1.json", "sessions/.folders.2.json" }
	local folders, revision, serial, currentSlot = {}, 0, 0, 0
	local blocked, saving = nil, false
	local M = { limit = LIMIT, nameBytes = NAME_BYTES }

	local function integer(value)
		return type(value) == "number" and value >= 0 and value < 9007199254740991 and value == math.floor(value)
	end

	local function cleanName(name)
		if type(name) ~= "string" then return nil, "a folder needs a name" end
		name = util.trim(name)
		if name == "" then return nil, "a folder needs a name" end
		if #name > NAME_BYTES then return nil, "folder names must be at most 120 UTF-8 bytes" end
		if name:find("[%z\1-\31\127]") or not util.validUtf8(name) then return nil, "folder names must be valid text on one line" end
		if name:lower() == "universal" then return nil, "Universal is already available" end
		return name
	end

	local function decode(raw)
		if type(raw) ~= "string" or #raw > 64 * 1024 then return nil end
		local data = util.decode(raw)
		if type(data) ~= "table" then return nil end
		if data.version ~= 1 then return nil, "saved folders use an unsupported format" end
		if not integer(data.revision) or not integer(data.serial) or type(data.folders) ~= "table"
			or not util.isArray(data.folders) or #data.folders > LIMIT then return nil end
		local indexed, names = {}, {}
		for _, folder in ipairs(data.folders) do
			if type(folder) ~= "table" or type(folder.id) ~= "string" then return nil end
			local number = tonumber(folder.id:match("^folder_([1-9]%d*)$"))
			local name = cleanName(folder.label)
			if not number or number > data.serial or not name or indexed[folder.id] or names[name:lower()] then return nil end
			indexed[folder.id] = { id = folder.id, label = name, kind = "custom" }
			names[name:lower()] = true
		end
		data.indexed = indexed
		return data
	end

	if fsx.enabled then
		local found = false
		for slot, path in ipairs(paths) do
			if fsx.exists(path) then
				found = true
				local raw = fsx.read(path)
				local data, why = decode(raw)
				if not raw then blocked = "saved folders could not be read"
				elseif why then blocked = why end
				if data and (currentSlot == 0 or data.revision > revision) then
					folders, revision, serial, currentSlot = data.indexed, data.revision, data.serial, slot
				end
			end
		end
		if found and currentSlot == 0 then blocked = blocked or "saved folders are damaged" end
		if blocked then log.warn("folders", blocked .. "; existing files were kept") end
	end

	local function ordered(source)
		local out = {}
		for _, folder in pairs(source) do out[#out + 1] = util.copy(folder) end
		table.sort(out, function(a, b)
			if a.label:lower() ~= b.label:lower() then return a.label:lower() < b.label:lower() end
			return a.id < b.id
		end)
		return out
	end

	local function save(nextFolders, nextSerial)
		if blocked then return false, blocked end
		if saving then return false, "folders are already being saved" end
		if fsx.enabled then
			saving = true
			local slot = currentSlot == 1 and 2 or 1
			local ok, body = pcall(util.encode, { version = 1, revision = revision + 1, serial = nextSerial, folders = ordered(nextFolders) })
			local written, why = false, body
			if ok then
				written, why = fsx.write(paths[slot], body)
				if written and fsx.read(paths[slot]) ~= body then written, why = false, "folder save could not be verified" end
			end
			saving = false
			if not written then return false, tostring(why or "folders could not be saved") end
			currentSlot = slot
		end
		folders, serial, revision = nextFolders, nextSerial, revision + 1
		return true
	end

	local function availableName(name, except)
		local clean, why = cleanName(name)
		if not clean then return nil, why end
		for id, folder in pairs(folders) do
			if id ~= except and folder.label:lower() == clean:lower() then return nil, "a folder with that name already exists" end
		end
		return clean
	end

	function M.list() return ordered(folders) end
	function M.get(id) return folders[id] and util.copy(folders[id]) or nil end

	function M.create(name)
		local clean, why = availableName(name)
		if not clean then return nil, why end
		if #M.list() >= LIMIT then return nil, "at most 64 custom folders are available" end
		local nextSerial = serial + 1
		local folder = { id = "folder_" .. tostring(nextSerial), label = clean, kind = "custom" }
		local nextFolders = util.copy(folders)
		nextFolders[folder.id] = folder
		local ok, err = save(nextFolders, nextSerial)
		if not ok then return nil, err end
		return util.copy(folder)
	end

	function M.rename(id, name)
		if not folders[id] then return false, "custom folder no longer exists" end
		local clean, why = availableName(name, id)
		if not clean then return false, why end
		if folders[id].label == clean then return true end
		local nextFolders = util.copy(folders)
		nextFolders[id] = { id = id, label = clean, kind = "custom" }
		return save(nextFolders, serial)
	end

	function M.remove(id)
		if not folders[id] then return false, "only custom folders can be removed" end
		local nextFolders = util.copy(folders)
		nextFolders[id] = nil
		return save(nextFolders, serial)
	end

	return M
end
