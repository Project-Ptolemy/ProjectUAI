-- Compact Code inspectors preserve results, fields and capture controls.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
io.stdout:setvbuf("no")
local F = require("coding_fixture")
local suite = F.suite("Mobile inspectors")
local case, check = suite.case, suite.check
local function ui(width, height, desktop)
	local f = F.ui(width, height)
	local uis = f.h.services.UserInputService
	uis.TouchEnabled, uis.MouseEnabled = not desktop, desktop == true
	f.env.require("ui/responsive").init(f.env.root)
	f.env.require("ui/theme").rebuild()
	return f
end
local function settle(f, root)
	root:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("GuiObject") then node:GetPropertyChangedSignal("AbsoluteSize"):Fire() end
	end
	f.h.sched.advance(0.2)
end
local function find(f, root, name) return assert(f.h.byName(name, root), name) end
local function shown(node)
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return true
end
local function listFits(f, node, pane, target)
	local scroll = pane.surfaceScroll
	local content = assert(scroll:FindFirstChild("SurfaceContent"))
	local height = scroll.AbsoluteSize.Y
	local top = node.AbsolutePosition.Y - content.AbsolutePosition.Y
	local bottom = top + node.AbsoluteSize.Y
	local maximum = math.max(0, scroll.CanvasSize.Y.Offset - height)
	local position = math.max(0, math.min(top, maximum))
	scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, position)
	check(node.Name .. " retains a useful viewport", node.AbsoluteSize.Y >= target)
	check(node.Name .. " remains inside its complete scroll canvas", bottom <= scroll.CanvasSize.Y.Offset + 1)
	check(node.Name .. " can be reached through the normal surface scroll", math.min(height, bottom - position) - math.max(0, top - position) >= target)
	check("only overflowing surfaces enable scrolling", scroll.ScrollingEnabled == (maximum > 0))
end
local function tab(f, root, label)
	for _, item in ipairs(root:GetChildren()) do
		local text = item:FindFirstChild("TabLabel", true)
		if text and text.Text == label then f.h.click(item:FindFirstChild("TabButton")); return end
	end
	error("missing tab " .. label)
end
local function action(f, root, label)
	for _, button in ipairs(root:GetDescendants()) do
		if button:IsA("TextButton") and f.h.textOf(button) == label then f.h.click(button); return end
	end
	error("missing action " .. label)
end

for _, size in ipairs({ { 320, 100 }, { 480, 200 }, { 844, 180 } }) do
	case("Explorer remains usable at " .. size[1] .. "x" .. size[2], function()
		local f = ui(size[1], size[2])
		local explorer, refs = f.env.require("runtime/explorer"), f.env.require("runtime/instance_refs")
		local part = f.h.Instance.new("Part", f.h.workspace); part.Name = "Mobile inspector object"
		local pane = f.env.require("ui/code/explorer").new(f.host, function() end)
		settle(f, pane.root)
		local target = f.env.require("ui/responsive").minTarget()
		listFits(f, pane.list.root, pane, target)
		check("the hierarchy retains useful width beside a fitted inspector", pane.list.root.AbsoluteSize.X >= 120 and pane.list.root.AbsoluteSize.X <= f.host.AbsoluteSize.X)
		local search = find(f, pane.root, "ExplorerSearch"):FindFirstChildOfClass("TextBox")
		search.Text, search.CursorPosition, search.SelectionStart = "Mobile", 5, 2
		local actions = find(f, pane.root, "ExplorerActions")
		check("the normal hierarchy actions stay reachable", shown(actions) and actions.AbsoluteSize.Y >= target)
		action(f, pane.root, "Refresh")
		check("the normal refresh retains the native search draft", search.Text == "Mobile" and search.CursorPosition == 5 and search.SelectionStart == 2)
		f.h.click(actions)
		check("hierarchy search options remain available", f.h.byName("Option_search") ~= nil and f.h.byName("Option_pick") ~= nil)
		f.env.require("ui/overlay").closeAll(); f.h.sched.advance(0.2)
		assert(explorer.select({ refs.id(part) })); settle(f, pane.root)
		listFits(f, find(f, pane.root, "InstanceProperties"), pane, target)
		local property = find(f, pane.root, "PropertySearch"):FindFirstChildOfClass("TextBox")
		property.Text, property.CursorPosition, property.SelectionStart = "Name", 4, 2
		local sections = find(f, pane.root, "InspectorSections")
		check("the normal inspector section strip stays visible", shown(sections))
		tab(f, sections, "Tags"); f.h.sched.advance(0.2)
		check("section tabs update the live inspector", explorer.view.section == "tags" and explorer.view.detail)
		f.host.Size = f.h.dt.UDim2.fromOffset(size[1], 600); settle(f, pane.root)
		check("restoring height keeps the property field and selection", find(f, pane.root, "PropertySearch"):FindFirstChildOfClass("TextBox") == property
			and property.Text == "Name" and property.CursorPosition == 4 and property.SelectionStart == 2)
		check("the same normal inspector sections remain mounted", find(f, pane.root, "InspectorSections") == sections and sections.Visible)
		check("restoring height removes unnecessary outer scrolling", not pane.surfaceScroll.ScrollingEnabled and pane.surfaceScroll.CanvasPosition.Y == 0)
		check("no alternate inspector chrome is built", f.h.byName("CompactInspectorActions", pane.root) == nil)
		pane.destroy(); f.healthy(); f.close()
	end)
end

for _, size in ipairs({ { 320, 100 }, { 480, 200 }, { 844, 180 } }) do
	case("Remotes retain capture controls and inspection at " .. size[1] .. "x" .. size[2], function()
		local f = ui(size[1], size[2])
		local refs, capture = f.env.require("runtime/instance_refs"), f.env.require("runtime/remote_capture")
		local records, values = f.env.require("runtime/remote_store"), f.env.require("runtime/values")
		local remote = f.h.Instance.new("RemoteEvent", f.h.workspace); remote.Name = "MobileCapture"
		local id = refs.id(remote)
		assert(capture.start({ mode = "incoming", ids = { id }, persistent = true }))
		local token = records.begin({ remoteId = id, name = remote.Name, className = remote.ClassName,
			method = "OnClientEvent", direction = "incoming", origin = "server", outcome = "received", sessionId = "fixture" }, values.pack("hello"))
		local pane = f.env.require("ui/code/remotes").new(f.host, function() end)
		settle(f, pane.root)
		local target = f.env.require("ui/responsive").minTarget()
		listFits(f, pane.list.root, pane, target)
		check("calls retain useful width beside fitted details", pane.list.root.AbsoluteSize.X >= 120 and pane.list.root.AbsoluteSize.X <= f.host.AbsoluteSize.X)
		local search = find(f, pane.root, "RemoteSearch"):FindFirstChildOfClass("TextBox")
		search.Text, search.CursorPosition, search.SelectionStart = "Mobile", 5, 2
		local stop = find(f, pane.root, "StopRemoteCapture")
		check("active capture retains the normal Stop target", shown(stop) and stop.AbsoluteSize.Y >= target)
		local actions = find(f, pane.root, "RemoteActions")
		f.h.click(actions)
		check("the normal capture menu retains coverage and traffic rules", f.h.byName("Option_coverage") ~= nil and f.h.byName("Option_rules") ~= nil)
		f.env.require("ui/overlay").closeAll(); f.h.sched.advance(0.2)
		f.h.click(find(f, pane.root, "StartRemoteCapture")); settle(f, pane.root)
		check("the normal capture action pauses recording", capture.status == "paused")
		f.h.click(find(f, pane.root, "StartRemoteCapture")); settle(f, pane.root)
		check("the same action resumes recording", capture.status == "running")
		local listTabs = find(f, pane.root, "RemoteListTabs")
		tab(f, listTabs, "Remotes"); settle(f, pane.root)
		check("normal tabs switch to remote browsing", capture.view.listMode == "remotes")
		tab(f, listTabs, "Calls"); settle(f, pane.root)
		check("normal tabs return to retained calls", capture.view.listMode == "calls")
		f.h.click(find(f, pane.root, "FilterRemoteCalls"))
		check("the normal filter control opens the retained-call form", #f.env.require("ui/overlay").open == 1)
		f.env.require("ui/overlay").closeAll(); f.h.sched.advance(0.2)
		local selected
		for index, item in ipairs(pane.list.items) do if item.id == token.id then selected = index end end
		assert(selected, "captured call remains listed"); pane.list.selected = selected; pane.list.activate(); settle(f, pane.root)
		listFits(f, find(f, pane.root, "RemoteValues"), pane, target)
		check("inspecting a call retains the same Stop action", shown(stop) and find(f, pane.root, "StopRemoteCapture") == stop)
		local sections = find(f, pane.root, "RemoteDetailTabs")
		check("detail sections use their normal tab strip", shown(sections))
		tab(f, sections, "Results"); f.h.sched.advance(0.2)
		check("section changes target the retained call", capture.view.section == "results" and capture.view.record.id == token.id)
		f.h.click(stop); settle(f, pane.root)
		check("the direct Stop actually ends capture", capture.status == "stopped")
		f.host.Size = f.h.dt.UDim2.fromOffset(size[1], 650); settle(f, pane.root)
		check("restoring height keeps the search field and selection", find(f, pane.root, "RemoteSearch"):FindFirstChildOfClass("TextBox") == search
			and search.Text == "Mobile" and search.CursorPosition == 5 and search.SelectionStart == 2)
		check("normal capture chrome stays mounted", find(f, pane.root, "CaptureControls").Visible and find(f, pane.root, "RemoteDetailTabs") == sections)
		check("restoring height removes unnecessary outer scrolling", not pane.surfaceScroll.ScrollingEnabled and pane.surfaceScroll.CanvasPosition.Y == 0)
		check("no alternate capture chrome is built", f.h.byName("CompactRemoteActions", pane.root) == nil)
		pane.destroy(); f.healthy(); f.close()
	end)
end

case("desktop inspectors keep their full chrome", function()
	local f = ui(900, 650, true)
	local explorer = f.env.require("ui/code/explorer").new(f.host, function() end)
	check("desktop Explorer keeps its section tabs", find(f, explorer.root, "InspectorSections").Visible and f.h.byName("CompactExplorerActions", explorer.root) == nil)
	explorer.destroy()
	local remotes = f.env.require("ui/code/remotes").new(f.host, function() end)
	check("desktop Remotes keeps capture controls", find(f, remotes.root, "CaptureControls").Visible and f.h.byName("CompactRemoteActions", remotes.root) == nil)
	remotes.destroy(); f.healthy(); f.close()
end)

suite.finish()
