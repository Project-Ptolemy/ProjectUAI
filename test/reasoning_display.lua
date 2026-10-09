-- Focused reasoning retention, presentation and deferred formatting checks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Reasoning display")
local check, case = suite.check, suite.case

case("transcript excerpts do not limit model reasoning or lose their disclosure on restore", function()
	local f = F.new()
	local source = ("Reasoning evidence. "):rep(4000)
	local context = f.env.require("agent/context").new()
	context.pushAssistant({ content = "Answer", reasoning = source })
	local transcript, owner = f.env.require("agent/transcript"), {}
	local store = transcript.new(owner)
	local event = store.append({ kind = "assistant:reasoning", text = source })
	check("retained text is bounded and marked", event.textTruncated and #event.text <= transcript.limits.field)
	check("the original provider text remains intact", context.messages[1].reasoning == source)
	local wired = f.env.require("provider/openai").wireMessages(context.messages)
	check("reasoning replay is not clipped to the display limit", wired[1].reasoning_content == source)
	local snapshot, metadata = store.snapshot(), store.metadata()
	store.restore(snapshot, context, metadata)
	check("restored excerpt keeps its explicit metadata", owner.log[1].textTruncated and owner.log[1].text == event.text)
	f.healthy(); f.close()
end)

case("folded reasoning does no Markdown work and opening formats only changed text", function()
	local f = F.ui()
	local markdown = f.env.require("ui/markdown")
	local original, calls = markdown.inline, 0
	local originalPlain, plainCalls = markdown.plain, 0
	markdown.inline = function(...) calls = calls + 1; return original(...) end
	markdown.plain = function(...) plainCalls = plainCalls + 1; return originalPlain(...) end
	local thought = f.env.require("ui/chat/message").reasoning(f.host, "**Initial** evidence", 1)
	for index = 1, 20 do thought.setText("**Updated** evidence " .. index) end
	check("closed previews never format hidden text", calls == 0 and plainCalls == 0 and not thought.body.RichText)
	local header = f.h.byName("ReasoningHeader", thought.root)
	f.h.click(header)
	check("opening formats latest text once", calls == 1 and thought.body.RichText and thought.body.Text:find("<b>Updated</b>", 1, true))
	thought.setText("**Updated** evidence 20")
	check("unchanged update does no work", calls == 1)
	f.h.click(header); f.h.click(header)
	check("reopening unchanged content reuses formatting and plain-text parsing", calls == 1 and plainCalls == 1)
	f.h.click(header); thought.setText("Fresh evidence", true)
	check("a new closed excerpt does not format", calls == 1)
	check("clipped text shows Excerpt instead of a false token ceiling", f.h.byName("ReasoningExtent", thought.root).Text == "Excerpt")
	f.h.click(header)
	check("the next opening formats the new source", calls == 2 and thought.body.Text == "Fresh evidence")
	check("explanation distinguishes display from billing and budget", f.h.byName("ReasoningNote", thought.root).Text:find("thinking budget", 1, true))
	thought.root:Destroy(); f.healthy(); f.close()
end)

case("formatting failures preserve readable reasoning and later updates recover", function()
	local f = F.ui()
	local markdown = f.env.require("ui/markdown")
	local original, originalPlain = markdown.inline, markdown.plain
	local thought = f.env.require("ui/chat/message").reasoning(f.host, "**Evidence** <literal>", 1)
	markdown.inline = function() error("fixture formatter failure") end
	markdown.plain = function() error("fixture plain-text failure") end
	f.h.click(f.h.byName("ReasoningHeader", thought.root)); f.h.settle(0.1)
	check("failed formatting keeps literal source visible", not thought.body.RichText and thought.body.Text == "**Evidence** <literal>"
		and f.h.byName("ThoughtViewport", thought.root).AbsoluteSize.Y > 0)
	markdown.inline, markdown.plain = original, originalPlain
	thought.setText("**Recovered** evidence", true)
	check("later content can format in the same row", thought.body.RichText and thought.body.Text:find("<b>Recovered</b>", 1, true))
	thought.append("Next step")
	check("appending cannot erase an existing excerpt disclosure", f.h.byName("ReasoningExtent", thought.root).Text == "Excerpt")
	thought.root:Destroy(); f.healthy(); f.close()
end)

case("normal estimates identify visible text and legacy excerpts remain labelled", function()
	local f = F.ui()
	local thought = f.env.require("ui/chat/message").reasoning(f.host, "Read", 1)
	local label = f.h.byName("ReasoningExtent", thought.root)
	check("estimate explicitly describes shown text", label.Text == "~1 token shown")
	thought.setText("Head\n... [5000 characters omitted] ...\nTail")
	check("older saved clipping markers are recognized", label.Text == "Excerpt")
	thought.root:Destroy(); f.healthy(); f.close()
end)

case("live and replayed combined traces preserve excerpt metadata", function()
	local f = F.ui()
	local session = f.env.require("agent/session").newThread()
	local view = f.env.require("ui/chat/view").new(f.host)
	view.attach(session); f.h.settle(0.5)
	session.busy = true
	session.emit("assistant:reasoning", { text = ("Observed evidence. "):rep(3000) })
	session.emit("assistant:reasoning", { text = "Next step" })
	check("combined live trace remains an excerpt", f.h.byName("ReasoningExtent", view.run.thought.root).Text == "Excerpt")
	view.refresh(); f.h.settle(1)
	check("replay keeps the same disclosure", f.h.byName("ReasoningExtent", view.scroll.instance).Text == "Excerpt")
	view.destroy(); f.healthy(); f.close()
end)

case("live channels report independent limits even when capped text no longer changes", function()
	local f = F.new()
	local session = f.env.require("agent/session").newThread()
	local stream, events = f.env.require("agent/stream"), {}
	session.events:connect(function(event) if event.kind == "assistant:preview" then events[#events + 1] = event end end)
	local preview = stream.new(session, "fixture", function() return false end)
	preview.feed({ choices = { { delta = { content = string.rep("a", stream.previewBytes + 5), reasoning_content = "Why" } } } })
	check("an oversized answer does not mark short reasoning as clipped", events[1].textLimited and not events[1].reasoningLimited and events[1].limited)
	preview.feed({ choices = { { delta = { reasoning_content = string.rep("r", stream.previewBytes - 3) } } } })
	f.h.sched.advance(0.11)
	local count, retained = #events, session.livePreview.reasoning
	check("an exact fit is still complete", #retained == stream.previewBytes and not session.livePreview.reasoningLimited)
	preview.feed({ choices = { { delta = { reasoning_content = "overflow" } } } }); f.h.sched.advance(0.11)
	check("new clipping is emitted even with identical retained bytes", #events == count + 1 and session.livePreview.reasoning == retained and session.livePreview.reasoningLimited)
	preview.close(); f.healthy(); f.close()
end)

case("live reasoning disclosures stay independent of answer preview limits", function()
	for _, limited in ipairs({ "text", "reasoning", "legacy" }) do
		local f = F.ui()
		local session = f.env.require("agent/session").newThread()
		local view = f.env.require("ui/chat/view").new(f.host)
		view.attach(session); f.h.settle(0.2); session.busy = true
		session.emit("user", { text = "Inspect the fixture" })
		local event = { streamId = "fixture", text = "Answer", reasoning = "Evidence", limited = true }
		if limited ~= "legacy" then event.textLimited, event.reasoningLimited = limited == "text", limited == "reasoning" end
		session.emit("assistant:preview", event); f.h.settle(0.2)
		local function checkDisclosure()
			local thought = view.preview.thoughtHandle
			local excerpt = f.h.byName("ReasoningExtent", thought.root).Text == "Excerpt"
			check(limited .. " flags only the affected reasoning channel", excerpt == (limited ~= "text"))
			local shortened = f.h.textOf(view.preview.textHandle.root):find("Reply preview shortened", 1, true) ~= nil
			check(limited .. " flags only the affected answer channel", shortened == (limited ~= "reasoning"))
		end
		checkDisclosure(); view.refresh(); f.h.settle(0.5); checkDisclosure()
		view.destroy(); f.healthy(); f.close()
	end
end)

suite.finish()
