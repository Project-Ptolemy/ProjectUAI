-- Reader intent, activity disclosure and incremental replay in the native client.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local Layout = require("chat_layout")
local suite = F.suite("Chat reading")
local check, case = suite.check, suite.case

local function setup()
	local f = F.ui(900, 650)
	local session = f.env.require("agent/session").newThread()
	for index = 1, 15 do
		session.emit("user", { text = "Question " .. index })
		session.emit("assistant:text", { text = "Answer " .. index .. ": " .. string.rep("Readable history. ", 70) })
	end
	local view = f.env.require("ui/chat/view").new(f.host)
	view.attach(session); Layout.settle(f.h, view, 2)
	return f, session, view
end

case("a small upward scroll releases follow and new replies stay below the reader", function()
	local f, session, view = setup()
	local scroll = view.scroll.instance
	local y = scroll.CanvasPosition.Y - 8
	Layout.scroll(f.h, view, y); Layout.settle(f.h, view, 0.3)
	check("eight pixels upward releases follow", not view.pinned and math.abs(scroll.CanvasPosition.Y - y) < 1)
	y = scroll.CanvasPosition.Y
	session.emit("assistant:text", { text = "New reply while reading" })
	Layout.settle(f.h, view, 0.4)
	check("incoming reply does not pull the reader down", not view.pinned and math.abs(scroll.CanvasPosition.Y - y) < 1)
	local latest = f.host:FindFirstChild("Latest", true)
	check("latest reports new unread dialogue", latest.Visible and f.h.textOf(latest):find("1 new message", 1, true) ~= nil)
	f.h.click(latest); Layout.settle(f.h, view, 0.3)
	check("Latest resumes following and clears the indicator", view.pinned and not latest.Visible)
	f.healthy(); view.destroy(); f.close()
end)

case("native tab and minimize round trips reuse content without history replay", function()
	local f, session, view = setup()
	Layout.scroll(f.h, view, 0); Layout.settle(f.h, view, 0.3)
	local first = view.rows[session.log[1].transcriptId]
	local renderer, created = first.handle, view.viewport.created
	local snapshot = session.transcript.snapshot
	local snapshots = 0
	session.transcript.snapshot = function() snapshots = snapshots + 1; return snapshot() end
	for index = 1, 3 do
		view.setVisible(false); f.h.settle(0.2)
		check("hidden content stays ready " .. index, renderer and first.handle == renderer and renderer.root.Parent ~= nil)
		view.setVisible(true)
		check("return is immediately ready without replay slices " .. index, not view.replaying and first.handle == renderer)
		Layout.settle(f.h, view, 0.2)
	end
	check("unchanged history is neither recopied nor redrawn", snapshots == 0 and view.viewport.created == created)
	f.healthy(); view.destroy(); f.close()
end)

case("a live preview survives hiding and catches up in its original renderer", function()
	local f, session, view = setup()
	session.busy = true
	session.emit("request:start", { provider = "Fixture", model = "model" })
	session.emit("assistant:preview", { streamId = "live", text = "Already readable" })
	Layout.settle(f.h, view, 0.3)
	local preview, renderer = view.preview.textHandle, view.preview.textHandle.handle
	view.setVisible(false)
	session.emit("assistant:preview", { streamId = "live", text = "Already readable with a new sentence" })
	f.h.settle(0.2)
	check("hiding preserves the preview's text tree", view.preview.textHandle == preview and preview.handle == renderer and renderer.root.Parent ~= nil)
	view.setVisible(true); Layout.settle(f.h, view, 0.2)
	check("return updates the original preview", view.preview.textHandle == preview and preview.handle == renderer
		and f.h.textOf(renderer.root):find("with a new sentence", 1, true) ~= nil)
	f.healthy(); view.destroy(); f.close()
end)

case("a conversation cleared while hidden cannot resurrect its previous content", function()
	local f, session, view = setup()
	local first = view.rows[session.log[1].transcriptId].root
	view.setVisible(false)
	session.clear()
	check("idle hidden conversation can be cleared", #session.log == 0)
	session.emit("user", { text = "A fresh conversation" })
	view.setVisible(true); Layout.settle(f.h, view, 0.5)
	check("the reset removes old rows before displaying new messages", not first.Parent
		and f.h.textOf(view.scroll.instance):find("A fresh conversation", 1, true) ~= nil
		and not f.h.textOf(view.scroll.instance):find("Question 1", 1, true))
	f.healthy(); view.destroy(); f.close()
end)

case("opening an activity keeps its header anchored as results finish", function()
	local f, session, view = setup()
	session.busy = true
	session.emit("tool:call", { id = "reading-call", name = "file_read", arguments = '{"path":"notes.txt"}' })
	Layout.settle(f.h, view, 0.3)
	local run = view.run
	local header = run.root:FindFirstChild("RunHeader", true)
	check("activity starts as one closed summary", header.Visible and not run.rows.Visible)
	f.h.click(header); f.h.settle(0.1)
	check("opening activity suspends follow", not view.pinned and run.rows.Visible)
	session.emit("tool:result", { id = "reading-call", name = "file_read", ok = true, text = "Saved notes", ms = 40 })
	f.h.settle(0.1)
	check("completion leaves inspected activity open", run.rows.Visible and not view.pinned)
	session.emit("tool:call", { id = "reading-error", name = "file_read", arguments = "{}" })
	f.h.click(header)
	session.emit("tool:error", { id = "reading-error", name = "file_read", ok = false, text = "Missing file" })
	check("failure leaves chosen collapse intact and flags the summary", not run.rows.Visible and f.h.textOf(header):find("failed", 1, true) ~= nil)
	f.healthy(); view.destroy(); f.close()
end)

case("completed call and child activity replay retains their original rows", function()
	local f, session, view = setup()
	session.busy = true
	session.emit("tool:call", { id = "dispatch", name = "dispatch_agent", arguments = "{}" })
	session.emit("subagent:start", { id = "worker", call = "dispatch", label = "Inspect", task = "Inspect the fixture" })
	session.emit("subagent:tool", { id = "worker", callId = "child-read", name = "file_read", arguments = "{}", index = 1 })
	session.emit("subagent:tool:done", { id = "worker", callId = "child-read", name = "file_read", ok = true, summary = "Found fixture", ms = 20 })
	local childResult = session.log[#session.log]
	session.emit("subagent:done", { id = "worker", ok = true, text = "Fixture report", calls = 1, finishedCalls = 1, ms = 30 })
	session.emit("tool:result", { id = "dispatch", name = "dispatch_agent", ok = true, text = "Fixture report", ms = 40 })
	local result = session.log[#session.log]
	session.busy = false
	local child, dispatch = view.rows[childResult.transcriptId], view.rows[result.transcriptId]
	check("both outcomes track their original activity rows", child and dispatch and child.root:IsDescendantOf(dispatch.root))
	view.setVisible(false); view.setVisible(true); Layout.settle(f.h, view, 1)
	check("returning does not replay completed outcomes as new notices or agents", view.rows[childResult.transcriptId] == child and view.rows[result.transcriptId] == dispatch)
	local agents = 0
	for _, node in ipairs(view.scroll.instance:GetDescendants()) do if node.Name == "Subagent" then agents = agents + 1 end end
	check("one delegated task keeps one task card", agents == 1)
	f.healthy(); view.destroy(); f.close()
end)

suite.finish()
