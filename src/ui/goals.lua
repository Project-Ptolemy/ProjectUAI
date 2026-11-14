-- A native planning board. All mutations go through the owning session facade.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local goals = env.require("runtime/micro_goals")
	local sessions = env.require("agent/session")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local overlay = env.require("ui/overlay")
	local drafts = setmetatable({}, { __mode = "k" })
	local opened, unloaded
	local M = {}
	function M.hasDrafts()
		if unloaded then return false end
		for session, draft in pairs(drafts) do
			if not session.removed and draft.dirty then return true end
		end
		return false
	end
	local function label(parent, name, text, order, role)
		return P.text(parent, { name = name, text = text or "", role = role or "small", wrap = true,
			auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = order })
	end
	local function sameForm(a, b) return a and b and a.kind == b.kind and a.taskId == b.taskId end
	local function taskById(value, taskId)
		for _, task in ipairs(value and value.tasks or {}) do if task.id == taskId then return task end end
	end
	local function base(value) return value and { id = value.id, revision = value.revision } or {} end
	local function readable(value)
		if not value then return "No objective is present." end
		local lines = { value.objective, value.status .. " · revision " .. tostring(value.revision) }
		for _, task in ipairs(value.tasks) do
			lines[#lines + 1] = "\n" .. task.text .. " [" .. task.status .. "]\nID: " .. task.id
			lines[#lines + 1] = "Complete when: " .. task.criterion
			if #task.dependsOn > 0 then lines[#lines + 1] = "Prerequisites: " .. table.concat(task.dependsOn, ", ") end
			if task.evidence then lines[#lines + 1] = "Evidence: " .. task.evidence end
			if task.blocker then lines[#lines + 1] = "Blocker: " .. task.blocker end
		end
		return table.concat(lines, "\n")
	end
	function M.open(session)
		session = session or sessions.current()
		if unloaded or not session or session.removed or not session.goalsSnapshot then return nil end
		if opened and not opened.closed then opened.close() end
		local closed, pending, editor, review, modal = false, false, nil, nil, nil
		local unsubscribes, entries = {}, {}
		local current
		local function cleanup()
			if closed then return end
			closed = true
			if review and not review.closed then review.close() end
			if editor and not editor.closed then editor.close() end
			for _, unsubscribe in ipairs(unsubscribes) do unsubscribe() end
			if session.removed or unloaded then drafts[session] = nil end
		end
		modal = overlay.modal({ title = "Micro-goals", description = "Keep a user objective focused. Each task has a result to verify. Pausing this board does not stop running tools.",
			width = theme.size.modalWide, scroll = true, fitContent = true, onClose = cleanup })
		if not modal then return nil end
		opened = modal; modal.card.Name = "MicroGoals"
		local title = label(modal.content, "GoalsObjective", "", 1, "bodyStrong")
		local summary = label(modal.content, "GoalsSummary", "", 2)
		local notice = label(modal.content, "GoalsNotice", "", 3, "caption")
		notice.TextColor3 = theme.color.textSecondary
		local actions = P.row(modal.content, { name = "GoalsActions", auto = "Y", wrap = true,
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 4 })
		local rows = P.column(modal.content, { name = "MicroGoalTasks", auto = "Y", gap = theme.space.sm,
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 5 })
		local empty = label(rows, "GoalsEmpty", "Start an objective, then add small tasks with observable completion criteria.", 1)
		local refresh, openForm
		local function report(why)
			if not closed then notice.Text, notice.TextColor3 = tostring(why), theme.color.warn end
		end
		local function apply(args, observed)
			if closed or session.removed then return nil, "The planning board is closed" end
			args = util.copy(args)
			if observed and observed.id then args.expected_id, args.expected_revision = observed.id, observed.revision end
			local value, why = session.updateGoals(args)
			if value == nil then report(why); return nil, why end
			if not closed then notice.Text, notice.TextColor3 = "", theme.color.textSecondary end
			return value
		end
		local function schedule()
			if closed or pending then return end
			pending = true
			clock.delay(0, function() pending = false; if not closed then refresh() end end)
		end
		local function formValues(draft, value)
			local task = taskById(value, draft.taskId)
			if draft.kind == "start" then return { objective = "" } end
			if draft.kind == "objective" then return { objective = value and value.objective or "" } end
			if draft.kind == "task" then
				return { text = task and task.text or "", criterion = task and task.criterion or "",
					dependencies = task and table.concat(task.dependsOn, ", ") or "" }
			end
			return { result = task and (draft.kind == "evidence" and task.evidence or task.blocker) or "" }
		end
		openForm = function(descriptor, recover)
			if closed then return end
			if editor and not editor.closed then editor.close() end
			local saved = drafts[session]
			if saved and saved.dirty and not sameForm(saved, descriptor) and not recover then
				report("Resume or discard the unfinished form before opening another one."); return
			end
			local value = session.goalsSnapshot()
			local draft = recover and saved or sameForm(saved, descriptor) and saved or {
				kind = descriptor.kind, taskId = descriptor.taskId, base = base(value), values = formValues(descriptor, value), dirty = false }
			if not draft then return end
			drafts[session] = draft
			local fields, fieldLimits, savedForm, form, feedback = {}, {}, false, nil, nil
			local function retain()
				if savedForm or session.removed or unloaded then drafts[session] = nil; return end
				for key, field in pairs(fields) do
					local value = field.get()
					if #value <= fieldLimits[key] and util.validUtf8(value) and not value:find("%z") then draft.values[key] = value end
				end
				if draft.dirty then drafts[session] = draft else drafts[session] = nil end
			end
			local function closeForm()
				retain()
				if review and not review.closed then review.close() end
				schedule()
			end
			local formTitle = draft.kind == "start" and "Start objective" or draft.kind == "objective" and "Edit objective"
				or draft.kind == "task" and (draft.taskId and "Edit micro-goal" or "Add micro-goal")
				or draft.kind == "evidence" and "Record completion evidence" or "Record blocker"
			form = overlay.modal({ title = formTitle, description = draft.taskId or "Changes are saved only when you choose Save.",
				width = theme.size.modalWide, scroll = true, fitContent = true, onClose = closeForm })
			if not form then return end
			editor = form; form.card.Name = "MicroGoalEditor"
			local order = 0
			local function field(key, caption, multiline, height, limit)
				fieldLimits[key] = limit
				order = order + 1; label(form.content, "GoalFieldLabel_" .. key, caption, order, "caption")
				order = order + 1
				fields[key] = P.field(form.content, { name = "GoalField_" .. key, text = draft.values[key], multiline = multiline,
					height = height, layoutOrder = order, onChange = function(text, control)
						if #text > limit or not util.validUtf8(text) or text:find("%z") then
							if feedback then feedback.Text, feedback.TextColor3 = "This field accepts up to " .. tostring(limit) .. " UTF-8 bytes. The previous text was kept.", theme.color.warn end
							control.set(draft.values[key]); return
						end
						if text ~= draft.values[key] then draft.values[key], draft.dirty = text, true end
					end })
			end
			if draft.kind == "start" or draft.kind == "objective" then
				field("objective", "Objective (up to 2,000 bytes)", true, theme.size.promptTextarea, goals.limits.objective)
			elseif draft.kind == "task" then
				field("text", "Task (up to 240 bytes)", false, nil, goals.limits.text)
				field("criterion", "Observable completion criterion (up to 600 bytes)", true, theme.size.control * 3, goals.limits.criterion)
				field("dependencies", "Prerequisite task IDs, separated by commas (up to eight)", false, nil, 1024)
				local names = {}; for _, task in ipairs(value and value.tasks or {}) do names[#names + 1] = task.id .. ": " .. util.ellipsis(task.text, 80) end
				order = order + 1; label(form.content, "GoalDependencyChoices", table.concat(names, "\n"), order, "caption")
			else
				field("result", draft.kind == "evidence" and "Observed result (up to 1,600 bytes)" or "Observed blocker (up to 800 bytes)", true,
					theme.size.promptTextarea, draft.kind == "evidence" and goals.limits.evidence or goals.limits.blocker)
			end
			order = order + 1
			feedback = label(form.content, "GoalEditorNotice", "Changing the objective or a task definition reopens affected completion. Unsaved forms stay in memory until unload.", order, "caption")
			local function showCurrent()
				if form.closed then return end
				local latest = session.goalsSnapshot()
				if review and not review.closed then review.close() end
				review = overlay.modal({ title = "Review current plan", width = theme.size.modalWide, scroll = true, fitContent = true,
					description = "Inspect the current record before keeping your draft against its revision." })
				if not review then return end
				local reviewing = review
				label(review.content, "GoalCurrentRecord", readable(latest), 1)
				P.button(review.footer, { text = "Close", variant = "ghost", size = "sm", onClick = reviewing.close })
				P.button(review.footer, { name = "KeepGoalDraft", text = "Keep draft", variant = "secondary", size = "sm", layoutOrder = 2,
					onClick = function()
						if form.closed then reviewing.close(); return end
						draft.base = base(latest)
						feedback.Text = "Draft kept against the reviewed plan. Save rechecks that revision."
						reviewing.close()
					end })
				P.button(review.footer, { name = "UseCurrentGoal", text = "Use current", variant = "ghost", size = "sm", layoutOrder = 3,
					onClick = function()
						if form.closed then reviewing.close(); return end
						draft.values, draft.base = formValues(draft, latest), base(latest)
						for key, control in pairs(fields) do control.set(draft.values[key]) end
						draft.dirty = false; feedback.Text = "Current fields loaded; Save remains explicit."
						reviewing.close()
					end })
			end
			P.button(form.footer, { name = "CloseGoalEditor", text = "Close", variant = "ghost", size = "sm", onClick = form.close })
			P.button(form.footer, { name = "ReviewGoalCurrent", text = "Review current", variant = "secondary", size = "sm", layoutOrder = 2, onClick = showCurrent })
			P.button(form.footer, { name = "SaveGoalForm", text = "Save", variant = "primary", size = "sm", layoutOrder = 3,
				onClick = function()
					if form.closed then return end
					local args
					if draft.kind == "start" or draft.kind == "objective" then args = { action = draft.kind, objective = fields.objective.get() }
					elseif draft.kind == "task" then
						local dependencies = {}; for dependency in fields.dependencies.get():gmatch("[^,%s]+") do dependencies[#dependencies + 1] = dependency end
						local task = { text = fields.text.get(), criterion = fields.criterion.get(), depends_on = dependencies }
						if draft.taskId then args = { action = "edit", id = draft.taskId, text = task.text, criterion = task.criterion, depends_on = dependencies }
						else args = { action = "add", task = task } end
					else
						args = { action = "status", id = draft.taskId, status = draft.kind == "evidence" and "done" or "blocked" }
						args[draft.kind == "evidence" and "evidence" or "blocker"] = fields.result.get()
					end
					local result, why = apply(args, draft.base)
					if result == nil then feedback.Text, feedback.TextColor3 = tostring(why), theme.color.warn
					else savedForm = true; drafts[session] = nil; form.close() end
				end })
			schedule()
		end
		local objective = P.button(actions, { name = "EditGoalsObjective", text = "Start objective", variant = "primary", size = "sm",
			onClick = function() openForm({ kind = (not current or current.status == "complete") and "start" or "objective" }) end })
		local add = P.button(actions, { name = "AddMicroGoal", text = "Add task", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() openForm({ kind = "task" }) end })
		local pause = P.button(actions, { name = "PauseMicroGoals", text = "Pause", variant = "ghost", size = "sm", layoutOrder = 3,
			onClick = function() if current then apply({ action = current.status == "paused" and "resume" or "pause" }, current) end end })
		local resumeForm = P.button(actions, { name = "ResumeGoalForm", text = "Resume form", variant = "ghost", size = "sm", layoutOrder = 4,
			onClick = function() local draft = drafts[session]; if draft then openForm(draft, true) end end })
		local discardForm = P.button(actions, { name = "DiscardGoalForm", text = "Discard form", variant = "ghost", size = "sm", layoutOrder = 5,
			onClick = function() drafts[session] = nil; schedule() end })
		local complete = P.button(modal.footer, { name = "CompleteMicroGoals", text = "Complete objective", variant = "secondary", size = "sm",
			onClick = function() if current then apply({ action = "complete" }, current) end end })
		local clear = P.button(modal.footer, { name = "ClearMicroGoals", text = "Clear plan", variant = "ghost", size = "sm", layoutOrder = 2,
			onClick = function()
				local observed = current
				if not observed then return end
				overlay.confirm({ title = "Clear this plan?", description = "Remove this objective and its task evidence. Running tools keep their own lifetime.",
					confirmText = "Clear plan", danger = true, onConfirm = function() apply({ action = "clear" }, observed) end })
			end })
		P.button(modal.footer, { name = "CloseMicroGoals", text = "Close", variant = "ghost", size = "sm", layoutOrder = 3, onClick = modal.close })
		local function makeEntry(task)
			local entry = {}
			entry.card = P.card(rows, { name = "MicroGoal_" .. task.id, gap = theme.space.xs, padding = theme.space.md })
			entry.heading = label(entry.card, "MicroGoalHeading", "", 1, "bodyStrong")
			entry.criterion = label(entry.card, "MicroGoalCriterion", "", 2)
			entry.result = label(entry.card, "MicroGoalResult", "", 3, "caption")
			local buttons = P.row(entry.card, { name = "MicroGoalActions", auto = "Y", wrap = true,
				size = UDim2.new(1, 0, 0, 0), gap = theme.space.xxs, layoutOrder = 4 })
			P.button(buttons, { name = "ReadMicroGoal_" .. task.id, text = "Details", variant = "ghost", size = "sm", layoutOrder = -1,
				onClick = function()
					if closed or not current then return end
					if review and not review.closed then review.close() end
					review = overlay.modal({ title = "Micro-goal details", width = theme.size.modalWide, scroll = true, fitContent = true })
					if not review then return end
					local viewing = review
					label(review.content, "FullMicroGoal", readable({ objective = entry.task.text, status = entry.task.status,
						revision = current.revision, tasks = { entry.task } }), 1)
					P.button(review.footer, { text = "Close", variant = "ghost", size = "sm", onClick = viewing.close })
				end })
			entry.edit = P.button(buttons, { name = "EditMicroGoal_" .. task.id, text = "Edit", variant = "ghost", size = "sm",
				onClick = function() openForm({ kind = "task", taskId = entry.task.id }) end })
			entry.start = P.button(buttons, { name = "StartMicroGoal_" .. task.id, text = "Start", variant = "ghost", size = "sm", layoutOrder = 2,
				onClick = function() apply({ action = "status", id = entry.task.id,
					status = (entry.task.status == "done" or entry.task.status == "active") and "pending" or "active" }, current) end })
			entry.done = P.button(buttons, { name = "FinishMicroGoal_" .. task.id, text = "Complete", variant = "ghost", size = "sm", layoutOrder = 3,
				onClick = function() openForm({ kind = "evidence", taskId = entry.task.id }) end })
			entry.block = P.button(buttons, { name = "BlockMicroGoal_" .. task.id, text = "Block", variant = "ghost", size = "sm", layoutOrder = 4,
				onClick = function() openForm({ kind = "blocker", taskId = entry.task.id }) end })
			local function move(direction)
				if not current then return end
				local order = {}; for _, item in ipairs(current.tasks) do order[#order + 1] = item.id end
				local other = entry.index + direction
				if other < 1 or other > #order then return end
				order[entry.index], order[other] = order[other], order[entry.index]
				apply({ action = "reorder", order = order }, current)
			end
			entry.up = P.button(buttons, { name = "MoveMicroGoalUp_" .. task.id, text = "Move up", variant = "ghost", size = "sm", layoutOrder = 5, onClick = function() move(-1) end })
			entry.down = P.button(buttons, { name = "MoveMicroGoalDown_" .. task.id, text = "Move down", variant = "ghost", size = "sm", layoutOrder = 6, onClick = function() move(1) end })
			P.button(buttons, { name = "RemoveMicroGoal_" .. task.id, text = "Remove", variant = "ghost", size = "sm", layoutOrder = 7,
				onClick = function()
					local observed, taskId = current, entry.task.id
					overlay.confirm({ title = "Remove this task?", description = entry.task.text, confirmText = "Remove", danger = true,
						onConfirm = function() apply({ action = "remove", id = taskId }, observed) end })
				end })
			return entry
		end
		refresh = function()
			if closed then return end
			current = session.goalsSnapshot()
			local counts = goals.counts(current)
			title.Text = current and current.objective or "No focused objective yet"
			summary.Text = current and string.format("%s · %d of %d tasks complete · revision %d", current.status, counts.done, counts.total, current.revision) or session.title
			objective.setText(not current and "Start objective" or current.status == "complete" and "New objective" or "Edit objective")
			add.setEnabled(current ~= nil and counts.total < goals.limits.tasks)
			pause.setEnabled(current ~= nil and current.status ~= "complete"); pause.setText(current and current.status == "paused" and "Resume" or "Pause")
			complete.setEnabled(current ~= nil and current.status == "active" and counts.total > 0 and counts.done == counts.total)
			clear.setEnabled(current ~= nil)
			local draft = drafts[session]
			resumeForm.instance.Visible, discardForm.instance.Visible = draft and draft.dirty and true or false, draft and draft.dirty and true or false
			empty.Visible = counts.total == 0
			if notice.TextColor3 ~= theme.color.warn then notice.Text = "Saved with this conversation when executor storage is available. Unsaved forms do not survive unload." end
			local keep = {}
			for index, task in ipairs(current and current.tasks or {}) do
				local entry = entries[task.id] or makeEntry(task); entries[task.id], keep[task.id] = entry, true
				entry.task, entry.index, entry.card.LayoutOrder = task, index, index
				entry.heading.Text = tostring(index) .. ". " .. task.text .. " [" .. task.status .. "]"
				entry.criterion.Text = "Complete when: " .. task.criterion
				local details = { "ID: " .. task.id }
				if #task.dependsOn > 0 then details[#details + 1] = "Prerequisites: " .. table.concat(task.dependsOn, ", ") end
				if task.evidence then details[#details + 1] = "Evidence: " .. util.ellipsis(task.evidence, 400) end
				if task.blocker then details[#details + 1] = "Blocker: " .. task.blocker end
				entry.result.Text = table.concat(details, "\n")
				local running = current.status == "active"
				entry.start.setText(task.status == "done" and "Reopen" or task.status == "active" and "Return to pending" or task.status == "blocked" and "Resume task" or "Start")
				entry.start.setEnabled((running or current.status == "complete" and task.status == "done") and (counts.active == 0 or task.status == "active" or task.status == "done"))
				entry.done.setEnabled(running and task.status == "active")
				entry.block.setEnabled(running and task.status ~= "done")
				entry.up.setEnabled(index > 1); entry.down.setEnabled(index < counts.total)
			end
			for taskId, entry in pairs(entries) do if not keep[taskId] then entry.card:Destroy(); entries[taskId] = nil end end
		end
		unsubscribes[#unsubscribes + 1] = session.events:connect(function(event) if event.kind == "goals:changed" or event.kind == "cleared" then schedule() end end)
		unsubscribes[#unsubscribes + 1] = sessions.listChanged:connect(function() if session.removed then modal.close() else schedule() end end)
		refresh()
		return modal
	end
	dispose.add(function()
		unloaded = true
		if opened and not opened.closed then opened.close() end
		drafts = setmetatable({}, { __mode = "k" })
	end, "micro-goal forms")
	return M
end
