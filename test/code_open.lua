-- Open Code through the shipped app, including hosts that cannot clone inputs.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Code first open")
local case, check = suite.case, suite.check
local function boot(touch, width, height)
	local h = require("env").new()
	h.services.UserInputService.TouchEnabled, h.services.UserInputService.MouseEnabled = touch, not touch
	h.setViewport(width, height)
	local client = assert(h.boot(arg[1]))
	require("password_fixture")(h, client)
	client.app.show("chat"); h.settle(0.2)
	return h, client
end
local function healthy(h)
	check("no asynchronous errors", #h.errors() == 0)
	check("valid GUI property types", #h.instanceState.typeErrors == 0)
end

for _, dimensions in ipairs({ { true, 390, 844 }, { true, 844, 390 }, { false, 1280, 800 } }) do
	case("sidebar opens Code at " .. dimensions[2] .. "x" .. dimensions[3] .. " with non-cloneable text inputs", function()
		local h, client = boot(unpack(dimensions))
		check("Code is built lazily", client.app.panels.code == nil)
		local original = h.sandbox.Instance
		h.sandbox.Instance = { new = function(class, parent)
			local node = original.new(class, parent)
			if class == "TextBox" then node.Archivable = false end
			return node
		end }
		local button = assert(h.byName("Segment_code", client.app.screen))
		-- The mock resolves scale/offset geometry; native UIListLayout owns flex width.
		local flex = assert(button:FindFirstChildOfClass("UIFlexItem"))
		check("the Code tab is enabled in the shared navigation row", button.Visible and button.Active and button.Selectable
			and button.AbsoluteSize.Y > 0 and button.Parent.AbsoluteSize.X > 0 and flex.FlexMode == h.sandbox.Enum.UIFlexMode.Fill)
		h.click(button); h.settle(0.3)
		local panel = assert(client.app.panels.code, "Code panel did not open")
		local box = assert(h.byName("SourceInput", panel.root))
		check("navigation selects and shows Code", client.app.panel == "code" and panel.root.Visible)
		check("the native input cannot be cloned", box:Clone() == nil)
		box.Text = "-- mobile draft\nreturn 42"; h.settle(0.1)
		check("editing publishes the exact draft", client.env.require("runtime/code_store").active().source == box.Text)
		h.click(assert(h.byName("Segment_chat", client.app.screen)))
		h.click(button); h.settle(0.1)
		check("reopening retains the editor and draft", client.app.panels.code == panel and h.byName("SourceInput", panel.root) == box and box.Text == "-- mobile draft\nreturn 42")
		healthy(h); client.unload()
	end)
end

case("a failed first open keeps Chat visible and permits a clean retry", function()
	local h, client = boot(true, 390, 844)
	local original = h.sandbox.Instance
	local connections = h.services.UserInputService.InputBegan:Count()
	local rejected = false
	h.sandbox.Instance = { new = function(class, parent)
		if class == "TextBox" and not rejected then rejected = true; error("synthetic unavailable input") end
		return original.new(class, parent)
	end }
	h.click(assert(h.byName("Segment_code", client.app.screen))); h.settle(0.1)
	check("failed construction preserves the active panel", client.app.panel == "chat" and client.app.panels.chat.root.Visible)
	check("failed construction is not cached", client.app.panels.code == nil and h.byName("Panel_code", client.app.screen) == nil)
	check("failed construction releases its input listeners", h.services.UserInputService.InputBegan:Count() == connections)
	h.sandbox.Instance = original
	h.click(assert(h.byName("Segment_code", client.app.screen))); h.settle(0.3)
	check("the next tap opens a usable workspace", client.app.panel == "code" and h.byName("SourceInput", client.app.panels.code.root) ~= nil)
	healthy(h); client.unload()
end)

suite.finish()
