-- A durable, visible script-making goal; it never executes source or grants access.
return function(env)
	local workflow = env.require("runtime/script_workflow")
	local H = env.require("tools/helpers")
	return { {
		name = "script_workflow", group = "coding", risk = "write",
		description = "Track a substantial script-making goal step by step: define, inspect, plan, build, validate, review. Start with goal and acceptance criteria. Read to resume; advance requires an evidence note. Criterion records a checked outcome; block records a real obstacle; rewind reopens work. Completion requires all criteria and a successful recorded syntax check after the last source change. This tool does not build or run source.",
		parameters = { type = "object", properties = {
			action = { type = "string", enum = { "start", "read", "advance", "criterion", "block", "resume", "rewind" } },
			goal = { type = "string", minLength = 1, maxLength = 2000 },
			criteria = { type = "array", minItems = 1, maxItems = 16, items = { type = "string", minLength = 1, maxLength = 400 } },
			note = { type = "string", minLength = 1, maxLength = 1600 },
			criterion = { type = "integer", minimum = 1, maximum = 16 }, done = { type = "boolean" },
			stage = { type = "string", enum = { "define", "inspect", "plan", "build", "validate", "review" } },
		}, required = { "action" }, additionalProperties = false },
		run = function(args, ctx)
			local session = ctx and ctx.session
			if not session then return H.fail("A conversation is required") end
			local value, why
			if args.action == "start" then value, why = workflow.start(session, args.goal, args.criteria)
			else value, why = workflow.update(session, args) end
			if not value then return H.fail(why) end
			return { text = workflow.describe(value), data = { stage = workflow.stages[value.stage].id, status = value.status, goal = value.goal, criteria = value.criteria, notes = value.notes, receipts = value.receipts } }
		end,
	} }
end
