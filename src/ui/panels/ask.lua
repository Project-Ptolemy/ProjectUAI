-- The question prompt.
--
-- ask_user raises one of these: the model has met a fork it cannot resolve from the
-- world and the turn is parked on a thread until it is answered. Same contract as the
-- permission prompt -- one at a time, queued, always resolved, closing counts as
-- dismissed -- because the failure mode is the same too: an unresolved question parks
-- the agent until its own timeout.
--
-- It listens to every conversation rather than the open one, for the same reason the
-- permission prompt does: a second conversation left running in the background can
-- ask into a stream nobody is subscribed to, and a question nobody can see is ten
-- minutes of a turn spent for nothing.
return function(env)
	local util = env.require("runtime/util")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")

	local M = { queue = {}, showing = false }
	local transitions, draining = 0, false
	local present, drain

	local function settle(request, text, resolve)
		if not request or request.settled then return false end
		transitions = transitions + 1
		request.settled = true
		local presentation, unsubscribe, handler = request.presentation, request.unsubscribeSettled, request.resolve
		request.presentation, request.unsubscribeSettled, request.resolve = nil, nil, nil
		if M.current == request then M.current, M.showing = nil, false end
		for index = #M.queue, 1, -1 do if M.queue[index] == request then table.remove(M.queue, index) end end
		-- The producer can settle synchronously and emit a new question in resolve.
		-- Release this request before either callback can reenter the presentation.
		if type(unsubscribe) == "function" then pcall(unsubscribe) end
		if resolve and type(handler) == "function" then pcall(handler, text) end
		if presentation and presentation.modal then pcall(presentation.modal.close) end
		transitions = transitions - 1
		if drain then drain() end
		return true
	end

	local function buildPresentation(request, presentation)
		local function reply(text)
			return settle(request, text, true)
		end
		request.answer = reply
		request.close = function() return reply("") end

		local options = {}
		for _, value in ipairs(type(request.options) == "table" and request.options or {}) do
			local clean = util.trim(tostring(value))
			if clean ~= "" and #options < 4 then options[#options + 1] = clean end
		end
		local modal = overlay.modal({
			title = "The agent is asking",
			description = tostring(request.question or ""),
			width = theme.size.modalWide,
			dismissable = true,
			-- Dismissed rather than cancelled: a question is not a permission, and the
			-- difference between "no" and "never mind" is one the model cannot act on.
			-- The tool result says the question was dismissed, which is a fact the
			-- next turn can work with.
			onClose = function() reply("") end,
		})
		presentation.modal = modal
		if not modal or request.settled then return end

		-- Which conversation is asking, for the same reason the permission prompt
		-- states it: with one queue serving every open conversation, a question on its
		-- own does not say whose turn it belongs to.
		if request.sessionTitle then
			P.text(modal.content, {
				name = "AskingIn",
				text = "in " .. tostring(request.sessionTitle),
				role = "caption",
				color = theme.color.textTertiary,
				wrap = true,
				auto = "Y",
				layoutOrder = 1,
			}).Size = UDim2.new(1, 0, 0, 0)
		end
		-- The concrete options, each a full-width row rather than a menu item: a menu
		-- hides every answer but the one on top, and a choice the reader has to scroll
		-- to discover is a choice they did not know they had.
		for index, option in ipairs(options) do
			local choice = P.rowButton(modal.content, {
				name = "AskOption" .. tostring(index),
				vertical = true,
				size = UDim2.new(1, 0, 0, math.max(theme.size.control, responsive.minTarget())),
				auto = "Y",
				bg = theme.color.surfaceRaised,
				stroke = true,
				radius = theme.radius.md,
				padding = { x = theme.space.md, y = theme.space.sm },
				layoutOrder = index + 1,
				onClick = function() reply(option) end,
			})
			P.text(choice.row, { name = "Label", text = option, role = "small",
				size = UDim2.new(1, 0, 0, 0), auto = "Y", wrap = true, layoutOrder = 1 })
		end

		-- The open answer. Always offered -- an option list is the model's guess at
		-- the answers worth having, and the real answer is allowed to be none of them.
		local field
		field = P.field(modal.content, {
			name = "AskField",
			placeholder = #options > 0 and "Or type your own answer" or "Type your answer",
			layoutOrder = #options + 2,
			onSubmit = function(text) reply(util.trim(text)) end,
		})
		P.button(modal.footer, {
			name = "AskDismiss",
			text = "Dismiss",
			variant = "ghost",
			size = "sm",
			layoutOrder = 1,
			onClick = function() reply("") end,
		})
		P.button(modal.footer, {
			name = "AskSend",
			text = "Send",
			variant = "primary",
			size = "sm",
			layoutOrder = 2,
			onClick = function() reply(util.trim(field.get())) end,
		})
	end

	present = function(request)
		if request.settled then return end
		transitions = transitions + 1
		local presentation = {}
		request.presentation = presentation
		M.current, M.showing = request, true
		local ok = pcall(buildPresentation, request, presentation)
		transitions = transitions - 1
		if request.settled then
			if presentation.modal then pcall(presentation.modal.close) end
		elseif not ok or not presentation.modal then
			settle(request, "", true)
		end
	end
	drain = function()
		if transitions > 0 or draining or M.showing then return end
		draining = true
		-- Settled queued requests never get a modal. A failed presentation can also
		-- dismiss and move on without recursing through the rest of the queue.
		while not M.showing and #M.queue > 0 do
			local request = table.remove(M.queue, 1)
			if not request.settled then present(request) end
		end
		draining = false
	end

	local function onEvent(session, event)
		if event.kind ~= "ask:user" then return end
		-- Headless sessions never emit this far -- the tool refuses them in words --
		-- but the guard is cheap insurance against a host wiring one in.
		if session and session.headless then return end
		local request = {
			id = event.id,
			question = event.question,
			options = event.options,
			resolve = event.resolve,
			sessionTitle = session and session.title or nil,
			session = session,
		}
		transitions = transitions + 1
		M.queue[#M.queue + 1] = request
		if type(event.subscribeSettled) == "function" then
			local ok, unsubscribe = pcall(event.subscribeSettled, function() settle(request, nil, false) end)
			if ok and type(unsubscribe) == "function" then
				if request.settled then pcall(unsubscribe) else request.unsubscribeSettled = unsubscribe end
			elseif not ok then
				settle(request, "", true)
			end
		end
		transitions = transitions - 1
		drain()
	end

	function M.answer(id, text)
		if M.current and M.current.id == id then return settle(M.current, text, true) end
		for _, request in ipairs(M.queue) do
			if request.id == id then return settle(request, text, true) end
		end
		return false
	end

	-- A turn that stops mid-ask leaves a question on screen for a conversation that
	-- is no longer waiting on the answer. The tool's own wait loop notices the abort
	-- and returns, so resolving here closes the modal rather than leaving the user
	-- able to answer a dead turn. Scoped to one conversation, like the permission
	-- layer's own sweep: stopping this turn must not dismiss another's question.
	function M.sweep(session)
		transitions = transitions + 1
		local taken, kept = {}, {}
		if M.current and (session == nil or M.current.session == session) then
			taken[#taken + 1] = M.current
		end
		for _, request in ipairs(M.queue) do
			if session == nil or request.session == session then
				taken[#taken + 1] = request
			else
				kept[#kept + 1] = request
			end
		end
		M.queue = kept
		for _, request in ipairs(taken) do settle(request, "", true) end
		transitions = transitions - 1
		-- Closing one conversation's active question must not strand questions
		-- retained for other conversations behind an empty current slot.
		drain()
		return #taken
	end

	function M.watch()
		if M.watching then return M end
		local dispose = env.require("runtime/dispose")
		if dispose.draining then return M end
		local sessions = env.require("agent/session")
		local unwatch = sessions.anyEvent:connect(onEvent)
		M.watching = dispose.add(function()
			unwatch(); M.watching = nil; M.sweep()
		end, "ask.watch")
		return M
	end

	return M
end
