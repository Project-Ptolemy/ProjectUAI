-- Direct dispatcher application and full-host script lifetimes, using synthetic resources.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("UI mod activation")
local check, case = suite.check, suite.case
local SOURCE = [[
local host = getgenv()
host.__modExecuted = (host.__modExecuted or 0) + 1
return function(context)
	host.__modContext = context
	host.__modPrepared = host.__prepareCount
	context.require("runtime/caps").fn.writefile("UAI/files/full-mod.txt", "Full host access")
	context:OnDestroy(function() host.__modCleanups = (host.__modCleanups or 0) + 1 end)
	context:Connect(context.env.run.Heartbeat, function() host.__modTicks = (host.__modTicks or 0) + 1 end)
	context:Delay(2, function() host.__modDelayed = true end)
	context:OnMount(function(root)
		host.__modMounts = (host.__modMounts or 0) + 1
		local frame = Instance.new("Frame", root)
		frame.Name = "OwnedModFrame"
		return function() frame:Destroy(); host.__mountCleanups = (host.__mountCleanups or 0) + 1 end
	end)
	return function() host.__returnedCleanup = (host.__returnedCleanup or 0) + 1 end
end
]]
local function newFixture()
	local f = F.new()
	f.tools({ "agentself", "ui_mods" })
	f.mods = f.env.require("runtime/ui_mods")
	f.runner = f.env.require("runtime/ui_mod_runner")
	f.activation = f.env.require("agent/ui_mod_activation")
	local sessions = f.env.require("agent/session")
	f.session = assert(sessions.newThread({ id = "mod-apply" }))
	local screen = f.h.sandbox.Instance.new("ScreenGui", f.h.coreGui)
	f.client = { alive = true, app = { screen = screen }, sessions = sessions, env = f.env }
	f.client.sdk = f.env.require("embedding/sdk").attach(f.client)
	f.env.getClient = function() return f.client end
	f.env.prepareUiMod = function()
		f.h.sandbox.__prepareCount = (f.h.sandbox.__prepareCount or 0) + 1
		return true
	end
	f.ctx = f.session.toolContext()
	f.questions = {}
	f.ctx.emit = function(kind, event) if kind == "ask:user" then f.questions[#f.questions + 1] = event end end
	function f.save(source, id)
		return assert(f.run(function() return f.mods.save({ version = 1, kind = "script", id = id or "full-workspace",
			name = "Full workspace", source = source or SOURCE }) end))
	end
	function f.begin(record, ctx)
		local work = { done = false }
		f.h.sched.spawn(function()
			work.result = f.registry.dispatch({ id = "direct-mod", name = "ui_mod_apply", arguments = f.h.json.encode({
				id = record.id, expected_revision = record.revision }) }, ctx or f.ctx)
			work.done = true
		end)
		f.h.sched.advance(0.3)
		return work
	end
	function f.finish() f.h.sched.advance(0.5) end
	return f
end
case("Allow everything applies directly and owns the full native lifetime", function()
	local f = newFixture(); local saved = f.save()
	check("staging executes nothing", #f.questions == 0
		and f.h.sandbox.__modExecuted == nil and f.h.files["UAI/files/full-mod.txt"] == nil)
	local work = f.begin(saved)
	check("the exact action starts source once without another question", work.done and work.result.ok and work.result.data.applied
		and f.h.sandbox.__modExecuted == 1 and #f.questions == 0)
	check("full host access receives the live client, root and owned scope", f.h.sandbox.__modContext.uai == f.client
		and f.h.sandbox.__modContext.env == f.env and f.h.sandbox.__modContext:GetRoot() == f.client.app.screen
		and f.h.files["UAI/files/full-mod.txt"] == "Full host access")
	check("appearance preparation finishes before startup", f.h.sandbox.__modPrepared == 1)
	check("registered mount resources exist", f.h.byName("OwnedModFrame", f.client.app.screen) ~= nil)
	f.h.services.RunService.Heartbeat:Fire(0.1)
	check("the registered host signal actually reaches the active mod", (f.h.sandbox.__modTicks or 0) > 0)
	f.runner.notifyMount(f.client.app.screen)
	check("remount releases the previous mount and runs its replacement", f.h.sandbox.__modMounts == 2
		and f.h.sandbox.__mountCleanups == 1 and #f.h.find(f.client.app.screen, function(node) return node.Name == "OwnedModFrame" end) == 1)
	local disabled = f.run(f.activation.disable)
	local ticks = f.h.sandbox.__modTicks
	f.h.services.RunService.Heartbeat:Fire(0.1)
	f.h.sched.advance(2.5)
	check("Disable releases all owned cleanup exactly once", disabled.ok and not f.runner.state().active
		and not f.mods.getActive() and f.h.sandbox.__modCleanups == 1 and f.h.sandbox.__returnedCleanup == 1
		and f.h.sandbox.__mountCleanups == 2 and not f.h.byName("OwnedModFrame", f.client.app.screen))
	check("released callbacks and delays stay inactive", f.h.sandbox.__modTicks == ticks and f.h.sandbox.__modDelayed == nil)
	check("arbitrary native effects remain honestly observable", f.h.files["UAI/files/full-mod.txt"] == "Full host access")
	f.run(f.activation.disable)
	check("repeated Disable cannot run cleanup twice", f.h.sandbox.__modCleanups == 1 and f.h.sandbox.__returnedCleanup == 1)
	f.healthy(); f.close()
end)
case("normal tool permissions control application without depending on ask_user", function()
	for _, restriction in ipairs({ "readonly", "denied" }) do
		local f = newFixture(); local saved = f.save()
		if restriction == "readonly" then f.env.require("agent/permissions").setMode("readonly")
		else f.env.require("agent/permissions").setRule("ui_mod_apply", "deny") end
		local work = f.begin(saved)
		check("ordinary permission denial prevents all source effects", work.done and not work.result.ok and #f.questions == 0
			and f.h.sandbox.__modExecuted == nil and f.h.files["UAI/files/full-mod.txt"] == nil and not f.mods.getActive())
		f.healthy(); f.close()
	end
	local f = newFixture(); local saved = f.save()
	f.env.require("agent/permissions").setRule("ask_user", "deny")
	local work = f.begin(saved)
	check("an allowed application does not require a separate question permission", work.done and work.result.ok
		and f.h.sandbox.__modExecuted == 1 and #f.questions == 0)
	f.run(f.activation.disable); f.healthy(); f.close()
end)
case("read scopes stay read only while authorized Full access workers may apply", function()
	local f = newFixture(); local saved = f.save()
	local scoped = f.begin(saved, { session = { headless = true, toolFilter = { ui_mod_list = true, ui_mod_read = true } },
		aborted = function() return false end, emit = f.ctx.emit })
	check("a read-only tool scope cannot acquire the application action", scoped.done and not scoped.result.ok
		and #f.questions == 0 and f.h.sandbox.__modExecuted == nil)
	local ctx = { session = { headless = true, toolFilter = { ui_mod_apply = true } }, aborted = function() return false end, emit = f.ctx.emit }
	local worker = f.begin(saved, ctx)
	check("an authorized Full access worker uses the same exact action", worker.done and worker.result.ok
		and worker.result.data.applied and f.h.sandbox.__modExecuted == 1 and #f.questions == 0)
	f.env.require("agent/permissions").setRule("ui_mod_apply", "deny")
	local denied = f.begin(saved, ctx)
	check("worker scope cannot bypass an explicit application denial", denied.done and not denied.result.ok
		and f.h.sandbox.__modExecuted == 1 and f.mods.getActive().id == saved.id)
	f.run(f.activation.disable)
	f.healthy(); f.close()
end)
case("stale revisions and source edits during preflight cannot execute", function()
	local f = newFixture(); local saved = f.save()
	local edited = saved.spec; edited.source = "getgenv().__wrongSource = true"
	local latest = assert(f.run(function() return f.mods.save(edited, saved.revision) end))
	local stale = f.begin(saved)
	check("stale revisions fail before preparation", stale.done and not stale.result.ok and #f.questions == 0)
	local checkScript = f.mods.checkScript
	f.mods.checkScript = function(spec)
		local ok, why, diagnostic = checkScript(spec)
		local current = assert(f.mods.read(latest.id)); current.spec.source = "getgenv().__newerSource = true"
		assert(f.mods.save(current.spec, current.revision))
		return ok, why, diagnostic
	end
	local changing = f.begin(latest)
	check("preflight source edits invalidate the captured application", changing.done and not changing.result.ok
		and f.h.sandbox.__wrongSource == nil and f.h.sandbox.__newerSource == nil and not f.mods.getActive())
	f.mods.checkScript = checkScript
	f.healthy(); f.close()
end)
case("Disable revokes pending preparation and concurrent Apply is refused", function()
	local f = newFixture(); local saved = f.save()
	local checkScript = f.mods.checkScript
	f.mods.checkScript = function(spec) f.h.sched.wait(1); return checkScript(spec) end
	local first = f.begin(saved)
	local second = f.begin(saved)
	check("one preflight owns the activation gate", not first.done and second.done and not second.result.ok and #f.questions == 0 and f.activation.isBusy())
	f.run(f.activation.disable); f.h.sched.advance(1.1)
	check("Disable invalidates preparation before any source starts", first.done and not first.result.ok and f.h.sandbox.__modExecuted == nil
		and not f.mods.getActive() and not f.activation.isBusy())
	f.mods.checkScript = checkScript
	f.healthy(); f.close()
end)
case("failed persistence and preparation keep source inert", function()
	local f = newFixture(); local saved = f.save(); local caps = f.env.require("runtime/caps")
	local write = caps.fn.writefile
	caps.fn.writefile = function(path, bytes) if path == "UAI/ui_mods/store.json" then return false end; return write(path, bytes) end
	local work = f.begin(saved); f.finish()
	check("unconfirmed selection cannot execute code", work.done and not work.result.ok and f.h.sandbox.__modExecuted == nil and not f.mods.getActive())
	caps.fn.writefile = write; assert(f.mods.reload())
	f.env.prepareUiMod = function() return false, "Mock mount failed" end
	saved = assert(f.mods.read(saved.id)); work = f.begin(saved); f.finish()
	check("failed interface preparation clears the selection", work.done and not work.result.ok and f.h.sandbox.__modExecuted == nil and not f.mods.getActive())
	f.healthy(); f.close()
end)
case("startup errors clean owned resources without claiming arbitrary rollback", function()
	local f = newFixture(); local saved = f.save([[return function(ctx)
		ctx:OnDestroy(function() getgenv().__errorCleanup = true end)
		ctx.require("runtime/caps").fn.writefile("UAI/files/before-error.txt", "Applied before the error")
		error("Fixture startup error")
	end]])
	local work = f.begin(saved); f.finish()
	check("failed startup is reported and disabled", work.done and not work.result.ok and work.result.text:find("arbitrary effects may remain", 1, true)
		and not f.mods.getActive() and not f.runner.state().active and not f.runner.isBusy())
	check("cleanup ran while arbitrary native writes remain", f.h.sandbox.__errorCleanup == true
		and f.h.files["UAI/files/before-error.txt"] == "Applied before the error")
	f.healthy(); f.close()
end)
case("outstanding raw startup retains ownership after the bounded wait", function()
	local f = newFixture(); local saved = f.save([[return function(ctx)
		ctx:OnDestroy(function() getgenv().__timeoutCleanup = true end)
		task.wait(15)
		getgenv().__nativeFinished = true
	end]])
	local work = f.begin(saved); f.finish(); f.h.sched.advance(10)
	check("bounded wait releases resources but retains native ownership", work.done and not work.result.ok and work.result.data.outstanding
		and f.h.sandbox.__timeoutCleanup and f.runner.isBusy() and not f.mods.getActive())
	local retry = f.begin(saved)
	check("outstanding work cannot be started a second time", retry.done and not retry.result.ok and #f.questions == 0)
	f.h.sched.advance(6)
	check("native completion releases its ownership without reactivating", f.h.sandbox.__nativeFinished and not f.runner.isBusy()
		and not f.runner.state().active and not f.mods.getActive())
	f.healthy(); f.close()
end)
case("source replacement and safe mode preserve the explicit execution boundary", function()
	local f = newFixture(); local saved = f.save(); local work = f.begin(saved); f.finish()
	check("initial applied source is active", work.result.ok and f.runner.state().active)
	local spec = saved.spec; spec.source = "getgenv().__replacementExecuted = true"
	local changed = assert(f.run(function() return f.mods.save(spec, saved.revision) end))
	check("saving new active source disables the old owned lifetime", not changed.active and not f.runner.state().active
		and f.h.sandbox.__modCleanups == 1 and f.h.sandbox.__replacementExecuted == nil)
	f.env.context.safeMode = true
	local safe = f.begin(changed)
	check("safe mode refuses activation before preparation", safe.done and not safe.result.ok and #f.questions == 0
		and f.h.sandbox.__replacementExecuted == nil)
	f.healthy(); f.close()
end)
case("compiler waits retain startup ownership and revoked selections stay inert", function()
	local f = newFixture(); local saved = f.save(); local selected = assert(f.run(function() return f.mods.activate(saved.id, saved.revision) end))
	local caps = f.env.require("runtime/caps"); local compile = caps.fn.loadstring
	caps.fn.loadstring = function(source, name) f.h.sched.wait(1); return compile(source, name) end
	local first, second
	f.h.sched.spawn(function() first = { f.runner.start(selected) } end)
	f.h.sched.advance(0.1)
	check("native compilation owns the whole start operation", f.runner.isBusy() and f.h.sandbox.__modExecuted == nil)
	f.h.sched.spawn(function() second = { f.runner.start(selected) } end)
	f.h.sched.advance(0.1)
	check("a second compiler/start cannot enter together", second and not second[1] and second[2]:find("outstanding", 1, true))
	f.run(f.mods.disable); f.h.sched.advance(1.5)
	check("disabled compiler work cannot later execute a chunk", first and not first[1] and f.h.sandbox.__modExecuted == nil
		and not f.runner.isBusy() and not f.runner.state().active)
	caps.fn.loadstring = compile
	f.healthy(); f.close()
end)
case("startup freezes source strings before a yielding compiler", function()
	local f = newFixture(); local saved = f.save(); local selected = assert(f.run(function() return f.mods.activate(saved.id, saved.revision) end))
	local caps = f.env.require("runtime/caps"); local compile = caps.fn.loadstring
	caps.fn.loadstring = function(source, name) f.h.sched.wait(0.4); return compile(source, name) end
	local result
	f.h.sched.spawn(function() result = { f.runner.start(selected) } end)
	f.h.sched.advance(0.1)
	selected.spec.source = "getgenv().__mutatedExecution = true"
	f.h.sched.advance(0.8)
	check("mutating a caller record cannot replace its frozen execution source", result and result[1]
		and f.h.sandbox.__modExecuted == 1 and f.h.sandbox.__mutatedExecution == nil)
	caps.fn.loadstring = compile; f.run(f.activation.disable)
	f.healthy(); f.close()
end)
case("a revision changed during interface preparation cancels startup", function()
	local f = newFixture(); local saved = f.save()
	f.env.prepareUiMod = function()
		local latest = assert(f.mods.read(saved.id)); latest.spec.source = "getgenv().__preparedNewSource = true"
		assert(f.mods.save(latest.spec, latest.revision)); return true
	end
	local work = f.begin(saved); f.finish()
	check("selection changes between preparation and startup run neither source", work.done and not work.result.ok
		and not f.mods.getActive() and f.h.sandbox.__modExecuted == nil and f.h.sandbox.__preparedNewSource == nil)
	f.env.prepareUiMod = nil
	f.healthy(); f.close()
end)
case("yielded remount callbacks cannot replace a newer mount cleanup", function()
	local f = newFixture(); local saved = f.save([[return function(ctx)
		local host = getgenv()
		host.__raceCleanups = {}
		ctx:OnMount(function(root)
			host.__raceMount = (host.__raceMount or 0) + 1
			local number = host.__raceMount
			local frame = Instance.new("Frame", root); frame.Name = "RaceMount" .. number
			if number == 2 then task.wait(0.8) end
			return function() frame:Destroy(); host.__raceCleanups[number] = (host.__raceCleanups[number] or 0) + 1 end
		end)
	end]])
	local work = f.begin(saved); f.finish(); check("initial mount completed", work.result.ok)
	f.h.sched.spawn(function() f.runner.notifyMount(f.client.app.screen) end); f.h.sched.advance(0.1)
	check("a yielded owned mount retains native work", f.runner.isBusy() and f.h.byName("RaceMount2", f.client.app.screen))
	f.runner.notifyMount(f.client.app.screen); f.h.sched.advance(1)
	check("stale mount cleanup runs immediately after its return", f.h.sandbox.__raceCleanups[1] == 1
		and f.h.sandbox.__raceCleanups[2] == 1 and not f.h.byName("RaceMount2", f.client.app.screen)
		and f.h.byName("RaceMount3", f.client.app.screen) and not f.runner.isBusy())
	f.runner.notifyMount(f.client.app.screen)
	check("the next remount releases the actual latest mount", f.h.sandbox.__raceCleanups[3] == 1
		and not f.h.byName("RaceMount3", f.client.app.screen) and f.h.byName("RaceMount4", f.client.app.screen))
	f.run(f.activation.disable)
	check("Disable releases remaining mounts once", f.h.sandbox.__raceCleanups[4] == 1)
	f.healthy(); f.close()
end)
case("in-flight helper callbacks and early cleanup block a replacement until done", function()
	for _, kind in ipairs({ "Connect", "Delay", "cleanup" }) do
		local f = newFixture()
		local body = [[return function(ctx)
			local function callback()
				getgenv().__helperStarted = true
				task.wait(1)
				getgenv().__helperFinished = true
			end
			KIND
		end]]
		local registration = kind == "Connect" and 'ctx:Connect(ctx.env.run.Heartbeat, callback)'
			or kind == "Delay" and 'ctx:Delay(0.2, callback)'
			or 'getgenv().__releaseHelper = ctx:Give(callback)'
		body = body:gsub("KIND", function() return registration end)
		local saved = f.save(body); local work = f.begin(saved); f.finish(); check("helper registered", work.result.ok)
		if kind == "Connect" then f.h.sched.spawn(function() f.h.services.RunService.Heartbeat:Fire(0.1) end)
		elseif kind == "cleanup" then f.h.sched.spawn(f.h.sandbox.__releaseHelper) end
		f.h.sched.advance(0.1)
		check("yielded helper work owns the runner", f.h.sandbox.__helperStarted and f.runner.isBusy())
		local disabled = f.run(f.activation.disable)
		check("Disable reports cooperative work honestly", disabled.ok and disabled.text:find("outstanding", 1, true) and f.runner.isBusy())
		local retry = f.begin(saved)
		check("new startup cannot overlap a released but running helper", retry.done and not retry.result.ok and #f.questions == 0)
		f.h.sched.advance(1.3)
		check("actual helper completion releases the runtime", f.h.sandbox.__helperFinished and not f.runner.isBusy() and not f.runner.state().active)
		f.healthy(); f.close()
	end
end)
case("early mount release cannot admit a new mount during yielding cleanup", function()
	local f = newFixture(); local saved = f.save([[return function(ctx)
		local host = getgenv()
		host.__releaseMount = ctx:OnMount(function(root)
			host.__earlyMounts = (host.__earlyMounts or 0) + 1
			local frame = Instance.new("Frame", root); frame.Name = "EarlyReleasedMount"
			return function()
				task.wait(0.6)
				frame:Destroy(); host.__earlyMountCleanup = (host.__earlyMountCleanup or 0) + 1
			end
		end)
	end]])
	local work = f.begin(saved); f.finish(); check("initial early-release mount is active", work.result.ok)
	f.h.sched.spawn(f.h.sandbox.__releaseMount); f.h.sched.advance(0.1)
	check("early-release cleanup retains ownership", f.runner.isBusy())
	f.runner.notifyMount(f.client.app.screen); f.h.sched.advance(0.8)
	check("released listener admits no later mount or leaked resource", f.h.sandbox.__earlyMounts == 1
		and f.h.sandbox.__earlyMountCleanup == 1 and not f.h.byName("EarlyReleasedMount", f.client.app.screen)
		and not f.runner.isBusy())
	f.run(f.activation.disable)
	check("Disable cannot repeat the released mount cleanup", f.h.sandbox.__earlyMountCleanup == 1)
	f.healthy(); f.close()
end)
case("CreatePanel owns native panel state and outstanding domain callbacks", function()
	local f = newFixture()
	f.client.app.showModPanel = function(key) f.shownPanel = key; return true end
	local saved = f.save([[return function(context)
		local host = getgenv()
		host.__nativePanel = assert(context:CreatePanel({ id = "workspace", title = "Native workspace" }))
		local section = assert(host.__nativePanel:Section({ id = "actions", title = "Actions" }))
		host.__nativeInput = assert(section:Input({ id = "notes", text = "Notes", value = "Keep across mounts" }))
		assert(section:Button({ id = "slow", text = "Owned operation", callback = function()
			host.__nativeStarted = true
			task.wait(1)
			host.__nativeFinished = true
		end }))
		assert(host.__nativePanel:Show())
	end]])
	local work = f.begin(saved); f.finish()
	local models = f.env.require("runtime/ui_mod_panels")
	local panel = f.h.sandbox.__nativePanel
	check("authorized Apply exposes a real native panel through the owned context", work.done and work.result.ok
		and f.shownPanel == panel.key and models.snapshot(panel.key).title == "Native workspace")
	f.runner.notifyMount(f.client.app.screen)
	check("presentation remounts cannot replace the native domain state", f.h.sandbox.__nativePanel == panel
		and f.h.sandbox.__nativeInput:Get() == "Keep across mounts")
	f.h.sched.spawn(function() models.trigger(panel.key, "slow") end); f.h.sched.advance(0.1)
	check("panel domain callbacks participate in runner native ownership", f.h.sandbox.__nativeStarted and f.runner.isBusy())
	local disabled = f.run(f.activation.disable)
	check("Disable unregisters panels while outstanding native callbacks remain owned", disabled.ok and models.snapshot(panel.key) == nil
		and not panel:IsAlive() and f.runner.isBusy() and panel:Show() == nil)
	f.h.sched.advance(1.1)
	check("callback completion releases ownership without restoring a removed panel", f.h.sandbox.__nativeFinished
		and not f.runner.isBusy() and models.snapshot(panel.key) == nil)
	f.healthy(); f.close()
end)
case("early native panel destruction releases scoped ownership without cancelling callbacks", function()
	local f = newFixture()
	local saved = f.save([[return function(context)
		local host = getgenv()
		host.__earlyPanelContext = context
		host.__earlyPanelBaseline = context.scope.resourceCount()
		host.__earlyPanel = assert(context:CreatePanel({ id = "early", title = "Early release" }))
		local section = assert(host.__earlyPanel:Section({ id = "actions", title = "Actions" }))
		assert(section:Button({ id = "slow", text = "Owned operation", callback = function()
			host.__earlyPanelStarted = true
			task.wait(1)
			host.__earlyPanelFinished = true
		end }))
	end]])
	local work = f.begin(saved); f.finish()
	local models = f.env.require("runtime/ui_mod_panels")
	local context, panel = f.h.sandbox.__earlyPanelContext, f.h.sandbox.__earlyPanel
	local baseline, removed = f.h.sandbox.__earlyPanelBaseline, 0
	local off = models.changed:connect(function(key, kind)
		if key == panel.key and kind == "structure" and not models.snapshot(key) then removed = removed + 1 end
	end)
	check("an authorized panel adds one owned scope resource", work.done and work.result.ok and context.scope.resourceCount() == baseline + 1)
	f.h.sched.spawn(function() models.trigger(panel.key, "slow") end); f.h.sched.advance(0.1)
	panel:Destroy(); panel:Destroy()
	check("early destruction removes the scope entry and panel exactly once", context.scope.resourceCount() == baseline
		and models.snapshot(panel.key) == nil and removed == 1)
	check("early panel destruction retains outstanding native callback ownership", f.h.sandbox.__earlyPanelStarted and f.runner.isBusy())
	for index = 1, 6 do
		local temporary = assert(context:CreatePanel({ id = "temporary", title = "Temporary panel" }))
		temporary:Destroy()
	end
	check("repeated early destruction cannot accumulate scoped panel resources", context.scope.resourceCount() == baseline and #models.list(context.id) == 0)
	local disabled = f.run(f.activation.disable); f.h.sched.advance(1.1)
	check("Disable preserves callback settlement without repeating early cleanup", disabled.ok and f.h.sandbox.__earlyPanelFinished
		and not f.runner.isBusy() and context.scope.resourceCount() == 0 and removed == 1)
	off(); f.healthy(); f.close()
end)
suite.finish()
