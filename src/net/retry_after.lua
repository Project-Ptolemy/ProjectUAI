-- Retry-After supports delay seconds and the standard GMT HTTP-date format.
return function(env)
	local clock = env.require("runtime/clock")
	local util = env.require("runtime/util")
	local M = {}
	local months = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }
	function M.seconds(value, nowMs)
		if type(value) ~= "string" and type(value) ~= "number" then return nil end
		local text = util.trim(tostring(value))
		local seconds = tonumber(text)
		if seconds then return seconds == seconds and seconds >= 0 and seconds < math.huge and seconds or nil end
		local day, month, year, hour, minute, second = text:match("^%a%a%a, (%d%d) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT$")
		day, month, year = tonumber(day), months[tostring(month):lower()], tonumber(year)
		hour, minute, second = tonumber(hour), tonumber(minute), tonumber(second)
		if not day or not month or year < 1970 or day < 1 or day > 31 or hour > 23 or minute > 59 or second > 59 then return nil end
		local days = clock.daysFromCivil(year, month, day)
		local checkYear, checkMonth, checkDay = clock.civilFromDays(days)
		if checkYear ~= year or checkMonth ~= month or checkDay ~= day then return nil end
		local now = tonumber(nowMs) or clock.ms()
		if now ~= now or math.abs(now) == math.huge then return nil end
		return math.max(0, days * 86400 + hour * 3600 + minute * 60 + second - now / 1000)
	end
	return M
end
