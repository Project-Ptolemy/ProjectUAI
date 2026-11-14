-- Micro-goal planning tools retain the normal conversation and permission scope.
return function(env)
	local goals = env.require("runtime/micro_goals")
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")
	local dependencySchema = { type = "array", maxItems = 8, items = { type = "string", minLength = 1, maxLength = 64 } }
	local taskSchema = { type = "object", properties = {
		id = { type = "string", minLength = 1, maxLength = 64, description = "Optional stable task ID when defining dependencies in an initial plan." },
		text = { type = "string", minLength = 1, maxLength = 240 },
		criterion = { type = "string", minLength = 1, maxLength = 600, description = "Observable result required to complete this task." },
		depends_on = dependencySchema,
	}, required = { "text", "criterion" }, additionalProperties = false }
	return {
		{
			name = "micro_goals_read", risk = "read",
			description = "Read this conversation's objective, micro-goals, dependencies, blockers and completion evidence. The JSON body pages by UTF-8 byte offsets. Use returned id and revision as expected_id and expected_revision for continuation pages and every later mutation. A stale continuation is refused; reread from the start after the board changes.",
			parameters = { type = "object", properties = {
				offset = { type = "integer", minimum = 1 }, limit = { type = "integer", minimum = 200, maximum = 12000 },
				expected_id = { type = "string", minLength = 1, maxLength = 64 },
				expected_revision = { type = "integer", minimum = 1 },
			}, required = {}, additionalProperties = false },
			run = function(args, ctx)
				local session = ctx and ctx.session
				if not session or not session.goalsSnapshot then return H.fail("A conversation is required") end
				if ctx.aborted and ctx.aborted() then return H.fail("Stopped before reading micro-goals") end
				local value, why = session.goalsSnapshot()
				if not value then
					if why then return H.fail(why) end
					if args.expected_id or args.expected_revision or (args.offset or 1) > 1 then return H.fail("The previous micro-goals record is no longer present") end
					return { text = "No micro-goals yet. Start an objective when the user's work benefits from focused tasks.", data = { present = false } }
				end
				if (args.expected_id ~= nil) ~= (args.expected_revision ~= nil) then return H.fail("Use both expected_id and expected_revision to bind a read") end
				if (args.offset or 1) > 1 and args.expected_id == nil then return H.fail("Continuation pages require the returned id and revision") end
				if args.expected_id and (args.expected_id ~= value.id or args.expected_revision ~= value.revision) then
					return H.fail("Micro-goals changed; restart the read with the current ID and revision")
				end
				local result = H.readSlice("Micro-goals " .. value.id .. " revision " .. tostring(value.revision), util.encode(value), args, 6000)
				result.data = result.data or {}
				result.data.id, result.data.revision, result.data.status = value.id, value.revision, value.status
				result.data.counts, result.data.present = goals.counts(value), true
				return result
			end,
		},
		{
			name = "micro_goals_update", risk = "write",
			description = "Manage a user-scoped objective with at most 24 focused tasks and one active task. Start with objective and optional tasks. Existing records require their observed expected_id and expected_revision. Add/edit define text, criterion and dependencies; status activates, blocks with blocker, or completes an active task with evidence. Dependencies must be done first. Reopening a completed task or changing its definition invalidates dependent completion. Pause/resume controls this planning board and does not stop running tools. Reorder includes every ID once; remove refuses referenced tasks; complete requires all tasks done; clear explicitly removes the board. This tool never executes or schedules work.",
			examples = { { title = "Break a user objective into focused tasks", arguments = { action = "start", objective = "Build a reusable settings module",
				tasks = { { id = "inspect", text = "Read existing settings and requirements", criterion = "Record exact settings fields and required defaults" },
					{ id = "build", text = "Implement and review the settings module", criterion = "Reviewed source implements the recorded fields", depends_on = { "inspect" } } } } } },
			parameters = { type = "object", properties = {
				action = { type = "string", enum = { "start", "objective", "add", "edit", "status", "reorder", "remove", "pause", "resume", "complete", "clear" } },
				expected_id = { type = "string", minLength = 1, maxLength = 64 },
				expected_revision = { type = "integer", minimum = 0, description = "Current board revision; omitted or zero only for the first start." },
				objective = { type = "string", minLength = 1, maxLength = 2000 },
				tasks = { type = "array", maxItems = 24, items = taskSchema }, task = taskSchema,
				id = { type = "string", minLength = 1, maxLength = 64, description = "Observed task ID for edit/status/remove." },
				text = { type = "string", minLength = 1, maxLength = 240 }, criterion = { type = "string", minLength = 1, maxLength = 600 },
				depends_on = dependencySchema, status = { type = "string", enum = { "pending", "active", "blocked", "done" } },
				evidence = { type = "string", minLength = 1, maxLength = 1600 }, blocker = { type = "string", minLength = 1, maxLength = 800 },
				order = { type = "array", maxItems = 24, items = { type = "string", minLength = 1, maxLength = 64 } },
			}, required = { "action" }, additionalProperties = false },
			run = function(args, ctx)
				local session = ctx and ctx.session
				if not session or not session.updateGoals then return H.fail("A conversation is required") end
				if ctx.aborted and ctx.aborted() then return H.fail("Stopped before updating micro-goals") end
				local value, why, detail = session.updateGoals(args)
				if value == nil then return H.fail(why) end
				if value == false then return { text = "Micro-goals cleared. Running tools and script workflows keep their own lifetime.", data = { cleared = true, persisted = detail and detail.persisted } } end
				return { text = (detail and detail.taskId and ("Updated task " .. detail.taskId .. ".\n") or "") .. goals.describe(value),
					data = { id = value.id, revision = value.revision, status = value.status, counts = goals.counts(value),
						taskId = detail and detail.taskId, persisted = detail and detail.persisted } }
			end,
		},
	}
end
