-- Session-owned, bounded multi-file proposals and conditional recovery.
return function(env)
	local fs = env.require("runtime/fsx")
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local source = env.require("runtime/project_source")
	local project = env.require("runtime/script_project")
	local M = {}
	local scope, plans, order, locks = { scope = "files" }, {}, {}, {}
	local serial, bytes = 0, 0
	local function prune()
		for i = #order, 1, -1 do
			local id, item = order[i], plans[order[i]]
			if item and not item.busy and clock.ms() > item.expires then
				bytes, plans[id] = bytes - item.bytes, nil; table.remove(order, i)
			end
		end
	end
	local function stopped(ctx) return ctx and ctx.aborted and ctx.aborted() end
	local function read(path)
		if fs.isDir(path, scope) then return nil, "Target is a directory: " .. path end
		local content, why = fs.read(path, scope)
		if content == nil and fs.exists(path, scope) then return nil, why end
		if content == nil then return false end
		return content
	end
	local function edit(text, edits)
		if type(edits) ~= "table" or not util.isArray(edits) or #edits < 1 or #edits > 20 then return nil, "Use 1-20 exact edits per file" end
		for _, item in ipairs(edits) do
			if type(item) ~= "table" or type(item.old_text) ~= "string" or item.old_text == "" or type(item.new_text) ~= "string" then return nil, "Each edit needs nonempty old_text and string new_text" end
			local first, last = text:find(item.old_text, 1, true)
			if not first then return nil, "Edit text was not found" end
			if text:find(item.old_text, first + 1, true) then return nil, "Edit text is ambiguous; include more context" end
			text = text:sub(1, first - 1) .. item.new_text .. text:sub(last + 1)
			if not source.valid(text) then return nil, "Edited file exceeds UTF-8/text/size limits" end
		end
		return text
	end
	function M.stage(operations, ctx)
		prune()
		if not ctx or not ctx.session then return nil, "A conversation is required for project proposals" end
		if type(operations) ~= "table" or not util.isArray(operations) or #operations < 1 or #operations > 20 then return nil, "Provide 1-20 file operations" end
		if #order >= 8 then return nil, "Eight proposals/checkpoints are retained; discard one with project_patch_discard" end
		local items, seen, size = {}, {}, 0
		for _, operation in ipairs(operations) do
			if type(operation) ~= "table" then return nil, "Each operation must be an object" end
			local path, why = project.path(operation.path); if not path then return nil, why end
			if seen[path:lower()] then return nil, "Duplicate or aliased target: " .. path end
			for target in pairs(seen) do
				local lower = path:lower()
				if lower:sub(1, #target + 1) == target .. "/" or target:sub(1, #lower + 1) == lower .. "/" then return nil, "Targets cannot be each other's parent directories" end
			end
			seen[path:lower()] = true
			local before, err = read(path); if before == nil then return nil, err end
			if before ~= false and not source.valid(before) then return nil, "Existing file exceeds text/size limits: " .. path end
			if before == false then
				if operation.create ~= true or operation.expected_hash then return nil, "New files require create=true and no expected_hash: " .. path end
			elseif operation.create or operation.expected_hash ~= source.hash(before) then return nil, "Read the current file hash before replacing it: " .. path end
			if (operation.content ~= nil) == (operation.edits ~= nil) then return nil, "Provide content or edits, not both" end
			local after = operation.content
			if operation.edits then
				if before == false then return nil, "Cannot edit a missing file" end
				after, err = edit(before, operation.edits); if after == nil then return nil, path .. ": " .. err end
			end
			if not source.valid(after) then return nil, "New content must be UTF-8 text without NUL, at most 256000 bytes" end
			size = size + #(before or "") + #after
			if size > 2 * 1024 * 1024 or bytes + size > 8 * 1024 * 1024 then return nil, "Proposal exceeds the 2 MiB change / 8 MiB retention budget" end
			items[#items + 1] = { path = path, before = before, after = after }
			if stopped(ctx) then return nil, "Proposal cancelled before staging" end
		end
		prune()
		if #order >= 8 or bytes + size > 8 * 1024 * 1024 then return nil, "Proposal retention filled while reading files; discard a checkpoint" end
		serial = serial + 1
		local id = "patch-" .. tostring(clock.ms()) .. "-" .. serial
		local item = { id = id, owner = ctx.session, items = items, bytes = size, status = "proposed", expires = clock.ms() + 600000 }
		plans[id], order[#order + 1], bytes = item, id, bytes + size
		return item
	end
	function M.get(id, ctx)
		prune()
		local plan = plans[id]
		if not plan or not ctx or plan.owner ~= ctx.session then return nil, "Proposal/checkpoint expired, discarded, or belongs to another conversation" end
		return plan
	end
	function M.describe(plan)
		local items = {}
		for _, item in ipairs(plan.items) do
			items[#items + 1] = { path = "files/" .. item.path, created = item.before == false, changed = item.before ~= item.after,
				beforeHash = item.before ~= false and source.hash(item.before) or nil, afterHash = source.hash(item.after),
				beforeBytes = #(item.before or ""), afterBytes = #item.after }
		end
		return { patchId = plan.id, status = plan.status, items = items, expiresAt = plan.expires,
			persistence = "memory only; expires after ten minutes or client unload", atomic = false }
	end
	function M.discard(id, ctx)
		local plan, why = M.get(id, ctx); if not plan then return nil, why end
		if plan.busy then return nil, "Proposal is being applied" end
		plans[id], bytes = nil, bytes - plan.bytes
		for i, key in ipairs(order) do if key == id then table.remove(order, i); break end end
		return { status = "discarded", patchId = id }
	end
	local function mutate(plan, ctx, restore, guard)
		if plan.busy then return nil, "Proposal is already in use" end
		if not restore and plan.status ~= "proposed" then return nil, "Proposal has already been attempted; inspect its checkpoint" end
		if restore and plan.status ~= "applied" and plan.status ~= "partial" then return nil, "Only an applied or partial checkpoint can be restored" end
		for _, item in ipairs(plan.items) do if locks[item.path:lower()] then return nil, "Another project operation owns " .. item.path end end
		plan.busy = true
		for _, item in ipairs(plan.items) do locks[item.path:lower()] = true end
		local ok, result, why = pcall(function()
			if stopped(ctx) then return nil, "Operation cancelled before writing" end
			if guard then local valid, err = guard(plan); if not valid then return nil, err end end
			-- All conflicts are checked before the first write. Check again before each write.
			for _, item in ipairs(plan.items) do
				local current, err = read(item.path); if current == nil then return nil, err end
				local expected = restore and item.after or item.before
				if current ~= expected and not (restore and current == item.before) then return nil, "File changed; no writes made: " .. item.path end
			end
			local changed, failure = 0, nil
			for _, item in ipairs(plan.items) do
				if stopped(ctx) then failure = "Cancelled"; break end
				local expected, target = item.before, item.after
				if restore then expected, target = item.after, item.before end
				local current, err = read(item.path)
				if current == nil then failure = err; break end
				if current ~= target then
					if current ~= expected then failure = "File changed during operation: " .. item.path; break end
					-- Mark before entering a host call: a failed write can still have effects.
					plan.status = "partial"
					local wrote, writeErr
					if target == false then wrote, writeErr = fs.delete(item.path, scope)
					else wrote, writeErr = fs.write(item.path, target, scope) end
					local observed, readErr = read(item.path)
					if not wrote or observed ~= target then failure = tostring(writeErr or readErr or "Write read-back mismatch") .. ": " .. item.path; break end
					changed = changed + 1
				end
			end
			if not failure then plan.status = restore and "restored" or "applied" end
			local report = M.describe(plan)
			report.ok, report.changedCount, report.error = failure == nil, changed, failure
			if failure then report.recovery = "Inspect project_patch_read before/after. Restore only succeeds when files still match recorded versions; unverified partial bytes require explicit repair." end
			return report
		end)
		plan.busy = nil
		for _, item in ipairs(plan.items) do locks[item.path:lower()] = nil end
		if not ok then return nil, tostring(result) end
		return result, why
	end
	function M.apply(plan, ctx, guard) return mutate(plan, ctx, false, guard) end
	function M.restore(plan, ctx, guard) return mutate(plan, ctx, true, guard) end
	env.require("runtime/dispose").add(function() plans, order, locks, bytes = {}, {}, {}, 0 end, "Project proposals")
	return M
end
