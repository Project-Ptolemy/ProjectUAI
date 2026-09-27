-- Viewport and minimized lifecycle contracts against the actual chat renderer.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local Layout = require("chat_layout")
local suite = F.suite("Chat viewport")
local check, case = suite.check, suite.case
local function setup(count)
	local f = F.ui(900, 650)
	local session = f.env.require("agent/session").newThread()
	for index = 1, count do
		session.emit("user", { text = "Question " .. index })
		session.emit("assistant:text", { text = "Answer " .. index .. "\n\n" .. string.rep("A readable paragraph with **detail**. ", 50), model = "viewport-fixture" })
	end
	local view = f.env.require("ui/chat/view").new(f.host)
	view.attach(session); Layout.settle(f.h, view, 2)
	return f, session, view
end
local function has(root, text, f) return f.h.textOf(root):find(text, 1, true) ~= nil end

case("long transcripts mount only nearby text and retain all reading positions", function()
	local f, session, view = setup(120)
	local first = view.rows[session.log[1].transcriptId]
	check("history replay completes without mounting every message", not view.replaying and #session.log == 240 and view.viewport.mounted < 60)
	check("an offscreen first message keeps a spacer", first and first.root.Parent and not first.handle and first.root.Size.Y.Offset > 0)
	check("latest answer is readable", has(view.scroll.instance, "Answer 120", f))
	Layout.scroll(f.h, view, 0); Layout.settle(f.h, view, 1)
	check("scrolling back mounts earlier content", first.handle and has(first.root, "Question 1", f))
	check("scrolling back unmounts the distant last answer", not view.rows[session.log[#session.log].transcriptId].handle and view.viewport.mounted < 60)
	local saved = session.viewState
	view.refresh(); Layout.settle(f.h, view, 2)
	check("refresh retains the reading preference and anchor", not view.pinned and session.viewState.pinned == false and (not saved.anchor or session.viewState.anchor == saved.anchor))
	check("scrolling never changes retained history", #session.log == 240)
	f.healthy(); view.destroy(); f.close()
end)

case("a single large reply is split into nearby Markdown chunks", function()
	local f = F.ui(900, 650); local session = f.env.require("agent/session").newThread()
	local paragraphs = {}; for index = 1, 130 do paragraphs[#paragraphs + 1] = "Paragraph " .. index .. ": " .. string.rep("content ", 12) end
	session.emit("assistant:text", { text = table.concat(paragraphs, "\n\n") })
	local view = f.env.require("ui/chat/view").new(f.host); view.attach(session); Layout.settle(f.h, view, 2)
	local chunks = 0
	for _, node in ipairs(view.scroll.instance:GetDescendants()) do if node.Name == "TranscriptChunk" then chunks = chunks + 1 end end
	check("all paragraph positions remain represented", chunks == 130)
	check("only a bounded portion is drawn", view.viewport.mounted < 35)
	Layout.scroll(f.h, view, 0); Layout.settle(f.h, view, 1)
	check("the start remains accessible after reading the end", has(view.scroll.instance, "Paragraph 1:", f))
	f.healthy(); view.destroy(); f.close()
end)

case("minimize releases render work while events and drafts stay in the session", function()
	local f, session, view = setup(35)
	Layout.scroll(f.h, view, 0); Layout.settle(f.h, view, 0.3)
	local state = session.viewState
	view.setVisible(false); f.h.settle(0.1)
	local created = f.h.instanceState.count
	session.busy = true
	for index = 1, 40 do session.emit("assistant:text", { text = "Hidden update " .. index }) end
	session.emit("assistant:preview", { streamId = "hidden-stream", text = "Hidden live reply" })
	f.h.settle(0.5)
	check("hidden events allocate no transcript GUI and keep no subscriber", f.h.instanceState.count == created and session.events:count() == 0 and view.viewport.mounted == 0)
	check("hidden updates still belong to the conversation", #session.log == 110 and session.livePreview.text == "Hidden live reply")
	view.setVisible(true); Layout.settle(f.h, view, 2)
	check("restoring preserves reading state and reconciles preview", not view.pinned and state.pinned == false and view.preview and session.events:count() == 1)
	view.pinned = true; view.repin(); Layout.settle(f.h, view, 1)
	check("jumping to latest exposes work received while minimized", has(view.scroll.instance, "Hidden live reply", f))
	view.destroy(); created = f.h.instanceState.count
	session.emit("assistant:text", { text = "After destruction" }); f.h.settle(1)
	check("destroyed replay cannot remount content", f.h.instanceState.count == created and session.events:count() == 0)
	f.healthy(); f.close()
end)

suite.finish()
