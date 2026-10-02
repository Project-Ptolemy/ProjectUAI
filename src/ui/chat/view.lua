-- The transcript.
--
-- Subscribe before replay, retain the reader's position, and release rows when
-- their activity leaves bounded history. Layout changes never own conversation data.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local message = env.require("ui/chat/message")

	local M = {}

	function M.new(parent, props)
		props = props or {}

		local scroll = P.scroll(parent, {
			name = "Transcript",
			size = props.size or UDim2.new(1, 0, 1, 0),
			gap = theme.space.lg,
			padding = { x = theme.space.lg, top = theme.space.xl, bottom = theme.space.lg },
			fade = false,
		})

		local view = {
			scroll = scroll,
			order = 0,
			tools = {},
			agents = {},
			working = nil,
			-- The open activity block, if the transcript is mid-run. Tool calls, the
			-- thinking between them and the notices they raise all go inside it; prose
			-- from either side closes it.
			run = nil,
			agentHandle = nil,
			session = nil,
			unsubscribe = nil,
			pinned = true,
			rows = {},
			runs = {},
			generation = 0,
			lastRenderedId = 0,
		}
		local destroyed, adjusting, layoutQueued = false, false, false
		local visible = props.visible ~= false
		local reading, chunkReading, disclosureReading
		local previousY = 0
		local unread = 0
		local viewport = env.require("ui/chat/viewport").new(scroll, { defer = function() return view.replaying end })
		props = util.copy(props); props.viewport = viewport
		view.viewport = viewport
		viewport.setVisible(visible)

		local function track(handle, event)
			if not handle or not handle.root or not event or not event.transcriptId then return handle end
			local id = event.transcriptId
			local previous = view.rows[id]
			if previous == handle then return handle end
			if previous and previous.transcriptIds then previous.transcriptIds[id] = nil end
			-- Several retained events can share a disclosure. One destruction listener
			-- per row avoids keeping a listener for every expired reasoning fragment.
			if not handle.transcriptIds then
				handle.transcriptIds = {}
				handle.root.Destroying:Connect(function()
					for tracked in pairs(handle.transcriptIds) do
						if view.rows[tracked] == handle then view.rows[tracked] = nil end
					end
					handle.transcriptIds, handle.thoughtChunks = {}, nil
				end)
			end
			handle.transcriptIds[id] = true
			view.rows[id] = handle
			return handle
		end
		local function setThoughtChunks(handle, chunks)
			handle.thoughtChunks = chunks
			local text = {}
			for _, chunk in ipairs(chunks) do text[#text + 1] = chunk.text end
			handle.setText(table.concat(text, "\n\n"))
		end
		-- Tracking is local to this view. No shared renderer or other chat is mutated.
		local builders = message
		local message = {}
		for name, builder in pairs(builders) do
			local renderer, rendererName = builder, name
			message[name] = function(...)
				local handle = renderer(...)
				if rendererName == "toolRun" then
					view.runs[handle.root] = handle
					handle.root.Destroying:Connect(function()
						view.runs[handle.root] = nil
						if view.run == handle then view.run = nil end
					end)
				elseif rendererName ~= "working" then track(handle, view.renderingEvent) end
				return handle
			end
		end

		local function remember()
			local state = { pinned = view.pinned, y = scroll.instance.CanvasPosition.Y }
			disclosureReading = nil
			chunkReading = not view.pinned and viewport.anchor() or nil
			if not view.pinned then
				local best, bestRoot, distance, firstTop, varied
				for id, handle in pairs(view.rows) do
					local root = handle.root
					local top = root.AbsolutePosition.Y - scroll.instance.AbsolutePosition.Y
					local visible, ancestor = root.Visible, root.Parent
					while visible and ancestor and ancestor ~= scroll.instance do
						if ancestor:IsA("GuiObject") and not ancestor.Visible then visible = false end
						ancestor = ancestor.Parent
					end
					if visible and ancestor == scroll.instance and root.AbsoluteSize.Y > 0 then
						if firstTop ~= nil and firstTop ~= top then varied = true end
						firstTop = firstTop or top
						local gap = math.max(0, top)
						if top + root.AbsoluteSize.Y > 0 and (not distance or gap < distance
							or (gap == distance and bestRoot and root:IsDescendantOf(bestRoot))) then
							best, bestRoot, distance = { id = id, offset = top }, root, gap
						end
					end
				end
				-- Until native layout has measured distinct rows, retain the pixel offset.
				if best and (varied or best.offset < 0) then state.anchor, state.offset = best.id, best.offset end
			end
			reading = state
			if view.session then view.session.viewState = util.copy(state) end
			return state
		end

		local function move(y)
			local previous = adjusting
			adjusting = true
			y = math.max(0, y)
			if math.abs(scroll.instance.CanvasPosition.Y - y) >= 0.5 then
				scroll.instance.CanvasPosition = Vector2.new(0, y)
			end
			previousY = scroll.instance.CanvasPosition.Y
			adjusting = previous
		end

		-- Opening details is an explicit decision to read here. Keep the clicked
		-- header in place even when the conversation had been following live output.
		local activityOptions = { beforeToggle = function(header)
			view.pinned = false
			remember()
			chunkReading = nil
			disclosureReading = { root = header, offset = header.AbsolutePosition.Y - scroll.instance.AbsolutePosition.Y }
			view.repin()
		end }

		local latest = P.button(parent, {
			name = "Latest",
			text = "Jump to latest",
			variant = "secondary",
			icon = "chevron",
			iconDirection = "down",
			radius = theme.radius.pill,
			size = "sm",
			anchor = Vector2.new(0.5, 1),
			position = UDim2.new(0.5, 0, 1, -theme.space.sm),
			zIndex = theme.z.raised,
			onClick = function()
				view.pinned = true
				reading, chunkReading, disclosureReading = nil, nil, nil
				unread = 0
				move(math.max(scroll.instance.AbsoluteCanvasSize.Y - scroll.instance.AbsoluteWindowSize.Y, 0))
				view.repin()
			end,
		})
		latest.instance.Visible = false
		local function updateLatest()
			latest.instance.Visible = not view.pinned and not view.welcomeCard
			latest.setText(unread > 0 and (util.pluralise(unread, "new message") .. " - Jump to latest") or "Jump to latest")
		end

		-- Use the layout's measured height rather than a circular automatic canvas
		-- calculation through deeply nested automatic-height activity cards.
		scroll.instance.AutomaticCanvasSize = Enum.AutomaticSize.None
		local function syncLayout()
			if destroyed or not visible or not scroll.instance.Parent then return end
			local previous = adjusting
			adjusting = true
			local height = scroll.layout.AbsoluteContentSize.Y
			local pad = scroll.instance:FindFirstChildOfClass("UIPadding")
			if pad then height = height + pad.PaddingTop.Offset + pad.PaddingBottom.Offset end
			if scroll.layout.AbsoluteContentSize.Y > 0 or view.order == 0 then
				local wanted = math.ceil(math.max(0, height))
				if scroll.instance.CanvasSize.Y.Offset ~= wanted then scroll.instance.CanvasSize = UDim2.fromOffset(0, wanted) end
			end
			if view.welcomeCard then move(0)
			elseif view.pinned then
				move(math.max(scroll.instance.AbsoluteCanvasSize.Y - scroll.instance.AbsoluteWindowSize.Y, 0))
			elseif reading then
				local y = reading.y or 0
				local handle = reading.anchor and view.rows[reading.anchor]
				local chunkY = chunkReading and viewport.restoreAnchor(chunkReading)
				if disclosureReading and disclosureReading.root:IsDescendantOf(scroll.instance) then
					y = scroll.instance.CanvasPosition.Y + disclosureReading.root.AbsolutePosition.Y
						- scroll.instance.AbsolutePosition.Y - disclosureReading.offset
				elseif chunkY then y = chunkY
				elseif handle and handle.root.Parent then
					y = scroll.instance.CanvasPosition.Y + handle.root.AbsolutePosition.Y
						- scroll.instance.AbsolutePosition.Y - (reading.offset or 0)
				end
				move(y)
			end
			updateLatest()
			adjusting = previous
			viewport.wake()
		end

		local function follow(force)
			if destroyed or not visible then return end
			if force then view.pinned = true; reading, chunkReading, disclosureReading = nil, nil, nil; unread = 0 end
			if layoutQueued then return end
			layoutQueued = true
			clock.delay(0, function()
				if destroyed then return end
				syncLayout(); layoutQueued = false
			end)
		end
		scroll.layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function() follow() end)
		scroll.instance:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() follow() end)
		scroll.instance:GetPropertyChangedSignal("AbsoluteCanvasSize"):Connect(function() follow() end)
		scroll.instance:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(function() follow() end)

		-- Restoring a window preserves whether the reader was following new output.
		function view.repin()
			updateLatest()
			follow()
		end

		scroll.instance:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			local y = scroll.instance.CanvasPosition.Y
			local upward = y < previousY - 0.5
			previousY = y
			if destroyed or adjusting or view.replaying then return end
			-- Even a small upward scroll means read here. A generous bottom threshold
			-- otherwise grabs the wheel back and snaps the reader down on the next row.
			view.pinned = view.welcomeCard ~= nil or (not upward and scroll.atBottom(theme.space.hair))
			if view.pinned then unread = 0 end
			updateLatest()
			remember()
		end)

		local function nextOrder()
			view.order = view.order + 1
			return view.order
		end

		-- The activity block.
		--
		-- A turn's machinery -- the calls, the thinking between them, a retry notice --
		-- used to be a stack of top-level rows, and the transcript deliberately puts a
		-- paragraph's worth of air between top-level rows. Eight calls therefore read as
		-- eight separate events with the reply lost at the bottom, which is the "too much
		-- tool call" this fixes: one block, one paragraph gap around it, tight lines
		-- inside, and a stable summary that opens only when the reader chooses.
		--
		-- Only prose closes it, because prose is what a run is between. Closing on
		-- reasoning instead would give a step-per-call turn one block per call and change
		-- nothing, and putting a later row above an earlier one is not an option: the
		-- block takes its layout order when it opens, so anything that has to sort after
		-- the rows already in it has to go in it.
		local function openRun(name)
			if not view.run then
				view.run = message.toolRun(scroll.instance, nextOrder(), view.renderingEvent and view.renderingEvent.at, activityOptions)
			end
			-- The run's header names the tools it holds, so the name of the call
			-- about to be added travels with the opening of its row.
			if name then view.run.pendingName = name end
			return view.run
		end

		local function closeRun()
			view.run = nil
		end

		local function appendThought(run, event, previewHandle)
			local handle = previewHandle or run.thought
			if not handle or not handle.root.Parent then handle = message.reasoning(run.rows, "", run.slot()) end
			local chunks = handle.thoughtChunks or {}
			local store = view.session and view.session.transcript
			local retained = event.transcriptId and store and store.get(event.transcriptId)
			chunks[#chunks + 1] = { id = event.transcriptId, text = (retained or event).text }
			setThoughtChunks(handle, chunks)
			run.thought = track(handle, event)
		end

		-- Where a row belongs: inside the open block, or in the transcript itself.
		local function target()
			if view.run then return view.run.rows, view.run.slot() end
			return scroll.instance, nextOrder()
		end

		local function agentFor(event)
			if not event.id then return nil end
			if not view.agents[event.id] then
				local into, order = target()
				view.agents[event.id] = message.subagent(into, event, order, activityOptions)
			end
			return view.agents[event.id]
		end

		local function clearWorking()
			if view.working then
				pcall(function() view.working.root:Destroy() end)
				view.working = nil
			end
		end

		-- The working row is transient and always belongs at the end of the
		-- transcript, so it takes an order no real row will reach rather than the next
		-- sequential one. Otherwise a tool row created while it is up sorts below it
		-- and the indicator ends up stranded in the middle of the conversation.
		local WORKING_ORDER = 2147483647

		local function ensureWorking()
			if not view.working then
				local request = view.session and view.session.liveRequest
				view.working = message.working(scroll.instance, WORKING_ORDER, request and request.at)
			end
			return view.working
		end

		local function clearPreview()
			local preview = view.preview; view.preview = nil
			if not preview then return end
			if preview.textHandle then preview.textHandle.root:Destroy() end
			if preview.thoughtHandle then
				preview.thoughtHandle.root:Destroy()
				if preview.ownsRun and preview.run.rows.Parent then
					local populated = false
					for _, child in ipairs(preview.run.rows:GetChildren()) do if child:IsA("GuiObject") then populated = true; break end end
					if not populated then preview.run.root:Destroy(); if view.run == preview.run then view.run = nil end end
				end
			end
		end

		local function showPreview(event)
			if not event.streamId then return end
			if view.preview and view.preview.id ~= event.streamId then clearPreview() end
			if not view.preview then view.preview = { id = event.streamId } end
			local preview = view.preview
			view.model = event.model or view.model
			local suffix = event.limited and "\n\n[Live preview limited; the full reply will appear when complete.]" or ""
			if util.trim(event.reasoning or "") ~= "" then
				if not preview.thoughtHandle then
					preview.ownsRun = view.run == nil; preview.run = openRun()
					preview.thoughtHandle = message.reasoning(preview.run.rows, "", preview.run.slot())
				end
				preview.thoughtHandle.setText(event.reasoning .. suffix)
			end
			if util.trim(event.text or "") ~= "" then
				if not preview.textHandle then
					closeRun()
					preview.textHandle = message.agent(scroll.instance, "", nextOrder(), view.model, props)
				end
				preview.textHandle.setModel(view.model)
				preview.textHandle.stream(event.text .. suffix)
			end
			ensureWorking().set(util.trim(event.text or "") ~= "" and "Receiving reply" or "Receiving reasoning")
			follow()
		end

		function view.empty()
			view.generation = view.generation + 1
			if view.replay then view.replay.events, view.replay.pending = {}, {} end
			view.replaying, view.replay = false, nil
			clearPreview()
			if view.welcomeCard then
				pcall(function() view.welcomeCard:Destroy() end)
				view.welcomeCard = nil
			end
			scroll.clear()
			view.order = 0
			view.lastRenderedId = 0
			view.tools = {}
			view.agents = {}
			view.working = nil
			view.run = nil
			view.agentHandle = nil
			view.model = nil
			view.pinned = true
			view.rows, view.runs = {}, {}
			view.historyNotice, view.issue, view.retentionRevision = nil, nil, nil
			reading, chunkReading, disclosureReading = nil, nil, nil
			unread = 0
			adjusting = true
			scroll.instance.CanvasSize = UDim2.fromOffset(0, 0)
			move(0)
			adjusting = false
			latest.instance.Visible = false
		end


		-- What an empty conversation shows: the greeting, the activity card, and -- on a
		-- client with nothing configured yet -- the one thing to do about that. The card
		-- itself lives in ui/panels/home, which reads agent/stats.
		function view.greeting()
			if destroyed or not visible then return end
			local providers = env.require("provider/registry")
			if view.welcomeCard then
				pcall(function() view.welcomeCard:Destroy() end)
				view.welcomeCard = nil
			end
			view.welcomeCard = env.require("ui/panels/home").card(scroll.instance, nextOrder(), props)
			scroll.instance.CanvasPosition = Vector2.new(0, 0)
			if providers.count() == 0 then
				C.emptyState(view.welcomeCard, {
					title = "No provider configured",
					description = "Add an OpenAI-compatible endpoint to start. Anything that speaks /v1/chat/completions works: a hosted API, a relay, or a local server.",
					action = "Open providers",
					onAction = function()
						env.require("ui/app").show("providers")
					end,
					layoutOrder = 5,
				})
			end
		end

		-- Bound the live instance tree as well as the saved log. A retained child
		-- agent moves out of an expired dispatch row before that row is destroyed.
		local function prune()
			local store = view.session and view.session.transcript
			if not store or view.retentionRevision == store.revision then return end
			view.retentionRevision = store.revision
			local retainedRoots = {}
			for id, handle in pairs(view.rows) do if store.get(id) then retainedRoots[handle.root] = true end end
			for id, handle in pairs(view.rows) do
				local root = handle.root
				if not store.get(id) then
					if root.Parent and not retainedRoots[root] then
						for _, child in pairs(view.rows) do
							if retainedRoots[child.root] and child.root:IsDescendantOf(root) then
								local ancestor, nested = child.root.Parent, false
								while ancestor and ancestor ~= root do
									if retainedRoots[ancestor] then nested = true; break end
									ancestor = ancestor.Parent
								end
								if not nested then child.root.LayoutOrder = root.LayoutOrder; child.root.Parent = root.Parent end
							end
						end
						root:Destroy()
					end
					if handle.transcriptIds then handle.transcriptIds[id] = nil end
					view.rows[id] = nil
				end
			end
			local thoughts = {}
			for _, handle in pairs(view.rows) do
				if handle.thoughtChunks and not thoughts[handle] then
					thoughts[handle] = true
					local kept = {}
					for _, chunk in ipairs(handle.thoughtChunks) do
						if not chunk.id or store.get(chunk.id) then kept[#kept + 1] = chunk end
					end
					if #kept ~= #handle.thoughtChunks then setThoughtChunks(handle, kept) end
				end
			end
			for root, run in pairs(view.runs) do
				local populated = false
				if root.Parent then
					for _, child in ipairs(run.rows:GetChildren()) do if child:IsA("GuiObject") then populated = true; break end end
				end
				if not populated then
					if view.run == run then view.run = nil end
					root:Destroy(); view.runs[root] = nil
				end
			end
			for id, handle in pairs(view.tools) do if not handle.root.Parent then view.tools[id] = nil end end
			for id, handle in pairs(view.agents) do if not handle.root.Parent then view.agents[id] = nil end end
			if view.run and view.run.thought and not view.run.thought.root.Parent then view.run.thought = nil end
			if view.agentHandle and not view.agentHandle.root.Parent then view.agentHandle = nil end
			local notes = {}
			if store.omitted.conversation > 0 then notes[#notes + 1] = "Older messages reached the saved-history limit. Recent messages remain available." end
			if store.omitted.activity + store.omitted.lifecycle > 0 then notes[#notes + 1] = "Older activity details were removed to keep this conversation responsive." end
			if store.recovered > 0 then notes[#notes + 1] = "Some messages were recovered from saved context." end
			if #notes > 0 then
				if not view.historyNotice then
					view.historyNotice = P.text(scroll.instance, { name = "HistoryNotice", role = "caption", wrap = true,
						auto = "Y", color = theme.color.textTertiary, layoutOrder = -2 })
				end
				view.historyNotice.Text = table.concat(notes, " ")
			end
			follow()
		end

		-- One event in, one row out. Anything not listed is deliberately ignored:
		-- the log carries more than a transcript should show.
		function view.render(event)
			if destroyed or not visible then return end
			view.renderingEvent = event
			if event.kind == "user" then
				clearPreview()
				clearWorking()
				closeRun()
				if view.welcomeCard then
					pcall(function() view.welcomeCard:Destroy() end)
					view.welcomeCard = nil
				end
				view.agentHandle = nil
				message.user(scroll.instance, event.text, nextOrder(), props)
				follow(not view.replaying)
			elseif event.kind == "status" then
				if event.text and event.text ~= "Ready" then
					ensureWorking().set(event.text)
					follow()
				elseif event.text == "Ready" then
					clearPreview()
					clearWorking()
				end
			elseif event.kind == "request:start" then
				clearPreview()
				view.model = event.model or event.provider
				-- Buffered HTTP provides no frames while the request is pending.
				ensureWorking().set("Waiting for " .. tostring(event.provider))
				follow()
			elseif event.kind == "assistant:preview" then
				showPreview(event)
			elseif event.kind == "assistant:complete" then
				clearPreview()
			elseif event.kind == "request:done" and event.error then
				clearPreview()
			elseif event.kind == "assistant:reasoning" then
				if util.trim(event.text or "") == "" then return end
				local preview = view.preview
				if preview and preview.id == event.streamId and preview.thoughtHandle then
					appendThought(preview.run, event, preview.thoughtHandle); preview.thoughtHandle = nil
				else
					appendThought(openRun(), event)
				end
				follow()
			elseif event.kind == "assistant:text" then
				local trimmed = util.trim(event.text or "")
				if trimmed ~= "" and trimmed ~= "..." and trimmed ~= "…" then
					clearWorking()
					closeRun()
					view.model = event.model or view.model
					local preview = view.preview
					if preview and preview.id == event.streamId and preview.textHandle then
						preview.textHandle.finish(event.text, view.model); view.agentHandle = track(preview.textHandle, event); preview.textHandle = nil
					else view.agentHandle = message.agent(scroll.instance, event.text, nextOrder(), view.model, props) end
					if not view.replaying and not view.pinned then unread = unread + 1 end
					follow()
				end
			elseif event.kind == "tool:call" then
				-- The working row deliberately survives a tool call: it is the "this
				-- turn is still running" indicator and it sorts last, so it stays put
				-- below the tool rows instead of being destroyed and rebuilt -- which
				-- restarted the spinner's phase and left the following request with no
				-- indicator at all.
				local run = openRun(event.name)
				run.thought = nil
				local handle = message.toolCall(run.rows, event, run.slot(), activityOptions)
				handle.run = run
				run.opened()
				view.tools[event.id or util.uid("tool")] = handle
				follow()
			elseif event.kind == "tool:progress" then
				local handle = event.id and view.tools[event.id]
				-- Older hosts may emit unaddressed progress. It is only unambiguous
				-- when a single call is open; never copy it onto unrelated parallel work.
				if not event.id and util.count(view.tools) == 1 then
					local _, only = next(view.tools)
					handle = only
				end
				if handle and handle.progress then handle.progress(event.text) end
				follow()
			elseif event.kind == "tool:result" or event.kind == "tool:error" then
				local handle = view.tools[event.id]
				if handle then
					handle.finish(event)
					track(handle, event)
					if handle.run then handle.run.closed(event.kind ~= "tool:error" and event.ok ~= false, event.at) end
					view.tools[event.id] = nil
				else
					local into, order = target()
					message.notice(into, {
						tone = event.kind == "tool:error" and "bad" or "info",
						text = string.format("%s: %s", tostring(event.name), util.ellipsis(event.text, 200)),
					}, order)
				end
				follow()
			elseif event.kind == "subagent:start" then
				-- Nested under the call that started it while that row is still tracked,
				-- so a delegated task reads as one block rather than as a card floating
				-- next to its own tool row. Standalone if the row is gone, which happens
				-- when the log has been trimmed past it.
				local host = event.call and view.tools[event.call] or nil
				if host and host.nest then
					view.agents[event.id] = message.subagent(host.nest(), event, 1, { nested = true, beforeToggle = activityOptions.beforeToggle })
				else
					local into, order = target()
					view.agents[event.id] = message.subagent(into, event, order, activityOptions)
				end
				follow()
			elseif event.kind == "subagent:status" then
				local handle = view.agents[event.id]
				if handle then handle.status(event) end
			elseif event.kind == "subagent:text" then
				local handle = agentFor(event)
				if handle then
					track(handle.say(event), event)
					follow()
				end
			elseif event.kind == "subagent:tool" then
				local handle = agentFor(event)
				if handle then
					track(handle.tool(event), event)
					follow()
				end
			elseif event.kind == "subagent:tool:done" then
				local handle = agentFor(event)
				if handle then track(handle.toolDone(event), event) end
			elseif event.kind == "subagent:done" then
				local handle = agentFor(event)
				if handle then
					handle.finish(event)
					track(handle, event)
					view.agents[event.id] = nil
					follow()
				end
			elseif event.kind == "request:retry" then
				local into, order = target()
				message.notice(into, {
					tone = "warn",
					text = string.format("%s: %s, retrying in %.1fs (attempt %d of %d)",
						tostring(event.provider), tostring(event.reason), event.wait or 0,
						event.attempt or 1, event.attempts or 1),
				}, order)
				follow()
			elseif event.kind == "provider:switch" then
				local into, order = target()
				message.notice(into, {
					tone = "warn",
					text = string.format("%s failed, trying %s", tostring(event.from), tostring(event.to)),
				}, order)
				follow()
			elseif event.kind == "compact" then
				local into, order = target()
				local before, after = tonumber(event.before), tonumber(event.after)
				local text = "Older turns were summarised to stay inside the context budget."
				if before and after and before > after then
					text = string.format("Compacted context: about %s to %s tokens.",
						util.formatNumber(before), util.formatNumber(after))
				end
				message.notice(into, { tone = "info", text = text }, order)
				follow()
			elseif event.kind == "error" then
				clearPreview()
				clearWorking()
				closeRun()
				message.notice(scroll.instance, {
					tone = "bad",
					text = tostring(event.message),
				}, nextOrder())
				follow()
			elseif event.kind == "abort" then
				clearPreview()
				clearWorking()
				closeRun()
				message.notice(scroll.instance, { tone = "warn", text = "Stopped." }, nextOrder())
				follow()
			elseif event.kind == "cleared" then
				view.empty()
				view.greeting()
			end
		end

		local function render(event)
			local ok, err = pcall(view.render, event)
			if event.transcriptId then view.lastRenderedId = math.max(view.lastRenderedId, event.transcriptId) end
			view.renderingEvent = nil
			if not ok then
				env.require("runtime/log").warn("ui", "transcript row failed: " .. tostring(event.kind), err)
				if not view.issue then
					view.issue = P.text(scroll.instance, { name = "TranscriptIssue", role = "caption", wrap = true,
						auto = "Y", color = theme.color.warn, layoutOrder = -1,
						text = "A row could not be displayed. Use Message options > Refresh conversation to redraw it." })
				end
				if event.text and (event.kind == "user" or event.kind == "assistant:text") then
					track({ root = P.text(scroll.instance, { name = "RecoveredText", text = event.text, role = "body",
						wrap = true, auto = "Y", layoutOrder = nextOrder() }) }, event)
				end
			end
		end

		local function saveReading()
			if not view.session then return end
			if disclosureReading then remember() end
			if reading then
				view.session.viewState = util.copy(reading); view.session.viewState.pinned = view.pinned
			else remember() end
		end

		local function settleLive(session)
			if session.busy then
				ensureWorking().set(session.status or "Working")
				if session.livePreview then render(session.livePreview)
				else
					clearPreview()
					if session.liveRequest then render(session.liveRequest) end
				end
				if session.transcript then for _, event in ipairs(session.transcript.live()) do render(event) end end
			else
				clearPreview(); clearWorking(); closeRun()
				for id, handle in pairs(view.tools) do
					if handle.stale then pcall(handle.stale) end
					if handle.run then pcall(handle.run.closed) end
					view.tools[id] = nil
				end
				for id, handle in pairs(view.agents) do
					if handle.stale then pcall(handle.stale) end
					view.agents[id] = nil
				end
			end
		end

		-- Subscribe before the snapshot so no event can fall between the two. A full
		-- replay rebuilds every retained row. Returning to a suspended view copies
		-- only unseen events into the queue, so unchanged history takes no replay
		-- slices and the existing text remains ready immediately.
		local function startReplay(session, incremental)
			view.replaying = true
			local mine = view.generation
			local replay = { events = {}, cursor = 1, pending = {}, incremental = incremental == true }
			view.replay = replay
			-- New durable events queue in order; transient preview/progress is
			-- reconciled from current state at the end.
			view.unsubscribe = session.events:connect(function(event)
				if destroyed or view.session ~= session then return end
				if event.kind == "cleared" then
					render(event); follow(); return
				end
				if view.replaying then
					if event.kind == "user" then view.pinned = true; reading, chunkReading, disclosureReading = nil, nil, nil; unread = 0 end
					if event.transcriptId then
						local saved = session.transcript and session.transcript.get(event.transcriptId) or event
						if saved then replay.pending[#replay.pending + 1] = saved end
						if #replay.pending > 1024 and session.transcript then
							local kept = {}
							for _, pending in ipairs(replay.pending) do if session.transcript.get(pending.transcriptId) then kept[#kept + 1] = pending end end
							replay.pending = kept
						end
					end
				else render(event); prune() end
			end)
			if incremental then
				for _, event in ipairs(session.log or {}) do
					if not event.transcriptId or event.transcriptId > view.lastRenderedId then
						replay.events[#replay.events + 1] = util.copy(event)
					end
				end
			else replay.events = session.transcript and session.transcript.snapshot() or util.slice(session.log or {}, 1) end
			if #(session.log or {}) == 0 and not view.welcomeCard then view.greeting() end
			local function batch()
				if destroyed or not visible or view.generation ~= mine or view.session ~= session then return end
				local started, processed = clock.ms(), 0
				while processed < 12 do
					if replay.cursor > #replay.events then
						if #replay.pending == 0 then
							replay.events, replay.pending = {}, {}
							view.replaying, view.replay = false, nil
							settleLive(session); prune(); follow(); return
						end
						replay.events, replay.pending, replay.cursor = replay.pending, {}, 1
						replay.incremental = false
					end
					local event = replay.events[replay.cursor]
					replay.cursor, processed = replay.cursor + 1, processed + 1
					-- An incremental replay skips rows that survived the release: their
					-- geometry and content are already measured or mounted.
					local tracked = replay.incremental and event.transcriptId and view.rows[event.transcriptId]
					if not tracked and (not event.transcriptId or not session.transcript or session.transcript.get(event.transcriptId)) then render(event) end
					if destroyed or view.generation ~= mine then return end
					if clock.since(started) >= 6 then break end
				end
				prune(); follow()
				clock.delay(0, batch)
			end
			batch()
		end

		function view.attach(session, force)
			if destroyed then return end
			if session and view.session == session and not force then
				-- A paused view (hidden window or another panel) returns through an
				-- incremental replay. It must not tear down its measured rows first.
				if visible and not view.unsubscribe then
					reading = session.viewState and util.copy(session.viewState) or reading
					view.pinned = not reading or reading.pinned ~= false
					startReplay(session, true)
					return
				end
				if not view.replaying then
					if session.busy then ensureWorking().set(session.status or "Working") else clearWorking() end
				end
				view.repin(); return
			end
			saveReading()
			if view.unsubscribe then view.unsubscribe(); view.unsubscribe = nil end
			view.empty(); view.session = session
			if not session then view.greeting(); return end
			reading = session.viewState and util.copy(session.viewState) or nil
			view.pinned = not reading or reading.pinned ~= false
			if not visible then return end
			startReplay(session, false)
		end

		function view.refresh() view.attach(view.session, true) end

		-- Coming back from a hidden window or another panel keeps the measured
		-- spacers and reconciles only the events that arrived while the view was
		-- released. A conversation cleared while hidden has no retained rows left to
		-- trust, so it takes the full rebuild; the transcript is empty, so that costs
		-- nothing. A switched session has already been emptied by attach.
		local function resume()
			local session = view.session
			if not session then view.attach(nil, true); return end
			if view.lastRenderedId > 0 and session.transcript then
				local retained = false
				for id in pairs(view.rows) do if session.transcript.get(id) then retained = true; break end end
				-- Clear may have been followed by new messages while hidden. No old row
				-- survives that reset; never display the old conversation beside the new.
				if not retained then view.attach(session, true); return end
			elseif view.order > 0 and #(session.log or {}) == 0 then view.attach(session, true); return end
			startReplay(session, true)
		end

		function view.setVisible(value)
			value = value == true
			if destroyed or visible == value then return end
			saveReading()
			visible = value
			local visited = {}
			for _, handle in pairs(view.rows) do
				if handle.setVisible and not visited[handle] then
					visited[handle] = true
					handle.setVisible(value)
				end
			end
			viewport.setVisible(value)
			-- Keep the bounded rendered reading window, expanded sections and live
			-- preview intact. Pause subscriptions and drawing until this view returns.
			if not value then
				if view.unsubscribe then view.unsubscribe(); view.unsubscribe = nil end
				clearWorking()
				view.generation = view.generation + 1
				view.replaying, view.replay = false, nil
			else resume() end
		end
		local function cleanup()
			if destroyed then return end
			saveReading(); destroyed = true
			view.generation = view.generation + 1
			if view.replay then view.replay.events, view.replay.pending = {}, {} end
			view.replaying, view.replay = false, nil
			if view.unsubscribe then view.unsubscribe(); view.unsubscribe = nil end
			viewport.destroy()
			view.rows, view.runs, view.tools, view.agents = {}, {}, {}, {}
			view.preview, view.working, view.agentHandle, view.run = nil, nil, nil, nil
			pcall(function() latest.instance:Destroy() end)
		end
		scroll.instance.Destroying:Connect(cleanup)
		function view.destroy()
			cleanup()
			pcall(function() scroll.instance:Destroy() end)
		end

		return view
	end

	return M
end
