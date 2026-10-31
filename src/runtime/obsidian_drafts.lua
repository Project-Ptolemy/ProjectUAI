-- Unsent note edits stay in bounded memory until saved or explicitly discarded.
return function(env)
	local limit = env.require("runtime/obsidian").MAX_BYTES
	local M = { limit = 8 }
	local entries = {}
	local function key(vault, path) return tostring(vault) .. "\0" .. tostring(path) end
	function M.get(vault, path) return entries[key(vault, path)] end
	function M.reserve(vault, path, document)
		local id = key(vault, path)
		if entries[id] then return entries[id] end
		local count = 0; for _ in pairs(entries) do count = count + 1 end
		if count >= M.limit then return nil, "Eight note drafts are already open. Save or discard one before editing another note." end
		local entry = { document = document, text = env.require("runtime/obsidian_document").editorText(document.content), dirty = false }
		entries[id] = entry
		return entry
	end
	function M.update(entry, text)
		if type(text) ~= "string" or #text > limit then return nil, "Notes can contain at most 1 MiB. Extra input was not added." end
		entry.text = text
		entry.dirty = text ~= env.require("runtime/obsidian_document").editorText(entry.document.content)
		return true
	end
	function M.remove(vault, path) entries[key(vault, path)] = nil end
	function M.list(vault)
		local out = {}
		for _, entry in pairs(entries) do if (entry.dirty or entry.blocked) and (not vault or entry.document.vault == vault) then out[#out + 1] = entry end end
		table.sort(out, function(a, b) return a.document.path < b.document.path end)
		return out
	end
	function M.clear() entries = {} end
	local dispose = env.require("runtime/dispose")
	dispose.add(M.clear, "native note drafts")
	return M
end
