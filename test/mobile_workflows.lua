-- Mobile behavior against the shipped bundle. Run with LuaJIT or lune_runner.
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
local function boot(width, height)
	local h = envMock.new()
	h.services.UserInputService.TouchEnabled = true
	h.services.UserInputService.MouseEnabled = false
	h.setViewport(width, height)
	local app = assert(h.boot(arg[1] or "dist/uai.lua")); h.settle(1); app.app.show("chat")
	return h, app
end
local function healthy(h)
	check("no asynchronous errors", #h.errors() == 0)
	check("valid property assignments", #h.instanceState.typeErrors == 0)
	for _, warning in ipairs(h.console.warnings) do
		check("no hidden UI callback failures", not warning:find("handler failed", 1, true) and not warning:find("pane failed", 1, true))
	end
end
local function keyboard(h, height, top)
	local uis = h.services.UserInputService
	uis.OnScreenKeyboardSize = h.dt.Vector2.new(h.instanceState.viewport.X, height)
	uis.OnScreenKeyboardPosition = h.dt.Vector2.new(0, top or 0)
	uis.OnScreenKeyboardVisible = height > 0
	uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
	h.settle(0.3)
end
local function drag(h, target, dx, dy)
	local E, V = h.sandbox.Enum, h.dt.Vector3
	local p = target.AbsolutePosition
	local input = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin,
		Position = V.new(p.X + 100, p.Y + 20, 0), Changed = newSignal("touch") }
	target.InputBegan:Fire(input)
	input.Position = V.new(p.X + 100 + dx, p.Y + 20 + dy, 0)
	h.services.UserInputService.InputChanged:Fire(input)
	input.UserInputState = E.UserInputState.End; input.Changed:Fire()
	h.services.UserInputService.InputEnded:Fire(input)
end

scenario("tablet rotation preserves the live editor and separate orientation placements", function()
	local h, app = boot(834, 1194)
	local window, composer = app.app.window, app.app.chatPanel.composer
	local desktop = h.json.encode(app.config.get("ui.window"))
	composer.field.set("Keep this draft and selection")
	local field = composer.field.instance
	field.CursorPosition, field.SelectionStart = 12, 4
	drag(h, window.header, -35, -85)
	local portrait = h.json.encode(app.config.get("ui.mobileSheet"))
	local portraitY = window.root.Position.Y.Offset
	h.setViewport(1194, 834); h.settle(0.3)
	check("tablet keeps the same window", app.app.window == window)
	check("tablet keeps the same text field", app.app.chatPanel.composer.field.instance == field)
	check("rotation preserves selection", field.CursorPosition == 12 and field.SelectionStart == 4)
	drag(h, window.header, -120, -65)
	local landscape = h.json.encode(app.config.get("ui.mobilePanel"))
	check("landscape never overwrites portrait", h.json.encode(app.config.get("ui.mobileSheet")) == portrait)
	h.setViewport(834, 1194); h.settle(0.3)
	check("portrait placement restores", window.root.Position.Y.Offset == portraitY)
	check("landscape placement stays saved", h.json.encode(app.config.get("ui.mobilePanel")) == landscape)
	app.config.set("ui.layout", "window"); h.settle(0.4)
	check("a forced window retains the shared sidebar", app.app.sidebar ~= nil and app.app.sideHolder.Visible)
	drag(h, window.header, 20, -20)
	window.toggleMaximised(); window.toggleMaximised()
	check("mobile never writes desktop placement", h.json.encode(app.config.get("ui.window")) == desktop)
	healthy(h); app.unload()
end)

for _, size in ipairs({ { 844, 390 }, { 932, 430 }, { 1194, 834 }, { 667, 375 }, { 320, 568 }, { 390, 844 } }) do
	scenario("input stays usable at " .. size[1] .. "x" .. size[2], function()
		local h, app = boot(size[1], size[2])
		local composer = app.app.chatPanel.composer
		local field = composer.field.instance
		check("touch always supports newlines", field.MultiLine == true)
		check("the reduced input retains useful editable width", composer.field.shell.AbsoluteSize.X >= 60)
		check("launcher cannot cover Send", app.app.launcher.Visible == false)
		local sends = 0
		app.sessions.current().send = function() sends = sends + 1; return true end
		composer.field.set("A first line\nAnd a second line")
		check("shared composer controls stay mounted", h.byName("ModelChip", composer.shell) ~= nil
			and h.byName("AddContext", composer.shell).Visible)
		field.FocusLost:Fire(true)
		check("keyboard return never accidentally submits", sends == 0)
		composer.setExpanded(true)
		check("expansion keeps the native input object", composer.field.instance == field)
		local chosen = app.app.window.root.Size.Y.Offset
		keyboard(h, math.floor(size[2] * 0.55))
		local root, body = app.app.window.root, app.app.chatPanel.root
		check("window clears keyboard", root.AbsolutePosition.Y + root.AbsoluteSize.Y <= size[2] - math.floor(size[2] * 0.55))
		check("input fits body", composer.shell.AbsoluteSize.Y <= body.AbsoluteSize.Y)
		check("input preserves its compact target", composer.field.shell.AbsoluteSize.Y >= app.env.require("ui/responsive").minTarget())
		check("keyboard retains text", composer.field.get() == "A first line\nAnd a second line")
		local send = h.byName("Send", composer.shell)
		local inputRight = composer.field.shell.AbsolutePosition.X + composer.field.shell.AbsoluteSize.X
		local inputBottom = composer.field.shell.AbsolutePosition.Y + composer.field.shell.AbsoluteSize.Y
		check("input and Send never overlap", inputRight <= send.AbsolutePosition.X or inputBottom <= send.AbsolutePosition.Y)
		h.click(send)
		check("Send submits once", sends == 1 and composer.field.get() == "")
		keyboard(h, 0)
		check("keyboard dismissal restores height", root.Size.Y.Offset == chosen)
		app.app.hide()
		check("minimizing restores launcher", app.app.launcher.Visible)
		h.click(app.app.launcher)
		check("launcher reopens the panel and moves out of the way", app.app.window.visible and not app.app.launcher.Visible)
		healthy(h); app.unload()
	end)
end

scenario("context and many attachments cannot displace the input above a keyboard", function()
	local h, app = boot(390, 844)
	local composer, session = app.app.chatPanel.composer, app.sessions.current()
	for index = 1, 20 do composer.attachments[index] = { label = "notes/long-file-name-" .. index .. ".txt", text = "context" } end
	composer.field.set("Keep every attachment")
	local other = app.sessions.newThread()
	composer.attach(other); composer.attach(session)
	check("all attachments restore", #composer.attachments == 20)
	local strip = h.byName("AttachmentStrip", composer.shell)
	check("attachments use the same wrapped scrolling region as desktop", strip.ScrollingDirection == h.sandbox.Enum.ScrollingDirection.Y)
	h.click(h.byName("ComposerOptions", composer.shell)); h.click(h.byName("Option_context"))
	check("context can be expanded", h.byName("ContextStrip", composer.shell).Visible)
	h.setViewport(844, 390); keyboard(h, 300)
	check("many attachments cannot cover input", composer.shell.AbsoluteSize.Y <= app.app.chatPanel.root.AbsoluteSize.Y)
	check("tight keyboard space hides only the attachment preview", not strip.Visible and #composer.attachments == 20)
	h.click(h.byName("ComposerOptions", composer.shell)); h.click(h.byName("Option_attachments"))
	check("hidden attachments remain manageable", h.byName("Option_20") ~= nil)
	h.click(h.byName("Option_20"))
	check("removal edits only the chosen attachment", #composer.attachments == 19 and composer.attachments[19].label:find("19.txt", 1, true))
	keyboard(h, 0); h.setViewport(390, 844); h.settle(0.3)
	check("context preference returns after keyboard dismissal", h.byName("ContextStrip", composer.shell).Visible)
	healthy(h); app.unload()
end)

scenario("shared conversation search opens a result without losing drafts or summoning a keyboard", function()
	local h, app = boot(390, 844)
	local conversations = {}
	for index = 1, 14 do
		conversations[index] = app.sessions.newThread()
		conversations[index].rename("Project " .. index)
	end
	local current = app.sessions.current()
	app.app.openSession(current.id)
	app.app.chatPanel.composer.field.set("Draft stays with this chat")
	local search = app.app.showSearch()
	local field = h.byName("SearchField", search.card):FindFirstChildOfClass("TextBox")
	field.Text = "Project 14"
	field.CursorPosition, field.SelectionStart = 8, 3
	h.setViewport(844, 390); h.settle(0.3)
	h.setViewport(390, 844); h.settle(0.3)
	check("rotation retains the native search field and selection", h.byName("SearchField", search.card):FindFirstChildOfClass("TextBox") == field
		and field.CursorPosition == 8 and field.SelectionStart == 3)
	check("search finds its unique matching conversation", h.textOf(h.byName("Result_1", search.card)):find("Project 14", 1, true) ~= nil
		and h.byName("Result_2", search.card) == nil)
	field.Text = "Project 2"
	local focusCalls = 0
	app.app.chatPanel.composer.focus = function() focusCalls = focusCalls + 1 end
	h.click(h.byName("Result_1", search.card))
	check("search reaches conversations beyond the recent menu limit", app.sessions.activeId == conversations[2].id and search.closed)
	check("opening history does not summon the keyboard", focusCalls == 0)
	app.app.openSession(current.id)
	check("history navigation retains drafts", app.app.chatPanel.composer.field.get() == "Draft stays with this chat")
	h.click(h.byName("Nav_collapse", app.app.window.root)); h.settle(0.3)
	local menuButton = h.byName("Nav_menu", app.app.window.header)
	check("the collapsed layout exposes its header menu", menuButton.Visible)
	h.click(menuButton)
	h.click(h.byName("Option_session:" .. current.id))
	check("the shared conversation menu retains management actions", h.byName("Option_open") and h.byName("Option_rename")
		and h.byName("Option_move") and h.byName("Option_delete"))
	app.env.require("ui/overlay").closeAll(); h.settle(0.4)
	healthy(h); app.unload()
end)

scenario("shared settings categories and anchored menus fit landscape keyboards", function()
	local h, app = boot(844, 390)
	local dialog = app.app.showSettingsDialog("agent")
	check("settings opens the requested category", dialog.activeCategory() == "agent")
	check("settings uses its normal category rows", h.byName("Category_agent", dialog.card) ~= nil and h.byName("CategoryPicker", dialog.card) == nil)
	local pane = h.byName("Pane_agent", dialog.card)
	h.setViewport(390, 844); h.settle(0.3)
	check("rotating settings keeps its live pane", h.byName("Pane_agent", dialog.card) == pane)
	check("all categories are reachable", h.byName("Category_infinite_yield", dialog.card) ~= nil)
	h.click(h.byName("Category_privacy", dialog.card))
	check("choosing a category updates the same dialog", dialog.activeCategory() == "privacy" and not dialog.closed)
	h.setViewport(844, 390); keyboard(h, 220)
	local overlay = app.env.require("ui/overlay")
	local menu = overlay.menu({ target = h.byName("Category_privacy", dialog.card), options = {
		{ label = "First action", value = "first" }, { label = "Second action", value = "second" },
	} })
	check("anchored menu clears keyboard", menu.card.AbsolutePosition.Y + menu.card.AbsoluteSize.Y <= 170)
	check("the shared menu keeps readable option space", h.byName("Options", menu.card).AbsoluteSize.Y >= app.env.require("ui/responsive").minTarget())
	check("no separate mobile menu chrome is built", h.byName("MenuClose", menu.card) == nil)
	h.press("Escape")
	check("Escape dismisses the same anchored menu", menu.closed)
	app.env.require("ui/overlay").closeAll(); h.settle(0.4)
	healthy(h); app.unload()
end)

scenario("keyboard position and focused forms use device-safe coordinates", function()
	local h, app = boot(390, 844)
	local responsive = app.env.require("ui/responsive")
	keyboard(h, 200, 430)
	local root = app.app.window.root
	check("a floating keyboard is avoided at its reported top", root.AbsolutePosition.Y + root.AbsoluteSize.Y <= 430)
	local P = app.env.require("ui/primitives")
	local scroll = P.scroll(app.app.screen, { name = "FocusTest", size = h.dt.UDim2.fromOffset(300, 120),
		position = h.dt.UDim2.fromOffset(10, 60) })
	scroll.instance.AbsoluteCanvasSize = h.dt.Vector2.new(300, 800)
	local field = P.field(scroll.instance, { name = "OffscreenField" })
	field.instance.AbsolutePosition = h.dt.Vector2.new(20, 460)
	h.services.UserInputService.GetFocusedTextBox = function() return field.instance end
	responsive.revealFocused()
	check("keyboard focus reveals its form field", scroll.instance.CanvasPosition.Y > 300)
	check("focus reveal keeps scrolling within content", scroll.instance.CanvasPosition.Y <= 680)
	scroll.instance:Destroy(); h.services.UserInputService.GetFocusedTextBox = function() return nil end
	healthy(h); app.unload()
end)

print(string.format("mobile workflows: %d checks passed, %d scenarios failed", passed, failed))
if failed > 0 then os.exit(1) end
