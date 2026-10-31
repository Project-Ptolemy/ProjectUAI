-- Diagnostics: frame rate, memory, and what the place is actually made of.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local H = env.require("tools/helpers")
	local scan = env.require("runtime/instance_scan")

	return {
		{
			name = "performance",
			examples = { { title = "Sample current performance", arguments = { sample = 1 },
				note = "Compare equivalent samples before and after a change; one sample does not establish a long-term trend." } },
			risk = "read",
			description = "Measure frame rate over a short sample and report memory and network stats.",
			parameters = {
				type = "object",
				properties = {
					sample = { type = "number", description = "Seconds to sample the frame rate, 0.2-3. Default 1.", minimum = 0.2, maximum = 3 },
				},
				required = {},
			},
			run = function(args, ctx)
				local sample = util.clamp(tonumber(args.sample) or 1, 0.2, 3)
				local frames, elapsed, fastest, slowest, alive = 0, 0, math.huge, 0, true
				-- Counting Heartbeat deltas measures real frames rather than dividing
				-- by a clock read, which on a stuttering client reads very differently.
				local connection = env.run.Heartbeat:Connect(function(delta)
					if not alive or type(delta) ~= "number" or delta ~= delta or delta <= 0 or delta == math.huge then return end
					frames = frames + 1
					elapsed = elapsed + delta
					fastest, slowest = math.min(fastest, delta), math.max(slowest, delta)
				end)
				local release = env.require("runtime/dispose").add(function() alive = false; connection:Disconnect() end, "tool performance sample")
				local start = clock.ms()
				local waited, why = pcall(function()
					while alive and clock.since(start) < sample * 1000 and not (ctx and ctx.aborted and ctx.aborted()) do clock.wait(0.05) end
				end)
				local stopped = not alive or (ctx and ctx.aborted and ctx.aborted())
				release()
				if not waited then return H.fail("sampling failed: " .. tostring(why)) end
				if stopped then return { ok = false, text = "Performance sample cancelled; listener released.", data = { status = "aborted", frames = frames } } end

				local rows = {
					{ "FPS", elapsed > 0 and string.format("%.1f", frames / elapsed) or "unknown" },
					{ "Frames sampled", tostring(frames) },
					{ "Sample duration", string.format("%.3fs", elapsed) },
				}
				if frames > 0 then rows[#rows + 1] = { "Frame time", string.format("%.2fms average, %.2fms fastest, %.2fms slowest", elapsed * 1000 / frames, fastest * 1000, slowest * 1000) } end

				local stats = env.services.Stats
				local okMemory, memory = pcall(function() return stats:GetTotalMemoryUsageMb() end)
				if okMemory then rows[#rows + 1] = { "Memory", string.format("%.0f MB", memory) } end
				for _, field in ipairs({ "DataReceiveKbps", "DataSendKbps", "HeartbeatTimeMs", "PhysicsStepTimeMs", "InstanceCount" }) do
					local ok, value = pcall(function() return stats[field] end)
					if ok and type(value) == "number" then
						rows[#rows + 1] = { field, string.format("%.2f", value) }
					end
				end

				local okPing, ping = pcall(function()
					return stats.Network.ServerStatsItem["Data Ping"]:GetValue()
				end)
				if okPing and type(ping) == "number" then
					rows[#rows + 1] = { "Ping", string.format("%.0f ms", ping) }
				end

				return { text = H.keyValues(rows), data = { frames = frames, elapsedSeconds = elapsed, fps = frames > 0 and frames / elapsed or nil, minFrameMs = frames > 0 and fastest * 1000 or nil, maxFrameMs = frames > 0 and slowest * 1000 or nil } }
			end,
		},
		{
			name = "class_counts",
			risk = "read",
			description = "Count instances by class under a subtree. Good for sizing up an unfamiliar place before walking it.",
			parameters = {
				type = "object",
				properties = {
					root = { type = "string", description = "Where to count. Defaults to Workspace." },
					limit = { type = "integer", description = "Classes to list, 1-40. Default 20.", minimum = 1, maximum = 40 },
					offset = { type = "integer", minimum = 1 },
				},
				required = {},
			},
			run = function(args, ctx)
				local root, err = H.resolve(args.root or "Workspace")
				if not root then return H.fail(err) end

				local counts, total = {}, 0
				local scanned = scan.descendants(root, ctx, function(node)
					total = total + 1
					counts[node.ClassName] = (counts[node.ClassName] or 0) + 1
				end, 20000)
				local note = not scanned.complete and ("\nScan incomplete: " .. tostring(scanned.reason or "unreadable objects") .. ". Counts are lower bounds.") or ""

				local rows = {}
				for class, count in pairs(counts) do rows[#rows + 1] = { class = class, count = count } end
				table.sort(rows, function(a, b)
					if a.count ~= b.count then return a.count > b.count end
					return a.class < b.class
				end)

				if total == 0 then return H.pathOf(root) .. (scanned.complete and " is empty." or " has no readable counted descendants.") .. note end
				local result = H.page(rows, args, string.format("%s contains %s across %d classes.%s", H.pathOf(root), util.pluralise(total, "instance"), #rows, note), function(row)
						return string.format("%-28s %s", row.class, util.formatNumber(row.count))
					end, 20, 40)
				if result.data then result.data.complete, result.data.scanned = scanned.complete, scanned.scanned end
				if scanned.reason == "aborted" then result.ok = false end
				return result
			end,
		},
		{
			name = "client_status",
			risk = "read",
			description = "Report the agent's own state: provider, model, token spend this session, context size, host capabilities and how many tools are available.",
			parameters = { type = "object", properties = util.emptyObject(), required = {} },
			run = function(_, ctx)
				local caps = env.require("runtime/caps")
				local usage = env.require("agent/usage")
				local providers = env.require("provider/registry")
				local registry = env.require("agent/registry")
				local permissions = env.require("agent/permissions")
				local ua = env.require("net/ua")

				local record = providers.active()
				local stats = registry.stats()
				local owner = ctx and ctx.session or {}
				local offered = #registry.definitions({ only = owner.toolFilter, groups = owner.toolGroups, exclude = owner.toolExclude })
				local rows = {
					{ "Provider", record and (record.label .. " (" .. record.id .. ")") or "none configured" },
					{ "Model", record and record.model or "-" },
					{ "Identity", ua.enabled() and ua.userAgent() or "client identity disabled" },
					{ "Transport", caps.http .. (caps.uaSupported and "" or " (cannot set User-Agent)") },
					{ "Permissions", permissions.mode() },
					{ "Tools", string.format("%d offered to this conversation, %d registered, %d missing host capabilities", offered, stats.total, #stats.unavailable) },
					{ "Loaded client tokens", usage.line() },
				}
				if ctx and ctx.session then
					local contextStats = ctx.session.ctx.stats()
					rows[#rows + 1] = { "Context", string.format("%d messages, about %s tokens, %d compaction(s)",
						contextStats.messages, util.formatNumber(contextStats.tokens), contextStats.compactions) }
				end
				return H.keyValues(rows)
			end,
		},
	}
end
