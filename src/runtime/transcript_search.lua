-- Bounded saved-transcript search. Result identities remain stable across redraws.
return function(env)
	local util = env.require("runtime/util")
	local search = env.require("runtime/search")
	local M = { maxBytes = 4 * 1024 * 1024, maxEvents = 1000, pageSize = 50 }
	local labels = { user = "Message", ["assistant:text"] = "Reply", ["error"] = "Error" }
	function M.excerpt(body, query)
		local at = 1
		for _, term in ipairs(search.terms(query)) do
			if not term.excluded then at = body:lower():find(term.value, 1, true) or at; break end
		end
		local first = math.max(1, at - 48)
		while first > 1 and (body:byte(first) or 0) >= 128 and (body:byte(first) or 0) < 192 do first = first - 1 end
		return (first > 1 and "... " or "") .. util.ellipsis(body:sub(first):gsub("%s+", " "), 180)
	end
	function M.page(events, query, options)
		options = options or {}
		local out = { items = {}, scanned = 0, bytes = 0, complete = true }
		if util.trim(tostring(query or "")) == "" then return out end
		local match = search.compile(query)
		local before = tonumber(options.before) or math.huge
		local limit = math.max(1, math.min(M.pageSize, tonumber(options.limit) or M.pageSize))
		local byteLimit = math.max(1, math.min(M.maxBytes, tonumber(options.maxBytes) or M.maxBytes))
		for index = #(events or {}), 1, -1 do
			local event = events[index]
			local id = tonumber(event.transcriptId) or index
			if id < before then
				if out.scanned >= M.maxEvents or out.bytes >= byteLimit then out.complete = false; break end
				out.scanned = out.scanned + 1
				out.nextBefore = id
				local label = labels[event.kind]
				if label and (not options.role or options.role == "all" or event.kind == options.role) then
					local raw = tostring(event.text or event.message or "")
					local body = util.truncate(raw, math.min(16384, byteLimit - out.bytes))
					out.bytes = out.bytes + #body
					if #body < #raw then out.clipped = true end
					local score = match(body)
					if score then
						out.items[#out.items + 1] = { id = id, kind = event.kind, label = label, at = event.at,
							snippet = M.excerpt(body, query), score = score }
						if #out.items >= limit and index > 1 then out.complete = false; break end
					end
				end
			end
		end
		if out.complete then out.nextBefore = nil end
		return out
	end
	return M
end
