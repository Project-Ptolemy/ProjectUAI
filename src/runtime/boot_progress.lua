-- Startup milestones come from init. Module totals include lazy features and are
-- useful counts, never an overall percentage.
return function(env)
	local M = {}
	local STAGES = {
		{ id = "prepare", label = "Prepare", title = "Preparing your client", detail = "Reading preferences and preparing tools." },
		{ id = "restore", label = "Restore", title = "Restoring your workspace", detail = "Opening saved files and conversations." },
		{ id = "interface", label = "Open", title = "Opening Project UAI", detail = "Building your workspace and controls." },
	}
	function M.new(now)
		local state = { index = 1, count = 0, total = 0, started = now or 0, changed = now or 0,
			status = "loading", detail = STAGES[1].detail }
		function state.stage(id, detail, stamp)
			if state.status ~= "loading" then return false end
			for index, stage in ipairs(STAGES) do
				if stage.id == id then
					if index < state.index then return false end
					state.index, state.changed = index, stamp or state.changed
					state.detail = type(detail) == "string" and detail ~= "" and detail or stage.detail
					return true
				end
			end
			return false
		end
		function state.module(count, total, stamp)
			if state.status ~= "loading" then return end
			if type(count) == "number" and count == count and count >= 0 and count < math.huge then state.count = math.max(state.count, math.floor(count)) end
			if type(total) == "number" and total == total and total >= 0 and total < math.huge then state.total = math.floor(total) end
			state.changed = stamp or state.changed
		end
		function state.phase(detail, stamp)
			if state.status ~= "loading" then return end
			if type(detail) == "string" and detail ~= "" then state.detail = detail end
			state.changed = stamp or state.changed
		end
		function state.finish(detail, stamp)
			if state.status ~= "loading" then return false end
			state.status, state.index, state.ended = "ready", #STAGES, stamp or state.changed
			state.detail = type(detail) == "string" and detail ~= "" and detail or "Your workspace is ready."
			return true
		end
		function state.fail(stamp)
			if state.status ~= "loading" then return false end
			state.status, state.ended = "failed", stamp or state.changed
			state.detail = "Stopped during " .. STAGES[state.index].label:lower() .. ". Check the executor console for details."
			return true
		end
		function state.snapshot(stamp)
			stamp = state.ended or stamp or state.changed
			local stage = STAGES[state.index]
			local slow = state.status == "loading" and stamp - state.changed >= 8
			local out = { status = state.status, title = state.status == "ready" and "Ready when you are"
				or state.status == "failed" and "Could not finish startup" or stage.title,
				detail = state.detail, count = state.count, elapsed = math.max(0, stamp - state.started), slow = slow,
				index = state.index, stages = {}, note = state.status == "ready" and "Other components load when you open them."
					or state.status == "failed" and "Close this notice, resolve the error, then run the script again."
					or slow and "Still working. This step is taking longer on this device."
					or "Your workspace will open as soon as it is ready." }
			for index, entry in ipairs(STAGES) do
				out.stages[index] = { id = entry.id, label = entry.label,
					status = (state.status == "ready" or index < state.index) and "done"
						or index == state.index and state.status or "pending" }
			end
			return out
		end
		return state
	end
	return M
end
