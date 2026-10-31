-- Explain admission without sending requests or changing key rotation.
return function(env)
	local config = env.require("runtime/config")
	local registry = env.require("provider/registry")
	local keys = env.require("runtime/provider_keys")
	local community = env.require("provider/community_key")
	local health = env.require("provider/health")
	local M = {}
	function M.describe(record)
		if not record then return { state = "missing", message = "Add a provider to get started", ready = false } end
		if record.enabled == false then return { state = "disabled", message = "Disabled", ready = false } end
		if config.accessProblem() or config.vaultStatus().locked then return { state = "locked", message = "Unlock credential storage", ready = false } end
		local problem = registry.protocolProblem(record)
		if problem then return { state = "blocked", message = problem, ready = false } end
		local pool = keys.summary(record)
		if pool.total > 0 and pool.available == 0 then return { state = "paused", message = "No active API key", ready = false } end
		local remaining = health.remaining(record)
		if remaining > 0 then return { state = "cooling", message = health.message(record), ready = true, retryAfterMs = remaining } end
		if community.isApplied(record) then return { state = "community", message = "Community access open", ready = true } end
		if not registry.opencodeKeyOptional(record) and not registry.isCline(record) and (record.authStyle or "bearer") ~= "none" and pool.total == 0 then
			return { state = "key-required", message = "API key required", ready = false }
		end
		return { state = "configured", message = "Configured", ready = true }
	end
	return M
end
