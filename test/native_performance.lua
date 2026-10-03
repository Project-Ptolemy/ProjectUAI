-- Work and retention budgets are deterministic; elapsed times are diagnostic only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local F = require("coding_fixture")
local suite = F.suite("Native performance")
local case, check = suite.case, suite.check
local function rows(root, name)
	local count = 0
	for _, node in ipairs(root:GetDescendants()) do if node.Name == name then count = count + 1 end end
	return count
end

case("signal bursts reuse subscriptions while nested mutation preserves dispatch order", function()
	local f = F.new(); local signal = f.env.require("runtime/signal").new("performance")
	local seen, disconnectSecond, disconnectLate = {}, nil, nil
	local disconnectFirst = signal:connect(function(kind)
		seen[#seen + 1] = "first:" .. kind
		if kind == "outer" then
			disconnectSecond()
			disconnectLate = signal:connect(function(value) seen[#seen + 1] = "late:" .. value end)
			signal:fire("nested")
		end
	end)
	disconnectSecond = signal:connect(function(kind) seen[#seen + 1] = "second:" .. kind end)
	signal:once(function(kind) seen[#seen + 1] = "once:" .. kind end)
	local handlers = signal.handlers
	signal:fire("outer")
	check("nested dispatch sees additions, skips removals and calls once only once", table.concat(seen, ",") == "first:outer,first:nested,once:nested,late:nested")
	check("compaction retains only live subscriptions", signal:count() == 2 and #signal.handlers == 2)
	for _ = 1, 1000 do signal:fire("burst") end
	check("event bursts keep the subscription storage and exact delivery count", signal.handlers == handlers and #seen == 2004)
	disconnectFirst(); disconnectFirst(); disconnectLate(); disconnectSecond()
	check("repeated disconnection releases all subscription references", signal:count() == 0 and #signal.handlers == 0)
	f.healthy(); f.close()
end)

case("yielded signals keep their original boundary through mutation and clear", function()
	local f = F.new(); local signal = f.env.require("runtime/signal").new("yielded")
	local seen = {}
	signal:connect(function(kind)
		seen[#seen + 1] = "first:" .. kind
		if kind == "outer" then coroutine.yield("waiting") end
	end)
	local disconnect = signal:connect(function(kind) seen[#seen + 1] = "removed:" .. kind end)
	local worker = coroutine.create(function() signal:fire("outer") end)
	local ok, state = coroutine.resume(worker)
	check("a signal subscriber may yield", ok and state == "waiting" and signal.firing)
	disconnect()
	signal:connect(function(kind) seen[#seen + 1] = "late:" .. kind end)
	signal:fire("nested")
	assert(coroutine.resume(worker))
	check("resuming does not visit newly appended or disconnected subscriptions", table.concat(seen, ",") == "first:outer,first:nested,late:nested" and not signal.firing)
	worker = coroutine.create(function() signal:fire("outer") end)
	assert(coroutine.resume(worker))
	signal:clear()
	local fresh = 0; signal:connect(function() fresh = fresh + 1 end)
	signal:fire("fresh"); assert(coroutine.resume(worker))
	check("clear detaches a suspended dispatch from replacement subscriptions", fresh == 1 and signal:count() == 1 and signal.depth == 0 and not signal.firing)
	local errors, delivered = 0, 0
	signal:clear(); signal.onError = function() errors = errors + 1; error("reporter failed") end
	signal:connect(function() error("subscriber failed") end)
	signal:connect(function() delivered = delivered + 1 end); signal:fire()
	check("subscriber and error reporter failures do not interrupt delivery", errors == 1 and delivered == 1)
	signal:clear(); local recursive = 0
	signal:connect(function() recursive = recursive + 1; signal:fire() end); signal:fire()
	check("recursive dispatch still stops at the existing depth limit", recursive == 32 and signal.dropped == 1 and not signal.firing)
	f.healthy(); f.close()
end)

case("focused syntax previews blink without rescanning or measuring unchanged text", function()
	local f = F.ui(640, 420); local P, lexer = f.env.require("ui/primitives"), f.env.require("runtime/code_lexer")
	local before = f.env.run.Heartbeat:Count()
	local field = P.field(f.host, { text = string.rep("local value = 123\n", 200), role = "mono", multiline = true, bare = true, size = f.h.sandbox.UDim2.fromScale(1, 1) })
	local box = field.instance; box:CaptureFocus(); box.CursorPosition = 7; f.h.sched.advance(0.1)
	local caret = f.h.byName("PreviewCaret", box); local initialRows, initialX = rows(box, "SyntaxPreviewLine"), caret.Position.X.Offset
	local measure, scan, measured, scanned, blinks = P.measureText, lexer.scan, 0, 0, 0
	P.measureText = function(...) measured = measured + 1; return measure(...) end
	lexer.scan = function(...) scanned = scanned + 1; return scan(...) end
	caret:GetPropertyChangedSignal("Visible"):Connect(function() blinks = blinks + 1 end)
	for _ = 1, 120 do f.h.frame(1 / 60) end
	check("idle focused previews do no syntax scans or text measurements", scanned == 0 and measured == 0)
	check("the caret keeps blinking and the row pool stays stable", blinks >= 3 and rows(box, "SyntaxPreviewLine") == initialRows)
	box.CursorPosition = 10; box.SelectionStart = 7; f.h.sched.advance(0.05)
	check("native cursor and selection changes still redraw geometry", caret.Visible and caret.Position.X.Offset > initialX and f.h.byName("PreviewSelection", box).Visible and scanned > 0)
	box.Text = "return 42"; box.CursorPosition, box.SelectionStart = 9, -1; f.h.sched.advance(0.05)
	check("editing still updates visible syntax", f.h.byName("SyntaxPreviewLine", box).Text:find("return", 1, true) ~= nil)
	box:ReleaseFocus(); field.shell:Destroy(); f.h.sched.advance(0.05)
	measured, scanned = 0, 0; f.h.frame(1 / 60)
	check("destroyed previews release their frame callback and queued work", f.env.run.Heartbeat:Count() == before and measured == 0 and scanned == 0)
	P.measureText, lexer.scan = measure, scan; f.healthy(); f.close()
end)

case("focused editor caret blink does not remeasure a long source line", function()
	local f = F.ui(640, 420); local P, store = f.env.require("ui/primitives"), f.env.require("runtime/code_store")
	assert(store.update(store.activeId(), "local value = '" .. string.rep("x", 8000) .. "'"))
	local editor = f.env.require("ui/code/editor").new(f.host)
	editor.box:CaptureFocus(); editor.box.CursorPosition = 1000; f.h.sched.advance(0.6)
	local caret = f.h.byName("SourceCaret", editor.root); local initialX = caret.Position.X.Offset
	local measure, measured, blinks = P.measureText, 0, 0
	P.measureText = function(...) measured = measured + 1; return measure(...) end
	caret:GetPropertyChangedSignal("Visible"):Connect(function() blinks = blinks + 1 end)
	for _ = 1, 120 do f.h.frame(1 / 60) end
	check("idle editor frames have no text-measurement work", measured == 0 and blinks >= 3)
	editor.box.CursorPosition = 1200
	check("moving the editor cursor still updates its measured position", caret.Visible and caret.Position.X.Offset > initialX and measured > 0)
	editor.setVisible(false); measured = 0
	for _ = 1, 30 do f.h.frame(1 / 60) end
	check("hidden editor releases focus and does no caret measurement", not caret.Visible and not editor.box:IsFocused() and measured == 0)
	P.measureText = measure; editor.destroy(); f.healthy(); f.close()
end)

case("line insertion reuses shifted syntax while multiline state changes invalidate it", function()
	local f = F.new(); local lexer = f.env.require("runtime/code_lexer")
	local lines = {}; for i = 1, 6000 do lines[i] = "local value" .. i .. " = " .. i end
	local source = table.concat(lines, "\n"); local original = lexer.scan(source)
	local inserted = lexer.scan("-- inserted\n" .. source, original)
	check("inserting one line lexes only that line", inserted.lexed == 1 and inserted.reused == 6000 and inserted.spans[6001] == original.spans[6000])
	check("unchanged source reuses the entire cache", lexer.scan(inserted.source, inserted) == inserted)
	local block = lexer.scan("--[[\ninside\n]]\nreturn 1")
	local changed = lexer.scan("-- plain\ninside\n]]\nreturn 1", block)
	check("changed multiline state invalidates affected lines only", changed.lexed == 3 and changed.reused == 1 and changed.spans[2][1].kind ~= "comment" and changed.spans[4] == block.spans[4])
	print(string.format("metric lexer: %d bytes, %d reused lines, %d newly lexed", #source, inserted.reused, inserted.lexed))
	f.close()
end)

case("typing reuses measurements and scroll rendering retains a bounded row pool", function()
	local f = F.ui(640, 420); local store, P = f.env.require("runtime/code_store"), f.env.require("ui/primitives")
	local lines = {}; for i = 1, 5000 do lines[i] = "local value" .. i .. " = " .. i end
	assert(store.update(store.activeId(), table.concat(lines, "\n")))
	local measure, measured = P.measureText, 0
	P.measureText = function(value, options) measured = measured + 1; return measure(value, options) end
	local editor = f.env.require("ui/code/editor").new(f.host); f.h.sched.advance(0.1)
	local initialMeasures, initialRows = measured, rows(editor.root, "SyntaxLine")
	measured = 0; editor.box.Text = "-- new line\n" .. editor.box.Text; f.h.sched.advance(0.1)
	check("a one-line edit does not remeasure the document", initialMeasures >= 5000 and measured < 30)
	for i = 1, 20 do editor.scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, i * 2300) end
	check("scrolling recycles the visible rows", initialRows > 0 and initialRows <= 160 and rows(editor.root, "SyntaxLine") == initialRows)
	print(string.format("metric editor: %d initial measurements, %d edit/scroll measurements, %d retained rows", initialMeasures, measured, initialRows))
	P.measureText = measure; f.healthy(); editor.destroy(); f.close()
end)

case("typing publishes metadata without deep-copying documents or history", function()
	local f = F.new(); local store, util = f.env.require("runtime/code_store"), f.env.require("runtime/util"); store.init()
	assert(store.update(store.activeId(), "--" .. string.rep("a", 240000)))
	local copy, copies, sourceEvents = util.deepCopy, 0, 0
	util.deepCopy = function(...) copies = copies + 1; return copy(...) end
	local off = store.changed:connect(function(event)
		if event.kind == "source" then sourceEvents = sourceEvents + 1; assert(event.source == nil and event.document == nil and event.revision) end
	end)
	for i = 1, 40 do assert(store.update(store.activeId(), store.active().source .. "a", { origin = "typing" })) end
	check("typing has no full-document deep copy", copies == 0 and sourceEvents == 40)
	check("typing bursts coalesce history checkpoints", #store.active().versions <= 3)
	util.deepCopy = copy; off(); f.healthy(); f.close()
end)

case("long lines and large-source pages bound text measurement and drawing", function()
	local f = F.ui(480, 300); local P, store = f.env.require("ui/primitives"), f.env.require("runtime/code_store")
	local measure, largest = P.measureText, 0
	P.measureText = function(value, options) largest = math.max(largest, #value); return measure(value, options) end
	assert(store.update(store.activeId(), "--" .. string.rep("你", 60000)))
	local editor = f.env.require("ui/code/editor").new(f.host)
	editor.scroll.CanvasPosition = f.h.sandbox.Vector2.new(150000, 0)
	local visibleBytes = 0
	for _, node in ipairs(editor.root:GetDescendants()) do if node.Name == "SyntaxLine" and node.Visible then visibleBytes = math.max(visibleBytes, #node.Text) end end
	check("measurement calls use bounded UTF-8 chunks", largest <= 2051)
	check("horizontal rendering emits a bounded rich-text window", visibleBytes > 0 and visibleBytes < 9000)
	local sources, limits, text = f.env.require("runtime/script_sources"), f.env.require("runtime/code_limits"), f.env.require("runtime/code_text")
	local source = string.rep("你", 650000); local item = assert(sources.keep(source, "performance fixture"))
	local page = assert(sources.read(item.id, 1, 1000000))
	check("near-limit source pages remain bounded and UTF-8 aligned", #page.text <= limits.sourcePage and text.boundary(source, page.nextOffset))
	print(string.format("metric long source: %d source bytes, %d measured bytes per call, %d rendered bytes", #source, largest, visibleBytes))
	P.measureText = measure; f.healthy(); editor.destroy(); f.close()
end)

case("source and capture retention stay within count and byte budgets", function()
	local f = F.new(); local sources, limits = f.env.require("runtime/script_sources"), f.env.require("runtime/code_limits")
	limits.sourceSnapshots, limits.sourceCacheBytes = 3, 10000
	local first = assert(sources.keep(string.rep("a", 4000), "fixture")); local owner = {}; assert(sources.pin(first.id, owner))
	for i = 1, 40 do assert(sources.keep(string.rep(tostring(i % 10), 4000), "fixture")) end
	check("source bytes and count cannot grow with completed requests", sources.state().bytes <= 10000 and sources.state().snapshots <= 3 and sources.get(first.id))
	local records, values = f.env.require("runtime/remote_store"), f.env.require("runtime/values")
	records.limits.records, records.limits.bytes = 30, 16000
	for i = 1, 200 do records.begin({ name = "Synthetic", direction = "incoming", method = "OnClientEvent", outcome = "received" }, values.pack(string.rep("x", 300))) end
	local state = records.state()
	check("capture ring cannot grow with traffic", state.retained <= 30 and state.bytes <= 16000 and state.counters.evicted > 0)
	local page = assert(records.exportPage(assert(records.freeze()), 1, 3))
	check("frozen export pages honor the requested bound", #page.items == 3 and page.nextOffset == 4)
	sources.release(owner); f.healthy(); f.close()
end)

suite.finish()
