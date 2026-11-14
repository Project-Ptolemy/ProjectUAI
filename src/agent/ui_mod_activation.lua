-- Exact saved mods apply through ordinary tool permissions, with owned startup.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local mods = env.require("runtime/ui_mods")
	local runner = env.require("runtime/ui_mod_runner")
	local H = env.require("tools/helpers")
	local dispose = env.require("runtime/dispose")
	local M = {}
	local pending, alive, operationEpoch = false, true, 0
	function M.isBusy() return pending or runner.isBusy() end
	local function stopped(ctx) return ctx and ctx.aborted and ctx.aborted() end
	local function same(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end
	local function apply(args, ctx)
		local mine = operationEpoch
		if config.accessProblem() then return H.fail(config.accessProblem()) end
		if stopped(ctx) then return H.fail("Mod activation stopped before preparation") end
		if env.context and env.context.safeMode then return H.fail("UI mods are disabled for this safe-mode execution. Reload normally before applying a mod.") end
		local record, why = mods.read(args.id)
		if not record then return H.fail(why) end
		if record.revision ~= args.expected_revision then return H.fail("This mod changed; read its current revision before applying") end
		local spec = util.deepCopy(record.spec)
		if spec.kind == "script" then
			local checked, diagnostic = mods.checkScript(spec)
			if not checked then return H.fail(type(diagnostic) == "string" and diagnostic or "Script mod source did not compile") end
		end
		if not alive or mine ~= operationEpoch or stopped(ctx) or config.accessProblem() then return H.fail("Mod activation stopped during preparation; no source executed") end
		local latest, problem = mods.read(args.id)
		if not latest or latest.revision ~= record.revision or not same(latest.spec, spec) then
			return H.fail(problem or "The mod changed during preparation; read the new revision before applying")
		end
		local appliedSelection = false
		local function aborted()
			if not alive or mine ~= operationEpoch or stopped(ctx) then return true end
			if appliedSelection then
				local state = mods.state()
				return state.activeId ~= args.id or state.activeRevision ~= record.revision
			end
			return false
		end
		local selected, failure = mods.activate(args.id, record.revision, { aborted = aborted })
		if not selected then return H.fail(failure) end
		appliedSelection = true
		if aborted() then mods.disable(); return H.fail("Mod activation stopped; selection was cleared and no script source executed") end
		if env.prepareUiMod then
			local ok, prepared, why = pcall(env.prepareUiMod)
			if not ok or prepared == false then
				runner.stop(); mods.disable()
				return H.fail(why or "The mod interface could not prepare its new appearance; no script source executed")
			end
		end
		if aborted() then mods.disable(); return H.fail("Mod activation stopped during interface preparation; no script source executed") end
		if spec.kind == "script" then
			local started, fault, detail = runner.start(selected, { aborted = aborted })
			if not started then
				mods.disable()
				return { ok = false, text = tostring(fault), data = detail or { applied = false } }
			end
		else
			local cleaned, warning = runner.stop()
			if not cleaned then return { ok = true, text = "Visual mod applied. " .. tostring(warning), data = { applied = true, cleanupIncomplete = true } } end
		end
		return { ok = true, text = "Applied UI mod '" .. spec.name .. "'.", data = { applied = true, id = spec.id, revision = selected.revision, kind = spec.kind } }
	end
	function M.apply(args, ctx)
		if not alive then return H.fail("The client is unloaded") end
		if pending or runner.isBusy() then return H.fail("Another mod application or startup is still in progress") end
		pending = true
		local ok, result = pcall(apply, args or {}, ctx)
		pending = false
		if not ok then
			pcall(runner.stop); pcall(mods.disable)
			return H.fail("Mod activation failed. Selection was cleared and registered cleanup was requested; arbitrary or native effects may remain.")
		end
		return result
	end
	function M.disable()
		operationEpoch = operationEpoch + 1
		local cleaned, cleanupWhy = runner.stop()
		local disabled, warning, detail = mods.disable()
		if runner.isBusy() then warning = (warning and warning .. " " or "") .. "Already-running mod callbacks or native work are still outstanding; wait for them to finish before reloading or applying another mod." end
		if env.prepareUiMod then
			local ok, prepared = pcall(env.prepareUiMod)
			if not ok or prepared == false then warning = (warning and warning .. " " or "") .. "The interface could not rebuild; use safe mode to recover it." end
		end
		return { ok = disabled == true, text = "UI mods disabled."
			.. (warning and " " .. tostring(warning) or "") .. (not cleaned and " " .. tostring(cleanupWhy) or ""),
			data = detail or { persisted = false } }
	end
	dispose.add(function() alive = false; operationEpoch = operationEpoch + 1 end, "mod application lifetime")
	return M
end
