-- Hook bus.
--
-- Extension points around the loop so a host script can observe or amend what
-- happens without patching the loop: rewrite a request before it is sent, veto a
-- tool call, post-process a result, or log an error to somewhere else. The host
-- gets at this through env.context.hooks.
return function(env)
	local util = env.require("runtime/util")
	local log = env.require("runtime/log")

	local KINDS = {
		preRequest = true,   -- (payload) -> may mutate or replace payload.request
		postResponse = true, -- (payload) -> may mutate payload.result
		preTool = true,      -- (payload) -> return false to veto; payload.reason explains
		postTool = true,     -- (payload) -> may mutate payload.text
		onError = true,      -- reserved; observe error events through onEvent today
		onEvent = true,      -- (payload) every session event, observer only
	}

	local M = { handlers = {} }
	local sequence = 0

	function M.register(kind, fn, opts)
		local reason
		if not KINDS[kind] then reason = "unknown hook kind: " .. tostring(kind)
		elseif type(fn) ~= "function" then reason = "hook callback must be a function"
		elseif opts ~= nil and type(opts) ~= "table" then reason = "hook options must be a table"
		elseif opts and opts.order ~= nil and (type(opts.order) ~= "number" or opts.order ~= opts.order or math.abs(opts.order) == math.huge) then reason = "hook order must be a finite number"
		elseif opts and opts.name ~= nil and type(opts.name) ~= "string" then reason = "hook name must be a string" end
		if reason then
			log.warn("hooks", reason)
			return function() return false end, reason
		end
		M.handlers[kind] = M.handlers[kind] or {}
		sequence = sequence + 1
		local entry = { fn = fn, alive = true, order = (opts and opts.order) or 0, name = (opts and opts.name) or "hook", sequence = sequence }
		table.insert(M.handlers[kind], entry)
		table.sort(M.handlers[kind], function(a, b)
			if a.order == b.order then return a.sequence < b.sequence end
			return a.order < b.order
		end)
		return function()
			if not entry.alive then return false end
			entry.alive, entry.fn = false, nil
			for index, candidate in ipairs(M.handlers[kind] or {}) do
				if candidate == entry then table.remove(M.handlers[kind], index); break end
			end
			return true
		end
	end

	-- Runs every handler for a kind. A handler that errors is logged and skipped:
	-- a broken host hook must not take the agent down with it. Returns false when
	-- any handler vetoed, which only preTool acts on.
	function M.run(kind, payload)
		local allowed = true
		-- Snapshot membership before callbacks: removals take effect immediately;
		-- new registrations start on the next run without reshaping this walk.
		local snapshot = {}
		for index, entry in ipairs(M.handlers[kind] or {}) do snapshot[index] = entry end
		for _, entry in ipairs(snapshot) do
			if entry.alive then
				local ok, result = pcall(entry.fn, payload)
				if not ok then
					log.warn("hooks", entry.name .. " (" .. kind .. ") failed", result)
				elseif result == false then
					allowed = false
				end
			end
		end
		return allowed, payload
	end

	function M.count(kind)
		local total = 0
		for _, entry in ipairs(M.handlers[kind] or {}) do
			if entry.alive then total = total + 1 end
		end
		return total
	end

	-- A host may pass hooks in at boot: env.context.hooks = { preTool = fn, ... }.
	function M.adoptContext()
		local provided = env.context and env.context.hooks
		if type(provided) ~= "table" then return 0 end
		local adopted = 0
		for kind, fn in pairs(provided) do
			if KINDS[kind] and type(fn) == "function" then
				M.register(kind, fn, { name = "host" })
				adopted = adopted + 1
			end
		end
		if adopted > 0 then log.info("hooks", util.pluralise(adopted, "host hook") .. " registered") end
		return adopted
	end

	M.KINDS = KINDS

	return M
end
