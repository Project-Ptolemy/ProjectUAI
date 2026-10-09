-- Project information, reached explicitly from the player's existing menu.
return function(env)
	local caps = env.require("runtime/caps")
	local theme = env.require("ui/theme")
	local responsive = env.require("ui/responsive")
	local overlay = env.require("ui/overlay")
	local P = env.require("ui/primitives")
	local R = env.require("ui/settingsrows")
	local icons = env.require("ui/icons")
	local M = {}
	local REPOSITORY = "https://github.com/Project-Ptolemy/ProjectUAI"
	local current

	function M.open()
		if current and not current.closed then return current end
		local modal = overlay.modal({ title = "ProjectUAI",
			description = "An open-source AI agent for Roblox. Explore your game, build scripts, and work with your own models and tools.",
			width = theme.size.modalWide, onClose = function() current = nil end })
		if not modal then return nil end
		current = modal
		local identity = P.row(modal.content, { name = "ProjectIdentity", gap = theme.space.sm,
			size = UDim2.new(1, 0, 0, theme.size.avatar), alignY = "Center", layoutOrder = 0 })
		local mark = P.frame(identity, { size = UDim2.fromOffset(theme.size.avatar, theme.size.avatar), layoutOrder = 1 })
		icons.brand(mark, theme.size.avatar)
		P.text(identity, { text = "Project UAI", role = "strong", auto = "X", layoutOrder = 2 })
		local support = R.section(modal.content, { name = "ProjectSupport", title = "Enjoying ProjectUAI?", layoutOrder = 1 })
		R.paragraph(support, "A star on GitHub helps others discover the project. Browse the source, follow development, or share an issue there.",
			{ color = theme.color.textSecondary, layoutOrder = 1 })
		local link = P.field(support, { name = "ProjectRepository", text = REPOSITORY,
			role = "small", multiline = true,
			height = math.max(responsive.minTarget(), theme.text.small.height * 2 + theme.space.sm * 2), layoutOrder = 2 })
		link.instance.TextEditable = false
		local status = R.paragraph(support, "Open the repository, then choose Star on GitHub if you'd like to support it.",
			{ name = "ProjectLinkStatus", color = theme.color.textSecondary, layoutOrder = 3 })
		local function copyLink()
			local ok, result = false, nil
			if caps.fn.clipboard then ok, result = pcall(caps.fn.clipboard, REPOSITORY) end
			if ok and result ~= false then
				status.Text = "Repository link copied. Paste it into your browser to visit GitHub."
			else
				status.Text = "Select and copy the repository link above, then open it in your browser."
			end
		end
		P.button(support, { name = "ProjectGitHub", text = "Star us on GitHub", variant = "primary", fill = true, layoutOrder = 4,
			onClick = function()
				-- Roblox hosts may deny browser access. Keep a usable link in that case.
				local ok, result = pcall(function() return env.guisvc:OpenBrowserWindow(REPOSITORY) end)
				if ok and result ~= false then
					status.Text = "Browser open requested. Choose Star on the repository page to support ProjectUAI."
				else
					copyLink()
				end
			end })
		P.button(modal.footer, { name = "ProjectCopy", text = "Copy link", variant = "secondary", layoutOrder = 1, onClick = copyLink })
		P.button(modal.footer, { name = "ProjectClose", text = "Close", variant = "ghost", layoutOrder = 2,
			onClick = function() modal.close() end })
		return modal
	end

	return M
end
