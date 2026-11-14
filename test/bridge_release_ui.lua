-- Focused 3.1.0 client motion migration and compact sidebar checks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local checks = 0
local function check(label, condition)
	assert(condition, label)
	checks = checks + 1
	print("ok " .. label)
end
for _, mobile in ipairs({ false, true }) do
	local h = envMock.new()
	h.services.UserInputService.TouchEnabled = mobile
	h.services.UserInputService.MouseEnabled = not mobile
	h.services.GuiService.ReducedMotionEnabled = true
	h.setViewport(mobile and 390 or 1280, mobile and 844 or 820)
	local app = assert(h.boot(arg[1] or "dist/uai.lua"))
	h.settle(1)
	local allowed
	h.sched.spawn(function() allowed = app.config.continueWithoutEncryption() end)
	h.settle(1)
	assert(allowed and app.config.vaultStatus().ready, "Bridge UI fixture must complete credential setup")
	local responsive = app.env.require("ui/responsive")
	local config = app.config
	check("motion starts enabled despite platform preference", responsive.reduceMotion == false)
	check("retired setting is absent from defaults", config.defaults.ui.reduceMotion == nil)
	local snapshot = app.env.require("runtime/util").deepCopy(config.data)
	snapshot.ui.reduceMotion = "on"
	snapshot.bridge.requestTimeout = 35
	assert(config.replace(snapshot))
	h.settle(0.3)
	check("replacement strips legacy motion preference", config.get("ui.reduceMotion") == nil and not responsive.reduceMotion)
	check("replacement strips bridge request time limit", config.get("bridge.requestTimeout") == nil)
	local ui = app.env.require("runtime/util").deepCopy(config.data.ui)
	ui.reduceMotion = "auto"
	config.set("ui", ui)
	h.settle(0.3)
	check("appearance replacement cannot restore motion switch", config.data.ui.reduceMotion == nil and ui.reduceMotion == "auto")
	app.app.showSettingsDialog("general")
	h.settle(0.5)
	check("settings has no motion switch", h.byName("ReduceMotion") == nil)
	h.services.GuiService.ReducedMotionEnabled = false
	h.services.GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Fire()
	h.services.GuiService.ReducedMotionEnabled = true
	h.services.GuiService:GetPropertyChangedSignal("ReducedMotionEnabled"):Fire()
	responsive.refresh("motion-policy-check")
	h.settle(0.3)
	check("platform changes preserve enabled animations", not responsive.reduceMotion)
	if mobile then
		local sidebar = h.byName("Sidebar")
		check("mobile sidebar is present", sidebar ~= nil)
		local theme = app.env.require("ui/theme")
		check("mobile navigation is smaller than conversation captions", theme.text.sidebar.size == 9 and theme.text.sidebar.size < theme.text.caption.size)
		for _, node in ipairs(sidebar:GetDescendants()) do
			if node:IsA("TextLabel") and node.Visible then
				check("mobile sidebar uses compact readable type: " .. node.Name, node.TextSize >= 9 and node.TextSize <= 11)
			end
		end
		for _, name in ipairs({ "NewChat", "Segment_cowork", "Segment_chat", "Segment_code", "Settings", "ConversationFolders", "ProfileIdentity" }) do
			local control = assert(h.byName(name, sidebar), name)
			for _, node in ipairs(control:GetDescendants()) do
				if node:IsA("TextLabel") then check(name .. " uses compact mobile text", node.TextSize == 9) end
			end
		end
		config.set("ui.fontScale", 1.4)
		h.settle(0.5)
		check("mobile navigation still responds to text scale", theme.text.sidebar.size == 13 and theme.text.sidebar.size < theme.text.caption.size)
		h.setViewport(844, 390)
		h.settle(0.5)
		check("rotation retains compact mobile roles", theme.text.sidebar.size == 13 and h.byName("Sidebar") ~= nil)
	end
	check("no asynchronous errors", #h.errors() == 0)
	check("valid native properties", #h.instanceState.typeErrors == 0)
	app.unload()
end
print("bridge release UI: " .. checks .. " checks passed")
