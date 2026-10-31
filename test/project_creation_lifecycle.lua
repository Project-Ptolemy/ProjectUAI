-- Project drafts survive review; cancelled operations cannot resume file writes.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Project creation lifecycle")
local check, case = suite.check, suite.case
local function button(f, root, caption)
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("TextButton") and (node.Text == caption or f.h.textOf(node) == caption) then return node end
	end
	error("Missing button: " .. caption)
end
local function wizard()
	local f = F.ui(900, 750)
	f.session = assert(f.env.require("agent/session").newThread({ id = "project-owner" }))
	f.patch = f.env.require("runtime/project_patch")
	local stage = f.patch.stage
	f.patch.stage = function(operations, context)
		local plan, why = stage(operations, context); f.plan = plan; return plan, why
	end
	f.loaded["ui/code/compare"] = { open = function(_, after, _, apply, onCancel)
		if f.waitReview then f.h.sched.wait(0.2) end
		local review = { closed = false, apply = apply, source = after }
		function review.close(confirmed)
			if review.closed then return end
			review.closed = true; if confirmed ~= true then onCancel() end
		end
		f.review = review; return review
	end }
	f.navigations = 0
	f.form = assert(f.env.require("ui/code/project").create(function() f.navigations = f.navigations + 1 end))
	function f.submit()
		f.h.click(button(f, f.form.modal.footer, "Review files"))
	end
	return f
end
case("cancelled review frees only the untouched proposal and keeps the form draft", function()
	local f = wizard()
	local field = f.h.find(f.form.modal.content, function(node) return node:IsA("TextBox") end)[1]
	field.Text = "RetainedProject"
	f.submit()
	check("review owns an unapplied proposal", f.form.modal.closed and f.review and f.plan.status == "proposed")
	check("review handoff keeps entered values", f.env.require("runtime/code_store").workspace.forms["new-script-project"].directory == "RetainedProject")
	f.review.close()
	check("cancel releases proposal retention", f.patch.get(f.plan.id, { session = f.session }) == nil)
	check("cancel creates no project files", f.env.require("runtime/fsx").readUser(f.plan.items[1].path) == nil)
	local reopened = assert(f.env.require("ui/code/project").create())
	check("reopening recovers the entered folder", reopened.draft.directory == "RetainedProject")
	reopened.modal.close(); f.healthy(); f.close()
end)
case("successful apply clears the form draft and retains its recovery checkpoint", function()
	local f = wizard(); f.submit()
	local result = assert(f.run(f.review.apply))
	check("project application succeeds once", result.status == "applied" and f.navigations == 1)
	check("successful creation releases form recovery", f.env.require("runtime/code_store").workspace.forms["new-script-project"] == nil)
	f.review.close()
	check("closing does not discard an applied checkpoint", f.patch.get(f.plan.id, { session = f.session }) == f.plan)
	f.healthy(); f.close()
end)
case("closing the form while comparison construction yields cannot publish a stale review", function()
	local f = wizard(); f.waitReview = true
	f.env.require("runtime/clock").delay(0.05, function() f.form.modal.close() end)
	f.submit()
	check("late comparison is closed", f.review and f.review.closed)
	check("late comparison releases its proposal", f.patch.get(f.plan.id, { session = f.session }) == nil)
	check("late comparison retains form values", f.env.require("runtime/code_store").workspace.forms["new-script-project"] ~= nil and f.navigations == 0)
	f.healthy(); f.close()
end)
case("a later conversation lifetime cannot revive a stopped project preview", function()
	local f = wizard(); f.submit(); f.session.abort()
	local result, why = f.run(f.review.apply)
	check("old preview remains cancelled", result == nil and why:find("no longer active", 1, true) ~= nil)
	check("cancelled preview writes no files", f.env.require("runtime/fsx").readUser(f.plan.items[1].path) == nil)
	check("cancelled preview releases untouched plan", f.patch.get(f.plan.id, { session = f.session }) == nil)
	f.review.close(); f.healthy(); f.close()
end)
case("uncertain writes preserve checkpoint and form values", function()
	local f = wizard(); f.submit()
	local fs = f.env.require("runtime/fsx"); local write = fs.write
	fs.write = function(path, source, options)
		local saved, why = write(path, source, options)
		if options and options.scope == "files" then return false, "Write acknowledgment unavailable" end
		return saved, why
	end
	local result, why = f.run(f.review.apply)
	check("uncertain apply is not reported successful", result == nil and why:find("checkpoint", 1, true) ~= nil)
	check("uncertain checkpoint records possible effects", f.plan.status == "partial")
	f.review.close()
	check("closing preserves partial recovery", f.patch.get(f.plan.id, { session = f.session }) == f.plan)
	check("failed creation preserves form recovery", f.env.require("runtime/code_store").workspace.forms["new-script-project"] ~= nil)
	fs.write = write; f.healthy(); f.close()
end)
case("a stopped post-read apply and an unsaved editor binding both prevent writes", function()
	local f = F.new(); local fs = f.env.require("runtime/fsx")
	local session = assert(f.env.require("agent/session").newThread({ id = "yielding-project" }))
	local patch, source = f.env.require("runtime/project_patch"), f.env.require("runtime/project_source")
	assert(fs.write("existing.lua", "return 1", { scope = "files" }))
	local context = session.toolContext()
	local plan = assert(patch.stage({ { path = "existing.lua", expected_hash = source.hash("return 1"), content = "return 2" } }, context))
	local read, reads = fs.read, 0
	fs.read = function(path, options)
		if path == "existing.lua" and options and options.scope == "files" then
			reads = reads + 1; if reads == 2 then f.h.sched.wait(0.2) end
		end
		return read(path, options)
	end
	local result
	f.h.sched.spawn(function() result = patch.apply(plan, context) end)
	f.h.sched.advance(0.05); session.abort(); f.h.sched.advance(0.3)
	check("cancellation after a read prevents the next write", result and not result.ok and plan.status == "proposed" and fs.readUser("existing.lua") == "return 1")
	fs.read = read
	local files, store = f.env.require("runtime/code_files"), f.env.require("runtime/code_store"); store.init()
	local opened = assert(files.open("files/existing.lua"))
	assert(store.update(opened.documentId, "return 3"))
	local guarded, why = patch.apply(plan, session.toolContext(), f.env.require("runtime/project_guard").check)
	check("unsaved Code binding blocks shared project writer", guarded == nil and why:find("Unsaved Code draft", 1, true) ~= nil)
	check("guarded write preserves disk and editor source", fs.readUser("existing.lua") == "return 1" and store.resolve(opened.documentId).source == "return 3")
	f.healthy(); f.close()
end)
case("source invalidations update immediately but coalesce disk persistence", function()
	local f = F.new(); local sessions = f.env.require("agent/session")
	local session = assert(sessions.newThread({ id = "workflow-debounce" }))
	local workflow = f.env.require("runtime/script_workflow")
	assert(workflow.start(session, "Build a tested script", { "All checks pass" }))
	local fs = f.env.require("runtime/fsx"); local writeJson, writes = fs.writeJson, 0
	fs.writeJson = function(path, value)
		if path == "sessions/workflow-debounce.json" then writes = writes + 1 end
		return writeJson(path, value)
	end
	for _ = 1, 4 do assert(workflow.invalidate(session)) end
	check("new source state is immediately visible and dirty", session.workflow.revision == 4 and session.persistenceDirty and writes == 0)
	f.h.sched.advance(0.6)
	check("one checkpoint persists the latest source revision", writes == 1 and f.h.json.decode(f.h.files["UAI/sessions/workflow-debounce.json"]).workflow.revision == 4)
	assert(workflow.invalidate(session))
	assert(workflow.update(session, { action = "block", note = "Native validation is unavailable" }))
	check("explicit goal action saves without waiting", writes == 2)
	f.h.sched.advance(0.6)
	check("explicit save cancels the pending duplicate", writes == 2)
	assert(workflow.invalidate(session))
	f.close()
	check("unload flushes a deferred workflow update", f.h.json.decode(f.h.files["UAI/sessions/workflow-debounce.json"]).workflow.revision == 6)
	f.h.sched.advance(1)
	check("unload cancels the pending duplicate save", writes == 3)
	f.healthy()
end)
case("removal cancels a deferred workflow checkpoint", function()
	local f = F.new(); local sessions = f.env.require("agent/session")
	local session = assert(sessions.newThread({ id = "removed-workflow" }))
	local workflow = f.env.require("runtime/script_workflow")
	assert(workflow.start(session, "Build a tested script", { "All checks pass" }))
	assert(workflow.invalidate(session))
	assert(sessions.remove(session.id)); f.h.sched.advance(0.7)
	check("removed goal cannot recreate conversation history", f.h.files["UAI/sessions/removed-workflow.json"] == nil)
	f.healthy(); f.close()
end)
suite.finish()
