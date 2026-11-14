-- External contracts for planning, persistence, guarded tools and native forms.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Micro-goals")
local case, check = suite.case, suite.check
local function start(runtime)
	return assert(runtime.change(nil, { action = "start", objective = "Build the user's requested module", tasks = {
		{ id = "inspect", text = "Inspect the existing contract", criterion = "Record required fields" },
		{ id = "build", text = "Implement and review", criterion = "Reviewed source matches required fields", depends_on = { "inspect" } },
		{ id = "verify", text = "Verify the result", criterion = "Affected checks pass", depends_on = { "build" } },
	} }))
end
local function change(runtime, value, args)
	args.expected_id, args.expected_revision = value.id, value.revision
	return runtime.change(value, args)
end
local function finish(runtime, value)
	for _, taskId in ipairs({ "inspect", "build", "verify" }) do
		value = assert(change(runtime, value, { action = "status", id = taskId, status = "active" }))
		value = assert(change(runtime, value, { action = "status", id = taskId, status = "done", evidence = "Observed the stated result using the relevant checks" }))
	end
	return assert(change(runtime, value, { action = "complete" }))
end
case("dependencies and actual completion evidence govern progression", function()
	local f = F.new(); local runtime = f.env.require("runtime/micro_goals"); local value = start(runtime)
	check("dependent tasks cannot start early", not change(runtime, value, { action = "status", id = "build", status = "active" }))
	check("pending tasks cannot be marked done directly", not change(runtime, value, { action = "status", id = "inspect", status = "done", evidence = "A plan" }))
	value = assert(change(runtime, value, { action = "status", id = "inspect", status = "active" }))
	check("completion without evidence is rejected", not change(runtime, value, { action = "status", id = "inspect", status = "done" }))
	check("blockers require an observed reason", not change(runtime, value, { action = "status", id = "inspect", status = "blocked" }))
	value = assert(change(runtime, value, { action = "status", id = "inspect", status = "blocked", blocker = "Required source unavailable" }))
	check("blocked tasks keep the reason", value.tasks[1].blocker == "Required source unavailable")
	value = assert(change(runtime, value, { action = "status", id = "inspect", status = "active" }))
	value = assert(change(runtime, value, { action = "status", id = "inspect", status = "done", evidence = "Read exact required fields from the current source" }))
	value = assert(change(runtime, value, { action = "status", id = "build", status = "active" }))
	check("the verified prerequisite unlocks its dependent", value.tasks[2].status == "active")
	check("objective completion cannot hide unfinished tasks", not change(runtime, value, { action = "complete" }))
	check("pure planning performs no HTTP or executor work", #f.h.http.log == 0 and next(f.h.files) == nil)
	f.healthy(); f.close()
end)
case("independent tasks share one focus and replacement boards get a fresh identity", function()
	local f = F.new(); local runtime = f.env.require("runtime/micro_goals")
	local value = assert(runtime.change(nil, { action = "start", objective = "Two independent checks", tasks = {
		{ id = "first", text = "Check the first contract", criterion = "Observe the first result" },
		{ id = "second", text = "Check the second contract", criterion = "Observe the second result" },
	} }))
	value = assert(change(runtime, value, { action = "status", id = "first", status = "active" }))
	check("an unrelated task cannot displace the active focus", not change(runtime, value, { action = "status", id = "second", status = "active" })
		and value.tasks[1].status == "active" and value.tasks[2].status == "pending")
	local damaged = runtime.snapshot(value); damaged.tasks[2].status = "active"
	check("persisted competing active tasks are refused", not runtime.restore(damaged))
	value = assert(change(runtime, value, { action = "status", id = "first", status = "done", evidence = "Observed the first result" }))
	value = assert(change(runtime, value, { action = "status", id = "second", status = "active" }))
	value = assert(change(runtime, value, { action = "status", id = "second", status = "done", evidence = "Observed the second result" }))
	value = assert(change(runtime, value, { action = "complete" }))
	local util = f.env.require("runtime/util"); local originalUid, reused = util.uid, false
	util.uid = function(prefix)
		if prefix == "goals" and not reused then reused = true; return value.id end
		return originalUid(prefix)
	end
	local replacement = assert(change(runtime, value, { action = "start", objective = "A new completed-board successor" }))
	util.uid = originalUid
	check("restored ID collisions cannot reuse the replaced board identity", replacement.id ~= value.id and replacement.revision == 1)
	check("stale observers cannot edit the successor at its new revision", not runtime.change(replacement,
		{ action = "pause", expected_id = value.id, expected_revision = replacement.revision }))
	f.healthy(); f.close()
end)
case("definition changes and reopening invalidate dependent evidence", function()
	local f = F.new(); local runtime = f.env.require("runtime/micro_goals")
	local complete = finish(runtime, start(runtime))
	check("all checked tasks permit explicit objective completion", complete.status == "complete" and runtime.counts(complete).done == 3)
	local reopened = assert(change(runtime, complete, { action = "status", id = "inspect", status = "pending" }))
	check("reopening a prerequisite reopens transitive completion", reopened.status == "active" and runtime.counts(reopened).pending == 3)
	for _, task in ipairs(reopened.tasks) do check("invalidated evidence is removed", task.evidence == nil) end
	local edited = assert(change(runtime, complete, { action = "edit", id = "build", criterion = "New required behavior is observed" }))
	check("a changed middle task preserves only unaffected evidence", edited.tasks[1].status == "done"
		and edited.tasks[2].status == "pending" and edited.tasks[3].status == "pending")
	local unchanged = assert(change(runtime, complete, { action = "edit", id = "build", text = complete.tasks[2].text }))
	check("saving an unchanged definition preserves completion", unchanged.status == "complete" and runtime.counts(unchanged).done == 3)
	local revised = assert(change(runtime, complete, { action = "objective", objective = "A materially revised user objective" }))
	check("changing the objective requires fresh task evidence", revised.status == "active" and runtime.counts(revised).pending == 3)
	check("original snapshots stay unchanged", complete.tasks[2].status == "done" and complete.tasks[2].criterion == "Reviewed source matches required fields")
	f.healthy(); f.close()
end)
case("cycles, malformed records, bounds and ambiguous updates are refused", function()
	local f = F.new(); local runtime = f.env.require("runtime/micro_goals"); local value = start(runtime)
	check("cycles are refused without changing the plan", not change(runtime, value, { action = "edit", id = "inspect", depends_on = { "verify" } }) and #value.tasks[1].dependsOn == 0)
	check("duplicate dependencies are refused", not change(runtime, value, { action = "edit", id = "build", depends_on = { "inspect", "inspect" } }))
	check("unknown dependencies are refused", not change(runtime, value, { action = "add", task = { text = "New task", criterion = "Result", depends_on = { "missing" } } }))
	check("unrelated action arguments are refused", not change(runtime, value, { action = "pause", objective = "Ignored text" }))
	check("the order must retain every task exactly once", not change(runtime, value, { action = "reorder", order = { "inspect", "verify", "verify" } }))
	check("a referenced task cannot disappear", not change(runtime, value, { action = "remove", id = "inspect" }))
	local future = runtime.snapshot(value); future.version = 2
	check("unsupported persisted formats are refused", not runtime.restore(future))
	local invalid = runtime.snapshot(value); invalid.tasks[1].status = "done"
	check("forged completion without evidence cannot restore", not runtime.restore(invalid))
	check("invalid UTF-8 is refused", not change(runtime, value, { action = "objective", objective = "bad\255" }))
	check("UTF-8 byte limits are enforced", not change(runtime, value, { action = "edit", id = "inspect", text = ("\231\149\140"):rep(81) }))
	local many = {}; for index = 1, 25 do many[index] = { text = "Task " .. index, criterion = "Result" } end
	check("the task ceiling is enforced before creating a board", not runtime.change(nil, { action = "start", objective = "Too many", tasks = many }))
	local paused = assert(change(runtime, value, { action = "pause" }))
	check("paused boards cannot activate work", not change(runtime, paused, { action = "status", id = "inspect", status = "active" }))
	local resumed = assert(change(runtime, paused, { action = "resume" }))
	local ordered = assert(change(runtime, resumed, { action = "reorder", order = { "verify", "inspect", "build" } }))
	check("reordering keeps identities and dependencies", ordered.tasks[1].id == "verify" and ordered.tasks[1].dependsOn[1] == "build")
	f.healthy(); f.close()
end)
case("session state is detached, scoped and protected against stale edits", function()
	local f = F.new(); local sessions = f.env.require("agent/session")
	local first = assert(sessions.create({ id = "first-goals", ephemeral = true }))
	local second = assert(sessions.create({ id = "second-goals", ephemeral = true }))
	local value = assert(first.updateGoals({ action = "start", objective = "First job", tasks = { { id = "one", text = "First task", criterion = "Observe first result" } } }))
	assert(second.updateGoals({ action = "start", objective = "Second job" }))
	local snapshot = first.goalsSnapshot(); snapshot.tasks[1].text = "Mutated copy"; snapshot.tasks[1].dependsOn[1] = "foreign"
	check("reading cannot mutate another observer's state", first.goalsSnapshot().tasks[1].text == "First task" and #first.goalsSnapshot().tasks[1].dependsOn == 0)
	assert(first.updateGoals({ action = "status", id = "one", status = "active", expected_id = value.id, expected_revision = value.revision }))
	check("stale updates are refused", first.updateGoals({ action = "pause", expected_id = value.id, expected_revision = value.revision }) == nil)
	local latest = first.goalsSnapshot()
	assert(first.updateGoals({ action = "clear", expected_id = latest.id, expected_revision = latest.revision }) == false)
	local replacement = assert(first.updateGoals({ action = "start", objective = "Replacement job" }))
	check("an old ID cannot target a new board at the same revision", first.updateGoals({ action = "pause", expected_id = value.id, expected_revision = replacement.revision }) == nil)
	check("other conversations remain independent", second.goalsSnapshot().objective == "Second job")
	check("micro-goals leave existing tasks and script workflow separate", #first.todos == 0 and first.workflow == nil)
	f.healthy(); f.close()
end)
case("saved boards restore without starting work and damaged boards remain recoverable", function()
	local f = F.new(); local sessions = f.env.require("agent/session")
	local session = assert(sessions.newThread({ id = "durable-goals", title = "A durable plan" }))
	assert(session.updateGoals({ action = "start", objective = "Continue after reload", tasks = { { text = "Read current source", criterion = "Current revision is observed" } } }))
	local saved = assert(f.h.files["UAI/sessions/durable-goals.json"])
	local nextFixture = F.new()
	for path, body in pairs(f.h.files) do nextFixture.h.files[path] = body end
	for path, present in pairs(f.h.folders) do nextFixture.h.folders[path] = present end
	local nextSessions = nextFixture.env.require("agent/session")
	check("a valid plan restores with its conversation", nextSessions.restore() == 1 and nextSessions.get(session.id).goalsSnapshot().objective == "Continue after reload")
	check("restore never starts inference or execution", not nextSessions.get(session.id).busy and #nextFixture.h.http.log == 0)
	local broken = nextFixture.h.json.decode(saved); broken.goals.version = 99
	local badFixture = F.new(); badFixture.h.files["UAI/sessions/durable-goals.json"] = badFixture.h.json.encode(broken)
	badFixture.h.folders["UAI"], badFixture.h.folders["UAI/sessions"] = true, true
	local original = badFixture.h.files["UAI/sessions/durable-goals.json"]
	check("unsupported board data skips rather than erases saved history", badFixture.env.require("agent/session").restore() == 0 and badFixture.h.files["UAI/sessions/durable-goals.json"] == original)
	f.healthy(); nextFixture.healthy(); badFixture.healthy(); f.close(); nextFixture.close(); badFixture.close()
end)
case("tool reads page losslessly and permissions still gate mutations", function()
	local f = F.new(); f.tools({ "goals" }); local session = assert(f.env.require("agent/session").create({ ephemeral = true }))
	local ctx = { env = f.env, session = session, aborted = function() return false end }
	local value = assert(session.updateGoals({ action = "start", objective = ("\231\149\140"):rep(500), tasks = { { id = "task", text = "Read source", criterion = "An exact revision is available" } } }))
	f.env.require("runtime/config").set("agent.resultCap", 600)
	local pieces, offset = {}, 1
	repeat
		local args = { offset = offset, expected_id = value.id, expected_revision = value.revision }
		local result = f.dispatch("micro_goals_read", args, ctx)
		check("read pages fit the output budget and preserve UTF-8", result.ok and not result.truncated and #result.text <= 600 and f.env.require("runtime/util").validUtf8(result.text))
		pieces[#pieces + 1] = assert(result.text:match("^[^\n]*\n(.*)$"))
		offset = result.data.nextOffset
		assert(#pieces < 30, "micro-goal read did not advance")
	until not offset
	check("joined pages preserve complete structured state", f.h.json.decode(table.concat(pieces)).objective == value.objective)
	local update = f.dispatch("micro_goals_update", { action = "pause", expected_id = value.id, expected_revision = value.revision }, ctx)
	check("a guarded update reports the new revision", update.ok and update.data.revision == value.revision + 1)
	check("stale read pages are terminal", not f.dispatch("micro_goals_read", { offset = 2, expected_id = value.id, expected_revision = value.revision }, ctx).ok)
	f.env.require("agent/permissions").setRule("micro_goals_update", "deny")
	local current = session.goalsSnapshot()
	check("a saved deny rule blocks mutation under full mode", not f.dispatch("micro_goals_update", { action = "resume", expected_id = current.id, expected_revision = current.revision }, ctx).ok and session.goalsSnapshot().status == "paused")
	check("read tools remain available independently", f.dispatch("micro_goals_read", {}, ctx).ok)
	f.healthy(); f.close()
end)
case("native forms preserve drafts, expose conflicts and keep stable task rows", function()
	local f = require("coding_fixture").ui(420, 620)
	local session = assert(f.env.require("agent/session").newThread({ ephemeral = true }))
	local sessionReaders, threadReaders = session.events:count(), f.env.require("agent/session").listChanged:count()
	local ui = f.env.require("ui/goals"); local board = assert(ui.open(session)); f.h.settle(0.1)
	local function click(name) f.h.click(assert(f.h.byName(name))); f.h.settle(0.15) end
	local function field(name) return assert(f.h.byName("GoalField_" .. name)):FindFirstChildOfClass("TextBox") end
	click("EditGoalsObjective")
	check("an untouched form does not block client replacement", not ui.hasDrafts())
	field("objective").Text = "Build a reusable module"
	check("an open edited form protects unsaved work", ui.hasDrafts())
	field("objective").Text = ("x"):rep(2001)
	check("oversized form input keeps the previous valid draft", field("objective").Text == "Build a reusable module")
	click("SaveGoalForm")
	check("starting an objective is explicit and usable on a narrow viewport", session.goalsSnapshot().objective == "Build a reusable module")
	check("explicit save releases the unsaved-form guard", not ui.hasDrafts())
	click("AddMicroGoal"); field("text").Text = "Read current source"; field("criterion").Text = "Record the source revision"; click("SaveGoalForm")
	local taskId = session.goalsSnapshot().tasks[1].id
	local row = assert(f.h.byName("MicroGoal_" .. taskId))
	click("EditMicroGoal_" .. taskId); field("text").Text = "Preserve this unfinished edit"; click("CloseGoalEditor")
	board.close(); f.h.settle(0.2)
	check("closing preserves edited forms and the replacement guard", ui.hasDrafts())
	board = assert(ui.open(session)); f.h.settle(0.1)
	click("ResumeGoalForm")
	check("closing and reopening keeps the unfinished form", field("text").Text == "Preserve this unfinished edit")
	local current = session.goalsSnapshot(); assert(session.updateGoals({ action = "pause", expected_id = current.id, expected_revision = current.revision }))
	click("SaveGoalForm")
	check("a stale form keeps its text and reports the conflict", field("text").Text == "Preserve this unfinished edit" and f.h.byName("GoalEditorNotice").Text:find("changed", 1, true))
	click("ReviewGoalCurrent"); click("KeepGoalDraft"); click("SaveGoalForm")
	check("reviewed revision permits an explicit later save", session.goalsSnapshot().tasks[1].text == "Preserve this unfinished edit")
	check("saving a recovered form releases the guard", not ui.hasDrafts())
	local stable = assert(f.h.byName("MicroGoal_" .. taskId)); click("PauseMicroGoals"); click("StartMicroGoal_" .. taskId)
	check("task updates preserve existing rows", f.h.byName("MicroGoal_" .. taskId) == stable and session.goalsSnapshot().tasks[1].status == "active")
	click("FinishMicroGoal_" .. taskId); field("result").Text = "Read revision abc123 from the current saved source"; click("SaveGoalForm")
	check("completion stores evidence", session.goalsSnapshot().tasks[1].status == "done" and session.goalsSnapshot().tasks[1].evidence:find("abc123", 1, true))
	check("view rebuild produced a new board while later updates keep its row", row ~= stable)
	board.close(); f.h.settle(0.2)
	check("closing releases planning subscriptions", session.events:count() == sessionReaders and f.env.require("agent/session").listChanged:count() == threadReaders)
	f.healthy(); f.close()
end)
suite.finish()
