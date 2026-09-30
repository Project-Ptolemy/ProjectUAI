-- Touch intent, short keyboards, and rotation against the public library.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local h = envMock.new()
local uis = h.services.UserInputService
uis.TouchEnabled, uis.MouseEnabled = true, false
h.setViewport(390, 844)
local ui = assert(h.boot("dist/uai-ui.lua"))
local window = ui:CreateWindow({ Id = "mobile-regression", Title = "Mobile controls" })
local tab = window:Tab({ Title = "Main" })
local section = tab:Section({ Title = "Long section heading that wraps on a narrow phone", Collapsible = true })
local changes, commits = 0, 0
local slider = section:Slider({ Id = "slider", Text = "Value", Min = 0, Max = 100, Default = 50,
	Callback = function() changes = changes + 1 end, OnCommit = function() commits = commits + 1 end })
local E, V = h.sandbox.Enum, h.dt.Vector3
local hit = h.byName("Slider", slider.Frame)
local track = h.byName("Track", slider.Frame)
local function touch(fraction)
	return { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin,
		Position = V.new(track.AbsolutePosition.X + track.AbsoluteSize.X * fraction, track.AbsolutePosition.Y, 0) }
end
local finger = touch(0.2)
hit.InputBegan:Fire(finger)
finger.Position = finger.Position + V.new(2, 35, 0)
uis.InputChanged:Fire(finger); uis.InputEnded:Fire(finger)
check("vertical scrolling never changes or commits a slider", slider:Get() == 50 and changes == 0 and commits == 0 and tab.Frame.ScrollingEnabled)
finger = touch(0.2); hit.InputBegan:Fire(finger); uis.InputEnded:Fire(finger)
check("a deliberate tap changes the value and commits once", slider:Get() == 20 and commits == 1)
finger = touch(0.2); hit.InputBegan:Fire(finger)
finger.Position = touch(0.8).Position; uis.InputChanged:Fire(finger)
check("horizontal dragging owns the scroll gesture", slider:Get() == 80 and not tab.Frame.ScrollingEnabled)
window:Hide()
check("hiding releases scroll ownership without a commit", tab.Frame.ScrollingEnabled and window._gesture == nil and commits == 1)
window:Show()
finger = touch(0.3); hit.InputBegan:Fire(finger)
finger.UserInputState = E.UserInputState.Cancel; uis.InputEnded:Fire(finger)
check("cancelled touches never become taps", slider:Get() == 80 and commits == 1)
finger = touch(0.3); hit.InputBegan:Fire(finger)
finger.Position = touch(0.6).Position; uis.InputChanged:Fire(finger)
h.setViewport(844, 390); window:_Layout()
check("rotation releases a drag and native scrolling", tab.Frame.ScrollingEnabled and window._gesture == nil and commits == 1)
h.setViewport(320, 568); window:_Layout()
check("mobile headings wrap within their measured header", section._heading.Size.Y.Offset > 22 and section._header.Size.Y.Offset >= section._heading.Size.Y.Offset)
local choices = {}
for index = 1, 24 do choices[index] = "A readable option " .. index end
local dropdown = section:Dropdown({ Id = "choice", Text = "Choose", Options = choices, Multi = true })
local panel = dropdown:Open()
local search = h.byName("SearchOptions", panel.Root)
check("mobile dropdown search stays outside the scrolling results", search.Parent == panel.Frame and panel.Body.Size.Y.Offset >= 44)
window:SetTextScale(1.5)
check("open picker fields and actions follow larger targets", search.Size.Y.Offset >= 54 and h.byName("Done", panel.Root).Size.Y.Offset >= 54)
panel:Close(); window:SetTextScale(1)
panel = window:Dialog({ Title = "Choose an action", Content = "All four actions remain reachable.", Buttons = {
	{ Text = "Keep editing" }, { Text = "Save changes" }, { Text = "Use defaults" }, { Text = "Apply", Style = "Primary" },
} })
local first, third = h.byName("DialogAction_1", panel.Root), h.byName("DialogAction_3", panel.Root)
check("phone dialog actions wrap into reachable rows", third.Position.Y.Offset > first.Position.Y.Offset and first.Size.Y.Offset >= 44)
h.setViewport(844, 390)
uis.OnScreenKeyboardVisible, uis.OnScreenKeyboardSize, uis.OnScreenKeyboardPosition = true, h.dt.Vector2.new(844, 230), h.dt.Vector2.new(0, 160)
window:_Layout()
check("short keyboard dialogs keep full action targets in their scroll body", panel.InlineActions and panel.Actions.Parent == panel.Body and first.Size.Y.Offset >= 44 and panel.Body.Size.Y.Offset >= 44)
check("library overlays clear the reported keyboard edge", panel.Frame.AbsolutePosition.Y + panel.Frame.AbsoluteSize.Y <= 160)
panel:Close()
panel = dropdown:Open()
search = h.byName("SearchOptions", panel.Root)
check("very short pickers return search to the scroll body", search.Parent == panel.Body and panel.Body.Size.Y.Offset >= 44)
uis.OnScreenKeyboardVisible = false; h.setViewport(390, 844); window:_Layout()
check("restoring space pins the same search field again", h.byName("SearchOptions", panel.Root) == search and search.Parent == panel.Frame)
panel:Close()
local color = section:ColorPicker({ Id = "color", Text = "Color" })
panel = color:Open(); window:SetTextScale(1.5)
check("color picker fields reflow while open", h.byName("Hex", panel.Root).Size.Y.Offset >= 54 and h.byName("Apply", panel.Root).Size.Y.Offset >= 54)
panel:Close(); window:Destroy(); h.settle(0.2)
check("mobile library changes leave no invalid properties or callback errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print("UI library mobile: " .. passed .. " checks passed")
