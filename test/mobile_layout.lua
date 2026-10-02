-- Real Settings layout choices preserve shared controls and separate placements.
-- Run: luajit test/mobile_layout.lua [bundle]
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local envMock = require("env")
local newSignal = require("instance").newSignal
local passed = 0

local function check(label, value)
	assert(value, label)
	passed = passed + 1
end

local h = envMock.new()
local uis = h.services.UserInputService
uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, false, false
h.setViewport(390, 844)
local app = assert(h.boot(arg[1] or "dist/uai.lua"))
h.settle(1)
app.app.show("chat")
local window, composer = app.app.window, app.app.chatPanel.composer
local responsive, theme = app.env.require("ui/responsive"), app.env.require("ui/theme")
local function geometry()
	return table.concat({ window.root.Position.X.Offset, window.root.Position.Y.Offset,
		window.root.Size.X.Offset, window.root.Size.Y.Offset }, ":")
end
local original, desktop = geometry(), h.json.encode(app.config.get("ui.window"))
composer.field.set("Keep this layout draft")
local field = composer.field.instance
local dialog = app.app.showSettingsDialog("general")
local function choose(mode)
	local selector = assert(h.byName("Segment_sheet", dialog.card)).Parent
	h.click(assert(h.byName("Segment_" .. mode, selector)))
	h.settle(0.3)
	check("the real layout setting selects " .. mode, app.config.get("ui.layout") == mode)
	check("layout selection keeps the existing window and native draft", app.app.window == window
		and app.app.chatPanel.composer.field.instance == field and composer.field.get() == "Keep this layout draft")
end
choose("sheet")
local sheetWidth, sheetHeight = window.root.Size.X.Offset, window.root.Size.Y.Offset
local bounds = responsive.usableRect(window.root.Parent, theme.space.sm, false)
check("Sheet uses the available width at the bottom", math.abs(sheetWidth - bounds.width) <= 1
	and math.abs(window.root.Position.Y.Offset + sheetHeight - bounds.y - bounds.height) <= 1)
choose("panel")
check("Panel is narrower and taller than Sheet", window.root.Size.X.Offset < sheetWidth and window.root.Size.Y.Offset > sheetHeight)
check("Panel is placed against the right edge", math.abs(window.root.Position.X.Offset + window.root.Size.X.Offset - bounds.x - bounds.width) <= 1)
choose("window")
check("Window is the compact centred rectangle", window.root.Size.Y.Offset < sheetHeight
	and math.abs(window.root.Position.X.Offset + window.root.Size.X.Offset / 2 - bounds.x - bounds.width / 2) <= 1
	and math.abs(window.root.Position.Y.Offset + window.root.Size.Y.Offset / 2 - bounds.y - bounds.height / 2) <= 1)
dialog.close()

-- A touch drag retains the same initiating InputObject through release.
local E, V = h.sandbox.Enum, h.dt.Vector3
local origin, headerSize = window.header.AbsolutePosition, window.header.AbsoluteSize
local input = { UserInputType = E.UserInputType.Touch, UserInputState = E.UserInputState.Begin,
	Position = V.new(origin.X + math.min(96, headerSize.X * 0.4), origin.Y + math.min(20, headerSize.Y * 0.5), 0),
	Changed = newSignal("layout drag") }
window.header.InputBegan:Fire(input)
input.Position = V.new(input.Position.X - 30, input.Position.Y - 45, 0)
uis.InputChanged:Fire(input)
input.UserInputState = E.UserInputState.End
input.Changed:Fire()
uis.InputEnded:Fire(input)
local chosen = geometry()
check("explicit handheld Window has its own saved placement", app.config.get("ui.mobileSheet.layouts.window.placed") == true)
dialog = app.app.showSettingsDialog("general")
choose("sheet")
choose("window")
check("returning to Window restores its saved placement", geometry() == chosen)
choose("auto")
check("Auto restores the original compact placement", geometry() == original)
check("mobile layout choices leave desktop geometry alone", h.json.encode(app.config.get("ui.window")) == desktop)
dialog.close()
check("no asynchronous UI errors", #h.errors() == 0)
check("valid GUI property types: " .. tostring(h.instanceState.typeErrors[1] or "none"), #h.instanceState.typeErrors == 0)
app.unload()
print("Mobile layouts: " .. passed .. " assertions passed")
