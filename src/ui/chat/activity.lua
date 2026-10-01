-- Compact activity receipts and explicitly opened execution details.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local config = env.require("runtime/config")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local icons = env.require("ui/icons")
	local M = {}

	function M.new(render)
		local A = {}
		local stateWidth = math.max(theme.size.metaColumn, math.ceil(P.measureText("Unavailable", { role = "caption" }).X))
		local function column(parent, name, order, gap)
			return P.column(parent, { name = name, size = UDim2.new(1, 0, 0, 0), auto = "Y",
				layoutOrder = order, gap = gap or theme.space.xs })
		end
		local function text(parent, name, value, order, role, color)
			return P.text(parent, { name = name, text = tostring(value or ""), role = role or "small",
				color = color or theme.color.textSecondary, wrap = true,
				size = UDim2.new(1, 0, 0, 0), auto = "Y", layoutOrder = order })
		end
		local function singleLine(value, limit)
			return (util.ellipsis(tostring(value or ""), limit or 120):gsub("[\n\r]+", " "))
		end
		local function duration(ms)
			ms = math.max(0, tonumber(ms) or 0)
			return ms >= 1000 and util.formatDuration(ms) or string.format("%dms", ms)
		end

		-- Header labels reserve a fixed status column; long paths can only truncate
		-- their own line, never push the completion state beyond the reading column.
		local function header(parent, name, badgeName, icon, order)
			local button = Instance.new("TextButton", parent)
			button.Name, button.Text = name, ""
			button.AutoButtonColor = false
			button.BackgroundTransparency = 1
			button.Size = UDim2.new(1, 0, 0, math.max(theme.size.row, responsive.minTarget()))
			button.LayoutOrder, button.Selectable = order or 1, true
			Instance.new("UICorner", button).CornerRadius = UDim.new(0, theme.radius.sm)
			local stroke = Instance.new("UIStroke", button)
			stroke.Color, stroke.Thickness = theme.color.borderSubtle, theme.stroke.hair
			local mobile = responsive.isMobile()
			local row = P.row(button, { size = UDim2.fromScale(1, 1), gap = mobile and theme.space.xs or theme.space.sm,
				padding = { x = mobile and theme.space.xs or theme.space.sm } })
			local caret = P.frame(row, { name = "Caret", size = UDim2.fromOffset(theme.size.icon, theme.size.icon), layoutOrder = 1 })
			icons.chevron(caret, theme.size.icon, theme.color.textTertiary, "right")
			local badge = P.frame(row, { name = badgeName, size = UDim2.fromOffset(theme.size.icon, theme.size.icon), layoutOrder = 2 })
			badge.Visible = not mobile
			icons.draw(icon, badge, theme.size.icon, theme.color.accent)
			local label = P.text(row, { name = "Title", text = "", role = "small", color = theme.color.text,
				truncate = true, size = UDim2.new(0, 0, 1, 0), flex = "Fill", layoutOrder = 3 })
			local state = P.text(row, { name = "State", text = "", role = "caption", color = theme.color.textTertiary,
				align = "Right", size = UDim2.new(0, stateWidth, 1, 0), truncate = true, layoutOrder = 4 })
			return { root = button, caret = caret, label = label, state = state,
				tone = render.disclosure(button, stroke) }
		end
		local function bindToggle(head, body, opts, changed)
			local open = false
			local function setOpen(value)
				value = value == true
				if open == value then return end
				open = value
				if changed then changed(open) end
				body.Visible = open
				P.animate(head.caret, "hover", { Rotation = open and 90 or 0 })
			end
			body.Visible = false
			head.root.Activated:Connect(function()
				if opts and opts.beforeToggle then opts.beforeToggle(head.root) end
				setOpen(not open)
			end)
			return setOpen, function() return open end
		end

		function A.toolRun(parent, order, startedAt, opts)
			local holder = render.wrapper(parent, { name = "ToolRun", layoutOrder = order })
			local card = column(holder, "ActivitySurface")
			local head = header(card, "RunHeader", "RunIconBadge", "terminal")
			head.label.Name, head.state.Name = "RunSummary", "RunState"
			local rows = column(card, "Calls", 2)
			local handle = { root = holder, rows = rows, calls = 0, settled = 0, names = {}, failures = 0 }
			local started = tonumber(startedAt) or clock.ms()
			local slot, stop = 0, nil
			handle.setOpen, handle.isOpen = bindToggle(head, rows, opts)
			function handle.slot() slot = slot + 1; return slot end
			local function paint()
				local pending = math.max(0, handle.calls - handle.settled)
				local names = {}
				for index = 1, math.min(2, #handle.names) do names[#names + 1] = handle.names[index] end
				if #handle.names > 2 or handle.moreNames then names[#names + 1] = "more" end
				local state = pending > 0 and string.format("%d running", pending) or "Complete"
				if handle.failures > 0 then state = string.format("%d failed", handle.failures) end
				if handle.calls == 0 then state = "Details" end
				head.label.Text = handle.calls == 0 and "Reasoning" or string.format("Activity  ·  %s  ·  %d done  ·  %s%s", util.pluralise(handle.calls, "tool"), math.max(0, handle.settled - handle.failures), duration(handle.ms or clock.since(started)),
					#names > 0 and ("  ·  " .. table.concat(names, ", ")) or "")
				head.state.Text = state
				head.state.TextColor3 = handle.failed and theme.color.danger or (pending > 0 and theme.color.accent or theme.color.textTertiary)
			end
			function handle.opened()
				handle.ms = nil
				handle.calls = handle.calls + 1
				if handle.pendingName then
					local seen = false
					for _, name in ipairs(handle.names) do if name == handle.pendingName then seen = true; break end end
					if not seen then
						if #handle.names < 16 then handle.names[#handle.names + 1] = handle.pendingName else handle.moreNames = true end
					end
					handle.pendingName = nil
				end
				if not stop then stop = clock.interval(1, function() if handle.settled < handle.calls then paint() end end) end
				paint()
			end
			function handle.closed(ok, finishedAt)
				if ok == false then handle.failed = true; handle.failures = handle.failures + 1 end
				handle.settled = handle.settled + 1
				if handle.settled >= handle.calls then
					handle.ms = math.max(0, (tonumber(finishedAt) or clock.ms()) - started)
					if stop then stop(); stop = nil end
				end
				paint()
			end
			holder.Destroying:Connect(function() if stop then stop(); stop = nil end end)
			paint()
			return handle
		end

		function A.toolCall(parent, info, order, opts)
			opts = opts or {}
			local holder = render.wrapper(parent, { name = "Tool", layoutOrder = order })
			local card = column(holder, "ToolSurface")
			local head = header(card, "ToolHeader", "ToolIconBadge", "sliders")
			head.label.Name, head.state.Name = "ToolName", "ToolState"
			head.label.Text = tostring(info.name or "tool")
			head.state.Text = "Running"
			local raw = tostring(info.arguments or "")
			local decoded = util.decode(raw)
			local preview = text(card, "ToolSummary", render.summarise(decoded, raw), 2, "caption", theme.color.textTertiary)
			preview.TextWrapped = false
			preview.TextTruncate = Enum.TextTruncate.AtEnd
			preview.Size, preview.AutomaticSize = UDim2.new(1, -theme.space.md, 0, theme.text.caption.height), Enum.AutomaticSize.None
			local detail = column(card, "Detail", 4, theme.space.md)
			P.pad(detail, theme.space.sm)
			local handle = { root = holder, card = card }
			local nested, built, resultHolder, result, stale, shownResult
			local function paintResult()
				if not built or (not result and not stale) or shownResult == (result or "stale") then return end
				if resultHolder then resultHolder:Destroy() end
				resultHolder = column(detail, "Result", 3)
				shownResult = result or "stale"
				if stale and not result then
					text(resultHolder, "ResultLabel", "No result in the stored transcript.", 1, "caption", theme.color.textTertiary)
					return
				end
				local stopped = result.error == "aborted" or (result.data and result.data.status == "aborted")
				local timedOut = result.error == "timeout" or (result.data and result.data.status == "timeout")
				local quiet = stopped or result.denied
				local value = tostring(result.text or "")
				local isAnswer = info.name == "ask_user" and result.ok and util.startsWith(value, "The user answered:")
				text(resultHolder, "ResultLabel", isAnswer and "You answered" or (result.ok and "Result"
					or (stopped and "Execution stopped" or (timedOut and "Execution timed out"
					or (result.denied and "Permission declined" or "Execution failed")))), 1, "label",
					result.ok and theme.color.textTertiary or (quiet and theme.color.warn or theme.color.danger))
				if value:find("\n") or (not isAnswer and #value > 300) then
					render.codeBlock(resultHolder, { text = value, lang = "output", maxLines = 12, layoutOrder = 2 })
				else
					text(resultHolder, "ResultText", isAnswer and util.trim(value:sub(#"The user answered:" + 1)) or value,
						2, isAnswer and "small" or "monoSmall", result.ok and theme.color.textSecondary or theme.color.danger)
				end
				if result.truncated then text(resultHolder, "Truncation", "Trimmed before the model saw it.", 3, "caption", theme.color.warn) end
			end
			local function build()
				if built then paintResult(); return end
				built = true
				local codeParts, facts = render.splitArguments(decoded)
				if #facts > 0 then
					local args = column(detail, "Arguments", 1, theme.space.xxs)
					text(args, "ArgumentsLabel", "Input", 0, "label", theme.color.textTertiary)
					for index, fact in ipairs(facts) do C.keyValue(args, { key = fact.key, value = fact.value,
						role = "monoSmall", color = theme.color.textSecondary, layoutOrder = index }) end
				end
				if #codeParts > 0 and config.get("ui.showToolCode", true) ~= false then
					local listing = column(detail, "Listing", 2)
					for index, part in ipairs(codeParts) do render.codeBlock(listing, { text = part.text,
						lang = part.lang or part.key, label = part.label, maxLines = 12, layoutOrder = index }) end
				elseif #facts == 0 and #codeParts == 0 and util.trim(raw) ~= "" and util.trim(raw) ~= "{}" then
					render.codeBlock(detail, { text = raw, lang = "json", numbers = false, maxLines = 12, layoutOrder = 1 })
				end
				paintResult()
			end
			handle.setOpen, handle.isOpen = bindToggle(head, detail, opts, function(open) if open then build() end end)
			-- Delegated tasks have their own disclosure. Inspecting a child never needs
			-- the dispatch JSON or the duplicate tool result to be expanded first.
			function handle.nest()
				if not nested then nested = column(card, "Nested", 3); P.pad(nested, { left = theme.space.md }) end
				return nested
			end
			function handle.progress(value) preview.Text = singleLine(value) end
			function handle.stale()
				stale = true
				head.state.Text = "Unavailable"
				preview.Text = "No result in the stored transcript."
				if handle.isOpen() then paintResult() end
			end
			function handle.finish(value)
				result = { ok = value.ok, text = value.text, ms = value.ms, error = value.error,
					denied = value.denied, truncated = value.truncated,
					data = type(value.data) == "table" and { status = value.data.status } or nil }
				stale = false
				local stopped = result.error == "aborted" or (result.data and result.data.status == "aborted")
				local timedOut = result.error == "timeout" or (result.data and result.data.status == "timeout")
				local quiet = stopped or result.denied
				head.state.Text = result.ok and "Done" or (stopped and "Stopped" or (timedOut and "Timed out" or (result.denied and "Declined" or "Failed")))
				head.state.TextColor3 = result.ok and theme.color.success or (quiet and theme.color.warn or theme.color.danger)
				head.tone(not result.ok and (quiet and theme.color.warn or theme.color.dangerBorder) or nil)
				local answer = tostring(result.text or "")
				if info.name == "ask_user" and result.ok and util.startsWith(answer, "The user answered:") then
					answer = "You answered: " .. util.trim(answer:sub(#"The user answered:" + 1))
				end
				preview.Text = singleLine(answer)
				if result.ms then preview.Text = duration(result.ms) .. "  ·  " .. preview.Text end
				preview.TextColor3 = result.ok and theme.color.textTertiary or (quiet and theme.color.warn or theme.color.danger)
				if handle.isOpen() then paintResult() end
			end
			-- The explicit preference applies when a row is visible; hidden groups must
			-- never eagerly build listings during replay.
			if config.get("ui.showToolDetail", false) == true then
				local visible, ancestor = true, holder.Parent
				while ancestor do
					if ancestor:IsA("GuiObject") and not ancestor.Visible then visible = false; break end
					ancestor = ancestor.Parent
				end
				if visible then handle.setOpen(true) end
			end
			return handle
		end

		function A.subagent(parent, info, order, opts)
			opts = opts or {}
			local holder = render.wrapper(parent, { name = "Subagent", layoutOrder = order })
			local card = column(holder, "SubagentSurface")
			local head = header(card, "SubagentHeader", "SubagentIconBadge", "branch")
			head.label.Name, head.state.Name = "SubagentTitle", "SubagentState"
			head.label.Text = (info.followUp and "Follow-up: " or "Task: ") .. tostring(info.label or "Delegated task")
			head.state.Text = "Running"
			local summary = text(card, "SubagentSummary", "Starting", 2, "caption", theme.color.textTertiary)
			local report = column(card, "Report", 3)
			report.Visible = false
			local feed = column(card, "Feed", 4)
			P.pad(feed, { left = theme.space.md, top = theme.space.xs })
			local taskBuilt = false
			local handle = { root = holder, card = card }
			local rows, entries, slot, cursor, pending, destroyed = {}, {}, 2, 1, false, false
			local visible = true
			local started = tonumber(info.startedAt or info.at) or clock.ms()
			local calls, finished, finalMs, lastStatus, failures = 0, 0, nil, "Starting", 0
			local function paint()
				local counts = calls > 0 and string.format("%d/%d tools  ·  ", finished, calls) or ""
				summary.Text = counts .. duration(finalMs or clock.since(started)) .. "  ·  " .. singleLine(lastStatus, 160)
			end
			local function mount(entry)
				if entry.mounted or not entry.root.Parent then return end
				entry.mounted = true
				if entry.kind == "tool" then
					entry.renderer = A.toolCall(entry.root, entry.event, 1, opts)
					if entry.result then entry.renderer.finish(entry.result)
					elseif finalMs then entry.renderer.stale() end
				else
					text(entry.root, "UpdateText", entry.event.text, 1)
				end
			end
			local schedule
			schedule = function()
				if pending or destroyed or not visible or not handle.isOpen() then return end
				pending = true
				clock.delay(0.01, function()
					pending = false
					if destroyed or not visible or not handle.isOpen() then return end
					if not taskBuilt then
						taskBuilt = true
						if util.trim(tostring(info.task or "")) ~= "" then
							text(feed, "TaskLabel", "Task", 0, "label", theme.color.textTertiary)
							text(feed, "TaskText", info.task, 1)
						end
						text(feed, "ActivityLabel", "Activity", 2, "label", theme.color.textTertiary)
					end
					local made = 0
					while cursor <= #entries and made < 4 do
						local entry = entries[cursor]; cursor = cursor + 1
						if entry and entry.root.Parent and not entry.mounted then mount(entry); made = made + 1 end
					end
					if cursor <= #entries then schedule() end
				end)
			end
			handle.setOpen, handle.isOpen = bindToggle(head, feed, opts, function(open) if open then schedule() end end)
			function handle.setVisible(value)
				visible = value ~= false
				if visible then schedule() end
			end
			local function append(kind, event)
				slot = slot + 1
				local root = column(feed, kind == "tool" and "SubagentTool" or "SubagentUpdate", slot)
				local entry = { root = root, kind = kind, event = event }
				entries[#entries + 1] = entry
				root.Destroying:Connect(function()
					if entry.id and rows[entry.id] == entry then rows[entry.id] = nil end
					for index, retained in ipairs(entries) do
						if retained == entry then
							table.remove(entries, index)
							if index < cursor then cursor = math.max(1, cursor - 1) end
							break
						end
					end
					entry.event, entry.result, entry.renderer = nil, nil, nil
				end)
				schedule()
				return entry
			end
			local stop = clock.interval(1, function() if not finalMs then paint() end end)
			holder.Destroying:Connect(function()
				destroyed = true
				if stop then stop(); stop = nil end
				rows, entries = {}, {}
			end)
			function handle.status(event)
				local value = util.trim(tostring(event.text or ""))
				if value == "" or value == "Ready" then return end
				lastStatus = value
				summary.TextColor3 = event.bad and theme.color.danger or theme.color.textTertiary
				paint()
			end
			function handle.say(event)
				if util.trim(tostring(event.text or "")) == "" then return nil end
				lastStatus = tostring(event.text); paint()
				return append("text", event)
			end
			function handle.tool(event)
				local id = tostring(event.callId or (calls + 1))
				if rows[id] then return rows[id] end
				calls = math.max(calls + 1, tonumber(event.index) or 0)
				local entry = append("tool", event)
				entry.id, rows[id] = id, entry
				lastStatus = tostring(event.name or "tool") .. " running"
				paint()
				return entry
			end
			function handle.toolDone(event)
				local entry = rows[tostring(event.callId or "")]
				if entry and entry.result then return entry end
				finished = math.max(finished + 1, tonumber(event.finishedCalls) or 0)
				if event.ok == false then failures = failures + 1 end
				if entry then
					entry.result = { ok = event.ok, text = event.summary or event.text or "", ms = event.ms,
						error = event.error, denied = event.denied }
					if entry.renderer then entry.renderer.finish(entry.result) end
				end
				lastStatus = string.format("%s %s", tostring(event.name or (entry and entry.event.name) or "Tool"), event.ok == false and "failed" or "complete")
				paint()
				return entry
			end
			function handle.finish(event)
				calls, finished = math.max(calls, tonumber(event.calls) or 0), math.max(finished, tonumber(event.finishedCalls) or 0)
				finalMs = tonumber(event.ms) or clock.since(started)
				if stop then stop(); stop = nil end
				head.state.Text = event.aborted and "Stopped" or (event.ok == false and "Failed" or "Done")
				head.state.TextColor3 = event.aborted and theme.color.warn or (event.ok == false and theme.color.danger or theme.color.success)
				head.tone(event.ok == false and (event.aborted and theme.color.warn or theme.color.dangerBorder) or nil)
				lastStatus = event.aborted and "Stopped before it finished" or (event.ok == false and "Task failed"
					or (failures > 0 and string.format("Reported back · %d failed tools", failures) or "Reported back"))
				for _, entry in pairs(rows) do if entry.renderer and not entry.result then entry.renderer.stale() end end
				local value = util.trim(tostring(event.text or ""))
				if value ~= "" then
					for _, child in ipairs(report:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
					report.Visible = true
					text(report, "ReportLabel", event.ok == false and "Outcome" or "Report", 1, "label", theme.color.textTertiary)
					local excerpt = text(report, "ReportText", util.ellipsis(value, 560), 2, "small", theme.color.text)
					if #value > 560 then
						local expanded = false
						P.button(report, { name = "ExpandReport", text = "Read full report", variant = "ghost", size = "sm", layoutOrder = 3,
							onClick = function(button)
								if opts.beforeToggle then opts.beforeToggle(button.instance) end
								expanded = not expanded
								excerpt.Text = expanded and value or util.ellipsis(value, 560)
								button.setText(expanded and "Show less" or "Read full report")
							end })
					end
				end
				paint()
			end
			function handle.stale()
				if stop then stop(); stop = nil end
				finalMs = finalMs or clock.since(started)
				head.state.Text, lastStatus = "Unavailable", "No report in the stored transcript."
				for _, entry in pairs(rows) do if entry.renderer and not entry.result then entry.renderer.stale() end end
				paint()
			end
			paint()
			return handle
		end
		return A
	end
	return M
end
