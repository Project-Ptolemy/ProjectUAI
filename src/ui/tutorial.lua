-- First-run introduction and the profile menu's repeatable Tutorial.
-- The shared overlay owns fitting, focus, dismissal and surface animation.
-- This module owns page content, navigation and deferred first-run display.
return function(env)
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local icons = env.require("ui/icons")

	-- Mark on display, including manual opens, so dismissal is respected.
	local SEEN = "ui.tutorial.seen"

	-- Leave room for the boot indicator before offering the introduction.
	local OPEN_DELAY = 1.2

	-- UTF-8 middle dot, shared with the release-note list style.
	local MARKER = "\194\183"

	-- Follow the same density and device scale as the surrounding controls.
	local TILE = theme.size.control
	local MARK_SIZE = theme.size.iconLarge

	-- Actions navigate to existing panels/dialogs without submitting work.
	local PAGES = {
		{
			icon = "brand",
			title = "Welcome to Project UAI",
			body = "Ask questions, explore this place, or build a script. UAI connects "
				.. "a model to tools inside Roblox.",
			items = {
				"Choose a provider in the Providers library before your first message. Project UAI Free is an optional preset; HCNSEC uses your own API key.",
				"Try: Explain what is in this place before making any changes.",
				"Your messages and relevant tool results are sent to your selected provider.",
			},
			action = { label = "Start chatting", value = "chat" },
		},
		{
			icon = "search",
			title = "Find your way around",
			body = "Use the sidebar to move between conversations and tools.",
			items = {
				"Chat holds your conversations. Code is your script workspace.",
				"Cowork connects the browser workspace through a local bridge.",
				"Find a command in the app menu searches panels, settings and conversation titles. Ctrl+K opens it when you are not typing.",
			},
		},
		{
			icon = "sliders",
			title = "Connect a model",
			body = "Open the Providers library and choose a service, local server or custom endpoint.",
			items = {
				"Project UAI Free offers scheduled shared access. The separate HCNSEC preset always requires your personal key.",
				"Fetch the model list from that provider, or enter its exact model ID, then Save.",
				"Choose the provider and model above your message before sending.",
			},
			action = { label = "Open Providers", value = "providers" },
		},
		{
			icon = "check",
			title = "Decide what runs",
			body = "New installs start in Allow everything. Use the chip under the "
				.. "composer to choose how tools get permission.",
			items = {
				"Ask first lets you review changes and code before they run.",
				"Read only limits tools to reads, unless you have saved an explicit tool rule.",
				"Stop cancels further work. Changes already made are not undone.",
			},
		},
		{
			icon = "globe",
			title = "Join the community",
			body = "Provider help, executor quirks and release news live in the Discord.",
			items = {
				"The invite is also in the profile menu; reminders stop once copied.",
			},
			action = { label = "Open Discord invite", value = "discord" },
		},
		{
			icon = "spark",
			title = "Support the project",
			body = "UAI is free to use. Optional donations help keep the project and "
				.. "shared free access running. Thank you for using it.",
			items = {
				"Ko-fi copies a browser link; Robux goes to the donation place.",
			},
			action = { label = "Donation options", value = "donate" },
		},
	}

	local M = {}
	-- The open tour, so the menu entry cannot open a second one over the first.
	local current
	local cancelFirstRun

	-- One page out, the next in, in a single motion: the new page slides a few
	-- pixels from the travel direction while fading in. The old two-phase blink
	-- (out, swap, in) read as a flicker; there is no old page worth showing.
	-- The inner frame translates because the page group itself is a child of the
	-- body's UIListLayout, and a layout owns its children's positions; the inner
	-- frame is a plain child of the group, which owns nothing.
	local function showPage(tour, index, forward)
		if tour.modal.closed or tour.swapping then return end
		if index < 1 or index > #PAGES then return end

		tour.swapping = true
		tour.render(index)
		if tour.modal.closed then return end
		local inner = tour.inner
		inner.Position = UDim2.fromOffset(0, forward and theme.space.sm or -theme.space.sm)
		tour.page.GroupTransparency = 1
		P.animate(tour.page, "enter", { GroupTransparency = 0 })
		P.animate(inner, "enter", { Position = UDim2.fromOffset(0, 0) }, function()
			tour.swapping = false
		end)
	end

	-- Paints the dotted trail: the current step stretches into an accent pill,
	-- the rest stay dimmed dots. Tweened, so the pill glides along the trail
	-- instead of snapping between steps.
	local DOT, PILL = theme.size.dot, theme.size.dot * 3
	local function paintDots(tour)
		for position, dot in ipairs(tour.dots) do
			local active = position == tour.index
			P.animate(dot, "hover", {
				Size = UDim2.fromOffset(active and PILL or DOT, DOT),
				BackgroundColor3 = active and theme.color.accent or theme.color.textDisabled,
			})
		end
	end

	-- Builds the current page inside the group. The body scroll returns to the top
	-- with each page: arriving part-way down a page nobody has read yet reads as a
	-- rendering fault rather than as a position.
	local function render(tour, index)
		local page = PAGES[index]
		local inner = tour.inner
		tour.index = index
		tour.modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
		for _, child in ipairs(inner:GetChildren()) do
			if child:IsA("GuiObject") then child:Destroy() end
		end

		local order = 0
		local function nextOrder()
			order = order + 1
			return order
		end

		-- The page mark and heading: the icon on a soft coral tile, the way a
		-- starter card pairs its accent-hot icon with its label, with a tint
		-- behind it so the page opens on colour rather than on grey prose.
		local head = P.row(inner, {
			name = "TourHead",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			alignY = "Center",
			layoutOrder = nextOrder(),
		})
		local mark = P.frame(head, {
			name = "TourMark",
			size = UDim2.fromOffset(TILE, TILE),
			bg = theme.color.accentSurface,
			radius = theme.radius.sm,
			layoutOrder = 1,
		})
		if page.icon == "brand" then
			icons.brand(mark, MARK_SIZE)
		else
			icons.draw(page.icon, mark, MARK_SIZE, theme.color.accentHot)
		end
		P.text(head, {
			name = "TourTitle",
			text = page.title,
			role = "heading",
			wrap = true,
			auto = "Y",
			size = UDim2.new(1, -(TILE + theme.space.sm), 0, 0),
			layoutOrder = 2,
		})

		if page.body then
			-- The lead stays full-bright while the bullets below dim: the eye
			-- lands on the sentence first, the list second.
			P.text(inner, {
				name = "TourBody",
				text = page.body,
				role = "body",
				wrap = true,
				auto = "Y",
				size = UDim2.new(1, 0, 0, 0),
				layoutOrder = nextOrder(),
			})
		end
		if page.items then
			local role = theme.textRole("small")
			local markerWidth = theme.space.sm
			local list = P.column(inner, {
				name = "TourItems",
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.xs,
				layoutOrder = nextOrder(),
			})
			for index, item in ipairs(page.items) do
				local row = P.row(list, {
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = theme.space.xs,
					alignY = "Top",
					layoutOrder = index,
				})
				P.text(row, {
					name = "Marker",
					text = MARKER,
					role = "small",
					line = role.line,
					color = theme.color.accentHot,
					align = "Right",
					alignY = "Top",
					size = UDim2.new(0, markerWidth, 0, role.height),
					layoutOrder = 1,
				})
				P.text(row, {
					text = item,
					role = "small",
					line = role.line,
					color = theme.color.textSecondary,
					wrap = true,
					auto = "Y",
					alignY = "Top",
					size = UDim2.new(1, -(markerWidth + theme.space.xs), 0, 0),
					layoutOrder = 2,
				})
			end
		end
		if page.action then
			-- Sized to its label, not the card: a full-width slab reads as a
			-- second Next button competing with the footer.
			P.button(inner, {
				name = "TourAction",
				text = page.action.label,
				variant = "secondary",
				size = "sm",
				layoutOrder = nextOrder(),
				onClick = function()
					-- Close first: the invitation and the donation dialog are
					-- modals of their own, and two live scrims on one screen is
					-- how a dialog ends up dismissed by a click at its edge.
					tour.modal.close()
					if page.action.value == "chat" or page.action.value == "providers" then
						env.require("ui/app").show(page.action.value)
					elseif page.action.value == "discord" then
						env.require("ui/community").open()
					elseif page.action.value == "donate" then
						-- Required here rather than at the top of the file: app
						-- requires this module from its mount, and a load-time
						-- cycle between the two would be a load error.
						env.require("ui/app").donate()
					end
				end,
			})
		end

		paintDots(tour)
		tour.step.Text = string.format("Step %d of %d", index, #PAGES)
		tour.back.setEnabled(index > 1)
		tour.next.setText(index == #PAGES and "Finish" or "Next")
	end

	function M.seen()
		return config.get(SEEN, false) == true
	end

	function M.markSeen()
		-- Menu-driven opens call this too. Skipping the write when the flag is
		-- already set keeps a repeat visit from dirtying the settings and
		-- scheduling a persist for nothing.
		if M.seen() then return end
		config.set(SEEN, true)
	end

	-- Returns the open tour, or a new one. The pages always start at the first:
	-- the tour is a walkthrough, and a menu entry that resumed in the middle would
	-- have nothing to say about where the middle is.
	function M.open()
		if current and not current.modal.closed then return current end

		-- No fixed height: the card fits each page. Reserving the tallest page's
		-- height left short pages floating in an empty card.
		local modal = overlay.modal({
			title = "Getting started",
			description = "Six short steps. Close any time and reopen from your profile menu.",
			width = theme.size.modalWide,
			onClose = function() current = nil end,
		})
		if not modal then return nil end

		-- Shown once is the whole promise of the first-run gate, so the flag is set
		-- when the tour appears rather than when it is finished: a user who reads
		-- one page and closes it has been told what the client is.
		M.markSeen()

		local page = P.group(modal.content, {
			name = "TourPage",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			layoutOrder = 1,
		})
		local inner = P.column(page, {
			name = "TourPageInner",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.md,
		})

		local tour = { modal = modal, page = page, inner = inner, index = 0, swapping = false, dots = {} }
		tour.render = function(index) render(tour, index) end

		-- Sized for the widest state: one pill plus the rest dots. The layout
		-- reflows inside it as the pill moves.
		local progress = P.column(modal.footer, {
			name = "TourProgress",
			size = UDim2.fromOffset(PILL + (#PAGES - 1) * (DOT + theme.space.xs), 0),
			auto = "Y",
			gap = theme.space.xs,
			layoutOrder = 1,
		})
		local dots = P.row(progress, {
			name = "TourDots",
			size = UDim2.new(0, PILL + (#PAGES - 1) * (DOT + theme.space.xs), 0, DOT),
			gap = theme.space.xs,
			layoutOrder = 1,
		})
		for position = 1, #PAGES do
			local dot = P.frame(dots, {
				name = "TourDot",
				size = UDim2.fromOffset(position == 1 and PILL or DOT, DOT),
				bg = position == 1 and theme.color.accent or theme.color.textDisabled,
				layoutOrder = position,
			})
			P.corner(dot, theme.radius.pill)
			tour.dots[position] = dot
		end

		tour.step = P.text(progress, {
			name = "TourStep",
			text = "",
			role = "caption",
			color = theme.color.textSecondary,
			auto = "X",
			layoutOrder = 2,
		})
		tour.back = P.button(modal.footer, {
			name = "TourBack",
			text = "Back",
			variant = "ghost",
			size = "sm",
			layoutOrder = 3,
			onClick = function() showPage(tour, tour.index - 1, false) end,
		})
		tour.next = P.button(modal.footer, {
			name = "TourNext",
			text = "Next",
			variant = "primary",
			size = "sm",
			layoutOrder = 4,
			onClick = function()
				if tour.index >= #PAGES then
					modal.close()
				else
					showPage(tour, tour.index + 1, true)
				end
			end,
		})

		current = tour
		render(tour, 1)
		return tour
	end

	-- The once-per-install open, scheduled by ui/app's mount. Returns its
	-- canceller, so a client that unloads during the delay does not get a tour
	-- over nothing.
	function M.firstRun(app)
		if cancelFirstRun then cancelFirstRun() end
		if M.seen() or not app or not app.screen then return function() end end
		local alive, pending, destroyed = true, nil, nil
		local function cancel()
			alive = false
			if pending then pcall(task.cancel, pending); pending = nil end
			if destroyed then destroyed:Disconnect(); destroyed = nil end
			if cancelFirstRun == cancel then cancelFirstRun = nil end
		end
		local attempt
		attempt = function()
			pending = nil
			if not alive then return end
			if M.seen() or not app.screen.Parent then cancel(); return end
			local ok, focused = pcall(function() return env.uis:GetFocusedTextBox() end)
			local sessions = env.require("agent/session")
			-- Defer while the user is working; never replace a form, interrupt a
			-- request, or consume the first-run gate behind a hidden window.
			if app.screen.Enabled == false or not app.window or not app.window.visible
				or #overlay.open > 0 or not ok or focused or sessions.busyCount() > 0 then
				pending = clock.delay(OPEN_DELAY, attempt)
				return
			end
			cancel()
			M.open()
		end
		cancelFirstRun = cancel
		destroyed = app.screen.Destroying:Connect(cancel)
		pending = clock.delay(OPEN_DELAY, attempt)
		return cancel
	end

	return M
end
