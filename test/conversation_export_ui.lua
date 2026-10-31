-- Export preview, clipboard outcomes and save state operate on one snapshot.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Conversation export UI")
local check, case = suite.check, suite.case

case("copy and save use the previewed snapshot and failed copy remains visible", function()
	local f = F.ui(430, 650)
	local session = { id = "export-ui", title = "Review", log = { { kind = "user", text = "Original question" } } }
	local caps = f.env.require("runtime/caps")
	local copied
	caps.clipboard = true; caps.fn.clipboard = function(text) copied = text; return false end
	local modal = f.env.require("ui/conversation_export").open(session)
	f.h.settle(0.2)
	local preview = assert(f.h.byName("ExportPreview")):FindFirstChildWhichIsA("TextBox")
	check("preview is selectable and read-only", preview.TextEditable == false and preview.Text:find("Original question", 1, true))
	session.log[2] = { kind = "assistant:text", text = "Arrived later" }
	f.h.click(assert(f.h.byName("CopyConversation")))
	check("copy uses frozen text", copied:find("Original question", 1, true) and not copied:find("Arrived later", 1, true))
	check("explicit clipboard refusal is visible", f.h.byName("ExportFeedback").Text:find("Could not", 1, true))
	f.h.click(assert(f.h.byName("SaveConversation")))
	local count, saved = 0, nil
	for path, text in pairs(f.h.files) do
		if path:match("^UAI/export/conversation%-.+%.md$") then count, saved = count + 1, text end
	end
	check("save writes exactly the reviewed text", count == 1 and saved == copied)
	f.h.click(assert(f.h.byName("SaveConversation")))
	local after = 0
	for path in pairs(f.h.files) do if path:match("^UAI/export/conversation%-.+%.md$") then after = after + 1 end end
	check("repeated save does not duplicate exports", after == count)
	modal.close(); f.h.settle(0.4)
	f.healthy(); f.close()
end)

case("unavailable capabilities keep the preview usable", function()
	local f = F.ui(430, 650)
	f.env.require("runtime/caps").clipboard = false
	f.env.require("runtime/fsx").enabled = false
	local modal = f.env.require("ui/conversation_export").open({ id = "empty", log = {} })
	f.h.settle(0.2)
	check("unavailable actions are absent", not f.h.byName("CopyConversation") and not f.h.byName("SaveConversation"))
	check("manual selection guidance remains", f.h.byName("ExportPreview") and f.h.byName("ExportFeedback").Text:find("manually", 1, true))
	modal.close(); f.h.settle(0.4)
	f.healthy(); f.close()
end)

suite.finish()
