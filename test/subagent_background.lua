-- Source-only background admission, collection and cancellation contracts.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Background subagents")
local check, case = suite.check, suite.case

local function setup(limit)
	local f = F.new()
	local config = f.env.require("runtime/config")
	config.set("agent.subagentConcurrency", limit or 2)
	local parent = f.env.require("agent/session").create({ title = "Parent" })
	parent.busy = true
	local started, release = {}, false
	f.loaded["agent/loop"] = { run = function(child, text)
		started[#started + 1] = child
		child.emit("assistant:text", { text = "Working on " .. text })
		while not release and not child.aborted() do f.h.sched.wait(0.05) end
		return "Report for " .. text
	end }
	local agents = f.env.require("agent/subagent")
	return f, agents, parent, started, function() release = true; f.h.sched.advance(0.3) end
end

case("background registration returns before child work and reports require collection", function()
	local f, agents, parent, started, finish = setup()
	local record = assert(agents.start({ task = "first task", parent = parent, callId = "dispatch" }))
	check("accepted record is addressable before worker starts", agents.get(record.id) == record and record.status == "queued"
		and record.background and #started == 0 and agents.backgroundCount == 1 and #agents.pending(parent) == 1)
	local parentSteps = 0
	parentSteps = parentSteps + 1
	f.h.sched.advance(0.1)
	parentSteps = parentSteps + 1
	check("parent work continues while child is live", parentSteps == 2 and record.status == "running"
		and #started == 1 and record.latestText == "Working on first task")
	check("running work cannot be marked collected", not agents.markCollected(record, parent, record.runs))
	finish()
	check("completion releases admission worker but remains pending collection", record.status == "done" and record.ok
		and record.report == "Report for first task" and agents.backgroundCount == 0 and agents.live == 0
		and #agents.pending(parent) == 1)
	local other = f.env.require("agent/session").create({ title = "Other" })
	check("collection validates owner and run", #agents.pending(other) == 0 and not agents.markCollected(record, other, record.runs)
		and not agents.markCollected(record, parent, record.runs + 1))
	check("only collecting the current completed report settles coordination", agents.markCollected(record, parent, record.runs)
		and #agents.pending(parent) == 0)
	f.healthy(); f.close()
end)

case("Stop and a new parent epoch before the first frame cannot revive queued work", function()
	local f, agents, parent, started = setup()
	local stopped = assert(agents.start({ task = "stop queued", parent = parent }))
	check("queued worker accepts Stop synchronously", agents.stop(stopped.id))
	f.h.sched.advance(0.1)
	check("Stop is not reset when its worker starts", #started == 0 and stopped.status == "stopped" and stopped.aborted
		and agents.backgroundCount == 0 and agents.live == 0)
	agents.markCollected(stopped, parent, stopped.runs or 0)
	local stale = assert(agents.start({ task = "old parent turn", parent = parent }))
	local epoch = stale.parentEpoch
	parent.toolEpoch = {}
	f.h.sched.advance(0.1)
	check("a delayed worker keeps its admission epoch", stale.parentEpoch == epoch and #started == 0
		and stale.status == "stopped" and #agents.pending(parent) == 0 and agents.backgroundCount == 0)
	f.healthy(); f.close()
end)

case("follow-ups reserve their existing session before scheduling and reset acknowledgements", function()
	local f, agents, parent, started, finish = setup()
	local record = assert(agents.start({ task = "first", parent = parent }))
	finish()
	local child, oldRun, oldEpoch = record.session, record.runs, record.runEpoch
	assert(agents.markCollected(record, parent, oldRun))
	local resumed = assert(agents.startFollowUp({ id = record.id, task = "next", parent = parent }))
	local duplicate, why = agents.startFollowUp({ id = record.id, task = "duplicate", parent = parent })
	check("follow-up is synchronously reserved with the same context", resumed == record and record.session == child
		and record.status == "queued" and record.report == nil and record.collectedRun == nil and #agents.pending(parent) == 1
		and record.runEpoch ~= oldEpoch)
	check("a second follow-up cannot race the queued worker", duplicate == nil and why:find("still working", 1, true) ~= nil)
	f.h.sched.advance(0.2)
	check("follow-up advances one run and awaits its own report collection", record.status == "done" and record.runs == oldRun + 1
		and record.report == "Report for next" and started[#started] == child and #agents.pending(parent) == 1)
	check("previous run acknowledgement cannot acknowledge follow-up", not agents.markCollected(record, parent, oldRun))
	check("stale preparation tokens cannot acknowledge the new report", not agents.markCollected(record, parent, record.runs, oldEpoch))
	assert(agents.markCollected(record, parent, record.runs))
	f.healthy(); f.close()
end)

case("running, queued and unread work are bounded without losing reports", function()
	local f, agents, parent, started, finish = setup(1)
	local first = assert(agents.start({ task = "one", parent = parent }))
	local second = assert(agents.start({ task = "two", parent = parent }))
	local count = #agents.records
	local denied = agents.start({ task = "too many", parent = parent })
	check("queue admission is bounded before allocating records", denied == nil and #agents.records == count and agents.backgroundCount == 2)
	f.h.sched.advance(0.1)
	check("queued background work respects the shared execution ceiling", #started == 1 and agents.live == 1
		and first.status == "running" and second.status == "queued")
	finish(); f.h.sched.advance(0.3)
	check("queued work gets the released execution slot", first.status == "done" and second.status == "done" and agents.live == 0)
	check("uncollected reports also consume bounded admission", agents.start({ task = "read reports first", parent = parent }) == nil
		and #agents.pending(parent) == 2)
	assert(agents.markCollected(first, parent, first.runs))
	local third = assert(agents.start({ task = "three", parent = parent }))
	f.h.sched.advance(0.2)
	check("collection releases capacity without deleting other reports", third.status == "done" and second.report == "Report for two")
	f.healthy(); f.close()
end)

case("uncollected reports retain ownership after context release and ordinary history churn", function()
	local f, agents, parent, started, finish = setup(12)
	local records = {}
	for index = 1, 8 do records[index] = assert(agents.start({ task = "background " .. index, parent = parent })) end
	local firstEpoch = records[1].runEpoch
	finish()
	check("old unread context can expire without losing its report owner", records[1].session == nil and records[1].parent == parent
		and records[1].runEpoch == firstEpoch and #agents.pending(parent) == 8)
	for index = 1, 30 do
		assert(f.run(function() return agents.dispatch({ task = "blocking " .. index, parent = parent }) end))
	end
	check("ordinary finished history cannot evict unread background reports", #agents.records == 24
		and agents.get(records[1].id) == records[1] and #agents.pending(parent) == 8)
	check("a retained report can still be collected after context expiry", agents.markCollected(records[1], parent, records[1].runs)
		and #agents.pending(parent) == 7)
	f.healthy(); f.close()
end)

case("clearing history and cross-conversation follow-ups preserve unread ownership", function()
	local f, agents, parent, started, finish = setup()
	local record = assert(agents.start({ task = "owned report", parent = parent }))
	finish()
	agents.clearHistory()
	check("clear history retains current unread background reports", agents.get(record.id) == record
		and record.report == "Report for owned report" and #agents.pending(parent) == 1)
	local other = f.env.require("agent/session").create({ title = "Other owner" })
	other.busy = true
	local moved, why = agents.startFollowUp({ id = record.id, task = "transfer", parent = other })
	check("background transfer cannot steal another conversation's unread report", moved == nil
		and why:find("must be collected", 1, true) ~= nil and record.parent == parent
		and record.report == "Report for owned report" and #agents.pending(parent) == 1)
	check("blocking follow-up also preserves unread ownership",
		agents.followUp({ id = record.id, task = "blocking transfer", parent = other }) == nil)
	assert(agents.markCollected(record, parent, record.runs, record.runEpoch))
	assert(agents.startFollowUp({ id = record.id, task = "collected transfer", parent = other }))
	f.h.sched.advance(0.2)
	check("collection allows a later conversation to resume the same context", record.parent == other
		and record.report == "Report for collected transfer" and #agents.pending(parent) == 0 and #agents.pending(other) == 1)
	assert(agents.markCollected(record, other, record.runs, record.runEpoch))
	agents.clearHistory()
	check("collected background history remains clearable", agents.get(record.id) == nil)
	local stale = assert(agents.start({ task = "old turn", parent = parent }))
	f.h.sched.advance(0.2)
	parent.toolEpoch = {}
	check("stale ownership does not block a legitimate transfer",
		agents.startFollowUp({ id = stale.id, task = "new owner", parent = other }) == stale)
	f.h.sched.advance(0.2)
	check("transferred stale work belongs only to the new owner", #agents.pending(parent) == 0 and #agents.pending(other) == 1)
	f.healthy(); f.close()
end)

case("nested starts refuse occupied slots and terminal children stop descendants", function()
	local f, agents, parent = setup(1)
	local nested, reason
	f.loaded["agent/loop"].run = function(child)
		nested, reason = agents.start({ task = "nested", parent = child })
		return "Continued own work"
	end
	local record = assert(agents.start({ task = "outer", parent = parent }))
	f.h.sched.advance(0.2)
	check("one-slot nested delegation cannot deadlock its parent", nested == nil and reason:find("slots are in use", 1, true) ~= nil
		and record.status == "done" and #agents.records == 1)
	f.env.require("runtime/config").set("agent.subagentConcurrency", 2)
	local grandchild, outerChild
	f.loaded["agent/loop"].run = function(child)
		if child.depth == 1 then
			outerChild = child
			grandchild = assert(agents.start({ task = "nested accepted", parent = child }))
			f.h.sched.wait(0.05)
			return "Parent reached its limit"
		end
		while not child.aborted() do f.h.sched.wait(0.05) end
		return "Nested stopped"
	end
	local nextRecord = assert(agents.start({ task = "next outer", parent = parent }))
	f.h.sched.advance(0.3)
	check("terminal child exits stop unfinished descendants", nextRecord.status == "done" and grandchild.status == "stopped"
		and outerChild.aborted() and #agents.pending(outerChild) == 0 and agents.live == 0)
	f.healthy(); f.close()
end)

case("setup failures, depth refusals and unload cannot leak background workers", function()
	local f, agents, parent, started = setup()
	f.env.require("runtime/config").set("agent.subagentDepth", 0)
	check("depth rejection releases its admission", agents.start({ task = "depth", parent = parent }) == nil
		and agents.backgroundCount == 0 and #agents.records == 0)
	f.env.require("runtime/config").set("agent.subagentDepth", 2)
	local clock = f.env.require("runtime/clock")
	local delay = clock.delay
	clock.delay = function() error("fixture schedule failure") end
	check("failed scheduling does not leak capacity", agents.start({ task = "cannot schedule", parent = parent }) == nil
		and agents.backgroundCount == 0 and agents.records[1].status == "failed" and agents.records[1].error ~= nil
		and #agents.pending(parent) == 0)
	clock.delay = delay
	f.loaded["agent/loop"].run = function() error("fixture child failure") end
	local failed = assert(agents.start({ task = "failing child", parent = parent }))
	f.h.sched.advance(0.2)
	check("child failures settle the record and release its worker", failed.status == "failed" and failed.error ~= nil
		and agents.backgroundCount == 0 and agents.live == 0)
	local queued = assert(agents.start({ task = "unload queued", parent = parent }))
	f.close(); f.h.sched.advance(0.2)
	check("unload stops admitted work before it enters the loop", queued.status == "stopped" and #started == 0
		and agents.backgroundCount == 0 and agents.live == 0 and agents.start({ task = "late", parent = parent }) == nil)
	f.healthy()
end)

suite.finish()
