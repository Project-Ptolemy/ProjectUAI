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
local defaultWidth, defaultHeight = window:GetSize()
local viewport = window._viewport.AbsoluteSize
check("automatic phone dimensions leave game space around the window", defaultWidth <= viewport.X * 0.9 and defaultHeight <= viewport.Y * 0.76)
local resize = h.byName("Resize", window.Frame)
check("mobile resizing has a visible full touch target", resize.Visible and resize.Size.X.Offset >= 44 and resize.Size.Y.Offset >= 44)
local resizeTile, resizeGlyph = h.byName("ResizeTile", resize), h.byName("ResizeGlyph", resize)
check("the touch resize affordance is visible beside the attribution", resizeTile.Visible and resizeTile.Size.X.Offset == 26 and resizeGlyph.Size.X.Offset == 16
	and resizeTile.AbsolutePosition.X > window.Frame.AbsolutePosition.X + window.Frame.AbsoluteSize.X / 2)
check("mobile headers and navigation retain full touch targets", window._minimize.Size.Y.Offset >= 44 and window._close.Size.Y.Offset >= 44 and tab._button.Size.Y.Offset >= 44)
local extraTabs = {}
for index = 1, 4 do extraTabs[index] = window:Tab({ Id = "extra-" .. index, Title = "Extra tab " .. index }) end
local function tabExtent(target)
	local offset, count = window._navPad.PaddingLeft.Offset, 0
	for _, candidate in ipairs(window.Tabs) do
		if candidate.Alive and candidate.Visible then
			if count > 0 then offset = offset + window._navLayout.Padding.Offset end
			local finish = offset + candidate._button.Size.X.Offset
			if candidate == target then return offset, finish end
			offset, count = finish, count + 1
		end
	end
end
window:SelectTab("__uai_appearance_tab")
local appearanceLeft, appearanceRight = tabExtent(window._appearanceTab)
check("selecting automatic Appearance reveals its horizontal tab", window._nav.CanvasPosition.X > 0
	and appearanceLeft >= window._nav.CanvasPosition.X and appearanceRight <= window._nav.CanvasPosition.X + window._nav.AbsoluteSize.X)
local navScroll = window._nav.CanvasPosition.X
window:SelectTab("__uai_appearance_tab"); window:_Layout()
check("visible selected tabs retain the current navigation scroll", window._nav.CanvasPosition.X == navScroll)
window:SetSize(280, 500)
appearanceLeft, appearanceRight = tabExtent(window._appearanceTab)
check("narrow reflow keeps the active tab fully visible", appearanceLeft >= window._nav.CanvasPosition.X
	and appearanceRight <= window._nav.CanvasPosition.X + window._nav.AbsoluteSize.X)
window:SetTextScale(1.5)
appearanceLeft, appearanceRight = tabExtent(window._appearanceTab)
check("larger text reveals the resized active navigation target", appearanceLeft >= window._nav.CanvasPosition.X
	and appearanceRight <= window._nav.CanvasPosition.X + window._nav.AbsoluteSize.X and window._appearanceTab._button.Size.Y.Offset >= 54)
window:SetTextScale(1); window:ResetSize()
window:SelectTab(tab)
check("selecting the first tab returns it into view", window._nav.CanvasPosition.X == 0)
for _, extra in ipairs(extraTabs) do extra:Destroy() end
window:_Layout()
local resizeOrigin = V.new(resize.AbsolutePosition.X + resize.AbsoluteSize.X / 2, resize.AbsolutePosition.Y + resize.AbsoluteSize.Y / 2, 0)
local resizeFinger = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin, Position = resizeOrigin }
resize.InputBegan:Fire(resizeFinger)
local resizeGesture = window._gesture
resizeFinger.Position = resizeOrigin + V.new(-14, -40, 0); uis.InputChanged:Fire(resizeFinger)
local firstWidth, firstHeight = window:GetSize()
resizeFinger.Position = resizeOrigin + V.new(-28, -80, 0); uis.InputChanged:Fire(resizeFinger)
local chosenWidth, chosenHeight = window:GetSize()
check("one touch continuously resizes through its own reflow", resizeGesture ~= nil and window._gesture == resizeGesture
	and chosenWidth < firstWidth and firstWidth < defaultWidth and chosenHeight < firstHeight and firstHeight < defaultHeight)
local otherFinger = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin, Position = resizeOrigin + V.new(100, 100, 0) }
uis.InputChanged:Fire(otherFinger); uis.InputEnded:Fire(otherFinger)
check("an unrelated finger cannot resize or release the window", window._gesture == resizeGesture and window:GetSize() == chosenWidth)
uis.InputEnded:Fire(resizeFinger)
check("releasing a resize touch releases its gesture", window._gesture == nil)
window:SetTextScale(1.1); window:SetTextScale(1)
check("text reflow preserves a chosen mobile size", window:GetSize() == chosenWidth and select(2, window:GetSize()) == chosenHeight)
h.setViewport(844, 390); window:_Layout()
check("rotation clamps the chosen size without replacing it", select(2, window:GetSize()) < chosenHeight and window._requestedHeight == chosenHeight)
h.setViewport(390, 844); window:_Layout()
check("portrait restores the same chosen width and height", window:GetSize() == chosenWidth and select(2, window:GetSize()) == chosenHeight)
uis.OnScreenKeyboardSize, uis.OnScreenKeyboardPosition = h.dt.Vector2.new(390, 624), h.dt.Vector2.new(0, 220)
uis.OnScreenKeyboardVisible = true; window:_Layout()
check("the keyboard temporarily fits the window above its edge", window.Frame.AbsolutePosition.Y + window.Frame.AbsoluteSize.Y <= 220 and window._requestedHeight == chosenHeight)
uis.OnScreenKeyboardVisible = false; window:_Layout()
check("dismissing the keyboard restores the chosen size", window:GetSize() == chosenWidth and select(2, window:GetSize()) == chosenHeight)
window:SetSize(310, 420)
check("scripts can set a preferred mobile size", window:GetSize() == 310 and select(2, window:GetSize()) == 420)
window:SetSize(1, 1)
check("programmatic sizes keep usable minimum dimensions", window:GetSize() == 280 and select(2, window:GetSize()) == 240)
local beforeInvalidWidth, beforeInvalidHeight = window:GetSize()
check("invalid size inputs fail before changing the window", not pcall(function() window:SetSize(0 / 0, 400) end)
	and not pcall(function() window:SetSize(300, math.huge) end) and window:GetSize() == beforeInvalidWidth and select(2, window:GetSize()) == beforeInvalidHeight)
window:ResetSize()
check("reset restores automatic phone dimensions and centered placement", window:GetSize() == defaultWidth and select(2, window:GetSize()) == defaultHeight and window._position == nil)
resizeOrigin = V.new(resize.AbsolutePosition.X + resize.AbsoluteSize.X / 2, resize.AbsolutePosition.Y + resize.AbsoluteSize.Y / 2, 0)
resizeFinger = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin, Position = resizeOrigin }
resize.InputBegan:Fire(resizeFinger)
h.setViewport(844, 390); window:_Layout()
check("rotation cancels an active window resize", window._gesture == nil)
h.setViewport(390, 844); window:_Layout()
resizeOrigin = V.new(resize.AbsolutePosition.X + resize.AbsoluteSize.X / 2, resize.AbsolutePosition.Y + resize.AbsoluteSize.Y / 2, 0)
resizeFinger = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin, Position = resizeOrigin }
resize.InputBegan:Fire(resizeFinger)
window:Hide()
check("hiding cancels an active window resize", window._gesture == nil)
window:Show()
local explicit = ui:CreateWindow({ Id = "mobile-explicit-size", Width = 330, Height = 610 })
check("explicit constructor dimensions stay author preferences on touch", explicit:GetSize() == 330 and select(2, explicit:GetSize()) == 610)
explicit:SetSize(300, 400); explicit:ResetSize()
check("reset restores explicit constructor dimensions", explicit:GetSize() == 330 and select(2, explicit:GetSize()) == 610)
explicit:Destroy()
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
panel:Close()
local revealTab = window:Tab({ Id = "reveal-mobile", Title = "A dynamically named destination" })
local revealSection = revealTab:Section({ Title = "Hidden inputs", Collapsible = true, Collapsed = true })
local revealInput = revealSection:Input({ Id = "reveal-input", Text = "Destination", Required = true,
	RequiredMessage = "Enter a destination name before applying the changes to this workspace." })
revealTab:SetTitle("A longer destination title that needs room on a phone")
revealTab:SetVisible(false); window:Minimize()
window:Reveal("reveal-input"); h.settle(0.1)
check("mobile reveal restores a hidden tab within the safe viewport", window.Visible and revealInput.Frame.Visible and not revealSection.Collapsed
	and window:GetActiveTab() == revealTab and revealTab._button.Size.X.Offset <= window.Frame.Size.X.Offset)
revealInput:Validate()
check("mobile validation messages wrap without clipping", h.byName("Validation", revealInput.Frame).Size.Y.Offset > 22)
panel:Close(); window:Destroy(); h.settle(0.2)
uis.TouchEnabled, uis.MouseEnabled = false, true; h.setViewport(1280, 720)
local desktop = ui:CreateWindow({ Id = "desktop-resize-regression" })
local desktopWidth, desktopHeight = desktop:GetSize()
local desktopResize = h.byName("Resize", desktop.Frame)
check("desktop keeps its preferred dimensions and compact corner target", desktopWidth == 780 and desktopHeight == 580 and desktopResize.Size.X.Offset == 24)
local mouseOrigin = V.new(desktopResize.AbsolutePosition.X + 12, desktopResize.AbsolutePosition.Y + 12, 0)
local mouseDown = { UserInputType = E.UserInputType.MouseButton1, UserInputState = E.UserInputState.Begin, Position = mouseOrigin }
desktopResize.InputBegan:Fire(mouseDown)
uis.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement, Position = mouseOrigin + V.new(-60, -70, 0) })
uis.InputEnded:Fire(mouseDown)
check("desktop mouse resizing remains continuous and releases cleanly", desktop:GetSize() == desktopWidth - 60 and select(2, desktop:GetSize()) == desktopHeight - 70 and desktop._gesture == nil)
desktop:Destroy(); h.settle(0.2)
check("mobile library changes leave no invalid properties or callback errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print("UI library mobile: " .. passed .. " checks passed")
