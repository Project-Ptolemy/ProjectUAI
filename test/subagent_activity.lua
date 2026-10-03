-- Focused source-module coverage for the live subagent monitor and retention.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Subagent activity")
local check, case = suite.check, suite.case
local function settle(h, seconds)
	for _ = 1, math.ceil(seconds * 60) do h.frame(1 / 60) end
end

local function setup()
	local f = F.ui(900, 650)
	local h, env = f.h, f.env
	local release = false
	f.loaded["agent/loop"] = { run = function(child)
		while not release and not child.aborted() do h.sched.wait(0.05) end
		return "Finished fixture report"
	end }
	local agents = env.require("agent/subagent")
	h.sched.spawn(function() agents.dispatch({ task = "Inspect fixture", preset = "read" }) end)
	settle(h, 0.1)
	local record = assert(agents.records[1])
	local panel = env.require("ui/panels/agents").new(f.host)
	h.click(assert(f.host:FindFirstChild("Open", true)))
	local overlay = env.require("ui/overlay")
	local modal = assert(overlay.open[#overlay.open])
	local function find(name, root) return assert((root or modal.card):FindFirstChild(name, true), name) end
	return f, agents, record, panel, modal, find, function() release = true; settle(h, 0.2) end
end

case("open details show delivered output and parallel call progress without rebuilding", function()
	local f, agents, record, panel, modal, find, finish = setup()
	local h, child = f.h, record.session
	child.emit("request:start", { provider = "Fixture provider", model = "fixture-model" })
	settle(h, 0.2)
	check("waiting state explains buffered delivery", find("Delivery").Text:find("response completes", 1, true) ~= nil)
	check("waiting does not invent a message", find("LatestMessage").Text == "No message delivered yet.")
	child.emit("assistant:preview", { text = "I am inspecting the fixture", reasoning = "Checking its shape" })
	settle(h, 0.2)
	check("genuine preview arrives while the child is running", record.status == "running"
		and find("LatestMessage").Text == "I am inspecting the fixture" and find("LatestReasoning").Text == "Checking its shape")
	child.emit("request:done", {})
	child.emit("assistant:reasoning", { text = "Verified its shape" })
	child.emit("assistant:text", { text = "I found two files." })
	child.emit("assistant:complete", {})
	child.emit("tool:call", { id = "first", name = "file_read" })
	child.emit("tool:call", { id = "second", name = "file_search" })
	child.emit("tool:progress", { id = "first", text = "Reading the first file" })
	child.emit("tool:progress", { id = "second", text = "Searching the second file" })
	child.emit("tool:progress", { text = "Ambiguous legacy progress" })
	settle(h, 0.2)
	local first, second = find("Call_1"), find("Call_2")
	check("parallel progress belongs to its call", find("CallDetail", first).Text == "Reading the first file"
		and find("CallDetail", second).Text == "Searching the second file")
	check("the current work is visible at the top", find("CurrentProgress").Text:find("Reading the first file", 1, true) ~= nil)
	check("final content replaces the transient preview", record.preview == nil and find("LatestMessage").Text == "I found two files."
		and find("LatestReasoning").Text == "Verified its shape")
	local card, button = f.host:FindFirstChild("Agent_" .. record.id, true), f.host:FindFirstChild("Stop", true)
	local created = h.instanceState.count
	for index = 1, 30 do
		child.emit("tool:progress", { id = "first", text = "Progress " .. index })
		settle(h, 0.02)
		if index == 15 then check("continuous updates do not starve rendering", find("CallDetail", first).Text:find("Progress", 1, true) ~= nil) end
	end
	settle(h, 0.15)
	check("progress updates reuse every existing row and action", find("Call_1") == first
		and f.host:FindFirstChild("Agent_" .. record.id, true) == card and f.host:FindFirstChild("Stop", true) == button
		and h.instanceState.count == created and find("CallDetail", first).Text == "Progress 30")
	child.emit("tool:result", { id = "second", name = "file_search", text = "Found two matches", ms = 20 })
	check("finishing the latest parallel call reveals the remaining one", record.currentTool == "file_read")
	child.emit("tool:progress", { text = "Only one remains" })
	check("unscoped progress is safe with one remaining call", record.activity[1].progress == "Only one remains")
	child.emit("tool:result", { id = "first", name = "file_read", text = "Read complete", ms = 40 })
	check("completed tools cannot remain current", record.currentTool == nil)
	finish()
	check("an open monitor receives the final report", find("AgentReport").Visible and find("Report").Text == "Finished fixture report"
		and not find("StopAgent").Visible and find("FollowUp").Text:find("Open for a follow-up", 1, true) ~= nil)
	f.healthy(); panel.scroll.instance:Destroy(); f.close()
end)

case("activity is bounded and following up replaces current run state", function()
	local f, agents, record, panel, modal, find, finish = setup()
	local child, h = record.session, f.h
	local long = string.rep("fixture ", 1000)
	child.emit("assistant:preview", { text = long, reasoning = long })
	check("preview storage is bounded", #record.preview.text <= 4096 and #record.preview.reasoning <= 4096)
	local unicode = string.rep("\226\128\148", 2000)
	child.emit("assistant:preview", { text = unicode .. "Newest words", reasoning = long, limited = true })
	settle(h, 0.2)
	check("bounded excerpts retain new output and valid UTF-8", record.preview.text:sub(-12) == "Newest words"
		and f.env.require("runtime/util").sanitise(record.preview.text) == record.preview.text
		and find("MessageTitle").Text:find("latest excerpt", 1, true) ~= nil
		and find("Delivery").Text:find("preview limit reached", 1, true) ~= nil)
	for index = 1, 80 do
		child.emit("tool:call", { id = "call-" .. index, name = "file_read" })
		child.emit("tool:progress", { id = "call-" .. index, text = long })
		child.emit("tool:result", { id = "call-" .. index, text = long })
	end
	settle(h, 0.2)
	check("retention is explicit and keeps only recent bounded records", #record.activity == 24 and record.activity[1].index == 57
		and #record.activity[1].progress <= 1024 and #record.activity[1].summary <= 1024
		and find("ActivityHint").Text:find("earlier calls are omitted", 1, true) ~= nil)
	finish()
	local inspected = false
	f.loaded["agent/loop"].run = function(nextChild)
		inspected = nextChild == child and record.ms == nil and record.latestText == nil and record.preview == nil
			and #record.activity == 0 and record.currentTask == "Check the follow-up" and record.runCallBase == 80
		nextChild.emit("tool:call", { id = "follow", name = "file_read" })
		nextChild.emit("tool:progress", { text = "Follow-up progress" })
		check("follow-up call scoping uses this run's counters", record.activity[1].progress == "Follow-up progress")
		nextChild.emit("tool:result", { id = "follow", text = "Follow-up found" })
		return "Follow-up report"
	end
	local result = f.run(function() return agents.followUp({ id = record.id, task = "Check the follow-up" }) end)
	settle(h, 0.2)
	check("follow-ups reuse context and reset the monitor run", inspected and result.text == "Follow-up report" and record.runs == 2)
	check("open details replace old activity after a follow-up", modal.card:FindFirstChild("Call_57", true) == nil
		and find("Call_81") ~= nil and find("LiveMeta").Text:find("1 of 1 calls finished", 1, true) ~= nil)
	f.healthy(); panel.scroll.instance:Destroy(); f.close()
end)

case("a slow call survives faster parallel activity without unbounded retention", function()
	local f, agents, record, panel, modal, find, finish = setup()
	local child = record.session
	child.emit("tool:call", { id = "slow", name = "web_fetch" })
	for index = 1, 60 do
		child.emit("tool:call", { id = "fast-" .. index, name = "file_read" })
		child.emit("tool:result", { id = "fast-" .. index, text = "Read" })
	end
	child.emit("tool:progress", { id = "slow", text = "Still fetching the page" })
	settle(f.h, 0.2)
	check("the active call remains current and visible", #record.activity == 24 and record.activity[1].id == "slow"
		and record.currentTool == "web_fetch" and find("CurrentProgress").Text:find("Still fetching", 1, true) ~= nil)
	finish()
	f.healthy(); panel.scroll.instance:Destroy(); f.close()
end)

case("stop, close and hidden views release monitor work", function()
	local f, agents, record, panel, modal, find = setup()
	local h, child = f.h, record.session
	child.emit("tool:call", { id = "waiting", name = "file_read" })
	settle(h, 0.2)
	h.click(find("StopAgent"))
	settle(h, 0.2)
	check("stop reaches the child and preserves an interrupted outcome", record.status == "stopped" and child.abortFlag
		and record.activity[1].interrupted and find("CallTitle").Text:find("no result", 1, true) ~= nil)
	modal.close(); settle(h, 0.25)
	local note = f.host:FindFirstChild("Note", true)
	local oldText = note.Text
	panel.setVisible(false)
	record.report = "Updated while hidden"; agents.changed:fire()
	settle(h, 0.3)
	check("hidden registers suspend drawing", note.Text == oldText)
	panel.setVisible(true)
	check("return catches up in the existing row", f.host:FindFirstChild("Note", true) == note and note.Text == "Updated while hidden")
	local listeners = agents.changed:count()
	panel.scroll.instance:Destroy()
	local created = h.instanceState.count
	agents.changed:fire(); settle(h, 0.3)
	check("destroyed panels unsubscribe and cannot create more work", agents.changed:count() == listeners - 1 and created == h.instanceState.count)
	f.healthy(); f.close()
end)

case("clearing history closes an open monitor even when its register is hidden", function()
	local f, agents, record, panel, modal, find, finish = setup()
	finish()
	panel.setVisible(false)
	check("finished monitor is initially open and resumable", not modal.closed and record.session ~= nil)
	agents.clearHistory()
	settle(f.h, 0.3)
	check("removed records cannot leave a resumable monitor open", agents.get(record.id) == nil and modal.closed
		and modal.card.Parent == nil and #f.env.require("ui/overlay").open == 0
		and f.host:FindFirstChild("Agent_" .. record.id, true) == nil)
	local created = f.h.instanceState.count
	agents.changed:fire(); settle(f.h, 0.3)
	check("closed monitors stop rendering removed records", created == f.h.instanceState.count)
	f.healthy(); panel.scroll.instance:Destroy(); f.close()
end)

suite.finish()
