-- Project information uses the existing profile menu and modal, with host fallbacks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Project support")
local check, case = suite.check, suite.case
local URL = "https://github.com/Project-Ptolemy/ProjectUAI"
local function mobile(width, height, textScale)
	local f = F.ui(width, height)
	local uis = f.h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled = true, false
	f.env.require("ui/responsive").init(f.env.root)
	if textScale then f.env.require("runtime/config").set("ui.fontScale", textScale) end
	f.env.require("ui/theme").rebuild()
	return f
end
local function horizontalPadding(node)
	local padding = node:FindFirstChildOfClass("UIPadding")
	return padding and padding.PaddingLeft.Offset + padding.PaddingRight.Offset or 0
end

case("profile navigation keeps release notes separate", function()
	local f = mobile(390, 844)
	local overlay = f.env.require("ui/overlay")
	local original, menu = overlay.menu
	overlay.menu = function(options) menu = options; return nil end
	f.env.require("ui/app").showProfileMenu(f.host)
	overlay.menu = original
	local project, news = 0, 0
	for _, option in ipairs(menu.options) do
		if option.value == "project" then project = project + 1 end
		if option.value == "changelog" then news = news + 1 end
	end
	check("one project entry and existing release notes", project == 1 and news == 1)
	local notes = f.env.require("runtime/changelog")
	local unread = notes.isUnread()
	menu.onSelect("project")
	check("project navigation opens its content", f.h.byName("ProjectSupport") ~= nil)
	check("project information does not mark release notes read", notes.isUnread() == unread)
	f.healthy(); f.close()
end)

case("GitHub is opened only on user action with no automatic star", function()
	local f = F.ui(900, 650)
	local opened, copied = {}, {}
	f.env.guisvc.OpenBrowserWindow = function(_, url) opened[#opened + 1] = url end
	f.env.require("runtime/caps").fn.clipboard = function(url) copied[#copied + 1] = url end
	local project = f.env.require("ui/project")
	local modal = project.open()
	check("opening information causes no browser or clipboard action", #opened == 0 and #copied == 0)
	check("repeated navigation keeps one modal", project.open() == modal)
	f.h.click(f.h.byName("ProjectGitHub", modal.card))
	check("star action opens the actual repository", #opened == 1 and opened[1] == URL and #copied == 0)
	f.h.click(f.h.byName("ProjectCopy", modal.card))
	check("copy remains available independently", #copied == 1 and copied[1] == URL)
	f.h.click(f.h.byName("ProjectClose", modal.card))
	check("close releases modal", modal.closed)
	check("can reopen after closing", project.open() ~= modal)
	f.healthy(); f.close()
end)

case("denied browser and clipboard leave the real link selectable", function()
	local f = mobile(320, 568)
	local caps = f.env.require("runtime/caps")
	f.env.guisvc.OpenBrowserWindow = function() error("host denied") end
	local modal = f.env.require("ui/project").open()
	local copied
	caps.fn.clipboard = function(url) copied = url end
	f.h.click(f.h.byName("ProjectGitHub", modal.card))
	check("browser denial falls back to clipboard", copied == URL and not modal.closed)
	caps.fn.clipboard = function() return false end
	f.h.click(f.h.byName("ProjectGitHub", modal.card))
	local field = f.h.byName("ProjectRepository", modal.card):FindFirstChildOfClass("TextBox")
	check("full selectable read-only URL survives failures", field.Text == URL and field.TextEditable == false)
	check("manual fallback is explained", f.h.byName("ProjectLinkStatus", modal.card).Text:find("Select and copy", 1, true) ~= nil)
	f.env.guisvc.OpenBrowserWindow = function() return false end
	caps.fn.clipboard = nil
	f.h.click(f.h.byName("ProjectGitHub", modal.card))
	check("unavailable clipboard leaves dialog usable", not modal.closed)
	f.healthy(); f.close()
end)

for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 220 } }) do
	case("support content fits touch layout at " .. size[1] .. "x" .. size[2], function()
		local f = mobile(size[1], size[2], 1.4)
		local responsive, theme = f.env.require("ui/responsive"), f.env.require("ui/theme")
		local P = f.env.require("ui/primitives")
		local modal = f.env.require("ui/project").open()
		-- The general mock omits AutomaticSize/list measurement. Publish a tall
		-- body as the native layout would, then check the real modal's fit logic.
		modal.content:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize = f.h.dt.Vector2.new(240, 400)
		f.h.sched.advance(0.2)
		check("fixture uses actual touch metrics", responsive.isMobile() and theme.handheld)
		local position, bounds = modal.card.AbsolutePosition, modal.card.AbsoluteSize
		check("modal is bounded by the viewport", position.X >= 0 and position.Y >= 0
			and position.X + bounds.X <= size[1] + 1 and position.Y + bounds.Y <= size[2] + 1)
		local support = f.h.byName("ProjectSupport", modal.card)
		local repository = f.h.byName("ProjectRepository", modal.card)
		local field = repository:FindFirstChildOfClass("TextBox")
		local action = f.h.byName("ProjectGitHub", modal.card)
		local contentWidth = bounds.X - horizontalPadding(modal.scroll.instance) - horizontalPadding(support)
		local fieldWidth = contentWidth - horizontalPadding(field)
		local fieldPad = field:FindFirstChildOfClass("UIPadding")
		local lines = math.ceil(P.measureText(field.Text, { role = "small" }).X / math.max(1, fieldWidth))
		check("complete URL has room to wrap at enlarged text size", field.TextWrapped and fieldWidth > 0
			and repository.Size.Y.Offset >= lines * theme.text.small.height + fieldPad.PaddingTop.Offset + fieldPad.PaddingBottom.Offset)
		check("repository action fills the available row with a complete target", action.Size.X.Scale == 1 and action.Size.X.Offset == 0
			and action.Size.Y.Offset >= responsive.minTarget() and action.Parent == support and support:IsDescendantOf(modal.scroll.instance))
		local label = action:FindFirstChildWhichIsA("TextLabel", true)
		local labelWidth = P.measureText(label.Text, { textSize = label.TextSize, font = label.Font }).X
		check("star label fits without truncation", labelWidth <= contentWidth - horizontalPadding(action:FindFirstChild("Content")))
		local footerWidth = bounds.X - horizontalPadding(modal.footer)
		local actionsWidth = modal.footer:FindFirstChildOfClass("UIListLayout").Padding.Offset
		for _, name in ipairs({ "ProjectCopy", "ProjectClose" }) do
			local button = f.h.byName(name, modal.card)
			local text = button:FindFirstChildWhichIsA("TextLabel", true)
			actionsWidth = actionsWidth + P.measureText(text.Text, { textSize = text.TextSize, font = text.Font }).X
				+ horizontalPadding(button:FindFirstChild("Content"))
			check(name .. " remains available at full target height", button.Visible and button.Size.Y.Offset >= responsive.minTarget())
		end
		check("footer actions fit side by side", actionsWidth <= footerWidth)
		check("scroll body retains room for a complete action", modal.scroll.instance.Size.Y.Offset >= action.Size.Y.Offset)
		modal.close(); f.h.sched.advance(0.2)
		check("closing releases the mobile modal", #f.env.require("ui/overlay").open == 0)
		f.healthy(); f.close()
	end)
end

suite.finish()
