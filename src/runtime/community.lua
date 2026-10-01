-- Persistent invitation cadence, independent of presentation and UI mounting.
return function(env)
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local M = { invite = "https://discord.gg/9xYyyYuKap" }
	local COOLDOWN = 14 * 24 * 60 * 60 * 1000
	local shown = false

	function M.due()
		if shown or config.get("ui.communityInvite.disabled", false) == true then return false end
		local last = tonumber(config.get("ui.communityInvite.lastShown", 0)) or 0
		if last ~= last or last < 0 or last == math.huge then last = 0 end
		return last == 0 or clock.ms() - last >= COOLDOWN
	end

	function M.markShown()
		shown = true
		config.set("ui.communityInvite.lastShown", clock.ms())
	end

	function M.disable()
		config.set("ui.communityInvite.disabled", true)
	end

	return M
end
