-- Shared machinery for the tool groups: path resolution, value conversion in both
-- directions, and the formatting conventions every tool result follows.
--
-- Two rules drive the design. Model output is untrusted text, so a path or a
-- property value is parsed rather than trusted. And a tool result is read by a
-- model, not a person, so it is dense, labelled, and bounded -- a wall of
-- unlabelled values costs tokens and teaches nothing.
return function(env)
	local util = env.require("runtime/util")

	local H = {}

	-- Paths ------------------------------------------------------------------

	local paths = env.require("runtime/instance_paths")
	H.resolve, H.pathOf, H.ROOT_NAMES = paths.resolve, paths.pathOf, paths.ROOT_NAMES

	local legacy = env.require("runtime/legacy_values")
	H.show, H.coerce = legacy.show, legacy.coerce

	-- Formatting -------------------------------------------------------------

	function H.describe(instance, countChildren)
		if not instance then return "nil" end
		local extra = {}
		local ok = pcall(function()
			if instance:IsA("BasePart") then
				extra[#extra + 1] = "at " .. H.show(instance.Position)
			elseif instance:IsA("GuiObject") then
				extra[#extra + 1] = "size " .. H.show(instance.Size)
			elseif instance:IsA("Humanoid") then
				extra[#extra + 1] = string.format("health %s/%s", H.show(instance.Health), H.show(instance.MaxHealth))
			end
		end)
		local childCount = 0
		if countChildren ~= false then pcall(function() childCount = #instance:GetChildren() end) end
		if childCount > 0 then extra[#extra + 1] = util.pluralise(childCount, "child") end
		return string.format("%s [%s]%s", instance.Name, instance.ClassName,
			(ok and #extra > 0) and (" " .. table.concat(extra, ", ")) or "")
	end

	-- Numbered list with an explicit note when it was cut short, so a model can
	-- tell "that is everything" from "there is more".
	function H.list(items, limit, render)
		local lines = {}
		local shown = math.min(#items, limit or #items)
		for index = 1, shown do
			lines[#lines + 1] = string.format("%d. %s", index, render and render(items[index], index) or tostring(items[index]))
		end
		if #items > shown then
			lines[#lines + 1] = string.format("... %d more (narrow the query to see them)", #items - shown)
		end
		if #lines == 0 then return "(none)" end
		return table.concat(lines, "\n")
	end

	function H.keyValues(pairsList)
		local lines = {}
		for _, entry in ipairs(pairsList) do
			lines[#lines + 1] = entry[1] .. ": " .. tostring(entry[2])
		end
		return table.concat(lines, "\n")
	end

	function H.limit(value, fallback, ceiling)
		local number = tonumber(value) or fallback
		if type(number) ~= "number" or number ~= number or math.abs(number) == math.huge then number = fallback or 1 end
		return math.floor(util.clamp(number, 1, ceiling or 200))
	end

	-- A contiguous, resumable slice. Leave room for its cursor inside the registry's
	-- result budget so a second truncation cannot silently remove the middle.
	function H.resultBudget()
		local value = tonumber(env.require("runtime/config").get("agent.resultCap", 4000))
		if not value or value ~= value or math.abs(value) == math.huge then return 4000 end
		return math.floor(util.clamp(value, 0, 128000))
	end

	-- Page already-collected rows without formatting or copying the omitted tail.
	-- Keep metadata out of the row text so the model sees each payload only once.
	function H.page(items, args, title, render, defaultLimit, maximum)
		args = args or {}
		local offset = H.limit(args.offset, 1, #items + 1)
		if tonumber(args.offset) and tonumber(args.offset) > #items + 1 then return H.fail("offset is past the end of this listing") end
		local budget = H.resultBudget() - 320
		if budget < 128 then return H.fail("increase the tool result budget to at least 448 bytes before listing results") end
		local lines, bytes, nextOffset = {}, #title + 1, nil
		local limit = H.limit(args.limit, defaultLimit or 25, maximum or 100)
		for index = offset, math.min(#items, offset + limit - 1) do
			local line = tostring(render and render(items[index], index) or items[index])
			line = tostring(index) .. ". " .. line
			if bytes + #line + 1 > budget then
				if #lines == 0 then return H.fail("one listing row exceeds the result budget; increase it or narrow the requested fields") end
				nextOffset = index; break
			end
			lines[#lines + 1] = line; bytes = bytes + #line + 1
		end
		if not nextOffset and offset + #lines <= #items then nextOffset = offset + #lines end
		return { text = title .. (#lines > 0 and ("\n" .. table.concat(lines, "\n")) or "\n(none)"),
			data = { offset = offset, count = #lines, total = #items, remaining = math.max(0, #items - offset - #lines + 1), nextOffset = nextOffset, eof = nextOffset == nil } }
	end

	function H.readSlice(name, content, args, defaultLimit, budget)
		args = args or {}
		local cap = math.min(H.resultBudget(), budget or math.huge)
		if cap < 256 then return H.fail("increase the tool result budget to at least 256 bytes before reading files") end
		local requested = tonumber(args.offset) or 1
		if requested ~= requested or math.abs(requested) == math.huge then return H.fail("offset must be a finite byte position") end
		local offset = math.max(1, math.floor(requested))
		if offset > #content + 1 then return H.fail("offset is past the end; this source has " .. #content .. " bytes") end
		while offset > 1 do
			local byte = content:byte(offset)
			if not byte or byte < 128 or byte >= 192 then break end
			offset = offset - 1
		end
		local label = util.ellipsis(name, 100)
		local limit = H.limit(args.limit, defaultLimit or 6000, cap - 220)
		local last = math.min(#content, offset + math.floor(limit) - 1)
		while last >= offset and last < #content do
			local byte = content:byte(last + 1)
			if byte < 128 or byte >= 192 then break end
			last = last - 1
		end
		if last < offset and offset <= #content then
			last = offset
			while last < #content and content:byte(last + 1) >= 128 and content:byte(last + 1) < 192 do last = last + 1 end
		end
		local nextOffset = last < #content and last + 1 or nil
		local header = string.format("%s (bytes %d-%d of %d%s):\n", label, offset, last, #content,
			nextOffset and ("; continue with offset=" .. nextOffset) or "; end of file")
		if #content == 0 then header = label .. " (empty, 0 bytes):\n" end
		return { text = header .. content:sub(offset, last), data = {
			offset = offset, nextOffset = nextOffset, totalBytes = #content, eof = nextOffset == nil,
		} }
	end

	-- A tool that could not do what was asked returns this rather than a bare
	-- string, so the registry can mark the call as failed and the transcript can
	-- colour it. The model sees the same sentence either way.
	function H.fail(message)
		return { ok = false, text = "Failed: " .. tostring(message) }
	end

	-- A tool that changed something says what it changed and where, because the
	-- next turn often needs the path again.
	function H.changed(what, where, detail)
		return string.format("%s on %s%s", what, where, detail and (" -> " .. detail) or "")
	end

	-- Small property batches preflight every read, then report each observed write.
	-- Engine effects are not atomic and are never described as rolled back.
	function H.writeProperties(target, edits, label, ctx)
		if #edits == 0 then return H.fail("pass at least one value to change") end
		for _, edit in ipairs(edits) do
			local ok, value = pcall(function() return target[edit.property] end)
			if not ok or value == nil then return H.fail("could not read " .. edit.property .. " before changing " .. label) end
			edit.before = value
		end
		local rows, results, changed, failed, uncertain = {}, {}, 0, 0, 0
		for _, edit in ipairs(edits) do
			local checked, stopped = true, false
			if ctx and ctx.aborted then checked, stopped = pcall(ctx.aborted) end
			stopped = not checked or stopped
			local ok, problem = false, stopped and "cancelled before write" or nil
			local value
			if not stopped then
				ok, problem = pcall(function()
					if edit.value ~= edit.before then target[edit.property] = edit.value end
				end)
				local readable, observed = pcall(function() return target[edit.property] end)
				if readable then
					value = observed
					if value ~= edit.before then changed = changed + 1 end
					if ok and value ~= edit.value then ok, problem = false, "engine readback differs from requested value: " .. H.show(value) end
				else uncertain = uncertain + 1; ok, problem = false, "readback unavailable after write; effects are uncertain" end
			end
			if ok then
				rows[#rows + 1] = edit.property .. " = " .. H.show(value) .. " (was " .. H.show(edit.before) .. ")"
			else failed = failed + 1; rows[#rows + 1] = edit.property .. " failed: " .. tostring(problem) end
			results[#results + 1] = { property = edit.property, ok = ok, before = H.show(edit.before), observed = value ~= nil and H.show(value) or nil, error = not ok and tostring(problem) or nil }
		end
		return { ok = failed == 0, text = label .. ": " .. table.concat(rows, "; "),
			data = { status = failed == 0 and "applied" or (changed > 0 or uncertain > 0) and "partial" or "failed", changed = changed, uncertain = uncertain, failed = failed, results = results, localObservation = true } }
	end

	-- Temporary signal inspection owns its listener even when a wait fails or the
	-- client unloads. Bound formatting work before game traffic reaches the model.
	function H.watch(signal, count, seconds, ctx, label)
		local clock = env.require("runtime/clock")
		local function aborted()
			if not ctx or not ctx.aborted then return false end
			local ok, value = pcall(ctx.aborted); return not ok or value == true
		end
		if aborted() then return { ok = false, text = "Observation cancelled before listening.", data = { status = "aborted", count = 0 } } end
		local captured, alive, bytes = {}, true, 0
		local budget = math.max(128, H.resultBudget() - 480)
		local ok, connection = pcall(function()
			return signal:Connect(function(...)
				if not alive or #captured >= count or aborted() then return end
				local args, total = {}, select("#", ...)
				for index = 1, math.min(total, 32) do args[index] = select(index, ...) end
				local rendered, value = pcall(function()
					local parts = {}
					for index = 1, math.min(total, 32) do parts[#parts + 1] = index .. ": " .. util.ellipsis(H.show(args[index]), 160) end
					if total > 32 then parts[#parts + 1] = "... " .. (total - 32) .. " more arguments" end
					return #parts > 0 and table.concat(parts, ", ") or "(no arguments)"
				end)
				value = rendered and value or "<unreadable event arguments>"
				local room = math.min(1000, budget - bytes)
				if room < 32 then return end
				value = util.ellipsis(value, room)
				captured[#captured + 1] = value; bytes = bytes + #value + 8
			end)
		end)
		if not ok or not connection then return H.fail("could not connect to " .. label) end
		local stop = env.require("runtime/dispose").add(function() alive = false; connection:Disconnect() end, "tool signal observation")
		local started = clock.ms()
		local waited, problem = pcall(function()
			while alive and #captured < count and bytes < budget - 32 and clock.since(started) < seconds * 1000 and not aborted() do clock.wait(0.05) end
		end)
		local cancelled = not alive or aborted()
		stop()
		if not waited then return H.fail("observation failed: " .. tostring(problem)) end
		local elapsed = clock.since(started) / 1000
		return { ok = not cancelled, text = string.format("%s: %d event(s) in %.2fs%s\n%s", label, #captured, elapsed,
			cancelled and " (cancelled)" or bytes >= budget - 32 and " (result budget reached)" or "", H.list(captured, count)),
			data = { status = cancelled and "aborted" or "observed", count = #captured, elapsedSeconds = elapsed, limited = bytes >= budget - 32 } }
	end

	return H
end
