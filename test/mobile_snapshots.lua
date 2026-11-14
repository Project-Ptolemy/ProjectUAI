-- Export UI instances from the shipped bundle under LuaJIT or Lune for offline image QA.
-- This is a layout preview, not a substitute for Roblox's native text renderer.
-- luajit test/mobile_snapshots.lua [bundle] [output directory] [boot|changelog|conversations|major-release]
-- lune run test/lune_runner.luau test/mobile_snapshots.lua [bundle] [output directory] [boot|changelog|conversations|major-release]
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local bundle, directory = arg[1] or "dist/uai.lua", arg[2] or "refer/mobile-20260921/current"
local engine = type(jit) == "table" and "LuaJIT" or (_VERSION == "Luau" and "Lune" or (_VERSION or "Lua"))

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
local function write(h, app, name, width, height, keyboard, revealName)
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
	file:write(h.json.encode({ name = name, engine = engine, revealName = revealName,
		width = width, height = height, keyboard = keyboard or 0,
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

if arg[3] == "major-release" then
	local function run(h, fn)
		local result
		h.sched.spawn(function() result = { fn() } end); h.settle(1)
		assert(result, "major-release fixture operation did not finish")
		return unpack(result)
	end
	local function field(h, name, root)
		return assert(assert(h.byName(name, root), "missing " .. name):FindFirstChildOfClass("TextBox"))
	end
	local function click(h, name, root)
		h.click(assert(h.byName(name, root), "missing " .. name)); h.settle(0.3)
	end
	local function lastModal(client)
		local open = client.env.require("ui/overlay").open
		for index = #open, 1, -1 do if not open[index].closed then return open[index] end end
	end
	local function clickText(h, text, root)
		local labels = h.find(root, function(node) return node:IsA("TextLabel") and node.Text == text end)
		assert(#labels == 1, "one explicit " .. text .. " action must be present")
		local button = labels[1].Parent
		while button and not button:IsA("TextButton") do button = button.Parent end
		h.click(assert(button)); h.settle(0.3)
	end
	local function beginApply(h, client, record)
		local work = { done = false }
		h.sched.spawn(function()
			work.result = client.sessions.current().applyUiMod(record.id, record.revision); work.done = true
		end)
		h.settle(0.4)
		assert(client.env.require("ui/panels/ask").current == nil, "direct Apply must not open a dedicated source question")
		return work
	end
	local scriptSpec = { version = 1, kind = "script", id = "island-review", name = "Island source review",
		description = "A complete inert Lua package for optional source inspection.", author = "Offline visual fixture",
		sources = { { label = "UI Mods guide", url = "docs/UI_MODS.md" }, { label = "Island workspace notes" } }, source = [[
-- Inert source for review.
return function(context)
	local id = context.id
	context:OnDestroy(function()
		id = nil
	end)
end
]] }
	local visualSpec = { version = 1, kind = "visual", id = "island-workspace", name = "Island workspace",
		description = "Project notes, focused tasks and live conversation readouts.", author = "Offline visual fixture",
		sources = { { label = "UI Mods guide", url = "docs/UI_MODS.md" } },
		appearance = { density = "compact", accent = "aurora" }, panels = {
			{ id = "overview", title = "Overview", description = "Keep the shoreline work together.", widgets = {
				{ id = "intro", type = "text", body = "Review the saved lighting recipe, finish the focused task, then record the result before moving on." },
				{ id = "goals", type = "metric", label = "Micro-goals", selector = "goals" },
				{ id = "context", type = "metric", label = "Conversation context", selector = "context" },
				{ id = "vault", type = "action", label = "Open Master Vault", action = "vault" },
				{ id = "plan", type = "action", label = "Open Micro-goals", action = "micro_goals" },
			} },
			{ id = "progress", title = "Progress", description = "Check the project before starting another task.", widgets = {
				{ id = "tools", type = "metric", label = "Available tools", selector = "tools" },
				{ id = "review", type = "text", body = "Saved definitions stay available after Disable. Apply starts the exact saved revision through normal tool permissions." },
				{ id = "chat", type = "action", label = "Open conversation", action = "chat" },
			} },
		} }
	for _, size in ipairs({ { 320, 568 }, { 390, 844 }, { 1280, 900 } }) do
		local width, height = size[1], size[2]
		local h = envMock.new(); h.setViewport(width, height)
		local uis = h.services.UserInputService
		uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = width < 600, width >= 600, width >= 600
		local client = assert(h.boot(bundle))
		assert(client.env.info.version == "4.0.0", "major-release snapshots require the 4.0.0 bundle")
		client.config.set("ui.tutorial.seen", true, { quiet = true })
		require("password_fixture")(h, client); h.settle(2)
		client.config.set("permissions.mode", "full")
		local prefix = "major-release-" .. width .. "x" .. height
		local session = client.sessions.current(); session.rename("Island workspace")
		local provider = client.providers.blank("custom")
		provider.id, provider.label, provider.baseUrl = "workspace-preview", "Workspace preview", "https://snapshot.invalid/v1"
		provider.model, provider.models = "fixture/planning-model-with-detailed-attribution", { "fixture/planning-model-with-detailed-attribution" }
		assert(client.providers.save(provider, { force = true })); client.providers.setActive(provider.id)
		local function capture(label, revealName) write(h, client, prefix .. "-" .. label, width, height, nil, revealName) end
		local function captureEnds(label, scroll)
			scroll.CanvasPosition = h.dt.Vector2.new(0, 0); capture(label .. "-top")
			-- The renderer clamps the large offset to the complete content's bottom.
			scroll.CanvasPosition = h.dt.Vector2.new(0, 1000000); capture(label .. "-bottom")
			scroll.CanvasPosition = h.dt.Vector2.new(0, 0)
		end
		local vault = client.env.require("runtime/master_vault")
		local note = assert(run(h, function() return vault.save({ title = "Island shoreline lighting recipe", kind = "recipe",
			description = "A reusable starting point for the island's dock and shoreline.", scope = "global", status = "draft",
			tags = { "island", "lighting", "recipe" }, sources = { { label = "Island design notes", url = "docs/SCRIPT_DEVELOPMENT.md" } },
			content = "# Shoreline lighting\n\nKeep the central beach open and guide players toward the dock.\n\n- Use warm lights beside the path.\n- Keep the lighthouse visible from the beach.\n- Record the checked instance settings before reusing this recipe." }) end))
		assert(run(h, function() return vault.save({ title = "Island dock remote contract", kind = "remote", scope = "global", status = "draft",
			description = "Keep the documented inputs and expected results with the project.", tags = { "island", "remote" },
			content = "# Dock interaction contract\n\nDocument the owning script, input arguments and expected result before connecting the interaction." }) end))
		assert(run(h, function() return vault.save({ title = "Island path instance configuration", kind = "instance", scope = "global", status = "draft",
			description = "Reuse the path configuration and keep its review history.", tags = { "island", "instances" },
			content = "# Path configuration\n\nKeep the material, dimensions, collision and lighting settings together in one portable reference." }) end))
		client.app.show("vault"); h.settle(0.5)
		field(h, "VaultSearch", client.app.screen).Text = "island"; h.settle(0.5)
		captureEnds("vault-browser", assert(client.app.panels.vault).scroll.instance)
		local editor = client.env.require("ui/vault_editor")
		local editing = assert(editor.open(note))
		field(h, "VaultNoteContent", editing.card).Text = note.content .. "\n\nNext review: confirm the warm lighting beside the dock."
		capture("vault-editor-top")
		click(h, "VaultNoteDetails", editing.card)
		editing.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 1000000); capture("vault-editor-details")
		click(h, "VaultDiscardDraft", editing.card)
		clickText(h, "Discard", assert(lastModal(client)).footer)
		assert(editing.closed and #editor.listDrafts() == 0, "the illustrated Vault draft must be explicitly discarded")
		local function updateGoals(args)
			local value = session.goalsSnapshot()
			if value then args.expected_id, args.expected_revision = value.id, value.revision end
			return assert(run(h, function() return session.updateGoals(args) end))
		end
		updateGoals({ action = "start", objective = "Build a reusable island workspace with documented lighting and a focused review plan.", tasks = {
			{ id = "notes", text = "Read the shoreline recipe", criterion = "The saved lighting recipe and its sources have been read." },
			{ id = "layout", text = "Refine the dock and path layout", criterion = "The dock stays visible and the central beach remains open.", depends_on = { "notes" } },
			{ id = "reference", text = "Review the project reference image", criterion = "The new layout can be compared with the chosen reference." },
			{ id = "record", text = "Record the checked instance settings", criterion = "The saved note lists the reviewed dimensions and lighting settings.", depends_on = { "layout" } },
		} })
		updateGoals({ action = "status", id = "notes", status = "active" })
		updateGoals({ action = "status", id = "notes", status = "done", evidence = "Fixture review: the shoreline recipe, tags and source reference were read." })
		updateGoals({ action = "status", id = "layout", status = "active" })
		updateGoals({ action = "status", id = "reference", status = "blocked", blocker = "The chosen reference image has not been supplied yet." })
		local board = assert(client.app.showGoals()); captureEnds("micro-goals", board.scroll.instance)
		board.close(); h.settle(0.3)
		assert(not client.env.require("ui/goals").hasDrafts())
		local mods = client.env.require("runtime/ui_mods")
		local scriptRecord = assert(run(h, function() return mods.save(scriptSpec) end))
		local visualRecord = assert(run(h, function() return mods.save(visualSpec) end))
		local manager = assert(client.app.showUiMods()); captureEnds("mod-manager", manager.scroll.instance)
		-- Inspect the saved script through its optional Details view without Apply.
		click(h, "UiModRead_" .. scriptRecord.id, manager.card)
		local scriptPreview = assert(lastModal(client))
		assert(scriptPreview.card.Name == "UiModDetails" and field(h, "UiModPreviewSource", scriptPreview.card).Text == scriptSpec.source)
		captureEnds("script-preview", scriptPreview.scroll.instance)
		scriptPreview.scroll.instance.CanvasPosition = h.dt.Vector2.new(0, 220); capture("script-preview-source")
		scriptPreview.close(); manager.close(); h.settle(0.4)
		assert(mods.getActive() == nil and not client.env.require("runtime/ui_mod_runner").state().active)
		local asks = client.env.require("ui/panels/ask")
		assert(asks.current == nil and #asks.queue == 0)
		-- Only this declarative visual fixture receives direct Apply for live panels.
		local visualWork = beginApply(h, client, visualRecord); h.settle(0.5)
		assert(visualWork.done and visualWork.result.ok and visualWork.result.data.applied and mods.getActive().id == visualSpec.id)
		client.app.show("mods"); h.settle(0.4)
		captureEnds("live-panels", assert(h.byName("UiModsWorkspace", client.app.screen)))
		click(h, "UiModTab_progress", client.app.screen); capture("live-progress")
		client.config.set("ui.fontScale", 1.4, { transient = true }); client.app.flushAppearance(); h.settle(0.5)
		client.app.show("chat"); h.settle(0.3)
		local prompt = "What should I focus on next for the island workspace?"
		local reply = "Focus on the **dock and path layout**. Keep the central beach open, then save the reviewed settings in Master Vault."
		session.ctx.pushUser(prompt); session.emit("user", { text = prompt })
		session.ctx.pushAssistant({ content = reply, model = provider.model, outputTokens = 240, requestMs = 3200 })
		session.emit("assistant:text", { text = reply, model = provider.model, outputTokens = 240, requestMs = 3200 })
		session.emit("assistant:complete", {}); h.settle(0.4)
		local rate = assert(h.byName("RequestTokenRate", client.app.chatPanel.view.agentHandle.root))
		assert(client.config.get("ui.fontScale") == 1.4 and rate.Visible and rate.Text == "75.0 tk/s request avg")
		-- The mock lacks AutomaticSize geometry. Reveal the response footer after
		-- Chromium measures its approximate transcript instead of using mock offsets.
		capture("chat-rate-high-font", "RequestTokenRate")
		client.app.chatPanel.view.agentHandle.setRequestMetrics(1e12, 1); h.settle(0.2)
		assert(h.byName("RequestTokenRate", client.app.chatPanel.view.agentHandle.root).Text == "1e+15 tk/s request avg")
		capture("chat-rate-long-high-font", "RequestTokenRate")
		assert(run(h, client.disableUiMods).ok)
		client.env.require("ui/overlay").closeAll(); h.settle(0.3)
		assert(asks.current == nil and #asks.queue == 0 and #editor.listDrafts() == 0
			and not client.env.require("ui/goals").hasDrafts() and not client.env.require("ui/mods").hasDrafts())
		assert(not client.env.require("runtime/ui_mod_runner").state().active, "snapshot source must remain unexecuted")
		assert(client.destroy() ~= false); h.settle(0.3)
		assert(#h.errors() == 0 and #h.instanceState.typeErrors == 0, "major-release snapshot cleanup must finish cleanly")
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
