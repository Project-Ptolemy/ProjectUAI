-- Automatic personalization and validated profiles against the shipped bundle.
-- Manually audit source and test edits before building and running this file.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function count(map) local n = 0; for _ in pairs(map) do n = n + 1 end; return n end
local function sameColor(a, b)
	return a and b and math.abs(a.R - b.R) < 1e-12 and math.abs(a.G - b.G) < 1e-12 and math.abs(a.B - b.B) < 1e-12
end
local h = envMock.new()
local UI = assert(h.boot("dist/uai-ui.lua"))
local dt = h.dt
local accent, surface, textColor = dt.Color3.fromRGB(103, 160, 215), dt.Color3.fromRGB(35, 39, 49), dt.Color3.fromRGB(242, 232, 216)
local window = UI:CreateWindow({ Id = "appearance-contract", Accent = accent, CornerRadius = 6, TextScale = 1.2, ReducedMotion = true, Colors = { Surface = surface } })
local defaultWindow = UI:CreateWindow({ Id = "appearance-defaults" })
local appearanceTab = window.Tabs[1]
local first = window:Tab("Main")
local second = window:Tab("Tools")
check("every window supplies Appearance and keeps consumer tabs first", appearanceTab.Id == "__uai_appearance_tab"
	and appearanceTab.Title == "Appearance" and window.Tabs[1] == first and window.Tabs[2] == second
	and window.Tabs[#window.Tabs] == appearanceTab and window._activeTab == first and #defaultWindow.Tabs == 1)
check("default window corners are restrained", defaultWindow:GetAppearance().CornerRadius == 8)
local function builtin(id) return assert(window:Get("__uai_appearance_" .. id), "missing appearance control " .. id) end
local function node(name, parent) return assert(h.byName(name, parent or window.ScreenGui), "missing " .. name) end
check("personalization values are reflected at creation", builtin("theme"):Get() == "Dark" and sameColor(builtin("accent"):Get(), accent)
	and builtin("corner_radius"):Get() == 6 and builtin("text_scale"):Get() == 120 and builtin("reduced_motion"):Get())
local advanced = 0
for _, section in ipairs(appearanceTab.Sections) do
	if section.Collapsed then advanced = advanced + 1 end
	for _, control in ipairs(section.Controls) do check("built-in " .. control.Id .. " has one appearance persistence source", control.Persist == false) end
end
check("advanced palettes begin collapsed", advanced == 5)
local state = first:Section("State")
local callbacks = 0
local enabled = state:Toggle({ Id = "enabled", Default = false, Callback = function() callbacks = callbacks + 1 end })
local draft = state:Input({ Id = "draft", Default = "saved", Persist = false })
local field = node("Input", draft.Frame)
field.Text = "unfinished"
first.Frame.CanvasPosition = dt.Vector2.new(0, 27)
local scroll, frame = first.Frame.CanvasPosition, window.Frame
local reflected = 0
local unsubscribe = builtin("theme"):OnChanged(function() reflected = reflected + 1 end)
window:SetAppearance({ Theme = "Light", Colors = { Surface = surface, Text = textColor }, CornerRadius = 4, TextScale = 1.35, ReducedMotion = false })
check("appearance changes repaint mounted surfaces and text", window.Theme.Surface == surface and enabled._label.TextColor3 == textColor
	and sameColor(window:GetAppearance().Accent, accent) and window:GetAppearance().CornerRadius == 4)
check("existing window, section, and field corners follow personalization", window.Frame:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 4
	and state._body:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 3 and field:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 2)
appearanceTab:Select()
local palette = builtin("accent"):Open()
check("new picker corners inherit the preference", palette.Frame:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 4)
palette:Close()
first:Select()
check("appearance changes retain application controls and unsaved drafts", window.Frame == frame and draft:Get() == "saved" and field.Text == "unfinished"
	and first.Frame.CanvasPosition == scroll and callbacks == 0)
check("programmatic appearance reflection is silent", builtin("theme"):Get() == "Light" and builtin("corner_radius"):Get() == 4
	and builtin("text_scale"):Get() == 135 and not builtin("reduced_motion"):Get() and reflected == 0)
unsubscribe()
local copy = window:GetAppearance()
copy.Colors.Text = surface
check("returned appearance maps cannot alter the window", window:GetAppearance().Colors.Text == textColor)
local supplied = { Text = textColor }
window:SetAppearance({ Colors = supplied }); supplied.Text = surface
check("supplied override maps are copied and replace earlier overrides", window:GetAppearance().Colors.Text == textColor and window:GetAppearance().Colors.Surface == nil)
window:SetTheme("Dark")
check("legacy SetTheme preserves custom colors and reflects the built-in mode", window.Theme.Text == textColor and window:GetAppearance().Accent == nil and builtin("theme"):Get() == "Dark")
window:SetTextScale(1.1); window:SetReducedMotion(true)
check("existing text and motion setters reflect without extra callbacks", builtin("text_scale"):Get() == 110 and builtin("reduced_motion"):Get() and callbacks == 0)
appearanceTab:Select()
builtin("corner_radius"):Set(8)
builtin("text_scale"):Set(125)
builtin("reduced_motion"):Set(false)
builtin("theme"):Set("Light")
builtin("accent"):Set(accent)
builtin("color_Surface"):Set(surface)
builtin("color_Text"):Set(textColor)
check("built-in controls apply appearance without domain callbacks", window:GetAppearance().CornerRadius == 8 and window.TextScale == 1.25
	and not window.ReducedMotion and window:GetTheme() == "Light" and window.Theme.Surface == surface and window.Theme.Text == textColor and callbacks == 0)
check("color edits preserve independent overrides", sameColor(window:GetAppearance().Accent, accent) and window:GetAppearance().Colors.Surface == surface and window:GetAppearance().Colors.Text == textColor)
check("palette reset is available as a normal owned action", builtin("reset_colors"):Press())
h.settle(0.3)
check("palette reset clears overrides while retaining shape and comfort", next(window:GetAppearance().Colors) == nil and window:GetAppearance().Accent == nil
	and window:GetAppearance().Theme == "Light" and window:GetAppearance().CornerRadius == 8 and window.TextScale == 1.25)
check("complete appearance reset is available", builtin("reset"):Press())
h.settle(0.3)
local restored = window:GetAppearance()
check("reset restores the window's declared starting appearance", restored.Theme == "Dark" and sameColor(restored.Accent, accent)
	and restored.Colors.Surface == surface and restored.CornerRadius == 6 and restored.TextScale == 1.2 and restored.ReducedMotion)

local invalid = {
	{ Theme = "Other" }, { Accent = "blue" }, { Accent = dt.Color3.new(0 / 0, 0, 0) },
	{ Colors = false }, { Colors = { Imaginary = surface } }, { Colors = { Surface = "blue" } },
	{ CornerRadius = -1 }, { CornerRadius = 17 }, { TextScale = 0.5 }, { TextScale = 2 }, { ReducedMotion = "yes" },
}
for index, patch in ipairs(invalid) do
	patch.Theme = patch.Theme or "Light"
	local before = window:ExportConfig()
	check("invalid appearance patch " .. index .. " is atomic", not pcall(function() window:SetAppearance(patch) end) and window:ExportConfig() == before)
end
local retained = defaultWindow
for _, options in ipairs({ { Colors = false }, { CornerRadius = false }, { Colors = { Surface = "invalid" } }, { CornerRadius = 100 } }) do
	options.Id = defaultWindow.Id
	check("invalid new appearance does not replace an existing window", not pcall(function() UI:CreateWindow(options) end) and retained.Alive and UI:GetWindow(retained.Id) == retained)
end

window:SetAppearance({ Theme = "Light", Accent = false, Colors = { Surface = surface, Text = textColor, Selected = surface }, CornerRadius = 3, TextScale = 1.4, ReducedMotion = false })
enabled:Set(true, true)
local exported = window:ExportConfig()
local document = h.json.decode(exported)
check("version-1 profiles store full appearance once", document.version == 1 and count(document.values) == 1 and document.values.enabled.value
	and document.appearance.theme == "Light" and document.appearance.accent == nil and document.appearance.cornerRadius == 3
	and document.appearance.textScale == 1.4 and document.appearance.reducedMotion == false and #document.appearance.colors.Surface == 3)
window:ResetAppearance(); enabled:Set(false, true)
local observed
local stop = enabled:OnChanged(function() observed = window:GetAppearance() end)
local ok, imported = window:ImportConfig(exported, { Silent = false }); stop()
check("appearance restores before opt-in domain callbacks", ok and imported == 1 and observed and observed.Theme == "Light" and observed.CornerRadius == 3
	and observed.TextScale == 1.4 and observed.ReducedMotion == false and observed.Accent == nil and sameColor(observed.Colors.Text, textColor))
check("configuration restoration reflects the automatic panel", builtin("theme"):Get() == "Light" and builtin("corner_radius"):Get() == 3
	and builtin("text_scale"):Get() == 140 and not builtin("reduced_motion"):Get() and sameColor(builtin("color_Surface"):Get(), surface))
local saved, path = window:SaveConfig("personal")
window:ResetAppearance()
check("file profiles use full appearance without extra settings files", saved and h.files[path] and window:LoadConfig("personal") and window:GetAppearance().CornerRadius == 3 and window.TextScale == 1.4)

local malformed = {
	{ theme = "Dark", colors = false }, { theme = "Dark", colors = { Imaginary = { 0, 0, 0 } } },
	{ theme = "Dark", colors = { Text = { 1, 0, 0, 0 } } }, { theme = "Dark", colors = { Text = { 2, 0, 0 } } },
	{ theme = "Dark", colors = { Text = { [1] = 0, [2] = 0, [3] = 0, extra = 0 } } },
	{ theme = "Dark", accent = { 0, 0 } }, { theme = "Dark", cornerRadius = "4" }, { theme = "Dark", cornerRadius = 100 },
	{ theme = "Dark", textScale = 2 }, { theme = "Dark", reducedMotion = 1 },
}
for index, value in ipairs(malformed) do
	local before = window:ExportConfig()
	document = h.json.decode(exported)
	document.appearance, document.values.enabled.value = value, false
	check("invalid saved appearance " .. index .. " prevents all writes", not window:ImportConfig(h.json.encode(document), { Silent = false }) and window:ExportConfig() == before)
end
document = h.json.decode(exported); document.appearance.theme = "Dark"; document.values.enabled.value = "invalid"
check("invalid domain values prevent appearance changes", not window:ImportConfig(h.json.encode(document)) and window:GetTheme() == "Light")
document = h.json.decode(exported); document.appearance = nil
document.values.__uai_appearance_corner_radius = { kind = "Slider", value = 15 }
check("legacy imports ignore built-in values and retain current appearance", window:ImportConfig(h.json.encode(document)) and window:GetAppearance().CornerRadius == 3 and window:GetTheme() == "Light")
document.appearance = { theme = "Dark" }
window:SetAppearance({ Accent = accent })
check("older appearance records preserve newer settings and clear omitted accent", window:ImportConfig(h.json.encode(document)) and window:GetTheme() == "Dark"
	and window:GetAppearance().CornerRadius == 3 and window.TextScale == 1.4 and not window.ReducedMotion and window:GetAppearance().Accent == nil
	and sameColor(window:GetAppearance().Colors.Text, textColor))
local inheritedMotion = defaultWindow._motionOverride
local legacyDefault = { format = "project-uai-ui", version = 1, window = defaultWindow.Id, values = {}, appearance = { theme = "Light" } }
check("legacy theme import preserves platform motion following", defaultWindow:ImportConfig(h.json.encode(legacyDefault)) and defaultWindow._motionOverride == inheritedMotion)
local gui = h.services.GuiService
gui.ReducedMotionEnabled = true; gui:GetPropertyChangedSignal("ReducedMotionEnabled"):Fire()
check("platform motion changes still reach a window restored from a legacy profile", defaultWindow.ReducedMotion and window.ReducedMotion == false)
check("platform motion preference stays reflected in automatic settings", defaultWindow:Get("__uai_appearance_reduced_motion"):Get())
gui.ReducedMotionEnabled = false; gui:GetPropertyChangedSignal("ReducedMotionEnabled"):Fire()
check("platform motion can return to normal after a legacy import", not defaultWindow.ReducedMotion)
defaultWindow.Tabs[1]:Destroy()
local remaining = defaultWindow:Tab("After settings")
check("destroyed settings do not reappear when adding tabs", #defaultWindow.Tabs == 1 and defaultWindow.Tabs[1] == remaining and remaining.Alive)
check("internal Ids remain reserved after settings are destroyed", not pcall(function() defaultWindow:Tab({ Id = "__uai_appearance_tab" }) end)
	and not pcall(function() remaining:Section("Reserved"):Toggle({ Id = "__uai_appearance_custom" }) end))
local beforeReset = window:GetAppearance()
local values = window:GetValues()
local containsAppearance = false
for id in pairs(values) do if id:sub(1, 17) == "__uai_appearance_" then containsAppearance = true end end
check("application snapshots omit automatic appearance controls", not containsAppearance and values.enabled ~= nil)
check("resetting application values retains appearance preferences", window:ResetValues() and window:GetAppearance().CornerRadius == beforeReset.CornerRadius and window:GetTheme() == beforeReset.Theme)
window:Destroy(); defaultWindow:Destroy(); h.settle(0.3)
check("built-in personalization releases ownership and causes no host errors", window._appearanceTab == nil and window._appearanceSync == nil
	and next(window._paint) == nil and #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print("UI library appearance: " .. passed .. " checks passed")
