-- Short mobile Code panes retain readable results and explicit review actions.
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
		check("outer Code chrome still leaves a full history row", view.list.root.AbsoluteSize.Y >= 58)
		check("compact options replace fixed search and tabs", h.byName("MobileHistoryOptions", view.root).Visible and not h.byName("HistoryFilters", view.root).Visible)
		choose(f, h.byName("MobileHistoryOptions", view.root), "search")
		local overlay = env.require("ui/overlay"); local prompt = overlay.open[#overlay.open]
		h.byName("PromptField", prompt.card):FindFirstChildWhichIsA("TextBox").Text = "Stable"
		for _, button in ipairs(prompt.footer:GetChildren()) do if button:IsA("TextButton") and h.textOf(button) == "Search" then h.click(button); break end end
		check("search still filters from its compact action", #view.list.items == 1 and view.list.items[1].id == saved.id)
		choose(f, h.byName("MobileHistoryOptions", view.root), "filter:versions")
		activate(view.list, saved.id); settle(f, panel.root)
		local diff = h.byName("DiffLines", view.root)
		check("diff has at least two readable lines", diff.AbsoluteSize.Y >= env.require("ui/theme").text.mono.height * 2)
		choose(f, h.byName("MobileHistoryReviewOptions", view.root), "next")
		choose(f, h.byName("MobileHistoryReviewOptions", view.root), "section:source"); settle(f, panel.root)
		local source = h.byName("HistorySourcePreview", view.root)
		local box = source:FindFirstChild("PreviewText"):FindFirstChildWhichIsA("TextBox")
		check("saved source remains exact and readable", box.Text == saved.source and source.AbsoluteSize.Y >= 44)
		f.host.Size = h.sandbox.UDim2.fromOffset(320, 660); settle(f, panel.root)
		check("rotation keeps the native source preview mounted", box.Parent ~= nil and h.byName("HistorySourcePreview", view.root) == source)
		check("tall layout restores inline review sections", h.byName("HistoryReviewTabs", view.root).Visible)
		f.host.Size = h.sandbox.UDim2.fromOffset(740, 200); settle(f, panel.root)
		check("returning to short space keeps the same preview", h.byName("HistorySourcePreview", view.root) == source and source.AbsoluteSize.Y >= 44)
		h.click(h.byName("RestoreSourceVersion", view.root))
		check("restore still targets the reviewed revision", doc.source == saved.source)
		h.click(h.byName("BackToHistory", view.root)); settle(f, panel.root)
		check("Back returns to a usable filtered timeline", h.byName("HistoryTimeline", view.root).Visible and view.list.root.AbsoluteSize.Y >= 58)
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
	check("short field review removes the cramped separate list", not view.fields.root.Visible)
	check("both value panes have readable space", h.byName("BeforeValue", view.root).AbsoluteSize.Y >= 44 and h.byName("AfterValue", view.root).AbsoluteSize.Y >= 44)
	choose(f, h.byName("MobileHistoryReviewOptions", view.root), "field:2")
	check("another field remains selectable", h.byName("BeforeValue", view.root):FindFirstChild("PreviewText"):FindFirstChildWhichIsA("TextBox").Text == "false")
	part.Transparency = 0.8; h.click(h.byName("UndoGameFields", view.root)); settle(f, panel.root)
	check("external changes remain protected and the notice is accessible", part.Transparency == 0.8 and h.textOf(h.byName("MobileHistoryReviewOptions", view.root)) == "Review notice")
	choose(f, h.byName("MobileHistoryReviewOptions", view.root), "details")
	local overlay = env.require("ui/overlay"); check("entry details open explicitly", #overlay.open == 1); overlay.open[1].close()
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
