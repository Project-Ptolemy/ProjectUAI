-- The intro tour: interruption guards, owned lifetime, navigation and hand-offs.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Intro tutorial")
local check, case = suite.check, suite.case

case("new users choose a provider and HCNSEC stays a personal-key route", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local tour = tutorial.open()
	local text = f.h.textOf(assert(f.h.byName("TourPage")))
	check("welcome explains optional provider choice", text:find("optional preset", 1, true) and text:find("own API key", 1, true))
	f.h.click(f.h.byName("TourNext")); f.h.click(f.h.byName("TourNext"))
	text = f.h.textOf(assert(f.h.byName("TourPage")))
	check("model page explains separate HCNSEC", text:find("separate HCNSEC", 1, true) and not text:find("Keep the included", 1, true))
	tour.modal.close(); f.h.settle(0.3)
	f.healthy(); f.close()
end)

case("the first-run gate waits for a visible window and fires once", function()
	local f = F.ui(900, 650)
	local config = f.env.require("runtime/config")
	local tutorial = f.env.require("ui/tutorial")
	check("a fresh install has not seen the tour", not tutorial.seen())

	-- The window is what the tour belongs to: a client whose interface is mounted
	-- but hidden is one nobody asked to interrupt, and the gate has to survive it.
	local app = { screen = f.env.root, window = { visible = false } }
	tutorial.firstRun(app)
	f.h.sched.advance(3)
	check("a hidden window is left alone", f.h.byName("TourPage") == nil)
	check("and the gate stays unset", not tutorial.seen())

	app.window.visible = true
	f.h.sched.advance(3)
	check("restoring the same window offers the waiting tour", f.h.byName("TourPage") ~= nil)
	check("and the gate is set", tutorial.seen() and config.get("ui.tutorial.seen") == true)
	check("opening again returns the tour already on screen", tutorial.open() ~= nil
		and #f.h.allByName("TourPage") == 1 and f.h.byName("TourTitle").Text == "Welcome to Project UAI")

	-- A closed tour plus a cancelled schedule leaves the screen alone.
	f.env.require("ui/overlay").closeAll()
	f.h.settle(0.3)
	config.set("ui.tutorial.seen", false)
	local cancel = tutorial.firstRun(app)
	cancel()
	f.h.sched.advance(3)
	check("cancelling before the beat elapses opens nothing", f.h.byName("TourPage") == nil and not tutorial.seen())
	f.healthy(); f.close()
end)

case("the first run waits for dialogs, focused input and active work", function()
	local f = F.ui(900, 650)
	local tutorial, overlay = f.env.require("ui/tutorial"), f.env.require("ui/overlay")
	local app = { screen = f.env.root, window = { visible = true } }
	app.screen.Enabled = false
	local cancel = tutorial.firstRun(app)
	local function absent(label)
		f.h.sched.advance(3)
		check(label, f.h.byName("TourPage") == nil and not tutorial.seen())
	end
	absent("a disabled screen cannot consume first run")
	local other = overlay.modal({ title = "Unfinished provider setup" })
	app.screen.Enabled = true
	absent("an existing dialog is not covered")
	other.close()
	local input = f.h.Instance.new("TextBox", f.host)
	input:CaptureFocus()
	absent("typing is not interrupted")
	check("the draft keeps native focus", input:IsFocused())
	input:ReleaseFocus(false)
	local sessions = f.env.require("agent/session")
	local busyCount = sessions.busyCount
	sessions.busyCount = function() return 1 end
	absent("an active request is not interrupted")
	sessions.busyCount = busyCount
	f.h.sched.advance(3)
	check("the waiting tour opens when the blockers clear", f.h.byName("TourPage") ~= nil and tutorial.seen())
	cancel(); cancel()
	overlay.closeAll(); f.h.settle(0.3)
	f.healthy(); f.close()
end)

case("manual dismissal consumes an already scheduled first run", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local app = { screen = f.env.root, window = { visible = true } }
	local cancel = tutorial.firstRun(app)
	tutorial.firstRun(app)
	local tour = tutorial.open()
	tour.modal.close()
	f.h.sched.advance(4)
	check("pending first-run work cannot reopen a dismissed manual tour", f.h.byName("TourPage") == nil and tutorial.seen())
	cancel(); cancel()
	local again = tutorial.open()
	f.h.sched.advance(4)
	check("a later manual visit remains available", not again.modal.closed and #f.h.allByName("TourPage") == 1)
	again.modal.close(); f.h.settle(0.3)
	f.healthy(); f.close()
end)

case("cancellation remains effective when the host cannot cancel a queued task", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local cancel = tutorial.firstRun({ screen = f.env.root, window = { visible = true } })
	local nativeCancel = f.h.sandbox.task.cancel
	f.h.sandbox.task.cancel = function() end
	cancel(); cancel()
	f.h.sandbox.task.cancel = nativeCancel
	f.h.sched.advance(4)
	check("the queued callback observes its released owner", f.h.byName("TourPage") == nil and not tutorial.seen())
	f.healthy(); f.close()
end)

case("destroying the screen releases the pending first run", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local root = f.env.root
	tutorial.firstRun({ screen = root, window = { visible = false } })
	root:Destroy()
	f.h.sched.advance(4)
	check("no tour is recorded for a destroyed window", not tutorial.seen())
	check("destruction cannot remount the interface", f.h.screen() == nil)
	f.healthy(); f.close()
end)

case("pages step with Back and Next and the scrim dismisses the tour", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local tour = tutorial.open()
	check("the tour opens on the first page", f.h.byName("TourTitle").Text == "Welcome to Project UAI")
	check("the step names the place", f.h.byName("TourStep").Text == "Step 1 of 6")
	check("Back is off on the first page", not f.h.byName("TourBack").Active)

	f.h.click(f.h.byName("TourNext"))
	check("Next advances the page", f.h.byName("TourTitle").Text == "Find your way around"
		and f.h.byName("TourStep").Text == "Step 2 of 6")
	check("and only one page exists at a time", #f.h.allByName("TourTitle") == 1)
	check("Back turns on", f.h.byName("TourBack").Active)
	check("opening an existing tour preserves its page", tutorial.open() == tour
		and f.h.byName("TourStep").Text == "Step 2 of 6")

	local theme = f.env.require("ui/theme")
	local function accentedDot()
		local found = nil
		for _, dot in ipairs(f.h.allByName("TourDot")) do
			if dot.BackgroundColor3 == theme.color.accent then
				if found then return "too many" end
				found = dot
			end
		end
		return found
	end
	check("six dots trail the steps", #f.h.allByName("TourDot") == 6)
	local first = accentedDot()
	check("exactly one step is lit", first ~= nil and first ~= "too many")

	tour.modal.scroll.instance.CanvasPosition = f.h.sandbox.Vector2.new(0, 80)
	f.h.click(f.h.byName("TourBack"))
	check("Back returns to the page before it", f.h.byName("TourTitle").Text == "Welcome to Project UAI"
		and not f.h.byName("TourBack").Active)
	check("the previous page starts at the top", tour.modal.scroll.instance.CanvasPosition.Y == 0)
	local back = accentedDot()
	check("and the lit step follows it back", back ~= nil and back ~= "too many" and back ~= first)

	f.h.click(f.h.byName("Dismiss", tour.modal.scrim))
	check("clicking the scrim dismisses it", f.h.byName("TourPage") == nil)
	local again = tutorial.open()
	check("and reopening starts at the first page", again ~= tour
		and f.h.byName("TourTitle").Text == "Welcome to Project UAI" and f.h.byName("TourStep").Text == "Step 1 of 6")
	again.modal.close(); f.h.settle(0.3)
	f.healthy(); f.close()
end)

case("closing during page motion cannot retire a replacement tour", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local tour = tutorial.open()
	f.h.settle(0.3)
	f.h.byName("TourNext").Activated:Fire()
	tour.modal.close()
	local again = tutorial.open()
	f.h.settle(1)
	check("old motion cannot close the replacement", not again.modal.closed and #f.h.allByName("TourPage") == 1)
	check("the replacement still owns the singleton", tutorial.open() == again)
	f.h.click(f.h.byName("TourNext"))
	check("its navigation remains live", f.h.byName("TourStep").Text == "Step 2 of 6")
	for _ = 1, 4 do f.h.click(f.h.byName("TourNext")) end
	f.h.click(f.h.byName("TourNext"))
	check("Finish closes and unregisters the completed tour", f.h.byName("TourPage") == nil
		and #f.env.require("ui/overlay").open == 0)
	f.healthy(); f.close()
end)

case("touch navigation retains adaptive sizing and working page controls", function()
	local f = F.ui(320, 568)
	f.env.uis.TouchEnabled, f.env.uis.MouseEnabled = true, false
	local responsive = f.env.require("ui/responsive")
	responsive.init(f.env.root)
	local tutorial = f.env.require("ui/tutorial")
	for _, size in ipairs({ { 320, 568 }, { 844, 390 } }) do
		f.h.setViewport(size[1], size[2])
		local tour = tutorial.open()
		f.h.settle(0.6)
		for index = 1, 6 do
			local card = tour.modal.card
			local scroll = tour.modal.scroll.instance
			check("navigation can wrap on page " .. index,
				tour.modal.footer:FindFirstChildOfClass("UIListLayout").Wraps == true)
			check("the scroll viewport stays within the explicit card bounds on page " .. index,
				scroll.AbsolutePosition.Y >= card.AbsolutePosition.Y
				and scroll.AbsoluteSize.Y >= 0
				and scroll.AbsolutePosition.Y + scroll.AbsoluteSize.Y <= card.AbsolutePosition.Y + card.AbsoluteSize.Y + 1)
			-- The mock resolves explicit sizes, but does not run AutomaticSize or
			-- UIListLayout. Check their sizing contracts, not invented hit geometry.
			for _, name in ipairs({ "TourBack", "TourNext" }) do
				local button = f.h.byName(name)
				check(name .. " keeps its configured touch height on page " .. index,
					button.Size.Y.Offset >= responsive.minTarget())
				check(name .. " sizes its width to its label on page " .. index,
					button.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.X and f.h.textOf(button) ~= "")
			end
			check("the expected touch page is active", tour.index == index)
			f.h.click(f.h.byName("TourNext"))
		end
		check("Finish closes the tour after every touch page", tour.modal.closed)
	end
	f.healthy(); f.close()
end)

case("chat and provider actions navigate after releasing the tour", function()
	local f = F.ui(900, 650)
	local tutorial, overlay = f.env.require("ui/tutorial"), f.env.require("ui/overlay")
	local destination, released
	f.loaded["ui/app"] = { show = function(panel)
		destination, released = panel, #overlay.open == 0
	end }
	tutorial.open()
	f.h.click(f.h.byName("TourAction"))
	check("Start chatting opens Chat after closing the tour", destination == "chat" and released)
	tutorial.open()
	for _ = 1, 2 do f.h.click(f.h.byName("TourNext")) end
	f.h.click(f.h.byName("TourAction"))
	check("Open Providers reaches setup after closing the tour", destination == "providers" and released)
	f.h.settle(0.3)
	check("navigation leaves no tutorial controls behind", f.h.byName("TourPage") == nil)
	f.healthy(); f.close()
end)

case("the Discord and support pages hand off to the existing dialogs", function()
	local f = F.ui(900, 650)
	local tutorial = f.env.require("ui/tutorial")
	local tour = tutorial.open()
	for _ = 1, 4 do f.h.click(f.h.byName("TourNext")) end
	check("the community page is reached", f.h.byName("TourTitle").Text == "Join the community")
	f.h.click(f.h.byName("TourAction"))
	check("its action opens the existing invitation", f.h.byName("CommunityInvite") ~= nil)
	check("the tour stepped aside rather than stacking", f.h.byName("TourPage") == nil)
	f.env.require("ui/community").open().close(); f.h.settle(0.3)

	-- The donation dialog lives in ui/app, which requires this module; the page
	-- has to reach it lazily, and this is the seam that says so.
	local donated = false
	f.loaded["ui/app"] = { donate = function() donated = true end }
	tour = tutorial.open()
	for _ = 1, 5 do f.h.click(f.h.byName("TourNext")) end
	check("the support page is reached", f.h.byName("TourTitle").Text == "Support the project")
	check("where the forward action becomes Finish", f.h.textOf(f.h.byName("TourNext")) == "Finish")
	f.h.click(f.h.byName("TourAction"))
	check("its action asks the app for the donation dialog", donated and f.h.byName("TourPage") == nil)
	f.loaded["ui/app"] = nil
	f.healthy(); f.close()
end)

suite.finish()
