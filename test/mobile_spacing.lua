-- Mobile spacing, compact drafts and touch gestures against the shipped client.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local envMock = require("env")
local newSignal = require("instance").newSignal
local passed, failed = 0, 0
local function check(label, value) assert(value, label); passed = passed + 1 end
local function scenario(label, run)
	local ok, why = pcall(run)
	if ok then print("ok " .. label) else failed = failed + 1; print("FAIL " .. label .. ": " .. tostring(why)) end
end
local function boot(width, height, desktop)
	local h = envMock.new()
	h.services.UserInputService.TouchEnabled = not desktop
	h.services.UserInputService.MouseEnabled = desktop == true
	h.setViewport(width, height)
	local app = assert(h.boot(arg[1] or "dist/uai.lua")); h.settle(1); app.app.show("chat")
	return h, app
end
local function keyboard(h, height)
	local uis = h.services.UserInputService
	uis.OnScreenKeyboardSize = h.dt.Vector2.new(h.instanceState.viewport.X, height)
	uis.OnScreenKeyboardVisible = height > 0
	uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
	h.settle(0.3)
end
local function healthy(h)
	check("no asynchronous errors", #h.errors() == 0)
	check("valid property assignments", #h.instanceState.typeErrors == 0)
	for _, warning in ipairs(h.console.warnings) do
		check("no failed UI callbacks", not warning:find("handler failed", 1, true) and not warning:find("pane failed", 1, true))
	end
end

for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 390 }, { 834, 1194 } }) do
	scenario("ordinary drafts keep their reading space at " .. size[1] .. "x" .. size[2], function()
		local h, app = boot(size[1], size[2])
		local composer = app.app.chatPanel.composer
		local field = composer.field.instance
		composer.field.set("A short draft\nWith a second line")
		field.Focused:Fire()
		check("focus and newlines keep the compact composer", composer.shell.Size.Y.Offset <= 56)
		field.CursorPosition, field.SelectionStart = 10, 4
		composer.setExpanded(true, false)
		check("expansion increases editable space", composer.shell.Size.Y.Offset > 56)
		check("expansion keeps the native input and selection", composer.field.instance == field
			and field.CursorPosition == 10 and field.SelectionStart == 4)
		composer.setExpanded(false, false)
		check("compact input restores without editing the draft", composer.shell.Size.Y.Offset <= 56
			and composer.field.get() == "A short draft\nWith a second line" and field.MultiLine)
		for _, name in ipairs({ "Send", "ComposerOptions" }) do
			local button = h.byName(name, composer.shell)
			check(name .. " retains its tap area", button.AbsoluteSize.X >= 44 and button.AbsoluteSize.Y >= 44)
		end
		healthy(h); app.unload()
	end)
end

scenario("short mobile history puts matching rows before navigation furniture", function()
	local h, app = boot(390, 844)
	local wanted
	for index = 1, 12 do
		local session = app.sessions.newThread(); session.rename("Saved project " .. index)
		if index == 12 then wanted = session end
	end
	local nav = app.app.showAppMenu(h.byName("Nav_menu"))
	local scroll = h.byName("NavigationScroll", nav.card)
	local history = h.byName("MobileHistory", nav.card)
	local toolbar = h.byName("ConversationActions", nav.card)
	local folder = h.byName("HistoryFolder", nav.card)
	check("folder and count share a row", h.byName("HistoryCount", nav.card):IsDescendantOf(folder))
	check("search chrome does not waste a second padding band", h.byName("NavigationBody", nav.card).Position.Y.Offset <= 52)
	scroll.CanvasPosition = h.dt.Vector2.new(0, 200)
	nav.filter.set("Saved project 12")
	check("a new query starts at its first match", scroll.CanvasPosition.Y == 0)
	keyboard(h, 664)
	check("short layout prioritises results", history.LayoutOrder < toolbar.LayoutOrder
		and toolbar:IsDescendantOf(scroll))
	check("folder controls remain available", folder.Visible and folder:IsDescendantOf(scroll))
	check("the matching conversation remains reachable", h.byName("Open_" .. wanted.id, history) ~= nil)
	keyboard(h, 0)
	check("normal navigation order returns", not toolbar:IsDescendantOf(scroll))
	healthy(h); app.unload()
end)

scenario("quick chat keeps mobile newlines, selection and actions through rotation", function()
	local h, app = boot(390, 844)
	local quick = app.env.require("ui/quickchat")
	local sends = 0
	app.sessions.current().send = function() sends = sends + 1; return true end
	quick.show(); h.settle(0.3)
	quick.field.set("A quick draft\nA second line")
	local field, card = quick.field.instance, quick.card
	field.CursorPosition, field.SelectionStart = 12, 3
	field.FocusLost:Fire(true)
	check("mobile Return never sends quick chat", sends == 0 and quick.visible and field.MultiLine)
	h.setViewport(844, 390); h.settle(0.4)
	check("rotation retains quick chat's native field", quick.field.instance == field and quick.card == card)
	check("rotation keeps the selection", field.CursorPosition == 12 and field.SelectionStart == 3)
	local send = h.byName("SendQuickChat", card)
	check("quick actions share the compact header", send.Parent.Name == "QuickHeader"
		and h.byName("OpenFullChat", card).Parent == send.Parent)
	check("quick send remains a full touch target", send.AbsoluteSize.Y >= 44)
	keyboard(h, 230)
	check("quick chat clears the keyboard", card.AbsolutePosition.Y + card.AbsoluteSize.Y <= 160)
	h.click(send)
	check("explicit Send submits once", sends == 1 and quick.field.get() == "" and not quick.visible)
	healthy(h); app.unload()
end)

scenario("vertical scrolling across settings sliders does not change a value", function()
	local h, app = boot(390, 844)
	local P, controls = app.env.require("ui/primitives"), app.env.require("ui/controls")
	local scroll = P.scroll(app.app.screen, { size = h.dt.UDim2.fromOffset(300, 200) })
	local changes, commits = 0, 0
	local slider = controls.slider(scroll.instance, { min = 0, max = 100, step = 1, value = 25,
		onChange = function() changes = changes + 1 end, onCommit = function() commits = commits + 1 end })
	local hit = slider.instance:FindFirstChildOfClass("TextButton")
	local track, E = slider.instance:FindFirstChild("Track"), h.sandbox.Enum
	local function finger(share)
		return { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin,
			Position = h.dt.Vector3.new(track.AbsolutePosition.X + track.AbsoluteSize.X * share, 10, 0), Changed = newSignal("slider touch") }
	end
	local swipe = finger(0.8)
	hit.InputBegan:Fire(swipe)
	check("touch start waits for gesture direction", slider.value == 25 and changes == 0)
	swipe.Position = swipe.Position + h.dt.Vector3.new(2, 32, 0)
	h.services.UserInputService.InputChanged:Fire(swipe)
	swipe.UserInputState = E.UserInputState.End; swipe.Changed:Fire()
	h.services.UserInputService.InputEnded:Fire(swipe)
	check("page scrolling neither changes nor commits the setting", slider.value == 25 and changes == 0 and commits == 0)
	local tap = finger(0.7)
	hit.InputBegan:Fire(tap); tap.UserInputState = E.UserInputState.End; tap.Changed:Fire()
	h.services.UserInputService.InputEnded:Fire(tap)
	check("a deliberate tap changes and commits exactly once", slider.value == 70 and changes == 1 and commits == 1)
	local drag = finger(0.4)
	hit.InputBegan:Fire(drag)
	drag.Position = finger(0.6).Position
	h.services.UserInputService.InputChanged:Fire(drag)
	check("horizontal touch dragging remains immediate", slider.value == 60)
	h.services.UserInputService.WindowFocusReleased:Fire()
	drag.Position = finger(0.9).Position
	h.services.UserInputService.InputChanged:Fire(drag)
	h.services.UserInputService.InputEnded:Fire(drag)
	check("focus loss releases the gesture without a late commit", slider.value == 60 and commits == 1 and drag.Changed:Count() == 0)
	local cancelled = finger(0.9)
	hit.InputBegan:Fire(cancelled); cancelled.UserInputState = E.UserInputState.Cancel; cancelled.Changed:Fire()
	check("cancelled touch is not treated as a tap", slider.value == 60 and commits == 1 and cancelled.Changed:Count() == 0)
	scroll.instance:Destroy(); healthy(h); app.unload()
end)

scenario("keyboard geometry bursts reveal focus once and input capabilities refresh live", function()
	local h, app = boot(1194, 834)
	local responsive, uis = app.env.require("ui/responsive"), h.services.UserInputService
	local original, reveals = responsive.revealFocused, 0
	responsive.revealFocused = function() reveals = reveals + 1 end
	uis.OnScreenKeyboardVisible = true
	uis.OnScreenKeyboardSize = h.dt.Vector2.new(1194, 300)
	uis.OnScreenKeyboardPosition = h.dt.Vector2.new(0, 534)
	for _, property in ipairs({ "OnScreenKeyboardVisible", "OnScreenKeyboardSize", "OnScreenKeyboardPosition" }) do
		uis:GetPropertyChangedSignal(property):Fire()
	end
	h.settle(0.08)
	check("one keyboard transition queues one focus adjustment", reveals == 1)
	responsive.revealFocused = original
	keyboard(h, 0)
	uis.MouseEnabled = true; uis:GetPropertyChangedSignal("MouseEnabled"):Fire(); h.settle(0.3)
	check("attaching a pointer refreshes input capability", responsive.pointer and responsive.mode == "window")
	uis.MouseEnabled = false; uis:GetPropertyChangedSignal("MouseEnabled"):Fire(); h.settle(0.3)
	check("removing the pointer restores touch navigation", responsive.isMobile() and responsive.mode == "panel")
	healthy(h); app.unload()
end)

for _, desktop in ipairs({ false, true }) do
	scenario((desktop and "desktop" or "mobile") .. " shared cards respect compact defaults and explicit spacing", function()
		local h, app = boot(desktop and 1280 or 390, desktop and 720 or 844, desktop)
		local P, theme = app.env.require("ui/primitives"), app.env.require("ui/theme")
		local card = P.card(app.app.screen, {})
		local explicit = P.card(app.app.screen, { padding = theme.space.xl, gap = theme.space.lg })
		check("card padding follows the platform", card:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset
			== (desktop and theme.space.lg or theme.space.md))
		check("card gap follows the platform", card:FindFirstChildOfClass("UIListLayout").Padding.Offset
			== (desktop and theme.space.md or theme.space.sm))
		check("explicit card spacing stays intact", explicit:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset == theme.space.xl
			and explicit:FindFirstChildOfClass("UIListLayout").Padding.Offset == theme.space.lg)
		local field = P.field(card, { multiline = true, height = 12 })
		check("multiline inputs also respect the platform target", field.shell.Size.Y.Offset >= (desktop and 28 or 44))
		card:Destroy(); explicit:Destroy(); healthy(h); app.unload()
	end)
end

print(string.format("mobile spacing: %d checks passed, %d scenarios failed", passed, failed))
if failed > 0 then os.exit(1) end
