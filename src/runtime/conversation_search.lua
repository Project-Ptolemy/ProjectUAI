-- Search both the visible transcript and legacy context-only saved conversations.
return function(env)
	local search = env.require("runtime/search")
	local transcript = env.require("runtime/transcript_search")
	local util = env.require("runtime/util")
	local M = {}
	function M.find(session, folder, query)
		local match = search.compile(query)
		if match(session.title) then return { where = "title" } end
		if match(folder) then return { where = "folder" } end
		local page = transcript.page(session.log, query, { limit = 1, maxBytes = 262144 })
		local hit = page.items[1]
		if hit then return { where = hit.label:lower(), snippet = hit.snippet, transcriptId = hit.id } end
		local budget, scanned = math.max(0, 262144 - page.bytes), 0
		local messages = session.ctx and session.ctx.messages or {}
		for index = #messages, 1, -1 do
			if budget <= 0 or scanned >= 256 then break end
			local message = messages[index]
			scanned = scanned + 1
			if (message.role == "user" or message.role == "assistant") and type(message.content) == "string" then
				local text = util.truncate(message.content, math.min(16384, budget))
				budget = budget - #text
				if match(text) then return { where = message.role == "user" and "message" or "reply", snippet = transcript.excerpt(text, query) } end
			end
		end
		return nil
	end
	return M
end
