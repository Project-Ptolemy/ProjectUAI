-- Read the player's calendar afresh so daylight-saving and clock changes remain
-- local. Hosts without the local-date API retain their selected palette.
return function(env)
	local M = {}
	function M.current()
		local ok, date = pcall(function() return DateTime.now():ToLocalTime() end)
		if ok and type(date) == "table" and type(date.Month) == "number" and type(date.Day) == "number" then return date end
		return nil
	end
	function M.active(date)
		if not date then return nil end
		local month, day = date.Month, date.Day
		if month == 2 and day == 14 then return "Valentine" end
		if month == 4 and day == 22 then return "EarthDay" end
		if month == 6 and day >= 1 and day <= 30 then return "Pride" end
		if month == 9 and day == 21 then return "Peace" end
		if month == 10 and day >= 30 and day <= 31 or month == 11 and day >= 1 and day <= 2 then return "Halloween" end
		if month == 12 and day >= 20 and day <= 26 then return "Christmas" end
		if month == 12 and day == 31 or month == 1 and day >= 1 and day <= 2 then return "NewYear" end
		return nil
	end
	function M.manual(palette)
		return env.require("palettes").isSeasonal(palette)
	end
	function M.palette(palette, enabled)
		if not enabled or M.manual(palette) then return palette end
		return M.active(M.current()) or palette
	end
	function M.nextCheck()
		local date = M.current()
		if date and type(date.Hour) == "number" and type(date.Minute) == "number" and type(date.Second) == "number" then
			local remaining = 86400 - (date.Hour * 3600 + date.Minute * 60 + date.Second)
			return math.max(1, math.min(60, remaining))
		end
		return 60
	end
	return M
end
