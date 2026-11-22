-- Model-modal effort controls use the global setting and real adapter builders.
-- Synthetic UI only; no provider requests or image previews.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Model effort")
local case, check = suite.case, suite.check

local function fixture(width, height)
	local f = F.ui(width or 900, height or 700)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl, record.authStyle = "Effort fixture", "https://effort.fixture/v1", "none"
	record.model, record.models = "vendor/reasoner", { "vendor/reasoner", "vendor/plain", "claude-opus-4-6" }
	assert(registry.save(record)); registry.setActive(record.id)
	f.record, f.registry, f.config = record, registry, f.env.require("runtime/config")
	return f
end
local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing control: " .. name)); f.h.settle(0.1)
end
local function selected(f, level)
	local button = f.h.byName("Effort_" .. level)
	local stroke = button and button:FindFirstChildOfClass("UIStroke")
	return stroke and stroke.Transparency < 0.1
end
local function effort(f, style)
	local record = f.env.require("runtime/util").copy(f.record); record.api = style
	local body = f.env.require("provider/" .. style).buildBody(record, { messages = { { role = "user", content = "Inspect the fixture" } } })
	if style == "openai" then return body.reasoning_effort end
	return body.output_config and body.output_config.effort
end

case("manual reasoning support exposes global controls for either provider protocol", function()
	for _, width in ipairs({ 320, 900 }) do
		local f = fixture(width)
		local modal = f.env.require("ui/panels/modelpicker").open()
		f.h.settle(0.2)
		check("unclaimed models do not advertise effort", f.h.byName("Effort_low") == nil)
		click(f, "ModelOptions"); click(f, "Option_reasoning")
		check("manual support immediately exposes controls", f.h.byName("Section_ReasoningEffort").Visible and f.h.byName("Effort_low") ~= nil)
		check("the scope is explicit", f.h.byName("EffortLabel").Text:find("global", 1, true) ~= nil)
		check("default selection matches Agent settings", selected(f, "low") and f.config.get("agent.effort") == "low")
		click(f, "Effort_high")
		check("the modal writes the global preference", f.config.get("agent.effort") == "high" and selected(f, "high"))
		for _, style in ipairs({ "openai", "anthropic" }) do check(style .. " sends the chosen effort", effort(f, style) == "high") end
		click(f, "Effort_off")
		check("provider default is selectable", f.config.get("agent.effort") == "off" and selected(f, "off"))
		for _, style in ipairs({ "openai", "anthropic" }) do check(style .. " omits effort for provider default", effort(f, style) == nil) end
		check("controls fit the modal width", f.h.byName("EffortPills").AbsoluteSize.X > 0 and modal.card.AbsoluteSize.X <= width)
		check("choosing effort sends no inference", f.h.http.requestCount == 0)
		modal.close(); f.h.settle(0.3); f.healthy(); f.close()
	end
end)

case("short pickers keep enabled reasoning levels visible through model and viewport changes", function()
	for _, width in ipairs({ 320, 900 }) do
		local f = fixture(width, 400)
		for index = 4, 12 do f.record.models[index] = "vendor/fixture-" .. index end
		assert(f.registry.save(f.record))
		local modal = f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.3)
		local search = assert(f.h.byName("ModelFilter")):FindFirstChildOfClass("TextBox")
		local list = assert(f.h.byName("ModelScroll"))
		search.Text = "vendor/"
		local function visibleLevels()
			local section = assert(f.h.byName("Section_ReasoningEffort"))
			local strip = assert(f.h.byName("EffortPills"))
			local high = assert(f.h.byName("Effort_high"))
			check("enabled levels are shown directly", section.Visible and strip.Visible and high.Visible)
			check("the effort strip fits between the catalog and footer", strip.AbsoluteSize.X > 0
				and strip.AbsoluteSize.Y >= high.AbsoluteSize.Y
				and strip.AbsolutePosition.X >= modal.scroll.instance.AbsolutePosition.X
				and strip.AbsolutePosition.X + strip.AbsoluteSize.X <= modal.scroll.instance.AbsolutePosition.X + modal.scroll.instance.AbsoluteSize.X
				and list.AbsolutePosition.Y + list.AbsoluteSize.Y <= strip.AbsolutePosition.Y
				and strip.AbsolutePosition.Y + strip.AbsoluteSize.Y <= modal.footer.AbsolutePosition.Y)
			check("a visible effort choice is inside the strip", high.AbsoluteSize.X > 0 and high.AbsoluteSize.Y > 0
				and high.AbsolutePosition.X >= strip.AbsolutePosition.X
				and high.AbsolutePosition.X + high.AbsoluteSize.X <= strip.AbsolutePosition.X + strip.AbsoluteSize.X
				and high.AbsolutePosition.Y >= strip.AbsolutePosition.Y
				and high.AbsolutePosition.Y + high.AbsoluteSize.Y <= strip.AbsolutePosition.Y + strip.AbsoluteSize.Y)
			check("models retain their own bounded scrolling viewport", list.AbsoluteSize.Y > 0 and list.ScrollingEnabled
				and not modal.scroll.instance.ScrollingEnabled
				and list.AbsolutePosition.Y >= search.AbsolutePosition.Y + search.AbsoluteSize.Y)
		end
		click(f, "ModelOptions"); click(f, "Option_reasoning")
		visibleLevels()
		click(f, "Effort_high")
		check("visible levels update the shared preference", f.config.get("agent.effort") == "high" and selected(f, "high"))
		list.CanvasPosition = f.h.dt.Vector2.new(0, 20)
		for _, height in ipairs({ 700, 400 }) do
			f.h.setViewport(width, height)
			visibleLevels()
			check("resizing preserves search and catalog identity", f.h.byName("ModelFilter"):FindFirstChildOfClass("TextBox") == search
				and search.Text == "vendor/" and f.h.byName("ModelScroll") == list and list.CanvasPosition.Y == 20)
			check("resizing preserves the selected effort", selected(f, "high") and f.config.get("agent.effort") == "high")
		end
		f.registry.setModel(f.record.id, "vendor/plain"); f.h.settle(0.2)
		check("unsupported models remove the level strip", not f.h.byName("Section_ReasoningEffort").Visible and f.h.byName("EffortPills") == nil)
		f.registry.setModel(f.record.id, "claude-opus-4-6"); f.h.settle(0.2)
		visibleLevels()
		check("documented reasoning uses the same saved effort", selected(f, "high") and f.h.byName("Effort_xhigh") == nil)
		f.registry.setModel(f.record.id, "vendor/reasoner"); f.h.settle(0.2)
		visibleLevels()
		click(f, "ModelOptions"); click(f, "Option_reasoning")
		check("disabling manual support removes the controls immediately", not f.h.byName("Section_ReasoningEffort").Visible and f.h.byName("EffortPills") == nil)
		click(f, "ModelOptions"); click(f, "Option_reasoning")
		visibleLevels()
		check("reenabling restores the saved effort without resetting navigation", selected(f, "high")
			and search.Text == "vendor/" and f.h.byName("ModelScroll") == list and list.CanvasPosition.Y == 20)
		check("layout and reasoning changes send no inference", f.h.http.requestCount == 0)
		modal.close(); f.h.settle(0.3); f.healthy(); f.close()
	end
end)

case("model switches and external setting changes retain one global preference", function()
	local f = fixture()
	f.config.set("agent.forceReasoning", { ["vendor/reasoner"] = true })
	local modal = f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.2)
	f.config.set("agent.effort", "xhigh"); f.h.settle(0.1)
	check("external changes update the selection", selected(f, "xhigh"))
	click(f, "Model_claude-opus-4-6")
	check("documented scales remain constrained", f.h.byName("Effort_xhigh") == nil and selected(f, "high"))
	check("clamping never rewrites the global choice", f.config.get("agent.effort") == "xhigh")
	click(f, "Model_vendor/plain")
	check("unclaimed models stay unaffected", f.h.byName("Effort_low") == nil and effort(f, "openai") == nil)
	click(f, "Model_vendor/reasoner")
	check("returning restores the same choice", selected(f, "xhigh") and f.config.get("agent.effort") == "xhigh")
	assert(f.config.saveNow()); f.config.load(); f.h.settle(0.1)
	check("saved effort and reasoning support survive reload", selected(f, "xhigh") and f.env.require("provider/traits").thinkingStyle("vendor/reasoner") ~= nil)
	f.config.set("agent.forceReasoning", {}); f.h.settle(0.1)
	check("removing the override hides unsupported controls immediately", f.h.byName("Effort_low") == nil)
	modal.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("closing the picker releases its settings subscriptions", function()
	local f = fixture()
	local picker = f.env.require("ui/panels/modelpicker")
	local baseline = f.config.changed:count()
	for _ = 1, 3 do
		local modal = picker.open(); f.h.settle(0.1)
		modal.close(); f.h.settle(0.3)
		check("closed picker releases config listeners", f.config.changed:count() == baseline)
	end
	f.config.set("agent.effort", "medium")
	check("closed content cannot be recreated by a settings change", f.h.byName("ModelPicker") == nil)
	f.healthy(); f.close()
end)

case("custom Auto remains an exact model ID without local routing", function()
	local f = F.ui(900, 650)
	local env, h = f.env, f.h
	local config, providers = env.require("runtime/config"), env.require("provider/registry")
	local record = providers.blank("custom")
	record.label, record.baseUrl, record.authStyle = "Routing UI fixture", "https://routing.fixture/v1", "none"
	record.model, record.models = "auto", { "auto", "fixture-model" }
	assert(providers.save(record)); providers.setActive(record.id)
	local panes = env.require("ui/settingspanes")
	assert(panes.render("agent", f.host)); h.settle(0.1)
	check("retired routing controls are absent", h.byName("AutomaticFreeRouting") == nil)
	local picker = env.require("ui/panels/modelpicker").open(); h.settle(0.1)
	local model = assert(h.byName("Model_auto"))
	check("Auto is shown as the provider's exact ID", h.byName("ModelName", model).Text == "auto")
	check("Auto receives no invented free or measured status", not h.textOf(model):find("Free", 1, true)
		and not h.textOf(model):find("probe", 1, true))
	assert(config.saveNow()); config.load(); h.settle(0.1)
	check("configuration reload preserves the exact selection", providers.active().model == "auto"
		and h.byName("ModelName", h.byName("Model_auto")).Text == "auto")
	check("opening and reloading Auto never probes a provider", h.http.requestCount == 0)
	picker.close(); h.settle(0.2); f.healthy(); f.close()
end)

case("historical model notices remain visible after native transcript replay", function()
	local f = F.ui(900, 650)
	local session = f.env.require("agent/session").newThread()
	local view = f.env.require("ui/chat/view").new(f.host)
	view.attach(session); f.h.settle(0.2)
	local text = "Selected model: saved-model."
	session.emit("model:route", { model = "saved-model" }); f.h.settle(0.2)
	check("a legacy model notice names its saved choice", f.h.textOf(view.scroll.instance):find(text, 1, true) ~= nil)
	view.refresh(); f.h.settle(0.3)
	check("routing notice survives replay", f.h.textOf(view.scroll.instance):find(text, 1, true) ~= nil)
	f.healthy(); view.destroy(); f.close()
end)

suite.finish()
