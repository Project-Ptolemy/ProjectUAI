-- Quick-open and content search share retained workspace data and exact navigation.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local search = env.require("runtime/code_search")
	local store = env.require("runtime/code_store")
	local M = {}
	function M.open(contents, navigate)
		local modal = overlay.modal({ title = contents and "Search workspace source" or "Quick open script",
			description = contents and "Search literal text in retained scripts. Results include the line and source revision." or 'Search script names with words, "phrases", or -exclude.' })
		if not modal then return end
		local rows = P.column(modal.content, { name = "CodeSearchResults", auto = "Y", size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 3 })
		local status = P.text(modal.content, { name = "CodeSearchStatus", text = "", role = "caption", auto = "Y", wrap = true, layoutOrder = 2 })
		local query, offset, nextOffset, matches, render = "", 0, nil, {}
		local function choose(item)
			local doc = store.resolve(item.documentId or item.id)
			if not doc then status.Text = "This script is no longer available."; return end
			if item.revision and item.revision ~= doc.revision then status.Text = "The source changed. Search again to refresh its locations."; return end
			local opened, why = store.select(doc.id); if not opened then status.Text = why; return end
			store.workspace.sourceId = nil
			if item.first then local view = store.view(doc.id); view.cursor, view.selection = item.after, item.first end
			modal.close(); navigate("Editor")
			store.changed:fire({ kind = "source_navigation", documentId = doc.id })
		end
		local more = P.button(modal.footer, { text = "Next results", size = "sm", onClick = function() if nextOffset then offset = nextOffset; render() end end })
		P.button(modal.footer, { text = "Close", size = "sm", variant = "ghost", onClick = modal.close })
		render = function()
			if modal.closed then return end
			for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local result, why
			if contents then result, why = search.contents(query, { offset = offset }) else result = { items = search.documents(query), complete = true } end
			matches, nextOffset = result and result.items or {}, result and result.nextOffset
			more.instance.Visible = nextOffset ~= nil
			status.Text = why or (#matches .. " results" .. (result.total and (" / " .. result.total .. " retained matches") or "") .. (result.complete == false and " · narrow your search to inspect more" or ""))
			for index, item in ipairs(matches) do
				local entry = item
				local row = P.rowButton(rows, { name = "CodeSearchResult", auto = "Y", vertical = true, size = UDim2.new(1, 0, 0, 0), padding = theme.space.sm, layoutOrder = index, onClick = function() choose(entry) end })
				P.text(row.row, { text = item.name .. (item.line and (" · line " .. item.line) or ""), role = "small", auto = "Y", wrap = true, layoutOrder = 1 })
				P.text(row.row, { text = item.text or (item.bytes .. " bytes" .. (item.readOnly and " · read-only" or "")), role = "caption", auto = "Y", wrap = true, color = theme.color.textSecondary, layoutOrder = 2 })
			end
			modal.scroll.instance.CanvasPosition = Vector2.new(0, 0)
		end
		local field = P.field(modal.content, { name = "CodeWorkspaceSearch", placeholder = contents and "Find text across scripts" or "Find a script", layoutOrder = 1,
			onChange = function(value) query, offset = value, 0; render() end, onSubmit = function() if matches[1] then choose(matches[1]) end end })
		render(); task.defer(function() if not modal.closed then field.focus() end end)
		return modal
	end
	return M
end
