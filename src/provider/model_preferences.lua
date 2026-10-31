-- Per-connection model shortcuts. Preferences contain IDs, never credentials.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local modelId = env.require("provider/model_id")
	local M = { maxFavorites = 100, maxRecent = 12 }
	local function providerId(record)
		return type(record) == "table" and type(record.id) == "string" and record.id ~= "" and record.id or nil
	end
	local function allValues(path)
		local value = config.get(path, {})
		return type(value) == "table" and value or {}
	end
	local function values(path, record)
		local value = allValues(path)[providerId(record)]
		return type(value) == "table" and value or {}
	end
	function M.favorite(record, model)
		return values("ui.modelFavorites", record)[model] == true
	end
	function M.setFavorite(record, model, wanted)
		if wanted ~= nil and type(wanted) ~= "boolean" then return false, "Choose whether this model is a favorite." end
		local id, clean = providerId(record), modelId.parse(model)
		if not id or not clean then return false, "Save the provider and choose a valid model first." end
		local problem = config.accessProblem()
		if problem then return false, problem end
		local all = util.deepCopy(allValues("ui.modelFavorites"))
		local favorites = util.copy(values("ui.modelFavorites", record))
		if wanted == nil then wanted = favorites[clean] ~= true end
		local count = 0
		for _, value in pairs(favorites) do if value == true then count = count + 1 end end
		if wanted and favorites[clean] ~= true and count >= M.maxFavorites then return false, "Remove a favorite before adding another (100 per provider)." end
		favorites[clean] = wanted and true or nil
		all[id] = next(favorites) and favorites or nil
		config.set("ui.modelFavorites", all)
		return true, wanted == true
	end
	function M.remember(record, model)
		local id, clean = providerId(record), modelId.parse(model)
		if not id or not clean then return end
		local recent = { clean }
		local seen = { [clean] = true }
		for _, value in ipairs(values("ui.recentModels", record)) do
			if type(value) == "string" and not seen[value] and modelId.parse(value) then
				recent[#recent + 1], seen[value] = value, true
				if #recent == M.maxRecent then break end
			end
		end
		local all = util.deepCopy(allValues("ui.recentModels"))
		all[id] = recent
		config.set("ui.recentModels", all)
	end
	function M.ordered(record, models)
		local rank, out = {}, {}
		for index, id in ipairs(values("ui.recentModels", record)) do if not rank[id] then rank[id] = index end end
		for index, id in ipairs(models or {}) do out[#out + 1] = { id = id, index = index } end
		table.sort(out, function(a, b)
			local af, bf = M.favorite(record, a.id), M.favorite(record, b.id)
			if af ~= bf then return af end
			local ar, br = rank[a.id] or math.huge, rank[b.id] or math.huge
			if ar ~= br then return ar < br end
			return a.index < b.index
		end)
		for index, item in ipairs(out) do out[index] = item.id end
		return out
	end
	function M.forget(id)
		for _, path in ipairs({ "ui.modelFavorites", "ui.recentModels" }) do
			local all = config.get(path, {})
			if type(all) == "table" and all[id] ~= nil then
				local copy = util.deepCopy(all); copy[id] = nil; config.set(path, copy)
			end
		end
	end
	return M
end
