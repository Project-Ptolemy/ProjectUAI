-- Real check receipts, saved goals and concurrent edits must agree before completion.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Script goal workflow")
local check, case = suite.check, suite.case
local function setup()
	local f = F.new(); local w = f.env.require("runtime/script_workflow")
	local session = { id = "goal-owner" }
	assert(w.start(session, "Build a reusable interface", { "The action updates the value", "Destroy stops owned work" }))
	return f, w, session
end
local function advance(w, s, count)
	for _ = 1, count do assert(w.update(s, { action = "advance", note = "Reviewed source and recorded evidence" })) end
end
case("completion requires reviewed criteria and current successful syntax", function()
	local f, w, s = setup(); advance(w, s, 4)
	check("validation rejects an assertion without a receipt", not w.update(s, { action = "advance", note = "I think it works" }))
	w.observe(s, "script_analyze", { ok = true, data = { compilerAvailable = false } }, w.capture(s))
	check("unavailable compiler does not count", not w.update(s, { action = "advance", note = "Unavailable" }))
	w.observe(s, "check_luau", { ok = true }, w.capture(s)); advance(w, s, 1)
	check("review requires every criterion", not w.update(s, { action = "advance", note = "Ready" }))
	for i = 1, 2 do assert(w.update(s, { action = "criterion", criterion = i, done = true, note = "Observed expected behavior" })) end
	advance(w, s, 1)
	check("complete state roundtrips without aliasing", w.restore(s.workflow).status == "complete" and w.snapshot(s.workflow) ~= s.workflow)
	w.observe(s, "script_test", { ok = true, data = { ok = false } }, w.capture(s))
	check("a late failed test reopens validation", s.workflow.status == "active" and s.workflow.stage == 5)
	f.healthy(); f.close()
end)
case("parallel old checks never validate new edits or a replacement goal", function()
	local f, w, s = setup(); advance(w, s, 4)
	local started = w.capture(s)
	w.invalidate(s)
	w.observe(s, "check_luau", { ok = true }, started)
	check("source change returns to build", s.workflow.stage == 4)
	advance(w, s, 1)
	check("old revision cannot advance validation", not w.update(s, { action = "advance", note = "Old syntax" }))
	w.observe(s, "check_luau", { ok = true }, w.capture(s)); advance(w, s, 1)
	w.observe(s, "check_luau", { ok = false }, w.capture(s))
	check("failed final syntax cannot be hidden by earlier success", s.workflow.stage == 5 and not w.update(s, { action = "advance", note = "Ready" }))
	s.workflow = nil; assert(w.start(s, "A different goal", { "A different criterion" }))
	w.observe(s, "check_luau", { ok = true }, started)
	check("old goal receipt is ignored", #s.workflow.receipts == 0)
	f.healthy(); f.close()
end)
case("blockers, malformed saves and source uncertainty are explicit", function()
	local f, w, s = setup()
	assert(w.update(s, { action = "block", note = "Compiler unavailable on this host" }))
	check("blocked goals cannot advance", not w.update(s, { action = "advance", note = "Skip" }))
	assert(w.update(s, { action = "resume" })); advance(w, s, 4)
	w.observe(s, "file_write", { ok = false, error = "timeout" })
	check("uncertain writes invalidate checks", s.workflow.revision == 1 and s.workflow.stage == 4)
	local saved = w.snapshot(s.workflow); saved.stage = 99
	check("invalid persisted stage rejected", not w.restore(saved))
	saved = w.snapshot(s.workflow); saved.status = "complete"
	check("incomplete evidence cannot restore as complete", not w.restore(saved))
	f.healthy(); f.close()
end)
suite.finish()
