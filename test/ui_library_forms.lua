package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h, UI, window, section, check, done = require("ui_library_support").new("forms")
local changes, submitted = 0, 0
local name = section:Input({ Id = "name", Required = true, Pattern = "^[%w_-]+$", MaxLength = 32,
	Callback = function() changes = changes + 1 end, OnSubmit = function() submitted = submitted + 1 end })
local amount = section:Input({ Id = "amount", Numeric = true, Default = 2, Validate = function(value)
	return value % 2 == 0, "Use an even number."
end })
local field = h.byName("Input", name.Frame)
local numeric = h.byName("Input", amount.Frame)
check("empty required fields can mount without invoking callbacks", name:Get() == "" and changes == 0)
check("required validation reports a draft error", not name:Validate() and name:GetError() == "This field is required.")
check("incomplete persistent forms cannot produce unusable profiles", not pcall(function() window:ExportConfig() end))
field.Text = "first value"
check("pattern errors preserve the committed value", not name:Commit() and name:Get() == "")
field.Text = "session_one"; numeric.Text = "3"
local ok, errors = window:CommitInputs()
check("form commit validates every draft before applying any", not ok and errors.amount == "Use an even number." and name:Get() == "" and amount:Get() == 2)
numeric.Text = "4"
check("valid form commits are silent by default", window:CommitInputs() and name:Get() == "session_one" and amount:Get() == 4 and changes == 0)
field.Text = "session_two"; field.FocusLost:Fire(true)
check("Enter commits once and invokes submit", submitted == 1 and name:Get() == "session_two" and changes == 1)
name:SetDisabled(true); field.FocusLost:Fire(true)
check("disabled Enter does not submit a stale value", submitted == 1)
name:SetDisabled(false)
field.Text = "draft"
check("draft access does not commit edits", name:GetDraft() == "draft" and name:Get() == "session_two")
check("manual silent commit skips callbacks", name:Commit(true) and changes == 1 and name:Get() == "draft")
name:Reset(true)
check("reset restores an incomplete default without a stale error", name:IsDefault() and name:Get() == "" and name:GetError() == nil)
local before = #section.Controls
check("invalid validator options leave no partial control", not pcall(function() section:Input({ RequiredMessage = false }) end) and #section.Controls == before)
check("malformed patterns are rejected at construction", not pcall(function() section:Input({ Pattern = "[" }) end))
local throwing = section:Input({ Id = "throwing", Persist = false, Validate = function() error("private detail") end })
check("validator exceptions produce a bounded public error", not throwing:Validate() and throwing:GetError() == "Could not validate this field.")
throwing:Destroy()
done()
