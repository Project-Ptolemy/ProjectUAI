-- Rolling inference dispatch limits with fair, cancellable reservations.
-- Admission owns no native worker. Only commit records a dispatched attempt.
return function(env)
	local config = env.require("runtime/config")
	local clock = env.require("runtime/clock")
	local policy = env.require("runtime/inference_rate_policy")
	local M = {}
	local WINDOW, MAX_SCOPES, MAX_PENDING, MAX_BUCKETS = 60000, 512, 512, 65536
	local alive, lastTime, scopeCount, bucketCount = true, 0, 0, 0
	local contexts = setmetatable({}, { __mode = "k" })
	local draftKeys = setmetatable({}, { __mode = "k" })
	local scopes, queue, held = {}, {}, {}
	local function history() return { entries = {}, first = 1, last = 0, count = 0 } end
	local global = history()
	global.reserved = 0
	local function now()
		lastTime = math.max(lastTime, clock.ms())
		return lastTime
	end
	local function removeFirst(h)
		h.entries[h.first] = nil
		h.first, bucketCount = h.first + 1, bucketCount - 1
	end
	local function compact(h)
		if h.first > h.last then h.entries, h.first, h.last = {}, 1, 0
		elseif h.first > 256 and h.first > h.last / 2 then
			local entries, last = {}, 0
			for index = h.first, h.last do last = last + 1; entries[last] = h.entries[index] end
			h.entries, h.first, h.last = entries, 1, last
		end
	end
	local function prune(h, at)
		while h.first <= h.last and h.entries[h.first].at <= at - WINDOW do
			h.count = h.count - h.entries[h.first].count
			removeFirst(h)
		end
		compact(h)
	end
	local function pruneAll(at)
		prune(global, at)
		for key, state in pairs(scopes) do
			prune(state, at)
			if state.count == 0 and state.refs == 0 then scopes[key] = nil; scopeCount = scopeCount - 1 end
		end
	end
	local function needed(h, at)
		local last = h.entries[h.last]
		if last and last.at == at then return 0 end
		-- Keeping the newest MAX events is exact for every supported cap: while a
		-- discarded older event could matter, MAX newer events still block it.
		if h.count == policy.MAX and h.entries[h.first].count == 1 then return 0 end
		return 1
	end
	local function append(h, at)
		local last = h.entries[h.last]
		if last and last.at == at then last.count = last.count + 1
		else
			h.last, bucketCount = h.last + 1, bucketCount + 1
			h.entries[h.last] = { at = at, count = 1 }
		end
		h.count = h.count + 1
		while h.count > policy.MAX do
			local entry = h.entries[h.first]
			local removed = math.min(entry.count, h.count - policy.MAX)
			entry.count, h.count = entry.count - removed, h.count - removed
			if entry.count == 0 then removeFirst(h) end
		end
		compact(h)
	end
	function M.providerKey(record)
		local id = type(record) == "table" and record.id
		if type(id) == "string" and id ~= "" then return "provider:" .. id end
		if type(record) ~= "table" then return nil end
		local key = draftKeys[record]
		if not key then key = {}; draftKeys[record] = key end
		return key
	end
	function M.context(options)
		local context = {}
		contexts[context] = options
		return context
	end
	function M.deadline(context, deadline)
		local options = contexts[context]
		local limit = options and tonumber(options.deadlineMs)
		if not limit or limit ~= limit then limit = math.huge end
		return math.min(deadline or math.huge, limit)
	end
	local function check(waiter, at)
		if not alive then return "aborted" end
		local options = contexts[waiter.context]
		if not options or options.provider == nil then return "malformed: invalid inference rate context" end
		if options.valid then
			local ok, value = pcall(options.valid)
			if not ok or value ~= true then return "aborted" end
		end
		if waiter.options.aborted then
			local ok, value = pcall(waiter.options.aborted)
			if not ok or value == true then return "aborted" end
		end
		if M.deadline(waiter.context, waiter.options.deadlineMs) <= at then return "deadline: request budget expired while waiting for the request rate limit" end
		return nil
	end
	local function limits(waiter)
		local globalLimit = config.get("agent.requestsPerMinute", 0)
		local problem = policy.problem(globalLimit)
		if problem then return nil, nil, "malformed: " .. problem end
		local options = contexts[waiter.context]
		if not options then return nil, nil, "malformed: invalid inference rate context" end
		local ok, providerLimit = true, 0
		if options.limit then ok, providerLimit = pcall(options.limit) end
		if not ok then return nil, nil, "aborted" end
		if providerLimit == nil then providerLimit = 0 end
		problem = policy.problem(providerLimit)
		if problem then return nil, nil, "malformed: " .. problem end
		return globalLimit, providerLimit
	end
	local function report(waiter, phase)
		local callback = waiter.options and waiter.options.onRetry
		if callback then pcall(callback, { rateLimit = true, reason = "Waiting for request rate limit",
			phase = phase, wait = phase == "waiting" and (waiter.wait or 0.05) or 0 }) end
	end
	local function release(waiter, status)
		if waiter.status == "held" then
			global.reserved = global.reserved - 1
			waiter.state.reserved = waiter.state.reserved - 1
			held[waiter.permit] = nil
		elseif waiter.status ~= "queued" then return end
		waiter.state.refs = waiter.state.refs - 1
		waiter.status = status or "released"
	end
	local function waitFor(h, cap, at)
		if cap == 0 or h.count + h.reserved < cap then return 0 end
		local required = h.count + h.reserved - cap + 1
		for index = h.first, h.last do
			local entry = h.entries[index]
			required = required - entry.count
			if required <= 0 then return math.max(0.001, (entry.at + WINDOW - at) / 1000) end
		end
		return 0.05
	end
	local function permitFor(waiter)
		local permit = {}
		function permit.release()
			release(waiter)
			waiter.context, waiter.options = nil, nil
		end
		function permit.commit()
			if waiter.status ~= "held" then return false, "aborted", "terminal" end
			local at = now()
			pruneAll(at)
			local problem = check(waiter, at)
			local globalLimit, providerLimit, limitProblem = limits(waiter)
			problem = problem or limitProblem
			if problem then permit.release(); return false, problem, "terminal" end
			-- Ownership and policy readers can spend CPU time without yielding.
			-- Stamp the actual dispatch boundary and recheck its remaining budget.
			at = now(); prune(global, at); prune(waiter.state, at)
			if M.deadline(waiter.context, waiter.options.deadlineMs) <= at then
				permit.release(); return false, "deadline: request budget expired before dispatch", "terminal"
			end
			-- A changed cap can invalidate an unused reservation. The transport
			-- releases its worker and rejoins admission before trying to dispatch.
			if (globalLimit > 0 and global.count >= globalLimit) or (providerLimit > 0 and waiter.state.count >= providerLimit) then
				permit.release(); return false, "Request rate limits changed before dispatch", "rate"
			end
			-- Ceil millisecond timestamps prevent an event expiring early on a host
			-- whose fallback clock preserves fractional milliseconds.
			local stamp = math.ceil(at)
			if bucketCount + needed(global, stamp) + needed(waiter.state, stamp) > MAX_BUCKETS then
				permit.release(); return false, "capacity: request rate history is full; this attempt was not dispatched", "terminal"
			end
			append(global, stamp); append(waiter.state, stamp)
			release(waiter, "committed")
			waiter.context, waiter.options = nil, nil
			return true
		end
		return permit
	end
	local function pump()
		local at, blocked, index = now(), {}, 1
		pruneAll(at)
		while index <= #queue do
			local waiter = queue[index]
			local problem = check(waiter, at)
			local globalLimit, providerLimit, limitProblem = limits(waiter)
			problem = problem or limitProblem
			if problem then
				release(waiter, "failed"); waiter.error = problem; table.remove(queue, index)
			else
				local previous = blocked[waiter.key]
				local delay = math.max(waitFor(global, globalLimit, at), waitFor(waiter.state, providerLimit, at))
				local ready = true
				if waiter.options.ready then local ok, value = pcall(waiter.options.ready); ready = ok and value == true end
				if previous or delay > 0 or not ready then
					waiter.rateBlocked = delay > 0 or previous and previous.rateBlocked or false
					waiter.wait = math.max(delay, previous and previous.wait or 0.05)
					blocked[waiter.key] = waiter
					index = index + 1
				else
					waiter.status = "held"
					global.reserved, waiter.state.reserved = global.reserved + 1, waiter.state.reserved + 1
					waiter.permit = permitFor(waiter)
					held[waiter.permit] = waiter
					table.remove(queue, index)
				end
			end
		end
	end
	function M.acquire(context, options)
		options = options or {}
		if not alive then return nil, "aborted" end
		local declaration = contexts[context]
		if not declaration or declaration.provider == nil then return nil, "malformed: invalid inference rate context" end
		pump()
		if #queue + global.reserved >= MAX_PENDING then return nil, "capacity: request rate admission limit reached; this attempt was not dispatched" end
		local state = scopes[declaration.provider]
		if not state then
			if scopeCount >= MAX_SCOPES then return nil, "capacity: request rate provider history limit reached; this attempt was not dispatched" end
			state = history(); state.refs, state.reserved = 0, 0
			scopes[declaration.provider], scopeCount = state, scopeCount + 1
		end
		state.refs = state.refs + 1
		local waiter = { context = context, options = options, key = declaration.provider, state = state, status = "queued" }
		queue[#queue + 1] = waiter
		while waiter.status == "queued" do
			pump()
			if waiter.status == "queued" then
				if waiter.rateBlocked and not waiter.notified then waiter.notified = true; report(waiter, "waiting") end
				clock.wait(0.05)
			end
		end
		if waiter.status == "held" then
			if waiter.notified then report(waiter, "admitted") end
			return waiter.permit
		end
		if waiter.notified then report(waiter, "cancelled") end
		waiter.context, waiter.options = nil, nil
		return nil, waiter.error or "aborted"
	end
	function M.state(context)
		pruneAll(now())
		local declaration = contexts[context]
		local provider = declaration and scopes[declaration.provider]
		return { queued = #queue, held = global.reserved, scopes = scopeCount, buckets = bucketCount,
			tracked = global.count, providerTracked = provider and provider.count or 0, alive = alive,
			limits = { scopes = MAX_SCOPES, pending = MAX_PENDING, buckets = MAX_BUCKETS, windowMs = WINDOW } }
	end
	env.require("runtime/dispose").add(function()
		alive = false
		while #queue > 0 do
			local waiter = table.remove(queue, 1)
			release(waiter, "failed"); waiter.error = "aborted"
		end
		for permit in pairs(held) do permit.release() end
		scopes, held, global = {}, {}, history(); global.reserved = 0
		scopeCount, bucketCount = 0, 0
	end, "inference rate admission")
	return M
end
