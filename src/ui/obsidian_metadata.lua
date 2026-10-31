-- Bounded note structure details, without interpreting Markdown as UI markup.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local util = env.require("runtime/util")
	local M = {}
	function M.open(document)
		local modal = overlay.modal({ title = "Note details", description = document.path, width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local metadata = type(document.metadata) == "table" and document.metadata or {}
		local sections = { { "Revision", document.revision or "New note" }, { "Size", tostring(document.bytes or #document.content) .. " bytes" } }
		local headings = {}
		for index, heading in ipairs(type(metadata.headings) == "table" and metadata.headings or {}) do
			if index > 80 then break end
			if type(heading) == "table" then headings[#headings + 1] = "Line " .. tostring(heading.line or "?") .. ": " .. tostring(heading.text or "") end
		end
		if #headings > 0 then sections[#sections + 1] = { "Headings", table.concat(headings, "\n") } end
		local tags = {}
		for index, tag in ipairs(type(metadata.tags) == "table" and metadata.tags or {}) do if index > 80 then break end; tags[#tags + 1] = tostring(tag) end
		if #tags > 0 then sections[#sections + 1] = { "Tags", table.concat(tags, ", ") } end
		if type(metadata.frontmatter) == "string" and metadata.frontmatter ~= "" then sections[#sections + 1] = { "Frontmatter", util.ellipsis(metadata.frontmatter, 8000) } end
		for index, section in ipairs(sections) do
			P.text(modal.content, { text = section[1], role = "label", layoutOrder = index * 2 })
			P.text(modal.content, { text = section[2], role = "small", color = theme.color.textSecondary,
				wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = index * 2 + 1 })
		end
		P.text(modal.content, { text = "Headings, tags and frontmatter are bounded summaries. The note text remains authoritative.",
			role = "caption", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 999 })
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", onClick = modal.close })
		return modal
	end
	return M
end
