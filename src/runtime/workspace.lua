-- Place identity selects a stable workspace; the display name is only a label.
-- Existing folders are reused without renaming or merging user files.
return function(env)
	local util = env.require("runtime/util")
	local fsx = env.require("runtime/fsx")
	local place = env.require("runtime/place")
	local log = env.require("runtime/log")
	local M = {}
	local selections = {}
	local stored = fsx.readJson("workspace.json", nil)
	local mapping = type(stored) == "table" and stored.version == 1 and type(stored.games) == "table" and stored.games or {}
	local writable = stored == nil or (type(stored) == "table" and stored.version == 1)

	function M.folderName(displayName, placeId)
		local name = util.sanitise(displayName)
		local normalization = "preserved UTF-8"
		-- Luau hosts may supply full Unicode NFC. LuaJIT and older executors do
		-- not; never substitute a partial accent map and call it normalization.
		if type(utf8) == "table" and type(utf8.nfcnormalize) == "function" then
			local ok, normalized = pcall(utf8.nfcnormalize, name)
			if ok and type(normalized) == "string" and util.validUtf8(normalized) then name, normalization = normalized, "NFC" end
		end
		name = name:gsub('[<>:"/\\|%?%*%z\1-\31\127]', " ")
		-- Preserve accents, CJK, emoji modifiers and ZWJ sequences. Remove C1
		-- controls and invisible direction overrides that can disguise a path.
		name = name:gsub("\194[\128-\159]", " "):gsub("\226\128[\139\142\143\170-\174]", "")
		name = name:gsub("\226\129[\166-\169]", ""):gsub("\239\187\191", "")
		name = util.trim(name:gsub("%s+", " ")):gsub("[%. ]+$", "")
		-- Leave ample room for authored scripts and dump/ below the 180-byte
		-- executor path limit. Never split a Unicode code point.
		local last = math.min(#name, 72)
		while last > 0 and last < #name and name:byte(last + 1) >= 128 and name:byte(last + 1) < 192 do last = last - 1 end
		name = name:sub(1, last):gsub("[%. ]+$", "")
		if name == "" then name = "Place" end
		local id = string.format("%.0f", tonumber(placeId) or 0)
		local folder = name .. " (" .. id .. ")"
		-- CON.txt remains a Windows device even with a suffix after its dot.
		if not fsx.sanitise(folder) then folder = "_" .. folder end
		return folder, normalization
	end

	local function existing(id)
		local suffix = " (" .. id .. ")"
		local found, seen = {}, {}
		local root = ""
		local inspected = 0
		-- Older incorrect roots may have created repeated files/ containers.
		-- Discover those bounded legacy locations, but leave their contents in
		-- place: automatic flattening could overwrite unrelated user files.
		for _ = 1, 16 do
			local entries = fsx.list(root, { scope = "files" })
			for _, entry in ipairs(entries) do
				inspected = inspected + 1
				if inspected > 6000 then break end
				local relative = root == "" and entry.path or entry.path:sub(#root + 2)
				local leaf = relative:match("^[^/]+")
				if leaf and util.endsWith(leaf, suffix) then
					local path = root == "" and leaf or root .. "/" .. leaf
					if not seen[path] and fsx.sanitise(path) and fsx.isDir(path, { scope = "files" }) then
						seen[path] = true; found[#found + 1] = path
					end
				end
			end
			if #found > 0 or inspected > 6000 then break end
			root = root == "" and "files" or root .. "/files"
			if not fsx.isDir(root, { scope = "files" }) then break end
		end
		table.sort(found)
		if #found > 1 then log.warn("workspace", "multiple folders for PlaceId " .. id .. "; reusing " .. found[1] .. ", leaving the others intact") end
		return found[1]
	end

	function M.describe()
		local id = string.format("%.0f", place.id)
		local selected = selections[id]
		if not selected then
			local folder, normalization = M.folderName(place.label(), place.id)
			local saved = mapping[id]
			if type(saved) ~= "string" or not fsx.sanitise(saved) or not util.endsWith(saved, " (" .. id .. ")") then saved = nil end
			selected = { path = "files/" .. (saved or existing(id) or folder), normalization = normalization }
			selections[id] = selected
			if not saved and writable and fsx.enabled then
				mapping[id] = selected.path:sub(7)
				fsx.writeJson("workspace.json", { version = 1, games = mapping })
			end
		end
		return { path = selected.path, root = "files/", placeId = place.id,
			displayName = place.label(), normalization = selected.normalization }
	end

	return M
end
