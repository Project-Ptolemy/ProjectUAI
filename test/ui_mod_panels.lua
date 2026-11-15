-- Bounded native panel models, real shared controls, and mount-independent state.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Native mod panels")
local case, check = suite.case, suite.check
local function owner(f, name)
	return { id = name or "fixture-mod", invoke = function(fn, ...) return fn(...) end,
		gate = function() return true end, show = function(key) return key end }
end
local function create(f)
	local models = f.env.require("runtime/ui_mod_panels")
	local panel = assert(models.create({ id = "workbench", title = "Project workbench", description = "A native working panel" }, owner(f)))
	local section = assert(panel:Section({ id = "actions", title = "Project actions" }))
	return models, panel, section
end
case("panel identity, labels, values and collections are validated before admission", function()
	local f = F.new(); local models, panel, section = create(f)
	check("duplicate stable panel ids are refused", models.create({ id = "workbench", title = "Duplicate" }, owner(f)) == nil)
	check("native navigation labels stay text only", models.create({ id = "icons", title = "Panel ✓" }, owner(f)) == nil
		and section:Button({ id = "decorated", text = "Run <b>now</b>" }) == nil)
	check("duplicate section and control ids are refused", panel:Section({ id = "actions", title = "Again" }) == nil
		and section:Text({ id = "actions", text = "Collision" }) == nil)
	local toggle = assert(section:Toggle({ id = "enabled", text = "Enabled", value = true }))
	check("control values keep their types", toggle:Set("false") == nil and toggle:Get() == true)
	check("input values remain bounded UTF-8", section:Input({ id = "invalid", text = "Input", value = "\255" }) == nil
		and section:Input({ id = "oversized", text = "Input", value = string.rep("a", 8001) }) == nil)
	check("select options reject sparse and duplicate values", section:Select({ id = "sparse", text = "Destination", options = {
		[1] = { value = "one", label = "One" }, extra = { value = "two", label = "Two" } } }) == nil
		and section:Select({ id = "duplicates", text = "Destination", options = {
		{ value = "same", label = "One" }, { value = "same", label = "Two" } } }) == nil)
	check("slider arithmetic excludes nonfinite and unusable steps", section:Slider({ id = "nan", text = "Range", min = 0, max = 0 / 0 }) == nil
		and section:Slider({ id = "tiny", text = "Range", min = 0, max = 100, step = 1e-300 }) == nil)
	local slider = assert(section:Slider({ id = "range", text = "Range", min = 0, max = 10, step = 2, value = 3 }))
	check("slider values quantize consistently", slider:Get() == 4 and slider:Set(99) == true and slider:Get() == 10)
	local select = assert(section:Select({ id = "choice", text = "Choice", options = { { value = "original", label = "Original" } } }))
	for index = 4, 32 do assert(section:Text({ id = "text-" .. index, text = "Retained value" })) end
	check("a native panel has at most 32 controls", section:Text({ id = "extra", text = "Too many" }) == nil)
	for index = 2, 8 do assert(panel:Section({ id = "section-" .. index, title = "Section " .. index })) end
	check("a native panel has at most eight sections", panel:Section({ id = "section-nine", title = "Too many" }) == nil)
	for index = 2, 4 do assert(models.create({ id = "panel-" .. index, title = "Panel " .. index }, owner(f))) end
	check("a mod has at most four native panels", models.create({ id = "panel-five", title = "Too many" }, owner(f)) == nil)
	local snapshot = models.snapshot(panel.key)
	snapshot.sections[1].controls[1].value = false
	snapshot.sections[1].controls[3].options[1].value = "mutated"
	snapshot.sections[1].controls[3].options[1].label = "Mutated"
	check("presentation snapshots cannot rewrite retained state", toggle:Get() == true)
	check("nested snapshot options cannot rewrite the live select catalogue", select:Set("mutated") == nil and select:Get() == "original"
		and models.snapshot(panel.key).sections[1].controls[3].options[1].label == "Original")
	panel:Destroy()
	check("destruction closes registration and callbacks", not panel:IsAlive() and models.snapshot(panel.key) == nil and toggle:Set(false) == nil)
	f.healthy(); f.close()
end)
case("shared native controls update existing fields and callbacks survive remounts", function()
	local f = F.ui(390, 700); local models, panel, section = create(f)
	local calls, toggles = 0, 0
	local text = assert(section:Text({ id = "status", text = "Ready <literal text>" }))
	local input = assert(section:Input({ id = "notes", text = "Working notes", value = "Keep this draft", multiline = true }))
	assert(section:Button({ id = "run", text = "Refresh status", callback = function() calls = calls + 1; text:Set("Refresh " .. calls) end }))
	assert(section:Toggle({ id = "watch", text = "Watch progress", callback = function() toggles = toggles + 1 end }))
	local choice = assert(section:Select({ id = "destination", text = "Destination", options = {
		{ value = "code", label = "Code workspace" }, { value = "vault", label = "Master Vault" } } }))
	local render = f.env.require("ui/mod_panel")
	local view = assert(render.new(f.host, panel.key)); f.h.settle(0.2)
	local field = assert(f.h.byName("UiModNativeInput_notes", view.root)):FindFirstChildOfClass("TextBox")
	local textLabel = assert(f.h.byName("UiModNativeText_status", view.root))
	check("native text displays literal content", textLabel.Text == "Ready <literal text>" and textLabel.RichText == false)
	field.Text = "My current project draft"; f.h.settle(0.2)
	check("the original native field edits the retained value", input:Get() == field.Text and field.Text == "My current project draft")
	f.h.click(assert(f.h.byName("UiModNativeButton_run", view.root))); f.h.settle(0.2)
	check("actions update the same native widgets", calls == 1 and textLabel.Text == "Refresh 1"
		and f.h.byName("UiModNativeInput_notes", view.root):FindFirstChildOfClass("TextBox") == field)
	f.h.click(assert(f.h.byName("UiModNativeToggle_watch", view.root))); f.h.settle(0.2)
	check("native switches call only the domain callback", toggles == 1 and panel:Get("watch"):Get() == true)
	f.h.click(assert(f.h.byName("UiModNativeSelect_destination", view.root))); f.h.settle(0.2)
	local overlay = f.env.require("ui/overlay")
	local menu = overlay.open[#overlay.open]
	check("select uses the normal anchored native menu", menu and not menu.closed and f.h.byName("Option_vault", menu.card) ~= nil)
	f.h.click(assert(f.h.byName("Option_vault", menu.card))); f.h.settle(0.2)
	check("menu actions preserve exact selected values", choice:Get() == "vault")
	field.Text = string.rep("x", 8001); f.h.settle(0.2)
	check("invalid native edits restore the original retained input", field.Text == "My current project draft" and input:Get() == field.Text)
	view.setVisible(false); text:Set("Changed while hidden"); f.h.settle(0.2)
	check("hidden panels suspend drawing", textLabel.Text == "Refresh 1")
	view.setVisible(true)
	check("returning reconciles retained state", textLabel.Text == "Changed while hidden")
	view.destroy()
	view = assert(render.new(f.host, panel.key)); f.h.settle(0.2)
	check("new presentation mounts retain panel values", f.h.byName("UiModNativeInput_notes", view.root):FindFirstChildOfClass("TextBox").Text == "My current project draft"
		and f.h.byName("UiModNativeText_status", view.root).Text == "Changed while hidden")
	panel:Destroy()
	f.h.click(assert(f.h.byName("UiModNativeButton_run", view.root))); f.h.settle(0.2)
	check("stale mounted controls cannot run released callbacks", calls == 1 and not panel:IsAlive())
	view.destroy(); f.healthy(); f.close()
end)
case("deferred field events preserve silent updates and report only actual edits", function()
	local f = F.ui(390, 700); local models, panel, section = create(f)
	local edits = {}
	local input = assert(section:Input({ id = "deferred", text = "Working notes", value = "Original draft",
		callback = function(value) edits[#edits + 1] = value end }))
	local view = assert(f.env.require("ui/mod_panel").new(f.host, panel.key)); f.h.settle(0.2)
	local field = assert(f.h.byName("UiModNativeInput_deferred", view.root)):FindFirstChildOfClass("TextBox")
	local event, pending = field:GetPropertyChangedSignal("Text"), {}
	local fire = event.Fire
	event.Fire = function(self) pending[#pending + 1] = function() fire(self) end end
	local function flush()
		local ready = pending; pending = {}
		for _, deliver in ipairs(ready) do deliver() end
	end
	field:CaptureFocus()
	assert(input:Set("Programmatic update", false)); f.h.settle(0.2)
	check("a silent update paints the original field before its deferred event", field.Text == "Programmatic update" and #pending == 1)
	check("a silent repaint retains the native field and its focus", f.h.byName("UiModNativeInput_deferred", view.root):FindFirstChildOfClass("TextBox") == field
		and f.h.services.UserInputService:GetFocusedTextBox() == field)
	flush(); f.h.settle(0.2)
	check("a deferred programmatic repaint cannot notify the domain callback", #edits == 0 and input:Get() == "Programmatic update")
	event:Fire(); flush(); f.h.settle(0.2)
	check("same-value field events remain silent", #edits == 0)
	field.Text = "Actual user edit"; flush(); f.h.settle(0.2)
	check("a deferred real edit notifies exactly once", #edits == 1 and edits[1] == "Actual user edit" and input:Get() == "Actual user edit")
	field.Text = string.rep("x", 8001); flush(); flush(); f.h.settle(0.2)
	check("invalid deferred edits restore the draft without a callback echo", field.Text == "Actual user edit" and input:Get() == field.Text and #edits == 1)
	assert(input:Set("Explicit notification", true)); f.h.settle(0.2); flush(); f.h.settle(0.2)
	check("explicit notifications retain their domain semantics without a deferred duplicate", #edits == 2 and edits[2] == "Explicit notification")
	panel:Destroy(); field.Text = "Stale event"; flush(); f.h.settle(0.2)
	check("deferred events cannot reopen released callback admission", #edits == 2 and models.snapshot(panel.key) == nil)
	view.destroy(); f.healthy(); f.close()
end)
case("unrelated native updates preserve slider gestures and external values reconcile", function()
	local f = F.ui(390, 700); local models, panel, section = create(f)
	local committed = {}
	local status = assert(section:Text({ id = "status", text = "Waiting" }))
	local slider = assert(section:Slider({ id = "range", text = "Range", min = 0, max = 10, step = 1, value = 2,
		callback = function(value) committed[#committed + 1] = value end }))
	local view = assert(f.env.require("ui/mod_panel").new(f.host, panel.key)); f.h.settle(0.2)
	local shell = assert(f.h.byName("UiModNativeSlider_range", view.root))
	local track = assert(f.h.byName("Track", shell))
	local hit = assert(shell:FindFirstChildOfClass("TextButton"))
	local label = assert(f.h.byName("UiModNativeValue_range", view.root))
	local E, V = f.h.sandbox.Enum, f.h.dt.Vector3
	local function begin(alpha)
		local input = { UserInputType = E.UserInputType.MouseButton1, UserInputState = E.UserInputState.Begin,
			Position = V.new(track.AbsolutePosition.X + track.AbsoluteSize.X * alpha, track.AbsolutePosition.Y, 0),
			Changed = require("instance").newSignal("native slider gesture") }
		hit.InputBegan:Fire(input)
		return input
	end
	local function finish(input)
		input.UserInputState = E.UserInputState.End
		input.Changed:Fire(); f.h.services.UserInputService.InputEnded:Fire(input); f.h.settle(0.2)
	end
	local gesture = begin(0.8)
	check("native slider previews a gesture before one domain commit", shell:GetAttribute("UAIValue") == 8 and label.Text == "8"
		and slider:Get() == 2 and #committed == 0)
	status:Set("Background update"); f.h.settle(0.2)
	check("an unrelated readout cannot erase the pending slider value", shell:GetAttribute("UAIValue") == 8 and label.Text == "8"
		and slider:Get() == 2 and #committed == 0)
	view.setVisible(true)
	check("reasserting an already visible panel cannot reset its slider draft", shell:GetAttribute("UAIValue") == 8 and label.Text == "8")
	finish(gesture)
	check("release commits the retained gesture exactly once", slider:Get() == 8 and #committed == 1 and committed[1] == 8)
	gesture = begin(0.2)
	assert(slider:Set(6, false)); f.h.settle(0.2)
	check("an intentional external value change reconciles the current slider", shell:GetAttribute("UAIValue") == 6 and label.Text == "6"
		and slider:Get() == 6 and #committed == 1)
	finish(gesture)
	check("a reconciled gesture cannot commit the superseded pending value", slider:Get() == 6 and #committed == 2 and committed[2] == 6)
	gesture = begin(0.3)
	view.setVisible(false); finish(gesture)
	check("a hidden view cannot commit a stale native gesture", slider:Get() == 6 and #committed == 2)
	view.setVisible(true)
	check("returning from a hidden view restores its authoritative retained slider", shell:GetAttribute("UAIValue") == 6 and label.Text == "6")
	view.destroy(); panel:Destroy(); f.healthy(); f.close()
end)
case("running callbacks are owned and stale control requests cannot overlap", function()
	local f = F.new(); local models, panel, section = create(f)
	local calls, finished = 0, false
	local action = assert(section:Button({ id = "slow", text = "Owned action", callback = function()
		calls = calls + 1; f.h.sched.wait(1); finished = true
	end }))
	f.h.sched.spawn(function() models.trigger(panel.key, "slow") end)
	f.h.sched.advance(0.1)
	check("an outstanding action holds its own control admission", models.snapshot(panel.key).sections[1].controls[1].busy == true
		and action:Activate() == nil and calls == 1)
	panel:Destroy(); f.h.sched.advance(1.1)
	check("native callbacks finish cooperatively without reviving released panels", finished and models.snapshot(panel.key) == nil and action:Activate() == nil and calls == 1)
	f.healthy(); f.close()
end)
suite.finish()
