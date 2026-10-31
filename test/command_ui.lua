-- Command navigation preserves drafts, honors selection and releases listeners.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Command UI")
local check, case = suite.check, suite.case

case("keyboard selects a result and opens the real destination", function()
	local f = F.ui(900, 650)
	local destination
	local app = { show = function(id) destination = id end }
	local modal = f.env.require("ui/commands").open(app, "Open")
	f.h.settle(0.2)
	local field = assert(f.h.byName("CommandSearch")):FindFirstChildWhichIsA("TextBox")
	check("search receives native focus", f.env.uis:GetFocusedTextBox() == field)
	f.h.press("Down")
	field:ReleaseFocus(true)
	f.h.settle(0.4)
	check("second destination opens", destination == "code" and modal.closed)
	f.h.press("Down")
	check("closed command search leaves no results", f.h.byName("CommandResults") == nil)
	f.healthy(); f.close()
end)

case("settings and conversations are searchable and empty search is harmless", function()
	local f = F.ui(430, 620)
	local sessions = f.env.require("agent/session")
	local chat = assert(sessions.newThread({ title = "A saved task", activate = false }))
	local destination
	local app = { showSettingsDialog = function(id) destination = id end,
		openSession = function(id) destination = id end }
	local commands = f.env.require("ui/commands")
	local modal = commands.open(app, "Obsidian")
	f.h.settle(0.2)
	f.h.click(assert(f.h.byName("Command_setting_obsidian")))
	check("vault settings open", destination == "obsidian" and modal.closed)
	modal = commands.open(app, "A saved task")
	f.h.click(assert(f.h.byName("Command_conversation_" .. chat.id)))
	check("saved conversation opens by identity", destination == chat.id and modal.closed)
	modal = commands.open(app, "no-match-whatsoever")
	f.h.settle(0.2)
	local field = assert(f.h.byName("CommandSearch")):FindFirstChildWhichIsA("TextBox")
	f.h.press("Down"); field:ReleaseFocus(true)
	check("empty Enter does not close or navigate", not modal.closed and destination == chat.id)
	modal.close(); f.h.settle(0.3)
	f.healthy(); f.close()
end)

suite.finish()
