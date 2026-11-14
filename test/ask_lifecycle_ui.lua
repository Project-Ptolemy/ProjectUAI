-- Native question settlement against synthetic source modules.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Ask UI lifecycle")
local check, case = suite.check, suite.case
local function field(f, name, root)
	return assert(f.h.byName(name, root)):FindFirstChildOfClass("TextBox")
end
local function fixture()
	local f = F.ui(900, 700)
	f.sessions = { anyEvent = f.env.require("runtime/signal").new("ask UI fixture") }
	f.loaded["agent/session"] = f.sessions
	f.modals = {}
	local overlay = f.env.require("ui/overlay")
	local nativeModal = overlay.modal
	overlay.modal = function(props)
		if f.failModal then f.failModal = false; return nil end
		local modal = nativeModal(props)
		if modal then f.modals[#f.modals + 1] = modal end
		if f.onModal then f.onModal(modal) end
		return modal
	end
	f.ask = f.env.require("ui/panels/ask").watch()
	function f.send(session, question) f.sessions.anyEvent:fire(session, question.event) end
	return f
end
local function question(id, options)
	options = options or {}
	local q = { resolveCalls = 0, subscriptions = 0, releases = 0, observers = {} }
	function q.settle(reason)
		if q.settled then return false end
		q.settled, q.reason = true, reason
		local observers = q.observers; q.observers = {}
		for _, entry in ipairs(observers) do
			local fn = entry.fn; entry.fn = nil
			if fn then fn(reason) end
		end
		return true
	end
	q.event = { kind = "ask:user", id = id, question = options.question or ("Choose a configuration for " .. id),
		options = options.choices }
	q.event.subscribeSettled = function(fn)
		q.subscriptions = q.subscriptions + 1
		local entry, released = { fn = fn }, false
		if q.settled then fn(q.reason) else q.observers[#q.observers + 1] = entry end
		return function()
			if released then return false end
			released = true; q.releases = q.releases + 1; entry.fn = nil
			for index, candidate in ipairs(q.observers) do if candidate == entry then table.remove(q.observers, index); break end end
			return true
		end
	end
	q.event.resolve = function(text)
		q.resolveCalls = q.resolveCalls + 1
		if q.onResolve then q.onResolve(text) end
		if q.settled then return false end
		q.answer = text
		return q.settle("answered")
	end
	return q
end

case("ordinary questions settle after the real dispatcher emitter expires", function()
	local f = fixture(); f.tools({ "agentself" })
	local session = { id = "question-session", title = "Configuration workspace" }
	local clock = f.env.require("runtime/clock"); local wait = clock.wait
	clock.wait = function(seconds) return wait(seconds == 0.1 and 0.5 or seconds) end
	f.registry.get("ask_user").timeout = 0.05
	local emitted, work = 0, { done = false }
	local ctx = { session = session, aborted = function() return false end, emit = function(kind, event)
		if kind == "ask:user" then emitted = emitted + 1; event.kind = kind; f.sessions.anyEvent:fire(session, event) end
	end }
	f.h.sched.spawn(function()
		work.result = f.registry.dispatch({ id = "expired-question", name = "ask_user", arguments = f.h.json.encode({
			question = "Which configuration should be used?" }) }, ctx)
		work.done = true
	end)
	f.h.settle(0.2)
	local oldModal = assert(f.modals[1])
	check("dispatcher expiry leaves the producer's still-pending question visible", work.done and not work.result.ok
		and f.ask.current and not oldModal.closed and field(f, "AskField", oldModal.card) ~= nil)
	local expiredId = f.ask.current.id
	local unrelated = question("independent-work")
	f.send({ id = "another-session", title = "Independent work" }, unrelated)
	f.h.settle(0.7)
	check("request-local settlement closes the stale question without another emitted event", oldModal.closed
		and emitted == 1 and f.ask.current and f.ask.current.id == unrelated.event.id and #f.ask.queue == 0)
	check("the expired question cannot accept a late answer", not f.ask.answer(expiredId, "Late configuration") and f.h.http.requestCount == 0)
	check("unrelated questions remain answerable", f.ask.answer(unrelated.event.id, "Keep working") and unrelated.answer == "Keep working")
	f.h.settle(0.3); f.healthy(); f.close()
end)

case("settled queued questions are removed while unrelated questions keep their order", function()
	local f = fixture()
	local first, expired, last = question("first"), question("expired"), question("last")
	for _, q in ipairs({ first, expired, last }) do f.send({ title = q.event.id }, q) end
	check("only the first pending question is presented", #f.modals == 1 and #f.ask.queue == 2)
	expired.settle("timeout")
	check("external queued settlement releases its subscription without answering it", #f.ask.queue == 1
		and f.ask.queue[1].id == last.event.id and expired.resolveCalls == 0 and expired.releases == 1)
	assert(f.ask.answer(first.event.id, "First choice"))
	check("the expired question is skipped without stranding the next one", #f.modals == 2 and f.ask.current.id == last.event.id
		and #f.ask.queue == 0 and first.resolveCalls == 1 and first.releases == 1)
	assert(f.ask.answer(last.event.id, "Last choice")); f.h.settle(0.3); f.healthy(); f.close()
end)

case("immediate settlement before unsubscribe assignment cannot present or retain a request", function()
	local f = fixture()
	local active, expired = question("active"), question("already-settled")
	expired.settle("aborted")
	f.send({}, expired)
	check("an already-settled event leaves no presentation or subscription", #f.modals == 0 and f.ask.current == nil
		and not f.ask.showing and #f.ask.queue == 0 and expired.subscriptions == 1 and expired.releases == 1)
	f.send({}, active); f.send({}, expired)
	check("late settled events cannot disturb a live question", #f.modals == 1 and f.ask.current.id == active.event.id
		and #f.ask.queue == 0 and expired.releases == 2 and expired.resolveCalls == 0)
	assert(f.ask.answer(active.event.id, "Continue")); f.h.settle(0.3); f.healthy(); f.close()
end)

case("synchronous resolution detaches the old request before reentrant events and closes only its modal", function()
	local f = fixture()
	local first, second, third = question("first"), question("second"), question("third")
	f.send({}, first); f.send({}, second)
	local oldRequest, oldModal = f.ask.current, assert(f.modals[1])
	local lateReply = oldRequest.answer
	local detached, deferred = false, false
	first.onResolve = function()
		detached = f.ask.current == nil and not f.ask.showing and oldRequest.presentation == nil
			and oldRequest.unsubscribeSettled == nil and #first.observers == 0
		f.send({}, third)
		deferred = f.ask.current == nil and #f.ask.queue == 2 and not oldModal.closed
	end
	assert(f.ask.answer(first.event.id, "First choice"))
	check("resolution sees the detached state and defers reentrant presentation", detached and deferred and first.resolveCalls == 1)
	check("old-modal closure cannot clear the next presentation", oldModal.closed and #f.modals == 2
		and not f.modals[2].closed and f.ask.current.id == second.event.id and #f.ask.queue == 1)
	lateReply("Replacement")
	check("retained old callbacks cannot answer or close the next question", first.resolveCalls == 1 and first.answer == "First choice"
		and f.ask.current.id == second.event.id and not f.modals[2].closed)
	assert(f.ask.answer(second.event.id, "Second choice")); assert(f.ask.answer(third.event.id, "Third choice"))
	f.h.settle(0.3); f.healthy(); f.close()
end)

case("scoped sweeps remove all targeted questions before draining unrelated sessions", function()
	local f = fixture(); local targeted, other, lastSession = {}, {}, {}
	local active, queued, otherQuestion, more, last = question("target-active"), question("target-queued"),
		question("other"), question("target-more"), question("last")
	f.send(targeted, active); f.send(targeted, queued); f.send(other, otherQuestion); f.send(targeted, more); f.send(lastSession, last)
	check("a scoped sweep reports all removed questions", f.ask.sweep(targeted) == 3)
	for _, q in ipairs({ active, queued, more }) do
		check("sweep dismisses and unsubscribes each targeted request once", q.resolveCalls == 1 and q.answer == "" and q.releases == 1)
	end
	check("targeted queued questions never flash during the sweep", #f.modals == 2 and f.modals[1].closed
		and f.ask.current.id == otherQuestion.event.id and #f.ask.queue == 1 and f.ask.queue[1].id == last.event.id)
	check("another scoped sweep preserves the remaining session", f.ask.sweep(other) == 1 and f.ask.current.id == last.event.id
		and not last.settled and #f.ask.queue == 0)
	assert(f.ask.answer(last.event.id, "Continue")); f.h.settle(0.3); f.healthy(); f.close()
end)

case("queued answers, native typed replies and dismissals settle exactly once", function()
	local f = fixture()
	local typed, queued = question("typed"), question("queued")
	f.send({}, typed); f.send({}, queued)
	check("answering a queued question leaves the visible one intact", f.ask.answer(queued.event.id, "Queued choice")
		and queued.resolveCalls == 1 and queued.answer == "Queued choice" and queued.releases == 1
		and f.ask.current.id == typed.event.id and #f.ask.queue == 0)
	local modal = assert(f.modals[1]); field(f, "AskField", modal.card).Text = "  Native typed answer  "
	f.h.click(assert(f.h.byName("AskSend", modal.card)))
	check("native Send settles the original trimmed answer once", typed.answer == "Native typed answer"
		and typed.resolveCalls == 1 and typed.releases == 1 and modal.closed and f.ask.current == nil)
	local dismissed = question("dismissed"); f.send({}, dismissed)
	local dismissing = assert(f.modals[#f.modals]); dismissing.close(); dismissing.close()
	check("native close preserves one empty dismissal", dismissed.resolveCalls == 1 and dismissed.answer == ""
		and dismissed.releases == 1 and not f.ask.showing and #f.ask.queue == 0)
	f.h.settle(0.3); f.healthy(); f.close()
end)

case("settlement during modal construction and presentation failures cannot strand the queue", function()
	local f = fixture()
	local closing, nextQuestion = question("closing-during-build"), question("next")
	f.onModal = function()
		f.onModal = nil
		f.send({}, nextQuestion); closing.settle("aborted")
	end
	f.send({}, closing)
	check("a settled construction closes its old modal and presents the retained question", #f.modals == 2 and f.modals[1].closed
		and not f.modals[2].closed and f.ask.current.id == nextQuestion.event.id and closing.resolveCalls == 0)
	assert(f.ask.answer(nextQuestion.event.id, "Next choice"))
	local unavailable, recoverable = question("unavailable"), question("recoverable")
	f.failModal = true
	unavailable.onResolve = function() f.send({}, recoverable) end
	f.send({}, unavailable)
	check("unavailable presentation dismisses and proceeds to a reentrant question", unavailable.resolveCalls == 1 and unavailable.answer == ""
		and unavailable.releases == 1 and f.ask.current.id == recoverable.event.id and #f.ask.queue == 0)
	assert(f.ask.answer(recoverable.event.id, "Recovered")); f.h.settle(0.3); f.healthy(); f.close()
end)

case("unload releases active and queued settlement subscriptions and the event watcher", function()
	local f = fixture(); f.ask.watch()
	local first, nextQuestion = question("unload-first"), question("unload-next")
	f.send({}, first); f.send({}, nextQuestion)
	check("repeated mounting retains one event watcher", f.sessions.anyEvent:count() == 1)
	f.close(); f.h.settle(0.3)
	check("unload removes every presentation and watcher", f.sessions.anyEvent:count() == 0 and f.ask.watching == nil
		and f.ask.current == nil and not f.ask.showing and #f.ask.queue == 0 and f.modals[1].closed)
	check("unload dismisses and unsubscribes each request once", first.answer == "" and nextQuestion.answer == ""
		and first.resolveCalls == 1 and nextQuestion.resolveCalls == 1 and first.releases == 1 and nextQuestion.releases == 1)
	f.send({}, question("after-unload"))
	check("unloaded event delivery cannot recreate a question", f.ask.current == nil and #f.modals == 1)
	f.healthy()
end)

case("retired mod review data cannot block an ordinary user question", function()
	local f = fixture(); local q = question("ordinary-choice", { choices = { "Yes", "Blue" } })
	q.event.uiModReview = { revision = "retired", spec = { kind = "script", source = "getgenv().__retiredReviewExecuted = true" } }
	f.send({}, q)
	local modal = assert(f.modals[1])
	check("the native question contains only its ordinary controls", f.ask.current.uiModReview == nil
		and f.h.byName("UiModPreviewSource", modal.card) == nil and f.h.byName("AskOption1", modal.card).Active)
	f.h.click(assert(f.h.byName("AskOption1", modal.card)))
	check("ordinary affirmative answers are immediately usable", q.resolveCalls == 1 and q.answer == "Yes"
		and modal.closed and f.ask.current == nil and f.h.sandbox.__retiredReviewExecuted == nil)
	f.h.settle(0.3); f.healthy(); f.close()
end)

suite.finish()
