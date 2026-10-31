-- Focused synthetic timing, ownership and UI checks. No live inference.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Free model routing")
local case, check = suite.case, suite.check
local FAST, OTHER = "DeepSeek-V4-Flash", "DeepSeek-V4-Pro"
local request = { messages = { { role = "user", content = "Private user task" } }, maxTokens = 1024 }

local function fixture(options)
	local f = F.new(); options = options or {}
	f.now = 1767268800000 -- 20:00 UTC+8, when included access opens.
	f.env.require("runtime/clock").ms = function() return f.now + f.h.sched.now * 1000 end
	local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free"); registry.save(record); registry.setActive(record.id)
	f.record, f.registry, f.posts = record, registry, {}
	f.env.require("runtime/config").set("agent.maxTokens", 1024)
	if options.disabled then f.env.require("runtime/config").set("agent.autoFreeRouting", false) end
	f.h.http.handler = function(entry)
		if entry.url:find("/models", 1, true) then
			local rows = {}; for _, id in ipairs(options.models or { "auto", FAST, OTHER }) do rows[#rows + 1] = { id = id } end
			return { StatusCode = 200, Body = f.h.json.encode({ data = rows }) }
		end
		local body = f.h.json.decode(entry.body)
		f.posts[#f.posts + 1] = body
		check("probes exclude private conversation input", not entry.body:find("Private user task", 1, true))
		local delay = (options.delay or {})[body.model] or (body.model == FAST and 0.1 or 0.3)
		f.h.sched.wait(delay)
		local replay = body.messages[#body.messages].role == "tool"
		if options.refuse == body.model or (replay and options.badReplay == body.model) then
			return { StatusCode = 400, Body = '{"error":{"message":"unsupported"}}' }
		end
		local message = { role = "assistant", content = "PONG" }
		if not replay and options.noTools ~= body.model then
			message.content = ""
			message.tool_calls = { { id = "probe-call", type = "function", ["function"] = {
				name = "uai_ping", arguments = options.badArgs == body.model and '{"nonce":"wrong"}' or '{"nonce":"ok"}' } } }
		end
		return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = message, finish_reason = replay and "stop" or "tool_calls" } } }) }
	end
	f.route = f.env.require("provider/free_route")
	function f.warm(seconds) f.route.refresh(record); f.h.sched.advance(seconds or 2) end
	return f
end

case("closed hours skip probes and opening restores measurements", function()
	local f = fixture()
	f.now = 1767225600000 + 8 * 3600000 -- 16:00 UTC+8, between the midday close and the evening opening.
	f.warm()
	local status = f.route.status(f.record)
	check("closed included access retains setup but reports its schedule", status.supported and not status.available
		and status.availability:find("20:00-12:00 UTC+8", 1, true))
	check("closed refresh and selection send no probes", f.route.select(f.record, request) == f.record and f.h.http.requestCount == 0)
	f.now = 1767268800000
	f.warm()
	local selected = f.route.select(f.record, request)
	check("the next open-hours action resumes measurement", selected.model == FAST and f.route.status(f.record).available)
	f.now = 1767326400000 -- 12:00 UTC+8 the next day, when the window closes.
	check("closing hides stale measurements without cancelling accepted ownership", not f.route.status(f.record).ready and f.route.current(selected))
	f.healthy(); f.close()
end)

case("probes accepted near closing never issue an off-hours replay", function()
	local f = fixture({ delay = { [FAST] = 3, [OTHER] = 3, auto = 3 } })
	f.now = 1767326400000 - 1000
	f.warm(8)
	check("closing stops follow-up probe work and publication", #f.posts == 2 and not f.route.status(f.record).ready)
	f.healthy(); f.close()
end)

case("locking blocks new free probes while accepted routed snapshots can finish", function()
	local f = fixture(); f.warm()
	local selected = f.route.select(f.record, request)
	check("the fixture has an accepted routed snapshot", selected ~= f.record and selected.model == FAST)
	local config = f.env.require("runtime/config")
	config.vaultStatus = function() return { enabled = true, locked = true, busy = false } end
	f.record.apiKey = ""
	local count = f.h.http.requestCount
	f.route.refresh(f.record); f.h.sched.advance(0.2)
	check("lock stops new selection and background traffic", not f.route.eligible(f.record)
		and f.route.select(f.record, request) == f.record and f.h.http.requestCount == count)
	check("lock retains the already accepted snapshot's ownership", f.route.current(selected) and selected.apiKey ~= "")
	f.healthy(); f.close()
end)

case("the model picker explains closed free hours without probing", function()
	local f = F.ui(390, 760); local registry = f.env.require("provider/registry")
	-- 16:00 UTC+8: closed, four hours before the evening opening.
	f.now = 1767225600000 + 8 * 3600000
	f.env.require("runtime/clock").ms = function() return f.now + f.h.sched.now * 1000 end
	local record = registry.blank("projectuai-free"); registry.save(record); registry.setActive(record.id)
	local picker = f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.2)
	local text = f.h.textOf()
	check("closed Auto names the wait until opening", text:find("Auto (outside free hours)", 1, true)
		and text:find("Free | opens in ", 1, true))
	check("opening the picker outside free hours dispatches no probes", f.h.http.requestCount == 0)
	picker.close(); f.healthy(); f.close()
end)

case("paused community access is not described as closed hours", function()
	local f = F.ui(390, 760); local registry = f.env.require("provider/registry")
	f.env.require("runtime/clock").ms = function() return 1767268800000 + f.h.sched.now * 1000 end
	local record = registry.blank("projectuai-free"); assert(registry.save(record)); assert(registry.setActive(record.id))
	assert(f.env.require("runtime/provider_keys").setPaused(record, 1, true))
	local picker = f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.2)
	local text = f.h.textOf()
	check("open hours with a paused key explains how to resume", text:find("Auto (unavailable)", 1, true)
		and text:find("Resume an API key", 1, true) and not text:find("Auto (outside free hours)", 1, true))
	check("paused browsing dispatches no probes", f.h.http.requestCount == 0)
	picker.close(); f.healthy(); f.close()
end)

case("cold selection is immediate; fresh verified measurements select the fastest", function()
	local f = fixture()
	check("automatic free routing is enabled by default", f.env.require("runtime/config").get("agent.autoFreeRouting") == true)
	local before = f.env.require("runtime/clock").ms()
	check("cold user request uses existing auto without waiting", f.route.select(f.record, request) == f.record
		and f.env.require("runtime/clock").ms() == before)
	f.h.sched.advance(2)
	local selected = f.route.select(f.record, request)
	check("fastest tool and replay verified model wins", selected ~= f.record and selected.model == FAST)
	check("selection keeps the saved auto and health identity", f.registry.active() == f.record and f.record.model == "auto" and selected.health == f.record.health)
	local count = #f.posts
	f.route.select(f.record, request); f.h.sched.advance(0.2)
	check("fresh measurements do not issue more probes", #f.posts == count)
	check("measurements are visible without credentials", f.route.status(f.record).model == FAST and f.route.status(f.record).ms < 10000)
	f.healthy(); f.close()
end)

case("disabled routing sends no background probes and can be enabled later", function()
	local f = fixture({ disabled = true })
	f.warm()
	check("disabled startup retains the selected provider model", f.route.select(f.record, request) == f.record)
	f.h.sched.advance(1)
	check("disabled startup and picker refresh send no probes", f.h.http.requestCount == 0)
	local status = f.route.status(f.record)
	check("disabled included Auto is distinguishable from unsupported routing", status.enabled == false and status.supported == true and not status.running and not status.ready)
	f.env.require("runtime/config").set("agent.autoFreeRouting", true)
	f.warm()
	check("reenabled routing can measure and select", f.route.select(f.record, request).model == FAST)
	f.healthy(); f.close()
end)

case("disabling cancels measurements without cancelling accepted requests", function()
	local f = fixture({ delay = { [FAST] = 3, [OTHER] = 3, auto = 3 } })
	f.route.refresh(f.record); f.h.sched.advance(0.2)
	f.env.require("runtime/config").set("agent.autoFreeRouting", false)
	f.h.sched.advance(8)
	check("disabled in-flight probes cannot replay or publish", #f.posts == 2 and not f.route.status(f.record).ready)
	f.healthy(); f.close()
	f = fixture(); f.warm()
	local selected = f.route.select(f.record, request)
	f.env.require("runtime/config").set("agent.autoFreeRouting", false)
	check("accepted selection survives the preference change", f.route.current(selected))
	check("future selections including compaction use provider Auto", f.route.select(f.record, request) == f.record and f.route.select(selected, request) == f.record)
	f.env.require("provider/openai").rememberMaxTokens(selected, 512)
	f.route.observe(selected, {}, 200)
	check("accepted request can settle its scoped lesson after disabling", f.record.maxTokensCap and f.record.maxTokensCap.model == FAST and f.record.maxTokensCap.tokens == 512)
	f.registry.remove(f.record.id)
	local stale = f.route.select(selected, request)
	check("disabled routing cannot turn a removed owner into an unguarded draft", stale == selected and not f.route.current(stale))
	f.healthy(); f.close()
end)

case("text, malformed tools, replay refusals and ten-second timeouts cannot win", function()
	for _, options in ipairs({ { noTools = FAST }, { badArgs = FAST }, { badReplay = FAST }, { delay = { [FAST] = 11 } } }) do
		local f = fixture(options); f.warm(15)
		check("unverified fastest candidate is excluded", f.route.select(f.record, request).model ~= FAST)
		if options.delay then
			local calls = 0; for _, body in ipairs(f.posts) do if body.model == FAST then calls = calls + 1 end end
			check("timed-out synthetic request is not retried or replayed", calls == 1)
		end
		f.healthy(); f.close()
	end
end)

case("large contexts, unknown model limits, images and explicit parameters retain auto", function()
	local f = fixture({ models = { FAST, "unpublished-model" }, delay = { ["unpublished-model"] = 0.01 } }); f.warm()
	check("unknown context cannot outrank a documented candidate", f.route.select(f.record, request).model == FAST)
	f.env.require("runtime/config").set("agent.forceContext", { [FAST:lower()] = 2048 })
	check("prepared input and reply must fit candidate context", f.route.select(f.record, { messages = { { role = "user", content = string.rep("x", 9000) } }, maxTokens = 1024 }) == f.record)
	check("referenced images keep current router", f.route.select(f.record, { messages = { { role = "user", content = "see", images = { "fixture-image" } } } }) == f.record)
	check("inline image blocks keep current router", f.route.select(f.record, { messages = { { role = "user", content = { { type = "image_url", image_url = { url = "fixture" } } } } } }) == f.record)
	check("request overrides keep current router", f.route.select(f.record, { messages = request.messages, extra = { model = "specific" } }) == f.record)
	f.healthy(); f.close()
end)

case("manual selections, personal key pools and custom settings never probe", function()
	for _, change in ipairs({ function(r) r.model = FAST end, function(r) r.apiKey = "personal-one\npersonal-two" end,
		function(r) r.params = { temperature = 0.2 } end, function(r) r.query = { route = "private" } end,
		function(r) r.api = "anthropic" end, function(r) r.wsUrl = "wss://gateway.fixture" end }) do
		local f = fixture(); change(f.record)
		check("explicit configuration is preserved", f.route.select(f.record, request) == f.record)
		f.h.sched.advance(1)
		check("explicit configuration sends no probes", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end
end)

case("expired measurements, changed headers, removal and unload invalidate routing", function()
	local f = fixture(); f.warm()
	f.record.headers["X-Route"] = "changed"
	check("header changes invalidate immediately", not f.route.status(f.record).ready)
	f.warm()
	f.h.sched.advance(601)
	check("old latencies expire", not f.route.status(f.record).ready)
	f.warm()
	f.registry.remove(f.record.id)
	check("removed provider cannot retain a route", not f.route.status(f.record).ready)
	f.close()
	check("unload invalidates probes and selection", not f.route.eligible(f.record))
	f.healthy()
end)

case("in-flight measurements are discarded after a connection change", function()
	local f = fixture({ delay = { [FAST] = 3, [OTHER] = 3, auto = 3 } })
	f.route.refresh(f.record); f.h.sched.advance(0.2)
	f.record.apiKey = "personal-replacement"
	f.h.sched.advance(8)
	check("late replies cannot publish against new auth", not f.route.status(f.record).ready and f.route.select(f.record, request) == f.record)
	check("no follow-up probes after auth changed", #f.posts == 2)
	f.healthy(); f.close()
end)

case("scoped adapter lessons persist without changing auto or reusing a failed candidate", function()
	local f = fixture(); f.warm()
	local selected = f.route.select(f.record, request)
	local concurrent = f.route.select(f.record, request)
	f.env.require("provider/openai").rememberMaxTokens(selected, 512)
	check("adapter save cannot replace saved model", f.registry.active() == f.record and f.record.model == "auto" and f.record.maxTokensCap == nil)
	f.route.observe(selected, {}, 200)
	check("settlement merges scoped limit", f.record.maxTokensCap.model == FAST and f.record.maxTokensCap.tokens == 512 and f.record.model == "auto")
	f.route.observe(concurrent, {}, 200)
	check("an unchanged concurrent snapshot cannot erase a learned limit", f.record.maxTokensCap.tokens == 512)
	f.env.require("provider/openai").rememberMaxTokens(concurrent, 1024)
	f.route.observe(concurrent, {}, 200)
	check("a concurrent weaker limit cannot raise the known ceiling", f.record.maxTokensCap.tokens == 512)
	f.route.observe(selected, nil, 200)
	check("failed route is excluded from later selections", f.route.select(f.record, request).model ~= FAST)
	check("observation sends no retry", #f.posts == 6)
	f.healthy(); f.close()
end)

case("cache refresh does not cancel accepted requests; changed credentials do", function()
	local f = fixture(); f.warm()
	local selected = f.route.select(f.record, request)
	f.h.sched.advance(601); f.route.refresh(f.record)
	check("accepted request survives replacement of latency cache", f.route.current(selected))
	f.record.apiKey = "new-personal-credential"
	check("old credential snapshot becomes cancelled", not f.route.current(selected))
	f.env.require("provider/openai").rememberMaxTokens(selected, 512)
	f.route.observe(selected, nil, 1000)
	check("late old-scope lesson cannot edit new provider", f.record.apiKey == "new-personal-credential" and f.record.maxTokensCap == nil and f.record.model == "auto")
	f.healthy(); f.close()
end)

case("the agent prepares its prompt and hooks for the chosen model and sends user input once", function()
	local f = fixture(); f.warm(); f.tools({})
	local actual, hooked = {}, nil
	f.h.http.handler = function(entry)
		local body = f.h.json.decode(entry.body); actual[#actual + 1] = body
		return { StatusCode = 200, Body = f.h.json.encode({ model = body.model,
			choices = { { message = { role = "assistant", content = "Done" }, finish_reason = "stop" } } }) }
	end
	f.env.require("agent/hooks").register("preRequest", function(payload) hooked = payload end)
	local session = f.env.require("agent/session").newThread()
	local receipt, notice
	local unsubscribe = session.events:connect(function(event)
		if event.kind == "request:start" then receipt = event elseif event.kind == "model:route" then notice = event end
	end)
	check("user request is accepted", session.send("Private user task"))
	f.h.sched.advance(1)
	check("one user inference uses the measured model", #actual == 1 and actual[1].model == FAST)
	check("hook and prepared prompt agree with chosen model", hooked and hooked.record.model == FAST
		and f.h.json.encode(actual[1].messages):find("You are running on model " .. FAST, 1, true))
	check("request receipt records actual selection", receipt and receipt.model == FAST)
	check("routing notice identifies the chosen model and exact opt-out path", notice and notice.model == FAST
		and notice.text == "Automatic free routing selected " .. FAST .. ". Turn it off in Settings \226\134\146 Agent \226\134\146 Automatic free routing.")
	local retained = false
	for _, event in ipairs(session.log) do if event.kind == "model:route" and event.text == notice.text then retained = true end end
	check("routing notice is retained for replay", retained)
	check("user request leaves saved selector on auto", f.record.model == "auto")
	unsubscribe()
	f.healthy(); f.close()
end)

case("multi-step routing notices stay concise and disabling preserves the active response", function()
	for _, disable in ipairs({ false, true }) do
		local f = fixture(); f.warm(); f.tools({})
		f.registry.register({ name = "fixture_ping", risk = "read", group = "fixture", description = "Read fixture",
			parameters = { type = "object", properties = {} }, run = function() return "Read" end })
		local actual, notices = {}, 0
		f.h.http.handler = function(entry)
			local body = f.h.json.decode(entry.body); actual[#actual + 1] = body
			if #actual == 1 then
				if disable then f.env.require("runtime/config").set("agent.autoFreeRouting", false) end
				return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "",
					tool_calls = { { id = "real-call", type = "function", ["function"] = { name = "fixture_ping", arguments = "{}" } } } }, finish_reason = "tool_calls" } } }) }
			end
			return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = { role = "assistant", content = "Done" }, finish_reason = "stop" } } }) }
		end
		local session = f.env.require("agent/session").newThread()
		session.events:connect(function(event) if event.kind == "model:route" then notices = notices + 1 end end)
		check("multi-step request accepted", session.send("Inspect fixture"))
		f.h.sched.advance(2)
		check("the accepted response completes and its next step respects preference", not session.busy and #actual == 2
			and actual[1].model == FAST and actual[2].model == (disable and "auto" or FAST))
		check("the chosen model notice is not repeated on each tool step", notices == 1)
		f.healthy(); f.close()
	end
end)

case("relay probes retain their ten-second synthetic deadline and connection scope", function()
	local f = fixture({ models = { FAST }, delay = { [FAST] = 11 } })
	local endpoint = { target = "cowork", base = "http://127.0.0.1:28791", token = "fixture", enabled = true }
	local transport = f.env.require("net/transport")
	transport.endpoint = function() return endpoint end
	transport.coworkWeb = function() return true end
	local relayed = 0
	f.loaded["net/relay"] = { request = function(spec, headers, call)
		relayed = relayed + 1
		return call({ url = spec.url, method = spec.method, headers = headers, body = spec.body,
			aborted = spec.aborted, timeout = spec.timeout, silent = true })
	end }
	f.warm(12)
	check("probe uses the same active relay lane", relayed == 1)
	check("Cowork unlimited user budget cannot admit a slow probe", f.route.status(f.record).model == nil)
	endpoint.token = "reconnected"
	check("changed relay credentials invalidate old measurements", not f.route.status(f.record).ready)
	f.healthy(); f.close()
end)

case("free model choices retain subtle rounded outlines and a distinct focus state", function()
	local f = F.ui(900, 800); local registry = f.env.require("provider/registry")
	local theme, primitives = f.env.require("ui/theme"), f.env.require("ui/primitives")
	local record = registry.blank("zen"); record.apiKey = "fixture"; record.models = { "big-pickle", "cat-jam-free", "paid-model" }; record.model = "paid-model"
	registry.save(record); registry.setActive(record.id)
	local picker = f.env.require("ui/panels/modelpicker").open(); f.h.settle(0.2)
	local free = assert(f.h.byName("Model_big-pickle")); local paid = assert(f.h.byName("Model_paid-model"))
	local border = free:FindFirstChildOfClass("UIStroke")
	check("free choice uses a visible subtle one-pixel outline", border.Thickness == 1 and border.Transparency == 0
		and border.Color == primitives.freeModelOutline(theme.color.surface))
	check("outline follows rounded row", free:FindFirstChildOfClass("UICorner").CornerRadius.Offset > 0)
	check("paid choice has no free outline", paid:FindFirstChildOfClass("UIStroke").Transparency == 1)
	free.SelectionGained:Fire(); f.h.click(free); f.h.settle(0.2)
	check("focused selected free choice uses the focus accent", border.Transparency == 0 and border.Color == theme.color.accent and record.model == "big-pickle")
	free.SelectionLost:Fire(); f.h.settle(0.2)
	check("leaving focus restores its free outline without losing selection", border.Color == primitives.freeModelOutline(theme.color.surface)
		and border.Transparency == 0 and record.model == "big-pickle")
	picker.close()
	f.env.require("ui/panels/providers").editor(record); f.h.click(assert(f.h.byName("ActiveModel"))); f.h.settle(0.2)
	local option = assert(f.h.byName("Option_model:big-pickle"))
	check("provider editor model menu also marks free choices", option:GetAttribute("UAIFreeModel")
		and option:FindFirstChildOfClass("UIStroke").Thickness == 1
		and option:FindFirstChildOfClass("UIStroke").Color == primitives.freeModelOutline(theme.color.surfaceOverlay))
	f.healthy(); f.close()
end)

suite.finish()
