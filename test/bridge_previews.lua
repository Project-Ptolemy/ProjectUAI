-- Real received relay fragments only; no live provider or executor is contacted.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Native bridge previews")
local case, check = suite.case, suite.check

local function fixture(options)
	options = options or {}
	local f = F.new(); f.tools({})
	local endpoint = { target = options.target or "cowork", base = "http://127.0.0.1:28791", token = "fixture-token", instance = "fixture-bridge" }
	f.loaded["net/transport"] = {
		prepare = function() end, unlimited = function() return endpoint.target == "cowork" end,
		endpoint = function() return endpoint end, shouldRelay = function() return true end,
		coworkWeb = function() return endpoint.target == "cowork" end,
		streamForced = function() return endpoint.target == "cowork" end,
	}
	f.providers = f.env.require("provider/registry")
	f.record = f.providers.blank("custom"); f.record.model, f.record.baseUrl = "fixture-model", "https://provider.fixture/v1"
	f.record.label, f.record.apiKey = "Preview fixture", "fixture-provider-key"
	assert(f.providers.save(f.record)); f.providers.setActive(f.record.id)
	f.env.require("runtime/config").set("agent.retries", 1)
	f.env.require("runtime/config").set("agent.maxTokens", 1024)
	f.posts, f.polls, f.deletes, f.paths = 0, 0, 0, {}
	f.finalBody = f.h.json.encode({ model = "fixture-model", choices = { { message = { role = "assistant", content = "Final answer" }, finish_reason = "stop" } } })
	function f.running(page) return { StatusCode = 200, Body = f.h.json.encode({ id = f.id, state = "running", preview = page }) } end
	function f.complete() return { StatusCode = 200, Body = f.h.json.encode({ id = f.id, state = "completed", status = 200, headers = {}, body = f.finalBody }) } end
	f.h.http.handler = function(entry)
		if entry.url:find("/api/hello", 1, true) then
			return { StatusCode = 200, Body = f.h.json.encode({ protocol = 2, instance = endpoint.instance,
				server = endpoint.target == "companion" and "uai-relay" or nil,
				capabilities = options.old and {} or { inferencePreview = { schema = 1 } } }) }
		end
		if entry.method == "DELETE" then f.deletes = f.deletes + 1; return { StatusCode = 200, Body = "{}" } end
		if entry.url:match("/api/inference$") then
			f.posts = f.posts + 1; f.id = f.h.json.decode(entry.body).id; return f.running()
		end
		assert(entry.url:find("/api/inference/", 1, true), "unexpected direct provider call")
		f.polls = f.polls + 1; f.paths[#f.paths + 1] = entry.url
		return f.onPoll()
	end
	function f.start(adapter, callback, request)
		request = request or { messages = { { role = "user", content = "Read fixture" } }, stream = true }
		request.onFrame = callback
		f.h.sched.spawn(function() f.result, f.err = f.env.require("provider/" .. (adapter or "openai")).complete(f.record, request) end)
	end
	function f.done() f.healthy(); f.close() end
	return f
end

local function page(after, cursor, frames, extra)
	local value = { schema = 1, after = after, cursor = cursor, frames = frames or {}, model = "served-fixture" }
	for key, item in pairs(extra or {}) do value[key] = item end
	return value
end
local function frame(seq, text, channel) return { seq = seq, channel = channel or "text", text = text } end

case("agent shows received fragments while pending and commits exactly one final", function()
	local f = fixture(); local finished = false
	f.onPoll = function()
		if finished then return f.complete() end
		return f.running(f.polls == 1 and page(0, 2, { frame(1, "Checking", "reasoning"), frame(2, "Live answer") }) or page(2, 2))
	end
	local session = f.env.require("agent/session").newThread(); local finals, previews = 0, 0
	session.events:connect(function(event)
		if event.kind == "assistant:text" then finals = finals + 1 elseif event.kind == "assistant:preview" then previews = previews + 1 end
	end)
	check("agent accepts the fixture turn", session.send("Read fixture"))
	f.h.sched.advance(1.5)
	check("native preview appears before provider completion", session.busy and session.livePreview and session.livePreview.text == "Live answer"
		and session.livePreview.reasoning == "Checking" and session.livePreview.model == "served-fixture" and finals == 0)
	finished = true; f.h.sched.advance(2)
	check("completed parsing replaces preview once", not session.busy and session.livePreview == nil and finals == 1 and previews > 0)
	check("polling never submits a second inference", f.posts == 1 and f.polls >= 2)
	f.done()
end)

case("lost polls and overlapping pages keep one cursor and never repeat received text", function()
	local f = fixture(); local received = {}
	f.onPoll = function()
		if f.polls == 1 then error("fixture lost poll receipt") end
		if f.polls <= 3 then return f.running(page(0, 1, { frame(1, "A") })) end
		if f.polls == 4 then return f.running(page(1, 2, { frame(2, "B") })) end
		return f.complete()
	end
	f.start(nil, function(value) received[#received + 1] = value.choices[1].delta.content end)
	f.h.sched.advance(7)
	check("received fragments are delivered exactly once", table.concat(received) == "AB" and f.result and f.result.content == "Final answer")
	check("lost poll retries its cursor and advances only after receipt", f.paths[1]:find("after=0", 1, true) and f.paths[2]:find("after=0", 1, true)
		and f.paths[3]:find("after=1", 1, true) and f.paths[5]:find("after=2", 1, true) and f.posts == 1)
	f.done()
end)

case("missing or malformed preview pages freeze an honest prefix without losing the final", function()
	for _, broken in ipairs({ page(1, 8, {}, { gap = true }), page(1, 2, { frame("invalid", "suffix") }), page(1, 2, { frame(2, "suffix") }, { limited = true }) }) do
		local f = fixture(); local session = f.env.require("agent/session").newThread()
		local preview = f.env.require("agent/stream").new(session, "fixture", function() return false end)
		f.onPoll = function()
			if f.polls == 1 then return f.running(page(0, 1, { frame(1, "prefix") })) end
			if f.polls == 2 then return f.running(broken) end
			if f.polls == 3 then return f.running(page(8, 9, { frame(9, "must not splice") })) end
			return f.complete()
		end
		f.start(nil, preview.feed); f.h.sched.advance(3.5)
		check("preview limits are explicit and later suffixes are not spliced", session.livePreview and session.livePreview.limited
			and not session.livePreview.text:find("must not splice", 1, true) and not f.paths[3]:find("after=", 1, true))
		f.h.sched.advance(2)
		check("preview failure does not discard the authoritative result", f.result and f.result.content == "Final answer" and f.posts == 1)
		preview.close(); f.done()
	end
end)

case("old bridges and companion keep the existing completed-body exchange", function()
	for _, options in ipairs({ { old = true }, { target = "companion" } }) do
		local f = fixture(options); local received = 0
		f.onPoll = function()
			if f.polls == 1 then return f.running(page(0, 1, { frame(1, "not supported") })) end
			return f.complete()
		end
		f.start(nil, function() received = received + 1 end); f.h.sched.advance(4)
		check("unsupported transports do not request or replay previews", received == 0 and not f.paths[1]:find("after=", 1, true)
			and f.result and f.result.content == "Final answer" and f.posts == 1)
		f.done()
	end
end)

case("Stop inside a preview cancels the same accepted job and suppresses late output", function()
	local f = fixture(); local stopped, received = false, 0
	f.onPoll = function() return f.running(page(0, 2, { frame(1, "before Stop"), frame(2, "late output") })) end
	f.start(nil, function() received = received + 1; stopped = true end,
		{ messages = { { role = "user", content = "Read fixture" } }, aborted = function() return stopped end })
	f.h.sched.advance(3)
	check("Stop prevents the remaining page and any resubmission", received == 1 and f.result == nil and f.err == "aborted" and f.posts == 1 and f.deletes == 1)
	f.done()
end)

case("every bridge provider adapter forwards live fragments without replaying its completed body", function()
	for _, adapter in ipairs({ "openai", "responses", "anthropic", "gemini" }) do
		local f = fixture(); local received, finished = 0, false
		if adapter == "anthropic" then
			f.record.api = "anthropic"
			f.finalBody = f.h.json.encode({ type = "message", model = "fixture-model", content = { { type = "text", text = "Final answer" } }, stop_reason = "end_turn" })
		elseif adapter == "responses" then
			f.finalBody = f.h.json.encode({ id = "resp_fixture", status = "completed", output = { { type = "message", role = "assistant", content = { { type = "output_text", text = "Final answer" } } } } })
		elseif adapter == "gemini" then
			f.record.api, f.record.model = "gemini", "gemini-2.5-flash"
			f.finalBody = 'data: ' .. f.h.json.encode({ candidates = { { content = { parts = { { text = "Final answer", thoughtSignature = "private-final-signature" } } }, finishReason = "STOP" } } }) .. '\n\n'
		end
		f.onPoll = function() return finished and f.complete() or f.running(page(0, 1, { frame(1, "Live") })) end
		f.start(adapter, function() received = received + 1 end); f.h.sched.advance(1.5)
		check(adapter .. " publishes before completion", received == 1 and f.result == nil)
		finished = true; f.h.sched.advance(2)
		check(adapter .. " final parsing does not replay preview frames", received == 1 and f.result and f.result.content == "Final answer")
		f.done()
	end
end)

case("connected inference survives the native time budget while polling the original job", function()
	local f = fixture(); local finished, received = false, 0
	f.onPoll = function() return finished and f.complete() or f.running(page(0, 1, { frame(1, "Still working") })) end
	f.start(nil, function() received = received + 1 end, { messages = { { role = "user", content = "Read fixture" } }, timeout = 1 })
	f.h.sched.advance(310)
	check("native timeout does not end accepted Cowork inference", not f.result and not f.err and received == 1 and f.posts == 1 and f.deletes == 0)
	finished = true; f.h.sched.advance(2)
	check("the long-lived original job returns its final answer", f.result and f.result.content == "Final answer" and f.posts == 1)
	f.done()
end)

suite.finish()
