-- A host-owned model and two tools. No GUI, network request, or provider setup.
-- Return an installer so the same module works in a downloaded script or ModuleScript.
return function(uai)
	assert(type(uai) == "table" and uai.alive, "Load a live UAI client first")
	local existing = uai.env.context.workbenchExample
	if existing then return existing end
	assert(not uai.tools.get("workbench_status") and not uai.tools.get("workbench_configure"),
		"The workbench tool names are already registered by another integration")

	local changed = uai.env.require("runtime/signal").new("workbench:changed")
	local state = { title = "My workbench", enabled = true, batchSize = 5 }
	local alive = true
	local model = {}
	function model.read()
		return { title = state.title, enabled = state.enabled, batchSize = state.batchSize }
	end
	function model.update(patch)
		if not alive then return false, "The workbench was unloaded" end
		if type(patch) ~= "table" then return false, "Expected a settings table" end
		-- Validate domain inputs too: the manual UI also calls this function.
		for key in pairs(patch) do
			if key ~= "title" and key ~= "enabled" and key ~= "batchSize" then
				return false, "Unknown setting: " .. tostring(key)
			end
		end
		local title = patch.title == nil and state.title or patch.title
		local enabled = patch.enabled
		if enabled == nil then enabled = state.enabled end
		local batch = patch.batchSize == nil and state.batchSize or patch.batchSize
		if type(title) ~= "string" or #title < 1 or #title > 80 or not title:find("%S") then
			return false, "Title must contain 1-80 bytes and some non-whitespace text"
		end
		if type(enabled) ~= "boolean" then return false, "Enabled must be a boolean" end
		if type(batch) ~= "number" or batch ~= batch or batch < 1 or batch > 20 or batch % 1 ~= 0 then
			return false, "Batch size must be an integer from 1 to 20"
		end
		state = { title = title, enabled = enabled, batchSize = batch }
		changed:fire(model.read())
		return true, model.read()
	end
	function model.subscribe(callback) return changed:connect(callback) end

	assert(uai.tools.register({
		name = "workbench_status", group = "workbench", risk = "read",
		description = "Read this host script's example workbench title, enabled state and batch size. This is local example state, not a game inventory.",
		parameters = { type = "object", properties = {}, required = {} },
		run = function()
			if not alive then return { ok = false, text = "The workbench was unloaded" } end
			local value = model.read()
			return { text = string.format("%s: %s; batch size %d", value.title,
				value.enabled and "enabled" or "disabled", value.batchSize), data = value }
		end,
	}))
	assert(uai.tools.register({
		name = "workbench_configure", group = "workbench", risk = "write",
		description = "Update the host's example workbench settings. Only changes local example state. Read workbench_status to inspect the current values.",
		parameters = {
			type = "object", additionalProperties = false,
			properties = {
				title = { type = "string", minLength = 1, maxLength = 80 },
				enabled = { type = "boolean" },
				batchSize = { type = "integer", minimum = 1, maximum = 20 },
			}, required = {},
		},
		run = function(args, ctx)
			if ctx.aborted() then return { ok = false, text = "Stopped before changing the workbench" } end
			local ok, value = model.update(args)
			if not ok then return { ok = false, text = value } end
			return { text = "Workbench settings updated.", data = value }
		end,
	}))

	-- This is our own namespace in the context table, not a built-in UAI option.
	uai.env.context.workbenchExample = model
	uai.env.require("runtime/dispose").add(function()
		alive = false
		changed:clear()
		if uai.env.context.workbenchExample == model then uai.env.context.workbenchExample = nil end
	end, "embedding workbench model")
	return model
end
