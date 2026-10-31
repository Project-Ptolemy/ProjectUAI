-- Bounded local summaries for the user; no model request or content inference.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	function M.snapshot(session, folder)
		local messages, replies, latest = 0, 0, nil
		for _, event in ipairs(session.log or {}) do
			if event.kind == "user" then messages = messages + 1; latest = event.text
			elseif event.kind == "assistant:text" then replies = replies + 1 end
		end
		local pending = session.queueSnapshot and session.queueSnapshot() or {}
		local plan = { pending = 0, active = 0, done = 0, dropped = 0 }
		for _, item in ipairs(session.todos or {}) do if plan[item.status] then plan[item.status] = plan[item.status] + 1 end end
		return { id = session.id, title = session.title, folder = folder or "Unknown folder",
			messages = messages, replies = replies, retained = #(session.log or {}), queued = pending.count or 0,
			held = pending.held == true, queueReason = pending.reason, busy = session.busy == true,
			saved = session.ephemeral ~= true, draft = session.draft ~= nil, plan = plan,
			latest = latest and util.ellipsis(tostring(latest):gsub("%s+", " "), 320) or nil }
	end
	function M.text(value)
		local lines = { tostring(value.title), "Folder: " .. value.folder, "Conversation ID: " .. tostring(value.id),
			"State: " .. (value.busy and "Running" or "Idle"), "History: " .. (value.saved and "Saved when file storage is available" or "Not saved"),
			string.format("Retained messages: %d user / %d reply events", value.messages, value.replies),
			"Queued: " .. tostring(value.queued) .. (value.held and " (paused)" or ""), "Draft: " .. (value.draft and "Available" or "Empty"),
			string.format("Plan: %d done / %d active / %d pending / %d dropped", value.plan.done, value.plan.active, value.plan.pending, value.plan.dropped) }
		if value.queueReason then lines[#lines + 1] = "Queue pause: " .. tostring(value.queueReason) end
		if value.latest then lines[#lines + 1] = "Latest retained request: " .. value.latest end
		return table.concat(lines, "\n")
	end
	return M
end
