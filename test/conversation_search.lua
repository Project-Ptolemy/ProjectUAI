-- Search results remain dialogue-only, valid UTF-8 and fully reachable.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Conversation search")
local check, case = suite.check, suite.case

case("context fallback never presents system or tool data as a reply", function()
	local f = F.new()
	local sessions, util = f.env.require("agent/session"), f.env.require("runtime/util")
	local session = assert(sessions.newThread({ title = "Dialogue" }))
	session.ctx.messages = { { role = "system", content = "private-system-value" },
		{ role = "tool", content = "private-tool-value" }, { role = "assistant", content = "recoverable answer" } }
	check("system context is excluded", #sessions.search("private-system-value") == 0)
	check("tool context is excluded", #sessions.search("private-tool-value") == 0)
	check("retained context dialogue stays searchable", sessions.search("recoverable")[1].session == session)
	session.log = { { kind = "user", text = string.rep("\228\189\160", 19) .. "needle" } }
	local match = sessions.search("needle")[1]
	check("snippet begins on a UTF-8 boundary", match and util.validUtf8(match.snippet))
	f.healthy(); f.close()
end)

case("show more makes every matching conversation reachable", function()
	local f = F.ui(900, 650)
	local sessions = f.env.require("agent/session")
	for index = 1, 25 do assert(sessions.newThread({ title = "Shared title " .. index, activate = false })) end
	local app = f.env.require("ui/app")
	local modal = app.showSearch()
	f.h.settle(0.3)
	local field = assert(f.h.byName("SearchField")):FindFirstChildWhichIsA("TextBox")
	field.Text = "Shared title"; f.h.settle(0.2)
	check("initial page is bounded", f.h.byName("Result_12") and not f.h.byName("Result_13"))
	f.h.click(assert(f.h.byName("SearchMore")))
	check("second page is reachable", f.h.byName("Result_24") ~= nil)
	f.h.click(assert(f.h.byName("SearchMore")))
	check("last match is reachable", f.h.byName("Result_25") and not f.h.byName("SearchMore"))
	field.Text = "Shared title 1"; f.h.settle(0.2)
	check("new query starts from its own first page", not f.h.byName("Result_12"))
	modal.close(); f.h.settle(0.4)
	f.healthy(); f.close()
end)

suite.finish()
