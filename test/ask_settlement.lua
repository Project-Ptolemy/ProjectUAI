-- Request-local settlement survives dispatcher abandonment without game traffic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Ask settlement")
local check, case = suite.check, suite.case
local function has(text, needle) return tostring(text or ""):find(needle, 1, true) ~= nil end

local function fixture(waitSeconds)
	local f = F.new()
	f.tools({ "agentself" })
	f.events, f.abortFlag = {}, false
	if waitSeconds then
		local clock = f.env.require("runtime/clock")
		local wait = clock.wait
		-- Stall the question waiter; the dispatcher uses native task.wait instead.
		clock.wait = function(seconds) return wait(seconds == 0.1 and waitSeconds or seconds) end
	end
	f.ctx = { session = {}, aborted = function() return f.abortFlag end, emit = function(kind, event)
		if kind == "ask:user" then f.events[#f.events + 1] = event end
	end }
	local sequence = 0
	function f.begin()
		sequence = sequence + 1
		local work = { done = false }
		f.h.sched.spawn(function()
			work.result = f.registry.dispatch({ id = "settlement-" .. sequence, name = "ask_user",
				arguments = f.h.json.encode({ question = "Which fixture configuration should be used?" }) }, f.ctx)
			work.done = true
		end)
		f.h.sched.advance(0.02)
		return work, assert(f.events[#f.events], "the real ask tool must emit its question")
	end
	return f
end

case("settlement is one-shot, unsubscribable and safe under synchronous replies", function()
	local f = fixture(); local work, event = f.begin()
	local removed, notified, reason, reentrantRejected = 0, 0, nil, false
	local unsubscribe = event.subscribeSettled(function() removed = removed + 1 end)
	check("a pending observer can unsubscribe exactly once", unsubscribe() and not unsubscribe())
	local release = event.subscribeSettled(function(value)
		notified, reason = notified + 1, value
		reentrantRejected = not event.resolve("Replacement")
	end)
	event.subscribeSettled(function() error("Synthetic observer failure") end)
	event.subscribeSettled(function() notified = notified + 1 end)
	check("the first reply settles every retained observer once", event.resolve("Kept") and not event.resolve("Changed")
		and notified == 2 and removed == 0 and reason == "answered" and reentrantRejected and not release())
	local immediate = 0
	local lateRelease = event.subscribeSettled(function(value) immediate = immediate + 1; reason = value end)
	check("subscriptions after settlement fire immediately", immediate == 1 and reason == "answered" and not lateRelease())
	f.h.sched.advance(0.3)
	check("notification errors leave the original answer intact", work.done and work.result.ok
		and work.result.text == "The user answered: Kept" and notified == 2 and removed == 0)
	f.healthy(); f.close()
end)

case("concurrent questions retain independent settlement and dismissal", function()
	local f = fixture(); local first, firstEvent = f.begin(); local second, secondEvent = f.begin()
	local firstReason, secondReason
	firstEvent.subscribeSettled(function(value) firstReason = value end)
	secondEvent.subscribeSettled(function(value) secondReason = value end)
	check("each question has its own identity", firstEvent.id ~= secondEvent.id and #f.events == 2)
	assert(secondEvent.resolve("")); f.h.sched.advance(0.2)
	check("dismissal settles only its own question", second.done and second.result.ok
		and has(second.result.text, "dismissed") and secondReason == "answered" and firstReason == nil and not first.done)
	assert(firstEvent.resolve("First choice")); f.h.sched.advance(0.2)
	check("the other question can still receive its actual answer", first.done and first.result.ok
		and first.result.text == "The user answered: First choice" and firstReason == "answered"
		and not secondEvent.resolve("Late choice"))
	f.healthy(); f.close()
end)

case("the ten-minute deadline settles observers and rejects later replies", function()
	local f = fixture(); local work, event = f.begin()
	local notified, reason = 0, nil
	local unsubscribe = event.subscribeSettled(function(value) notified, reason = notified + 1, value end)
	f.h.sched.advance(601)
	check("timeout is explicit and settles its observers", work.done and work.result.ok
		and has(work.result.text, "Nobody answered") and has(work.result.text, "No answer or consent was given")
		and notified == 1 and reason == "timeout" and not unsubscribe() and not event.resolve("Late answer"))
	local immediate = 0
	event.subscribeSettled(function(value) immediate = immediate + 1; reason = value end)
	f.h.sched.advance(1)
	check("late observers see the existing timeout without reviving work", immediate == 1 and reason == "timeout"
		and notified == 1 and not has(work.result.text, "The user answered:"))
	f.healthy(); f.close()
end)

case("cancellation and dispatcher expiry notify after the scoped emitter ends", function()
	for _, mode in ipairs({ "cancel", "dispatcher-timeout" }) do
		local f = fixture(0.5)
		if mode == "dispatcher-timeout" then f.registry.get("ask_user").timeout = 0.05 end
		local work, event = f.begin()
		local notified, reason, afterDispatch = 0, nil, false
		event.subscribeSettled(function(value)
			notified, reason, afterDispatch = notified + 1, value, work.done
		end)
		if mode == "cancel" then f.abortFlag = true end
		f.h.sched.advance(0.1)
		check("the dispatcher leaves before the stalled waiter resumes", work.done and not work.result.ok
			and work.result.error == (mode == "cancel" and "aborted" or "timeout") and notified == 0)
		f.h.sched.advance(0.5)
		check("request-local notification survives dispatcher abandonment", notified == 1 and reason == "aborted"
			and afterDispatch and not event.resolve("Late answer"))
		f.healthy(); f.close()
	end
end)

case("replies cannot outrun an abort or elapsed deadline before the waiter resumes", function()
	for _, mode in ipairs({ "cancel", "timeout" }) do
		local f = fixture(mode == "timeout" and 600.2 or 0.5)
		local work, event = f.begin()
		local notified, reason = 0, nil
		event.subscribeSettled(function(value) notified, reason = notified + 1, value end)
		if mode == "cancel" then f.abortFlag = true else f.h.sched.advance(600.08) end
		check("the pending native waiter cannot accept stale consent", not work.done and not event.resolve("Too late")
			and notified == 1 and reason == (mode == "cancel" and "aborted" or "timeout"))
		f.h.sched.advance(mode == "cancel" and 0.6 or 0.3)
		check("the waiter preserves the settled decision", work.done and notified == 1
			and not has(work.result.text, "The user answered:")
			and (mode ~= "timeout" or work.result.ok and has(work.result.text, "Nobody answered")))
		f.healthy(); f.close()
	end
end)

suite.finish()
