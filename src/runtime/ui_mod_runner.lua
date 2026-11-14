-- Explicitly activated script mods have full host access and one owned lifetime.
-- Native calls and already-running callbacks remain cooperative until they return.
return function(env)
	local util = env.require("runtime/util")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local mods = env.require("runtime/ui_mods")
	local signal = env.require("runtime/signal")
	local M = { changed = signal.new("ui_mod_runner"), mounted = signal.new("ui_mod_mount") }
	local current, operation, starting, alive, generation = nil, nil, false, true, 0
	local stopping, callbacks, cancelEpoch, lastCleanupFailures = 0, 0, 0, 0
	local function member(value, key)
		local ok, fn = pcall(function() return value[key] end)
		return ok and type(fn) == "function" and fn or nil
	end
	local function packed(...) return { n = select("#", ...), ... } end
	local function notify() M.changed:fire() end
	function M.isBusy() return starting or stopping > 0 or callbacks > 0 end
	function M.state()
		local owner = current or operation
		return { busy = M.isBusy(), active = current ~= nil and current.alive == true,
			id = owner and owner.id, revision = owner and owner.revision,
			status = current and current.status or starting and "starting" or "disabled",
			callbacks = callbacks, cleanupOutstanding = stopping,
			cleanupFailures = current and current.cleanupFailures or lastCleanupFailures }
	end
	local function releaseCurrent()
		local record = current
		if not record then return true end
		current, record.alive, record.status = nil, false, "disabled"
		stopping = stopping + 1
		local cleaned = not record.scope or pcall(record.scope.destroy)
		stopping = stopping - 1
		if not cleaned then record.cleanupFailures = record.cleanupFailures + 1 end
		lastCleanupFailures = record.cleanupFailures
		notify()
		return record.cleanupFailures == 0, record.cleanupFailures > 0
			and "Some mod cleanup failed; registered callbacks are disabled, but effects may remain" or nil
	end
	function M.stop()
		cancelEpoch = cancelEpoch + 1
		return releaseCurrent()
	end
	function M.notifyMount(root) if alive then M.mounted:fire(root) end end
	local function contextFor(record, client)
		local scope = record.scope
		local context = { id = record.id, revision = record.revision, uai = client, env = env,
			app = client.app, root = client.app and client.app.screen, scope = scope, require = env.require }
		function context:IsAlive() return alive and record.alive and client.alive == true end
		function context:GetRoot() return client.app and client.app.screen end
		local function invoke(fn, ...)
			if not context:IsAlive() then return end
			callbacks = callbacks + 1
			local result = packed(pcall(fn, ...))
			callbacks = callbacks - 1
			if callbacks == 0 and not record.alive then notify() end
			if not result[1] then error(result[2], 0) end
			return unpack(result, 2, result.n)
		end
		function context:Give(resource)
			local cleanup
			if type(resource) == "function" then cleanup = resource
			else
				local fn = member(resource, "Disconnect") or member(resource, "Destroy") or member(resource, "Cancel") or member(resource, "destroy")
				if fn then cleanup = function() fn(resource) end end
			end
			if not cleanup then return nil, "Give needs a cleanup function, connection or destroyable resource" end
			return scope.give(function()
				stopping = stopping + 1
				local ok = pcall(cleanup)
				stopping = stopping - 1
				if not ok then record.cleanupFailures = record.cleanupFailures + 1 end
				if not record.alive then lastCleanupFailures = record.cleanupFailures end
				if stopping == 0 and not record.alive then notify() end
			end)
		end
		function context:OnDestroy(fn) return self:Give(fn) end
		function context:Connect(event, fn)
			if type(fn) ~= "function" then return nil, "Connect needs a callback" end
			return scope.connect(event, function(...) return invoke(fn, ...) end)
		end
		function context:Delay(seconds, fn, ...)
			if type(fn) ~= "function" then return nil, "Delay needs a callback" end
			return scope.delay(seconds, function(...) return invoke(fn, ...) end, ...)
		end
		function context:OnMount(fn)
			if type(fn) ~= "function" then return nil, "OnMount needs a function" end
			local releaseMount, mountEpoch, closed = nil, 0, false
			local function mount(root)
				if closed then return end
				mountEpoch = mountEpoch + 1
				local mine, previous = mountEpoch, releaseMount
				releaseMount = nil
				if previous then previous() end
				if closed or mine ~= mountEpoch or not self:IsAlive() then return end
				self.root, self.app = root, client.app
				local cleanup = invoke(fn, root, client.app)
				if cleanup ~= nil then
					local release = self:Give(cleanup)
					if release then
						if closed or mine ~= mountEpoch or not self:IsAlive() then release() else releaseMount = release end
					end
				end
			end
			local disconnect, why = scope.connect(M.mounted, mount)
			if not disconnect then return nil, why end
			local release, problem = self:Give(function()
				closed = true
				mountEpoch = mountEpoch + 1
				local previous = releaseMount; releaseMount = nil
				disconnect()
				if previous then previous() end
			end)
			if not release then disconnect(); return nil, problem end
			mount(self:GetRoot())
			return release
		end
		return context
	end
	local function exact(proposal)
		local state = mods.state()
		return state.activeId == proposal.id and state.activeRevision == proposal.revision
	end
	function M.start(record, options)
		if options ~= nil and type(options) ~= "table" then return nil, "Mod startup options must be a table" end
		options = options or {}
		if not alive then return nil, "The client is unloaded" end
		if env.context and env.context.safeMode then return nil, "UI mods are disabled for this safe-mode execution" end
		if M.isBusy() then return nil, "A script mod startup, callback or cleanup is still outstanding" end
		if type(record) ~= "table" or type(record.spec) ~= "table" or record.spec.kind ~= "script"
			or type(record.spec.id) ~= "string" or type(record.spec.source) ~= "string" or type(record.revision) ~= "string" then
			return nil, "A current scripted mod record is required"
		end
		-- Strings are immutable. Snapshot only the execution fields before any yield,
		-- and own the entire read/compiler/cleanup/startup admission immediately.
		local proposal = { id = record.spec.id, source = record.spec.source, revision = record.revision }
		local mine, done, failure, live = cancelEpoch, false, nil, nil
		local function aborted()
			return not alive or mine ~= cancelEpoch or env.context and env.context.safeMode
				or options.aborted and options.aborted() or not exact(proposal)
		end
		local at = clock.ms()
		starting, operation = true, proposal
		notify()
		clock.spawn(function()
			local ok, err = pcall(function()
				local selected = mods.getActive()
				if aborted() or not selected or selected.spec.source ~= proposal.source then error("The exact mod selection changed before startup", 0) end
				local client = env.getClient and env.getClient()
				if not client or not client.alive or not client.sdk or not client.sdk.createScope then error("The client mod host is unavailable", 0) end
				if not caps.has("exec") then error(caps.reason("exec"), 0) end
				local chunk, why = caps.fn.loadstring(proposal.source, "UAI mod: " .. proposal.id)
				if type(chunk) ~= "function" then error("Mod source did not compile: " .. util.ellipsis(tostring(why), 500), 0) end
				if aborted() then error("The mod selection changed during compilation; no source executed", 0) end
				local cleaned, cleanupWhy = releaseCurrent()
				if not cleaned then error(cleanupWhy, 0) end
				if aborted() then error("Mod startup stopped during cleanup; no source executed", 0) end
				generation = generation + 1
				local scope, reason = client.sdk.createScope("ui-mod-" .. proposal.id .. "-" .. generation)
				if not scope then error(reason, 0) end
				live = { id = proposal.id, revision = proposal.revision, scope = scope, alive = true,
					status = "starting", cleanupFailures = 0 }
				current = live
				local context = contextFor(live, client)
				if aborted() or not context:IsAlive() then error("Mod startup stopped before source execution", 0) end
				-- Plain chunks execute once; a returned factory receives the full host.
				local factory = chunk()
				if type(factory) == "function" then
					if aborted() or not context:IsAlive() then error("Mod startup stopped before its factory", 0) end
					local cleanup = factory(context)
					if cleanup ~= nil then context:Give(cleanup) end
				end
				if aborted() or not context:IsAlive() then error("Mod startup stopped; arbitrary effects may remain", 0) end
			end)
			if not ok then failure = util.ellipsis(tostring(err), 600) end
			if current == live and live then
				if not ok then releaseCurrent() else live.status = "active" end
			end
			starting, operation, done = false, nil, true
			notify()
		end)
		while not done do
			if not alive or mine ~= cancelEpoch or options.aborted and options.aborted() or clock.since(at) >= 10000 then
				M.stop()
				return nil, "Mod startup is still outstanding. Registered resources were released; raw/native code or already-running callbacks may continue. Do not retry until they finish.", { outstanding = true }
			end
			clock.wait(0.02)
		end
		if failure then return nil, "Script mod startup failed: " .. failure .. ". Owned cleanup ran; arbitrary effects may remain." end
		if not live or not live.alive then return nil, "Mod activation stopped; owned resources were released" end
		return true
	end
	dispose.add(mods.changed:connect(function()
		local selected = mods.state()
		if operation and (selected.activeId ~= operation.id or selected.activeRevision ~= operation.revision) then cancelEpoch = cancelEpoch + 1 end
		if current and (selected.activeId ~= current.id or selected.activeRevision ~= current.revision) then M.stop() end
	end), "mod selection lifetime")
	dispose.add(function()
		alive = false; M.stop(); M.changed:clear(); M.mounted:clear()
	end, "script mod lifetime")
	return M
end
