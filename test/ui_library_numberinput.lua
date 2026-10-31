-- Numeric steps share draft validation, atomic forms and saved values.
local h, UI, window, section, check, done = dofile("test/ui_library_support.lua").new("number-input")
local calls = 0
local amount = section:NumberInput({ Id = "amount", Text = "Amount", Min = -2, Max = 3, Step = 0.25, Default = 1.1,
	Callback = function() calls = calls + 1 end })
check("default rounds to a declared step", amount:Get() == 1)
amount:StepBy(1)
check("step commits and emits once", amount:Get() == 1.25 and calls == 1)
amount:StepBy(100)
check("step clamps to maximum", amount:Get() == 3)
local field = h.byName("Input", amount.Frame)
field.Text = "not a number"
check("invalid draft prevents stepping", amount:StepBy(-1) == false and amount:Get() == 3 and amount:GetError())
check("forms reject the same invalid draft", window:CommitInputs({ Ids = { "amount" } }) == false)
field.Text = "-1.7"
check("explicit commit quantizes typed values", amount:Commit(true) and amount:Get() == -1.75)
local saved = window:ExportConfig()
amount:Set(0)
check("profiles retain numeric values", window:ImportConfig(saved) and amount:Get() == -1.75)
amount:SetDisabled(true)
check("disabled controls reject steps", amount:StepBy(1) == false)
amount:SetDisabled(false)
amount:Reset(true)
check("reset retains normalized initial value", amount:Get() == 1)
local before = #section.Controls
check("invalid step does not leak a row", not pcall(function() section:NumberInput({ Step = 0 }) end) and #section.Controls == before)
local even = section:NumberInput({ Id = "even", Text = "Even amount", Step = 2, Default = 2,
	Validate = function(value) return value == 2 or value == 4, "Choose two or four." end })
local draft = h.byName("Input", even.Frame)
draft.Text = "3"
check("custom validation sees the quantized value", even:Commit(true) and even:Get() == 4)
local stepped, message = even:StepBy(1)
check("rejected step preserves value and reports the validator message", not stepped and message == "Choose two or four."
	and even:Get() == 4 and even:GetError() == message)
done()
