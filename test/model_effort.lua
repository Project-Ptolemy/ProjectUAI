-- Model-modal effort controls use the global setting and real adapter builders.
-- Synthetic UI only; no provider requests or image previews.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Model effort")
local case, check = suite.case, suite.check

local function fixture(width)
	local f = F.ui(width or 900, 700)
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

suite.finish()
