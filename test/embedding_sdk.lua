-- Public request/session contracts against the shipping bundle and mock transport.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local h = envMock.new({ context = { ui = false, reuse = true } })
local uai = assert(h.boot())
local sessions, sdk = uai.sessions, uai.sdk
local crypto, sha = uai.env.require("runtime/credential_crypto"), uai.env.require("runtime/credential_sha256")
crypto.derive = function(password, salt)
	return sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
end
local unlocked
h.sched.spawn(function() unlocked = uai.config.enableVault("sdk fixture master password") end)
h.settle(1)
assert(unlocked and uai.config.vaultStatus().ready, "SDK fixture must pass mandatory password setup")
local delay, calls = 0, 0
h.http.handler = function(entry)
	if not entry.url:find("/chat/completions", 1, true) then return nil end
	calls = calls + 1
	if delay > 0 then h.sched.wait(delay) end
	return { StatusCode = 200, Body = h.json.encode({
		id = "sdk-fixture", model = "fixture-model",
		choices = { { index = 0, message = { role = "assistant", content = "Fixture answer" }, finish_reason = "stop" } },
		usage = { prompt_tokens = 10, completion_tokens = 4, total_tokens = 14 },
	}) }
end
local record = uai.providers.blank("custom")
record.label, record.baseUrl, record.apiKey = "SDK fixture", "https://sdk.test/v1", "fixture-key"
record.model, record.models, record.stream = "fixture-model", { "fixture-model" }, false
assert(uai.providers.save(record))
assert(uai.providers.setActive(record.id))
check("SDK identifies supported public capabilities", sdk.version == "1.1.0" and sdk.features.requests and sdk.features.resourceScopes
	and sdk.features.requestSnapshots and sdk.features.scheduledScopes
	and sdk.features.uiFreeBoot == false and sdk.features.passwordGate == true)
local selected = sessions.current()
local session, created = sessions.open("sdk-conversation", { title = "SDK", ephemeral = true })
check("opening a named conversation preserves native selection", created and sessions.current() == selected and session.ephemeral)
local same, again = sessions.open(session.id, { title = "Ignored", ephemeral = false })
check("opening an existing identity preserves its settings", same == session and again == false and session.title == "SDK" and session.ephemeral)
local duplicate, collision = sessions.newThread({ id = session.id })
check("duplicate IDs cannot orphan a session", duplicate == nil and type(collision) == "string" and sessions.get(session.id) == session)
for _, id in ipairs({ "", "../config", "path/name", string.rep("a", 121) }) do
	check("invalid path-like session id rejected: " .. id:sub(1, 16), sessions.open(id) == nil and sessions.newThread({ id = id }) == nil)
end
check("untracked and foreign sessions are rejected", sdk.request(sessions.create(), "hello") == nil and sdk.request({ id = session.id }, "hello") == nil)
-- This process-lifetime cache is loaded lazily by the first inference. Measure
-- request-owned subscriptions after initializing it, so it is not a false leak.
uai.env.require("provider/free_route")
local initialListeners, initialDisposals = session.events:count(), uai.env.require("runtime/dispose").count()
local completions, firstEvent = 0, nil
local request = assert(sdk.request(session, "hello", {
	onEvent = function(event) firstEvent = firstEvent or event.kind end,
	onComplete = function(result) completions = completions + 1; assert(result.ok); result.text = "host-local mutation" end,
}))
local result = assert(request.await(5))
check("request returns final text and a successful terminal result: " .. tostring(result.error or result.text),
	result.ok and result.status == "succeeded" and result.text == "Fixture answer" and result.sessionId == session.id)
check("observation includes the first event and completion releases busy", firstEvent == "user" and completions == 1 and not session.busy)
check("ephemeral constructor prevents conversation persistence", h.files["UAI/sessions/" .. session.id .. ".json"] == nil)
check("completed requests release event and lifetime subscriptions", session.events:count() == initialListeners and uai.env.require("runtime/dispose").count() == initialDisposals)
request.onComplete(function(value) if value ~= result and value.text == result.text then completions = completions + 1 end end)
check("late completion subscription receives retained outcome once", completions == 2 and request.cancel() == false)
request.result.text, result.text = "changed public field", "changed awaited copy"
check("host mutation cannot corrupt the retained outcome", request.snapshot().result.text == "Fixture answer" and request.await(0).text == "Fixture answer")
local rejectedCallbacks = 0
check("empty send returns rejection without calling completion", sdk.request(session, " ", { onComplete = function() rejectedCallbacks = rejectedCallbacks + 1 end }) == nil and rejectedCallbacks == 0)
check("invalid callbacks and unknown options fail before dispatch", sdk.request(session, "x", { onComplete = true }) == nil and sdk.request(session, "x", { typo = true }) == nil)

local held = assert(sessions.open("sdk-held", { ephemeral = true }))
assert(held.restoreQueue({ version = 1, items = { { id = "earlier-follow-up", state = "queued", text = "Earlier instruction", files = {}, images = {} } } }))
check("SDK cannot bind to an earlier held user message", sdk.request(held, "New SDK request") == nil and held.queueSnapshot().count == 1)
local removeBeforeStart = session.events:connect(function(event)
	if event.kind == "message:queued" then session.removeQueued(event.messageId) end
end)
local removedBeforeStart = assert(sdk.request(session, "Remove before dispatch"))
check("a removed admission reports cancellation without waiting for a user event", removedBeforeStart.await(1).status == "cancelled" and not session.busy)
removeBeforeStart()

delay = 1
local slow = assert(sdk.request(session, "slow", { onEvent = function() error("host callback fixture") end }))
local waited, timeout = slow.await(0.05)
check("wait timeout keeps the request running", waited == nil and timeout == "timeout" and slow.status == "running" and session.busy)
local progress = slow.snapshot()
check("running snapshots expose elapsed time without inventing a result", progress.status == "running" and progress.elapsedMs >= 0 and progress.result == nil and progress.finishedAt == nil)
check("busy SDK request cannot steal another turn", sdk.request(session, "conflict") == nil)
local removedListener = false
local detach = assert(slow.onComplete(function() removedListener = true end)); detach()
check("await validates its deadline", slow.await(-1) == nil and slow.await(0 / 0) == nil)
assert(slow.cancel())
local stopped = assert(slow.await(5))
check("cooperative cancellation yields a distinct outcome", stopped.status == "cancelled" and not stopped.ok and not session.busy and not removedListener)
local outside = assert(sdk.request(session, "external stop"))
session.abort()
check("legacy stop is reflected in SDK completion", outside.await(5).status == "cancelled")

delay = 0
local originalRun = uai.env.require("agent/loop").run
uai.env.require("agent/loop").run = function() error("intentional loop failure") end
local crash = assert(sdk.request(session, "crash"))
check("internal loop failure is not mistaken for cancellation", crash.await(5).status == "failed")
uai.env.require("agent/loop").run = originalRun
local previousRecords = uai.env.require("runtime/util").deepCopy(uai.config.get("providers"))
-- Explicit list removal exercises the no-provider admission path.
uai.config.set("providers.list", {})
local unavailable = assert(sdk.request(session, "no provider"))
check("provider failure differs from successful acceptance", unavailable.await(5).status == "failed" and unavailable.result.error ~= nil)
uai.config.set("providers", previousRecords)

-- A completion callback can immediately submit the next request without a stale
-- listener reporting its events as part of the first turn.
local successor, secondResult
local predecessor = assert(sdk.request(session, "first", { onComplete = function()
	successor = assert(sdk.request(session, "next", { onComplete = function(value) secondResult = value end }))
end }))
assert(predecessor.await(5)); h.settle(1)
check("completion callbacks can start a new turn", successor and secondResult and secondResult.ok)

-- Legacy listeners may start another turn during listChanged, before the old
-- send invokes onDone. That request's events and cancellation remain separate.
delay = 0.1
local ownUsers, legacyStarted, legacyReply, cancelledLater = 0, false, nil, nil
local retiring = assert(sdk.request(session, "retiring", { onEvent = function(event)
	if event.kind == "user" then ownUsers = ownUsers + 1 end
end }))
local releaseLegacy = sessions.listChanged:connect(function()
	if not legacyStarted and not session.busy then
		legacyStarted = true
		assert(session.send("legacy successor", function(reply) legacyReply = reply end))
		cancelledLater = retiring.cancel()
	end
end)
check("a retiring request cannot cancel the next legacy turn", retiring.await(5).ok and cancelledLater == false and ownUsers == 1)
h.settle(1); releaseLegacy()
check("the successor legacy turn completes normally", legacyReply == "Fixture answer")

delay = 1
local removedCount = 0
local removed = assert(sdk.request(session, "remove", { onComplete = function() removedCount = removedCount + 1 end }))
sessions.remove(session.id)
check("removing a session settles its request once", removed.result and removed.result.status == "cancelled" and removedCount == 1)
h.settle(2)
check("late removed worker cannot complete twice", removedCount == 1)
local finalSession = assert(sessions.open("sdk-unload", { ephemeral = true }))
local unloadCount = 0
local unloading = assert(sdk.request(finalSession, "unload", { onComplete = function() unloadCount = unloadCount + 1 end }))
uai.unload()
check("unload settles accepted work and prevents new SDK requests", unloading.result.status == "cancelled" and unloadCount == 1 and sdk.request(finalSession, "after") == nil)
h.settle(2)
check("unload result survives late native completion", unloadCount == 1 and not uai.cleanupFailed)
check("unloaded sessions cannot create or send work", sessions.newThread() == nil and sessions.open("after") == nil and not finalSession.send("after"))
check("SDK scenarios have no uncaught asynchronous errors", #h.errors() == 0)
print("Embedding SDK: " .. passed .. " checks passed")
