-- Retire bundled access without retaining a usable credential in the client.
-- Old encrypted/provider envelopes are decoded before this migration runs.
return function(env)
	local util = env.require("runtime/util")
	local keys = env.require("runtime/provider_keys")
	local sha = env.require("runtime/credential_sha256")
	local M = {}
	local fingerprints = {}
	for _, hex in ipairs({
		"f232d4b8afbc789840ecf32fabf265c495cf4cafb877dd59c8c583c277392f48",
		"2fb558bb73aee28a8471e4eac99eaebe2010ab1f79a1c40d2e56a2bb8c9c9f28",
	}) do
		fingerprints[(hex:gsub("..", function(pair) return string.char(tonumber(pair, 16)) end))] = true
	end
	function M.retiredPreset(id)
		return id == "projectuai-free" or id == "hcnsec"
	end
	function M.retiredKey(value)
		if type(value) ~= "string" or #value ~= 51 or value:sub(1, 3) ~= "sk-" then return false end
		local digest = sha.digest(value)
		return digest ~= nil and fingerprints[digest] == true
	end
	local function decodeUrl(value)
		return (value:gsub("%%(%x%x)", function(pair) return string.char(tonumber(pair, 16)) end))
	end
	function M.containsKey(value)
		if type(value) ~= "string" then return false end
		if value:find("%", 1, true) then value = decodeUrl(value) end
		for token in value:gmatch("sk%-[%w_%-]+") do if M.retiredKey(token) then return true end end
		return false
	end
	function M.hasKey(value, seen, depth)
		if type(value) ~= "table" then return M.containsKey(value) end
		seen = seen or {}
		if seen[value] or (depth or 0) > 32 then return false end
		seen[value] = true
		for field, item in pairs(value) do if M.containsKey(field) or M.hasKey(item, seen, (depth or 0) + 1) then return true end end
		return false
	end
	local function clearCopies(values, seen, depth)
		if type(values) ~= "table" then return false end
		seen = seen or {}
		if seen[values] or (depth or 0) > 32 then return false end
		seen[values] = true
		local changed = false
		for field, value in pairs(values) do
			if M.containsKey(field) or M.containsKey(value) then values[field], changed = nil, true
			elseif type(value) == "table" and clearCopies(value, seen, (depth or 0) + 1) then
				changed = true
				if next(value) == nil then values[field] = nil end
			end
		end
		return changed
	end
	local function clearUrl(value)
		if not M.containsKey(value) then return value end
		local content, fragment = value:match("^(.-)#(.*)$")
		local prefix, query = (content or value):match("^(.-)%?(.*)$")
		local clean = prefix or content or value
		local authority, path = clean:match("^(%a[%w+%.%-]*://[^/]*)(.*)$")
		if authority then
			local userinfo = authority:match("//(.*)@")
			if userinfo and M.containsKey(userinfo) then authority = authority:gsub("//.*@", "//") end
			clean = authority .. path
		end
		if query then
			local kept = {}
			for item in query:gmatch("[^&]+") do if not M.containsKey(item) then kept[#kept + 1] = item end end
			if #kept > 0 then clean = clean .. "?" .. table.concat(kept, "&") end
		end
		if fragment and not M.containsKey(fragment) then clean = clean .. "#" .. fragment end
		-- A credential embedded in a path cannot be removed while guessing its API.
		return M.containsKey(clean) and "" or clean
	end
	local function personal(record)
		if #keys.keys(record) > 0 then return true end
		for name, value in pairs(type(record.headers) == "table" and record.headers or {}) do
			local field = tostring(name):lower():gsub("[_%-]", "")
			if (field == "authorization" or field == "apikey" or field == "xapikey" or field == "xgoogapikey")
				and util.trim(value) ~= "" then return true end
		end
		for name, value in pairs(type(record.query) == "table" and record.query or {}) do
			local field = tostring(name):lower():gsub("[_%-]", "")
			if (field == "key" or field == "apikey" or field == "token" or field == "accesstoken")
				and util.trim(value) ~= "" then return true end
		end
		for _, name in ipairs({ "baseUrl", "wsUrl" }) do
			local raw = type(record[name]) == "string" and decodeUrl(record[name]) or ""
			local authority = raw:gsub("^%a[%w+%.%-]*://", ""):gsub("^//", ""):match("^[^/?#]*") or ""
			if util.trim(authority:match("^(.*)@") or "") ~= "" then return true end
			local query = raw:match("%?([^#]*)") or ""
			for field, value in query:gmatch("([^&=]+)=([^&]*)") do
				field = field:lower():gsub("[_%-]", "")
				if (field == "key" or field == "apikey" or field == "token" or field == "accesstoken")
					and util.trim(value) ~= "" then return true end
			end
		end
		return false
	end
	local function edited(record)
		local base = util.trim(record.baseUrl):lower():gsub("/+$", "")
		local canonical = base == "" or base == "https://api.hcnsec.cn/v1" or base == "https://api.hcnsec.cn:443/v1"
			or base == "https://api.hcnsec.cn/v1/chat/completions" or base == "https://api.hcnsec.cn/v1/models"
		if not canonical or util.trim(record.wsUrl) ~= "" then return true end
		for _, field in ipairs({ "headers", "query", "params" }) do
			if type(record[field]) == "table" and next(record[field]) ~= nil then return true end
		end
		return record.authStyle ~= nil and record.authStyle ~= "bearer" or record.api ~= nil and record.api ~= "openai"
	end
	function M.record(record)
		if type(record) ~= "table" then return true, false end
		-- Corrupt/future envelopes remain recoverable. Their existing admission
		-- guard blocks use until the owner explicitly replaces the credentials.
		if record.storedCredentials ~= nil or record.credentialStorageError ~= nil then return true, false end
		local reference = record.communityCredential == true or record.communityKeyState ~= nil
		local pool, kept, positions = keys.keys(record), {}, {}
		local changed, included = false, false
		for index, key in ipairs(pool) do
			if M.retiredKey(key) then included, changed = true, true
			else kept[#kept + 1], positions[index] = key, #kept + 1 end
		end
		if included then
			for _, field in ipairs({ "keyNames", "keyIds", "keyPaused" }) do
				if type(record[field]) == "table" then
					local out = {}
					for index, position in pairs(positions) do out[position] = record[field][index] end
					record[field] = out
				end
			end
			local selected = positions[record.selectedKey or 1]
			if record.keyMode == "single" and not selected then
				-- The old pin authorized only the removed key. Keep surviving
				-- personal keys behind an explicit reviewed connection Save.
				record.keyMode, record.credentialsOmitted = "rotate", true
			end
			record.selectedKey, record.apiKey, record.keyRotation = selected or 1, table.concat(kept, "\n"), nil
		end
		for _, field in ipairs({ "headers", "query", "params", "health", "repairs", "maxTokensCap", "toolsCap" }) do
			if clearCopies(record[field]) then changed, included = true, true end
		end
		for _, field in ipairs({ "baseUrl", "wsUrl" }) do
			local clean = clearUrl(record[field])
			if clean ~= record[field] then record[field], changed, included = clean, true, true end
		end
		if M.containsKey(record.repairScope) then record.repairScope, changed, included = nil, true, true end
		local hasPersonal = personal(record)
		if not hasPersonal and (record.preset == "projectuai-free" or reference or included and record.preset == "hcnsec") then
			if not edited(record) then return false, true end
			record.credentialsOmitted, changed = true, true
		end
		if M.retiredPreset(record.preset) then
			if not hasPersonal then record.credentialsOmitted = true end
			record.preset = "custom"
			if type(record.note) == "string" and (record.note:find("Enter your personal HCNSEC key", 1, true) == 1
				or record.note:find("Optional access for the Project UAI community", 1, true) == 1) then record.note = nil end
			if record.label == "HCNSEC" or record.label == "Project UAI Free" then record.label = "Custom endpoint" end
			changed = true
		end
		if included and not hasPersonal then record.credentialsOmitted = true end
		if record.communityCredential ~= nil or record.communityKeyState ~= nil then changed = true end
		record.communityCredential, record.communityKeyState = nil, nil
		return true, changed
	end
	function M.apply(snapshot)
		if type(snapshot) ~= "table" then return 0 end
		local changed = 0
		if type(snapshot.agent) == "table" and snapshot.agent.autoFreeRouting ~= nil then
			snapshot.agent.autoFreeRouting, changed = nil, 1
		end
		-- Provider IDs authenticate the vault payload. Filtering while locked
		-- would make a valid legacy vault impossible to unlock.
		if snapshot.credentialVault ~= nil and snapshot.credentialVaultLocked ~= false then return changed end
		local providers = type(snapshot.providers) == "table" and snapshot.providers
		if not providers or type(providers.list) ~= "table" or not util.isArray(providers.list) then return changed end
		local kept, removed, seen, best = {}, {}, {}, nil
		local function order(record)
			local value = tonumber(record.order)
			return value and value == value and math.abs(value) < math.huge and value or 0
		end
		for _, record in ipairs(providers.list) do
			local keep, modified = M.record(record)
			if modified then changed = changed + 1 end
			if keep then
				kept[#kept + 1] = record
				if type(record) == "table" and type(record.id) == "string" then
					seen[record.id] = true
					if record.enabled ~= false and (not best or order(record) < order(best)
						or order(record) == order(best) and tostring(record.id) < tostring(best.id)) then best = record end
				end
			elseif record.id then removed[record.id] = true end
		end
		if #kept ~= #providers.list then
			providers.list = kept
			if not seen[providers.active] then providers.active = best and best.id or "" end
			for _, name in ipairs({ "modelFavorites", "recentModels" }) do
				local buckets = type(snapshot.ui) == "table" and snapshot.ui[name]
				if type(buckets) == "table" then for id in pairs(removed) do buckets[id] = nil end end
			end
		end
		if clearCopies(type(snapshot.identity) == "table" and snapshot.identity.extraHeaders) then changed = changed + 1 end
		return changed
	end
	return M
end
