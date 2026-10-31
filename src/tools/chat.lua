return function(env)
	local util = env.require("runtime/util")
	local chat = env.require("runtime/gamechat")
	local H = env.require("tools/helpers")
	local tools = {
		{
			name = "chat_send", risk = "write",
			description = "Send a message into Roblox chat. Reports a failure if no channel is available.",
			parameters = { type = "object", properties = {
				message = { type = "string", minLength = 1, maxLength = 800, description = "Message, at most 200 Unicode code points (800 UTF-8 bytes)." },
				channel = { type = "string", description = "Channel name; defaults to RBXGeneral. All/Team aliases supported." },
			}, required = { "message" } },
			run = function(args)
				for _, job in ipairs(env.require("runtime/chatloops").running()) do
					if job.kind == "agent" and job.channel == chat.channel(args.channel) then
						return H.fail("chat_agent " .. job.id .. " owns this channel's replies. Stop it with chat_loop_stop before sending manually.")
					end
				end
				local ok, channel = chat.send(args.message, args.channel)
				if not ok then return H.fail(channel) end
				return "Sent to chat [" .. channel .. "]: " .. args.message
			end,
		},
		{
			name = "chat_history", risk = "read", description = "Read recent in-game chat in chronological pages. Continue backward with nextBeforeSequence and identical filters. History retains 100 messages; older evicted messages are unavailable.",
			examples = { { title = "Read the latest chat", arguments = { limit = 10 },
				note = "Continue older pages with the returned nextBeforeSequence; do not guess a cursor." } },
			parameters = { type = "object", properties = {
				limit = { type = "integer", minimum = 1, maximum = 50 },
				sender = { type = "string", description = "Case-insensitive sender substring." },
				channel = { type = "string", description = "Optional channel filter; All/Team aliases are supported." },
				before_sequence = { type = "integer", minimum = 1, description = "Read older messages before this exclusive sequence; omit for latest messages." },
			}, required = {} },
			run = function(args)
				local lines, oldest, more, bytes = {}, nil, false, 0
				local sender = util.trim(args.sender or ""):lower()
				local channel = args.channel and chat.channel(args.channel)
				local limit = H.limit(args.limit, 20, 50)
				local budget = H.resultBudget() - 320
				for index = #chat.history, 1, -1 do
					local entry = chat.history[index]
					if (not args.before_sequence or entry.sequence < args.before_sequence) and (not channel or entry.channel == channel)
						and (sender == "" or entry.sender:lower():find(sender, 1, true)) then
						local line = string.format("[%s] <%s>: %s", entry.channel, entry.sender, entry.text)
						if #lines >= limit or bytes + #line + 1 > budget then
							if #lines == 0 then return H.fail("one chat message exceeds the result budget; increase it before reading this page") end
							more = true; break
						end
						table.insert(lines, 1, line); bytes, oldest = bytes + #line + 1, entry.sequence
					end
				end
				return { text = #lines == 0 and "No recent in-game chat messages recorded." or table.concat(lines, "\n"),
					data = { count = #lines, nextBeforeSequence = more and oldest or nil, oldestRetainedSequence = chat.history[1] and chat.history[1].sequence, eof = not more } }
			end,
		},
	}
	for _, tool in ipairs(env.require("tools/chatloops")) do tools[#tools + 1] = tool end
	return tools
end
