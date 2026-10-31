-- Review pending messages without interrupting the active conversation worker.
--
-- The queue is a list of things the user already decided to send, so the screen is
-- built around the order and the next item rather than around the controls: a numbered
-- medallion per message, the state in the line above it, and the four actions on a
-- quiet row underneath. Nothing here can start, stop or reorder the running turn --
-- that is the point of the surface -- so every control is either a reorder, an edit,
-- or a removal.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local M = {}
	local opened

	function M.open(session)
		if not session or session.removed then return end
		if opened and not opened.closed then opened.close() end
		local unsubscribes, scheduled, closed, editor = {}, false, false, nil
		local entries = {}
		local function cleanup()
			if closed then return end
			closed = true
			if editor and not editor.closed then editor.close() end
			for _, unsubscribe in ipairs(unsubscribes) do unsubscribe() end
		end
		local modal = overlay.modal({ title = "Up next", width = theme.size.modalWide,
			description = "Follow-ups run in this order after the current response or tool batch. Your draft stays in the composer, and the active turn is never interrupted.",
			scroll = true, onClose = cleanup })
		if not modal then return end
		opened = modal
		modal.card.Name = "MessageQueue"

		-- The state of the queue as one sentence, with a dot that carries the same
		-- meaning in colour. The old screen opened with a bare caption, so a held queue
		-- and a flowing one looked identical until the text was read.
		local summary = P.row(modal.content, { name = "QueueSummary", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.sm, layoutOrder = 1 })
		local statusDot = P.statusDot(summary, { diameter = theme.size.dot, color = theme.color.accent, layoutOrder = 1 })
		local status = P.text(summary, { name = "QueueStatus", text = "", role = "small",
			wrap = true, auto = "Y", flex = "Fill", layoutOrder = 2 })

		local rows = P.column(modal.content, { name = "QueuedItems", auto = "Y", gap = theme.space.sm,
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })

		-- Shown instead of the list when nothing is waiting. A modal that opens on an
		-- empty column reads as a loading failure, not as an empty queue.
		local empty = P.column(modal.content, { name = "QueueEmpty", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.hair, padding = { y = theme.space.lg }, layoutOrder = 3, visible = false })
		P.text(empty, { name = "QueueEmptyTitle", text = "Nothing waiting", role = "bodyStrong",
			color = theme.color.textSecondary, align = "Center", auto = "Y", wrap = true, layoutOrder = 1 })
		P.text(empty, { text = "Send a follow-up while UAI is working and it will wait here, in order.",
			role = "caption", color = theme.color.textTertiary, align = "Center", auto = "Y", wrap = true, layoutOrder = 2 })

		local resume = P.button(modal.footer, { name = "ResumeQueue", text = "Resume queued", variant = "primary", size = "sm",
			onClick = function()
				local ok, why = session.resumeQueue()
				if not ok then overlay.toast(tostring(why), "warn", 4) end
			end })
		local clear = P.button(modal.footer, { name = "ClearQueue", text = "Clear queued", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function()
				local ids = {}; for _, item in ipairs(session.queueSnapshot().items) do ids[#ids + 1] = item.id end
				overlay.confirm({ title = "Clear queued messages?", description = "Remove these " .. tostring(#ids) .. " follow-ups. The active response keeps running.",
					confirmText = "Clear queued", danger = true, onConfirm = function()
						local ok, why = session.clearQueued(ids)
						if not ok then overlay.toast(tostring(why), "warn", 3) end
					end })
			end })
		P.button(modal.footer, { name = "QueueDone", text = "Done", variant = "ghost", size = "sm", layoutOrder = 3,
			onClick = function() modal.close() end })

		local function edit(item)
			if editor and not editor.closed then editor.close() end
			editor = overlay.modal({ title = "Edit follow-up", description = "Changes apply to this queued message. Attached images stay attached.", width = theme.size.modalWide })
			if not editor then return end
			local currentEditor = editor
			local field = P.field(editor.content, { name = "QueuedEditField", text = item.text, multiline = true,
				height = theme.size.promptTextarea, layoutOrder = 1 })
			local notice = P.text(editor.content, { name = "QueuedEditNotice", text = "Up to 8,000 bytes.", role = "caption",
				wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
			-- A live count rather than a fixed limit: the only reason this field has a
			-- limit at all is that the queue stores bytes, so saying how many are used
			-- is more useful than restating the maximum.
			local function count()
				local used = #(field.get() or "")
				notice.Text = tostring(used) .. " of 8,000 bytes"
				notice.TextColor3 = used > 8000 and theme.color.warn or theme.color.textTertiary
			end
			field.instance:GetPropertyChangedSignal("Text"):Connect(count)
			count()
			P.button(editor.footer, { name = "CancelQueuedEdit", text = "Cancel", variant = "ghost", size = "sm",
				onClick = function() currentEditor.close() end })
			P.button(editor.footer, { name = "SaveQueuedEdit", text = "Save changes", variant = "primary", size = "sm", layoutOrder = 2,
				onClick = function()
					local ok, why = session.editQueued(item.id, field.get(), item.text)
					if ok then currentEditor.close() else notice.Text = tostring(why); notice.TextColor3 = theme.color.warn end
				end })
			field.focus()
		end

		local function makeEntry(item)
			local entry = {}
			-- A row, not a column: the medallion, the message and the remove control sit
			-- on one line, and the actions hang under the message rather than under the
			-- whole card. The card stays a single object when the list reorders because
			-- only its LayoutOrder moves.
			entry.frame = P.row(rows, { name = "Queued_" .. item.id, size = UDim2.new(1, 0, 0, 0), auto = "Y",
				gap = theme.space.sm, bg = theme.color.surfaceRaised, radius = theme.radius.lg,
				padding = { x = theme.space.md, y = theme.space.sm }, alignY = "Top" })
			P.stroke(entry.frame, theme.color.borderSubtle)
			entry.chip = P.frame(entry.frame, { name = "QueuedIndexChip", size = UDim2.fromOffset(theme.size.controlSmall, theme.size.controlSmall),
				bg = theme.color.surface, radius = theme.radius.sm, layoutOrder = 1 })
			entry.index = P.text(entry.chip, { name = "QueuedIndex", text = "", role = "caption",
				color = theme.color.textSecondary, align = "Center", size = UDim2.fromScale(1, 1) })
			entry.body = P.column(entry.frame, { name = "QueuedBody", size = UDim2.new(0, 0, 0, 0), auto = "Y",
				flex = "Fill", gap = theme.space.xs, layoutOrder = 2 })
			entry.status = P.text(entry.body, { name = "QueuedPosition", text = "", role = "caption",
				color = theme.color.textSecondary, auto = "Y", wrap = true, layoutOrder = 1 })
			entry.text = P.text(entry.body, { name = "QueuedText", text = "", role = "small", wrap = true,
				auto = "Y", layoutOrder = 2 })
			local actions = P.row(entry.body, { name = "QueuedActions", auto = "Y", wrap = true, gap = theme.space.xxs,
				size = UDim2.new(1, 0, 0, 0), layoutOrder = 3 })
			entry.read = P.button(actions, { name = "ReadQueued_" .. item.id, text = "Show full", variant = "ghost", size = "sm",
				onClick = function()
					entry.expanded = not entry.expanded
					entry.text.Text = entry.expanded and entry.item.text or util.ellipsis(entry.item.text, 320)
					entry.read.setText(entry.expanded and "Show less" or "Show full")
				end })
			entry.edit = P.button(actions, { name = "EditQueued_" .. item.id, text = "Edit", variant = "ghost", size = "sm", layoutOrder = 2,
				onClick = function() edit(entry.item) end })
			local function move(direction)
				local neighbor = direction == -1 and entry.previous or entry.next
				local ok, why = session.moveQueued(entry.item.id, direction, neighbor and neighbor.id)
				if not ok then overlay.toast(tostring(why), "warn", 3) end
			end
			entry.up = P.button(actions, { name = "MoveQueuedUp_" .. item.id, text = "Move up", variant = "ghost", size = "sm", layoutOrder = 3,
				onClick = function() move(-1) end })
			entry.down = P.button(actions, { name = "MoveQueuedDown_" .. item.id, text = "Move down", variant = "ghost", size = "sm", layoutOrder = 4,
				onClick = function() move(1) end })
			P.button(actions, { name = "CopyQueued_" .. item.id, text = "Copy text", variant = "ghost", size = "sm", layoutOrder = 5,
				onClick = function()
					local ok, why = env.require("runtime/clipboard").write(entry.item.text)
					overlay.toast(ok and "Queued message copied." or tostring(why), ok and "info" or "warn")
				end })
			entry.remove = P.iconButton(entry.frame, { name = "RemoveQueued_" .. item.id, icon = "trash", diameter = theme.size.controlSmall,
				variant = "ghost", layoutOrder = 3, onClick = function()
					local ok, why = session.removeQueued(entry.item.id)
					if not ok then overlay.toast(tostring(why), "warn", 3) end
				end })
			return entry
		end

		local function refresh()
			if closed or modal.closed then return end
			local current = sessions.current()
			if session.removed or not current or current.id ~= session.id then modal.close(); return end
			local pending = session.queueSnapshot()
			status.Text = pending.count == 0 and "Nothing is waiting. The active turn keeps running."
				or pending.held and ("Paused: " .. tostring(pending.reason or "work stopped") .. ". Resume when you are ready.")
				or (tostring(pending.count) .. " of " .. tostring(pending.limit) .. " queued. The active agent keeps working.")
			status.TextColor3 = pending.held and theme.color.warn or theme.color.textSecondary
			statusDot.BackgroundColor3 = pending.held and theme.color.warn
				or pending.count > 0 and theme.color.accent or theme.color.textDisabled
			resume.instance.Visible = pending.count > 0 and pending.held == true
			resume.setEnabled(not session.busy and not session.preparing)
			clear.instance.Visible = pending.count > 0
			empty.Visible = pending.count == 0
			local wanted = {}; for _, item in ipairs(pending.items) do wanted[item.id] = true end
			for id, entry in pairs(entries) do if not wanted[id] then entry.frame:Destroy(); entries[id] = nil end end
			for index, item in ipairs(pending.items) do
				local entry = entries[item.id]
				if not entry then
					entry = makeEntry(item)
					entries[item.id] = entry
				end
				entry.item, entry.previous, entry.next = item, pending.items[index - 1], pending.items[index + 1]
				entry.frame.LayoutOrder = index
				local imageCount, fileCount = #(item.images or {}), #(item.files or {})
				entry.index.Text = tostring(index)
				-- The first message is the one the next turn will actually send, so it
				-- carries the accent; everything behind it is neutral until it moves up.
				entry.chip.BackgroundColor3 = index == 1 and theme.color.accentSurface or theme.color.surface
				entry.index.TextColor3 = index == 1 and theme.color.accent or theme.color.textTertiary
				entry.status.Text = tostring(index) .. " of " .. tostring(pending.count) .. " \194\183 "
					.. (item.state == "preparing" and "Preparing attachments" or pending.held and "Paused" or index == 1 and "Up next" or "Waiting")
					.. (fileCount > 0 and (" \194\183 " .. util.pluralise(fileCount, "file")) or "")
					.. (imageCount > 0 and (" \194\183 " .. util.pluralise(imageCount, "image")) or "")
				entry.status.TextColor3 = item.state == "preparing" and theme.color.warn
					or pending.held and theme.color.warn
					or index == 1 and theme.color.accent or theme.color.textTertiary
				entry.text.Text = entry.expanded and item.text or util.ellipsis(item.text or "", 320)
				entry.read.instance.Visible = #(item.text or "") > 320
				entry.edit.instance.Visible = item.state == "queued" and fileCount == 0
				entry.up.instance.Visible = entry.previous ~= nil
				entry.down.instance.Visible = entry.next ~= nil
				entry.up.setEnabled(item.state == "queued" and entry.previous and entry.previous.state == "queued")
				entry.down.setEnabled(item.state == "queued" and entry.next and entry.next.state == "queued")
			end
		end
		local function queue()
			if scheduled or closed or modal.closed then return end
			scheduled = true
			clock.delay(0.05, function() scheduled = false; refresh() end)
		end
		unsubscribes[#unsubscribes + 1] = session.events:connect(function(event)
			if event.kind:sub(1, 8) == "message:" or event.kind == "queue:state" or event.kind == "status" then queue() end
		end)
		unsubscribes[#unsubscribes + 1] = sessions.listChanged:connect(queue)
		modal.scrim.Destroying:Connect(cleanup)
		refresh()
		return modal
	end
	return M
end
