-- Artwork integration against the built native client, including real settings
-- and authenticated application lifecycle. Layout is still the offline mock.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Native seasonal artwork")
local case, check = suite.case, suite.check
local SCENES = {
	{ "halloween", "Halloween", "Pumpkin", "Ghost" },
	{ "christmas", "Christmas", "FirTree", "Gift" },
	{ "newyear", "NewYear", "CelebrationStars", "Firework1" },
	{ "valentine", "Valentine", "Heart2", "Heart1" },
	{ "earthday", "EarthDay", "Globe", "EarthLeaves1" },
	{ "pride", "Pride", "RainbowRibbon", "RainbowCloud1" },
	{ "peace", "Peace", "Dove", "OliveBranch1" },
}

local function boot(theme, width, height, mobile, date)
	local f = F.new(); local h = f.h
	h.services.UserInputService.TouchEnabled = mobile == true
	h.setViewport(width or 1280, height or 820)
	if date then
		local original = h.sandbox.DateTime.now
		h.sandbox.DateTime.now = function()
			local value = original()
			value.ToLocalTime = function() return { Year = 2026, Month = date.month, Day = date.day } end
			return value
		end
	end
	-- This fixture has already made the explicit storage choice; normal Settings
	-- and window controls must stay subject to the application's password gate.
	h.files["UAI/config.json"] = h.json.encode({
		version = 1,
		ui = { theme = theme, seasonalThemes = true, tutorial = { seen = true }, communityInvite = { disabled = true } },
		security = { rememberCredentials = true, credentialProtection = "unprotected" },
		bridge = { autoDiscover = false }, agent = { autoFreeRouting = false }, fs = { migrated = true },
	})
	local handle = assert(h.boot("dist/uai.lua")); h.settle(1)
	check("fixture enters the authenticated app", handle.config.vaultStatus().ready and handle.app.window.visible)
	return f, h, handle, handle.app
end

local function clearance(h, app)
	local band = assert(app.seasonalBand)
	local header = app.window.header
	local headerBottom = header.AbsolutePosition.Y + header.AbsoluteSize.Y
	local artBottom = band.AbsolutePosition.Y + band.AbsoluteSize.Y
	check("artwork has a dedicated strip below the title and window controls", band.Parent == app.mainHolder
		and band.Visible and band.ClipsDescendants and band.AbsoluteSize.Y >= 36
		and band.AbsolutePosition.Y >= headerBottom - 0.001)
	check("panels start below the artwork instead of drawing beneath it", app.body.AbsolutePosition.Y >= artBottom - 0.001
		and band.AbsoluteSize.X <= app.mainHolder.AbsoluteSize.X + 0.001)
	for _, name in ipairs({ "Minimize", "Maximise", "Close" }) do
		local button = assert(h.byName(name, header))
		check(name .. " keeps its own clear header area", button.Visible and button.AbsolutePosition.Y + button.AbsoluteSize.Y <= band.AbsolutePosition.Y + 0.001)
	end
end

local function healthy(f, h, handle)
	check("native properties and tasks remain valid", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	local art = handle.app.seasonalArt
	handle.destroy(); h.settle(0.5)
	check("unload releases art and all application resources", (not art or not art.Alive) and handle.env.require("runtime/dispose").count() == 0)
	f.healthy(); f.close()
end

case("all seven native themes mount recognizable artwork and retain conversation drafts", function()
	local f, h, handle, app = boot("halloween")
	local session = handle.sessions.current()
	app.chatPanel.composer.field.set("Keep this seasonal draft")
	session.emit("user", { text = "An existing conversation" })
	local eventIndex = #session.log
	local retainedEvent = session.log[eventIndex]
	check("fixture retains the existing user conversation", retainedEvent.kind == "user" and retainedEvent.text == "An existing conversation")
	h.settle(0.4)
	local previous
	for _, scene in ipairs(SCENES) do
		handle.config.set("ui.theme", scene[1], { transient = true }); h.settle(0.5)
		local art = assert(app.seasonalArt)
		check(scene[2] .. " mounts the shared scene", art.SceneName == scene[2] and art.Root:GetAttribute("SeasonalTheme") == scene[2])
		check(scene[2] .. " has recognizable primary and companion motifs", h.byName(scene[3], art.Root) and h.byName(scene[4], art.Root))
		check(scene[2] .. " respects the shared node budget", art.NodeCount <= handle.env.require("ui/seasonal_art").MaxNodes
			and #art.Root:GetDescendants() + 1 == art.NodeCount)
		for _, node in ipairs(art.Root:GetDescendants()) do
			check(scene[2] .. " uses noninteractive native artwork", not node:IsA("GuiButton") and not node:IsA("TextBox") and not node:IsA("ImageLabel")
				and (not node:IsA("GuiObject") or (not node.Active and not node.Selectable)))
		end
		clearance(h, app)
		check("theme changes retain the selected conversation and editable draft", handle.sessions.current() == session
			and app.chatPanel.composer.field.get() == "Keep this seasonal draft" and session.log[eventIndex] == retainedEvent)
		if previous then check("outgoing artwork is released during theme replacement", not previous.Alive and previous.Root.Parent == nil) end
		previous = art
	end
	local root = app.seasonalArt.Root
	local nodeCount = #root:GetDescendants()
	h.sched.advance(120); h.settle(0.2)
	check("static scenes do not add frames or rebuild on ordinary minutes", app.seasonalArt.Root == root and #root:GetDescendants() == nodeCount)
	local field = app.chatPanel.composer.field.instance
	h.click(assert(h.byName("Minimize", app.window.header))); h.settle(0.2)
	check("minimize keeps the art and draft mounted", not app.window.visible and app.seasonalArt.Root == root and app.chatPanel.composer.field.instance == field)
	handle.show("chat"); h.settle(0.3)
	check("restoring retains the same seasonal scene", app.window.visible and app.seasonalArt.Root == root)
	healthy(f, h, handle)
end)

case("mobile rotation and keyboard layouts reserve controls while artwork remains owned", function()
	local f, h, handle, app = boot("halloween", 390, 844, true)
	clearance(h, app)
	local art, field = app.seasonalArt, app.chatPanel.composer.field.instance
	app.chatPanel.composer.field.set("A mobile draft")
	field:CaptureFocus(); field.CursorPosition, field.SelectionStart = 8, 2
	handle.config.set("ui.sidebarCollapsed", true, { transient = true }); h.settle(0.3)
	check("collapsing the sidebar keeps the seasonal art and working field", not app.sideHolder.Visible and app.seasonalArt == art and app.chatPanel.composer.field.instance == field)
	clearance(h, app)
	h.setViewport(844, 390); h.settle(0.4)
	check("rotation retains the original artwork and draft selection", app.seasonalArt == art and app.chatPanel.composer.field.instance == field
		and field.Text == "A mobile draft" and field.CursorPosition == 8 and field.SelectionStart == 2)
	clearance(h, app)
	local input = h.services.UserInputService
	input.OnScreenKeyboardVisible, input.OnScreenKeyboardPosition, input.OnScreenKeyboardSize = true, h.dt.Vector2.new(0, 150), h.dt.Vector2.new(844, 240)
	input:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); h.settle(0.5)
	check("short keyboard view gives decorative space back to the panel", not app.seasonalBand.Visible
		and app.body.Position.Y.Offset == app.window.headerHeight and app.seasonalArt == art)
	check("keyboard reflow keeps the draft and its native field", app.chatPanel.composer.field.instance == field and field.Text == "A mobile draft")
	input.OnScreenKeyboardVisible = false
	input:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); h.settle(0.4)
	check("dismissal restores the original seasonal scene", app.seasonalBand.Visible and app.seasonalArt == art)
	clearance(h, app)
	healthy(f, h, handle)
end)

case("automatic dates and the existing Settings switch add and remove native art", function()
	local date = { month = 10, day = 29 }
	local f, h, handle, app = boot("default", 1280, 820, false, date)
	check("Standard has no seasonal strip", app.seasonalBand == nil and app.body.Position.Y.Offset == app.window.headerHeight)
	app.chatPanel.composer.field.set("Keep the calendar draft")
	date.day = 30; h.sched.advance(60); h.settle(0.5)
	check("October 30 mounts pumpkin and ghost artwork automatically", app.seasonalArt and app.seasonalArt.SceneName == "Halloween")
	clearance(h, app)
	local old = app.seasonalArt
	local dialog = assert(app.showSettingsDialog("general")); h.settle(0.3)
	local row
	for _, node in ipairs(dialog.card:GetDescendants()) do
		if node:GetAttribute("UAISettingPath") == "ui.seasonalThemes" then row = node; break end
	end
	h.click(assert(h.byName("Switch", assert(row)))); h.settle(0.5)
	check("the Project UAI Settings switch removes automatic artwork", handle.config.get("ui.seasonalThemes") == false and app.seasonalArt == nil
		and not old.Alive and app.body.Position.Y.Offset == app.window.headerHeight)
	check("Settings opt-out retains the conversation draft", app.chatPanel.composer.field.get() == "Keep the calendar draft")
	dialog.close(); h.settle(0.3)
	handle.config.set("ui.seasonalThemes", true, { transient = true }); h.settle(0.5)
	check("the automatic preference can restore seasonal artwork", app.seasonalArt and app.seasonalArt.SceneName == "Halloween")
	old = app.seasonalArt
	date.month, date.day = 11, 3; h.sched.advance(60); h.settle(0.5)
	check("November 3 clears the strip and restores its space", app.seasonalArt == nil and app.seasonalBand == nil and not old.Alive
		and app.body.Position.Y.Offset == app.window.headerHeight)
	healthy(f, h, handle)
end)

suite.finish()
