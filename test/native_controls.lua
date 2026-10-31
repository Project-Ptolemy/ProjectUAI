-- Native keyboard, disabled-state and read-only behavior through public handles.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Native controls")
local case, check = suite.case, suite.check

case("slider keyboard commits real stops and ignores field input", function()
	local f = F.ui()
	local P, C = f.env.require("ui/primitives"), f.env.require("ui/controls")
	local commits = {}
	local slider = C.slider(f.host, { stops = { 100, 500, 1000, 2000 }, value = 500,
		onCommit = function(value) commits[#commits + 1] = value end })
	local hit = slider.instance:FindFirstChildWhichIsA("TextButton")
	f.env.guisvc.SelectedObject = hit
	f.h.press("Right"); f.h.settle(0.1)
	check("one key advances one stop", slider.value == 1000 and #commits == 1 and commits[1] == 1000)
	f.h.press("End"); f.h.press("Right")
	check("end reaches maximum without duplicate commits", slider.value == 2000 and #commits == 2)
	f.h.press("Home")
	check("home reaches the minimum", slider.value == 100 and #commits == 3)
	local field = P.field(f.host, { text = "editable" }); field.focus()
	f.h.press("Right")
	check("editing text does not adjust a selected slider", slider.value == 100 and #commits == 3)
	field.instance:ReleaseFocus(); slider.setEnabled(false); f.h.press("Right")
	check("disabled slider is inert", slider.value == 100 and not hit.Selectable and not slider.stepBy(1))
	slider.setEnabled(true); check("reenabled slider accepts a step", slider.stepBy(1) and slider.value == 500)
	slider.instance:Destroy(); f.h.press("Right")
	check("destroyed slider no longer listens", slider.value == 500)
	f.host:Destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("buttons and switches remain inert when disabled or busy", function()
	local f = F.ui()
	local P, C = f.env.require("ui/primitives"), f.env.require("ui/controls")
	local calls = 0
	local button = P.button(f.host, { text = "Run", onClick = function() calls = calls + 1 end })
	button.setBusy(true); button.setEnabled(true); button.instance.Activated:Fire()
	check("busy survives enable refresh", calls == 0 and not button.instance.Selectable)
	button.setBusy(false); button.instance.Activated:Fire()
	check("released busy button can run", calls == 1)
	local row = P.rowButton(f.host, { enabled = false, onClick = function() calls = calls + 1 end })
	row.instance.Activated:Fire(); check("disabled row ignores activation", calls == 1 and not row.instance.Selectable)
	local switch = C.switch(f.host, { value = true, enabled = false, onChange = function() calls = calls + 1 end })
	switch.instance.Activated:Fire()
	check("disabled switch keeps its value", switch.value and calls == 1 and switch.instance:GetAttribute("UAIValue") == true)
	switch.setEnabled(true); switch.instance.Activated:Fire()
	check("enabled switch changes once", switch.value == false and calls == 2)
	f.host:Destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("read-only text supports native selection and disabled fields release focus", function()
	local f = F.ui()
	local field = f.env.require("ui/primitives").field(f.host, { text = "Copy this", readOnly = true })
	check("read-only is selectable but not editable", not field.instance.TextEditable and field.instance.Selectable)
	check("select all focuses and selects text", field.selectAll() and field.instance.SelectionStart == 1
		and field.instance.CursorPosition == #field.get() + 1)
	field.setEnabled(false)
	check("disabled field releases input", f.env.uis:GetFocusedTextBox() == nil and not field.focus())
	field.setEnabled(true); field.setReadOnly(false)
	check("editable state can be restored", field.instance.TextEditable)
	f.host:Destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

suite.finish()
