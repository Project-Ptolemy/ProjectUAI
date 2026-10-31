-- Readouts retain bounded snapshots and expose honest copy outcomes.
local h, UI, window, section, check, done = dofile("test/ui_library_support.lua").new("structured-readouts")
local view = section:TextView({ Id = "log", Text = "Log", Value = "First", Code = true, MaxLength = 32 })
view:Append("\nSecond")
check("text output appends without becoming editable", view:Get() == "First\nSecond" and h.byName("TextView", view.Frame).TextEditable == false)
view:SetDisabled(true); view:SetDisabled(false)
check("reenabling a viewer never makes it editable", h.byName("TextView", view.Frame).TextEditable == false)
local original = view:Get()
check("oversized append preserves previous text", not pcall(function() view:Append(string.rep("x", 33)) end) and view:Get() == original)
local copied
h.sandbox.setclipboard = function(text) copied = text; return false end
check("explicit clipboard refusal is a failure", view:Copy() == false and copied == original)
h.sandbox.setclipboard = function(text) copied = text end
check("successful copy uses the displayed snapshot", view:Copy() and copied == original)
local data = section:KeyValue({ Id = "details", Text = "Details", Items = { { Key = "Count", Value = 2 }, { Key = "Enabled", Value = true } } })
data:SetValue("Count", 3)
check("key/value updates retain row order", data:Get()[1].Key == "Count" and data:Get()[1].Value == "3" and data:Get()[2].Value == "true")
local detached = data:Get(); detached[1].Value = "changed"
check("readout snapshots do not mutate underlying state", data:Get()[1].Value == "3")
check("unknown keys fail without adding data", not pcall(function() data:SetValue("missing", "value") end) and #data:Get() == 2)
local config = h.json.decode(window:ExportConfig())
check("transient readouts stay out of profiles by default", config.values.log == nil and config.values.details == nil)
check("duplicate key rows fail atomically", not pcall(function() data:Set({ { Key = "same", Value = "a" }, { Key = "same", Value = "b" } }) end) and data:Get()[1].Key == "Count")
done()
