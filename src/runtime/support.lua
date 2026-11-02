-- Shared support copy, independent of configuration, logging and presentation.
return function(env)
	local M = { invite = "https://discord.gg/9xYyyYuKap" }

	local function freeUsageCode(value)
		local lower = tostring(value or ""):lower()
		return lower == "freeusagelimiterror" or lower == "ratelimit.freeusagelimiterror"
	end
	local function freeUsageMessage(value)
		return tostring(value or ""):lower():find("free usage limit reached. free models work in opencode", 1, true) ~= nil
	end
	local function freeUsageText(value)
		local lower = tostring(value or ""):lower()
		return lower:find("freeusagelimiterror", 1, true) ~= nil
			or freeUsageMessage(value)
	end

	-- Callers decode complete JSON before applying this retry policy. Ordinary
	-- rate limits, completion text and partial SSE frames cannot establish it.
	function M.isOpencodeFreeUsage(payload)
		if type(payload) ~= "table" then return false end
		local failure = payload.error
		if failure == nil then
			if payload.type ~= "error" and not freeUsageCode(payload.type)
				and not freeUsageCode(payload.name) and not freeUsageCode(payload.code) then return false end
			failure = payload
		end
		if type(failure) == "string" then return freeUsageCode(failure) or freeUsageMessage(failure) end
		if type(failure) ~= "table" then return false end
		return freeUsageCode(failure.type) or freeUsageCode(failure.name) or freeUsageCode(failure.code)
			or freeUsageMessage(failure.message)
	end

	function M.opencodeProblem(message)
		local lower = tostring(message or ""):lower()
		if freeUsageText(message) then return "free-usage" end
		if lower:find("go model requires global regions", 1, true) then return "region" end
		if lower:find("active opencode go subscription is required", 1, true) then return "subscription" end
		if lower:find("opencode proxy endpoint", 1, true) and (lower:find("deprecated", 1, true)
			or lower:find("retired", 1, true)) then return "retired" end
	end

	function M.error(message)
		local text = tostring(message or "An unexpected error occurred")
		-- Cancellation is a control signal used verbatim throughout the runtime.
		if text == "aborted" then return text end
		local lower = text:lower()
		local problem = M.opencodeProblem(text)
		if problem == "free-usage" and not lower:find("opencode refused this direct free-model request", 1, true) then
			text = text .. " -- " .. M.opencodeFreeUsage()
		elseif problem == "region" and not lower:find("review this privacy choice", 1, true) then
			text = text .. " -- In the OpenCode workspace that owns this key, this model requires Privacy regions set to Global. "
				.. "Review this privacy choice in OpenCode before changing it."
		elseif problem == "subscription" and not lower:find("check the key's workspace", 1, true) then
			text = text .. " -- Check the key's workspace and its Go subscription in OpenCode. "
				.. "If it is already active, report this refusal to OpenCode support. A public model list does not confirm subscription access."
		elseif problem == "retired" and not lower:find("a 410 does not validate", 1, true) then
			text = text .. " -- Select OpenCode Go for a Go subscription or OpenCode Zen for Zen access. "
				.. "A 410 does not validate your key or subscription."
		elseif not problem and not lower:find("requires the uai relay app", 1, true) and (lower:find("freetiererror", 1, true)
			or lower:find("can only be used from within opencode", 1, true)) then
			text = text .. " -- " .. M.opencode()
		end
		if text:find(M.invite, 1, true) then return text end
		return text .. "\nHelp and updates: " .. M.invite
	end

	function M.opencodeFreeUsage()
		return "OpenCode refused this direct free-model request. The installed CLI can still have access. "
			.. "Changing keys may not restore it. Update the UAI client and Project UAI Desktop Bridge for API-key access, "
			.. "or use the installed OpenCode tunnel through the bridge."
	end

	function M.opencode()
		return "If direct desktop access is refused, update the UAI client and Project UAI Desktop Bridge for API-key access, "
			.. "or use the installed OpenCode CLI through the bridge. "
			.. "Mobile OpenCode requires the UAI Relay app from Discord; install and start the app, then connect it in UAI. "
			.. "The OpenCode proxy is retired. Project UAI Free remains an alternative."
	end

	return M
end
