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
local function listFits(node, host, target)
	check(node.Name .. " retains a useful viewport", node.AbsoluteSize.Y >= target)
	check(node.Name .. " stays above the host edge", node.AbsolutePosition.Y + node.AbsoluteSize.Y <= host.AbsolutePosition.Y + host.AbsoluteSize.Y + 1)
end

for _, size in ipairs({ { 320, 100 }, { 480, 200 }, { 844, 180 } }) do
	case("Explorer remains usable at " .. size[1] .. "x" .. size[2], function()
		local f = ui(size[1], size[2])
		local explorer, refs = f.env.require("runtime/explorer"), f.env.require("runtime/instance_refs")
		local part = f.h.Instance.new("Part", f.h.workspace); part.Name = "Mobile inspector object"
		local pane = f.env.require("ui/code/explorer").new(f.host, function() end)
		settle(f, pane.root)
		listFits(pane.list.root, f.host, 44)
		check("mobile hierarchy gets the available width", pane.list.root.AbsoluteSize.X == f.host.AbsoluteSize.X)
		local search = find(f, pane.root, "ExplorerSearch"):FindFirstChildOfClass("TextBox")
		search.Text, search.CursorPosition, search.SelectionStart = "Mobile", 5, 2
		local actions = find(f, pane.root, "CompactExplorerActions")
		check("short hierarchy keeps an action target beside search", shown(actions) and actions.AbsoluteSize.Y >= 44)
		f.h.click(actions)
		check("hidden hierarchy refresh remains available", f.h.byName("Option_refreshTree") ~= nil)
		f.env.require("ui/overlay").closeAll(); f.h.sched.advance(0.2)
		assert(explorer.select({ refs.id(part) })); settle(f, pane.root)
		listFits(find(f, pane.root, "InstanceProperties"), f.host, 44)
		local property = find(f, pane.root, "PropertySearch"):FindFirstChildOfClass("TextBox")
		property.Text, property.CursorPosition, property.SelectionStart = "Name", 4, 2
		f.h.click(find(f, pane.root, "CompactInspectorActions"))
		check("all inspector sections remain available", f.h.byName("Option_section:properties") and f.h.byName("Option_section:attributes") and f.h.byName("Option_section:tags"))
		f.h.click(f.h.byName("Option_section:tags")); f.h.sched.advance(0.2)
		check("compact sections use the live inspector", explorer.view.section == "tags" and explorer.view.detail)
		f.host.Size = f.h.dt.UDim2.fromOffset(size[1], 600); settle(f, pane.root)
		check("restoring height keeps the property field and selection", find(f, pane.root, "PropertySearch"):FindFirstChildOfClass("TextBox") == property
			and property.Text == "Name" and property.CursorPosition == 4 and property.SelectionStart == 2)
		check("normal inspector sections return", find(f, pane.root, "InspectorSections").Visible and not find(f, pane.root, "CompactInspectorActions").Visible)
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
		listFits(pane.list.root, f.host, 44)
		check("mobile calls get the available width", pane.list.root.AbsoluteSize.X == f.host.AbsoluteSize.X)
		local search = find(f, pane.root, "RemoteSearch"):FindFirstChildOfClass("TextBox")
		search.Text, search.CursorPosition, search.SelectionStart = "Mobile", 5, 2
		local stop = find(f, pane.root, "CompactStopRemoteCapture")
		check("active capture retains a direct Stop target", shown(stop) and stop.AbsoluteSize.Y >= 44)
		local actions = find(f, pane.root, "CompactRemoteActions")
		f.h.click(actions)
		check("compact capture preserves browsing and filter actions", f.h.byName("Option_remotes") and f.h.byName("Option_calls") and f.h.byName("Option_viewFilter") and f.h.byName("Option_pauseResume"))
		f.env.require("ui/overlay").closeAll(); f.h.sched.advance(0.2)
		local selected
		for index, item in ipairs(pane.list.items) do if item.id == token.id then selected = index end end
		assert(selected, "captured call remains listed"); pane.list.selected = selected; pane.list.activate(); settle(f, pane.root)
		listFits(find(f, pane.root, "RemoteValues"), f.host, 44)
		local detailStop = find(f, pane.root, "CompactDetailStopRemoteCapture")
		check("inspecting a call retains Stop", shown(detailStop) and detailStop.AbsoluteSize.Y >= 44)
		f.h.click(find(f, pane.root, "CompactRemoteDetailActions"))
		check("detail sections remain reachable", f.h.byName("Option_section:arguments") and f.h.byName("Option_section:results") and f.h.byName("Option_section:caller"))
		f.h.click(f.h.byName("Option_section:results")); f.h.sched.advance(0.2)
		check("section changes target the retained call", capture.view.section == "results" and capture.view.record.id == token.id)
		f.h.click(detailStop); settle(f, pane.root)
		check("the direct Stop actually ends capture", capture.status == "stopped" and not detailStop.Visible)
		f.host.Size = f.h.dt.UDim2.fromOffset(size[1], 650); settle(f, pane.root)
		check("restoring height keeps the search field and selection", find(f, pane.root, "RemoteSearch"):FindFirstChildOfClass("TextBox") == search
			and search.Text == "Mobile" and search.CursorPosition == 5 and search.SelectionStart == 2)
		check("normal capture chrome returns", find(f, pane.root, "CaptureControls").Visible and find(f, pane.root, "RemoteDetailTabs").Visible)
		pane.destroy(); f.healthy(); f.close()
	end)
end

case("desktop inspectors keep their full chrome", function()
	local f = ui(900, 650, true)
	local explorer = f.env.require("ui/code/explorer").new(f.host, function() end)
	check("desktop Explorer keeps its section tabs", find(f, explorer.root, "InspectorSections").Visible and not find(f, explorer.root, "CompactExplorerActions").Visible)
	explorer.destroy()
	local remotes = f.env.require("ui/code/remotes").new(f.host, function() end)
	check("desktop Remotes keeps capture controls", find(f, remotes.root, "CaptureControls").Visible and not find(f, remotes.root, "CompactRemoteActions").Visible)
	remotes.destroy(); f.healthy(); f.close()
end)

suite.finish()
