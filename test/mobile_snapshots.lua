-- Export UI instances from the shipped bundle under Lune for offline image QA.
-- This is a layout preview, not a substitute for Roblox's native text renderer.
-- lune run test/lune_runner.luau test/mobile_snapshots.lua [bundle] [output directory] [boot|changelog|conversations]
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local bundle, directory = arg[1] or "dist/uai.lua", arg[2] or "refer/mobile-20260921/current"

local properties = {
	"Size", "Position", "AnchorPoint", "Visible", "AutomaticSize", "BackgroundColor3", "BackgroundTransparency",
	"BorderSizePixel", "ClipsDescendants", "ZIndex", "LayoutOrder", "Rotation", "Text", "TextSize", "TextColor3", "TextTransparency",
	"TextXAlignment", "TextYAlignment", "TextWrapped", "TextTruncate", "RichText", "Font", "LineHeight", "MultiLine",
	"PlaceholderText", "PlaceholderColor3", "Image", "ImageColor3", "ImageTransparency", "ScaleType",
	"FillDirection", "SortOrder", "Padding", "HorizontalAlignment", "VerticalAlignment", "Wraps", "FlexMode",
	"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "CornerRadius", "Color", "Thickness", "Transparency",
	"MinSize", "MaxSize", "AspectRatio", "CanvasPosition", "ScrollingDirection", "ScrollBarThickness", "ScrollingEnabled",
}
local function serialize(value)
	if type(value) == "number" and (value == math.huge or value == -math.huge) then return value > 0 and 1000000 or -1000000 end
	if type(value) ~= "table" then return value end
	if value.EnumType then return value.Name end
	if value.R then return { value.R, value.G, value.B } end
	if value.X and type(value.X) == "table" then
		return { value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset }
	end
	if value.X then return { serialize(value.X), serialize(value.Y) } end
	if value.Scale then return { value.Scale, value.Offset } end
	return tostring(value)
end
local function tree(node)
	local out = { class = node.ClassName, name = node.Name, props = {}, children = {} }
	for _, key in ipairs(properties) do
		if node.__props[key] ~= nil or node.__defaults[key] ~= nil then
			out.props[key] = serialize(node[key])
		end
	end
	for _, child in ipairs(node:GetChildren()) do
		if child:IsA("GuiObject") or child:IsA("UIComponent") then out.children[#out.children + 1] = tree(child) end
	end
	return out
end
local function write(h, app, name, width, height, keyboard)
	h.settle(0.4)
	-- The offline instance harness resolves scale/offset geometry on read. Fire
	-- the size notifications Roblox would publish after showing/resizing a view,
	-- so responsive grids and pinned regions are captured after their reflow.
	for _ = 1, 3 do
		for _, node in ipairs(app.app.screen:GetDescendants()) do
			local signal = node.__signals.__prop_AbsoluteSize
			if signal and node.Parent then signal:Fire() end
		end
		h.settle(0.05)
	end
	assert(#h.errors() == 0, "asynchronous errors in " .. name)
	assert(#h.instanceState.typeErrors == 0, "invalid properties in " .. name)
	local file = assert(io.open(directory .. "/" .. name .. ".json", "wb"))
	file:write(h.json.encode({ name = name, width = width, height = height, keyboard = keyboard or 0,
		window = tree(app.app.window.root), root = tree(app.app.screen) }))
	file:close()
	print("snapshot " .. name)
end

if arg[3] == "boot" then
	for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 390 }, { 1280, 720 } }) do
		local width, height = size[1], size[2]
		local h = envMock.new(); h.setViewport(width, height)
		local app = assert(h.boot(bundle)); h.settle(2)
		-- Preview time follows the virtual scheduler for elapsed/slow-state scenes.
		h.sandbox.os = setmetatable({ clock = function() return h.sched.now end }, { __index = os })
		local boot = app.env.require("ui/boot").show()
		local surface = { app = { screen = boot.screen, window = { root = boot.card } } }
		local prefix = "boot-" .. width .. "x" .. height
		boot.step("runtime/config", 24, app.env.moduleTotal)
		write(h, surface, prefix .. "-prepare", width, height)
		boot.stage("restore"); boot.step("agent/session", 88, app.env.moduleTotal)
		write(h, surface, prefix .. "-restore", width, height)
		boot.stage("interface"); boot.step("ui/app", app.env.moduleCount, app.env.moduleTotal)
		write(h, surface, prefix .. "-interface", width, height)
		h.frame(8.2)
		write(h, surface, prefix .. "-slow", width, height)
		boot.fail("synthetic startup failure")
		write(h, surface, prefix .. "-failed", width, height)
		boot.destroy(); app.destroy()
	end
	return
end

if arg[3] == "changelog" then
	for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 1280, 720 } }) do
		local width, height = size[1], size[2]
		local h = envMock.new(); h.setViewport(width, height)
		h.services.UserInputService.TouchEnabled = width < 600
		local app = assert(h.boot(bundle))
		app.config.set("ui.tutorial.seen", true, { quiet = true })
		require("password_fixture")(h, app); h.settle(2)
		local modal = assert(app.app.showChangelog())
		local prefix = "changelog-" .. width .. "x" .. height
		write(h, app, prefix .. "-top", width, height)
		local search = assert(h.byName("ReleaseSearch", modal.content):FindFirstChildWhichIsA("TextBox"))
		search.Text = app.env.require("runtime/changelog").latest().version
		modal.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 2200)
		write(h, app, prefix .. "-latest-middle", width, height)
		-- Chromium clamps this to the measured bottom of the filtered content.
		modal.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 1000000)
		write(h, app, prefix .. "-latest-bottom", width, height)
		search.Text = ""
		modal.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 1000000)
		write(h, app, prefix .. "-history-bottom", width, height)
		modal.close(); app.destroy()
	end
	return
end

if arg[3] == "conversations" then
	for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 390 }, { 1280, 720 } }) do
		local width, height = size[1], size[2]
		local h = envMock.new(); h.setViewport(width, height)
		h.services.UserInputService.TouchEnabled = width < 900
		local app = assert(h.boot(bundle))
		app.config.set("ui.tutorial.seen", true, { quiet = true })
		require("password_fixture")(h, app); h.settle(2)
		local first
		for index = 1, 12 do
			local session = assert(app.sessions.newThread({ id = "browser-preview-" .. index, activate = false }))
			session.rename(index == 1 and "Island planning: a long conversation title about paths, lighting and the shoreline" or "Island project " .. index)
			session.emit("user", { text = "Review the shoreline and lighting before adding the lighthouse and dock." })
			if index == 1 then first = session; session.setPinned(true) end
		end
		local modal = assert(app.env.require("ui/conversations").browse(app.app))
		local prefix = "conversations-" .. width .. "x" .. height
		write(h, app, prefix .. "-top", width, height)
		modal.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 1000000)
		write(h, app, prefix .. "-bottom", width, height)
		modal.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 0)
		local search = assert(h.byName("ConversationSearch", modal.content):FindFirstChildWhichIsA("TextBox"))
		search.Text = "shoreline"
		write(h, app, prefix .. "-search", width, height)
		search.Text = "planning"
		write(h, app, prefix .. "-one", width, height)
		search.Text = "no-matching-conversation"
		write(h, app, prefix .. "-empty", width, height)
		modal.close(); h.settle(0.4)
		local transcript = assert(app.env.require("ui/chat/search").open(first))
		h.byName("TranscriptSearch", transcript.content):FindFirstChildWhichIsA("TextBox").Text = "shoreline"
		write(h, app, prefix .. "-transcript", width, height)
		transcript.close(); app.destroy()
	end
	return
end

for _, size in ipairs({ { 844, 390 }, { 932, 430 }, { 1194, 834 }, { 390, 844 }, { 1280, 720, true }, { 1920, 1080, true } }) do
	local width, height, desktop = size[1], size[2], size[3]
	local h = envMock.new()
	local uis = h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = not desktop, desktop == true, desktop == true
	h.setViewport(width, height)
	local app = assert(h.boot(bundle)); h.settle(1); app.app.show("chat")
	local prefix = (desktop and "desktop-" or "mobile-") .. width .. "x" .. height
	local providers = app.providers
	local provider = providers.blank("custom")
	provider.id, provider.label, provider.baseUrl, provider.key = "preview", "Preview endpoint", "https://preview.invalid/v1", "fixture"
	provider.model = "claude-opus-5"
	provider.models = { "claude-opus-5", "claude-sonnet-5", "gpt-5", "qwen3-coder", "deepseek-r1", "vendor/free:free" }
	assert(providers.save(provider, { force = true })); providers.setActive(provider.id)
	write(h, app, prefix .. "-home", width, height)
	local view = app.app.chatPanel.view
	view.replaying = true
	view.render({ kind = "user", text = "What should I improve on this island?" })
	view.render({ kind = "assistant:text", text = "Start with the **shoreline and lighting**. A few focused changes will make the island easier to explore.\n\n- Add a dock beside the lighthouse.\n- Use warm lights to guide the path.\n- Keep the central beach open for players." })
	view.replaying = false
	write(h, app, prefix .. "-chat", width, height)
	local composer = app.app.chatPanel.composer
	composer.field.set("Build a cozy island with a lighthouse.\nAdd a dock and warm lighting by the water.")
	composer.setExpanded(true, false)
	write(h, app, prefix .. "-compose", width, height)
	if not desktop then
		local keyboard = math.floor(height * (width > height and 0.52 or 0.36))
		uis.OnScreenKeyboardSize = h.dt.Vector2.new(width, keyboard)
		uis.OnScreenKeyboardVisible = true
		uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
		write(h, app, prefix .. "-keyboard", width, height, keyboard)
		uis.OnScreenKeyboardVisible = false
		uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire()
	end
	for index = 1, 13 do
		h.settle(0.05) -- Distinct timestamps make history order deterministic in both runtimes.
		app.sessions.newThread().rename("Island project " .. index)
	end
	app.app.showAppMenu(h.byName("Nav_menu", app.app.window.root) or h.byName("Nav_collapse", app.app.window.root))
	write(h, app, prefix .. "-navigation", width, height)
	app.env.require("ui/overlay").closeAll(); h.settle(0.4)
	local settings = app.app.showSettingsDialog("general")
	write(h, app, prefix .. "-settings", width, height)
	settings.close(); h.settle(0.4)
	local picker = app.env.require("ui/panels/modelpicker").open()
	write(h, app, prefix .. "-models", width, height)
	picker.close(); h.settle(0.4)
	local context = app.sessions.current().ctx
	for index = 1, 12 do
		context.pushUser(("Keep the lighthouse. "):rep(60))
		context.pushAssistant({ content = ("Work on the dock. "):rep(80) })
	end
	context.summary = ("Preserve the shoreline and warm lights. "):rep(80)
	context.calibrate(context.tokens() + 12000)
	app.config.set("agent.forceContext", { ["claude-opus-5"] = 80000 })
	local inspector = app.env.require("ui/chat/context").open(app.sessions.current())
	write(h, app, prefix .. "-context", width, height)
	inspector.close(); h.settle(0.4)
	app.app.show("providers")
	write(h, app, prefix .. "-providers", width, height)
	app.unload()
end
