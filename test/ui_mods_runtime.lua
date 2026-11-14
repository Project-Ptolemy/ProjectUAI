-- Portable definitions, version guards and verified persistence without executing mod code.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("UI mods runtime")
local case, check = suite.case, suite.check
local PATH = "UAI/ui_mods/store.json"
local function visual(id)
	return { version = 1, kind = "visual", id = id or "workbench", name = "Project workbench", description = "A focused workspace",
		appearance = { accent = "indigo", density = "compact", fontScale = 1.05 }, panels = { { id = "progress", title = "Progress", widgets = {
			{ id = "intro", type = "text", body = "Keep the current goal and verification evidence visible." },
			{ id = "goals", type = "metric", label = "Micro goals", selector = "goals" },
			{ id = "vault", type = "action", label = "Open Master Vault", action = "vault" },
		} } } }
end
local function script(id, source)
	return { version = 1, kind = "script", id = id or "scripted-workbench", name = "Scripted workbench", source = source or "return function(context) return function() end end",
		sources = { { label = "Reviewed local source", url = "https://example.invalid/mod-source" } } }
end
case("portable visual and full script definitions round trip as detached data", function()
	local f = F.new(); local doc = f.env.require("runtime/ui_mod_document")
	local value = visual(); value.panels[1].widgets[1].body = "界\r\nPlain <text> with literal Markdown **markers**."
	local json = assert(doc.format(value)); local decoded = assert(doc.parse(json))
	check("canonical visual JSON is stable", doc.format(decoded) == json)
	check("body UTF-8 and CRLF survive", decoded.panels[1].widgets[1].body == value.panels[1].widgets[1].body)
	decoded.appearance.accent = "amber"
	check("validation detached appearance", value.appearance.accent == "indigo")
	local code = "-- arbitrary native access stays source text\r\nreturn function(ctx)\r\n local app = ctx.env.require('ui/app')\r\n return function() end\r\nend\r\n"
	local restored = assert(doc.parse(assert(doc.format(script(nil, code)))))
	check("script source exports every byte", restored.source == code)
	f.close()
end)
case("schema rejects unsupported fields, malformed JSON and unsafe visual selectors", function()
	local f = F.new(); local doc = f.env.require("runtime/ui_mod_document")
	local value = visual(); value.appearance.apiKey = "not a UI preference"
	check("arbitrary preferences stay out of visual definitions", doc.validate(value) == nil)
	value = visual(); value.panels[1].widgets[2].selector = "providers.apiKey"
	check("metrics cannot select arbitrary client paths", doc.validate(value) == nil)
	value = visual(); value.panels[1].widgets[3].action = "run_luau"
	check("visual actions only navigate", doc.validate(value) == nil)
	value = visual(); value.panels[1].widgets[3].label = "<b>Run</b>"
	check("action labels cannot inject markup", doc.validate(value) == nil)
	value = visual(); value.panels[1].widgets[3].label = "Run ✓"
	check("visual labels do not supply icon glyphs", doc.validate(value) == nil)
	value = visual(); value.panels[1].widgets[2].id = value.panels[1].widgets[1].id
	check("duplicate stable widget IDs are refused", doc.validate(value) == nil)
	check("future and duplicate JSON versions are rejected", doc.parse('{"version":2}') == nil and doc.parse('{"version":2,"version":1}') == nil)
	check("escaped duplicate object keys are rejected", doc.parse('{"id":"a","\\u0069d":"b"}') == nil)
	check("excessive depth is refused before decoding", doc.parse(string.rep('[', 20) .. '0' .. string.rep(']', 20)) == nil)
	check("script source limit and invalid UTF-8 are refused", doc.validate(script(nil, string.rep("x", 262145))) == nil and doc.validate(script(nil, "return '\255'")) == nil)
	value = script(); value.enabled = true
	check("portable definitions do not import enabled state", doc.validate(value) == nil)
	for _, field in ipairs({ "description", "sources", "appearance", "panels" }) do
		value = visual(); value[field] = false
		check("supplied " .. field .. " keeps its declared type", doc.validate(value) == nil)
	end
	value = visual(); value.panels[1].description = false
	check("optional panel descriptions keep their declared type", doc.validate(value) == nil)
	f.close()
end)
case("visual limits apply across all panels and finite appearance values", function()
	local f = F.new(); local doc = f.env.require("runtime/ui_mod_document")
	local value = visual(); value.panels = {}
	for panelIndex = 1, 4 do
		local panel = { id = "panel-" .. panelIndex, title = "Panel " .. panelIndex, widgets = {} }
		for widgetIndex = 1, 3 do panel.widgets[widgetIndex] = { id = "widget-" .. panelIndex .. "-" .. widgetIndex,
			type = "text", body = "A declared panel body." } end
		value.panels[panelIndex] = panel
	end
	check("four panels and twelve widgets are accepted together", doc.validate(value) ~= nil)
	value.panels[4].widgets[4] = { id = "thirteenth", type = "text", body = "One extra widget." }
	check("a thirteenth widget is rejected across panel boundaries", doc.validate(value) == nil)
	value.panels[4].widgets[4] = nil; value.panels[4].widgets[3].id = value.panels[1].widgets[1].id
	check("widget IDs are unique across separate panels", doc.validate(value) == nil)
	for _, scale in ipairs({ 0.85, 1.4 }) do
		value = visual(); value.appearance.fontScale = scale
		check("fontScale accepts its endpoint " .. scale, doc.validate(value) ~= nil)
	end
	for _, scale in ipairs({ 0 / 0, math.huge, -math.huge, 0.84, 1.41 }) do
		value = visual(); value.appearance.fontScale = scale
		check("fontScale rejects nonfinite or out-of-range values", doc.validate(value) == nil)
	end
	check("source accepts the exact byte limit without compilation", doc.validate(script(nil, string.rep("x", doc.limits.source))) ~= nil)
	f.close()
end)
case("scalar collection limits stop allocation before the native decoder", function()
	local f = F.new(); local doc = f.env.require("runtime/ui_mod_document"); local util = f.env.require("runtime/util")
	local decode, calls = util.decode, 0
	util.decode = function(...) calls = calls + 1; return decode(...) end
	local portable = "[0" .. string.rep(",0", doc.limits.nodes) .. "]"
	local decoded, why = doc.decodeJson(portable)
	check("portable scalar arrays are refused before any JSON decode", decoded == nil and why:find("entry count", 1, true) and calls == 0)
	local mods = f.env.require("runtime/ui_mods")
	local store = "[0" .. string.rep(",0", mods.limits.nodes) .. "]"
	decoded, why = doc.decodeJson(store, mods.limits.file, mods.limits.depth, mods.limits.nodes)
	check("storage scalar arrays are refused before any JSON decode", decoded == nil and why:find("entry count", 1, true) and calls == 0)
	local commas = script(nil, "-- " .. string.rep(",", 1000) .. "\nreturn 1")
	local encoded = assert(doc.format(commas))
	check("commas inside unrestricted source strings remain source data", assert(doc.parse(encoded)).source == commas.source)
	f.close()
end)
case("the complete supported visual collection fits the JSON admission limits", function()
	local f = F.new(); local doc = f.env.require("runtime/ui_mod_document"); local mods = f.env.require("runtime/ui_mods")
	local value = visual("maximal-visual"); value.author = string.rep("a", 160); value.sources = {}
	for index = 1, 8 do value.sources[index] = { label = string.rep("s", 160), url = string.rep("u", 500) } end
	value.appearance = { theme = "default", accent = "amber", density = "compact", fontScale = 1.4,
		interfaceFont = "montserrat", codeFont = "code", codeTheme = "dark", transcriptWidth = "wide" }
	value.panels = {}
	for panelIndex = 1, 4 do
		local panel = { id = "maximal-panel-" .. panelIndex, title = string.rep("p", 100), description = string.rep("d", 500), widgets = {} }
		for widgetIndex = 1, 3 do panel.widgets[widgetIndex] = { id = "maximal-widget-" .. panelIndex .. "-" .. widgetIndex,
			type = "metric", label = string.rep("l", 100), selector = "goals" } end
		value.panels[panelIndex] = panel
	end
	local portable = assert(doc.format(value))
	check("all supported visual collections and fields fit portable admission", doc.parse(portable) ~= nil)
	local rows = {}
	for index = 1, 16 do
		local spec = assert(doc.parse(portable)); spec.id = "maximal-visual-" .. index
		local row = { version = 4, updatedAt = 0, spec = spec, history = {} }
		for version = 3, 1, -1 do row.history[#row.history + 1] = { version = version, updatedAt = 0, spec = spec } end
		rows[index] = row
	end
	f.h.sandbox.writefile(PATH, f.h.json.encode({ version = 1, generation = 1,
		selected = { id = "maximal-visual-16", version = 4 }, records = rows }))
	local listing = assert(mods.list())
	check("sixteen complete visual records with all retained history remain writable", listing.total == 16 and listing.state.writable
		and mods.read("maximal-visual-16").historyCount == 3 and mods.getActive().id == "maximal-visual-16")
	f.healthy(); f.close()
end)
case("authored catalog examples validate and script checks only compile", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local doc = f.env.require("runtime/ui_mod_document")
	local caps = f.env.require("runtime/caps"); local compile = caps.fn.loadstring
	local compiled, executed = 0, false
	caps.fn.loadstring = function(source, name)
		compiled = compiled + 1
		local chunk, why = compile(source, name)
		if not chunk then return nil, why end
		return function(...) executed = true; return chunk(...) end
	end
	local function readFile(path)
		local file = assert(io.open(path, "rb")); local bytes = file:read("*a"); file:close(); return bytes
	end
	local catalog = assert(doc.decodeJson(readFile("mods/catalog.json"), 2048, 3, 16))
	local expected = { "project-workbench.json", "native-lifecycle-marker.json" }
	check("catalog contains the two reviewed examples", catalog.version == 1 and type(catalog.entries) == "table" and #catalog.entries == #expected)
	for index, name in ipairs(expected) do
		check("catalog preserves the reviewed filename " .. name, catalog.entries[index] == name)
		local value = assert(doc.parse(readFile("mods/" .. name)))
		local portable = assert(doc.format(value))
		check(name .. " round trips through its supported schema", doc.format(assert(doc.parse(portable))) == portable)
		local ok, why, diagnostic = mods.checkScript(value)
		check(name .. " has a valid inert preview", ok and why == nil and diagnostic.executed == false)
	end
	check("only the scripted example was compiled and no chunk was called", compiled == 1 and not executed)
	check("reading examples does not install or select them", mods.list().total == 0 and mods.getActive() == nil)
	f.healthy(); f.close()
end)
case("import, reads and compiler checks never execute authored source", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	local executed, compiled = false, 0
	caps.fn.loadstring = function() compiled = compiled + 1; return function() executed = true end end
	local before = #f.h.http.log
	local value = script(nil, "error('must only be compiled')")
	local saved = assert(mods.import(assert(mods.format(value))))
	check("import stages disabled without compilation", not saved.active and compiled == 0 and not executed)
	assert(mods.read(saved.id)); assert(mods.export(saved.id))
	check("reads and exports do not compile or execute", compiled == 0 and not executed)
	local ok, reason, diagnostic = mods.checkScript(value)
	check("explicit check compiles without calling", ok and reason == nil and diagnostic.executed == false and compiled == 1 and not executed)
	caps.fn.loadstring = nil
	local available, _, missing = mods.checkScript(value)
	check("missing compiler is explicit", not available and missing.compilerAvailable == false and missing.executed == false)
	check("data/check operations make no HTTP", #f.h.http.log == before)
	f.close()
end)
case("yielded preview compilation remains owned through disposal and errors", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	assert(mods.list())
	local calls, executed, outcome = 0, false, nil
	caps.fn.loadstring = function()
		calls = calls + 1; f.h.sched.wait(0.05)
		return function() executed = true end
	end
	f.h.sched.spawn(function() outcome = { mods.checkScript(script()) } end); f.h.sched.advance(0.01)
	check("a native preview compile owns the runtime", mods.isBusy() and mods.state().compiling == 1 and not executed)
	f.close()
	check("disposal keeps the native compiler tracked", mods.isBusy())
	local admitted, _, stopped = mods.checkScript(script())
	check("unloaded previews admit no further native compiler calls", not admitted and stopped.stopped and calls == 1)
	f.h.sched.advance(0.1)
	check("late completion releases ownership without executing or publishing success", outcome and outcome[1] == false and outcome[3].stopped
		and not mods.isBusy() and mods.state().compiling == 0 and not executed)
	f.healthy()
	local failure = F.new(); local nextMods = failure.env.require("runtime/ui_mods")
	failure.env.require("runtime/caps").fn.loadstring = function() error("Compiler failed") end
	local ok, why = nextMods.checkScript(script())
	check("compiler errors release preview admission", not ok and why:find("Compiler failed", 1, true) and not nextMods.isBusy() and nextMods.state().compiling == 0)
	failure.healthy(); failure.close()
end)
case("revisions and bounded full history protect saved mods", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods")
	local saved = assert(mods.save(script(nil, "return 1"))); local initialRevision = saved.revision
	local original = f.h.files[PATH]
	check("missing replacement revision keeps storage", mods.save(saved.spec) == nil and f.h.files[PATH] == original)
	for version = 2, 6 do saved.spec.source = "return " .. version; saved = assert(mods.save(saved.spec, saved.revision)) end
	check("versions advance and retain the newest three complete sources", saved.version == 6 and #saved.history == 3
		and saved.history[1].version == 5 and saved.history[3].version == 3 and saved.history[3].spec.source == "return 3")
	check("stale writes and deletes preserve the latest version", mods.save(saved.spec, initialRevision) == nil and not mods.delete(saved.id, initialRevision))
	saved.spec.source = "caller mutation"; saved.history[1].spec.source = "caller mutation"
	check("returned records/history are detached", mods.read(saved.id).spec.source == "return 6" and mods.read(saved.id).history[1].spec.source == "return 5")
	f.close()
end)
case("the collection cap permits replacement and reuse after deletion", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local saved = {}
	for index = 1, mods.limits.mods do saved[index] = assert(mods.save(visual("saved-" .. index))) end
	local original = f.h.files[PATH]
	check("the collection admits sixteen saved definitions", mods.list().total == 16)
	local extra, why = mods.save(visual("seventeenth"))
	check("a seventeenth definition is refused before persistence", extra == nil and why:find("sixteen", 1, true) and f.h.files[PATH] == original)
	saved[1].spec.description = "A reviewed replacement at the collection cap."
	local replacement = assert(mods.save(saved[1].spec, saved[1].revision))
	check("replacement at the cap retains the collection size", replacement.version == 2 and mods.list().total == 16)
	assert(mods.delete(saved[2].id, saved[2].revision))
	local reused = assert(mods.save(visual("seventeenth")))
	check("confirmed deletion admits one new disabled definition", reused.active == false and mods.list().total == 16)
	f.healthy(); f.close()
end)
case("the whole-file cap protects source history and oversized storage", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local rows = {}
	for index = 1, 7 do
		local value = script("stored-" .. index, string.rep("x", 144000))
		rows[index] = { version = 4, updatedAt = 0, spec = value, history = {} }
		for previous = 3, 1, -1 do rows[index].history[#rows[index].history + 1] = { version = previous, updatedAt = 0, spec = value } end
	end
	local original = f.h.json.encode({ version = 1, generation = 1, records = rows })
	check("the complete-history fixture remains below four MiB", #original < mods.limits.file and #original > mods.limits.file - 200000)
	f.h.sandbox.writefile(PATH, original)
	local listed = assert(mods.list())
	check("complete bounded history loads as writable storage", listed.total == 7 and listed.state.writable and mods.read("stored-1").historyCount == 3)
	local saved, why = mods.save(script("overflow", string.rep("y", 200000)))
	check("an over-cap commit preserves every original byte", saved == nil and why:find("4 MiB", 1, true) and f.h.files[PATH] == original)
	check("capacity refusal does not publish source or mark a write unconfirmed", mods.read("overflow") == nil and not mods.state().uncertain and mods.list().total == 7)
	local oversized = string.rep(" ", mods.limits.file + 1); f.h.files[PATH] = oversized
	local refreshed, reason = mods.reload()
	check("oversized disk data stays untouched with known records retained", refreshed == nil and reason:find("4 MiB", 1, true)
		and f.h.files[PATH] == oversized and mods.read("stored-1").version == 4 and not mods.state().writable)
	check("oversized storage cannot be silently replaced", mods.save(visual("new")) == nil and f.h.files[PATH] == oversized)
	f.healthy(); f.close()
end)
case("visual selections restore and fresh script selections stay disabled", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods")
	local a = assert(mods.save(visual())); assert(mods.activate(a.id, a.revision))
	check("visual preferences are active overrides", mods.appearance().accent == "indigo")
	check("base configuration stays separate", f.env.require("runtime/config").get("ui.accent") ~= "indigo")
	local visualFresh = F.new(); visualFresh.h.sandbox.writefile(PATH, f.h.files[PATH])
	check("validated approved visual selection restores", visualFresh.env.require("runtime/ui_mods").getActive().id == a.id)
	visualFresh.close()
	local b = assert(mods.save(script())); assert(mods.activate(b.id, b.revision))
	check("exactly one active identity is selected", mods.getActive().id == b.id and mods.appearance().accent == nil)
	local scriptFresh = F.new(); scriptFresh.h.sandbox.writefile(PATH, f.h.files[PATH])
	local freshMods = scriptFresh.env.require("runtime/ui_mods"); local restored = assert(freshMods.read(b.id))
	check("fresh script selection awaits new apply without execution", restored.selected and not restored.active and freshMods.getActive() == nil)
	check("history versions survive reload with fresh read tokens", restored.version == b.version and restored.revision ~= b.revision)
	check("old runtime tokens cannot change restored records", freshMods.save(restored.spec, b.revision) == nil)
	scriptFresh.close(); f.close()
end)
case("safe-mode recovery retains definitions without restoring either mod kind", function()
	for _, kind in ipairs({ "visual", "script" }) do
		local f = F.new(); local mods = f.env.require("runtime/ui_mods")
		local saved = assert(mods.save(kind == "visual" and visual() or script()))
		assert(mods.activate(saved.id, saved.revision))
		local bytes = f.h.files[PATH]
		local fresh = F.new(); fresh.env.context.safeMode = true; fresh.h.sandbox.writefile(PATH, bytes)
		local safeMods = fresh.env.require("runtime/ui_mods"); local reviewed = assert(safeMods.read(saved.id))
		check(kind .. " safe-mode selection stays available and inactive", reviewed.selected and not reviewed.active
			and safeMods.getActive() == nil and next(safeMods.appearance()) == nil)
		local applied, why = safeMods.activate(reviewed.id, reviewed.revision)
		check(kind .. " direct activation respects safe mode without rewriting storage", applied == nil and why:find("safe-mode", 1, true)
			and fresh.h.files[PATH] == bytes and safeMods.getActive() == nil)
		local staged = assert(safeMods.save(script("safe-mode-draft", "return 1")))
		check(kind .. " recovery still permits inert staging and export", not staged.active and safeMods.export(reviewed.id) ~= nil
			and safeMods.read(reviewed.id).selected)
		f.env.context.safeMode = true; assert(mods.reload())
		check(kind .. " recovery reload clears a previously live identity", mods.getActive() == nil and next(mods.appearance()) == nil and mods.read(saved.id).selected)
		local disabled, _, detail = safeMods.disable()
		check(kind .. " recovery can remember an explicit disable", disabled and detail.persisted and not safeMods.read(reviewed.id).selected)
		f.healthy(); fresh.healthy(); fresh.close(); f.close()
	end
end)
case("failed persistence retains the last known good live mod until explicit recovery", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	local saved = assert(mods.save(visual())); assert(mods.activate(saved.id, saved.revision))
	local baseWrite = caps.fn.writefile
	caps.fn.writefile = function(path, bytes) if path == PATH then error("payload-bearing host error " .. bytes) end; return baseWrite(path, bytes) end
	saved.spec.appearance.accent = "amber"
	local changed, why, detail = mods.save(saved.spec, saved.revision)
	check("uncertain save keeps known live appearance", changed == nil and detail.uncertain and mods.appearance().accent == "indigo")
	check("host payload errors are suppressed", not why:find("payload-bearing", 1, true))
	check("unreviewed retry is refused", mods.save(saved.spec, saved.revision) == nil)
	check("resident reads do not pretend to resolve disk uncertainty", mods.read(saved.id).spec.appearance.accent == "indigo" and mods.state().uncertain)
	caps.fn.writefile = baseWrite
	local current = assert(mods.read(saved.id, { refresh = true }))
	check("explicit refresh resolves verified old bytes", not mods.state().uncertain and current.spec.appearance.accent == "indigo")
	current.spec.appearance.accent = "amber"; local replaced = assert(mods.save(current.spec, current.revision))
	check("confirmed active replacement stages disabled", not replaced.active and mods.getActive() == nil)
	f.close()
end)
case("lost write verification can recover a newly saved disabled version", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	local saved = assert(mods.save(script(nil, "return 1")))
	local baseWrite, baseRead, failRead = caps.fn.writefile, caps.fn.readfile, false
	caps.fn.writefile = function(path, bytes) local result = baseWrite(path, bytes); if path == PATH then failRead = true end; return result end
	caps.fn.readfile = function(path) if path == PATH and failRead then failRead = false; error("verification unavailable") end; return baseRead(path) end
	saved.spec.source = "return 2"
	check("lost confirmation retains version one in memory", mods.save(saved.spec, saved.revision) == nil and mods.read(saved.id).spec.source == "return 1")
	caps.fn.writefile, caps.fn.readfile = baseWrite, baseRead
	local reviewed = assert(mods.read(saved.id, { refresh = true }))
	check("actual written version becomes reviewable without activation", reviewed.version == 2 and reviewed.spec.source == "return 2" and not reviewed.active)
	f.close()
end)
case("external edits invalidate old observations even when stored versions repeat", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods")
	local saved = assert(mods.save(script(nil, "return 1")))
	f.h.files[PATH] = f.h.files[PATH]:gsub("return 1", "return 9")
	check("full store bytes guard external edits", mods.save(saved.spec, saved.revision) == nil)
	local reviewed = assert(mods.read(saved.id, { refresh = true }))
	check("fresh observation differs despite repeated persisted version", reviewed.version == saved.version and reviewed.revision ~= saved.revision)
	check("another reader cannot revive the old token", mods.save(saved.spec, saved.revision) == nil)
	f.close()
end)
case("native writes serialize and disable cancels an admitted activation", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	local saved = assert(mods.save(visual()))
	local baseRead, delayed, outcome = caps.fn.readfile, true, nil
	caps.fn.readfile = function(path)
		if path == PATH and delayed then delayed = false; local bytes = baseRead(path); f.h.sched.wait(0.05); return bytes end
		return baseRead(path)
	end
	f.h.sched.spawn(function() outcome = { mods.activate(saved.id, saved.revision) } end)
	f.h.sched.advance(0.01)
	check("native preflight owns mutation admission", mods.isBusy())
	check("concurrent writer and recovery reload are refused", mods.save(visual("second")) == nil and mods.reload() == nil)
	local disabled, _, detail = mods.disable()
	check("emergency disable takes effect during the native call", disabled and not detail.persisted and mods.getActive() == nil)
	f.h.sched.advance(0.1)
	check("pending activation cannot reenable after disable", outcome and outcome[1] == nil and outcome[3].disabledDuringWrite and mods.getActive() == nil and not mods.isBusy())
	local fresh = F.new(); fresh.h.sandbox.writefile(PATH, f.h.files[PATH])
	check("a pre-dispatch disable is stored without active selection", fresh.env.require("runtime/ui_mods").getActive() == nil)
	fresh.close(); f.close()
end)
case("native reload reads remain owned and cannot undo a concurrent disable", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods"); local caps = f.env.require("runtime/caps")
	local saved = assert(mods.save(visual())); assert(mods.activate(saved.id, saved.revision))
	local baseRead, delayed, outcome = caps.fn.readfile, true, nil
	caps.fn.readfile = function(path)
		if path == PATH and delayed then delayed = false; local bytes = baseRead(path); f.h.sched.wait(0.05); return bytes end
		return baseRead(path)
	end
	f.h.sched.spawn(function() outcome = { mods.reload() } end); f.h.sched.advance(0.01)
	check("an outstanding native read owns the runtime", mods.isBusy() and mods.state().loading)
	check("resident reads retain known data during reload", mods.read(saved.id).revision == saved.revision)
	check("a native reload excludes a concurrent write", mods.save(visual("second")) == nil)
	local disabled, _, detail = mods.disable()
	check("disable recovers immediately during reload", disabled and not detail.persisted and mods.getActive() == nil)
	f.h.sched.advance(0.1)
	check("a pre-disable disk snapshot cannot restore the active selection", outcome and outcome[1] and not mods.isBusy()
		and mods.getActive() == nil and not mods.read(saved.id).selected)
	delayed, outcome = true, nil
	f.h.sched.spawn(function() outcome = { mods.reload() } end); f.h.sched.advance(0.01)
	f.close()
	check("disposal keeps an outstanding native read tracked", mods.isBusy())
	f.h.sched.advance(0.1)
	check("read completion cannot revive a disposed runtime", outcome and outcome[1] == nil and not mods.isBusy() and mods.state().status == "unloaded")
	f.healthy()
end)
case("malformed files stay on disk while supported records remain readable", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods")
	local saved = assert(mods.save(visual()))
	local bytes = f.h.files[PATH]
	f.h.files[PATH] = "{malformed"
	check("invalid reload retains known good record", mods.reload() == nil and mods.read(saved.id).name == saved.name and f.h.files[PATH] == "{malformed")
	check("invalid storage cannot be silently overwritten", mods.save(visual("new")) == nil and f.h.files[PATH] == "{malformed")
	local fresh = F.new(); local raw = f.h.json.decode(bytes)
	raw.records[#raw.records + 1] = { version = 1, spec = { version = 99 }, history = {} }
	raw.records[#raw.records + 1] = { version = 1, updatedAt = 0, spec = script("malformed-history"), history = false }
	raw.records[#raw.records + 1] = { version = 1, updatedAt = false, spec = script("malformed-timestamp"), history = {} }
	local partial = f.h.json.encode(raw); fresh.h.sandbox.writefile(PATH, partial)
	local nextMods = fresh.env.require("runtime/ui_mods"); local listed = assert(nextMods.list())
	check("supported initial records load with incomplete coverage", listed.total == 1 and listed.state.incomplete and not listed.state.writable)
	check("unsupported records are preserved untouched", fresh.h.files[PATH] == partial)
	fresh.close(); f.close()
end)
case("without a filesystem live disable still recovers the base preferences", function()
	local f = F.new(); local mods = f.env.require("runtime/ui_mods")
	local saved = assert(mods.save(visual())); assert(mods.activate(saved.id, saved.revision))
	f.env.require("runtime/fsx").enabled = false
	local ok, why, detail = mods.disable()
	check("disable succeeds without pretending persistence", ok and why and detail.persisted == false and mods.getActive() == nil and mods.appearance().accent == nil)
	check("resident records remain portable", mods.export(saved.id) ~= nil and not mods.state().writable)
	f.close()
end)
suite.finish()
