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

for _, failure in ipairs({ "source", "find", "selection" }) do
	case("a failed " .. failure .. " initialization keeps Chat visible and permits a clean retry", function()
		local h, client = boot(true, 390, 844)
		local original = h.sandbox.Instance
		local store = client.env.require("runtime/code_store")
		local active, observers = store.active, store.changed:count()
		local signals = { h.services.UserInputService.InputBegan, h.services.UserInputService.InputEnded,
			h.services.UserInputService.WindowFocusReleased, h.services.RunService.Heartbeat }
		local connections = {}; for index, signal in ipairs(signals) do connections[index] = signal:Count() end
		local rejected = false
		if failure == "selection" then
			store.active = function()
				if not rejected then rejected = true; error("synthetic unavailable selection initialization") end
				return active()
			end
		end
		h.sandbox.Instance = { new = function(class, parent)
			local target = failure == "source" and "SourceScroll" or "FindSourceText"
			if failure ~= "selection" and class == "TextBox" and parent and parent.Name == target and not rejected then
				rejected = true; error("synthetic unavailable " .. failure .. " initialization")
			end
			return original.new(class, parent)
		end }
		h.click(assert(h.byName("Segment_code", client.app.screen))); h.settle(0.1)
		check("failed construction preserves the active panel", client.app.panel == "chat" and client.app.panels.chat.root.Visible)
		check("failed construction is not cached", client.app.panels.code == nil and h.byName("Panel_code", client.app.screen) == nil)
		for index, signal in ipairs(signals) do check("failed construction releases owned listener " .. index, signal:Count() == connections[index]) end
		check("failed construction releases workspace observers", store.changed:count() == observers)
		local found = false
		for _, entry in ipairs(client.env.require("runtime/log").entries) do
			if entry.message:find("panel 'code' failed to build", 1, true) then
				found = entry.message:find("synthetic unavailable " .. failure .. " initialization", 1, true) ~= nil
			end
		end
		check("the visible log message includes the actual failing operation", found)
		h.sandbox.Instance = original
		store.active = active
		h.click(assert(h.byName("Segment_code", client.app.screen))); h.settle(0.3)
		check("the next tap opens a usable workspace", client.app.panel == "code" and h.byName("SourceInput", client.app.panels.code.root) ~= nil)
		healthy(h); client.unload()
	end)
end

for _, failure in ipairs({ "create", "property", "bounds", "watch" }) do
	case("Code remains editable when native calibration cannot " .. failure, function()
		local h, client = boot(true, 390, 844)
		local original = h.sandbox.Instance
		h.sandbox.Instance = { new = function(class, parent)
			local probe = class == "TextBox" and parent and (parent.Name == "CodeEditor" or parent.Name == "PreviewMetrics")
			if probe and failure == "create" then error("synthetic unavailable metric input") end
			local node = original.new(class, parent)
			if probe then
				local native = getmetatable(node); local guarded = {}; for key, value in pairs(native) do guarded[key] = value end
				guarded.__index = function(object, key)
					if failure == "bounds" and key == "TextBounds" then error("synthetic unavailable text bounds") end
					if failure == "watch" and key == "GetPropertyChangedSignal" then
						return function() error("synthetic unavailable metric signal") end
					end
					return native.__index(object, key)
				end
				guarded.__newindex = function(object, key, value)
					if failure == "property" and key == "TextEditable" then error("synthetic unavailable probe property") end
					return native.__newindex(object, key, value)
				end
				setmetatable(node, guarded)
			end
			return node
		end }
		h.click(assert(h.byName("Segment_code", client.app.screen))); h.settle(0.2)
		local panel = assert(client.app.panels.code, "Code panel did not open")
		local box = assert(h.byName("SourceInput", panel.root))
		check("the calibration failure does not prevent navigation", client.app.panel == "code" and panel.root.Visible)
		box.Text = "local value = 42\nreturn value"; h.settle(0.1)
		check("native editing still publishes raw source", client.env.require("runtime/code_store").active().source == box.Text)
		local row = assert(h.byName("SyntaxLine", panel.root))
		check("fallback metrics keep bounded source visible", row.Visible and row.Size.Y.Offset > 0 and row.Text:find("value", 1, true))
		local preview = client.env.require("ui/code/preview").new(panel.root, box.Text, "FallbackPreview"); h.settle(0.1)
		local previewRow = assert(h.byName("SyntaxPreviewLine", preview.box))
		check("read-only previews share the calibration fallback", preview.box.Text == box.Text and not preview.box.TextEditable
			and previewRow.Visible and previewRow.Size.Y.Offset > 0)
		preview.destroy()
		h.sandbox.Instance = original
		healthy(h); client.unload()
	end)
end

suite.finish()
