-- Calendar transitions, preference ownership, and cleanup against the bundle.
-- Audit this source before building or running it; native rendering is separate.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local seasonalNames = { "Halloween", "Christmas", "NewYear", "Valentine", "EarthDay", "Pride", "Peace" }
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function sameColor(a, b)
	return a and b and math.abs(a.R - b.R) < 1e-12 and math.abs(a.G - b.G) < 1e-12 and math.abs(a.B - b.B) < 1e-12
end
local h = envMock.new()
local date = { Year = 2026, Month = 10, Day = 29, Hour = 23, Minute = 59, Second = 59 }
local reads = 0
-- The Unix timestamp stays in January: only the player's local calendar may
-- choose a season. Mutating this test's calendar also models a device clock jump.
h.sandbox.DateTime.now = function()
	return { UnixTimestamp = 1767225600, ToLocalTime = function() reads = reads + 1; return date end }
end
local UI = assert(h.boot("dist/uai-ui.lua"))
local window = UI:CreateWindow({ Id = "seasonal-appearance", Palette = "Ocean", ReducedMotion = true })
local section = window:Tab("Main"):Section("State")
local callbacks = 0
local value = section:Toggle({ Id = "enabled", Default = false, Callback = function() callbacks = callbacks + 1 end })
local draft = section:Input({ Id = "draft", Default = "saved", Persist = false })
local input = assert(h.byName("Input", draft.Frame))
input.Text = "unsaved draft"
local frame = window.Frame
local ordinary = window.Theme.Canvas
check("ordinary dates retain the declared palette and opt in by default", window:GetActivePalette() == "Ocean"
	and window:GetAppearance().Palette == "Ocean" and window:GetAppearance().SeasonalTheme)
date = { Year = 2026, Month = 10, Day = 30, Hour = 0, Minute = 0, Second = 0 }
h.settle(1.1)
check("local midnight switches an existing window into Halloween", window:GetActivePalette() == "Halloween"
	and sameColor(window.Theme.Canvas, UI:GetPalette("Halloween", "Dark").Canvas) and not sameColor(window.Theme.Canvas, ordinary))
check("automatic repaint preserves the window, controls, and draft", window.Frame == frame and draft:Get() == "saved"
	and input.Text == "unsaved draft" and not value:Get() and callbacks == 0 and input.BackgroundColor3 == window.Theme.Input)
local exported = window:ExportConfig()
local document = h.json.decode(exported)
check("automatic selection never replaces the saved base palette", document.appearance.palette == "Ocean"
	and document.appearance.seasonalTheme == true and window:GetAppearance().Palette == "Ocean")
check("automatic opt out is a library API preference", window:Get("__uai_appearance_seasonal_theme") == nil)
local labels = {}
for _, option in ipairs(window:Get("__uai_appearance_palette"):GetOptions()) do labels[option.Value] = option.Label end
check("seasonal picker labels retain stable values", labels.NewYear == "New Year" and labels.Valentine == "Valentine's Day"
	and labels.EarthDay == "Earth Day" and labels.Pride == "Pride" and labels.Peace == "Peace Day")
local dialog = window:Dialog({ Title = "Seasonal dialog", Content = "Keep the draft" })
local toast = window:Notify({ Title = "Seasonal notice", Content = "Still here", Duration = 0 })
date = { Year = 2026, Month = 11, Day = 3, Hour = 0, Minute = 0, Second = 0 }
h.settle(60)
check("calendar changes repaint open overlays", not dialog.Closed and dialog.Frame.BackgroundColor3 == window.Theme.Surface
	and toast.Frame.BackgroundColor3 == window.Theme.Surface)
dialog:Close(); toast:Close()
date = { Year = 2026, Month = 10, Day = 30, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
window:Minimize()
date = { Year = 2026, Month = 11, Day = 3, Hour = 0, Minute = 0, Second = 0 }
h.settle(60)
check("November 3 restores the saved palette while minimized", window:GetActivePalette() == "Ocean" and not window.Visible
	and window._launcher.BackgroundColor3 == window.Theme.Canvas and sameColor(window.Theme.Canvas, ordinary))
window:Show()

local cases = {
	{ 2, 13, "Ocean" }, { 2, 14, "Valentine" }, { 2, 15, "Ocean" },
	{ 4, 21, "Ocean" }, { 4, 22, "EarthDay" }, { 4, 23, "Ocean" },
	{ 5, 31, "Ocean" }, { 6, 1, "Pride" }, { 6, 30, "Pride" }, { 7, 1, "Ocean" },
	{ 9, 20, "Ocean" }, { 9, 21, "Peace" }, { 9, 22, "Ocean" },
	{ 10, 29, "Ocean" }, { 10, 30, "Halloween" }, { 10, 31, "Halloween" },
	{ 11, 1, "Halloween" }, { 11, 2, "Halloween" }, { 11, 3, "Ocean" },
	{ 12, 19, "Ocean" }, { 12, 20, "Christmas" }, { 12, 26, "Christmas" }, { 12, 27, "Ocean" },
	{ 12, 30, "Ocean" }, { 12, 31, "NewYear" }, { 1, 1, "NewYear" }, { 1, 2, "NewYear" }, { 1, 3, "Ocean" },
}
for _, year in ipairs({ 2026, 2027, 2032 }) do
	for _, entry in ipairs(cases) do
		date = { Year = year, Month = entry[1], Day = entry[2], Hour = 12, Minute = 0, Second = 0 }
		window:SetAppearance({})
		check("calendar boundary " .. year .. "/" .. entry[1] .. "/" .. entry[2], window:GetActivePalette() == entry[3])
	end
end
date = { Year = 2026, Month = 12, Day = 20, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
local christmas = UI:CreateWindow({ Id = "christmas-created", Theme = "Light", Palette = "Forest", ReducedMotion = true })
check("creation uses the current local season without changing light mode", christmas:GetActivePalette() == "Christmas"
	and christmas:GetTheme() == "Light" and christmas:GetAppearance().Palette == "Forest")
date = { Year = 2027, Month = 1, Day = 1, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
check("a year-boundary clock jump switches live windows to New Year", window:GetActivePalette() == "NewYear"
	and christmas:GetActivePalette() == "NewYear")
date = { Year = 2026, Month = 10, Day = 31, Hour = 12, Minute = 0, Second = 0 }
window:SetAppearance({ Palette = "Christmas" })
check("manual seasonal palette takes precedence over another calendar season", window:GetActivePalette() == "Christmas"
	and window:GetAppearance().Palette == "Christmas" and window._seasonalCancel == nil)
date = { Year = 2027, Month = 6, Day = 15, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
check("manual seasonal palette remains selected year-round", window:GetActivePalette() == "Christmas")
for _, name in ipairs(seasonalNames) do
	window:SetAppearance({ Palette = name, SeasonalTheme = true })
	check("manual " .. name .. " takes precedence over Pride month", window:GetActivePalette() == name and window._seasonalCancel == nil)
	local selected = window:ExportConfig()
	window:SetAppearance({ Palette = "Ocean" })
	check("profile restores manual " .. name, window:ImportConfig(selected) and window:GetAppearance().Palette == name
		and window:GetActivePalette() == name and window._seasonalCancel == nil)
	window:SetAppearance({ Palette = name, SeasonalTheme = false })
	check("manual " .. name .. " works with automation disabled", window:GetActivePalette() == name)
end
window:SetAppearance({ Palette = "Ocean", SeasonalTheme = true })
date = { Year = 2026, Month = 10, Day = 30, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
window:SetAppearance({ SeasonalTheme = false })
check("programmatic opt out restores the saved palette immediately and cancels refresh", window:GetActivePalette() == "Ocean"
	and not window:GetAppearance().SeasonalTheme and window._seasonalCancel == nil and callbacks == 0)
local optOut = window:ExportConfig()
window:SetAppearance({ SeasonalTheme = true })
check("reenabling automation applies the current season immediately", window:GetActivePalette() == "Halloween" and window._seasonalCancel ~= nil)
check("profiles retain the automation preference", window:ImportConfig(optOut) and not window:GetAppearance().SeasonalTheme
	and window:GetActivePalette() == "Ocean")
document = h.json.decode(optOut); document.appearance.seasonalTheme = nil
check("legacy profiles preserve the current seasonal preference", window:ImportConfig(h.json.encode(document)) and not window:GetAppearance().SeasonalTheme)
local before = window:ExportConfig()
check("invalid automation patches fail atomically", not pcall(function() window:SetAppearance({ SeasonalTheme = "yes", Palette = "Forest" }) end)
	and window:ExportConfig() == before)
document.appearance.seasonalTheme = "yes"; document.values.enabled.value = true
check("invalid imported automation prevents all writes", not window:ImportConfig(h.json.encode(document)) and window:ExportConfig() == before and not value:Get())
check("invalid constructor automation does not replace a live window", not pcall(function() UI:CreateWindow({ Id = window.Id, SeasonalTheme = 1 }) end)
	and UI:GetWindow(window.Id) == window and window.Alive)
local accent, surface = h.dt.Color3.fromRGB(108, 168, 210), h.dt.Color3.fromRGB(38, 40, 46)
window:SetAppearance({ Palette = "Forest", SeasonalTheme = true, Accent = accent, Colors = { Surface = surface } })
check("custom accent and color overrides take precedence over seasonal tokens", window:GetActivePalette() == "Halloween"
	and window.Theme.Accent == accent and window.Theme.Surface == surface and window:GetAppearance().Palette == "Forest")
date = { Year = 2026, Month = 11, Day = 3, Hour = 12, Minute = 0, Second = 0 }
h.settle(60)
check("season end preserves custom overrides", window:GetActivePalette() == "Forest" and window.Theme.Accent == accent and window.Theme.Surface == surface)

local function luminance(color)
	local function linear(n) return n <= 0.04045 and n / 12.92 or ((n + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end
local function contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
for _, name in ipairs(seasonalNames) do
	for _, mode in ipairs({ "Dark", "Light" }) do
		window:SetAppearance({ Palette = name, Theme = mode, Accent = false, Colors = {}, Contrast = "Standard" })
		check(name .. " " .. mode .. " text and actions remain readable", contrast(window.Theme.Text, window.Theme.Surface) >= 7
			and contrast(window.Theme.Muted, window.Theme.Input) >= 4.5 and contrast(window.Theme.OnPrimary, window.Theme.Primary) >= 7
			and contrast(window.Theme.OnAccent, window.Theme.Accent) >= 4.5)
		window:SetAppearance({ Contrast = "High" })
		check(name .. " " .. mode .. " high contrast strengthens text and edges", contrast(window.Theme.Text, window.Theme.Surface) >= 7
			and contrast(window.Theme.Edge, window.Theme.Surface) >= 3 and contrast(window.Theme.OnAccent, window.Theme.Accent) >= 4.5)
	end
end
window:SetAppearance({ Palette = "Ocean", SeasonalTheme = true })
h.settle(0.3)
local paint = 0
for _ in pairs(window._paint) do paint = paint + 1 end
h.settle(180)
local afterPaint = 0
for _ in pairs(window._paint) do afterPaint = afterPaint + 1 end
check("ordinary date checks do not remount or grow color bindings", window.Frame == frame and afterPaint == paint and callbacks == 0)
local replaced = UI:CreateWindow({ Id = "replace-seasonal", ReducedMotion = true })
local replacement = UI:CreateWindow({ Id = "replace-seasonal", ReducedMotion = true })
check("same-Id replacement cancels the previous calendar refresh", not replaced.Alive and replaced._seasonalCancel == nil and replacement._seasonalCancel ~= nil)
check("attribution remains fixed in themed windows", h.byName("Attribution", window.Frame).Text == "Project UAI | UI LIB.")
UI:DestroyAll(); h.settle(0.3)
local finalReads = reads
h.settle(120)
check("destroy releases calendar callbacks and all owned resources", reads == finalReads and window._seasonalCancel == nil
	and next(window._scope.items) == nil and #h.errors() == 0 and #h.instanceState.typeErrors == 0)
local unsupported = envMock.new()
local plainUI = assert(unsupported.boot("dist/uai-ui.lua"))
local plain = plainUI:CreateWindow({ Id = "no-local-date", Palette = "Rose" })
check("a host without local calendar support keeps its preference without polling", plain:GetActivePalette() == "Rose" and plain._seasonalCancel == nil)
plain:Destroy(); unsupported.settle(0.3)
check("unsupported local calendar causes no host errors", #unsupported.errors() == 0 and #unsupported.instanceState.typeErrors == 0)
print("UI library seasons: " .. passed .. " checks passed")
