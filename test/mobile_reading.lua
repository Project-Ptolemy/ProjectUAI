-- Narrow transcript spacing and keyboard-aware nested scroll regions.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Mobile reading")
local check, case = suite.check, suite.case

case("narrow source blocks preserve Copy and use the available keyboard space", function()
	local f = F.ui(320, 568)
	f.h.services.UserInputService.TouchEnabled = true
	f.h.services.UserInputService.MouseEnabled = false
	local responsive = f.env.require("ui/responsive"); responsive.init(f.env.root)
	local message = f.env.require("ui/chat/message")
	local code = message.codeBlock(f.host, { text = string.rep("print('test')\n", 40), lang = "lua",
		meta = string.rep("long metadata ", 20) })
	f.h.settle(0.2)
	local bar, copy = code:FindFirstChild("Bar"), f.h.byName("Copy", code)
	check("Copy retains a full touch target", copy.AbsoluteSize.Y >= 44)
	check("long metadata yields space to source actions", not bar:FindFirstChild("Meta").Visible)
	check("narrow code gains usable width", bar:FindFirstChildOfClass("UIPadding").PaddingLeft.Offset <= 8)
	local body = code:FindFirstChild("CodeScroll")
	local tall = body.Size.Y.Offset
	responsive.keyboardHeight = 350
	responsive.changed:fire("keyboard")
	check("keyboard reduces nested code height", body.Size.Y.Offset < tall and body.Size.Y.Offset > 40)
	local thought = message.reasoning(f.host, string.rep("Thinking details. ", 150))
	local viewport = f.h.byName("ThoughtViewport", thought.root)
	check("nested reasoning leaves room for text", viewport.Position.X.Offset <= 12)
	local header = f.h.byName("ReasoningHeader", thought.root)
	check("reasoning still has a complete tap target", header.Size.Y.Offset >= 44)
	f.healthy(); f.close()
end)

case("tables contract above the keyboard without discarding their rows", function()
	local f = F.ui(390, 844)
	f.h.services.UserInputService.TouchEnabled = true; f.h.services.UserInputService.MouseEnabled = false
	local responsive = f.env.require("ui/responsive"); responsive.init(f.env.root)
	local rows = {}; for i = 1, 30 do rows[i] = { "Item " .. i, "Full row text" } end
	local root = f.env.require("ui/chat/table").render(f.host, { block = { header = { "Name", "Value" }, rows = rows } })
	f.h.settle(0.2)
	local scroll = root:FindFirstChild("TableViewport")
	local tall, canvas = scroll.Size.Y.Offset, scroll.CanvasSize.Y.Offset
	responsive.keyboardHeight = 650; responsive.changed:fire("keyboard"); f.h.settle(0.2)
	check("table fits reduced reading space", scroll.Size.Y.Offset < tall)
	check("full table remains scrollable", scroll.CanvasSize.Y.Offset == canvas and scroll.ScrollingEnabled)
	responsive.keyboardHeight = 0; responsive.changed:fire("keyboard"); f.h.settle(0.2)
	check("dismissal restores table height", scroll.Size.Y.Offset == tall)
	f.healthy(); f.close()
end)

suite.finish()
