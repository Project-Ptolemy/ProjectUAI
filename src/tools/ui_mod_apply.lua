return function(env)
	return {
		name = "ui_mod_apply", group = "ui_mods", risk = "danger", timeout = 30,
		description = "Apply one exact saved UI mod revision directly under normal tool permissions. Allow everything applies without an extra question or preview dialog. Script source executes with full UAI/Roblox/executor access and owns registered cleanup; it is not sandboxed. Import/save stages disabled data. Read current id/revision before applying; preflight compilation, changed-source checks, cancellation and safe-mode recovery remain enforced. Authorized Full access workers may use this action within their parent's scope.",
		parameters = { type = "object", properties = {
			id = { type = "string", minLength = 1, maxLength = 64, description = "Exact saved mod ID from ui_mod_list/read." },
			expected_revision = { type = "string", minLength = 1, maxLength = 512, description = "Exact current revision from ui_mod_read." },
		}, required = { "id", "expected_revision" } },
		run = function(args, ctx) return env.require("agent/ui_mod_activation").apply(args, ctx) end,
	}
end
