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
	local valid = type(stored) == "table" and stored.version == 1 and type(stored.games) == "table"
	local mapping = valid and stored.games or {}
	local writable = valid or (stored == nil and not fsx.exists("workspace.json"))

	function M.folderName(displayName, placeId)
		-- Executor listfiles implementations can corrupt Unicode even when writes
		-- accept it. Only generated names use ASCII; existing user paths stay exact.
		local name = tostring(displayName or ""):gsub("[^A-Za-z0-9 _%-]+", " ")
		name = util.trim(name:gsub(" +", " ")):sub(1, 72):gsub(" +$", "")
		if name == "" then name = "Place" end
		local id = string.format("%.0f", tonumber(placeId) or 0)
		local folder = name .. " (" .. id .. ")"
		-- Keep generated paths within the same host validation as explicit paths.
		if not fsx.sanitise(folder) then folder = "_" .. folder end
		return folder, "ASCII"
	end

	local function reusable(path)
		if not fsx.isDir(path, { scope = "files" }) then return false end
		local entries, err = fsx.list(path, { scope = "files" })
		return err == nil or #entries > 0
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
					if not seen[path] then
						-- Recursive listings can mention every child of an unreadable
						-- folder. Probe the folder once even when that probe fails.
						seen[path] = true
						if fsx.sanitise(path) and reusable(path) then found[#found + 1] = path end
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
			-- A Unicode path saved by an older build may be inaccessible on this
			-- executor. Keep its files untouched and select a usable ASCII default.
			if saved and saved:find("[\128-\255]") and fsx.enabled and not reusable(saved) then saved = nil end
			local prior = saved or existing(id)
			selected = { path = "files/" .. (prior or folder), normalization = prior and "existing path" or normalization }
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
