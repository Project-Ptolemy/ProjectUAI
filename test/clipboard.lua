-- Clipboard refusals never claim success or reveal payloads through host errors.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Clipboard")
local check, case = suite.check, suite.case

case("executor results distinguish successful nil from false and exceptions", function()
	local f = F.new()
	local caps, clipboard = f.env.require("runtime/caps"), f.env.require("runtime/clipboard")
	local copied
	caps.clipboard = true
	caps.fn.clipboard = function(text) copied = text end
	check("nil success preserves exact bytes", clipboard.write("  exact\ntext  ") and copied == "  exact\ntext  ")
	caps.fn.clipboard = function() return false end
	check("explicit refusal fails", not clipboard.write("text"))
	caps.fn.clipboard = function(text) error("native error: " .. text) end
	local ok, why = clipboard.write("private-copy-value")
	check("exception payload is not exposed", not ok and not why:find("private-copy-value", 1, true))
	check("invalid values are rejected", not clipboard.write({}))
	caps.fn.clipboard = nil
	check("disappearing capability fails safely", not clipboard.write("text"))
	f.healthy(); f.close()
end)

case("code preview copy reports executor refusal", function()
	local f = F.ui(900, 650)
	local caps = f.env.require("runtime/caps")
	caps.clipboard = true; caps.fn.clipboard = function() return false end
	local common = f.env.require("ui/code/common")
	check("shared code copy returns failure", common.copy("source text") == false)
	local toasts = f.env.require("ui/overlay").toasts
	check("refusal produces visible feedback", #toasts > 0)
	f.healthy(); f.close()
end)

suite.finish()
