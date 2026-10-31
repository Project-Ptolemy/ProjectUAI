-- Read the durable evidence ledger for the current conversation.
return function(env)
	local evidence = env.require("runtime/evidence")
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")

	return {
		{
			name = "evidence",
			examples = { { title = "Recover syntax-check evidence", arguments = { action = "search", query = "check_luau", limit = 10 },
				note = "Read the returned record ID and continuation pages before relying on older results." } },
			risk = "read",
			needs = { "fs" },
			description = "Read retained tool results for this conversation after compaction. action=list returns compact receipts; action=search filters by tool or text; action=read pages one record's full text, structured data or summary. Offsets are bytes. The ledger never executes captured content.",
			parameters = {
				type = "object",
				properties = {
					action = { type = "string", enum = { "list", "search", "read", "status" } },
					query = { type = "string", description = "Case-insensitive tool name or text filter for list/search." },
					record_id = { type = "string", description = "Evidence id from list/search." },
					section = { type = "string", enum = { "text", "data", "summary" }, description = "Default text." },
					offset = { type = "integer", minimum = 1, description = "1-based row or byte offset." },
					limit = { type = "integer", minimum = 1, maximum = 64000, description = "Rows (default 20) or text bytes (default 4000)." },
				},
				required = { "action" },
			},
			run = function(args, ctx)
				local session = ctx and ctx.session
				if args.action == "status" then
					local state = evidence.state(session)
					return { text = string.format("Evidence ledger: %d record(s), %.1f KiB retained.", state.records or 0, (state.bytes or 0) / 1024), data = state }
				elseif args.action == "list" or args.action == "search" then
					if args.action == "search" and util.trim(tostring(args.query or "")) == "" then return H.fail("query is required for search") end
					local data, why = evidence.list(session, { query = args.query, offset = args.offset, limit = args.limit })
					if not data then return H.fail(why) end
					local lines = {}
					for index, item in ipairs(data.items) do
						lines[#lines + 1] = string.format("%d. %s [%s] %d B %s", index, item.id, tostring(item.tool),
							item.bytes or 0, util.ellipsis(tostring(item.preview or ""), 120))
					end
					local text = #lines > 0 and table.concat(lines, "\n") or "No retained evidence matches this conversation."
					if data.nextOffset then text = text .. "\ncontinue with offset=" .. data.nextOffset end
					return { text = text, data = data }
				elseif args.action == "read" then
					if not args.record_id then return H.fail("record_id is required for read") end
					local page, why = evidence.read(session, args.record_id, args.section, args)
					if not page then return H.fail(why) end
					local result = H.readSlice("Evidence " .. page.id .. " / " .. page.section, page.text,
						{ offset = args.offset, limit = math.min(args.limit or 4000, 64000) }, 4000)
					result.data = result.data or {}
					result.data.evidence = { id = page.id, tool = page.tool, section = page.section, truncated = page.truncated }
					return result
				end
				return H.fail("unknown action")
			end,
		},
		{
			name = "evidence_clear",
			risk = "write",
			needs = { "fs" },
			description = "Delete retained tool evidence for this conversation. Does not delete files, conversations or captured records.",
			parameters = { type = "object", properties = {}, required = {} },
			run = function(_, ctx)
				local before = evidence.state(ctx and ctx.session)
				evidence.clear(ctx and ctx.session)
				local after = evidence.state(ctx and ctx.session)
				return { text = string.format("Evidence cleared: %d record(s), %.1f KiB removed.", before.records or 0,
					((before.bytes or 0) - (after.bytes or 0)) / 1024), data = { before = before, after = after } }
			end,
		},
	}
end
