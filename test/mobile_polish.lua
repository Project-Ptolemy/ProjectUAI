-- Short mobile forms and keyboard focus against the shipped native bundle.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local envMock = require("env")
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

for _, size in ipairs({ { 844, 390, 230 }, { 667, 375, 260 }, { 320, 568, 420 } }) do
	scenario("a form and its actions remain reachable above a keyboard at " .. size[1] .. "x" .. size[2], function()
		local h, app = boot(size[1], size[2])
		local overlay, P = app.env.require("ui/overlay"), app.env.require("ui/primitives")
		local modal = overlay.modal({ title = "Rename folder", scroll = true })
		local field = P.field(modal.content, { name = "FolderName", text = "My shared scripts" })
		field.instance.CursorPosition, field.instance.SelectionStart = 9, 4
		local accepted
		local save = P.button(modal.footer, { name = "SaveName", text = "Save", onClick = function() accepted = field.get() end })
		h.settle(0.2)
		check("ordinary forms keep pinned actions", modal.footer.Parent == modal.card)
		keyboard(h, size[3])
		check("form clears the keyboard", modal.card.AbsolutePosition.Y + modal.card.AbsoluteSize.Y <= size[2] - size[3])
		local target = app.env.require("ui/responsive").minTarget()
		check("short forms retain a usable body", modal.scroll.instance.AbsoluteSize.Y >= target)
		check("short form actions remain in the live card", save.instance:IsDescendantOf(modal.card)
			and (save.instance:IsDescendantOf(modal.scroll.instance) or modal.footer.Parent == modal.card))
		check("actions keep their configured targets", save.instance.AbsoluteSize.Y >= target and modal.footer.AbsoluteSize.Y >= target)
		check("dismissal stays reachable above the body", h.byName("Close", modal.card).AbsoluteSize.Y >= target)
		check("reflow retains the input and selection", h.byName("FolderName", modal.card) == field.shell
			and field.instance.CursorPosition == 9 and field.instance.SelectionStart == 4)
		field.set("Universal scripts")
		h.click(save.instance)
		check("the original action uses the live draft", accepted == "Universal scripts")
		keyboard(h, 0)
		check("keyboard dismissal pins the same actions again", modal.footer.Parent == modal.card and save.instance.Parent == modal.footer)
		check("keyboard dismissal retains the edited draft", field.get() == "Universal scripts")
		healthy(h); app.unload()
	end)
end

scenario("wrapped mobile actions retain their full height in short forms", function()
	local h, app = boot(320, 568)
	local overlay, P = app.env.require("ui/overlay"), app.env.require("ui/primitives")
	local modal = overlay.modal({ title = "Manage this folder", scroll = true })
	P.field(modal.content, { name = "FolderName", text = "Universal" })
	P.button(modal.footer, { text = "Save changes" })
	P.button(modal.footer, { text = "Move conversations" })
	-- The mock does not run native wrapping. Supply the measured two-row footer.
	modal.footer:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize = h.dt.Vector2.new(230, 96)
	keyboard(h, 440)
	check("wrapping keeps the actions inside the scroll canvas", modal.footer.Parent == modal.scroll.instance)
	check("wrapping never truncates the second action row", modal.footer.Size.Y.Offset >= 96)
	check("wrapping still leaves room to edit", modal.scroll.instance.Size.Y.Offset >= app.env.require("ui/responsive").minTarget())
	modal.footer.Visible = false; h.settle(0.2)
	check("hiding actions returns their reserved space", not modal.footer.Visible and modal.footer.Size.Y.Offset == 0)
	modal.footer.Visible = true; h.settle(0.2)
	check("actions can return while constrained", modal.footer.Visible and modal.footer.Parent == modal.scroll.instance)
	keyboard(h, 0)
	check("wrapped actions pin again in ordinary space", modal.footer.Parent == modal.card)
	check("restored footer has its side padding", modal.footer:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset > 0)
	modal.close(); h.settle(0.3)
	check("closing reparented actions releases the overlay", #overlay.open == 0)
	keyboard(h, 260)
	check("closed forms do not return during keyboard updates", h.byName("FolderName") == nil)
		healthy(h); app.unload()
end)

scenario("mobile focus accounts for the reported keyboard edge", function()
	local h, app = boot(390, 844)
	keyboard(h, 200, 430)
	local P, responsive = app.env.require("ui/primitives"), app.env.require("ui/responsive")
	local scroll = P.scroll(app.app.screen, { size = h.dt.UDim2.fromOffset(300, 500), position = h.dt.UDim2.fromOffset(10, 60) })
	scroll.instance.AbsoluteCanvasSize = h.dt.Vector2.new(300, 1200)
	local field = P.field(scroll.instance, {})
	field.instance.AbsolutePosition = h.dt.Vector2.new(20, 410)
	h.services.UserInputService.GetFocusedTextBox = function() return field.instance end
	responsive.revealFocused()
	check("a field below the usable edge is scrolled upward", scroll.instance.CanvasPosition.Y > 0)
	check("the whole field clears the keyboard", 410 + field.instance.AbsoluteSize.Y - scroll.instance.CanvasPosition.Y <= 430)
	check("focus scrolling stays within the content", scroll.instance.CanvasPosition.Y <= 700)
	scroll.instance:Destroy(); healthy(h); app.unload()
end)

scenario("mobile focus respects clipping and does not repeat an inner scroll", function()
	local h, app = boot(390, 844)
	local P, responsive = app.env.require("ui/primitives"), app.env.require("ui/responsive")
	local clip = P.frame(app.app.screen, { size = h.dt.UDim2.fromOffset(300, 120), position = h.dt.UDim2.fromOffset(10, 40), clip = true })
	local clipped = P.scroll(clip, { size = h.dt.UDim2.fromOffset(300, 300) })
	clipped.instance.AbsoluteCanvasSize = h.dt.Vector2.new(300, 900)
	local field = P.field(clipped.instance, {})
	field.instance.AbsolutePosition = h.dt.Vector2.new(20, 220)
	h.services.UserInputService.GetFocusedTextBox = function() return field.instance end
	responsive.revealFocused()
	check("focus reveals through a clipping frame", clipped.instance.CanvasPosition.Y > 0)
	check("the field clears the clipping edge", 220 + field.instance.AbsoluteSize.Y - clipped.instance.CanvasPosition.Y <= 160)
	clip.Visible = false; clipped.instance.CanvasPosition = h.dt.Vector2.new(0, 0)
	responsive.revealFocused()
	check("hidden fields cannot move a background panel", clipped.instance.CanvasPosition.Y == 0)
	clip:Destroy()
	local outer = P.scroll(app.app.screen, { size = h.dt.UDim2.fromOffset(300, 220), position = h.dt.UDim2.fromOffset(10, 20) })
	outer.instance.AbsoluteCanvasSize = h.dt.Vector2.new(300, 700)
	local inner = P.scroll(outer.instance, { size = h.dt.UDim2.fromOffset(280, 120), position = h.dt.UDim2.fromOffset(0, 40) })
	inner.instance.AbsoluteCanvasSize = h.dt.Vector2.new(280, 800)
	field = P.field(inner.instance, {})
	field.instance.AbsolutePosition = h.dt.Vector2.new(20, 500)
	responsive.revealFocused()
	check("the nearest scroller reveals its own input", inner.instance.CanvasPosition.Y > 0)
	check("an outer panel does not repeat the same displacement", outer.instance.CanvasPosition.Y == 0)
	check("the result fits the inner viewport", 500 + field.instance.AbsoluteSize.Y - inner.instance.CanvasPosition.Y <= 180)
	outer.instance:Destroy(); healthy(h); app.unload()
end)

scenario("the shared app menu keeps New conversation reachable with a keyboard", function()
	local h, app = boot(844, 390)
	local overlay = app.env.require("ui/overlay")
	h.click(h.byName("Nav_collapse", app.app.window.root))
	local menuButton = h.byName("Nav_menu", app.app.window.header)
	check("collapsing the sidebar reveals the shared header menu", menuButton.Visible)
	h.click(menuButton)
	local nav = overlay.open[#overlay.open]
	local button = h.byName("Option_new", nav.card)
	check("New conversation is a normal menu option", button and button:IsDescendantOf(h.byName("Options", nav.card)))
	keyboard(h, 230)
	check("short navigation scrolls all its actions", h.byName("Options", nav.card).ScrollingEnabled
		and button.AbsoluteSize.Y >= app.env.require("ui/responsive").minTarget())
	check("the navigation card fits above the keyboard", nav.card.AbsolutePosition.Y + nav.card.AbsoluteSize.Y <= 160)
	keyboard(h, 0)
	check("keyboard dismissal retains the same action", h.byName("Option_new", nav.card) == button)
	keyboard(h, 230); h.click(button)
	check("New conversation remains usable above the keyboard", nav.closed and h.byName("ConversationName") ~= nil)
	healthy(h); app.unload()
end)

scenario("focus leaves horizontal strips and desktop forms alone", function()
	for _, desktop in ipairs({ false, true }) do
		local h, app = boot(844, 390, desktop)
		local P, responsive = app.env.require("ui/primitives"), app.env.require("ui/responsive")
		local scroll = P.scroll(app.app.screen, { size = h.dt.UDim2.fromOffset(300, 80), horizontal = not desktop })
		scroll.instance.AbsoluteCanvasSize = h.dt.Vector2.new(900, 800)
		scroll.instance.CanvasPosition = h.dt.Vector2.new(33, 0)
		local field = P.field(scroll.instance, {})
		field.instance.AbsolutePosition = h.dt.Vector2.new(20, 460)
		h.services.UserInputService.GetFocusedTextBox = function() return field.instance end
		responsive.revealFocused()
		check("focus preserves the existing scroll position", scroll.instance.CanvasPosition.X == 33 and scroll.instance.CanvasPosition.Y == 0)
		if desktop then
			local modal = app.env.require("ui/overlay").modal({ title = "Desktop form", scroll = true })
			P.field(modal.content, {})
			P.button(modal.footer, { text = "Save" })
			keyboard(h, 230)
			check("pointer forms use the same bounded footer rules", modal.footer:IsDescendantOf(modal.card)
				and modal.card.AbsolutePosition.Y + modal.card.AbsoluteSize.Y <= 160)
		end
		scroll.instance:Destroy(); healthy(h); app.unload()
	end
end)

print(string.format("mobile polish: %d checks passed, %d scenarios failed", passed, failed))
if failed > 0 then os.exit(1) end
