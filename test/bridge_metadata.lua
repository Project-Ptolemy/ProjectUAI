-- Focused bridge metadata checks using real context/traits, without network I/O.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Bridge model and context metadata")
local case, check = suite.case, suite.check

case("documented effort scales clamp global preferences and expose provider default", function()
	local f = F.new(); local metadata = f.env.require("net/bridge_metadata")
	f.env.require("runtime/config").set("agent.effort", "xhigh")
	local record = { id = "claude", baseUrl = "https://api.anthropic.com", model = "claude-opus-4-6" }
	local model = metadata.model(record, record.model)
	check("native documented scale includes explicit provider-default choice", table.concat(model.efforts, ",") == "low,medium,high,max,off")
	check("xhigh does not round up to max", model.effectiveEffort == "high" and model.effortSource == "documented" and model.reasoning)
	f.env.require("runtime/config").set("agent.effort", "off")
	check("off means provider default", metadata.model(record).effectiveEffort == "off")
	model.efforts[1] = "changed"
	check("callers cannot mutate shared model traits", metadata.model(record).efforts[1] == "low")
	local known = metadata.model({ baseUrl = "https://api.openai.com/v1" }, "gpt-6.1-sol")
	check("GPT-6.1 Sol exposes its exact documented scale", known.reasoning == true and known.effortSource == "documented"
		and table.concat(known.efforts, ",") == "low,medium,high,xhigh,max,off")
	f.healthy(); f.close()
end)

case("unknown capabilities stay unknown and manual reasoning is explicitly identified", function()
	local f = F.new(); local metadata = f.env.require("net/bridge_metadata")
	local record = { id = "custom", baseUrl = "https://custom.fixture/v1", model = "unpublished-model" }
	local model = metadata.model(record)
	check("unknown models have no invented context or reply limits", model.contextWindow == nil and model.maxOutputTokens == nil)
	check("unknown model does not claim reasoning or effort controls", model.reasoning == nil and model.efforts == nil and model.effortSource == "none" and model.effectiveEffort == nil)
	f.env.require("runtime/config").set("agent.forceReasoning", { [record.model] = true })
	f.env.require("runtime/config").set("agent.forceContext", { [record.model] = 42000 })
	model = metadata.model(record)
	check("manual declarations are honored without claiming a documented scale", model.reasoning and model.effortSource == "manual" and model.contextWindow == 42000)
	check("manual control matches native choices", table.concat(model.efforts, ",") == "low,medium,high,xhigh,max,off")
	check("reading metadata never sends traffic", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("catalog reasoning capability alone does not invent an effort scale", function()
	local f = F.new(); local info = f.env.require("provider/model_info")
	info.capabilities = function() return { reasoning = true } end
	local model = f.env.require("net/bridge_metadata").model({ baseUrl = "https://catalog.fixture/v1", model = "catalog-only-fixture" })
	check("catalog flag has no undocumented controls", model.reasoning == true and model.efforts == nil and model.effortSource == "none")
	f.healthy(); f.close()
end)

case("context separates model capacity, compaction trigger, and partial prepared estimates", function()
	local f = F.new(); local metadata = f.env.require("net/bridge_metadata")
	local ctx = f.env.require("agent/context").new()
	local record = { id = "zen", baseUrl = "https://opencode.ai/zen/v1", model = "deepseek-v4-flash-free" }
	local session = { id = "context-session", ctx = ctx }
	f.env.require("runtime/config").set("agent.contextTokens", 50000)
	ctx.pushUser("Hello"); ctx.summary = "Earlier summary"
	local initial = metadata.context(session, record)
	check("cold context clearly reports incomplete prompt overhead", initial.partial and initial.estimated and not initial.estimatedPrompt and not initial.calibrated)
	check("known model capacity remains separate from compaction budget", initial.windowTokens == 200000 and initial.compactionTokens == 50000)
	local accounting = ctx.observeRequest({ { role = "system", content = string.rep("s", 400) }, { role = "user", content = "Hello" } }, {}, record)
	local prepared = metadata.context(session, record)
	check("prepared prompt adds system/tool estimate", not prepared.partial and prepared.estimatedPrompt and prepared.systemTokens > 0)
	check("categories sum to displayed usage", prepared.usedTokens == prepared.systemTokens + prepared.messageTokens + prepared.summaryTokens)
	ctx.calibrate(200, accounting)
	local calibrated = metadata.context(session, record)
	check("calibration retains estimate label for future context", calibrated.calibrated and calibrated.estimated and not calibrated.partial)
	check("metadata preserves session and provider identity", calibrated.sessionId == session.id and calibrated.providerId == record.id and calibrated.model == record.model)
	f.healthy(); f.close()
end)

case("live routed model uses its own limits and calibration without changing saved selection", function()
	local f = F.new(); local metadata = f.env.require("net/bridge_metadata")
	local ctx = f.env.require("agent/context").new()
	local record = { id = "custom", baseUrl = "https://gateway.fixture/v1", model = "auto" }
	local routed = { id = record.id, baseUrl = record.baseUrl, model = "DeepSeek-V4-Flash" }
	ctx.pushUser("Hello")
	local request = ctx.observeRequest({ { role = "user", content = "Hello" } }, {}, routed); ctx.calibrate(100, request)
	local session = { id = "routed-session", ctx = ctx, liveRequest = { providerId = record.id, model = routed.model } }
	local live = metadata.context(session, record)
	check("live same-provider route has its matching catalog capacity and calibration", live.model == routed.model and live.windowTokens == 1048576 and live.calibrated)
	check("metadata cannot overwrite the saved auto selection", record.model == "auto")
	session.liveRequest.providerId = "different-provider"
	local stale = metadata.context(session, record)
	check("other provider receipt cannot lend stale identity or capacity", stale.model == "auto" and stale.windowTokens == nil and not stale.calibrated)
	session.liveRequest = nil
	check("completed request returns to selected model", metadata.context(session, record).model == "auto")
	check("no session has no invented context", metadata.context(nil, record) == nil)
	f.healthy(); f.close()
end)

suite.finish()
