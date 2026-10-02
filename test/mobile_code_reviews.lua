-- Small Code panes retain the same review controls and guards as desktop.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Mobile Code reviews")
local case, check = suite.case, suite.check
local function ui(scale)
	local f = F.ui(740, 200)
	local input = f.h.services.UserInputService
	input.TouchEnabled, input.MouseEnabled, input.KeyboardEnabled = true, false, false
	f.env.require("runtime/config").set("ui.fontScale", scale or 1)
	f.env.require("ui/responsive").init(f.env.root)
	f.env.require("ui/theme").rebuild()
	return f
end
local function settle(f, root)
	f.h.sched.advance(0.1)
	root:GetPropertyChangedSignal("AbsoluteSize"):Fire()
	for _, node in ipairs(root:GetDescendants()) do if node:IsA("GuiObject") then node:GetPropertyChangedSignal("AbsoluteSize"):Fire() end end
	f.h.sched.advance(0.1)
end
local function activate(list, id)
	for index, item in ipairs(list.items) do if item.id == id then list.selected = index; list.activate(); return end end
	error("missing history row")
end
local function tab(f, root, label)
	for _, item in ipairs(root:GetChildren()) do
		local text = item:FindFirstChild("TabLabel", true)
		if text and text.Text:find(label, 1, true) then f.h.click(item:FindFirstChild("TabButton")); return end
	end
	error("missing tab " .. label)
end
local function reveal(f, panel, node)
	-- The mock does not subtract CanvasPosition from AbsolutePosition, so account
	-- for each inner canvas explicitly while checking the outer scrolling region.
	local ancestor, shifted = node.Parent, 0
	while ancestor and ancestor ~= panel.root do
		if ancestor.Name == "SurfaceScroll" then
			local content = assert(ancestor:FindFirstChild("SurfaceContent"))
			local height = ancestor.AbsoluteSize.Y
			local top = node.AbsolutePosition.Y - content.AbsolutePosition.Y - shifted
			local maximum = math.max(0, ancestor.CanvasSize.Y.Offset - height)
			local position = math.max(0, math.min(top, maximum))
			ancestor.CanvasPosition = f.h.sandbox.Vector2.new(0, position)
			check(node.Name .. " remains reachable through its surface canvas", math.min(height, top + node.AbsoluteSize.Y - position) - math.max(0, top - position) > 0)
			shifted = shifted + position
		end
		ancestor = ancestor.Parent
	end
end
local function choose(f, button, wanted)
	local overlay = f.env.require("ui/overlay")
	local original, props, opened = overlay.menu
	overlay.menu = function(spec) props = spec; opened = original(spec); return opened end
	f.h.click(button); overlay.menu = original
	check("review menu opens", props and opened and not opened.closed)
	for _, option in ipairs(props.options) do
		if option.value == wanted then opened.close(); props.onSelect(wanted, option); return end
	end
	error("missing menu action " .. wanted)
end

for _, scale in ipairs({ 1, 1.4 }) do
	case("short source history remains readable at text scale " .. scale, function()
		local f = ui(scale); local h, env = f.h, f.env
		local store = env.require("runtime/code_store"); local doc = store.active()
		assert(store.update(doc.id, "return 'saved'")); local saved = assert(store.saveVersion(doc.id, "Stable version"))
		assert(store.update(doc.id, "return 'current'"))
		local panel = env.require("ui/panels/code").new(f.host); panel.navigate("History"); settle(f, panel.root)
		local view = panel.views.History
		check("short review space scrolls the full desktop composition", panel.surfaceScroll.ScrollingEnabled or view.surfaceScroll.ScrollingEnabled)
		check("outer Code chrome still leaves a full history row", view.list.root.AbsoluteSize.Y >= view.list.rowHeight)
		local filters = h.byName("HistoryFilters", view.root)
		local search = h.byName("HistorySearch", view.root):FindFirstChildWhichIsA("TextBox")
		check("the original search field and filter tabs stay visible", search.Parent.Visible and filters.Visible and h.byName("MobileHistoryOptions", view.root) == nil)
		search.Text = "Stable"; settle(f, panel.root)
		check("the normal search field filters exact versions", #view.list.items == 1 and view.list.items[1].id == saved.id)
		tab(f, filters, "Versions")
		activate(view.list, saved.id); settle(f, panel.root)
		local diff = h.byName("DiffLines", view.root)
		check("diff has at least two readable lines", diff.AbsoluteSize.Y >= env.require("ui/theme").text.mono.height * 2)
		reveal(f, panel, diff)
		h.click(h.byName("NextSourceChange", view.root))
		local sections = h.byName("HistoryReviewTabs", view.root)
		tab(f, sections, "Saved source"); settle(f, panel.root)
		local source = h.byName("HistorySourcePreview", view.root)
		local box = source:FindFirstChild("PreviewText"):FindFirstChildWhichIsA("TextBox")
		check("saved source remains exact and readable", box.Text == saved.source and source.AbsoluteSize.Y >= env.require("ui/theme").text.mono.height * 2)
		f.host.Size = h.sandbox.UDim2.fromOffset(320, 660); settle(f, panel.root)
		check("rotation keeps the native source preview mounted", box.Parent ~= nil and h.byName("HistorySourcePreview", view.root) == source)
		check("rotation retains the same inline review sections", h.byName("HistoryReviewTabs", view.root) == sections and sections.Visible)
		f.host.Size = h.sandbox.UDim2.fromOffset(740, 200); settle(f, panel.root)
		check("returning to short space keeps the same preview", h.byName("HistorySourcePreview", view.root) == source and source.AbsoluteSize.Y >= env.require("ui/theme").text.mono.height * 2)
		reveal(f, panel, source)
		h.click(h.byName("RestoreSourceVersion", view.root))
		check("restore still targets the reviewed revision", doc.source == saved.source)
		f.host.Size = h.sandbox.UDim2.fromOffset(320, 660); settle(f, panel.root)
		h.click(h.byName("BackToHistory", view.root)); settle(f, panel.root)
		check("Back returns to a usable filtered timeline", h.byName("HistoryTimeline", view.root).Visible and not h.byName("HistoryReview", view.root).Visible and view.list.root.AbsoluteSize.Y >= view.list.rowHeight)
		check("the native history query survives review and rotation", h.byName("HistorySearch", view.root):FindFirstChildWhichIsA("TextBox") == search and search.Text == "Stable")
		f.healthy(); panel.destroy(); f.close()
	end)
end

case("short game review exposes every field and keeps conflict protection", function()
	local f = ui(); local h, env = f.h, f.env
	local part = h.Instance.new("Part", h.workspace); part.Name, part.Transparency, part.Anchored = "Mobile marker", 0, false
	local refs, values = env.require("runtime/instance_refs"), env.require("runtime/values")
	local result = env.require("runtime/instance_edits").apply({
		{ instanceId = refs.id(part), kind = "property", key = "Transparency", expected = values.node(0), value = values.node(0.5) },
		{ instanceId = refs.id(part), kind = "property", key = "Anchored", expected = values.node(false), value = values.node(true) },
	}, { origin = "Explorer" }); assert(result.ok)
	local panel = env.require("ui/panels/code").new(f.host); panel.navigate("Game changes"); settle(f, panel.root)
	local view = panel.views["Game changes"]; activate(view.list, result.batchId); settle(f, panel.root)
	reveal(f, panel, view.fields.root)
	check("the original field list stays visible and selectable", view.fields.root.Visible and view.fields.root.AbsoluteSize.Y >= view.fields.rowHeight)
	local line = env.require("ui/theme").text.mono.height
	check("both value panes have readable space", h.byName("BeforeValue", view.root).AbsoluteSize.Y >= line * 2 and h.byName("AfterValue", view.root).AbsoluteSize.Y >= line * 2)
	activate(view.fields, "2")
	reveal(f, panel, h.byName("BeforeValue", view.root))
	check("another field remains selectable", h.byName("BeforeValue", view.root):FindFirstChild("PreviewText"):FindFirstChildWhichIsA("TextBox").Text == "false")
	part.Transparency = 0.8; h.click(h.byName("UndoGameFields", view.root)); settle(f, panel.root)
	local notice = h.byName("HistoryReviewNotice", view.root)
	check("external changes remain protected and the inline notice names the conflict", part.Transparency == 0.8 and notice.Visible and notice.Text:find("Transparency", 1, true) ~= nil)
	check("both original review metadata and field list remain mounted", h.byName("HistoryReviewMetadata", view.root).Visible and view.fields.root.Visible and h.byName("MobileHistoryReviewOptions", view.root) == nil)
	f.healthy(); panel.destroy(); f.close()
end)

case("short output retains scrolling and copy actions and releases subscriptions", function()
	local f = ui(); local h, env = f.h, f.env
	local runner = env.require("tools/code_runner"); local doc = env.require("runtime/code_store").active()
	runner.runs = { { id = "mobile-run", documentId = doc.id, name = doc.name, revision = doc.revision,
		status = "succeeded", output = { "first line", "exact <output>" } } }
	local panel = env.require("ui/panels/code").new(f.host); panel.navigate("Output"); settle(f, panel.root)
	local view = panel.views.Output; local scroll = h.byName("OutputTextScroll", view.root)
	check("output has a positive reading region after both toolbar rows", scroll.AbsoluteSize.Y >= 58)
	choose(f, h.byName("OutputMore", view.root), "copy")
	check("copy preserves raw output without RichText escaping", h.sandbox.__clipboard:find("exact <output>", 1, true) ~= nil)
	local before = runner.changed:count(); scroll.CanvasPosition = h.sandbox.Vector2.new(0, 17)
	view.root:Destroy()
	check("direct destruction releases output subscription", runner.changed:count() == before - 1 and not view.alive)
	check("reading position is retained", env.require("runtime/code_store").workspace.outputY == 17)
	panel.destroy(); h.sched.advance(0.2); f.healthy(); f.close()
end)

suite.finish()
