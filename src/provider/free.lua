-- Explicit installation for the public free provider. The provider-supported
-- `auto` router was verified against live /models and a successful tool call.
-- Startup does not discover models or dispatch inference on the user's behalf.
return function(env)
	local config = env.require("runtime/config")
	local registry = env.require("provider/registry")
	local communityKey = env.require("provider/community_key")
	local dispose = env.require("runtime/dispose")
	local M = {}
	local unsubscribe

	function M.use()
		local access = config.accessProblem()
		if access then return nil, access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return nil, "Unlock the credential vault before changing providers." end
		for _, record in ipairs(registry.list()) do
			if communityKey.isApplied(record) then
				local wasEnabled = record.enabled
				record.enabled = true
				local saved, why = registry.save(record, { force = true })
				if not saved then record.enabled = wasEnabled; return nil, table.concat(why or {}, "; ") end
				if not record.model or record.model == "" then
					local selected, problem = registry.setModel(record.id, "auto")
					if not selected then return nil, problem end
				end
				local selected, problem = registry.setActive(record.id)
				if not selected then return nil, problem end
				return record
			end
		end
		local record = registry.blank("projectuai-free")
		local saved, problems = registry.save(record)
		if not saved then return nil, table.concat(problems or {}, "; ") end
		local selected, problem = registry.setActive(record.id)
		if not selected then return nil, problem end
		return record
	end

	function M.ensure()
		local access = config.accessProblem()
		if access then return registry.active(), access end
		if config.vaultStatus().locked then return registry.active() end
		local list = registry.list()
		if #list == 0 then return nil end
		local selected = config.get("providers.active", "")
		if not registry.get(selected) then
			for _, record in ipairs(list) do
				if record.enabled ~= false then registry.setActive(record.id); return record end
			end
		end
		return registry.active()
	end

	function M.start()
		if unsubscribe then return end
		M.ensure()
		unsubscribe = config.changed:connect(function(path)
			-- Selection repair considers installed providers only. Empty imports,
			-- reset, removal and startup all keep an empty provider list empty.
			if path == nil or path == "providers" then M.ensure() end
		end)
	end

	function M.stop()
		if unsubscribe then unsubscribe(); unsubscribe = nil end
	end

	dispose.add(M.stop, "free provider configuration")
	return M
end
