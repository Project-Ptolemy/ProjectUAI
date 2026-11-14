-- Direct native/Cowork application and ordinary questions; all resources are synthetic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local envMock, json = require("env"), require("json")
local desktop = require("automatic_bridge_fixture")
local suite = F.suite("UI mod bridge apply")
local case, check = suite.case, suite.check
local SOURCE = "getgenv().__bridgeModExecuted = (getgenv().__bridgeModExecuted or 0) + 1\nreturn function(context)\n context:OnDestroy(function() getgenv().__bridgeModCleaned = true end)\n return function() end\nend"
local function onlyKeys(value, names)
	if type(value) ~= "table" then return false end
	local allowed = {}; for _, name in ipairs(names) do allowed[name] = true end
	for key in pairs(value) do if not allowed[key] then return false end end
	return true
end
local function setup()
	local h = envMock.new()
	local f = { h = h, outgoing = {}, inbox = {}, acks = {}, sequence = 0 }
	h.http.handler = function(req)
		if req.url:find("/api/hello", 1, true) then
			return { StatusCode = 200, Body = json.encode({ protocol = 2, instance = "mod-apply-worker", capabilities = {} }) }
		elseif req.url:find("/api/agent/inbox", 1, true) then
			return { StatusCode = 200, Body = json.encode({ commands = f.inbox }), delay = 0.1 }
		elseif req.url:find("/api/agent/ack", 1, true) then
			for _, result in ipairs(json.decode(req.body).results or {}) do
				f.acks[result.id] = result
				if result.pending ~= true then f.inbox = {} end
			end
		elseif req.url:find("/api/agent/events", 1, true) then
			local value = json.decode(req.body)
			f.outgoing[#f.outgoing + 1] = value
			if value.state then f.latest = value.state end
		end
		return { StatusCode = 204, Body = "" }
	end
	f.app = assert(h.boot()); require("password_fixture")(h, f.app)
	f.env = f.app.env
	f.permissions = f.env.require("agent/permissions"); f.permissions.setMode("full")
	f.registry, f.mods = f.env.require("agent/registry"), f.env.require("runtime/ui_mods")
	f.activation, f.asks = f.env.require("agent/ui_mod_activation"), f.env.require("ui/panels/ask")
	f.commands, f.sessions = f.env.require("net/bridge_commands"), f.env.require("agent/session")
	f.session = f.sessions.current()
	desktop.connect(h, f.app, { instance = "mod-apply-worker" }); h.settle(1.3)
	function f.save(source, id)
		local result
		h.sched.spawn(function() result = { f.mods.save({ version = 1, kind = "script", id = id or "bridge-workspace",
			name = "Bridge workspace", source = source or SOURCE }) } end)
		h.settle(0.3)
		return assert(result and result[1], result and result[2] or "synthetic mod save did not finish")
	end
	function f.begin(name, arguments)
		f.sequence = f.sequence + 1
		local work = { done = false }
		h.sched.spawn(function()
			work.result = f.registry.dispatch({ id = "bridge-direct-" .. f.sequence, name = name,
				arguments = json.encode(arguments) }, f.session.toolContext())
			work.done = true
		end)
		h.settle(0.3)
		return work
	end
	function f.apply(record)
		f.sequence = f.sequence + 1
		local work = { done = false }
		h.sched.spawn(function()
			work.ok, work.result = pcall(f.commands.run, { type = "tool:run", commandId = "browser-mod-" .. f.sequence,
				sessionId = f.session.id, name = "ui_mod_apply", arguments = { id = record.id, expected_revision = record.revision } })
			work.done = true
		end)
		h.settle(0.4)
		return work
	end
	function f.answer(id, text)
		return pcall(f.commands.run, { type = "ask:answer", id = id, text = text, sessionId = f.session.id })
	end
	function f.question(id)
		for _, row in ipairs(f.latest and f.latest.questions or {}) do if row.id == id then return row end end
	end
	function f.event(id, key)
		for _, batch in ipairs(f.outgoing) do
			for _, event in ipairs(batch[key or "events"] or {}) do if event.kind == "ask:user" and event.id == id then return event end end
		end
	end
	function f.close()
		f.app.destroy(); h.settle(0.3)
		check("native mod transport releases callbacks cleanly", #h.errors() == 0)
		check("native mod transport uses legal mock properties", #h.instanceState.typeErrors == 0)
	end
	return f
end

case("Allow everything executes an exact saved mod without dedicated source transport", function()
	local f = setup()
	local prefix, tail = "-- 界\r\n-- literal <script>window.executed=true</script>\r\n-- ", "\r\n" .. SOURCE .. "\r\n-- COMPLETE_SOURCE_TAIL\r\n"
	local source = prefix .. string.rep("x", 262144 - #prefix - #tail) .. tail
	local saved = f.save(source)
	check("saving the full supported source remains inert", #saved.spec.source == 262144 and f.h.sandbox.__bridgeModExecuted == nil)
	local work = f.apply(saved); f.h.settle(1.3)
	check("the real browser tool dispatcher applies directly", work.done and work.ok and work.result.ok and work.result.data.applied
		and f.h.sandbox.__bridgeModExecuted == 1 and f.mods.getActive().id == saved.id)
	check("application creates no dedicated question", f.asks.current == nil and #f.asks.queue == 0 and #(f.latest.questions or {}) == 0)
	check("native source is not automatically sent as a question or review", not json.encode(f.outgoing):find("COMPLETE_SOURCE_TAIL", 1, true)
		and not json.encode(f.outgoing):find("uiModReview", 1, true))
	f.h.sched.spawn(f.activation.disable); f.h.settle(0.4)
	check("normal Disable releases registered script cleanup", f.h.sandbox.__bridgeModCleaned == true and f.mods.getActive() == nil)
	f.close()
end)

case("normal permission prompts use the actual native inbox and command receipts", function()
	local f = setup(); local saved = f.save()
	f.permissions.setMode("ask")
	local work = f.apply(saved); f.h.settle(1.3)
	local id, pending = next(f.permissions.pending)
	check("Ask first waits at the ordinary permission gate", id ~= nil and pending.tool.name == "ui_mod_apply"
		and not work.done and f.h.sandbox.__bridgeModExecuted == nil and f.asks.current == nil)
	local visible
	for _, request in ipairs(f.latest.pendingPermissions or {}) do if request.id == id then visible = request end end
	check("the permission exposes only the concrete application arguments", visible and visible.name == "ui_mod_apply"
		and onlyKeys(visible.args, { "id", "expected_revision" }) and visible.args.expected_revision == saved.revision)
	f.inbox = { { type = "permission", commandId = "ordinary-mod-permission", id = id, sessionId = f.session.id, allow = true, remember = false } }
	f.h.settle(1.5)
	check("an actual browser permission answer starts the source once", work.done and work.ok and work.result.ok
		and work.result.data.applied and f.h.sandbox.__bridgeModExecuted == 1 and next(f.permissions.pending) == nil)
	check("the native bridge acknowledges the permission command", f.acks["ordinary-mod-permission"]
		and f.acks["ordinary-mod-permission"].ok == true and #f.inbox == 0)
	check("normal permission resolution adds no mod review or source history", f.asks.current == nil
		and not json.encode(f.outgoing):find("uiModReview", 1, true))
	f.h.sched.spawn(f.activation.disable); f.h.settle(0.4); f.close()
end)

case("ordinary denial, read scope and stale revisions prevent source execution", function()
	local f = setup(); local saved = f.save()
	f.permissions.setMode("readonly")
	local readOnly = f.apply(saved)
	check("Read only denies the real browser application dispatcher", readOnly.done and readOnly.ok and not readOnly.result.ok)
	f.permissions.setMode("full"); f.permissions.setRule("ui_mod_apply", "deny")
	local denied = f.apply(saved)
	check("an explicit application denial remains effective", denied.done and denied.ok and not denied.result.ok)
	f.permissions.setRule("ui_mod_apply", "default")
	f.session.toolFilter = { ui_mod_list = true, ui_mod_read = true }
	local scoped = f.apply(saved)
	check("a read tool scope cannot acquire application access", scoped.done and scoped.ok and not scoped.result.ok)
	f.session.toolFilter = nil
	local stale = f.apply({ id = saved.id, revision = saved.revision .. ":stale" })
	check("the application rejects stale revisions before startup", stale.done and stale.ok and not stale.result.ok
		and stale.result.text:find("changed", 1, true))
	check("all refused applications remain inert without a dedicated question", f.h.sandbox.__bridgeModExecuted == nil
		and f.mods.getActive() == nil and f.asks.current == nil and #f.asks.queue == 0)
	f.close()
end)

case("retired metadata is stripped from ordinary live questions and reconnect state", function()
	local f = setup(); local answers = {}
	f.session.emit("ask:user", { id = "retained-question", question = "Pick a color", options = { "Yes", "Blue" }, sessionTitle = "Retained fixture",
		uiModReviewRequired = true, uiModReviewRevision = "retired-revision",
		uiModReview = { spec = { source = SOURCE .. "\n-- PRIVATE_SOURCE_SENTINEL" }, history = { "PRIVATE_HISTORY_SENTINEL" },
			state = { secret = "PRIVATE_STATE_SENTINEL" }, resolve = function() end },
		resolve = function(text) answers[#answers + 1] = text end })
	f.h.settle(1.3)
	local request = assert(f.asks.current)
	request.history = { "LOCAL_QUESTION_HISTORY_SENTINEL" }; request.state = { secret = "LOCAL_QUESTION_STATE_SENTINEL" }
	f.h.settle(1.3)
	local row, event = assert(f.question(request.id)), assert(f.event(request.id))
	check("ordinary question rows exclude private/native metadata", onlyKeys(row, { "id", "question", "options", "sessionTitle" })
		and row.question == "Pick a color" and #row.options == 2 and row.resolve == nil and row.uiModReview == nil)
	check("live asks strip every retired mod-review field", event.uiModReview == nil and event.uiModReviewRequired == nil
		and event.uiModReviewRevision == nil and event.resolve == nil and event.question == row.question)
	f.outgoing, f.latest = {}, nil
	local bridge = f.env.require("net/bridge"); bridge.stop(); bridge.sync(); f.h.settle(1.5)
	check("Reconnect resumes desktop discovery before replay", bridge.running and bridge.online)
	-- Live questions restore from current state; they are not durable transcript events.
	local replay = assert(f.question(request.id))
	check("Reconnect restores the same ordinary question state", replay.id == request.id and replay.question == "Pick a color" and #replay.options == 2
		and replay.options[1] == "Yes" and replay.options[2] == "Blue" and replay.sessionTitle == row.sessionTitle
		and onlyKeys(replay, { "id", "question", "options", "sessionTitle" })
		and replay.uiModReview == nil and replay.uiModReviewRequired == nil and replay.uiModReviewRevision == nil and replay.resolve == nil)
	check("transient asks stay outside durable replay and retain their native resolver", f.event(request.id, "snapshot") == nil
		and f.asks.current == request and #answers == 0)
	local encoded = json.encode(f.outgoing)
	check("source histories and local state never reach question transport", not encoded:find("PRIVATE_SOURCE_SENTINEL", 1, true)
		and not encoded:find("PRIVATE_HISTORY_SENTINEL", 1, true) and not encoded:find("PRIVATE_STATE_SENTINEL", 1, true)
		and not encoded:find("LOCAL_QUESTION_HISTORY_SENTINEL", 1, true) and not encoded:find("LOCAL_QUESTION_STATE_SENTINEL", 1, true))
	assert(f.answer(request.id, "Yes")); f.h.settle(1.3)
	check("ordinary Yes needs no privileged revision answer", #answers == 1 and answers[1] == "Yes" and f.question(request.id) == nil)
	check("late ordinary answers cannot revive a settled question", not f.answer(request.id, "Yes") and #answers == 1
		and f.h.sandbox.__bridgeModExecuted == nil)
	f.close()
end)

case("direct application preserves unrelated current and queued questions", function()
	local f = setup(); local saved = f.save()
	local first = f.begin("ask_user", { question = "Pick a color", options = { "Yes", "Blue" } })
	local current = assert(f.asks.current)
	local second = f.begin("ask_user", { question = "Pick another color", options = { "Red", "Green" } })
	local queued = assert(f.asks.queue[1])
	local applied = f.apply(saved)
	check("application does not wait behind unrelated questions", applied.done and applied.ok and applied.result.ok
		and applied.result.data.applied and f.h.sandbox.__bridgeModExecuted == 1)
	check("current and queued ordinary questions remain interactive", f.asks.current == current and f.asks.queue[1] == queued
		and not first.done and not second.done)
	assert(f.answer(queued.id, "Red")); f.h.settle(0.3)
	check("answering a queued question preserves the current question", second.done and second.result.ok
		and second.result.text == "The user answered: Red" and f.asks.current == current and not first.done)
	assert(f.answer(current.id, "Yes")); f.h.settle(0.3)
	check("Allow everything still requires an actual ordinary answer", first.done and first.result.ok
		and first.result.text == "The user answered: Yes" and f.asks.current == nil)
	f.h.sched.spawn(f.activation.disable); f.h.settle(0.4); f.close()
end)

suite.finish()
