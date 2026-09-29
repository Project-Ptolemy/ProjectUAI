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

-- Fixed-height chunks exercise scheduling and spacer corrections independently
-- of the mock's deliberately absent native text measurement.
local function chunks(count, height)
	local f = F.ui(800, 300)
	local P = f.env.require("ui/primitives")
	local scroll = P.scroll(f.host, { size = f.h.sandbox.UDim2.fromScale(1, 1), gap = 0 })
	local viewport = f.env.require("ui/chat/viewport").new(scroll)
	local rows, built = {}, {}
	for index = 1, count do
		local number = index
		local pixels = type(height) == "function" and height(index) or height
		rows[index] = viewport.add(scroll.instance, { order = index, estimate = pixels,
			build = function(parent)
				built[#built + 1] = number
				return { root = P.frame(parent, { size = f.h.sandbox.UDim2.new(1, 0, 0, pixels) }) }
			end })
	end
	return f, scroll, viewport, rows, built
end

case("backtracking reuses recently read content and releases distant content", function()
	local f, scroll, viewport, rows = chunks(100, 100)
	f.h.settle(0.2)
	local first = rows[1].handle
	scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 600); f.h.settle(0.2)
	check("a recently read chunk remains ready beyond prefetch", first and rows[1].handle == first and viewport.warm > 0)
	local created = viewport.created
	scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 0); f.h.settle(0.2)
	check("a short reversal needs no new renderers", rows[1].handle == first and viewport.created == created)
	scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 7000); f.h.settle(0.2)
	check("a distant jump releases the old renderer and keeps its spacer", not rows[1].handle and rows[1].root.Parent and rows[1].height == 100)
	check("distant history does not accumulate renderers", viewport.mounted < 20)
	viewport.destroy(); scroll.instance:Destroy(); f.healthy(); f.close()
end)

case("visible content is built before overscan within the four-chunk slice", function()
	local f, scroll, viewport, rows, built = chunks(40, function(index) return index == 1 and 2000 or 20 end)
	scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 1700)
	f.h.sched.advance(0.016)
	check("the tall visible chunk is not starved by short upcoming rows", rows[1].handle and built[1] == 1)
	check("one rendering slice builds at most four chunks", viewport.created == 4)
	viewport.destroy(); local created = viewport.created
	f.h.settle(0.2)
	check("queued slices cannot rebuild a destroyed viewport", viewport.created == created and viewport.mounted == 0)
	scroll.instance:Destroy(); f.healthy(); f.close()
end)

case("warm content is bounded and native input survives scrolling", function()
	local f, scroll, viewport, rows = chunks(300, 20)
	f.h.settle(0.3)
	local first = rows[1].handle
	local input = f.h.Instance.new("TextBox", first.root); input.Text = "Keep my selection"; input:CaptureFocus()
	for y = 300, 1500, 300 do scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, y); f.h.settle(0.2) end
	check("warm history has a fixed renderer bound", viewport.warm <= 24 and viewport.mounted < 65)
	check("a focused field stays mounted outside the cache band", rows[1].handle == first and input:IsFocused())
	input:ReleaseFocus(); viewport.wake(); f.h.settle(0.2)
	check("released focus allows distant content to be reclaimed", not rows[1].handle)
	local visibleHandle, mounted = rows[76].handle, viewport.mounted
	viewport.setVisible(false)
	local created = viewport.created
	viewport.wake(); f.h.settle(0.2)
	check("hidden view suspends draws and keeps its bounded renderers", viewport.mounted == mounted and viewport.created == created)
	viewport.setVisible(true); f.h.settle(0.2)
	check("returning reuses the exact visible renderer", visibleHandle and rows[76].handle == visibleHandle and viewport.created == created)
	viewport.destroy(); scroll.instance:Destroy(); f.healthy(); f.close()
end)

case("reading anchors track inner chunks when earlier paragraphs are measured", function()
	local f = F.ui(800, 300)
	local P, D = f.env.require("ui/primitives"), f.h.sandbox.UDim2
	local scroll = P.scroll(f.host, { size = D.fromScale(1, 1), gap = 0 })
	local viewport = f.env.require("ui/chat/viewport").new(scroll)
	local inner = {}
	local outer = viewport.add(scroll.instance, { estimate = 1000,
		build = function(parent)
			local root = P.column(parent, { size = D.new(1, 0, 0, 1000), gap = 0 })
			for index = 1, 10 do
				inner[index] = viewport.add(root, { order = index, estimate = 100,
					build = function(into) return { root = P.frame(into, { size = D.new(1, 0, 0, 100) }) } end })
			end
			return { root = root }
		end })
	scroll.instance.CanvasPosition = f.h.dt.Vector2.new(0, 450); f.h.settle(0.3)
	local anchor = viewport.anchor()
	check("the anchor uses the visible paragraph inside a large reply", anchor and anchor.root == inner[5].root and anchor.root ~= outer.root and anchor.offset == -50)
	inner[4].handle.root.AbsoluteSize = f.h.dt.Vector2.new(800, 180)
	check("measurement preserves the same paragraph and line offset", viewport.restoreAnchor(anchor) == 530)
	inner[5].root:Destroy()
	check("a removed anchor lets the view use its retained message position", viewport.restoreAnchor(anchor) == nil)
	viewport.destroy(); scroll.instance:Destroy(); f.healthy(); f.close()
end)

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

case("minimize suspends render work and restores the same measured content", function()
	local f, session, view = setup(35)
	Layout.scroll(f.h, view, 0); Layout.settle(f.h, view, 0.3)
	local state = session.viewState
	local first = view.rows[session.log[1].transcriptId]
	local firstRenderer, mounted = first.handle, view.viewport.mounted
	view.setVisible(false); f.h.settle(0.1)
	local created = f.h.instanceState.count
	session.busy = true
	for index = 1, 40 do session.emit("assistant:text", { text = "Hidden update " .. index }) end
	session.emit("assistant:preview", { streamId = "hidden-stream", text = "Hidden live reply" })
	f.h.settle(0.5)
	check("hidden events allocate no transcript GUI and keep no subscriber", f.h.instanceState.count == created and session.events:count() == 0 and view.viewport.mounted == mounted)
	check("hidden updates still belong to the conversation", #session.log == 110 and session.livePreview.text == "Hidden live reply")
	view.setVisible(true); Layout.settle(f.h, view, 2)
	check("restoring preserves reading state and reconciles preview", not view.pinned and state.pinned == false and view.preview and session.events:count() == 1)
	check("restoring reuses the measured rows instead of replaying the transcript", view.rows[session.log[1].transcriptId] == first and first.root.Parent ~= nil)
	check("restoring reuses the exact renderer the user was reading", firstRenderer and first.handle == firstRenderer)
	view.pinned = true; view.repin(); Layout.settle(f.h, view, 1)
	check("jumping to latest exposes work received while minimized", has(view.scroll.instance, "Hidden live reply", f))
	view.destroy(); created = f.h.instanceState.count
	session.emit("assistant:text", { text = "After destruction" }); f.h.settle(1)
	check("destroyed replay cannot remount content", f.h.instanceState.count == created and session.events:count() == 0)
	f.healthy(); f.close()
end)

suite.finish()
