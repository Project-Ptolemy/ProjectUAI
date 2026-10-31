-- The Settings panel: every pane, stacked in one scroll.
--
-- The panes themselves live in ui/settingspanes, because the settings dialog the
-- sidebar opens shows the same ones behind a category list. This surface is the one
-- that shows all of them at once, which is what a panel in a five-panel client is
-- for -- and it means a setting cannot exist in one place and not the other.
return function(env)
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local panes = env.require("ui/settingspanes")
	local responsive = env.require("ui/responsive")
	local searchUI = env.require("ui/settings_search")

	local M = {}

	function M.new(parent)
		local panel = {}
		local searchHeight = math.max(theme.size.control, responsive.minTarget()) + theme.space.sm * 2
		local scroll = P.scroll(parent, {
			name = "Settings",
			size = UDim2.new(1, 0, 1, -searchHeight),
			position = UDim2.fromOffset(0, searchHeight),
			gap = theme.space.lg,
			padding = theme.space.lg,
		})

		local columns = {}
		for index, entry in ipairs(panes.PANES) do
			local column = P.column(scroll.instance, {
				name = "Pane_" .. entry.id,
				size = UDim2.new(1, 0, 0, 0),
				auto = "Y",
				gap = theme.space.md,
				layoutOrder = index,
			})
			panes.render(entry.id, column)
			columns[entry.id] = column
		end
		local searching, position = false, Vector2.new(0, 0)
		local search
		function panel.reveal(category, path)
			if not columns[category] then return false end
			search.setQuery("")
			task.defer(function()
				task.wait()
				if scroll.instance.Parent then searchUI.reveal(scroll.instance, columns[category], path) end
			end)
			return true
		end
		search = searchUI.new(parent, scroll.instance, {
			onQuery = function(value)
				if value and not searching then position = scroll.instance.CanvasPosition end
				local changed = searching ~= value
				searching = value
				for _, column in pairs(columns) do column.Visible = not value end
				if changed or value then scroll.instance.CanvasPosition = value and Vector2.new(0, 0) or position end
			end,
			onChoose = function(item) panel.reveal(item.category, item.path) end,
		})

		panel.scroll = scroll
		panel.search = search
		return panel
	end

	return M
end
