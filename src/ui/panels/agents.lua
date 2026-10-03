-- Subagents: what has been delegated, what is still running, and the ceilings.
--
-- A dispatch is the longest-lived and least visible thing this client does. It runs
-- for minutes on its own context, calls its own tools, and the only trace of it was a
-- card in one conversation's transcript -- which scrolls away, belongs to whichever
-- conversation started it, and offered no way to stop one child without stopping the
-- whole turn. Three subagents working at once were three spinners in three places.
--
-- So this panel is the register: every dispatch in this session, running ones first,
-- with what it was asked to do, where it came from, what it has called, and a stop for
-- each. Nothing here is computed for display -- it is `agent/subagent`'s own record.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local overlay = env.require("ui/overlay")
	local subagent = env.require("agent/subagent")
	local registry = env.require("agent/registry")

	local M = {}

	local STATUS = {
		queued = { label = "waiting for a slot", colour = "warn" },
		running = { label = "working", colour = "accent" },
		done = { label = "reported back", colour = "success" },
		stopped = { label = "stopped", colour = "warn" },
		failed = { label = "failed", colour = "danger" },
	}

	local function isLive(record)
		return record.status == "running" or record.status == "queued"
	end

	-- What a preset actually grants, in the group names the Tools panel uses. `full` is
	-- the absence of a filter rather than a list, which is worth saying in those words:
	-- it is the one preset that can change the game.
	local function describePreset(id)
		local groups = subagent.PRESETS[id]
		if groups == nil then return "every tool this client has" end
		local names = {}
		for group in pairs(groups) do names[#names + 1] = registry.groupLabel(group) end
		table.sort(names)
		return table.concat(names, ", ")
	end

	function M.new(parent)
		local panel = {}
		local elapsedLabels = {}
		local cards, monitors = {}, {}
		local visible, dirty, limitsDirty, destroyed = true, false, true, false
		local membershipDirty = false
		local emptyState, lastCapacity
		local function setText(label, value)
			if label.Text ~= value then label.Text = value end
		end
		local function counts(record)
			return math.max(0, (record.calls or 0) - (record.runCallBase or 0)),
				math.max(0, (record.finishedCalls or 0) - (record.runFinishedBase or 0))
		end
		local function currentNote(record)
			if record.stopping then return "Stopping after the current step" end
			if not isLive(record) then return util.trim(tostring(record.report or "")) end
			local calls, finished = counts(record)
			local pending = calls - finished
			if pending > 1 then return tostring(pending) .. " tool calls in progress" end
			if pending > 0 and record.currentTool then return "Running " .. record.currentTool end
			if pending > 0 then return "A tool call is still in progress" end
			if record.preview and record.preview.text ~= "" then return "Writing a response" end
			if record.preview and record.preview.reasoning ~= "" then return "Reasoning" end
			return record.statusText or (STATUS[record.status] or STATUS.done).label
		end

		local scroll = P.scroll(parent, {
			name = "Agents",
			size = UDim2.new(1, 0, 1, 0),
			gap = theme.space.lg,
			padding = theme.space.lg,
		})

		P.sectionHeader(scroll.instance, {
			title = "Subagents",
			description = "The agent hands self-contained work to a subagent with dispatch_agent: "
				.. "its own context, a subset of the tools, and a written report at the end. "
				.. "Open an agent to watch its current step, tool progress, latest messages and report.",
			layoutOrder = 1,
		})

		-- Capacity ------------------------------------------------------------

		local capacityCard = P.card(scroll.instance, { layoutOrder = 2, gap = theme.space.sm })
		local capacityRow = P.row(capacityCard, {
			name = "Capacity",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 1,
		})
		local capacityText = P.text(capacityRow, {
			name = "CapacityText",
			text = "",
			role = "small",
			color = theme.color.text,
			wrap = true,
			auto = "Y",
			size = UDim2.new(0, 0, 0, 0),
			flex = "Fill",
			layoutOrder = 1,
		})
		local stopAll = P.button(capacityRow, {
			name = "StopAll",
			text = "Stop all",
			variant = "danger",
			size = "sm",
			layoutOrder = 2,
			onClick = function()
				local stopped = subagent.stopAll()
				overlay.toast(stopped == 0 and "Nothing was running"
					or ("Stopping " .. util.pluralise(stopped, "subagent")), "info", 2)
			end,
		})
		stopAll.instance.LayoutOrder = 2
		local capacityBar = C.progress(capacityCard, { value = 0, layoutOrder = 2 })
		local capacityHint = P.text(capacityCard, {
			name = "CapacityHint",
			text = "",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 3,
		})

		-- The register --------------------------------------------------------

		local list = P.column(scroll.instance, {
			name = "Dispatches",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			layoutOrder = 3,
		})

		-- Declared here, defined with the card it draws into. The redraw covers both,
		-- and the card is built below the list it sits under.
		local renderLimits = function() end

		local function reportModal(record)
			local monitor = { record = record, dirty = true, rows = {} }
			local function cleanup()
				monitors[monitor] = nil
				monitor.record, monitor.rows, record = nil, nil, nil
			end
			local modal = overlay.modal({
				title = record.label,
				description = "Live activity and the latest delivered messages",
				width = theme.size.modalWide,
				scroll = true,
				height = theme.size.dialogTall,
				onClose = cleanup,
			})
			if not modal then return end
			monitor.modal = modal
			monitors[monitor] = true
			modal.card.Destroying:Connect(cleanup)
			local function textBlock(host, name, role, order)
				return P.text(host, { name = name, text = "", role = role or "small",
					color = theme.color.textSecondary, wrap = true, auto = "Y", layoutOrder = order })
			end
			local summary = P.card(modal.content, { name = "AgentLiveStatus", layoutOrder = 1, gap = theme.space.xs })
			local stateLabel = textBlock(summary, "CurrentStep", "bodyStrong", 1)
			local metaLabel = textBlock(summary, "LiveMeta", "caption", 2)
			local providerLabel = textBlock(summary, "Provider", "caption", 3)
			local deliveryLabel = textBlock(summary, "Delivery", "caption", 4)
			local workLabel = textBlock(summary, "CurrentProgress", "small", 5)
			local _, taskLabel = C.keyValue(modal.content, { key = "Task", value = record.currentTask or record.task, layoutOrder = 2 })
			local messages = P.card(modal.content, { name = "AgentMessages", layoutOrder = 3, gap = theme.space.xs })
			local messageTitle = textBlock(messages, "MessageTitle", "label", 1)
			local messageLabel = textBlock(messages, "LatestMessage", "small", 2)
			local reasoningTitle = textBlock(messages, "ReasoningTitle", "label", 3)
			local reasoningLabel = textBlock(messages, "LatestReasoning", "small", 4)
			setText(reasoningTitle, "Latest reasoning")
			local activity = P.card(modal.content, { name = "AgentActivity", layoutOrder = 4, gap = theme.space.sm })
			local activityTitle = textBlock(activity, "ActivityTitle", "label", 1)
			local activityHint = textBlock(activity, "ActivityHint", "caption", 2)
			setText(activityTitle, "Recent tool activity")
			local report = P.card(modal.content, { name = "AgentReport", layoutOrder = 5, gap = theme.space.xs })
			setText(textBlock(report, "ReportTitle", "label", 1), "Report")
			local reportLabel = textBlock(report, "Report", "small", 2)
			local followLabel = textBlock(report, "FollowUp", "caption", 3)
			C.keyValue(modal.content, { key = "Id", value = tostring(record.id), role = "monoSmall", layoutOrder = 6 })
			C.keyValue(modal.content, { key = "Tools", value = describePreset(record.preset), layoutOrder = 7 })
			local stopButton = P.button(modal.footer, {
				name = "StopAgent", text = "Stop", variant = "danger", size = "sm", layoutOrder = 1,
				onClick = function()
					if record and subagent.stop(record.id) then overlay.toast("Asked it to stop. It finishes the step it is on.", "info", 3) end
				end,
			})
			P.button(modal.footer, {
				text = "Close",
				variant = "primary",
				size = "sm",
				layoutOrder = 2,
				onClick = function() modal.close() end,
			})
			function monitor.tick()
				if not record or modal.closed then return end
				local calls, finished = counts(record)
				local elapsed = isLive(record) and clock.since(record.startedAt or clock.ms()) or (record.ms or 0)
				setText(metaLabel, string.format("%s  \194\183  %d of %d calls finished  \194\183  run %d",
					util.formatDuration(elapsed), finished, calls, record.runs or 1))
			end
			function monitor.update()
				if modal.closed then cleanup(); return end
				if subagent.get(record.id) ~= record then modal.close(); return end
				monitor.dirty = false
				local live = isLive(record)
				local status = STATUS[record.status] or STATUS.done
				setText(taskLabel, record.currentTask or record.task)
				setText(stateLabel, live and currentNote(record) or status.label)
				stateLabel.TextColor3 = theme.color[status.colour]
				monitor.tick()
				setText(providerLabel, record.provider and (tostring(record.provider) .. "  \194\183  " .. tostring(record.model or "")) or "")
				providerLabel.Visible = record.provider ~= nil
				local preview = record.preview
				local streaming = preview and (preview.text ~= "" or preview.reasoning ~= "")
				setText(deliveryLabel, preview and preview.limited and "Live preview limit reached; waiting for the full response."
					or streaming and "Receiving live output"
					or record.request and "Waiting for provider output. Buffered connections deliver text when the response completes."
					or "")
				deliveryLabel.Visible = streaming or record.request ~= nil
				local message = preview and preview.text ~= "" and preview.text or record.latestText
				local reasoning = preview and preview.reasoning ~= "" and preview.reasoning or record.latestReasoning
				local messageExcerpt, reasoningExcerpt = record.textExcerpt, record.reasoningExcerpt
				if preview and preview.text ~= "" then messageExcerpt = preview.textExcerpt end
				if preview and preview.reasoning ~= "" then reasoningExcerpt = preview.reasoningExcerpt end
				setText(messageTitle, (preview and preview.text ~= "" and "Live message" or "Latest message")
					.. (messageExcerpt and " (latest excerpt)" or ""))
				setText(reasoningTitle, "Latest reasoning" .. (reasoningExcerpt and " (latest excerpt)" or ""))
				setText(messageLabel, message or (live and "No message delivered yet." or "No intermediate message was delivered."))
				setText(reasoningLabel, reasoning or "")
				reasoningTitle.Visible, reasoningLabel.Visible = reasoning ~= nil and reasoning ~= "", reasoning ~= nil and reasoning ~= ""
				local calls = counts(record)
				local entries = record.activity or {}
				local work, active = {}, 0
				for _, item in ipairs(entries) do
					if not item.done then
						active = active + 1
						if #work < 4 then work[#work + 1] = item.name .. ": "
							.. util.ellipsis(item.progress or "waiting for progress", 220) end
					end
				end
				if active > #work then work[#work + 1] = tostring(active - #work) .. " more calls in progress" end
				setText(workLabel, table.concat(work, "\n"))
				workLabel.Visible = #work > 0
				setText(activityHint, #entries == 0 and "Tool calls appear here as they start."
					or calls > #entries and ("Showing " .. tostring(#entries) .. " active or recent calls; earlier calls are omitted.")
					or "Each call updates as progress and results arrive.")
				local retained = {}
				for index, item in ipairs(entries) do
					local key = item.index
					retained[key] = true
					local row = monitor.rows[key]
					if not row then
						local root = P.column(activity, { name = "Call_" .. tostring(key), auto = "Y",
							size = UDim2.new(1, 0, 0, 0), gap = theme.space.xxs })
						row = { root = root, title = textBlock(root, "CallTitle", "monoSmall", 1), detail = textBlock(root, "CallDetail", "small", 2) }
						monitor.rows[key] = row
					end
					row.root.LayoutOrder = index + 2
					local outcome = item.interrupted and "no result" or item.done and (item.ok and "finished" or "failed") or "in progress"
					setText(row.title, item.name .. "  \194\183  " .. outcome
						.. (item.ms and ("  \194\183  " .. util.formatDuration(item.ms)) or ""))
					row.title.TextColor3 = item.interrupted and theme.color.warn or item.done
						and (item.ok and theme.color.success or theme.color.danger) or theme.color.accent
					setText(row.detail, item.done and (item.summary or item.progress or "") or (item.progress or "Waiting for progress or a result."))
				end
				for key, row in pairs(monitor.rows) do
					if not retained[key] then row.root:Destroy(); monitor.rows[key] = nil end
				end
				report.Visible = not live
				setText(reportLabel, record.report or "Nothing was reported.")
				setText(followLabel, record.session and "Open for a follow-up. Ask the agent to continue this subagent by its Id."
					or "This subagent's context has been released.")
				stopButton.instance.Visible = live
				stopButton.setText(record.stopping and "Stopping" or "Stop")
				local enabled = live and not record.stopping
				if stopButton.enabled ~= enabled then stopButton.setEnabled(enabled) end
			end
			monitor.update()
			return modal
		end

		local function renderRecord(record, order)
			local view = cards[record.id]
			if not view then
				local card = P.card(list, { name = "Agent_" .. tostring(record.id), layoutOrder = order, gap = theme.space.xs })
				local head = P.row(card, { name = "Head", size = UDim2.new(1, 0, 0, 0), auto = "Y",
					gap = theme.space.xs, layoutOrder = 1 })
				local slot = P.frame(head, { name = "DotSlot", size = UDim2.fromOffset(theme.size.icon, theme.size.icon), layoutOrder = 1 })
				local dot = P.statusDot(slot, { diameter = theme.size.dot, color = theme.color.accent,
					anchor = Vector2.new(0.5, 0.5), position = UDim2.fromScale(0.5, 0.5) })
				P.text(head, { name = "Label", text = record.label, role = "small", color = theme.color.text,
					truncate = true, size = UDim2.new(0, 0, 0, theme.text.small.height), flex = "Fill", layoutOrder = 2 })
				local elapsed = P.text(head, { name = "Elapsed", text = "", role = "caption", color = theme.color.textTertiary,
					align = "Right", size = UDim2.fromOffset(theme.size.metaColumn, theme.text.small.height), layoutOrder = 3 })
				local facts = P.text(card, { name = "Facts", text = "", role = "caption", color = theme.color.textTertiary,
					wrap = true, auto = "Y", layoutOrder = 2 })
				local note = P.text(card, { name = "Note", text = "", role = "small", color = theme.color.textSecondary,
					wrap = true, auto = "Y", layoutOrder = 3 })
				local actions = P.row(card, { name = "Actions", size = UDim2.new(1, 0, 0, 0), auto = "Y", wrap = true,
					alignX = "Right", gap = theme.space.xs, layoutOrder = 4 })
				P.button(actions, { name = "Open", text = "Details", variant = "ghost", size = "sm", layoutOrder = 2,
					onClick = function() reportModal(record) end })
				local stop = P.button(actions, { name = "Stop", text = "Stop", variant = "danger", size = "sm", layoutOrder = 3,
					onClick = function()
						if subagent.stop(record.id) then overlay.toast("Asked it to stop. It finishes the step it is on.", "info", 3) end
					end })
				view = { card = card, dot = dot, facts = facts, note = note, stop = stop, elapsed = elapsed }
				cards[record.id] = view
			end
			local live = isLive(record)
			local status = STATUS[record.status] or STATUS.done
			view.card.LayoutOrder = order
			view.dot.BackgroundColor3 = theme.color[status.colour]
			local elapsed = live and clock.since(record.startedAt or clock.ms()) or (record.ms or 0)
			setText(view.elapsed, elapsed >= 1000 and util.formatDuration(elapsed) or "")
			if live then elapsedLabels[record.id] = { record = record, label = view.elapsed } end
			local calls, finished = counts(record)
			local facts = { record.stopping and "stopping" or status.label, tostring(record.preset) .. " tools" }
			if (record.depth or 1) > 1 then facts[#facts + 1] = "depth " .. tostring(record.depth) end
			if record.parentTitle then facts[#facts + 1] = "from " .. record.parentTitle end
			if record.unlimited then facts[#facts + 1] = "unlimited" end
			if (record.runs or 1) > 1 then facts[#facts + 1] = util.pluralise(record.runs, "run") end
			if calls > 0 then facts[#facts + 1] = string.format("%d of %s finished", finished, util.pluralise(calls, "call")) end
			if not live and record.session then facts[#facts + 1] = "open for a follow-up" end
			setText(view.facts, table.concat(facts, "  \194\183  "))
			local note = live and currentNote(record) or tostring(record.report or "")
			-- A different agent's progress must not rescan every retained report.
			if view.noteSource ~= note then
				view.noteSource = note
				local display = util.ellipsis(util.trim(note):gsub("%s+", " "), 220)
				setText(view.note, display)
				view.note.Visible = display ~= ""
			end
			view.note.TextColor3 = record.status == "failed" and theme.color.danger or theme.color.textSecondary
			view.stop.instance.Visible = live
			view.stop.setText(record.stopping and "Stopping" or "Stop")
			local enabled = live and not record.stopping
			if view.stop.enabled ~= enabled then view.stop.setEnabled(enabled) end
			return view.card
		end

		local function render()
			if not scroll.instance.Parent then return end
			elapsedLabels = {}
			if limitsDirty then renderLimits(); limitsDirty = false end

			local records = subagent.list()
			local running = #subagent.running()
			local ceiling = subagent.concurrencyLimit()

			capacityText.Text = running == 0
				and "Nothing is delegated right now."
				or string.format("%d of %d slots in use", running, ceiling)
			local capacity = ceiling > 0 and (running / ceiling) or 0
			if lastCapacity ~= capacity then capacityBar.set(capacity); lastCapacity = capacity end
			if subagent.unlimited() then
				capacityHint.Text = string.format(
					"Subagents run without a step limit or clock while the main agent continues working. "
					.. "Admitted work over the ceiling waits for a slot; a subagent "
					.. "may dispatch its own up to %s deep. Stop is the bound that still applies.",
					util.pluralise(tonumber(config.get("agent.subagentDepth", 2)) or 2, "level"))
			else
				capacityHint.Text = string.format(
					"Each one may work for %s and take up to %s. Anything over the ceiling waits for a slot; "
					.. "a subagent may dispatch its own up to %s deep.",
					util.formatDuration(subagent.budgetSeconds() * 1000),
					util.pluralise(tonumber(config.get("agent.subagentTurns", 14)) or 14, "step"),
					util.pluralise(tonumber(config.get("agent.subagentDepth", 2)) or 2, "level"))
			end
			stopAll.instance.Visible = running > 0

			local retained = {}
			for index, record in ipairs(records) do
				retained[record.id] = true
				renderRecord(record, index)
			end
			for id, view in pairs(cards) do
				if not retained[id] then view.card:Destroy(); cards[id] = nil end
			end
			if #records == 0 and not emptyState then
				emptyState = C.emptyState(list, {
					title = "No subagents yet",
					description = "When the agent delegates -- a wide search, a sweep of the instance "
						.. "tree, anything repetitive -- the dispatch shows up here while it works "
						.. "and stays afterwards with its report.",
					layoutOrder = 1,
				})
			elseif #records > 0 and emptyState then
				emptyState:Destroy(); emptyState = nil
			end
		end

		-- Limits --------------------------------------------------------------

		-- Stated here, changed in Settings. Both surfaces read the same four keys, and a
		-- slider is built with the value it had at build time -- so a second set of
		-- sliders here would sit next to the first and be able to disagree with it. The
		-- facts are redrawn with the list, so what this says is always what is in force.
		local limits = P.card(scroll.instance, { layoutOrder = 4, gap = theme.space.sm })
		P.text(limits, {
			name = "LimitsTitle",
			text = "Limits",
			role = "label",
			color = theme.color.textSecondary,
			layoutOrder = 1,
		})
		local limitFacts = P.column(limits, {
			name = "LimitFacts",
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.xxs,
			layoutOrder = 2,
		})
		P.button(limits, {
			name = "OpenAgentSettings",
			text = "Change these",
			variant = "secondary",
			size = "sm",
			layoutOrder = 3,
			onClick = function()
				env.require("ui/app").showSettingsDialog("agent")
			end,
		})

		local function renderLimitsInto()
			for _, child in ipairs(limitFacts:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			-- The button's own layout order is stated above; a P.card is a column, so the
			-- facts sit between the title and it.
			local unlimited = subagent.unlimited()
			local rows = {
				{
					key = "Budget",
					value = unlimited
						and "no clock while the parent turn remains active; the main agent can keep working"
						or (util.formatDuration(subagent.budgetSeconds() * 1000)
							.. " of work each, then it wraps up"),
				},
				{
					key = "At once",
					value = util.pluralise(subagent.concurrencyLimit(), "subagent")
						.. " across the whole tree; the rest wait for a slot",
				},
				{
					key = "Steps",
					value = unlimited
						and "no limit -- only the repeat breaker and Stop end a run"
						or (util.pluralise(tonumber(config.get("agent.subagentTurns", 14)) or 14, "tool round")
							.. " before it has to answer with what it has"),
				},
				{
					key = "Depth",
					value = (function()
						local depth = tonumber(config.get("agent.subagentDepth", 2)) or 2
						if depth <= 0 then
							return "delegation is off -- the agent does the work in the conversation"
						end
						return util.pluralise(depth, "level") .. " of delegation"
					end)(),
				},
				{
					key = "Follow-ups",
					value = "the agent can send a finished subagent another message with agent_followup; "
						.. "the newest few keep their context for it",
				},
			}
			for index, row in ipairs(rows) do
				C.keyValue(limitFacts, {
					key = row.key,
					value = row.value,
					color = theme.color.textSecondary,
					layoutOrder = index,
				})
			end
		end

		-- Now that the card exists, the forward declaration points at the real one.
		renderLimits = renderLimitsInto

		-- Presets -------------------------------------------------------------

		local presets = P.card(scroll.instance, { layoutOrder = 5, gap = theme.space.xs })
		P.text(presets, {
			name = "PresetsTitle",
			text = "What a subagent is given",
			role = "label",
			color = theme.color.textSecondary,
			layoutOrder = 1,
		})
		P.text(presets, {
			name = "PresetsHint",
			text = "The model picks one of these per dispatch. 'read' is the default and cannot "
				.. "change anything; a delegated write is hard to attribute afterwards, which is "
				.. "why it has to be asked for.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 2,
		})
		local presetOrder = { "read", "web", "game", "full" }
		for index, id in ipairs(presetOrder) do
			C.keyValue(presets, {
				key = id,
				value = describePreset(id),
				color = id == "full" and theme.color.warn or theme.color.textSecondary,
				layoutOrder = index + 2,
			})
		end

		render()

		-- One owned frame subscription drains changes at most ten times a second.
		-- Continuous output cannot postpone its own redraw, and updates retain rows,
		-- focused controls and scroll positions. Hidden registers do no drawing.
		local unsubscribe = subagent.changed:connect(function()
			dirty, membershipDirty = true, true
			for monitor in pairs(monitors) do monitor.dirty = true end
		end)
		local unsubscribeConfig = config.changed:connect(function(path)
			if path == nil or path == "agent" or util.startsWith(tostring(path), "agent.subagent") then
				dirty, limitsDirty = true, true
			end
		end)
		local refreshElapsed, timerElapsed = 0, 0
		local heartbeat = env.run.Heartbeat:Connect(function(dt)
			if destroyed or (not visible and next(monitors) == nil and not membershipDirty) then return end
			refreshElapsed, timerElapsed = refreshElapsed + dt, timerElapsed + dt
			if refreshElapsed >= 0.1 then
				refreshElapsed = 0
				if dirty and visible then dirty = false; render() end
				if membershipDirty and not visible then
					local retained = {}
					for _, record in ipairs(subagent.list()) do retained[record.id] = true end
					for id, view in pairs(cards) do
						if not retained[id] then
							view.card:Destroy(); cards[id], elapsedLabels[id] = nil, nil
						end
					end
				end
				membershipDirty = false
				for monitor in pairs(monitors) do if monitor.dirty then monitor.update() end end
			end
			if timerElapsed >= 0.5 then
				timerElapsed = 0
				if visible then
					for _, entry in pairs(elapsedLabels) do
						if entry.label.Parent and isLive(entry.record) then
							local elapsed = clock.since(entry.record.startedAt or clock.ms())
							setText(entry.label, elapsed >= 1000 and util.formatDuration(elapsed) or "")
						end
					end
				end
				for monitor in pairs(monitors) do if isLive(monitor.record) then monitor.tick() end end
			end
		end)
		scroll.instance.Destroying:Connect(function()
			destroyed = true
			unsubscribe(); unsubscribeConfig(); heartbeat:Disconnect()
			for monitor in pairs(monitors) do monitor.modal.close() end
			monitors, cards, elapsedLabels = {}, {}, {}
		end)

		panel.scroll = scroll
		panel.render = render
		function panel.setVisible(value)
			visible = value == true
			if visible and dirty and not destroyed then dirty = false; render() end
		end
		return panel
	end

	return M
end
