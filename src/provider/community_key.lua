-- The intentionally distributed Project UAI Free credential. Importing this
-- module sends no traffic. Never replace it with a private development key.
return function(env)
	local url = env.require("net/url")
	local util = env.require("runtime/util")
	local M = {}
	local credential = env.require("runtime/community_credential")
	local key = credential.key
	local function official(record)
		if type(record) ~= "table" then return false end
		local base = url.normaliseBase(record.baseUrl)
		local parsed = url.parse(base)
		return parsed ~= nil and parsed.scheme == "https" and parsed.authority:lower() == "api.hcnsec.cn"
			and parsed.path == "/v1" and (not parsed.query or parsed.query == "")
	end
	function M.eligible(record)
		return type(record) == "table" and record.preset == "projectuai-free" and official(record)
	end
	function M.apply(record)
		if not M.eligible(record) then return nil, "Project UAI Free requires the official HCNSEC endpoint. Help: https://discord.gg/9xYyyYuKap" end
		record.apiKey = key
		record.authStyle = "bearer"
		record.keyRotation = nil
		record.keyNames, record.keyMode, record.selectedKey, record.keyPaused = nil, "rotate", 1, nil
		record.keyIds = nil
		for name, value in pairs(record.headers or {}) do
			local lower = type(name) == "string" and name:lower() or ""
			if (lower == "authorization" and tostring(value) ~= "Bearer " .. key)
				or ((lower == "x-api-key" or lower == "api-key") and tostring(value) ~= key) then
				record.headers[name] = nil
			end
		end
		return true
	end
	local function usesIncluded(record, expected)
		if not official(record) or record.apiKey ~= expected or (record.authStyle or "bearer") ~= "bearer" then return false end
		-- Extra headers win over generated authentication. A personal override
		-- must not keep the included-access badge or its zero-cost estimate.
		for name, value in pairs(record.headers or {}) do
			local lower = type(name) == "string" and name:lower() or ""
			if lower == "authorization" and tostring(value) ~= "Bearer " .. expected then return false end
			if (lower == "x-api-key" or lower == "api-key") and tostring(value) ~= expected then return false end
		end
		return true
	end
	function M.isApplied(record)
		return M.eligible(record) and usesIncluded(record, key)
	end
	-- Preset changes remove only known public credentials, even after a draft's
	-- endpoint or auth style was edited. Remaining personal keys keep their IDs,
	-- labels, pauses and selected position through the ordinary key-pool API.
	function M.clear(record)
		local keys = env.require("runtime/provider_keys")
		local pool = keys.keys(record)
		local removes = {}
		for index, value in ipairs(pool) do
			if value == key or credential.isRetired(value) then removes[#removes + 1] = index end
		end
		if #removes > 0 then
			local valid, why = keys.validate(record)
			if not valid then return nil, why end
			for index = #removes, 1, -1 do keys.remove(record, removes[index]) end
		end
		for name, value in pairs(type(record.headers) == "table" and record.headers or {}) do
			local raw = type(value) == "string" and value:gsub("^[Bb]earer%s+", "") or ""
			if raw == key or credential.isRetired(raw) then record.headers[name] = nil end
		end
		record.communityCredential, record.communityKeyState = nil, nil
		return true
	end
	function M.migrate(record)
		if not official(record) or (record.preset ~= "hcnsec" and record.preset ~= "projectuai-free")
			or not credential.isRetired(record.apiKey) then return false end
		-- Replace only the exact old included credential and matching auth copies.
		-- Preserve personal header overrides and key preferences; usage IDs cannot
		-- follow a different credential into its new accounting history.
		local previous = record.apiKey
		record.apiKey, record.keyIds, record.keyRotation = key, nil, nil
		for name, value in pairs(record.headers or {}) do
			local lower = type(name) == "string" and name:lower() or ""
			if lower == "authorization" and value == "Bearer " .. previous then record.headers[name] = "Bearer " .. key
			elseif (lower == "x-api-key" or lower == "api-key") and value == previous then record.headers[name] = key end
		end
		return true
	end
	function M.restore(record)
		if not official(record) or (record.preset ~= "hcnsec" and record.preset ~= "projectuai-free")
			or record.communityCredential ~= true or util.trim(record.apiKey) ~= "" then return false end
		local state = record.communityKeyState
		if state ~= nil then
			if type(state) ~= "table" or type(state.revision) ~= "string" or state.revision == "" then return false end
			local metadata = { apiKey = key }
			local fields = { "keyNames", "keyIds", "keyPaused", "keyMode", "selectedKey" }
			for _, field in ipairs(fields) do metadata[field] = util.deepCopy(state[field]) end
			if not env.require("runtime/provider_keys").validate(metadata) then return false end
			for _, field in ipairs(fields) do record[field] = metadata[field] end
			if state.revision ~= credential.revision then record.keyIds, record.keyRotation = nil, nil end
			record.communityKeyState = nil
		end
		-- Restore only the included key and its known metadata. Connection fields
		-- and explicit personal auth overrides retain their existing values.
		record.apiKey = key
		return true
	end

	-- Earlier releases used one HCNSEC preset for both access types. Migrate only
	-- effective community access; personal keys, pools and custom names survive.
	function M.separate(record)
		if type(record) ~= "table" or record.preset ~= "hcnsec" then return false end
		if usesIncluded(record, key) then
			record.preset = "projectuai-free"
			if record.label == "HCNSEC" or record.label == "Project UAI Free" then record.label = "Project UAI Free" end
			return true
		end
		if record.label == "Project UAI Free" then record.label = "HCNSEC"; return true end
		return false
	end

	-- The window opens at 20:00 and closes at 12:00 the following midday, so the
	-- morning half is part of the same interval rather than a second one.
	M.hours = "20:00-12:00 UTC+8 (Beijing/Singapore)"
	M.shortHours = "20:00-12:00 UTC+8"
	local OPEN_HOUR, CLOSE_HOUR = 20, 12

	-- This is local request guidance, not upstream access control. Fixed UTC+8
	-- avoids the host's local timezone and daylight-saving settings entirely.
	function M.availability(record, atMs)
		if not M.isApplied(record) then return { applies = false, open = true } end
		local now = atMs or env.require("runtime/clock").ms()
		if type(now) ~= "number" or now ~= now or math.abs(now) == math.huge then
			return { applies = true, open = false, hours = M.hours,
				message = "Project UAI Free cannot determine its scheduled hours. Check your device clock. Available daily " .. M.hours .. "." }
		end
		local hour, day = 3600000, 86400000
		local shifted = now + 8 * hour
		local sinceMidnight = shifted % day
		local midnight = now - sinceMidnight
		local open = sinceMidnight < CLOSE_HOUR * hour or sinceMidnight >= OPEN_HOUR * hour
		local nextOpen = midnight + OPEN_HOUR * hour
		if sinceMidnight >= OPEN_HOUR * hour then nextOpen = nextOpen + day end
		local nextClose = midnight + CLOSE_HOUR * hour
		if sinceMidnight >= CLOSE_HOUR * hour then nextClose = nextClose + day end
		return { applies = true, open = open, hours = M.hours, nextOpenMs = nextOpen, nextCloseMs = nextClose,
			message = open and ("Project UAI Free is within its daily " .. M.hours .. " schedule. Shared capacity and speed can vary.")
				or ("Project UAI Free is outside its daily " .. M.hours .. " schedule. Try again from 20:00 UTC+8 or choose another provider.") }
	end

	-- Remaining time in the form a countdown label reads: minutes while the answer
	-- is hours away, seconds inside the last minute so the number visibly moves.
	function M.remaining(ms)
		local seconds = math.max(0, math.floor((tonumber(ms) or 0) / 1000))
		if seconds < 60 then return tostring(seconds) .. "s" end
		if seconds < 3600 then return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60) end
		return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
	end

	-- The live half of the schedule message: what the next change is and when.
	-- Nil when the record is not on included access, so a caller can leave its
	-- own wording in place.
	function M.countdown(record, atMs)
		local status = M.availability(record, atMs)
		if not status.applies then return nil end
		local now = atMs or env.require("runtime/clock").ms()
		local target = status.open and status.nextCloseMs or status.nextOpenMs
		if type(target) ~= "number" then return { open = false, text = "Check device clock", hours = M.hours } end
		local left = target - now
		return { open = status.open, ms = left, opensAt = status.nextOpenMs, closesAt = status.nextCloseMs,
			text = (status.open and "Closes in " or "Opens in ") .. M.remaining(left) }
	end

	function M.problem(record, atMs)
		local status = M.availability(record, atMs)
		if not status.open then return status.message end
	end
	return M
end
