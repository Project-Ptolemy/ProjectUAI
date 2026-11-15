-- Synthetic pointers and external keyboards must not inflate phone UI metrics.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1 end
local function boot(platform, keyboard)
	local h = envMock.new()
	local uis = h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, true, keyboard
	if platform then uis.GetPlatform = function() return { Name = platform } end end
	h.setViewport(1280, 800)
	local client = assert(h.boot(arg[1] or "dist/uai.lua"))
	require("password_fixture")(h, client)
	h.settle(0.4); client.app.show("chat")
	return h, client
end
for _, item in ipairs({ { "synthetic mouse", nil, false }, { "Android peripherals", "Android", true }, { "iOS peripherals", "IOS", true } }) do
	local h, client = boot(item[2], item[3])
	local theme, responsive = client.env.require("ui/theme"), client.env.require("ui/responsive")
	local window, composer = client.app.window, client.app.chatPanel.composer
	composer.field.set("Keep this phone draft")
	local field = composer.field.instance
	check(item[1] .. " identifies the handheld host independently of layout", client.env.require("runtime/device").isHandheld() and responsive.isMobile() and theme.metricScale == 0.55)
	check(item[1] .. " starts with compact native controls", window.root.Size.X.Offset <= 440 and window.root.Size.Y.Offset <= 350)
	client.config.set("ui.layout", "window"); h.settle(0.4)
	check(item[1] .. " explicit Window keeps mobile dimensions and the existing field", theme.metricScale == 0.55
		and client.app.window == window and composer.field.instance == field and composer.field.get() == "Keep this phone draft")
	h.setViewport(800, 1280); h.settle(0.4)
	h.setViewport(1280, 800); h.settle(0.4)
	check(item[1] .. " rotations cannot expand the phone interface into desktop metrics", theme.metricScale == 0.55
		and responsive.isMobile() and window.root.Size.X.Offset <= 440 and window.root.Size.Y.Offset <= 350
		and composer.field.instance == field and composer.field.get() == "Keep this phone draft")
	check(item[1] .. " never overwrites normal desktop placement", not client.config.get("ui.window.placed"))
	check(item[1] .. " has no asynchronous or native property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	client.unload()
end
local h, client = boot("Windows", true)
check("a touch-capable desktop retains full native desktop metrics", not client.env.require("runtime/device").isHandheld()
	and not client.env.require("ui/responsive").isMobile() and client.env.require("ui/theme").metricScale == 1)
check("desktop controls retain their original default geometry", client.app.window.root.Size.X.Offset >= 460 and client.app.window.root.Size.Y.Offset >= 360)
local window, composer = client.app.window, client.app.chatPanel.composer
composer.field.set("Keep this desktop draft")
local field = composer.field.instance
for _, layout in ipairs({ "panel", "window", "sheet", "auto" }) do
	client.config.set("ui.layout", layout); h.settle(0.4)
	check("a touch-capable Windows desktop keeps native metrics in " .. layout,
		client.env.require("ui/theme").metricScale == 1 and not client.env.require("ui/responsive").isMobile()
		and client.app.window == window and composer.field.instance == field and composer.field.get() == "Keep this desktop draft")
end
h.setViewport(800, 1280); h.settle(0.4)
check("portrait Panel cannot switch a touch Windows desktop to handheld metrics", client.env.require("ui/responsive").mode == "panel"
	and client.env.require("ui/theme").metricScale == 1 and not client.env.require("ui/responsive").isMobile()
	and client.app.window == window and composer.field.instance == field)
h.setViewport(1280, 800); h.settle(0.4)
check("returning to landscape preserves the original desktop field and scale", client.env.require("ui/responsive").mode == "window"
	and client.env.require("ui/theme").metricScale == 1 and client.app.window == window
	and composer.field.instance == field and composer.field.get() == "Keep this desktop draft")
check("desktop parity has no asynchronous or native property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
client.unload()
print("Mobile device identity: " .. passed .. " assertions passed")
