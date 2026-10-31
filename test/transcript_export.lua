-- Explicit transcript export excludes internals and verifies owned file bytes.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Transcript export")
local check, case = suite.check, suite.case

case("only retained dialogue enters an immutable Markdown snapshot", function()
	local f = F.new()
	local exporter = f.env.require("runtime/transcript_export")
	local session = { id = "chat", title = "Notes\nfrom today", log = {
		{ kind = "user", text = "A question" }, { kind = "assistant:text", text = "An answer", final = true },
		{ kind = "assistant:text", text = "partial-preview", final = false },
		{ kind = "assistant:reasoning", text = "private-reasoning" },
		{ kind = "tool:call", arguments = "secret-key" }, { kind = "tool:result", text = "private-file" },
		false, { kind = "assistant:text", text = "Another answer" },
	} }
	local text, receipt = exporter.markdown(session)
	check("messages exported chronologically", receipt.messages == 3 and text:find("A question", 1, true) < text:find("An answer", 1, true))
	for _, secret in ipairs({ "private-reasoning", "secret-key", "private-file", "partial-preview" }) do
		check("non-dialogue is excluded", not text:find(secret, 1, true))
	end
	check("title is one line", text:sub(1, 18) == "# Notes from today")
	session.log[1].text = "Changed later"
	check("snapshot does not change with live history", not text:find("Changed later", 1, true))
	check("missing conversation is rejected", exporter.markdown(nil) == nil)
	f.healthy(); f.close()
end)

case("size limits disclose omissions and preserve Unicode", function()
	local f = F.new()
	local exporter, util = f.env.require("runtime/transcript_export"), f.env.require("runtime/util")
	local log = {}
	for index = 1, 60 do log[index] = { kind = "user", text = string.rep("\228\189\160", 10000) } end
	local text, receipt = exporter.markdown({ id = "large", title = "Large", log = log })
	check("bounded whole-message output", receipt.limited and receipt.messages < 60 and #text <= exporter.maxBytes)
	check("valid Unicode and explicit limit", util.validUtf8(text) and text:find("1 MiB limit", 1, true))
	local empty = exporter.markdown({ id = "empty", log = {} })
	check("empty export explains missing dialogue", empty:find("No retained dialogue", 1, true))
	f.healthy(); f.close()
end)

case("saving never overwrites a previous export or reports unverified bytes", function()
	local f = F.new()
	local exporter = f.env.require("runtime/transcript_export")
	local fsx = f.env.require("runtime/fsx")
	f.env.hs.GenerateGUID = function() return "fixed-id" end
	local path = assert(exporter.save("First export"))
	check("saved bytes match", f.h.files[path] == "First export")
	check("collision refuses replacement", exporter.save("Replacement") == nil and f.h.files[path] == "First export")
	f.env.hs.GenerateGUID = function() return "second-id" end
	local write = fsx.write
	fsx.write = function(file) return write(file, "corrupt") end
	local saved, why = exporter.save("Wanted bytes")
	check("failed verification is explicit", not saved and why:find("verification failed", 1, true))
	check("invalid UTF-8 is rejected before saving", exporter.save("bad\255") == nil)
	f.healthy(); f.close()
end)

case("unavailable or failed existence checks cannot authorize an overwrite", function()
	local f = F.new()
	local exporter, caps = f.env.require("runtime/transcript_export"), f.env.require("runtime/caps")
	f.env.hs.GenerateGUID = function() return "reserved" end
	local path = "UAI/export/conversation-reserved.md"
	f.h.files[path] = "Previous export"
	caps.fn.isfile = function() error("native-private-details") end
	local saved, why = exporter.save("Replacement")
	check("failed probe preserves previous bytes", not saved and f.h.files[path] == "Previous export")
	check("probe errors are bounded generic messages", not why:find("native-private-details", 1, true))
	caps.fn.isfile = nil
	check("missing probe cannot write", not exporter.save("Replacement") and f.h.files[path] == "Previous export")
	caps.fn.isfile = function() return nil end
	check("ambiguous probe cannot write", not exporter.save("Replacement") and f.h.files[path] == "Previous export")
	f.healthy(); f.close()
end)

suite.finish()
