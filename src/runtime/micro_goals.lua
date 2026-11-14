-- Bounded, conversation-owned planning records. No execution or retry scheduler.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local M = {}
	M.limits = { tasks = 24, dependencies = 8, objective = 2000, text = 240,
		criterion = 600, evidence = 1600, blocker = 800, prompt = 2400 }
	local statuses = { pending = true, active = true, blocked = true, done = true }
	local transitions = { pending = { active = true, blocked = true },
		active = { pending = true, blocked = true, done = true },
		blocked = { pending = true, active = true }, done = { pending = true } }
	local function text(value, limit)
		return type(value) == "string" and #value <= limit and util.trim(value) ~= ""
			and util.validUtf8(value) and not value:find("%z")
	end
	local function id(value)
		return type(value) == "string" and #value <= 64 and value:match("^[%w_-]+$") ~= nil
	end
	local function integer(value, minimum)
		return type(value) == "number" and value == value and value < 9007199254740991
			and value >= minimum and value == math.floor(value)
	end
	local function array(value, maximum)
		if type(value) ~= "table" or #value > maximum then return false end
		local count = 0
		for key in pairs(value) do
			count = count + 1
			if count > maximum or not integer(key, 1) or key > #value then return false end
		end
		return count == #value
	end
	local function dependencies(value)
		if not array(value, M.limits.dependencies) then return nil, "Provide at most eight dependency IDs" end
		local out, seen = {}, {}
		for _, dependency in ipairs(value) do
			if not id(dependency) or seen[dependency] then return nil, "Dependency IDs must be valid and unique" end
			seen[dependency] = true; out[#out + 1] = dependency
		end
		return out
	end
	local function graph(tasks)
		local known, active = {}, 0
		for _, task in ipairs(tasks) do
			if known[task.id] then return nil, "Task IDs must be unique" end
			known[task.id] = task
			if task.status == "active" then active = active + 1 end
		end
		if active > 1 then return nil, "Focus on one active micro-goal at a time" end
		for _, task in ipairs(tasks) do
			for _, dependency in ipairs(task.dependsOn) do
				if dependency == task.id then return nil, "A task cannot depend on itself" end
				if not known[dependency] then return nil, "Unknown dependency: " .. dependency end
				if (task.status == "active" or task.status == "done") and known[dependency].status ~= "done" then
					return nil, "Complete dependency " .. dependency .. " before activating or completing " .. task.id
				end
			end
		end
		local visiting, visited = {}, {}
		local function visit(taskId)
			if visiting[taskId] then return false end
			if visited[taskId] then return true end
			visiting[taskId] = true
			for _, dependency in ipairs(known[taskId].dependsOn) do if not visit(dependency) then return false end end
			visiting[taskId], visited[taskId] = nil, true
			return true
		end
		for _, task in ipairs(tasks) do if not visit(task.id) then return nil, "Micro-goal dependencies contain a cycle" end end
		return known
	end
	function M.restore(value)
		if value == nil then return nil end
		if type(value) ~= "table" or value.version ~= 1 or not id(value.id)
			or not text(value.objective, M.limits.objective) or not integer(value.revision, 1)
			or (value.status ~= "active" and value.status ~= "paused" and value.status ~= "complete")
			or not array(value.tasks, M.limits.tasks) then return nil, "Invalid micro-goals record" end
		local clean = { version = 1, id = value.id, objective = value.objective, status = value.status,
			revision = value.revision, tasks = {}, updatedAt = integer(value.updatedAt, 0) and value.updatedAt or 0 }
		for _, task in ipairs(value.tasks) do
			if type(task) ~= "table" or not id(task.id) or not text(task.text, M.limits.text)
				or not text(task.criterion, M.limits.criterion) or not statuses[task.status]
				or (task.evidence ~= nil and not text(task.evidence, M.limits.evidence))
				or (task.blocker ~= nil and not text(task.blocker, M.limits.blocker)) then return nil, "Invalid micro-goal task" end
			if task.status == "done" and not task.evidence then return nil, "Completed tasks require result evidence" end
			if task.status == "blocked" and not task.blocker then return nil, "Blocked tasks require a reason" end
			if task.status ~= "done" and task.evidence ~= nil or task.status ~= "blocked" and task.blocker ~= nil then
				return nil, "Evidence and blockers must match the task's status"
			end
			local dependsOn, why = dependencies(task.dependsOn)
			if not dependsOn then return nil, why end
			clean.tasks[#clean.tasks + 1] = { id = task.id, text = task.text, criterion = task.criterion,
				status = task.status, dependsOn = dependsOn, evidence = task.evidence, blocker = task.blocker }
		end
		local known, why = graph(clean.tasks); if not known then return nil, why end
		if clean.status == "complete" then
			if #clean.tasks == 0 then return nil, "A completed objective needs completed tasks" end
			for _, task in ipairs(clean.tasks) do if task.status ~= "done" then return nil, "Complete every task before completing the objective" end end
		end
		return clean
	end
	function M.snapshot(value) return M.restore(value) end
	local function newTask(value)
		if type(value) ~= "table" then return nil, "Provide a task with text and a completion criterion" end
		for key in pairs(value) do
			if key ~= "id" and key ~= "text" and key ~= "criterion" and key ~= "depends_on" then return nil, "Unknown new-task field: " .. tostring(key) end
		end
		if not text(value.text, M.limits.text) or not text(value.criterion, M.limits.criterion) then
			return nil, "Tasks need text (1–240 bytes) and a completion criterion (1–600 bytes)"
		end
		if value.id ~= nil and not id(value.id) then return nil, "Invalid task ID" end
		local dependsOn, why = dependencies(value.depends_on or {})
		if not dependsOn then return nil, why end
		return { id = value.id or util.uid("task"), text = util.trim(value.text), criterion = util.trim(value.criterion),
			status = "pending", dependsOn = dependsOn }
	end
	local fields = {
		start = { objective = true, tasks = true }, objective = { objective = true },
		add = { task = true }, edit = { id = true, text = true, criterion = true, depends_on = true },
		status = { id = true, status = true, evidence = true, blocker = true },
		reorder = { order = true }, remove = { id = true }, pause = {}, resume = {}, complete = {}, clear = {},
	}
	local function reopen(value, taskId)
		local affected = { [taskId] = true }
		for _ = 1, #value.tasks do
			local changed = false
			for _, task in ipairs(value.tasks) do
				if not affected[task.id] then
					for _, dependency in ipairs(task.dependsOn) do
						if affected[dependency] then affected[task.id], changed = true, true; break end
					end
				end
			end
			if not changed then break end
		end
		for _, task in ipairs(value.tasks) do
			if affected[task.id] then task.status, task.evidence, task.blocker = "pending", nil, nil end
		end
		if value.status == "complete" then value.status = "active" end
	end
	function M.change(value, args)
		if type(args) ~= "table" or not fields[args.action] then return nil, "Choose a micro-goals action" end
		local allowed = fields[args.action]
		for key in pairs(args) do
			if key ~= "action" and key ~= "expected_id" and key ~= "expected_revision" and not allowed[key] then
				return nil, "Unexpected field for " .. args.action .. ": " .. tostring(key)
			end
		end
		local clean, why = M.restore(value)
		if value ~= nil and not clean then return nil, why end
		if clean then
			if args.expected_id ~= clean.id or args.expected_revision ~= clean.revision then
				return nil, "Micro-goals changed; read their current ID and revision before updating"
			end
		elseif args.expected_id ~= nil or args.expected_revision ~= nil and args.expected_revision ~= 0 then
			return nil, "The previous micro-goals record is no longer present"
		end
		local detail = {}
		if args.action == "start" then
			if clean and clean.status ~= "complete" then return nil, "An objective is already active; edit it or explicitly clear it first" end
			if not text(args.objective, M.limits.objective) then return nil, "Provide an objective of 1–2,000 UTF-8 bytes" end
			local tasks = args.tasks or {}
			if not array(tasks, M.limits.tasks) then return nil, "Provide at most 24 micro-goals" end
			local previousId, nextId = clean and clean.id, util.uid("goals")
			if nextId == previousId then nextId = util.uid("goals") end
			clean = { version = 1, id = nextId, objective = util.trim(args.objective), status = "active", revision = 0, tasks = {} }
			for _, task in ipairs(tasks) do
				local created, errorText = newTask(task); if not created then return nil, errorText end
				clean.tasks[#clean.tasks + 1] = created
			end
		elseif args.action == "clear" then
			return false, nil, { cleared = true }
		elseif not clean then
			return nil, "Start an objective first"
		elseif args.action == "objective" then
			if not text(args.objective, M.limits.objective) then return nil, "Provide an objective of 1–2,000 UTF-8 bytes" end
			local objective = util.trim(args.objective)
			if objective ~= clean.objective then
				clean.objective = objective
				for _, task in ipairs(clean.tasks) do task.status, task.evidence, task.blocker = "pending", nil, nil end
				if clean.status == "complete" then clean.status = "active" end
			end
		elseif args.action == "add" then
			if #clean.tasks >= M.limits.tasks then return nil, "This objective already has 24 micro-goals" end
			local task, errorText = newTask(args.task); if not task then return nil, errorText end
			clean.tasks[#clean.tasks + 1] = task; detail.taskId = task.id
			if clean.status == "complete" then clean.status = "active" end
		elseif args.action == "pause" then
			if clean.status ~= "active" then return nil, "Only an active objective can be paused" end
			clean.status = "paused"
		elseif args.action == "resume" then
			if clean.status ~= "paused" then return nil, "Only a paused objective can be resumed" end
			clean.status = "active"
		elseif args.action == "complete" then
			if clean.status ~= "active" then return nil, "Resume the objective before completing it" end
			if #clean.tasks == 0 then return nil, "Add and complete micro-goals before completing the objective" end
			for _, task in ipairs(clean.tasks) do if task.status ~= "done" then return nil, "Complete every micro-goal with evidence first" end end
			clean.status = "complete"
		elseif args.action == "reorder" then
			if not array(args.order, M.limits.tasks) or #args.order ~= #clean.tasks then return nil, "The order must include every task ID exactly once" end
			local known = {}; for _, task in ipairs(clean.tasks) do known[task.id] = task end
			local ordered = {}
			for _, taskId in ipairs(args.order) do
				if not id(taskId) or not known[taskId] then return nil, "The order contains an unknown or duplicate task ID" end
				ordered[#ordered + 1], known[taskId] = known[taskId], nil
			end
			clean.tasks = ordered
		else
			local task, index
			for at, candidate in ipairs(clean.tasks) do if candidate.id == args.id then task, index = candidate, at; break end end
			if not task then return nil, "Read a current micro-goal task ID" end
			detail.taskId = task.id
			if args.action == "remove" then
				for _, other in ipairs(clean.tasks) do
					for _, dependency in ipairs(other.dependsOn) do if dependency == task.id then return nil, "Remove references to this task before removing it" end end
				end
				table.remove(clean.tasks, index)
				if clean.status == "complete" and #clean.tasks == 0 then clean.status = "active" end
			elseif args.action == "edit" then
				if args.text == nil and args.criterion == nil and args.depends_on == nil then return nil, "Provide task text, criterion or dependencies to edit" end
				local previousText, previousCriterion, previousDependencies = task.text, task.criterion, table.concat(task.dependsOn, "\n")
				if args.text ~= nil then
					if not text(args.text, M.limits.text) then return nil, "Task text must contain 1–240 UTF-8 bytes" end
					task.text = util.trim(args.text)
				end
				if args.criterion ~= nil then
					if not text(args.criterion, M.limits.criterion) then return nil, "A criterion must contain 1–600 UTF-8 bytes" end
					task.criterion = util.trim(args.criterion)
				end
				if args.depends_on ~= nil then
					local dependsOn, errorText = dependencies(args.depends_on); if not dependsOn then return nil, errorText end
					task.dependsOn = dependsOn
				end
				if task.text ~= previousText or task.criterion ~= previousCriterion or table.concat(task.dependsOn, "\n") ~= previousDependencies then
					reopen(clean, task.id)
				end
			elseif args.action == "status" then
				local reopening = clean.status == "complete" and task.status == "done" and args.status == "pending"
				if clean.status ~= "active" and not reopening then return nil, "Resume an active objective before changing task status" end
				if not statuses[args.status] then return nil, "Choose pending, active, blocked or done" end
				if task.status ~= args.status and not transitions[task.status][args.status] then
					return nil, "Activate a pending or blocked task before completing it; reopen completed tasks to pending"
				end
				if args.status == "done" then
					if not text(args.evidence, M.limits.evidence) or args.blocker ~= nil then return nil, "Completed tasks require result evidence and no blocker" end
					task.status, task.evidence, task.blocker = "done", util.trim(args.evidence), nil
				elseif args.status == "blocked" then
					if not text(args.blocker, M.limits.blocker) or args.evidence ~= nil then return nil, "Blocked tasks require a reason and no completion evidence" end
					task.status, task.blocker, task.evidence = "blocked", util.trim(args.blocker), nil
				else
					if args.evidence ~= nil or args.blocker ~= nil then return nil, "Pending and active tasks cannot have completion evidence or a blocker" end
					if args.status == "pending" and task.status == "done" then reopen(clean, task.id)
					else task.status, task.evidence, task.blocker = args.status, nil, nil end
				end
			end
		end
		clean.revision = clean.revision + 1
		clean.updatedAt = math.floor(clock.ms())
		local validated, errorText = M.restore(clean)
		if not validated then return nil, errorText end
		return validated, nil, detail
	end
	function M.counts(value)
		local clean = M.restore(value)
		local counts = { total = 0, pending = 0, active = 0, blocked = 0, done = 0 }
		if clean then
			counts.total = #clean.tasks
			for _, task in ipairs(clean.tasks) do counts[task.status] = counts[task.status] + 1 end
		end
		return counts
	end
	function M.describe(value)
		local clean = M.restore(value); if not clean then return nil end
		local lines = { string.format("Micro-goals %s revision %d (%s)", clean.id, clean.revision, clean.status),
			"Objective: " .. util.encode(util.ellipsis(clean.objective, 400)) }
		local bytes, shown = #table.concat(lines, "\n"), 0
		for _, task in ipairs(clean.tasks) do
			local line = "- " .. task.id .. " [" .. task.status .. "] " .. util.encode(util.ellipsis(task.text, 100))
			if #task.dependsOn > 0 then line = line .. " after " .. table.concat(task.dependsOn, ",") end
			if bytes + #line + 1 > M.limits.prompt - 140 then break end
			lines[#lines + 1] = line; bytes, shown = bytes + #line + 1, shown + 1
		end
		if shown < #clean.tasks then lines[#lines + 1] = tostring(#clean.tasks - shown) .. " more tasks." end
		lines[#lines + 1] = "Use micro_goals_read for full criteria, evidence and current IDs before edits."
		return table.concat(lines, "\n")
	end
	return M
end
