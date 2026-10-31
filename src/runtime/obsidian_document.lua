-- Complete note assembly binds every byte page to one file revision.
return function(env)
	local util = env.require("runtime/util")
	local vault = env.require("runtime/obsidian")
	local M = {}
	function M.revision(value) return type(value) == "string" and #value == 64 and value:match("^[a-f0-9]+$") ~= nil end
	function M.reader(vaultId, path)
		local state = { vault = vaultId, path = path, offset = 1, bytes = 0, parts = {}, pages = 0 }
		function state.accept(page)
			if state.done or type(page) ~= "table" or type(page.content) ~= "string" or not util.validUtf8(page.content)
				or not M.revision(page.revision) or page.offset ~= state.offset or type(page.bytes) ~= "number"
				or page.bytes ~= math.floor(page.bytes) or page.bytes < 0 or page.bytes > vault.MAX_BYTES then
				return nil, "The bridge returned an invalid note page. Reload this note."
			end
			if state.revision and (state.revision ~= page.revision or state.size ~= page.bytes) then return nil, "This note changed while reading. Reload it." end
			state.pages = state.pages + 1
			if state.pages > 90 or state.bytes + #page.content > vault.MAX_BYTES then return nil, "This note exceeds the read limit." end
			state.revision, state.size = page.revision, page.bytes
			if state.offset == 1 then state.metadata = page.metadata end
			state.parts[#state.parts + 1], state.bytes = page.content, state.bytes + #page.content
			if page.nextOffset == nil then
				if page.eof ~= true or state.bytes ~= state.size then return nil, "The complete note did not arrive. Reload it." end
				state.done = true
				return { vault = vaultId, path = path, content = table.concat(state.parts), revision = state.revision,
					bytes = state.size, metadata = state.metadata, modifiedAt = page.modifiedAt }
			end
			if #page.content == 0 or page.nextOffset ~= state.offset + #page.content or page.eof ~= false then return nil, "The note page did not advance safely." end
			state.offset = page.nextOffset
			return false
		end
		return state
	end
	function M.editorText(text) return tostring(text or ""):gsub("\r\n", "\n"):gsub("\r", "\n") end
	function M.savedText(document, text)
		local original = tostring(document.content or "")
		if original:find("\r\n", 1, true) and not original:gsub("\r\n", ""):find("\n", 1, true) then
			return M.editorText(text):gsub("\n", "\r\n")
		end
		return text
	end
	return M
end
