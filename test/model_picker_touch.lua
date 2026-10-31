-- Touch-only boots use the real handheld metrics from the shipped bundle.
-- Bounds are synthetic native geometry, not a claim about Roblox raster output.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(name, value) assert(value, name); passed = passed + 1 end

for _, size in ipairs({ { 320, 640 }, { 844, 390 } }) do
	local h = envMock.new()
	local uis = h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled, uis.KeyboardEnabled = true, false, false
	h.setViewport(size[1], size[2])
	local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.5)
	local record = app.providers.blank("custom")
	record.label, record.baseUrl, record.authStyle = "Touch fixture", "https://touch.fixture/v1", "none"
	record.model, record.models = "claude-opus-5", { "claude-opus-5" }
	for index = 2, 12 do record.models[index] = "fixture-" .. index .. "-free" end
	assert(app.providers.save(record)); app.providers.setActive(record.id)
	local windowPosition, windowSize = app.app.window.root.Position, app.app.window.root.Size
	local picker = app.env.require("ui/panels/modelpicker").open(); h.settle(0.3)
	check("picker leaves the main window's placement intact", app.app.window.root.Position == windowPosition and app.app.window.root.Size == windowSize)
	check("picker is inside the physical viewport", picker.card.AbsolutePosition.X >= 0 and picker.card.AbsolutePosition.Y >= 0
		and picker.card.AbsolutePosition.X + picker.card.AbsoluteSize.X <= size[1]
		and picker.card.AbsolutePosition.Y + picker.card.AbsoluteSize.Y <= size[2])
	check("portrait picker can use more than the old compact height", size[2] < 500 or picker.card.AbsoluteSize.Y > 400)
	for _, name in ipairs({ "Section_Endpoint", "FreeOnly", "Model_claude-opus-5", "FetchModels", "ModelOptions", "PickerDone", "Close" }) do
		local node = assert(h.byName(name, picker.card), name)
		check(name .. " has a 40px touch target", node.AbsoluteSize.X >= 40 and node.AbsoluteSize.Y >= 40)
	end
	local search = h.byName("ModelFilter", picker.card)
	check("model search has a 40px touch target", search.AbsoluteSize.Y >= 40)
	for _, node in ipairs(picker.card:GetDescendants()) do
		if (node:IsA("TextLabel") or node:IsA("TextBox")) and node.Text ~= "" then check("text respects the handheld reading floor", node.TextSize >= 10) end
	end
	local list = h.byName("ModelScroll", picker.card)
	local effort = h.byName("Section_ReasoningEffort", picker.card)
	check("reasoning levels stay visible in portrait and short landscape pickers", effort.Visible
		and h.byName("EffortPills", picker.card).AbsoluteSize.Y >= 40
		and list.AbsolutePosition.Y + list.AbsoluteSize.Y < effort.AbsolutePosition.Y
		and effort.AbsolutePosition.Y + effort.AbsoluteSize.Y <= picker.footer.AbsolutePosition.Y)
	check("only the model catalog scrolls", not picker.scroll.instance.ScrollingEnabled and list.ScrollingEnabled)
	list.CanvasPosition = h.dt.Vector2.new(0, 60)
	uis.OnScreenKeyboardSize, uis.OnScreenKeyboardVisible = h.dt.Vector2.new(size[1], math.floor(size[2] * 0.55)), true
	uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); h.settle(0.3)
	check("keyboard keeps the catalog as the scrolling owner", not picker.scroll.instance.ScrollingEnabled and list.ScrollingEnabled)
	check("keyboard leaves a bounded model viewport", list.Size.Y.Offset > 0 and list.Position.Y.Offset + list.Size.Y.Offset <= picker.scroll.viewportSize().Y)
	check("keyboard retains the current model scroll", list.CanvasPosition.Y == 60)
	check("footer actions stay outside the model viewport", picker.footer.Parent == picker.card)
	local provider = h.byName("Section_Endpoint", picker.card)
	local providerPosition, searchPosition = provider.AbsolutePosition, search.AbsolutePosition
	list.CanvasPosition = h.dt.Vector2.new(0, 120); h.settle(0.1)
	check("scrolling models leaves provider and search fixed", provider.AbsolutePosition == providerPosition and search.AbsolutePosition == searchPosition
		and picker.scroll.instance.CanvasPosition.Y == 0)
	if size[2] >= 500 then
		check("portrait keyboard space keeps the reasoning levels visible", effort.Visible
			and list.AbsolutePosition.Y + list.AbsoluteSize.Y < effort.AbsolutePosition.Y
			and effort.AbsolutePosition.Y + effort.AbsoluteSize.Y <= picker.footer.AbsolutePosition.Y)
		h.click(h.byName("Effort_medium", picker.card)); h.settle(0.1)
		check("visible levels change the real preference above the keyboard", app.config.get("agent.effort") == "medium")
	else
		check("extreme landscape keyboard space retains the Options fallback", not effort.Visible)
	end
	h.click(h.byName("ModelOptions", picker.card)); h.settle(0.1)
	h.click(h.byName("Option_effort")); h.settle(0.1)
	local high = assert(h.byName("Option_high"))
	check("compact effort choices retain a touch target", high.AbsoluteSize.Y >= 40)
	h.click(high); h.settle(0.1)
	check("compact effort changes the real preference", app.config.get("agent.effort") == "high")
	h.click(h.byName("ModelOptions", picker.card)); h.settle(0.1)
	h.click(h.byName("Option_effort")); h.settle(0.1)
	h.click(h.byName("Option_off")); h.settle(0.1)
	check("provider-default effort remains available", app.config.get("agent.effort") == "off")
	h.click(h.byName("ModelOptions", picker.card)); h.settle(0.1)
	check("custom model entry remains available", h.byName("Option_add") ~= nil)
	h.click(h.byName("Option_add")); h.settle(0.1)
	check("custom model prompt opens above the picker", h.byName("PromptField") ~= nil)
	local surfaces = app.env.require("ui/overlay").open
	surfaces[#surfaces].close(); h.settle(0.2)
	uis.OnScreenKeyboardVisible = false; uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); h.settle(0.3)
	h.click(h.byName("Section_Endpoint", picker.card)); h.settle(0.3)
	local switcher = app.env.require("ui/panels/providerpicker").open(picker)
	for _, name in ipairs({ "ProviderSwitchSearch", "ManageSavedProviders", "Close" }) do
		local node = assert(h.byName(name, switcher.card), name)
		check("provider " .. name .. " has a 40px touch target", node.AbsoluteSize.X >= 40 and node.AbsoluteSize.Y >= 40)
	end
	picker.close(); h.settle(0.3)
	check("touch picker releases callbacks without errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	app.unload()
end

print("Model picker touch: " .. passed .. " checks passed")
