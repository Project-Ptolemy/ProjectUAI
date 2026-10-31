-- Annual local-date appearance schedule; no presentation or saved-state changes.
return function(env)
	local M = {}
	local THEMES = {
		halloween = true, christmas = true, newyear = true,
		valentine = true, earthday = true, pride = true, peace = true,
	}

	function M.forDate(month, day)
		if type(month) ~= "number" or type(day) ~= "number"
			or month % 1 ~= 0 or day % 1 ~= 0 or day < 1 or day > 31 then return nil end
		if month == 2 and day == 14 then return "valentine" end
		if month == 4 and day == 22 then return "earthday" end
		if month == 6 and day <= 30 then return "pride" end
		if month == 9 and day == 21 then return "peace" end
		if (month == 10 and day >= 30) or (month == 11 and day <= 2) then return "halloween" end
		if month == 12 and day >= 20 and day <= 26 then return "christmas" end
		if (month == 12 and day == 31) or (month == 1 and day <= 2) then return "newyear" end
		return nil
	end

	function M.current()
		-- Read the host's current local calendar each time, including DST changes.
		local ok, date = pcall(function() return DateTime.now():ToLocalTime() end)
		if ok and type(date) == "table" and type(date.Month) == "number" and type(date.Day) == "number" then
			return M.forDate(date.Month, date.Day)
		end
		local formatted, text = pcall(function() return DateTime.now():FormatLocalTime("MM-dd", "en-us") end)
		if formatted and type(text) == "string" then
			local month, day = text:match("^(%d%d)%-(%d%d)$")
			if month then return M.forDate(tonumber(month), tonumber(day)) end
		end
		-- Without a usable local-calendar API, preserve the saved appearance.
		return nil
	end

	function M.resolve(manual, automatic)
		if THEMES[manual] then return manual end
		return automatic ~= false and M.current() or "default"
	end

	return M
end
