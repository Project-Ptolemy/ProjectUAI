-- Mobile Code and settings behavior; native keyboard gestures/rendering still
-- require an executor/device. No screenshots or live providers are used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Mobile Code and forms")
local case, check = suite.case, suite.check
local function fixture(width, height)
	local f = F.ui(width, height)
	f.h.services.UserInputService.TouchEnabled, f.h.services.UserInputService.MouseEnabled = true, false
	f.env.require("ui/responsive").init(f.env.root)
	return f
end
local function click(f, name, root) f.h.click(assert(f.h.byName(name, root), name)) end
local function size(f, width, height)
	f.h.setViewport(width, height)
	f.host.Size = f.h.sandbox.UDim2.fromOffset(width, height)
	f.h.settle(0.3)
end
local function visible(node, root)
	while node and node ~= root do if node.Visible == false then return false end; node = node.Parent end
	return node == root
end

for _, dimensions in ipairs({ { 320, 500 }, { 844, 280 }, { 932, 205 }, { 1194, 700 } }) do
	case("Code keeps full controls and editor width at " .. dimensions[1] .. "x" .. dimensions[2], function()
		local f = fixture(dimensions[1], dimensions[2])
		local store = f.env.require("runtime/code_store")
		local first = store.active()
		assert(store.update(first.id, "local value = 1\nreturn value"))
		local second = assert(store.create("A second script with a long name.lua", "return 2", { select = true }))
		assert(store.select(first.id))
		local panel = f.env.require("ui/panels/code").new(f.host)
		panel.navigate("Editor"); f.h.settle(0.2)
		local editor, target = panel.views.Editor, f.env.require("ui/responsive").minTarget()
		check("mobile panes reserve the full width for source", editor.root.AbsoluteSize.X == f.host.AbsoluteSize.X)
		check("desktop tab strips are replaced", not f.h.byName("CodeDestinations", panel.root).Visible and not f.h.byName("OpenDocumentTabs", panel.root).Visible)
		for _, name in ipairs({ "CodeDestinationPicker", "MobileRunCode", "MobileCodeActions" }) do
			local button = assert(f.h.byName(name, panel.root))
			check(name .. " is visible and touch sized", visible(button, panel.root) and button.AbsoluteSize.X >= target and button.AbsoluteSize.Y >= target)
		end
		local short = dimensions[2] < f.env.require("ui/code/common").barHeight() * 4 + f.env.require("ui/theme").size.codeStatus
		check("short keyboard height has one chrome row", f.h.byName("MobileCodeDocuments", panel.root).Visible ~= short)
		check("the source keeps useful vertical space", editor.root.AbsoluteSize.Y >= dimensions[2] - (short and 80 or 132))
		click(f, "MobileCodeActions", panel.root); click(f, "Option_documents")
		click(f, "Option_" .. second.id)
		check("script switching remains reachable with the document row hidden", editor.box.Text == "return 2")
		click(f, "CodeDestinationPicker", panel.root); click(f, "Option_Files")
		check("every destination can open through the picker", store.workspace.destination == "Files" and panel.views.Files ~= nil)
		if dimensions[2] <= 280 then
			check("short Files pane leaves room for its tree", panel.views.Files.list.root.AbsoluteSize.Y > 40)
			local field = f.h.byName("WorkspaceFileSearch", panel.views.Files.root):FindFirstChildOfClass("TextBox")
			field.Text = "mobile-filter"
			click(f, "CompactFileActions", panel.views.Files.root)
			check("compact Files keeps all actions reachable", f.h.byName("Option_new") ~= nil and f.h.byName("Option_delete") ~= nil and f.h.byName("Option_refresh") ~= nil)
			f.h.press("Escape")
			check("opening the file menu keeps the query", field.Text == "mobile-filter")
		end
		panel.navigate("Editor")
		editor.box:CaptureFocus(); editor.box.CursorPosition, editor.box.SelectionStart = 5, 2
		local box, source = editor.box, editor.box.Text
		size(f, 390, 650); size(f, 844, 205)
		check("rotation keeps the mounted editor and source", panel.views.Editor.box == box and box.Text == source)
		check("rotation keeps the native selection", box.CursorPosition == 5 and box.SelectionStart == 2)
		editor.openFind(); f.h.settle(0.2)
		local find = f.h.byName("EditorFind", editor.root)
		check("mobile Find takes one row", find.Size.Y.Offset == f.env.require("ui/code/common").barHeight())
		click(f, "MobileFindOptions", editor.root)
		check("find options and dismissal remain accessible", f.h.byName("Option_previous") ~= nil and f.h.byName("Option_case") ~= nil and f.h.byName("Option_close") ~= nil)
		click(f, "Option_close")
		check("closing Find returns source space", not find.Visible)
		panel.destroy(); f.healthy(); f.close()
	end)
end

case("mobile settings keep draft fields and independent scroll positions across categories", function()
	local f = fixture(390, 700)
	local dialog = f.env.require("ui/panels/settingsdialog").open("agent")
	f.h.settle(0.2)
	local field = assert(f.h.byName("CustomInstructions", dialog.card)):FindFirstChildOfClass("TextBox")
	field.Text = "Keep this multiline\nmobile draft"
	field.CursorPosition, field.SelectionStart = 8, 3
	local scroll = f.h.byName("PaneScroll", dialog.card)
	scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, 120)
	dialog.select("general"); f.h.settle(0.1)
	scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, 35)
	dialog.select("agent"); f.h.settle(0.1)
	check("returning to a category reuses the same native field", f.h.byName("CustomInstructions", dialog.card):FindFirstChildOfClass("TextBox") == field)
	check("the draft and selection survive", field.Text == "Keep this multiline\nmobile draft" and field.CursorPosition == 8 and field.SelectionStart == 3)
	check("the category restores its own scroll", scroll.CanvasPosition.Y == 120)
	dialog.select("general"); f.h.settle(0.1)
	check("another category retains its own scroll", scroll.CanvasPosition.Y == 35)
	local config = f.env.require("runtime/config")
	config.set("agent.maxTurns", 42)
	dialog.select("agent"); f.h.settle(0.1)
	local refreshed = f.h.byName("CustomInstructions", dialog.card):FindFirstChildOfClass("TextBox")
	check("unrelated configuration changes refresh the pane and preserve its local draft", refreshed ~= field and refreshed.Text == "Keep this multiline\nmobile draft")
	dialog.select("general")
	config.set("agent.customInstructions", "Imported instructions")
	dialog.select("agent"); f.h.settle(0.1)
	local imported = f.h.byName("CustomInstructions", dialog.card):FindFirstChildOfClass("TextBox")
	check("an imported setting replaces its stale field", imported.Text == "Imported instructions")
	imported.FocusLost:Fire(false)
	check("blurring the revisited field cannot undo the import", config.get("agent.customInstructions") == "Imported instructions")
	dialog.close(); f.healthy(); f.close()
end)

case("destroying a Code root releases its responsive listener and child views", function()
	local f = fixture(390, 650)
	local panel = f.env.require("ui/panels/code").new(f.host)
	panel.navigate("Editor")
	local editor = panel.views.Editor
	panel.root:Destroy()
	f.env.require("ui/responsive").changed:fire()
	check("external destruction marks the workspace and editor dead", not panel.alive and not editor.alive)
	f.healthy(); f.close()
end)

case("mobile provider navigation keeps Add visible and exposes every provider", function()
	local f = fixture(320, 500)
	local registry = f.env.require("provider/registry")
	for i = 1, 7 do
		local record = registry.blank("custom")
		record.label, record.baseUrl, record.apiKey, record.model = "Provider " .. i, "https://fixture.invalid/v1", "fixture-key", "manual-model"
		record.models = { record.model }; assert(registry.save(record))
	end
	local panel = f.env.require("ui/panels/providers").new(f.host)
	local add = assert(f.h.byName("MobileAddProvider", panel.root))
	check("Add is outside the scrolling provider list", visible(add, panel.root) and add.Parent.Name == "MobileProviderNavigation")
	click(f, "ProviderPicker", panel.root)
	local last = registry.list()[7]
	click(f, "Option_" .. last.id)
	check("the last provider opens directly", f.h.byName("ProviderTitle", panel.root).Text == last.label)
	local detailPadding = panel.scroll.instance:FindFirstChildOfClass("UIPadding")
	check("the detail uses compact outer padding", detailPadding.PaddingLeft.Offset == f.env.require("ui/theme").space.sm)
	panel.root:Destroy(); f.healthy(); f.close()
end)

suite.finish()
