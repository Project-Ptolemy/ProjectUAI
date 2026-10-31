-- Local, redacted diagnostics for a support report.
return function(env)
	local support = env.require("runtime/support_bundle")

	return {
		{
			name = "support_bundle",
			examples = { { title = "Prepare local diagnostics", arguments = {},
				note = "Creates a redacted local file and returns its path; it does not upload the report." } },
			risk = "write",
			description = "Write a redacted support bundle for this client: version/build, place, capabilities, provider health, permissions, enabled tools, session metadata, recent HTTP failures and logs, UI/device facts. API keys, authorization values, conversation text, file contents and captured payloads are excluded. The file is local; nothing is uploaded.",
			parameters = {
				type = "object",
				properties = {
					destination = { type = "string", maxLength = 512, description = "Workspace path for the JSON bundle; defaults to exports/uai-support-<time>.json." },
				},
				required = {},
			},
			run = function(args)
				local result, why = support.write(args.destination)
				if not result then return { ok = false, text = "Support bundle was not written: " .. tostring(why) } end
				return { text = string.format("Support bundle written to %s (%d bytes). It excludes API keys, conversation text, file contents and captured payloads.",
					tostring(result.path or "the workspace"), result.bytes or 0),
					data = { path = result.path, bytes = result.bytes, verified = result.verified, sections = result.sections } }
			end,
		},
	}
end
