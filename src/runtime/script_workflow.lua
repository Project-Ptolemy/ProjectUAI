-- Conversation-owned script goals. Persistence is delegated to the session vault.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local M = {}
	M.stages = {
		{ id = "define", label = "Define the goal", hint = "State the result, acceptance criteria and required lifetime." },
		{ id = "inspect", label = "Inspect the environment", hint = "Read relevant source, API capabilities and existing interfaces." },
		{ id = "plan", label = "Plan the script", hint = "Choose modules, UI LIB controls, ownership and cleanup." },
		{ id = "build", label = "Build and review", hint = "Write focused changes and manually review source before checks." },
		{ id = "validate", label = "Validate behavior", hint = "Compile, inspect generated output, run applicable checks and inspect effects." },
		{ id = "review", label = "Review the result", hint = "Check every acceptance criterion; report evidence and remaining limits." },
	}
	local function text(value, maximum)
		return type(value) == "string" and #value <= maximum and util.trim(value) ~= "" and util.validUtf8(value) and not value:find("%z")
	end
	local function finite(value, fallback)
		value = tonumber(value)
		return value and value == value and math.abs(value) < math.huge and value >= 0 and value or fallback
	end
	function M.restore(value)
		if value == nil then return nil end
		if type(value) ~= "table" or value.version ~= 1 or not text(value.goal, 2000) or type(value.criteria) ~= "table"
			or not util.isArray(value.criteria) or #value.criteria < 1 or #value.criteria > 16 then return nil, "Invalid script goal" end
		if type(value.stage) ~= "number" or value.stage ~= math.floor(value.stage) or value.stage < 1 or value.stage > #M.stages
			or (value.status ~= "active" and value.status ~= "blocked" and value.status ~= "complete") then return nil, "Invalid script goal stage" end
		local clean = { version = 1, id = text(value.id, 120) and value.id or "legacy", goal = value.goal, stage = value.stage, status = value.status,
			criteria = {}, notes = {}, receipts = {}, revision = math.floor(finite(value.revision, 0)),
			updatedAt = finite(value.updatedAt, 0), blocker = text(value.blocker, 800) and value.blocker or nil }
		for _, item in ipairs(value.criteria) do
			if type(item) ~= "table" or not text(item.text, 400) or (item.note ~= nil and not text(item.note, 800)) then return nil, "Invalid acceptance criterion" end
			clean.criteria[#clean.criteria + 1] = { text = item.text, done = item.done == true, note = item.note }
		end
		for i = 1, #M.stages do
			local note = type(value.notes) == "table" and value.notes[i]
			if note ~= nil and not text(note, 1600) then return nil, "Invalid workflow evidence" end
			clean.notes[i] = note
		end
		for _, item in ipairs(type(value.receipts) == "table" and value.receipts or {}) do
			if #clean.receipts >= 24 then break end
			if type(item) == "table" and text(item.tool, 100) and type(item.ok) == "boolean" and (item.kind == "syntax" or item.kind == "test") then
				clean.receipts[#clean.receipts + 1] = { tool = item.tool, ok = item.ok, kind = item.kind, at = finite(item.at, 0), revision = finite(item.revision, -1) }
			end
		end
		if clean.status == "complete" then
			for i = 1, #M.stages do if not clean.notes[i] then return nil, "Completed goal is missing stage evidence" end end
			for _, item in ipairs(clean.criteria) do if not item.done or not item.note then return nil, "Completed goal has unchecked criteria" end end
		end
		return clean
	end
	function M.snapshot(value) return M.restore(value) end
	local function save(session, value, deferSave)
		value.updatedAt = clock.ms()
		local clean, why = M.restore(value); if not clean then return nil, why end
		if type(session.setWorkflow) == "function" then
			local ok, err = session.setWorkflow(clean, { deferSave = deferSave == true }); if not ok then return nil, err end
		else session.workflow = clean end
		return clean
	end
	function M.start(session, goal, criteria)
		if not session then return nil, "A conversation is required" end
		if session.workflow and session.workflow.status ~= "complete" then return nil, "A script goal is already active; read it or revise the current work first" end
		if not text(goal, 2000) or type(criteria) ~= "table" or not util.isArray(criteria) or #criteria < 1 or #criteria > 16 then return nil, "Provide a goal and 1–16 acceptance criteria" end
		local value = { version = 1, id = util.uid("script-goal"), goal = goal, stage = 1, status = "active", criteria = {}, notes = {}, receipts = {}, revision = 0 }
		for _, item in ipairs(criteria) do if not text(item, 400) then return nil, "Acceptance criteria must contain 1–400 UTF-8 bytes" end; value.criteria[#value.criteria + 1] = { text = item, done = false } end
		return save(session, value)
	end
	function M.update(session, args)
		local value, why = M.restore(session and session.workflow); if not value then return nil, why or "Start a script goal first" end
		if args.action == "read" then return value end
		if args.action == "block" then
			if not text(args.note, 800) then return nil, "Describe the observed blocker" end
			value.status, value.blocker = "blocked", args.note
		elseif args.action == "resume" then value.status, value.blocker = "active", nil
		elseif args.action == "rewind" then
			local at; for i, stage in ipairs(M.stages) do if stage.id == args.stage then at = i end end
			if not at or at > value.stage then return nil, "Rewind to the current or an earlier stage" end
			value.stage, value.status, value.blocker = at, "active", nil
			for i = at, #M.stages do value.notes[i] = nil end
			for _, item in ipairs(value.criteria) do item.done, item.note = false, nil end
		elseif args.action == "criterion" then
			local index = tonumber(args.criterion)
			if not index or index ~= math.floor(index) or not value.criteria[index] then return nil, "Choose an acceptance criterion number" end
			if not text(args.note, 800) then return nil, "Record the evidence or remaining issue for this criterion" end
			value.criteria[index].done, value.criteria[index].note = args.done == true, args.note
		elseif args.action == "advance" then
			if value.status ~= "active" then return nil, "Resume the blocked goal or rewind completed work first" end
			if not text(args.note, 1600) then return nil, "Record what was done and the evidence before advancing" end
			if value.stage >= 5 then
				local checked, tested = false, nil
				for _, receipt in ipairs(value.receipts) do
					if receipt.revision == value.revision then
						if receipt.kind == "syntax" then checked = receipt.ok else tested = receipt.ok end
					end
				end
				if not checked then return nil, "Run a successful check_luau or script_analyze after the latest source change; record unavailable validation as a blocker" end
				if tested == false then return nil, "The latest test failed; fix it and rerun before completing validation" end
			end
			local completedStage = value.stage
			if value.stage == 6 then
				for _, item in ipairs(value.criteria) do if not item.done or not item.note then return nil, "Review every acceptance criterion and record its evidence before completion" end end
				value.status = "complete"
			else value.stage = value.stage + 1 end
			value.notes[completedStage] = args.note
		else return nil, "Unknown workflow action" end
		return save(session, value)
	end
	local writes = { file_write = true, file_edit = true, file_edit_many = true, file_append = true, file_delete = true,
		code_write = true, code_edit = true, code_transform = true, project_patch_apply = true, project_patch_restore = true }
	function M.capture(session)
		local value = session and session.workflow
		return value and { id = value.id or "legacy", revision = value.revision } or { id = false, revision = -1 }
	end
	function M.invalidate(session)
		local value = M.restore(session and session.workflow); if not value then return end
		value.revision = value.revision + 1; value.receipts = {}
		if value.stage > 4 then value.stage, value.status = 4, "active"; value.notes[4], value.notes[5], value.notes[6] = nil, nil, nil end
		for _, item in ipairs(value.criteria) do item.done, item.note = false, nil end
		return save(session, value, true)
	end
	function M.observe(session, tool, result, started)
		if not session or not session.workflow or tool == "script_workflow" then return end
		local value = M.restore(session.workflow); if not value then return end
		if writes[tool] and (result.ok or result.error == "timeout" or result.error == "error" or result.error == "tool reported a failure") then
			return M.invalidate(session)
		elseif tool == "check_luau" or tool == "script_analyze" or tool == "script_test" then
			if started and started.id ~= value.id then return end
			local data = type(result.data) == "table" and result.data or {}
			local ok = result.ok == true and data.ok ~= false and data.cancelled ~= true and (not data.errors or data.errors == 0)
			if tool == "script_analyze" and not data.compilerAvailable then ok = false end
			local revision = started and started.revision or value.revision
			value.receipts[#value.receipts + 1] = { tool = tool, ok = ok, kind = tool == "script_test" and "test" or "syntax", at = clock.ms(), revision = revision }
			if not ok and revision == value.revision and value.stage >= 5 then
				value.stage, value.status = 5, "active"; value.notes[5], value.notes[6] = nil, nil
			end
			while #value.receipts > 24 do table.remove(value.receipts, 1) end
		else return end
		save(session, value)
	end
	function M.describe(value)
		local clean = M.restore(value); if not clean then return "No script goal is active." end
		local lines = { "Script goal: " .. clean.goal, "Status: " .. clean.status .. " · " .. M.stages[clean.stage].label }
		for index, stage in ipairs(M.stages) do lines[#lines + 1] = index .. ". " .. stage.label .. " — " .. (clean.notes[index] and "reviewed" or index == clean.stage and "current" or "pending") end
		for i, item in ipairs(clean.criteria) do lines[#lines + 1] = (item.done and "[done] " or "[open] ") .. i .. ". " .. item.text end
		if clean.blocker then lines[#lines + 1] = "Blocker: " .. clean.blocker end
		return table.concat(lines, "\n")
	end
	return M
end
