-- Shared search presentation for both settings surfaces. Search results point to
-- stable config paths; they never inspect text currently entered into controls.
return function(env)
	local catalog = env.require("runtime/settings_catalog")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local P = env.require("ui/primitives")
	local M = {}

	function M.find(root, path)
		if not root or not path then return root end
		if root:GetAttribute("UAISettingPath") == path then return root end
		for _, child in ipairs(root:GetChildren()) do
			local found = M.find(child, path)
			if found then return found end
		end
		return nil
	end

	function M.reveal(scroll, root, path)
		local target = M.find(root, path) or root
		return target and responsive.reveal(target, scroll, theme.space.md) or false
	end

	function M.new(parent, resultsParent, props)
		props = props or {}
		local handle = { query = "", matches = {} }
		local toolbar = P.row(parent, { name = "SettingsSearchBar", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.xs, padding = theme.space.sm, layoutOrder = props.layoutOrder or 0 })
		local results = P.column(resultsParent, { name = "SettingsSearchResults", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.xs, layoutOrder = -1, visible = false })
		handle.results, handle.toolbar = results, toolbar
		local function choose(item)
			handle.field.instance:ReleaseFocus()
			if props.onChoose then props.onChoose(item) end
		end
		local clear
		local function render(query)
			handle.query = query:sub(1, 160)
			for _, child in ipairs(results:GetChildren()) do
				if child:IsA("GuiObject") then child:Destroy() end
			end
			local searching = handle.query:match("%S") ~= nil
			results.Visible = searching
			if clear then clear.setEnabled(query ~= "") end
			if props.onQuery then props.onQuery(searching) end
			local matches, total = catalog.search(handle.query)
			handle.matches = matches
			if not searching then return end
			P.text(results, { name = "SettingsSearchCount", text = total == 0 and "No settings found."
				or (total > #matches and string.format("Showing %d of %d settings", #matches, total)
					or string.format("%d setting%s", total, total == 1 and "" or "s")),
				role = "caption", color = theme.color.textSecondary, auto = "Y", wrap = true, layoutOrder = 0 })
			for index, item in ipairs(matches) do
				local row = P.rowButton(results, { name = "SettingResult_" .. (item.path or item.category),
					vertical = true, size = UDim2.new(1, 0, 0, 0), auto = "Y", padding = theme.space.sm,
					layoutOrder = index, onClick = function() choose(item) end })
				P.text(row.row, { text = item.label, role = "label", auto = "Y", wrap = true,
					size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
				P.text(row.row, { text = item.categoryLabel, role = "caption", color = theme.color.textTertiary,
					auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
			end
		end
		handle.field = P.field(toolbar, { name = "SettingsSearch", placeholder = "Find a setting",
			size = UDim2.new(0, 0, 0, math.max(theme.size.control, responsive.minTarget())),
			flex = "Fill", layoutOrder = 1, onChange = render,
			onSubmit = function() if handle.matches[1] then choose(handle.matches[1]) end end })
		clear = P.button(toolbar, { name = "ClearSettingsSearch", text = "Clear", size = "sm",
			layoutOrder = 2, enabled = false, onClick = function() handle.setQuery(""); handle.field.focus() end })
		function handle.setQuery(query)
			query = type(query) == "string" and query:sub(1, 160) or ""
			if handle.field.get() == query then render(query) else handle.field.set(query) end
		end
		return handle
	end

	return M
end
