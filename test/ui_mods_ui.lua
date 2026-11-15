-- Native mod previews and management against synthetic source modules only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("UI Mods interface")
local check, case = suite.check, suite.case
local function field(f, name, root)
	return assert(f.h.byName(name, root)):FindFirstChildOfClass("TextBox")
end
local function modal(f, name)
	local surfaces = f.env.require("ui/overlay").open
	for index = #surfaces, 1, -1 do
		if not surfaces[index].closed and (not name or surfaces[index].card.Name == name) then return surfaces[index] end
	end
end
local function click(f, name, root, seconds)
	f.h.click(assert(f.h.byName(name, root))); f.h.settle(seconds or 0.3)
end
local function spec(kind, id, body)
	local value = { version = 1, kind = kind or "visual", id = id or "fixture-mod", name = "Fixture workspace",
		description = "A portable working definition", author = "Fixture author",
		sources = { { label = "Fixture guide", url = "docs/UI_MODS.md" }, { label = "Local design notes" } } }
	if value.kind == "script" then value.source = body or "local value = 1\nreturn function() end"
	else
		value.appearance = { density = "compact", fontScale = 1.1 }
		value.panels = { { id = "overview", title = "Project overview", description = "Personal workspace", widgets = {
			{ id = "intro", type = "text", body = body or "Read the current project notes." },
			{ id = "tokens", type = "metric", label = "Session tokens", selector = "tokens" },
			{ id = "vault", type = "action", label = "Open Master Vault", action = "vault" },
		} } }
	end
	return value
end
local function record(value, revision, version)
	return { id = value.id, name = value.name, kind = value.kind, description = value.description, author = value.author,
		spec = value, revision = revision or "original", version = version or 1, updatedAt = 0, history = {},
		active = false, selected = false }
end
local function stub(f, value, overrides)
	local runtime = {
		changed = f.env.require("runtime/signal").new("mods fixture"),
		state = function() return { loaded = true, writable = true, filesystem = true, busy = false, count = value and 1 or 0 } end,
		list = function() return { items = value and { value } or {}, total = value and 1 or 0, offset = 1,
			state = { loaded = true, writable = true, filesystem = true, busy = false } } end,
		read = function() return value end,
		checkScript = function() return true, nil, { ok = true, executed = false, compilerAvailable = true } end,
		activate = function() error("The UI must not activate directly") end,
		disable = function() error("The UI must use its cleanup controller") end,
	}
	for key, replacement in pairs(overrides or {}) do runtime[key] = replacement end
	f.loaded["runtime/ui_mods"] = runtime
	return runtime
end
local function open(f, props)
	local manager = f.env.require("ui/mods")
	local view = assert(manager.open(props)); f.h.settle(0.4)
	return manager, view
end
local function workspaceFixture(f, value)
	local signal = f.env.require("runtime/signal")
	local w = { active = value, metrics = { tokens = 60, goals = "1/2 done" }, reads = 0, metricReads = 0, routes = {}, manages = 0 }
	w.mods = stub(f, value, { getActive = function() w.reads = w.reads + 1; return w.active end })
	w.runner = { changed = signal.new("runner fixture"), state = function() return { status = "running" } end }
	f.loaded["runtime/ui_mod_runner"] = w.runner
	w.session = { id = "workspace-session", modMetrics = function() w.metricReads = w.metricReads + 1; return w.metrics end,
		disableUiMods = function() error("Configure the cleanup fixture before clicking Disable") end }
	w.current = w.session
	w.sessions = { activeId = w.session.id, current = function() return w.current end,
		listChanged = signal.new("workspace sessions"), anyEvent = signal.new("workspace events"), usageChanged = signal.new("workspace usage") }
	f.loaded["agent/session"] = w.sessions
	w.app = { showUiMods = function() w.manages = w.manages + 1 end,
		show = function(action) w.routes[#w.routes + 1] = action end,
		showGoals = function() w.routes[#w.routes + 1] = "micro_goals" end,
		showCommands = function() w.routes[#w.routes + 1] = "commands" end }
	function w.open()
		w.panel = f.env.require("ui/panels/mods").new(f.host, w.app); f.h.settle(0.3)
		return w.panel
	end
	return w
end

case("default visual reviews never run metric or navigation callbacks or apply appearance", function()
	local f = F.ui(390, 700); local calls = 0
	local density = f.env.require("runtime/config").get("ui.density")
	local value = spec()
	local view = f.env.require("ui/mod_preview").render(f.host, record(value), {
		metric = function() calls = calls + 1; return 999 end,
		navigate = function() calls = calls + 1 end,
	})
	local action = assert(f.h.byName("UiModAction_vault", view.root))
	f.h.click(action); view.visual.refresh()
	check("preview callbacks remain inert", calls == 0 and not action.Active)
	check("requested appearance is visible without changing preferences", f.h.byName("UiModPreviewAppearance", view.root).Text:find("density: compact", 1, true)
		and f.env.require("runtime/config").get("ui.density") == density)
	check("preview preserves provenance", f.h.byName("UiModPreviewSources", view.root).Text:find("Fixture author", 1, true)
		and f.h.byName("UiModPreviewSources", view.root).Text:find("docs/UI_MODS.md", 1, true))
	check("preview creates no active definition", f.env.require("runtime/ui_mods").getActive() == nil)
	view.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("script reviews show complete source and only compile, including hosts without a compiler", function()
	local f = F.ui(900, 700); local compiled, executed = 0, 0
	local value = spec("script", "source-fixture", string.rep("-- complete source\n", 1000) .. "return function() end")
	local caps = f.env.require("runtime/caps")
	caps.fn.loadstring = function(source, name)
		check("compile receives the exact reviewed source", source == value.source and name == "@uai-mod/source-fixture")
		compiled = compiled + 1; return function() executed = executed + 1 end
	end
	local renderer = f.env.require("ui/mod_preview")
	local view = renderer.render(f.host, record(value))
	check("compilation does not execute its result", compiled == 1 and executed == 0 and view.check.ok and view.check.executed == false)
	check("the full source remains selectable and read-only", field(f, "UiModPreviewSource", view.root).Text == value.source
		and field(f, "UiModPreviewSource", view.root).TextEditable == false and view.reviewComplete == true)
	check("execution and cleanup scope is stated", f.h.byName("UiModPreviewScope", view.root).Text:find("executor's permissions", 1, true)
		and f.h.byName("UiModPreviewScope", view.root).Text:find("native work may remain", 1, true))
	caps.fn.loadstring = nil
	local unavailable = renderer.render(f.host, record(value))
	check("missing compilers retain source without claiming validation", not unavailable.check.ok and unavailable.check.compilerAvailable == false
		and field(f, "UiModPreviewSource", unavailable.root).Text == value.source
		and f.h.byName("UiModCompileResult", unavailable.root).Text:find("unavailable", 1, true))
	view.destroy(); unavailable.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("the live visual renderer refreshes declared metrics and routes only declared client actions", function()
	local f = F.ui(900, 700); local metricCalls, actionCalls, current = 0, 0, 60
	local renderer = f.env.require("ui/mod_preview")
	local view = renderer.renderVisual(f.host, spec(), { panelId = "overview",
		metric = function(selector) check("the declared aggregate is requested", selector == "tokens"); metricCalls = metricCalls + 1; return current end,
		navigate = function(action) check("the declared destination is routed", action == "vault"); actionCalls = actionCalls + 1 end,
	})
	check("live metrics are displayed", f.h.byName("UiModMetricValue_tokens", view.root).Text == "60" and metricCalls == 1)
	click(f, "UiModAction_vault", view.root)
	current = "120 measured tokens"; view.refresh()
	check("refresh updates the same declared widget", f.h.byName("UiModMetricValue_tokens", view.root).Text == current and metricCalls == 2 and actionCalls == 1)
	view.destroy(); view.refresh()
	check("destroyed views stop callback work", metricCalls == 2)
	local invalid = spec(); invalid.panels[1].widgets[3].action = "execute_code"
	local rejected = renderer.renderVisual(f.host, invalid, { navigate = function() actionCalls = actionCalls + 1 end })
	check("invalid visual actions render an error", f.h.byName("UiModPanelsError", rejected.root) ~= nil and f.h.byName("UiModAction_vault", rejected.root) == nil)
	rejected.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("importing and saving stages a disabled portable script while Preview only compiles", function()
	local f = F.ui(900, 720); local compiled, executed = 0, 0
	f.env.require("runtime/caps").fn.loadstring = function() compiled = compiled + 1; return function() executed = executed + 1 end end
	local runtime, document = f.env.require("runtime/ui_mods"), f.env.require("runtime/ui_mod_document")
	local manager, view = open(f)
	click(f, "UiModsImport", view.card)
	local editing = assert(modal(f, "UiModEditor"))
	local value = spec("script", "portable-script")
	field(f, "UiModJson", editing.card).Text = assert(document.format(value))
	check("typing does not persist source", f.run(function() return runtime.list() end).total == 0 and manager.hasDrafts())
	click(f, "UiModPreviewDraft", editing.card)
	check("Preview compiles full source without activating it", compiled == 1 and executed == 0 and runtime.getActive() == nil
		and field(f, "UiModPreviewSource", assert(modal(f, "UiModDraftPreview")).card).Text == value.source)
	click(f, "UiModPreviewClose", assert(modal(f, "UiModDraftPreview")).card)
	click(f, "UiModSaveDraft", editing.card, 0.5)
	local saved = assert(f.run(function() return runtime.read(value.id) end))
	check("Save retains source and attribution in a disabled definition", saved.spec.source == value.source and saved.spec.author == value.author
		and #saved.spec.sources == 2 and not saved.active and not saved.selected and runtime.getActive() == nil)
	check("Save never invokes the compiler or source", compiled == 1 and executed == 0 and not manager.hasDrafts())
	click(f, "UiModEditorClose", editing.card); view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("clipboard failure exposes complete portable JSON for manual copying", function()
	local f = F.ui(390, 700)
	local runtime, document = f.env.require("runtime/ui_mods"), f.env.require("runtime/ui_mod_document")
	local value = spec("script", "manual-export")
	assert(f.run(function() return runtime.save(value) end))
	local caps = f.env.require("runtime/caps"); caps.clipboard = true; caps.fn.clipboard = function() return false end
	local manager, view = open(f)
	click(f, "UiModExport_" .. value.id, view.card, 0.4)
	local exported = assert(modal(f, "UiModExport"))
	local text = field(f, "UiModExportJson", exported.card)
	local portable = assert(document.parse(text.Text))
	check("manual export keeps the entire definition", portable.source == value.source and portable.author == value.author and #portable.sources == 2 and not text.TextEditable)
	click(f, "UiModExportSelect", exported.card)
	check("Select all uses the complete native field", text.CursorPosition == #text.Text + 1 and text.SelectionStart == 1)
	check("export does not allocate an unfinished form", not manager.hasDrafts())
	view.close(); f.h.settle(0.3)
	check("closing the manager closes its export", exported.closed)
	f.healthy(); f.close()
end)

case("conflicted saves retain the form until an explicit review adopts the new revision", function()
	local f = F.ui(900, 720); local saves, reads, revisions = 0, 0, {}
	local initial = record(spec("visual", "conflict", "Original"))
	local latest = record(spec("visual", "conflict", "External edit"), "external", 2)
	stub(f, initial, {
		read = function(_, options) check("current reads explicitly refresh storage", options.refresh == true); reads = reads + 1; return reads == 1 and initial or latest end,
		save = function(value, revision)
			saves = saves + 1; revisions[saves] = revision
			if saves == 1 then return nil, "The saved definition changed" end
			return record(value, "saved", 3)
		end,
	})
	local manager, view = open(f)
	click(f, "UiModEdit_conflict", view.card)
	local editing = assert(modal(f, "UiModEditor"))
	local draft = spec("visual", "conflict", "My unfinished change")
	local json = assert(f.env.require("runtime/ui_mod_document").format(draft))
	field(f, "UiModJson", editing.card).Text = json
	click(f, "UiModSaveDraft", editing.card); click(f, "UiModSaveDraft", editing.card)
	check("a failed save is not repeated", saves == 1 and field(f, "UiModJson", editing.card).Text == json and manager.hasDrafts())
	click(f, "UiModReadCurrent", editing.card)
	local reviewing = assert(modal(f, "UiModCurrentReview"))
	check("the current file is visible before a choice", field(f, "UiModCurrentJson", reviewing.card).Text:find("External edit", 1, true) and saves == 1)
	click(f, "UiModKeepDraft", reviewing.card)
	check("adopting a revision does not save or replace the draft", saves == 1 and field(f, "UiModJson", editing.card).Text == json)
	click(f, "UiModSaveDraft", editing.card)
	check("the next explicit Save uses the exact reviewed revision", saves == 2 and revisions[1] == "original" and revisions[2] == "external" and not manager.hasDrafts())
	view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("a closed pending import retains its identity and recovers without duplicate creation", function()
	local f = F.ui(430, 650); local imports, saves, savedRevision = 0, 0, nil
	local value = spec("script", "pending-import")
	stub(f, nil, {
		import = function() imports = imports + 1; f.h.sched.wait(1); return nil, "Unconfirmed write", { uncertain = true, id = value.id } end,
		read = function(id) check("recovery reads the original portable identity", id == value.id); return record(value, "written", 1) end,
		save = function(saved, revision) saves = saves + 1; savedRevision = revision; return record(saved, "confirmed", 2) end,
	})
	local manager, view = open(f)
	click(f, "UiModsImport", view.card)
	local editing = assert(modal(f, "UiModEditor"))
	local json = assert(f.env.require("runtime/ui_mod_document").format(value)); field(f, "UiModJson", editing.card).Text = json
	click(f, "UiModSaveDraft", editing.card, 0.1)
	editing.close(); f.h.settle(0.2)
	click(f, "UiModsResume", view.card, 0.1)
	check("pending forms cannot reopen or duplicate their write", manager.hasDrafts() and imports == 1 and modal(f, "UiModEditor") == nil)
	f.h.settle(1)
	click(f, "UiModsResume", view.card)
	editing = assert(modal(f, "UiModEditor"))
	check("the uncertain result retains the original complete JSON", field(f, "UiModJson", editing.card).Text == json)
	click(f, "UiModSaveDraft", editing.card)
	check("an uncertain create cannot run again", imports == 1 and saves == 0)
	click(f, "UiModReadCurrent", editing.card); click(f, "UiModKeepDraft", assert(modal(f, "UiModCurrentReview")).card)
	click(f, "UiModSaveDraft", editing.card)
	check("the recovered draft updates the reviewed identity", imports == 1 and saves == 1 and savedRevision == "written" and not manager.hasDrafts())
	view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("history exports the selected version and restores it only as an unsaved disabled definition", function()
	local f = F.ui(900, 720)
	local runtime, document = f.env.require("runtime/ui_mods"), f.env.require("runtime/ui_mod_document")
	local original = spec("visual", "history", "Version one")
	local first = assert(f.run(function() return runtime.save(original) end))
	local current = spec("visual", "history", "Version two")
	assert(f.run(function() return runtime.save(current, first.revision) end))
	local manager, view = open(f)
	click(f, "UiModRead_history", view.card)
	local details = assert(modal(f, "UiModDetails")); click(f, "UiModVersion_1", details.card)
	check("retained versions display their own full definition", assert(document.parse(field(f, "UiModDetailsJson", details.card).Text)).panels[1].widgets[1].body == "Version one"
		and not f.h.byName("UiModApplyVersion", details.card).Active)
	click(f, "UiModExportVersion", details.card)
	check("export preserves the selected version and attribution", assert(document.parse(f.h.sandbox.__clipboard)).panels[1].widgets[1].body == "Version one"
		and assert(document.parse(f.h.sandbox.__clipboard)).author == original.author)
	click(f, "UiModRestoreVersion", details.card)
	local editing = assert(modal(f, "UiModEditor"))
	check("restore does not write or apply source", manager.hasDrafts() and f.run(function() return runtime.read("history") end).version == 2 and runtime.getActive() == nil)
	click(f, "UiModSaveDraft", editing.card, 0.4)
	local restored = assert(f.run(function() return runtime.read("history") end))
	check("Save creates a disabled version with bounded retained history", restored.version == 3 and #restored.history == 2
		and restored.spec.panels[1].widgets[1].body == "Version one" and not restored.active)
	view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("Apply uses the session dispatcher once across close and reopen and reports declines and cleanup warnings", function()
	local f = F.ui(900, 720); local applies, disables, releaseApply = 0, 0, false
	local value = record(spec("script", "reviewed"), "reviewed-revision")
	stub(f, value)
	local session = {
		applyUiMod = function(id, revision)
			check("Apply passes the exact saved identity and revision", id == value.id and revision == value.revision)
			applies = applies + 1
			while not releaseApply do f.h.sched.wait(0.05) end
			return { ok = true, text = "The mod was not applied because the review was declined.", data = { applied = false } }
		end,
		disableUiMods = function()
			disables = disables + 1
			return { ok = true, text = "Disabled for this run; the cleanup choice could not be saved.", data = { persisted = false } }
		end,
	}
	local manager, view = open(f, { session = session })
	click(f, "UiModApply_reviewed", view.card, 0.1)
	view.close(); f.h.settle(0.1)
	manager, view = open(f, { session = session })
	click(f, "UiModApply_reviewed", view.card, 0.1); click(f, "UiModsDisable", view.card, 0.1)
	check("reopened managers retain pending controller ownership", applies == 1 and disables == 0)
	releaseApply = true
	f.h.settle(1)
	click(f, "UiModApply_reviewed", view.card, 1.3)
	check("explicit declines are not reported as successful application", applies == 2
		and f.h.byName("UiModsNotice", view.card).Text:find("not applied", 1, true))
	click(f, "UiModsDisable", view.card)
	check("disable uses the cleanup facade and preserves persistence warnings", disables == 1
		and f.h.byName("UiModsNotice", view.card).Text:find("could not be saved", 1, true))
	view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("bounded forms survive invalid input and must be resumed or explicitly discarded", function()
	local f = F.ui(390, 700)
	stub(f, nil)
	local manager, view = open(f)
	click(f, "UiModsImport", view.card)
	local editing = assert(modal(f, "UiModEditor"))
	local json = assert(f.env.require("runtime/ui_mod_document").format(spec("script", "retained")))
	local input = field(f, "UiModJson", editing.card); input.Text = json
	for _, invalid in ipairs({ string.char(255), "\0", "\1", string.rep("a", f.env.require("runtime/ui_mod_document").limits.json + 1) }) do
		input.Text = invalid; check("invalid replacements keep the previous bounded JSON", input.Text == json)
	end
	editing.close(); f.h.settle(0.3)
	click(f, "UiModsNewScript", view.card)
	check("one unfinished form protects its complete draft", manager.hasDrafts() and modal(f, "UiModEditor") == nil
		and f.h.byName("UiModsNotice", view.card).Text:find("unfinished", 1, true))
	click(f, "UiModsResume", view.card)
	editing = assert(modal(f, "UiModEditor")); check("Resume preserves the original form", field(f, "UiModJson", editing.card).Text == json)
	click(f, "UiModDiscardDraft", editing.card)
	local confirmation = assert(modal(f))
	check("discard presents a separate concrete confirmation", confirmation ~= editing)
	local confirming
	for _, button in ipairs(confirmation.footer:GetChildren()) do
		if button:IsA("TextButton") then
			for _, text in ipairs(button:GetDescendants()) do
				if text:IsA("TextLabel") and text.Text == "Discard draft" then confirming = button end
			end
		end
	end
	f.h.click(assert(confirming))
	f.h.settle(0.3)
	check("only explicit discard clears the reload guard", not manager.hasDrafts() and modal(f, "UiModEditor") == nil)
	view.close(); f.h.settle(0.3); f.healthy(); f.close()
end)

case("the workspace keeps full-width containers and selected tabs while routing declared destinations", function()
	local f = F.ui(390, 700)
	local value = spec()
	value.panels[2] = { id = "work", title = "Current work", widgets = {
		{ id = "goals", type = "action", label = "Open Micro-goals", action = "micro_goals" },
		{ id = "commands", type = "action", label = "Open commands", action = "commands" },
	} }
	local w = workspaceFixture(f, record(value)); w.open()
	for _, name in ipairs({ "UiModsWorkspaceActions", "UiModPanelTabs", "UiModsWorkspaceContent" }) do
		local holder = assert(f.h.byName(name, f.host))
		check("workspace containers fill the available width", holder.Size.X.Scale == 1 and holder.Size.X.Offset == 0
			and holder.AutomaticSize == f.h.sandbox.Enum.AutomaticSize.Y)
	end
	check("only the selected panel is rendered", f.h.byName("UiModPanel_overview", f.host) ~= nil and f.h.byName("UiModPanel_work", f.host) == nil)
	click(f, "UiModTab_work", f.host)
	click(f, "UiModAction_goals", f.host); click(f, "UiModAction_commands", f.host)
	w.mods.changed:fire(); f.h.settle(0.3)
	check("saved-definition refresh preserves the selected tab", f.h.byName("UiModPanel_work", f.host) ~= nil and f.h.byName("UiModPanel_overview", f.host) == nil)
	click(f, "UiModTab_overview", f.host); click(f, "UiModAction_vault", f.host); click(f, "ManageUiMods", f.host)
	check("declared destinations use the native application routes", table.concat(w.routes, ",") == "micro_goals,commands,vault" and w.manages == 1)
	w.panel.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("first-load signals and change bursts cannot recursively duplicate workspace widgets", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec()))
	w.mods.getActive = function()
		w.reads = w.reads + 1
		if w.reads == 1 then w.mods.changed:fire(); w.runner.changed:fire() end
		return w.active
	end
	w.open()
	check("initial loading finishes without recursive reads", w.reads == 2)
	check("initial loading leaves one tab, panel and widget", #f.h.allByName("UiModTab_overview", f.host) == 1
		and #f.h.allByName("UiModPanel_overview", f.host) == 1 and #f.h.allByName("UiModMetricValue_tokens", f.host) == 1)
	local before = w.reads
	w.active = record(spec("visual", "fixture-mod", "The latest saved definition"), "latest", 2)
	for _ = 1, 12 do w.mods.changed:fire(); w.runner.changed:fire() end
	check("signal bursts defer their read until the scheduled refresh", w.reads == before)
	f.h.settle(0.3)
	check("one refresh consumes the latest saved definition", w.reads == before + 1
		and f.h.byName("UiModText_intro", f.host).Text == "The latest saved definition" and #f.h.allByName("UiModPanels", f.host) == 1)
	w.panel.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("hidden workspaces defer reads and render the latest definition and metrics when shown", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec())); w.open()
	local previous = assert(f.h.byName("UiModText_intro", f.host))
	local reads, metricReads = w.reads, w.metricReads
	w.panel.setVisible(false)
	w.active = record(spec("visual", "replacement", "Updated while hidden"), "replacement", 2); w.metrics.tokens = 140
	w.mods.changed:fire(); w.runner.changed:fire(); w.sessions.usageChanged:fire(); w.sessions.listChanged:fire()
	f.h.settle(0.3)
	check("hidden updates keep existing widgets without reading", w.reads == reads and w.metricReads == metricReads
		and previous.Parent ~= nil and previous.Text ~= "Updated while hidden")
	w.panel.setVisible(true); f.h.settle(0.3)
	check("showing replaces stale widgets with the latest data", previous.Parent == nil
		and f.h.byName("UiModText_intro", f.host).Text == "Updated while hidden"
		and f.h.byName("UiModMetricValue_tokens", f.host).Text == "140")
	w.active = record(spec("visual", "replacement", string.rep("A longer project note.\n", 50)), "long-content", 3)
	w.mods.changed:fire(); f.h.settle(0.3)
	local scroll = assert(f.h.byName("UiModsWorkspace", f.host)); scroll.CanvasPosition = f.h.sandbox.Vector2.new(0, 80)
	w.mods.changed:fire(); f.h.settle(0.3)
	check("definition refresh keeps the current scroll position", scroll.CanvasPosition.Y == 80)
	w.panel.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("metric bursts refresh the existing view and follow the active conversation", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec())); w.open()
	local value = assert(f.h.byName("UiModMetricValue_tokens", f.host))
	local reads, metrics = w.reads, w.metricReads
	w.sessions.anyEvent:fire({ id = "background" }, { kind = "goals:changed" })
	w.sessions.anyEvent:fire(w.session, { kind = "message:delta" }); f.h.settle(0.1)
	check("unrelated events do not request aggregate metrics", w.metricReads == metrics)
	w.metrics.tokens = "85 (estimated)"
	for _ = 1, 12 do
		w.sessions.listChanged:fire(); w.sessions.usageChanged:fire(); w.sessions.anyEvent:fire(w.session, { kind = "goals:changed" })
	end
	check("aggregate bursts are deferred", w.metricReads == metrics)
	f.h.settle(0.3)
	check("metrics update once without rebuilding widgets", w.metricReads == metrics + 1 and w.reads == reads
		and f.h.byName("UiModMetricValue_tokens", f.host) == value and value.Text == "85 (estimated)")
	w.current = { id = "other-session", modMetrics = function() return { tokens = 240 } end }
	w.sessions.activeId = w.current.id; w.sessions.listChanged:fire(); f.h.settle(0.3)
	check("changing conversation changes the current aggregate", value.Text == "240")
	w.panel.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("destruction releases subscriptions and cancels queued refresh work", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec())); w.open()
	local reads, metrics = w.reads, w.metricReads
	w.mods.changed:fire(); w.sessions.usageChanged:fire()
	f.host:Destroy(); w.panel.destroy(); w.panel.setVisible(true)
	for _, signal in ipairs({ w.mods.changed, w.runner.changed, w.sessions.listChanged, w.sessions.anyEvent, w.sessions.usageChanged }) do
		check("workspace subscriptions are released", signal:count() == 0)
	end
	w.mods.changed:fire(); w.sessions.listChanged:fire(); f.h.settle(0.3)
	check("destroyed workspaces cannot recreate or refresh their widgets", w.reads == reads and w.metricReads == metrics
		and f.h.byName("UiModsWorkspace") == nil)
	f.healthy(); f.close()
end)

case("Disable owns one captured cleanup request and preserves warnings and contained errors", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec())); local disables, otherDisables, notices = 0, 0, {}
	local releaseDisable = false
	f.env.require("ui/overlay").toast = function(text, tone) notices[#notices + 1] = { text = text, tone = tone } end
	w.session.disableUiMods = function()
		disables = disables + 1
		while not releaseDisable do f.h.sched.wait(0.05) end
		return { ok = true, text = "Disabled for this run; the cleanup choice could not be saved.", data = { persisted = false } }
	end
	w.open()
	local button = assert(f.h.byName("DisableWorkspaceMods", f.host))
	f.h.click(button); f.h.settle(0.1)
	w.current = { id = "other-session", disableUiMods = function() otherDisables = otherDisables + 1 end }
	w.sessions.activeId = w.current.id
	f.h.click(button); f.h.settle(0.1)
	check("pending cleanup is submitted once to the original conversation", disables == 1 and otherDisables == 0 and not button.Active)
	releaseDisable = true
	f.h.settle(0.9)
	check("completion restores the control and retains persistence warnings", button.Active and #notices == 1
		and notices[1].tone == "warn" and notices[1].text:find("could not be saved", 1, true))
	w.current, w.sessions.activeId = w.session, w.session.id
	w.session.disableUiMods = function() error("synthetic cleanup failure") end
	f.h.click(button); f.h.settle(0.2)
	check("cleanup exceptions release the pending state without leaking errors", button.Active and #notices == 2
		and notices[2].tone == "warn" and notices[2].text:find("stopped unexpectedly", 1, true)
		and not notices[2].text:find("synthetic", 1, true))
	w.panel.destroy(); f.h.settle(0.2); f.healthy(); f.close()
end)

case("closing a pending Disable suppresses late interface work", function()
	local f = F.ui(900, 700)
	local w = workspaceFixture(f, record(spec())); local disables, notices = 0, 0
	local releaseDisable = false
	f.env.require("ui/overlay").toast = function() notices = notices + 1 end
	w.session.disableUiMods = function()
		disables = disables + 1
		while not releaseDisable do f.h.sched.wait(0.05) end
		return { ok = true, text = "Disabled", data = { persisted = true } }
	end
	w.open(); click(f, "DisableWorkspaceMods", f.host, 0.1)
	w.panel.destroy(); w.panel.setVisible(true); releaseDisable = true; f.h.settle(1)
	check("closed cleanup completes once without restoring or toasting destroyed UI", disables == 1 and notices == 0
		and f.h.byName("UiModsWorkspace", f.host) == nil)
	f.healthy(); f.close()
end)

case("script panels appear inside the native Mod workspace with retained controls", function()
	local f = F.ui(900, 700); local value = record(spec("script", "native-fixture"))
	local w = workspaceFixture(f, value)
	local models = f.env.require("runtime/ui_mod_panels")
	local native = assert(models.create({ id = "workspace", title = "Project controls" }, {
		id = value.id, gate = function() return true end, invoke = function(fn, ...) return fn(...) end,
	}))
	local section = assert(native:Section({ id = "notes", title = "Working notes" }))
	local notes = assert(section:Input({ id = "scratchpad", text = "Scratchpad", value = "Original draft" }))
	w.open()
	check("script mods have a native workspace tab and real controls", f.h.byName("UiModNativeTab_workspace", f.host) ~= nil
		and f.h.byName("UiModNativeSection_notes", f.host) ~= nil and f.h.byName("UiModScriptWorkspace", f.host) == nil)
	local nativeField = field(f, "UiModNativeInput_scratchpad", f.host)
	nativeField.Text = "Retain my scratchpad"; f.h.settle(0.2)
	check("native mod inputs retain their domain state", notes:Get() == "Retain my scratchpad")
	notes:Set("Live update"); f.h.settle(0.2)
	check("value changes update the existing field rather than rebuilding the workspace", field(f, "UiModNativeInput_scratchpad", f.host) == nativeField
		and nativeField.Text == "Live update")
	local second = assert(models.create({ id = "second", title = "Second panel" }, {
		id = value.id, gate = function() return true end, invoke = function(fn, ...) return fn(...) end,
	}))
	assert(second:Section({ id = "content", title = "Second panel content" })):Text({ id = "retained", text = "Selected after remount" })
	f.h.settle(0.2)
	assert(w.panel.select(second.key)); f.h.settle(0.2)
	w.panel.destroy(); w.open()
	check("native mod workspace remounts retain the selected panel", f.h.byName("UiModNativeText_retained", f.host) ~= nil
		and w.app.modPanelSelection == second.key)
	second:Destroy(); assert(w.panel.select(native.key)); f.h.settle(0.2)
	native:Destroy(); f.h.settle(0.2)
	check("removing the owned panel removes its native workspace view", f.h.byName("UiModNativeInput_scratchpad", f.host) == nil
		and f.h.byName("UiModScriptWorkspace", f.host) ~= nil)
	w.panel.destroy(); f.healthy(); f.close()
end)
suite.finish()
