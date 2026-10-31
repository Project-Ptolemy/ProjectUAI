-- Search retained workspace documents without reading disk or copying whole sources.
return function(env)
	local store = env.require("runtime/code_store")
	local search = env.require("runtime/search")
	local M = {}
	function M.documents(query)
		local match, rows = search.compile(query), {}
		for _, doc in ipairs(store.list()) do
			local score = match(doc.name, doc.provenance or "")
			if score then rows[#rows + 1] = { id = doc.id, name = doc.name, score = score, bytes = #doc.source, readOnly = doc.readOnly } end
		end
		table.sort(rows, function(a, b) if a.score ~= b.score then return a.score > b.score end; if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end; return a.id < b.id end)
		return rows
	end
	function M.contents(query, options)
		if type(query) ~= "string" or query == "" or #query > 256 then return nil, "Enter 1–256 bytes of literal text" end
		options = options or {}
		local items, why, nextOffset, counts = store.search(query, { caseSensitive = options.caseSensitive == true, offset = options.offset, limit = 25 })
		if not items then return nil, why end
		for _, item in ipairs(items) do
			local doc = store.resolve(item.documentId)
			item.name, item.after = doc and doc.name or item.documentId, item.last + 1
		end
		return { items = items, complete = counts.complete, total = counts.retainedMatches, nextOffset = nextOffset }
	end
	return M
end
