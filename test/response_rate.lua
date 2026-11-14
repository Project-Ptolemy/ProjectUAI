-- Request averages and message replay against synthetic clocks and provider data.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Response token rate")
local case, check = suite.case, suite.check
local function assistant(session)
	for index = #session.log, 1, -1 do if session.log[index].kind == "assistant:text" then return session.log[index] end end
end
local function loopFixture()
	local f = F.new(); f.tools({})
	local config, providers = f.env.require("runtime/config"), f.env.require("provider/registry")
	config.set("agent.fallback", true)
	f.records = {}
	for index, name in ipairs({ "Primary", "Fallback" }) do
		local record = providers.blank("custom")
		record.label, record.model, record.models = name, "rate-model", { "rate-model" }
		record.baseUrl, record.apiKey, record.order = "https://rate.fixture/v1", "fixture-rate-key", index
		assert(providers.save(record)); f.records[index] = record
	end
	providers.setActive(f.records[1].id)
	f.session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	f.chat = { contextOverflow = function() return false end }
	f.loaded["provider/chat"] = f.chat
	return f
end

case("only provider counts and positive finite request durations produce averages", function()
	local f = F.new(); local rate = f.env.require("runtime/response_rate")
	check("OpenAI and Responses usage share the same calculation", rate.rate(rate.outputTokens({ completion_tokens = 60 }), 2000) == 30
		and rate.rate(rate.outputTokens({ output_tokens = 60 }), 2000) == 30)
	check("missing or explicitly unreported counts stay unknown", rate.outputTokens(nil) == nil and rate.outputTokens({}) == nil
		and rate.outputTokens({ completion_tokens = 0, output_tokens_reported = false }) == nil)
	for _, invalid in ipairs({ -1, 0.5, "60", false, math.huge, 0 / 0 }) do
		check("invalid output count is hidden", rate.outputTokens({ completion_tokens = invalid }) == nil and rate.text(invalid, 2000) == nil)
	end
	for _, invalid in ipairs({ 0, -1, "2000", false, math.huge, 0 / 0 }) do check("invalid duration is hidden", rate.text(60, invalid) == nil) end
	check("missing durations and overflow are hidden", rate.text(60, nil) == nil and rate.text(1e12, 1e-300) == nil)
	check("the label states a request average", rate.text(60, 2000) == "30.0 tk/s request avg")
	check("tiny positive rates do not round into an apparent zero", rate.text(1, 100000) == "<0.1 tk/s request avg")
	check("large finite rates have bounded readable labels", rate.text(1e12, 1) == "1e+15 tk/s request avg"
		and #rate.text(1e12, 1e-290) < 32)
	f.healthy(); f.close()
end)

case("normalized Anthropic and Gemini usage preserve whether output was reported", function()
	local f = F.new(); local rate = f.env.require("runtime/response_rate")
	local anthropic = f.env.require("provider/anthropic")
	local decoded = { content = { { type = "text", text = "Done" } }, stop_reason = "end_turn", usage = { input_tokens = 20 } }
	check("input-only Anthropic usage does not invent a zero rate", rate.outputTokens(anthropic.fromMessage(decoded).usage) == nil)
	decoded.usage.output_tokens = 60
	check("reported Anthropic output remains available", rate.outputTokens(anthropic.fromMessage(decoded).usage) == 60)
	decoded.usage.output_tokens = "60"
	check("coerced Anthropic output is not presented as a measured count", rate.outputTokens(anthropic.fromMessage(decoded).usage) == nil)
	local function anthropicStream(output)
		local events = {
			{ type = "message_start", message = { usage = { input_tokens = 20, output_tokens = 0 } } },
			{ type = "content_block_delta", index = 0, delta = { type = "text_delta", text = "Done" } },
			{ type = "message_delta", delta = { stop_reason = "end_turn" }, usage = output and { output_tokens = output } or nil },
			{ type = "message_stop" },
		}
		local body = {}
		for _, event in ipairs(events) do body[#body + 1] = "event: " .. event.type .. "\ndata: " .. f.h.json.encode(event) .. "\n\n" end
		return anthropic.parseStream(table.concat(body)).usage
	end
	check("Anthropic's initial zero is not final output usage", rate.outputTokens(anthropicStream(nil)) == nil)
	check("later Anthropic stream usage supplies the measured output", rate.outputTokens(anthropicStream(60)) == 60)
	local gemini = f.env.require("provider/gemini")
	decoded = { candidates = { { content = { parts = { { text = "Done" } } }, finishReason = "STOP" } }, usageMetadata = { promptTokenCount = 20 } }
	check("input-only Gemini usage does not invent a zero rate", rate.outputTokens(assert(gemini.fromResponse(decoded)).usage) == nil)
	decoded.usageMetadata.candidatesTokenCount, decoded.usageMetadata.thoughtsTokenCount = 40, 20
	check("Gemini includes separately reported reasoning output", rate.outputTokens(assert(gemini.fromResponse(decoded)).usage) == 60)
	decoded.usageMetadata.thoughtsTokenCount = -1
	check("invalid Gemini output categories hide the rate", rate.outputTokens(assert(gemini.fromResponse(decoded)).usage) == nil)
	f.healthy(); f.close()
end)

case("the agent records the successful request's wall time before response hooks", function()
	local f = loopFixture(); local done = {}
	f.session.events:connect(function(event) if event.kind == "request:done" then done[#done + 1] = event end end)
	f.chat.complete = function(record, request)
		if record.id == f.records[1].id then f.h.sched.wait(1); return nil, "Primary unavailable" end
		request.onFrame({ choices = { { delta = { content = "Delivered preview" } } } })
		f.h.sched.wait(2)
		return { content = "Done", reasoning = "", toolCalls = {}, finish = "stop", usage = { prompt_tokens = 20, completion_tokens = 60 } }
	end
	f.env.require("agent/hooks").register("postResponse", function(payload)
		f.h.sched.wait(1); payload.result.usage.completion_tokens = 9999
	end)
	check("the synthetic fallback completes", f.run(function() return f.env.require("agent/loop").run(f.session, "Measure this reply") end, 5) == "Done")
	local event = assert(assistant(f.session))
	check("the counter belongs to the successful provider request", #done == 2 and done[1].error ~= nil
		and done[2].ms == 2000 and event.requestMs == 2000 and event.outputTokens == 60)
	check("conversation recovery receives the same primitives", f.session.ctx.last("assistant").requestMs == 2000
		and f.session.ctx.last("assistant").outputTokens == 60)
	check("preview text and hook latency do not define the token rate", f.env.require("runtime/response_rate").text(event.outputTokens, event.requestMs) == "30.0 tk/s request avg")
	f.healthy(); f.close()
end)

case("estimated fallback usage and zero-time completions do not create a visible rate", function()
	for _, reported in ipairs({ false, true }) do
		local f = loopFixture()
		f.chat.complete = function()
			return { content = "Done", reasoning = "", toolCalls = {}, finish = "stop",
				usage = reported and { prompt_tokens = 20, completion_tokens = 60 } or nil }
		end
		f.run(function() return f.env.require("agent/loop").run(f.session, "Answer now") end)
		local event = assert(assistant(f.session))
		check("a missing or unusable measurement stays hidden", f.env.require("runtime/response_rate").text(event.outputTokens, event.requestMs) == nil)
		if not reported then check("estimated completion counts stay out of the message", event.outputTokens == nil) end
		f.healthy(); f.close()
	end
end)

case("the native counter is a static readout and hides unavailable measurements", function()
	local f = F.ui(320, 568)
	local message = f.env.require("ui/chat/message").agent(f.host, "Reply", 1, "fixture-model")
	local label = assert(f.h.byName("RequestTokenRate", message.root))
	check("an old message has no fabricated counter", label:IsA("TextLabel") and not label.Visible and label.Text == "")
	check("narrow captions keep their units without competing with attribution", label.Parent == message.root
		and label.TextWrapped and tostring(label.AutomaticSize) == "Enum.AutomaticSize.Y" and label.LayoutOrder == 3)
	message.finish("Finished reply", "fixture-model", 50, 2000)
	check("completion paints the measured average in place", f.h.byName("RequestTokenRate", message.root) == label
		and label.Visible and label.Text == "25.0 tk/s request avg")
	message.setRequestMetrics(50, 0)
	check("an invalid replacement clears the previous rate", not label.Visible and label.Text == "")
	f.h.settle(0.2); f.healthy(); f.close()
end)

case("stream adoption and transcript replay retain the measured rate without preview pacing", function()
	local f = F.ui(900, 650)
	local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	local view = f.env.require("ui/chat/view").new(f.host)
	view.attach(session); f.h.settle(0.3)
	session.busy = true
	session.emit("request:start", { streamId = "rate-preview", provider = "Fixture", model = "fixture-model" })
	session.emit("assistant:preview", { streamId = "rate-preview", model = "fixture-model", text = "Preview text", outputTokens = 9999, requestMs = 1 })
	f.h.settle(0.4)
	local retained = assert(view.preview.textHandle)
	local label = assert(f.h.byName("RequestTokenRate", retained.root))
	check("preview counters are ignored", not label.Visible)
	session.emit("assistant:text", { streamId = "rate-preview", model = "fixture-model", text = "Final answer", outputTokens = 120, requestMs = 4000 })
	session.emit("assistant:complete", { streamId = "rate-preview" }); f.h.settle(0.3)
	check("the final event adopts the preview and its existing label", view.agentHandle == retained and f.h.byName("RequestTokenRate", retained.root) == label
		and label.Visible and label.Text == "30.0 tk/s request avg")
	session.busy = false; view.refresh(); f.h.settle(0.4)
	label = assert(f.h.byName("RequestTokenRate", view.agentHandle.root))
	check("replayed and lazily mounted messages retain the same average", label.Visible and label.Text == "30.0 tk/s request avg")
	view.destroy(); f.healthy(); f.close()
end)

case("context persistence and transcript recovery preserve rate metadata and attribution", function()
	local f = F.new(); local context = f.env.require("agent/context")
	local original = context.new()
	original.pushAssistant({ content = "Saved answer", reasoning = "", toolCalls = {}, model = "saved-model", outputTokens = 60, requestMs = 2000 })
	local serialized = f.h.json.decode(f.h.json.encode(original.serialise()))
	local restored = context.new(); assert(restored.restore(serialized))
	check("persisted assistant metadata remains primitive", restored.last("assistant").outputTokens == 60
		and restored.last("assistant").requestMs == 2000 and restored.last("assistant").model == "saved-model")
	local owner = {}; local transcript = f.env.require("agent/transcript").new(owner)
	transcript.restore({}, restored)
	local event = assert(owner.log[1])
	check("legacy recovery keeps the same measured average", event.kind == "assistant:text" and event.outputTokens == 60 and event.requestMs == 2000
		and event.model == "saved-model" and f.env.require("runtime/response_rate").text(event.outputTokens, event.requestMs) == "30.0 tk/s request avg")
	local replayed = f.env.require("agent/transcript").new({})
	replayed.restore(f.h.json.decode(f.h.json.encode(transcript.snapshot())), restored, transcript.metadata())
	check("durable replay retains exactly one measured message", #replayed.snapshot() == 1 and replayed.snapshot()[1].outputTokens == 60)
	f.healthy(); f.close()
end)

suite.finish()
