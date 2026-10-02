-- Drag reachability, mobile density and desktop parity against the shipped bundle.
-- Run: luajit test/mobile_ui.lua [bundle] [previous bundle for desktop comparison]
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local envMock = require("env")
local newSignal = require("instance").newSignal
local bundle = arg[1] or "dist/uai.lua"
local passed, failed = 0, 0

local function check(label, value)
	assert(value, label)
	passed = passed + 1
end

local function scenario(label, run)
	local ok, err = pcall(run)
	if ok then print("ok " .. label)
	else failed = failed + 1; print("FAIL " .. label .. ": " .. tostring(err)) end
end

local function boot(touch, width, height, topbar, path)
	local h = envMock.new()
	local uis = h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = touch, not touch, not touch
	if topbar then
		h.services.GuiService.GetGuiInset = function()
			return h.dt.Vector2.new(0, topbar), h.dt.Vector2.new(0, 0)
		end
	end
	h.setViewport(width, height)
	local app = assert(h.boot(path or bundle))
	h.settle(1)
	app.app.show("chat")
	return h, app
end

-- Touch movement must reuse the initiating InputObject, unlike MouseMovement.
local function drag(h, target, dx, dy, touch)
	local E, V = h.sandbox.Enum, h.dt.Vector3
	local origin = target.AbsolutePosition
	local startX = target.Name == "Header" and math.min(96, target.AbsoluteSize.X * 0.4) or target.AbsoluteSize.X * 0.5
	local startY = math.min(20, target.AbsoluteSize.Y * 0.5)
	local input = { UserInputType = touch and E.UserInputType.Touch or E.UserInputType.MouseButton1,
		UserInputState = E.UserInputState.Begin,
		Position = V.new(origin.X + startX, origin.Y + startY, 0),
		Changed = newSignal("drag") }
	target.InputBegan:Fire(input)
	local move = touch and input or { UserInputType = E.UserInputType.MouseMovement }
	move.Position = V.new(input.Position.X + dx, input.Position.Y + dy, 0)
	h.services.UserInputService.InputChanged:Fire(move)
	input.UserInputState = E.UserInputState.End
	input.Changed:Fire()
	h.services.UserInputService.InputEnded:Fire(input)
end

local function keyboard(h, height)
	local uis = h.services.UserInputService
	uis.OnScreenKeyboardSize = h.dt.Vector2.new(844, height)
	uis.OnScreenKeyboardVisible = height > 0
	uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
	h.settle(0.3)
end

local function healthy(h)
	check("no asynchronous UI errors", #h.errors() == 0)
	check("valid GUI property types: " .. tostring(h.instanceState.typeErrors[1] or "none"), #h.instanceState.typeErrors == 0)
end

for _, touch in ipairs({ false, true }) do
	scenario((touch and "touch" or "mouse") .. " reaches every screen edge despite a tall top bar", function()
		local h, app = boot(touch, touch and 844 or 1280, touch and 390 or 720, 112)
		local window = app.app.window
		drag(h, window.header, -2000, -2000, touch)
		check("window reaches the top, not the reserved CoreGui band", window.root.AbsolutePosition.Y <= 8)
		check("window reaches the left edge", window.root.AbsolutePosition.X <= 8)
		drag(h, window.header, 2000, 2000, touch)
		local viewport = app.env.require("ui/responsive").viewport
		local bottom = viewport.Y - (touch and 24 or 0)
		local margin = app.env.require("ui/theme").space.sm
		check("window reaches the right edge", math.abs(window.root.AbsolutePosition.X + window.root.AbsoluteSize.X - (viewport.X - margin)) <= 1)
		check("window reaches the bottom without losing the composer", math.abs(window.root.AbsolutePosition.Y + window.root.AbsoluteSize.Y - (bottom - margin)) <= 1)
		drag(h, app.app.launcher, -2000, -2000, touch)
		check("launcher also reaches the top", app.app.launcher.AbsolutePosition.Y <= 8)
		check("launcher also reaches the left", app.app.launcher.AbsolutePosition.X <= 8)
		healthy(h)
	end)
end

scenario("portrait sheet moves upward and keeps the released position through a rebuild", function()
	local h, app = boot(true, 390, 844, 112)
	local window = app.app.window
	local originalY = window.root.AbsolutePosition.Y
	drag(h, window.header, 0, -160, true)
	check("portrait header moves the sheet", window.root.AbsolutePosition.Y < originalY - 100)
	local savedY = window.root.Position.Y.Offset
	check("release saves immediately", app.config.get("ui.mobileSheet.y") == savedY)
	app.app.rebuild("test placement")
	check("rebuild retains the dragged sheet", app.app.window.root.Position.Y.Offset == savedY)
	drag(h, app.app.window.header, 0, -2000, true)
	check("portrait sheet reaches the top safe edge", app.app.window.root.AbsolutePosition.Y <= 8)
	check("mobile movement leaves desktop placement alone", not app.config.get("ui.window.placed"))
	healthy(h)
end)

scenario("mobile header separates window controls from move and resize gestures", function()
	local h, app = boot(true, 844, 390)
	local window = app.app.window
	local close = h.byName("Close", window.root)
	local E, V = h.sandbox.Enum, h.dt.Vector3
	local point = close.AbsolutePosition
	local finger = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin,
		Position = V.new(point.X + 10, point.Y + 10, 0), Changed = newSignal("control") }
	local position = tostring(window.root.Position)
	window.header.InputBegan:Fire(finger)
	finger.Position = V.new(point.X - 100, point.Y + 50, 0)
	h.services.UserInputService.InputChanged:Fire(finger)
	check("pressing a header control does not start a window drag", tostring(window.root.Position) == position)
	local width, height = window.root.Size.X.Offset, window.root.Size.Y.Offset
	drag(h, h.byName("ResizeGrip", window.root), 20, -40, true)
	check("corner grip still resizes the mobile panel", window.root.Size.X.Offset > width and window.root.Size.Y.Offset < height)
	check("resize release is saved", app.config.get("ui.mobilePanel.height") == window.root.Size.Y.Offset)
	healthy(h)
end)

scenario("mobile expansion, keyboard and rotation preserve size and draft", function()
	local h, app = boot(true, 844, 390)
	local window, composer = app.app.window, app.app.chatPanel.composer
	app.config.set("ui.window.maximised", true, { quiet = true })
	composer.field.set("Keep this mobile draft")
	local desktop = app.config.get("ui.window")
	local desktopBefore = h.json.encode(desktop)
	drag(h, window.header, -90, -20, true)
	local x, y, width, height = window.root.Position.X.Offset, window.root.Position.Y.Offset,
		window.root.Size.X.Offset, window.root.Size.Y.Offset
	local expand = h.byName("Maximise", window.root)
	check("handheld uses the same maximise action as desktop", expand ~= nil and expand.AbsoluteSize.Y >= app.env.require("ui/responsive").minTarget())
	h.click(expand)
	check("expand uses the available screen height", window.root.Size.Y.Offset > height)
	check("expansion keeps the same composer and draft", app.app.chatPanel.composer == composer and composer.field.get() == "Keep this mobile draft")
	h.click(expand)
	check("restore returns to the chosen size and position", window.root.Position.X.Offset == x and window.root.Position.Y.Offset == y
		and window.root.Size.X.Offset == width and window.root.Size.Y.Offset == height)
	composer.setExpanded(true)
	keyboard(h, 230)
	check("keyboard cannot cover the window", window.root.AbsolutePosition.Y + window.root.AbsoluteSize.Y <= 160)
	check("expanded input fits the remaining body", composer.shell.AbsoluteSize.Y <= app.app.chatPanel.root.AbsoluteSize.Y)
	check("keyboard keeps the compact input target", composer.field.shell.AbsoluteSize.Y >= app.env.require("ui/responsive").minTarget())
	keyboard(h, 0)
	check("keyboard dismissal restores geometry", window.root.Position.X.Offset == x and window.root.Position.Y.Offset == y
		and window.root.Size.X.Offset == width and window.root.Size.Y.Offset == height)
	h.setViewport(390, 844)
	check("rotation preserves draft text", app.app.chatPanel.composer.field.get() == "Keep this mobile draft")
	h.setViewport(844, 390)
	check("returning to landscape restores its placement", app.app.window.root.Position.X.Offset == x and app.app.window.root.Position.Y.Offset == y)
	check("mobile never overwrites desktop geometry", h.json.encode(desktop) == desktopBefore)
	healthy(h)
end)

for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 390 }, { 1280, 720 } }) do
	scenario("mobile stays compact and tappable at " .. size[1] .. "x" .. size[2], function()
		local h, app = boot(true, size[1], size[2])
		local window, composer = app.app.window, app.app.chatPanel.composer
		local theme, responsive = app.env.require("ui/theme"), app.env.require("ui/responsive")
		check("sidebar is the same mounted component on every width", app.app.sidebar ~= nil)
		check("sidebar retains the desktop composition at every width", app.app.sideHolder.Visible)
		check("the regular menu remains available when the sidebar is collapsed", h.byName("Nav_menu", window.root) ~= nil)
		check("header uses substantially reduced native metrics", window.headerHeight <= 38)
		check("collapsed composer remains compact", composer.shell.Size.Y.Offset <= 56)
		check("the desktop header brand and detail remain present", h.byName("HeaderBrand", window.root).Visible
			and h.byName("TitleDetail", window.root).Visible)
		check("the shared welcome view keeps its brand", h.byName("HomeBrand", window.root).Visible)
		check("the handheld control minimum is reduced", responsive.minTarget() == 15)
		for _, name in ipairs({ "Close", "Minimize", "Maximise", "ResizeGrip", "Send", "AddContext", "ComposerOptions", "Starter_explore" }) do
			local control = assert(h.byName(name, window.root), name)
			check(name .. " retains its compact target", control.AbsoluteSize.X >= responsive.minTarget() and control.AbsoluteSize.Y >= responsive.minTarget())
		end
		local grip = h.byName("ResizeGrip", window.root)
		check("resize is a corner grip on the panel like desktop", grip.Parent == window.root
			and grip.AnchorPoint.X == 1 and grip.AnchorPoint.Y == 1)
		local starter = h.byName("Starter_explore", window.root)
		local content = starter:FindFirstChild("Content")
		local padding = content:FindFirstChildOfClass("UIPadding")
		check("the shared starter card fits its readable content", starter.Size.Y.Offset >= theme.size.promptCard
			and content.AbsoluteSize.Y + 1 >= content:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize.Y
				+ padding.PaddingTop.Offset + padding.PaddingBottom.Offset)
		h.click(h.byName("Starter_explore", window.root))
		check("compact starter still inserts its prompt", composer.field.get():find("Explore this game", 1, true) ~= nil)
		h.click(h.byName("ComposerOptions", window.root))
		check("model controls remain reachable", h.byName("Option_model") ~= nil)
		check("no alternate mobile shell is built", h.byName("ExpandPanel", window.root) == nil and h.byName("MobileNavigation") == nil)
		healthy(h)
	end)
end

scenario("handheld keeps compact desktop geometry with readable text and icons", function()
	local desktopHarness, desktop = boot(false, 1280, 720)
	local h, app = boot(true, 390, 844)
	local desktopTheme, theme = desktop.env.require("ui/theme"), app.env.require("ui/theme")
	for _, entry in ipairs({
		{ "size", "header" }, { "size", "sidebar" }, { "size", "control" },
		{ "size", "codeWide" }, { "space", "sm" }, { "space", "lg" }, { "space", "xl" },
		{ "radius", "md" }, { "radius", "lg" },
	}) do
		check(entry[1] .. "." .. entry[2] .. " follows the uniform scale",
			math.abs(theme[entry[1]][entry[2]] - desktopTheme[entry[1]][entry[2]] * 0.55) <= 1)
	end
	for _, role in ipairs({ "body", "caption", "title", "mono" }) do
		check(role .. " text stays small without falling below the reading floor", theme.text[role].size >= 10
			and theme.text[role].size < desktopTheme.text[role].size)
	end
	check("standard icons retain a full-pixel artwork stroke", theme.size.icon >= 12 and theme.size.iconLarge >= 12)
	check("native title and input use the readable type sizes", app.app.titleLabel.TextSize >= 10
		and app.app.chatPanel.composer.field.instance.TextSize >= 10)
	check("native header height follows the desktop proportion", math.abs(app.app.window.headerHeight - desktop.app.window.headerHeight * 0.55) <= 1)
	check("native composer height follows the desktop proportion", math.abs(app.app.chatPanel.composer.shell.Size.Y.Offset - desktop.app.chatPanel.composer.shell.Size.Y.Offset * 0.55) <= 3)
	for _, name in ipairs({ "HeaderBrand", "TitleDetail", "Minimize", "Maximise", "Close", "HomeBrand", "GreetingSubtitle", "AddContext", "ComposerOptions" }) do
		local small, original = assert(h.byName(name, app.app.window.root)), assert(desktopHarness.byName(name, desktop.app.window.root))
		check(name .. " retains desktop ownership", small.ClassName == original.ClassName and small.Parent.Name == original.Parent.Name)
	end
	local window, composer = app.app.window, app.app.chatPanel.composer
	composer.field.set("Keep the shared draft")
	local field = composer.field.instance
	h.click(h.byName("Nav_collapse", window.root))
	check("explicit collapse changes layout without replacing the input", not app.app.sideHolder.Visible and app.app.chatPanel.composer.field.instance == field)
	h.click(h.byName("Nav_collapse", window.root))
	check("expanding restores the same sidebar and draft", app.app.sideHolder.Visible and app.app.window == window and composer.field.get() == "Keep the shared draft")
	h.click(h.byName("Minimize", window.root))
	check("the shared minimize control exposes the launcher", not window.visible and app.app.launcher.Visible)
	h.click(app.app.launcher)
	check("restore keeps the same mounted draft", window.visible and app.app.chatPanel.composer.field.instance == field and composer.field.get() == "Keep the shared draft")
	local oldCaption = theme.text.caption.size
	app.config.set("ui.fontScale", 1.2); h.settle(0.5)
	check("text scale still enlarges the smallest text", theme.text.caption.size > oldCaption)
	check("text scaling retains the draft", app.app.chatPanel.composer.field.get() == "Keep the shared draft")
	healthy(h); healthy(desktopHarness); app.unload(); desktop.unload()
end)

scenario("dragging respects an inset parent without counting the CoreGui band twice", function()
	local h, app = boot(true, 1000, 600, 112)
	local parent = h.Instance.new("Frame", app.app.screen)
	parent.Position = h.dt.UDim2.fromOffset(32, 24)
	parent.Size = h.dt.UDim2.fromOffset(936, 552)
	local window = app.env.require("ui/window").new(parent)
	window.show()
	drag(h, window.header, -2000, -2000, true)
	local margin = app.env.require("ui/theme").space.sm
	check("left device-safe inset is counted once", window.root.AbsolutePosition.X == 32 + margin)
	check("top device-safe inset is counted once", window.root.AbsolutePosition.Y == 24 + margin)
	window.destroy()
	parent:Destroy()
	healthy(h)
end)

for _, touch in ipairs({ false, true }) do
	scenario((touch and "touch" or "mouse") .. " uses GUI pixels when camera resolution differs", function()
		local h, app = boot(touch, 1000, 600)
		-- The native UI grows while the camera still reports its render viewport.
		h.instanceState.viewport = h.dt.Vector2.new(1400, 840)
		app.env.require("ui/responsive").refresh("scaled display")
		local window = app.app.window
		drag(h, window.header, 2000, 2000, touch)
		local theme = app.env.require("ui/theme")
		check("right drag bound follows the full GUI width", window.root.AbsolutePosition.X + window.root.AbsoluteSize.X == 1400 - theme.space.sm)
		check("bottom drag bound follows the full GUI height", window.root.AbsolutePosition.Y + window.root.AbsoluteSize.Y == 840 - theme.space.sm - (touch and 24 or 0))
		drag(h, app.app.launcher, 2000, 2000, touch)
		check("launcher also uses the full GUI width", app.app.launcher.AbsolutePosition.X + app.app.launcher.AbsoluteSize.X == 1400 - theme.space.xs)
		healthy(h)
	end)
end

scenario("desktop appearance stays unchanged", function()
	local h, app = boot(false, 1280, 720)
	local window = app.app.window
	check("desktop keeps its sidebar", app.app.sidebar ~= nil)
	check("desktop keeps the original header", window.headerHeight == 56)
	check("desktop keeps the original composer", app.app.chatPanel.composer.shell.Size.Y.Offset == 62)
	check("desktop keeps the bottom inset", app.app.chatPanel.composer.shell.Position.Y.Offset == -3)
	check("desktop keeps header details and welcome mark", h.byName("TitleDetail", window.root).Visible and h.byName("HomeBrand", window.root).Visible)
	check("desktop retains its corner grip", h.byName("ResizeGrip", window.root).Parent == window.root)
	check("mobile expand control stays off desktop", h.byName("ExpandPanel", window.root) == nil)
	if arg[2] then
		local oldH, oldApp = boot(false, 1280, 720, nil, arg[2])
		local function geometry(node)
			return table.concat({ tostring(node.Size), tostring(node.Position), tostring(node.AnchorPoint), tostring(node.Visible) }, "|")
		end
		for _, name in ipairs({ "UAI_Window", "Header", "HeaderBrand", "TitleDetail", "Composer", "ComposerSurface", "Home",
			"HomeBrand", "GreetingText", "GreetingSubtitle", "Starter_explore", "ResizeGrip", "Minimize", "Maximise", "Close" }) do
			check("desktop geometry matches the previous bundle: " .. name,
				geometry(assert(h.byName(name))) == geometry(assert(oldH.byName(name))))
		end
		oldApp.unload()
	end
	healthy(h)
end)

print(string.format("mobile UI: %d checks passed, %d scenarios failed", passed, failed))
if failed > 0 then os.exit(1) end
