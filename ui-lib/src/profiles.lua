return function(env)
	local config = env.require("config")
	local M = {}
	function M.ListConfigs(window)
		if not window.Alive then return false, "Window is destroyed" end
		local list = env.globals.listfiles or listfiles
		local exists = env.globals.isfolder or isfolder
		if type(list) ~= "function" then return false, "This host does not provide listfiles" end
		local ok, result = pcall(function()
			local _, folder = config.pathFor(window, "default")
			if type(exists) == "function" and not exists(folder) then return {} end
			local names, seen = {}, {}
			local entries = list(folder)
			assert(type(entries) == "table", "The host returned an invalid profile listing")
			for _, entry in ipairs(entries) do
				if type(entry) == "string" then
					local normalized = entry:gsub("\\", "/"):gsub("/+", "/"):gsub("^%./", "")
					local name = normalized:match("/([%w_-]+)%.json$") or normalized:match("^([%w_-]+)%.json$")
					if name and #name <= 48 and not seen[name] then
						-- Host listings sometimes return basenames. Accept only files
						-- directly in this window's profile directory, never children.
						local wanted = folder .. "/" .. name .. ".json"
						local absoluteSuffix = normalized:sub(-#wanted - 1) == "/" .. wanted and not normalized:find("/../", 1, true)
						if normalized == wanted or normalized == name .. ".json" or absoluteSuffix then names[#names + 1], seen[name] = name, true end
					end
				end
			end
			table.sort(names)
			return names
		end)
		return ok, result
	end
	function M.DeleteConfig(window, name)
		if not window.Alive then return false, "Window is destroyed" end
		local remove = env.globals.delfile or delfile
		local exists = env.globals.isfile or isfile
		if type(remove) ~= "function" then return false, "This host does not provide delfile" end
		local ok, result = pcall(function()
			local path = config.pathFor(window, name)
			if type(exists) == "function" and not exists(path) then return false end
			remove(path)
			if type(exists) == "function" then assert(not exists(path), "The host did not remove the profile") end
			return true
		end)
		return ok, result
	end
	return M
end
