-- Invitation cadence and interruption guards, with no external requests.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Community invitation")
local check, case = suite.check, suite.case
local DAY = 86400000

case("dismissal survives reload and opt-out leaves manual access available", function()
	local f = F.ui(320, 568)
	local clock, config = f.env.require("runtime/clock"), f.env.require("runtime/config")
	local now = 1800000000000
	clock.ms = function() return now end
	local policy = f.env.require("runtime/community")
	check("new install is eligible", policy.due())
	policy.markShown()
	check("shown once per client", not policy.due())
	now = now + 30 * DAY
	check("long sessions still show once", not policy.due())
	f.loaded["runtime/community"] = nil
	policy = f.env.require("runtime/community")
	now = now - 29 * DAY
	check("saved cooldown carries across reload", not policy.due())
	now = now + 13 * DAY
	check("two-week cooldown expires", policy.due())
	policy.disable()
	check("opt-out suppresses reminders", not policy.due())
	local modal = f.env.require("ui/community").open()
	check("manual menu access still works", modal and not modal.closed)
	f.h.click(f.h.byName("CommunityNever", modal.card))
	check("opt-out closes the dialog and persists", modal.closed and config.get("ui.communityInvite.disabled") == true)
	f.healthy(); f.close()
end)

case("copy failure keeps the selectable invite and successful copy stops reminders", function()
	local f = F.ui(320, 568)
	local caps = f.env.require("runtime/caps")
	local modal = f.env.require("ui/community").open()
	caps.fn.clipboard = function() return false end
	f.h.click(f.h.byName("CommunityCopy", modal.card))
	check("failed clipboard keeps the modal open", not modal.closed)
	local invite = f.h.byName("CommunityInvite", modal.card):FindFirstChildOfClass("TextBox")
	check("manual copy fallback retains the full invite", invite.Text == "https://discord.gg/9xYyyYuKap" and invite.TextEditable == false)
	local copied
	caps.fn.clipboard = function(value) copied = value end
	f.h.click(f.h.byName("CommunityCopy", modal.card))
	check("copy uses the invite and disables reminders", copied == invite.Text and modal.closed
		and f.env.require("runtime/config").get("ui.communityInvite.disabled") == true)
	f.healthy(); f.close()
end)

case("reminders wait for idle visible chat without taking focus or interrupting work", function()
	local f = F.ui(390, 844)
	local clock = f.env.require("runtime/clock")
	local now, draft, busy, focused = 1800000000000, false, false, nil
	clock.ms = function() return now end
	f.loaded["ui/chat/composer"] = { hasDrafts = function() return draft end }
	f.env.require("agent/session").busyCount = function() return busy and 1 or 0 end
	f.h.services.UserInputService.GetFocusedTextBox = function() return focused end
	local app = { screen = f.env.root, window = { visible = true }, panel = "chat",
		chatPanel = { view = { pinned = true } } }
	local ui = f.env.require("ui/community")
	local stop = ui.watch(app)
	local function tick(seconds)
		now = now + seconds * 1000; f.h.sched.advance(30)
	end
	local function absent(label) check(label, f.h.byName("CommunityInvite") == nil) end
	tick(299); absent("no startup interruption")
	f.h.services.UserInputService.InputBegan:Fire({})
	tick(10); absent("recent input delays the invitation")
	app.window.visible = false; tick(31); absent("minimized window stays quiet")
	app.window.visible = true; app.panel = "code"; tick(31); absent("Code work stays uninterrupted")
	app.panel = "chat"; busy = true; tick(31); absent("requests stay uninterrupted")
	busy = false; now = now + 30000
	f.env.require("agent/session").listChanged:fire()
	tick(1); absent("a just-finished request gets a new idle pause")
	f.h.services.UserInputService.WindowFocusReleased:Fire()
	tick(31); absent("unfocused Roblox stays quiet")
	f.h.services.UserInputService.WindowFocused:Fire()
	tick(1); absent("returning to Roblox starts a new idle pause")
	busy = false; draft = true; tick(31); absent("drafts stay uninterrupted")
	draft = false; focused = {}; tick(31); absent("focused fields stay uninterrupted")
	focused = nil; app.chatPanel.view.pinned = false; tick(31); absent("history reading stays uninterrupted")
	app.chatPanel.view.pinned = true
	local other = f.env.require("ui/overlay").modal({ title = "Existing dialog" })
	tick(31); absent("other dialogs stay uninterrupted")
	other.close(); f.h.settle(0.3)
	tick(31)
	check("idle invitation finally appears", f.h.byName("CommunityInvite") ~= nil)
	local modal = ui.open()
	f.h.click(f.h.byName("CommunityLater", modal.card)); f.h.settle(0.3)
	tick(15 * DAY / 1000); absent("Not now cannot repeat in the same session")
	stop(); stop(); f.healthy(); f.close()
end)

case("watch cleanup releases listeners and prevents future invitations", function()
	local f = F.ui(390, 844)
	local clock = f.env.require("runtime/clock")
	local now = 1800000000000; clock.ms = function() return now end
	local input = f.h.services.UserInputService.InputBegan
	local before = input:Count()
	local stop = f.env.require("ui/community").watch({ screen = f.env.root, window = { visible = true }, panel = "chat" })
	stop(); now = now + DAY; f.h.sched.advance(60)
	check("no invitation after destruction", f.h.byName("CommunityInvite") == nil)
	check("watch destruction releases input listeners", input:Count() == before)
	f.healthy(); f.close()
end)

suite.finish()
