-- Local calendar boundaries, saved preferences and native seasonal theme lifetime.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Seasonal themes")
local case, check = suite.case, suite.check
local THEMES = { "halloween", "christmas", "newyear", "valentine", "earthday", "pride", "peace" }

local function calendar(f, date)
	local original = f.h.sandbox.DateTime.now
	f.h.sandbox.DateTime.now = function()
		local value = original()
		value.ToLocalTime = function() return { Year = date.year, Month = date.month, Day = date.day } end
		return value
	end
end

local function ratio(a, b)
	local function channel(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
	local function light(v) return channel(v.R) * 0.2126 + channel(v.G) * 0.7152 + channel(v.B) * 0.0722 end
	local x, y = light(a), light(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end

case("annual windows include their last day and use current local calendar", function()
	local f = F.new()
	local date = { year = 2026, month = 10, day = 29 }
	calendar(f, date)
	local schedule = f.env.require("runtime/seasonal_theme")
	local boundaries = {
		{ 2, 13 }, { 2, 14, "valentine" }, { 2, 15 },
		{ 4, 21 }, { 4, 22, "earthday" }, { 4, 23 },
		{ 5, 31 }, { 6, 1, "pride" }, { 6, 15, "pride" }, { 6, 30, "pride" }, { 7, 1 },
		{ 9, 20 }, { 9, 21, "peace" }, { 9, 22 },
		{ 10, 29 }, { 10, 30, "halloween" }, { 10, 31, "halloween" },
		{ 11, 1, "halloween" }, { 11, 2, "halloween" }, { 11, 3 },
		{ 12, 19 }, { 12, 20, "christmas" }, { 12, 25, "christmas" }, { 12, 26, "christmas" }, { 12, 27 },
		{ 12, 30 }, { 12, 31, "newyear" }, { 1, 1, "newyear" }, { 1, 2, "newyear" }, { 1, 3 },
	}
	for _, year in ipairs({ 2026, 2027, 2028 }) do
		date.year = year
		for _, entry in ipairs(boundaries) do
			date.month, date.day = entry[1], entry[2]
			check("local " .. year .. "/" .. entry[1] .. "/" .. entry[2], schedule.current() == entry[3])
		end
	end
	check("malformed dates cannot activate a holiday", schedule.forDate(10, 0) == nil and schedule.forDate(11, 1.5) == nil
		and schedule.forDate(0 / 0, 31) == nil and schedule.forDate("10", 31) == nil and schedule.forDate(6, 31) == nil)
	f.close()
end)

case("unavailable local calendars preserve Standard and formatter fallback works", function()
	local f = F.new()
	local schedule = f.env.require("runtime/seasonal_theme")
	check("mock UTC January 1 cannot become a guessed local holiday", schedule.current() == nil and schedule.resolve("default", true) == "default")
	local original = f.h.sandbox.DateTime.now
	f.h.sandbox.DateTime.now = function()
		local value = original()
		value.ToLocalTime = function() error("local calendar unavailable") end
		value.FormatLocalTime = function(_, pattern) assert(pattern == "MM-dd"); return "12-26" end
		return value
	end
	check("local formatter retains the inclusive Christmas closing day", schedule.current() == "christmas")
	for _, name in ipairs(THEMES) do check(name .. " manual choice wins over the local date", schedule.resolve(name, true) == name) end
	check("disabled automatic schedule uses saved Standard", schedule.resolve("default", false) == "default")
	f.close()
end)

case("live transitions restore saved choices and stop with the screen or unload", function()
	local f = F.new()
	local date = { year = 2026, month = 10, day = 29 }
	calendar(f, date)
	local config = f.env.require("runtime/config")
	config.set("ui.accent", "aurora", { transient = true })
	local theme = f.env.require("ui/theme")
	local screen = f.h.Instance.new("ScreenGui", f.h.services.CoreGui)
	theme.watchSeasonal(screen)
	local changes = 0
	local stop = theme.changed:connect(function() changes = changes + 1 end)
	local saved = f.h.json.encode(config.data)
	date.day = 30; f.h.sched.advance(60)
	check("October 30 activates Halloween while preserving saved preference", theme.themeName == "halloween"
		and theme.accentName == "aurora" and config.get("ui.theme") == "default" and f.h.json.encode(config.data) == saved)
	f.h.sched.advance(120)
	check("ordinary minute checks do not rebuild again", changes == 1)
	date.month, date.day = 11, 3; f.h.sched.advance(60)
	check("November 3 restores the saved standard accent", theme.themeName == "default" and theme.color.accent == theme.ACCENTS.aurora.base
		and changes == 2 and f.h.json.encode(config.data) == saved)
	for _, entry in ipairs({ { 2, 14, "valentine" }, { 4, 22, "earthday" }, { 6, 1, "pride" }, { 9, 21, "peace" } }) do
		date.month, date.day = entry[1], entry[2]; f.h.sched.advance(60)
		check("an already-open client enters " .. entry[3], theme.themeName == entry[3] and f.h.json.encode(config.data) == saved)
	end
	date.month, date.day = 12, 20; f.h.sched.advance(60)
	check("an already-open client enters Christmas", theme.themeName == "christmas")
	config.set("ui.theme", "halloween", { transient = true })
	date.day = 31; f.h.sched.advance(60)
	check("explicit Halloween stays active through New Year", theme.themeName == "halloween")
	config.set("ui.theme", "default", { transient = true })
	check("returning to Standard immediately resolves New Year", theme.themeName == "newyear")
	config.set("ui.seasonalThemes", false, { transient = true })
	check("opt-out immediately restores saved colors", theme.themeName == "default" and theme.color.accent == theme.ACCENTS.aurora.base)
	config.set("ui.seasonalThemes", true, { transient = true })
	local before = changes
	screen:Destroy(); date.month, date.day = 1, 3; f.h.sched.advance(60)
	check("screen destruction stops automatic repaint", changes == before and theme.themeName == "newyear")
	stop(); f.close()
	config.set("ui.theme", "christmas", { transient = true })
	check("unload releases the theme configuration listener", theme.themeName == "newyear")
	f.healthy()
end)

case("every seasonal palette keeps text and code readable with distinct surfaces", function()
	local f = F.new()
	local theme, config = f.env.require("ui/theme"), f.env.require("runtime/config")
	local standard = theme.color
	local canvases = {}
	for _, name in ipairs(THEMES) do
		config.set("ui.theme", name, { transient = true })
		local c = theme.color
		canvases[name] = c.canvas
		for _, pair in ipairs({
			{ c.text, c.canvas }, { c.textSecondary, c.canvas }, { c.textTertiary, c.surfaceOverlay },
			{ c.accentHot, c.canvas }, { c.textOnAccent, c.accent }, { c.onSolid, c.solid }, { c.text, c.bubbleUser },
			{ c.codeText, c.codeSurface }, { c.codeGutter, c.codeBar }, { c.codeAddText, c.codeAddSurface },
			{ c.codeRemoveText, c.codeRemoveSurface },
		}) do check(name .. " readable text pair", ratio(pair[1], pair[2]) >= 4.5) end
		check(name .. " hairlines remain visible", ratio(c.borderSubtle, c.surfaceRaised) >= 1.25)
		check(name .. " retains semantic status colors", c.success == standard.success and c.warn == standard.warn
			and c.danger == standard.danger and c.info == standard.info)
		for _, pair in ipairs({ { c.success, c.successSurface }, { c.warn, c.warnSurface }, { c.danger, c.dangerSurface }, { c.info, c.infoSurface } }) do
			check(name .. " readable status pair", ratio(pair[1], pair[2]) >= 3)
		end
		config.set("ui.codeTheme", "light", { transient = true })
		check(name .. " retains explicit light code preference", theme.codeThemeName == "light" and theme.code == theme.CODE_THEMES.light
			and ratio(theme.color.codeText, theme.color.codeSurface) >= 4.5)
		config.set("ui.codeTheme", "dark", { transient = true })
	end
	for left, color in pairs(canvases) do
		check(left .. " has a seasonal surface", color ~= standard.canvas)
		for right, other in pairs(canvases) do if left < right then check(left .. " differs from " .. right, color ~= other) end end
	end
	local transfer, util = f.env.require("runtime/config_transfer"), f.env.require("runtime/util")
	local legacy = util.deepCopy(config.defaults)
	legacy.ui.theme, legacy.ui.seasonalThemes = nil, nil
	local imported = assert(transfer.validate(legacy))
	check("old configurations adopt the new automatic default", imported.ui.theme == "default" and imported.ui.seasonalThemes == true)
	for _, name in ipairs(THEMES) do
		legacy.ui.theme, legacy.ui.seasonalThemes = name, false
		local parsed = assert(transfer.validate(legacy))
		check(name .. " manual choice and opt-out survive configuration transfer", parsed.ui.theme == name and parsed.ui.seasonalThemes == false)
	end
	legacy.ui.theme = "unknown"
	check("unsupported imported themes are rejected", transfer.validate(legacy) == nil)
	legacy.ui.theme, legacy.ui.seasonalThemes = "default", "yes"
	check("non-boolean automatic preferences are rejected", transfer.validate(legacy) == nil)
	f.healthy(); f.close()
end)

case("native Appearance exposes manual themes and the automatic toggle on a narrow screen", function()
	local f = F.ui(320, 568)
	local catalog = f.env.require("runtime/settings_catalog")
	local searchable = {}
	for _, item in ipairs(catalog.search("Halloween")) do searchable[item.path] = item.category end
	check("manual and automatic themes are discoverable in General", searchable["ui.theme"] == "general" and searchable["ui.seasonalThemes"] == "general")
	for _, query in ipairs({ "Valentine", "Earth Day", "Pride", "Peace" }) do
		local paths = {}
		for _, item in ipairs(catalog.search(query)) do paths[item.path] = item.category end
		check(query .. " manual and automatic settings are searchable", paths["ui.theme"] == "general" and paths["ui.seasonalThemes"] == "general")
	end
	check("automatic date schedule is discoverable", catalog.search("October 30")[1].path == "ui.seasonalThemes")
	for _, query in ipairs({ "February 14", "April 22", "June", "September 21" }) do
		check(query .. " automatic date is searchable", catalog.search(query)[1].path == "ui.seasonalThemes")
	end
	check("General settings build", f.env.require("ui/settingspanes").render("general", f.host))
	f.h.settle(0.3)
	local picker = assert(f.h.byName("Select_Theme", f.env.root))
	check("theme picker has a usable width", picker.AbsoluteSize.X > 0 and picker.AbsoluteSize.X <= f.host.AbsoluteSize.X)
	local config = f.env.require("runtime/config")
	for _, name in ipairs(THEMES) do
		f.h.click(picker); f.h.settle(0.2)
		f.h.click(assert(f.h.byName("Option_" .. name, f.env.root))); f.h.settle(0.2)
		check(name .. " manual option writes the shared preference", config.get("ui.theme") == name)
	end
	local toggleRow
	for _, node in ipairs(f.host:GetDescendants()) do
		if node:GetAttribute("UAISettingPath") == "ui.seasonalThemes" then toggleRow = node; break end
	end
	f.h.click(assert(f.h.byName("Switch", assert(toggleRow))))
	check("automatic seasonal toggle writes the shared preference", config.get("ui.seasonalThemes") == false)
	f.healthy(); f.close()
end)

suite.finish()
