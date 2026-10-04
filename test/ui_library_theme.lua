-- Theme behavior against the published bundle, including existing live bindings.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local function count(map) local n = 0; for _ in pairs(map) do n = n + 1 end; return n end
local function sameColor(a, b) return math.abs(a.R - b.R) < 1e-12 and math.abs(a.G - b.G) < 1e-12 and math.abs(a.B - b.B) < 1e-12 end
local h = envMock.new()
local UI = assert(h.boot("dist/uai-ui.lua"))
local dt, uis = h.dt, h.services.UserInputService
local accent = dt.Color3.fromRGB(180, 90, 200)
local window = UI:CreateWindow({ Id = "theme-regression", Title = "Theme coverage", Accent = accent })
local other = UI:CreateWindow({ Id = "theme-independent", Theme = "Light", ThemeToggle = false })
local tab = window:Tab("Main")
local section = tab:Section("State")
local changes = 0
local toggle = section:Toggle({ Id = "toggle", Text = "Enabled", Default = false, Callback = function() changes = changes + 1 end })
local slider = section:Slider({ Id = "slider", Text = "Amount", Default = 35, Min = 0, Max = 100 })
local text = section:Input({ Id = "text", Text = "Draft", Default = "saved" })
local dropdown = section:Dropdown({ Id = "choice", Text = "Choice", Options = { "A", "B" }, Default = "A" })
local color = section:ColorPicker({ Id = "color", Text = "Color", Default = accent })
local action = section:Button({ Text = "Apply", Style = "Primary" })
local function node(name, parent) return assert(h.byName(name, parent or window.ScreenGui), "missing " .. name) end
local field = node("Input", text.Frame)
h.settle(0.3)
field.Text = "unfinished draft"
tab.Frame.CanvasPosition = dt.Vector2.new(0, 25)
local scroll = tab.Frame.CanvasPosition
local roots = { window.Frame, tab.Frame, toggle.Frame }
local mode = node("ThemeToggle")
check("mode action is built in and can be omitted", node("ThemeLabel").Text == "Light mode" and h.byName("ThemeToggle", other.ScreenGui) == nil)
toggle:Set(true, true)
local thumb = node("Thumb", toggle.Frame)
local oldMotion = window._motions[thumb]
mode.SelectionGained:Fire()
mode.Activated:Fire()
local name, chosenAccent = window:GetTheme()
check("mode action changes only its window and preserves custom accent", name == "Light" and chosenAccent == accent and other:GetTheme() == "Light" and node("ThemeLabel").Text == "Dark mode")
check("switching mode preserves mounted controls, draft, values, and scroll", roots[1] == window.Frame and roots[2] == tab.Frame and roots[3] == toggle.Frame
	and toggle:Get() and slider:Get() == 35 and text:Get() == "saved" and field.Text == "unfinished draft" and tab.Frame.CanvasPosition == scroll and changes == 0)
check("switching settles in-flight motion without a stale color overwrite", oldMotion and oldMotion.tween.PlaybackState == "Cancelled" and thumb.Position.X.Offset == 24 and next(window._motions) == nil)
h.settle(0.3)
check("existing chrome, text, fields, and selected controls use Light tokens", window.Frame.BackgroundColor3 == window.Theme.Chrome
	and window._workspace.BackgroundColor3 == window.Theme.Canvas and window._rail.BackgroundColor3 == window.Theme.Sidebar
	and text._label.TextColor3 == window.Theme.Text and field.BackgroundColor3 == window.Theme.Input and field.TextColor3 == window.Theme.Text
	and tab._button.BackgroundColor3 == window.Theme.Selected and node("Track", toggle.Frame).BackgroundColor3 == accent
	and thumb.BackgroundColor3 == window.Theme.OnAccent and node("Action", action.Frame).BackgroundColor3 == window.Theme.Primary)
check("gamepad focus survives a mode change", mode:FindFirstChildOfClass("UIStroke").Thickness == 2 and mode:FindFirstChildOfClass("UIStroke").Color == accent)
mode.SelectionLost:Fire()
slider:SetDisabled(true)
window:ToggleTheme()
check("disabled states inherit Dark without becoming enabled", slider.Disabled and slider._label.TextColor3 == window.Theme.Muted and node("Fill", slider.Frame).BackgroundColor3 == window.Theme.Muted)
window:SetTheme("Light")
local fresh = section:Input({ Text = "New field" })
check("new components inherit the current palette", node("Input", fresh.Frame).BackgroundColor3 == window.Theme.Input and fresh._label.TextColor3 == window.Theme.Text)

local picker = dropdown:Open()
local search = node("SearchOptions", picker.Root)
search.Text = "A"
window:ToggleTheme()
check("open dropdowns repaint while preserving search and selection", not picker.Closed and search.Text == "A" and dropdown:Get() == "A"
	and picker.Frame.BackgroundColor3 == window.Theme.Surface and search.TextColor3 == window.Theme.Text
	and node("Option_1", picker.Root).BackgroundColor3 == window.Theme.Selected)
picker:Close()
picker = color:Open()
local hex = node("Hex", picker.Root)
hex.Text = "#00FF00"; hex.FocusLost:Fire()
window:ToggleTheme()
check("color picker drafts survive theme changes and chrome repaints", not picker.Closed and hex.Text == "#00FF00" and color:Get() == accent
	and picker.Frame.BackgroundColor3 == window.Theme.Surface and hex.BackgroundColor3 == window.Theme.Input)
picker:Close()
local dialog = window:Dialog({ Title = "Theme dialog", Content = "Keep this open", Buttons = { { Text = "Done", Style = "Primary" } } })
local toast = window:Notify({ Title = "Theme notice", Content = "Still visible", Duration = 0 })
window:ToggleTheme()
check("open dialogs and notifications share the active palette", not dialog.Closed and dialog.Frame.BackgroundColor3 == window.Theme.Surface
	and node("DialogAction_1", dialog.Root).BackgroundColor3 == window.Theme.Primary and toast.Frame.BackgroundColor3 == window.Theme.Surface)
dialog:Close(); toast:Close()
window:Minimize(); window:ToggleTheme()
check("minimized launcher repaints and remains minimized", not window.Visible and window._launcher.Visible and window._launcher.BackgroundColor3 == window.Theme.Canvas
	and node("RestoreTitle").TextColor3 == window.Theme.Text and node("Attribution", window._launcher).Text == "Project UAI | UI LIB.")
window:Show()

local function luminance(value)
	local function channel(c) return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
	return channel(value.R) * 0.2126 + channel(value.G) * 0.7152 + channel(value.B) * 0.0722
end
local function contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
for _, theme in ipairs({ "Dark", "Light" }) do
	window:SetTheme(theme)
	check(theme .. " text and action pairs remain readable", contrast(window.Theme.Text, window.Theme.Surface) >= 7
		and contrast(window.Theme.Muted, window.Theme.Input) >= 4.5 and contrast(window.Theme.OnPrimary, window.Theme.Primary) >= 7
		and contrast(window.Theme.OnAccent, window.Theme.Accent) >= 4.5)
	for _, custom in ipairs({ accent, dt.Color3.fromRGB(120, 120, 120), dt.Color3.fromRGB(30, 150, 100), dt.Color3.fromRGB(40, 70, 220) }) do
		window:SetTheme(theme, custom)
		check(theme .. " custom accent foreground has at least 4.5 contrast", contrast(window.Theme.OnAccent, custom) >= 4.5)
	end
end
local previousTheme = window.Theme
check("invalid accents fail before changing a live palette", not pcall(function() window:SetTheme("Light", dt.Color3.new(0 / 0, 0, 0)) end) and window.Theme == previousTheme)
check("invalid mode options do not replace a live window", not pcall(function() UI:CreateWindow({ Id = window.Id, ThemeToggle = "yes" }) end) and window.Alive)

window:SetTheme("Light", accent)
local exported = window:ExportConfig()
local document = h.json.decode(exported)
check("appearance shares the existing versioned config", document.version == 1 and document.appearance.theme == "Light" and math.abs(document.appearance.accent[1] - accent.R) < 1e-12)
window:SetTheme("Dark"); toggle:Set(false, true)
local callbackTheme
local stop = toggle:OnChanged(function() callbackTheme = window:GetTheme() end)
local ok = window:ImportConfig(exported, { Silent = false }); stop()
local restoredName, restoredAccent = window:GetTheme()
check("config restores theme and accent before opt-in callbacks", ok and restoredName == "Light" and sameColor(restoredAccent, accent) and callbackTheme == "Light" and toggle:Get())
document.appearance = nil
window:SetTheme("Dark")
check("legacy version-1 configs preserve current appearance", window:ImportConfig(h.json.encode(document)) and window:GetTheme() == "Dark")
document.appearance = { theme = "Light", accent = { 2, 0, 0 } }; document.values.toggle.value = false
check("invalid appearance prevents partial control import", not window:ImportConfig(h.json.encode(document)) and toggle:Get() and window:GetTheme() == "Dark")
document.appearance = { theme = "Light" }; document.values.toggle.value = "invalid"
check("invalid controls prevent partial appearance import", not window:ImportConfig(h.json.encode(document)) and window:GetTheme() == "Dark")
window:SetTheme("Light", accent)
local saved, path = window:SaveConfig("theme")
window:SetTheme("Dark")
check("explicit profiles persist appearance without another settings file", saved and h.files[path] and window:LoadConfig("theme") and window:GetTheme() == "Light")

for _, viewport in ipairs({ { 1280, 720, false }, { 390, 844, true }, { 844, 390, true }, { 320, 568, true } }) do
	uis.TouchEnabled = viewport[3]
	h.setViewport(viewport[1], viewport[2])
	for _, scale in ipairs({ 1, 1.5 }) do
		window:SetTextScale(scale)
		local right = mode.AbsolutePosition.X + mode.AbsoluteSize.X
		local bottom = mode.AbsolutePosition.Y + mode.AbsoluteSize.Y
		check("mode action fits navigation at " .. viewport[1] .. " and scale " .. scale, mode.Visible and mode.AbsoluteSize.Y >= window.Target
			and right <= window.Frame.AbsolutePosition.X + window.Frame.AbsoluteSize.X and bottom <= window.Frame.AbsolutePosition.Y + window.Frame.AbsoluteSize.Y - 30)
		if window._compact then
			check("compact tabs retain space beside the mode action", window._nav.AbsoluteSize.X >= 100 and window._nav.AbsolutePosition.X + window._nav.AbsoluteSize.X <= mode.AbsolutePosition.X)
		else
			check("desktop mode action clears profile and scrolling tabs", bottom <= node("Profile").AbsolutePosition.Y
				and window._nav.AbsolutePosition.Y + window._nav.AbsoluteSize.Y <= mode.AbsolutePosition.Y)
		end
	end
end
h.setViewport(844, 390)
uis.OnScreenKeyboardVisible, uis.OnScreenKeyboardSize, uis.OnScreenKeyboardPosition = true, dt.Vector2.new(844, 230), dt.Vector2.new(0, 160)
window:_Layout()
check("very short keyboard layouts hide mode with compact navigation", not mode.Visible and not window._nav.Visible)
uis.OnScreenKeyboardVisible = false
h.setViewport(390, 844); window:_Layout()
check("mode action returns after keyboard layout recovers", mode.Visible)
local bindings = count(window._paint)
for _ = 1, 30 do mode.Activated:Fire() end
check("repeated mode switching does not add paint or motion subscriptions", count(window._paint) == bindings and next(window._motions) == nil)
window:Destroy(); other:Destroy(); h.settle(0.3)
check("theme resources clean up without invalid properties or tasks", next(window._paint) == nil and #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print("UI library themes: " .. passed .. " checks passed")
