-- Presentation-only guidance; never changes errors retained by the runtime.
return function(env)
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local M = {}

	function M.matches(value)
		if type(value) ~= "string" then return false end
		local text = value:lower()
		local status = tonumber(text:match("http%s*%(?(%d%d%d)"))
		if status and ({ [400] = true, [401] = true, [403] = true, [404] = true, [409] = true, [422] = true, [429] = true })[status] then return false end
		if text:match("^%s*timeout%s*$") then return true end
		for _, phrase in ipairs({ "deadline:", "deadline exceeded", "deadline reached", "deadline_exceeded",
			"deadline expired", "timed out", "etimedout", "esockettimedout", "transport timeout", "request timeout",
			"connection timeout", "socket timeout", "gateway timeout" }) do
			if text:find(phrase, 1, true) then return true end
		end
		return false
	end

	function M.new(parent, order)
		local group = P.column(parent, { name = "DeadlineRecovery", size = UDim2.new(1, 0, 0, 0),
			auto = "Y", gap = theme.space.xs, layoutOrder = order })
		P.text(group, { name = "DeadlineRecoveryAdvice", text = "Review the last reply and any completed actions before sending again. "
			.. "A timeout does not confirm that the provider stopped working. Request wait settings can help with short client limits; host limits still apply.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y", layoutOrder = 1 })
		P.button(group, { name = "DeadlineRequestSettings", text = "Review request wait", size = "sm", layoutOrder = 2,
			onClick = function()
				local dialog = env.require("ui/app").showSettingsDialog("agent")
				if dialog and dialog.reveal then dialog.reveal("agent", "agent.requestTimeout") end
			end })
		local button = P.rowButton(group, { name = "DeadlineHelp", vertical = true,
			size = UDim2.new(1, 0, 0, 0), auto = "Y", layoutOrder = 3,
			bg = theme.color.warnSurface, bgHover = theme.color.surfaceHover,
			stroke = true, strokeColor = theme.color.warn, radius = theme.radius.md,
			padding = theme.space.sm, gap = theme.space.xxs,
			onClick = function() env.require("ui/community").open() end })
		P.text(button.row, { name = "DeadlineHelpTitle", text = "Join our Discord for a tutorial on fixing this",
			role = "label", color = theme.color.warn, wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
		P.text(button.row, { name = "DeadlineHelpAction", text = "Open the official Project UAI invite",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y",
			size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		button.container = group
		return button
	end

	return M
end
