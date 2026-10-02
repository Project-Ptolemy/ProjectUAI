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
	f.env.require("ui/theme").rebuild()
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
local function tab(f, root, label)
	for _, item in ipairs(root:GetChildren()) do
		local text = item:FindFirstChild("TabLabel", true)
		if text and text.Text:find(label, 1, true) then f.h.click(item:FindFirstChild("TabButton")); return end
	end
	error("missing tab " .. label)
end

for _, dimensions in ipairs({ { 320, 100 }, { 844, 100 }, { 320, 500 }, { 844, 280 }, { 932, 205 }, { 1194, 700 } }) do
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
		check("source retains useful space beside any docked panes", editor.root.AbsoluteSize.X >= 120 and editor.root.AbsoluteSize.X <= f.host.AbsoluteSize.X)
		check("the desktop destination and document tab strips remain visible", f.h.byName("CodeDestinations", panel.root).Visible and f.h.byName("OpenDocumentTabs", panel.root).Visible)
		for _, name in ipairs({ "RunCode", "CodeActions" }) do
			local button = assert(f.h.byName(name, panel.root))
			check(name .. " is visible at the compact control size", visible(button, panel.root) and button.AbsoluteSize.X >= target and button.AbsoluteSize.Y >= target)
		end
		check("no alternate mobile navigation is built", f.h.byName("MobileCodeNavigation", panel.root) == nil and f.h.byName("CodeDestinationPicker", panel.root) == nil)
		check("the source keeps useful vertical space", editor.root.AbsoluteSize.Y >= math.max(target * 3, dimensions[2] - 100))
		if dimensions[2] == 100 then
			local scroll = panel.surfaceScroll
			check("the full original workspace scrolls in keyboard-height space", scroll.ScrollingEnabled and scroll.CanvasSize.Y.Offset > scroll.AbsoluteSize.Y)
			local bottom = scroll.CanvasSize.Y.Offset - scroll.AbsoluteSize.Y
			scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, bottom)
			check("the workspace scroll can reach the lower editor region", scroll.CanvasPosition.Y == bottom)
		end
		tab(f, f.h.byName("OpenDocumentTabs", panel.root), second.name)
		check("the normal document tab selects exact source", editor.box.Text == "return 2")
		tab(f, f.h.byName("CodeDestinations", panel.root), "Files")
		check("destinations open through their normal tabs", store.workspace.destination == "Files" and panel.views.Files ~= nil)
		if dimensions[2] <= 280 then
			check("short Files pane leaves room for its tree", panel.views.Files.list.root.AbsoluteSize.Y > 40)
			local field = f.h.byName("WorkspaceFileSearch", panel.views.Files.root):FindFirstChildOfClass("TextBox")
			field.Text = "mobile-filter"
			check("Files keeps the desktop actions mounted", f.h.byName("NewWorkspaceFile", panel.views.Files.root) ~= nil
				and f.h.byName("DeleteWorkspaceEntry", panel.views.Files.root) ~= nil and f.h.byName("RefreshWorkspaceFiles", panel.views.Files.root) ~= nil)
			click(f, "RefreshWorkspaceFiles", panel.views.Files.root)
			check("refreshing files keeps the query", field.Text == "mobile-filter")
		end
		panel.navigate("Editor")
		editor.box:CaptureFocus(); editor.box.CursorPosition, editor.box.SelectionStart = 5, 2
		local box, source = editor.box, editor.box.Text
		size(f, 390, 650); size(f, 844, 205)
		check("rotation keeps the mounted editor and source", panel.views.Editor.box == box and box.Text == source)
		check("rotation keeps the native selection", box.CursorPosition == 5 and box.SelectionStart == 2)
		editor.openFind(); f.h.settle(0.2)
		local find = f.h.byName("EditorFind", editor.root)
		check("Find retains the desktop two-row composition", find.Size.Y.Offset == f.env.require("ui/code/common").barHeight() * 2)
		for _, name in ipairs({ "FindPrevious", "FindNext", "FindCaseSensitive", "FindWholeWord", "CloseFind" }) do
			check(name .. " stays reachable", visible(assert(f.h.byName(name, editor.root)), editor.root))
		end
		click(f, "CloseFind", editor.root)
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

case("the shared provider strip exposes Add and every provider", function()
	local f = fixture(300, 500)
	local registry = f.env.require("provider/registry")
	for i = 1, 7 do
		local record = registry.blank("custom")
		record.label, record.baseUrl, record.apiKey, record.model = "Provider " .. i, "https://fixture.invalid/v1", "fixture-key", "manual-model"
		record.models = { record.model }; assert(registry.save(record))
	end
	local panel = f.env.require("ui/panels/providers").new(f.host)
	local list = assert(f.h.byName("ProviderList", panel.root))
	local add = assert(f.h.byName("AddProvider", list))
	check("the normal Add action remains in the scrolling strip", visible(add, panel.root) and list.ScrollingEnabled)
	check("provider navigation has no alternate mobile picker", f.h.byName("ProviderPicker", panel.root) == nil)
	local last = registry.list()[7]
	click(f, "Provider_" .. last.id, panel.root)
	check("the last provider opens directly", f.h.byName("ProviderTitle", panel.root).Text == last.label)
	local detailPadding = panel.scroll.instance:FindFirstChildOfClass("UIPadding")
	check("the detail uses the same scaled desktop padding", detailPadding.PaddingLeft.Offset == f.env.require("ui/theme").space.lg)
	panel.root:Destroy(); f.healthy(); f.close()
end)

suite.finish()
