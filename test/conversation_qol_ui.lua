-- Native search navigation and composer recovery exercise the actual controls.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Conversation quality of life UI")
local check, case = suite.check, suite.case
local function checkStack(f, modal, name)
	local stack = assert(f.h.byName(name, modal.content))
	check(name .. " fills available content width", stack.AbsoluteSize.X == modal.content.AbsoluteSize.X and stack.AbsoluteSize.X > 100)
	check(name .. " has no fixed height floor", stack.Size.Y.Scale == 0 and stack.Size.Y.Offset == 0
		and stack.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
	return stack
end
for _, size in ipairs({ { 320, 568 }, { 844, 390 }, { 1280, 720 } }) do
	case("browser cards fit the modal at " .. size[1] .. "x" .. size[2], function()
		local f = F.ui(size[1], size[2]); local sessions = f.env.require("agent/session")
		local session = assert(sessions.newThread({ id = "browse-layout" }))
		session.rename("A long conversation title that should wrap across the available card width")
		local opened
		local modal = assert(f.env.require("ui/conversations").browse({ openSession = function(id) opened = id end }))
		f.h.settle(0.3)
		checkStack(f, modal, "ConversationFilters")
		local rows = checkStack(f, modal, "ConversationResults")
		local row = assert(f.h.byName("Conversation_" .. session.id, rows))
		check("conversation card fills result column", row.AbsoluteSize.X == rows.AbsoluteSize.X)
		local title
		for _, node in ipairs(row:GetDescendants()) do
			if node:IsA("TextLabel") and node.Text == session.title then title = node; break end
		end
		assert(title, "conversation title is rendered")
		check("long title wraps within card", title.TextWrapped and title.Size.X.Scale == 1
			and title.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
		f.h.click(row)
		check("card opens selected conversation", modal.closed and opened == session.id)
		f.h.settle(0.3); f.healthy(); f.close()
	end)
end
case("browser filters and whitespace searches keep the expected conversations", function()
	local f = F.ui(900, 750); local sessions = f.env.require("agent/session")
	local pinned = assert(sessions.newThread({ id = "browse-pinned" })); pinned.rename("Pinned parser"); pinned.setPinned(true)
	local other = assert(sessions.newThread({ id = "browse-other" })); other.rename("Other conversation")
	local modal = assert(f.env.require("ui/conversation_browser").open({ openSession = function() end }))
	local search = f.h.byName("ConversationSearch", modal.content):FindFirstChildOfClass("TextBox")
	search.Text = "  \t "; f.h.settle(0.3)
	check("whitespace preserves all results", f.h.byName("Conversation_" .. pinned.id, modal.content)
		and f.h.byName("Conversation_" .. other.id, modal.content))
	f.h.click(f.h.byName("ConversationFilter", modal.content)); f.h.settle(0.3)
	f.h.click(assert(f.h.byName("Option_pinned", f.env.root))); f.h.settle(0.3)
	check("pinned filter removes unpinned results", f.h.byName("Conversation_" .. pinned.id, modal.content)
		and not f.h.byName("Conversation_" .. other.id, modal.content))
	search.Text = "missing-result"; f.h.settle(0.3)
	check("empty results show zero count", f.h.byName("ConversationCount", modal.content).Text:find("0 conversations", 1, true) == 1)
	search.Text = "parser"; f.h.settle(0.3)
	check("search restores matching pinned result", f.h.byName("Conversation_" .. pinned.id, modal.content) ~= nil)
	f.h.click(f.h.byName("ConversationFilter", modal.content)); f.h.settle(0.3)
	local menu = assert(f.h.byName("MenuLayer", f.env.root))
	modal.close(); f.h.settle(0.5)
	check("closing browser releases filter menu", menu.Parent == nil)
	f.healthy(); f.close()
end)
case("a removed result cannot open during the debounced refresh", function()
	local f = F.ui(900, 750); local sessions = f.env.require("agent/session")
	local session = assert(sessions.newThread({ id = "browse-removed" }))
	sessions.newThread({ id = "browse-retained" })
	local opened = 0
	local modal = assert(f.env.require("ui/conversation_browser").open({ openSession = function() opened = opened + 1 end }))
	local row = assert(f.h.byName("Conversation_" .. session.id, modal.content))
	sessions.remove(session.id); f.h.click(row)
	check("stale card keeps browser open", not modal.closed and opened == 0)
	f.h.settle(0.3)
	check("refresh removes deleted card", not f.h.byName("Conversation_" .. session.id, modal.content))
	modal.close(); f.h.settle(0.3); f.healthy(); f.close()
end)
case("search selects a stable transcript event and releases pending work", function()
	local f = F.ui(900, 750); local sessions = f.env.require("agent/session")
	local session = assert(sessions.newThread({ id = "search-ui" }))
	session.emit("user", { text = "Find the parser" }); session.emit("assistant:text", { text = "Parser result" })
	local opened, selected
	f.loaded["ui/app"] = { openSession = function(id) opened = id end, chatPanel = { view = { jumpTo = function(id) selected = id end } } }
	local modal = assert(f.env.require("ui/chat/search").open(session))
	f.h.byName("TranscriptSearch", modal.card):FindFirstChildOfClass("TextBox").Text = "Parser"
	f.h.settle(0.25)
	checkStack(f, modal, "TranscriptSearchResults")
	local latest = session.log[#session.log].transcriptId
	f.h.click(assert(f.h.byName("SearchResult_" .. latest, modal.card)))
	check("result opens its conversation and exact event", modal.closed and opened == session.id and selected == latest)
	f.h.settle(0.3); f.healthy(); f.close()
end)
case("composer restores session draft without sending it", function()
	local f = F.ui(900, 750); local session = assert(f.env.require("agent/session").newThread({ id = "draft-ui" }))
	assert(session.setDraft({ text = "Recovered question", attachments = {}, expanded = false }))
	local sent = 0
	local composer = f.env.require("ui/chat/composer").new(f.host, { onSend = function() sent = sent + 1 end })
	check("recovery populates composer", composer.field.get() == "Recovered question" and sent == 0)
	composer.field.set("Edited recovered question"); f.h.settle(2)
	check("edits update conversation recovery", session.draft.text == "Edited recovered question")
	local modal = assert(f.env.require("ui/chat/draft").open(composer, session))
	check("details explain recovery", f.h.textOf(modal.card):find("recovery", 1, true) ~= nil)
	modal.close(); f.h.settle(0.3); f.healthy(); f.close()
end)
suite.finish()
