-- Chat agent integration: a subagent-backed loop, using the shipped bundle and
-- yielding transports. Run: luajit test/chat_agent.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, gamechat, json = require("env"), require("gamechat"), require("json")
local passed, failed = 0, 0
local function check(label, condition) assert(condition, label); passed = passed + 1 end
local function scenario(name, fn)
	local ok, err = pcall(fn)
	if ok then print("ok " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(err)) end
end
local function dispatch(app, name, args)
	return app.tools.dispatch({ name = name, arguments = json.encode(args or {}) }, app.sessions.current().toolContext())
end
local function toolNames(request)
	local names = {}
	for _, definition in ipairs(request.tools or {}) do
		local fn = definition["function"] or definition
		names[fn.name] = true
		-- Focused families declare their permitted underlying action names.
		local properties = fn.parameters and fn.parameters.properties
		local actions = properties and properties.name and properties.name.enum
		if fn.name:sub(1, 4) == "uai_" and type(actions) == "table" then
			for _, name in ipairs(actions) do names[name] = true end
		end
	end
	return names
end
local function lastUser(request)
	for index = #request.messages, 1, -1 do
		if request.messages[index].role == "user" then return request.messages[index].content end
	end
end
local function count(haystack, needle)
	local total, from = 0, 1
	while true do
		local at = haystack:find(needle, from, true)
		if not at then return total end
		total, from = total + 1, at + 1
	end
end
local function boot(options)
	options = options or {}
	local h = envMock.new()
	local chat = gamechat(h)
	local requests = {}
	local reply = { text = "Hey! What's up?", delay = 0 }
	local function hasToolResult(payload)
		for _, message in ipairs(payload.messages or {}) do
			if message.role == "tool" then return true end
		end
		return false
	end
	h.http.handler = function(req)
		if req.url:find("/chat/completions", 1, true) or req.url:find("/messages", 1, true) then
			local payload = json.decode(req.body)
			requests[#requests + 1] = payload
			-- A scripted tool call is answered once: after its result is in the
			-- request, the same handler replies with prose instead.
			local calls, text = nil, reply.text
			if reply.toolCalls and not hasToolResult(payload) then
				calls = reply.toolCalls
			else
				text = reply.after or reply.text
			end
			local delay, status = reply.delay, reply.status
			if delay > 0 then h.sandbox.task.wait(delay) end
			if status then return { StatusCode = status, Body = '{"error":{"message":"Unavailable"}}' } end
			local response
			if options.anthropic then
				response = { model = "harness-model", content = { { type = "text", text = text } }, stop_reason = "end_turn",
					usage = { input_tokens = 12, output_tokens = 8 } }
			else
				response = { model = "harness-model", choices = { { message = { role = "assistant", content = text,
					tool_calls = calls }, finish_reason = calls and "tool_calls" or "stop" } },
					usage = { prompt_tokens = 12, completion_tokens = 8 } }
			end
			return { StatusCode = 200, Body = json.encode(response) }
		end
		return { StatusCode = 200, Body = '{"data":[]}' }
	end
	local app = assert(h.boot()); h.settle(1)
	app.config.set("permissions.mode", "full")
	-- This build asks for a credential-storage decision before any provider can be
	-- saved; the fixture chooses reversible storage so it can hold a test key.
	assert(app.config.continueWithoutEncryption())
	h.settle(1)
	-- Startup now installs included Free access. These scenarios deliberately
	-- exercise one chosen fixture provider, or a genuinely empty setup.
	for _, record in ipairs(app.providers.list()) do app.providers.remove(record.id) end
	if not options.noProvider then
		local record = app.providers.blank("custom")
		record.label, record.baseUrl, record.apiKey = "Chat agent test", "https://chatagent.test/v1", "test-key"
		record.model, record.models, record.stream = "harness-model", { "harness-model" }, false
		if options.anthropic then record.api = "anthropic" end
		assert(app.providers.save(record))
		app.providers.setActive(record.id)
	end
	h.settle(1)
	return h, app, chat, app.env.require("runtime/chatloops"), requests, reply
end
local function clean(h, app)
	app.destroy(); h.settle(1)
	check("no asynchronous errors", #h.errors() == 0)
end

scenario("the tool launches a subagent that batches input and keeps its context private", function()
	local h, app, chat, loops, requests, reply = boot()
	local session = app.sessions.current()
	session.ctx.pushUser("PRIVATE_MAIN_CONVERSATION")
	chat.receive("old history", 2, "Alice", nil, "old")
	local result = dispatch(app, "chat_agent", { instructions = "Talk about building games." })
	check("registered write tool starts", result.ok and result.data.id and app.tools.get("chat_agent").risk == "write")
	check("no turn before new chat", #requests == 0 and #chat.sent == 0 and not session.busy)
	check("UI identifies the chat agent", h.textOf(h.byName("ChatLoops")):find("Chat agent", 1, true))
	chat.receive("yo", 2, "Alice", nil, "a")
	chat.receive("let me ask something", 2, "Alice", nil, "b")
	h.settle(3)
	check("one burst makes one turn and one reply", #requests == 1 and #chat.sent == 1)
	check("tagged reply", chat.sent[1].text == "[AGENT] Hey! What's up?")
	local request = requests[1]
	local batch = lastUser(request)
	check("both fresh messages are included once", count(batch, "yo") == 1 and count(batch, "let me ask something") == 1
		and batch:find("Alice", 1, true) ~= nil)
	check("main transcript and old chat are excluded", not json.encode(request):find("PRIVATE_MAIN_CONVERSATION", 1, true)
		and not json.encode(request):find("old history", 1, true))
	check("the worker is a real agent with tools", type(request.tools) == "table" and #request.tools > 0)
	local names = toolNames(request)
	check("it can read chat history and the game", names.chat_history and names.instance_query)
	check("it cannot send chat or start another loop", not names.chat_send and not names.chat_agent and not names.tool_search)
	check("operator instructions reach its brief", request.messages[1].content:find("Talk about building games.", 1, true))
	check("its brief names the speaker and the reply limit", request.messages[1].content:find("Chat operator", 1, true)
		and request.messages[1].content:find("TestPlayer", 1, true))
	local usage = app.env.require("agent/usage")
	check("background turns do not change the user's turn totals", usage.turn.total == 0 and usage.session.total >= 20)
	check("manual sending cannot double-answer", not dispatch(app, "chat_send", { message = "Another reply" }).ok)
	check("another loop cannot duplicate this channel", not dispatch(app, "chat_agent", {}).ok
		and not dispatch(app, "auto_reply", { rules = { { trigger = "yo", response = "Hi" } } }).ok)
	reply.text = "Sure, ask me about your game."
	app.sessions.newThread(); chat.receive("can you help?", 2, "Alice", nil, "c")
	h.settle(7)
	check("switching conversation does not stop the agent", #chat.sent == 2 and loops.list()[1].state == "running")
	check("the worker keeps its own context across turns", requests[2] and json.encode(requests[2]):find("Hey! What's up?", 1, true))
	check("status exposes turns", dispatch(app, "chat_loop_status", { id = result.data.id }).data[1].agent.turns == 2)
	clean(h, app)
end)

scenario("the worker reads the game before answering", function()
	local h, app, chat, loops, requests, reply = boot()
	reply.text, reply.after = "", "The shop closes at 20:00."
	reply.toolCalls = { { id = "lookup", type = "function", ["function"] = { name = "chat_history", arguments = '{"limit":3}' } } }
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("when does the shop close?", 2, "Alice", nil, "a")
	h.settle(4)
	check("the tool call ran and the turn continued", #requests == 2)
	local used = false
	for _, message in ipairs(requests[2].messages) do
		if message.role == "tool" and tostring(message.content):find("Alice", 1, true) then used = true end
	end
	check("the worker saw the tool result", used)
	check("its answer is the chat line", #chat.sent == 1 and chat.sent[1].text == "[AGENT] The shop closes at 20:00.")
	check("one reply completes the turn", loops.list()[1].sent == 1)
	clean(h, app)
end)

scenario("replayed IDs, duplicate text, self echoes, and filtered chat never double-reply", function()
	local h, app, chat, loops, requests = boot()
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("yo", 2, "Alice", nil, "first")
	chat.receive("yo", 2, "Alice", nil, "first")
	chat.receive("YO!", 2, "Alice", nil, "duplicate-text")
	chat.receive("mine", 1, "TestPlayer")
	chat.receive("system", nil, "System")
	chat.receive("other channel", 2, "Alice", "RBXTeam")
	chat.receive("###########", 3, "Bob")
	chat.receive("[AGENT] Hello", 3, "OtherBot")
	h.settle(3)
	check("exactly one input accepted", #requests == 1 and count(lastUser(requests[1]), "yo") == 1 and #chat.sent == 1)
	for index = 1, 110 do chat.receive("system " .. index, nil, "System", nil, "filler" .. index) end
	h.settle(20)
	chat.receive("yo", 2, "Alice", nil, "first")
	chat.receive("YO!", 2, "Alice", nil, "duplicate-text")
	chat.receive("filtered echo", 1, "TestPlayer", nil, "echo")
	h.settle(3)
	check("IDs survive history rollover and cooldown", #requests == 1 and #chat.sent == 1)
	chat.receive("another question", 2, "Alice", nil, "new")
	h.settle(3)
	check("duplicate agent output is suppressed", #requests == 2 and #chat.sent == 1 and loops.list()[1].agent.skipped > 0)
	clean(h, app)
end)

scenario("slow turns are single-flight and queue later messages for one subsequent reply", function()
	local h, app, chat, loops, requests, reply = boot()
	reply.delay = 8
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("first question", 2, "Alice", nil, "a"); h.settle(2)
	for index = 1, 25 do chat.receive("follow-up " .. index, 2, "Alice", nil, "q" .. index) end
	h.settle(6)
	check("only one turn is running", #requests == 1 and #chat.sent == 0 and loops.list()[1].agent.generating)
	check("queue is bounded under load", #loops.list()[1].agent.queue == 20 and loops.list()[1].agent.dropped == 5)
	reply.text = "Here's the follow-up answer."
	h.settle(3)
	check("first result sends once", #requests == 1 and #chat.sent == 1)
	h.settle(14)
	check("later burst sends once", #requests == 2 and #chat.sent == 2)
	check("new batch has each retained message once", count(lastUser(requests[2]), "follow-up ") == 20)
	check("send pacing holds", chat.sent[2].at - chat.sent[1].at >= 5000)
	clean(h, app)
end)

scenario("stop, clear, removal, permission changes, deadline, and unload discard late turns", function()
	for _, action in ipairs({ "stop", "clear", "remove", "disable", "deny", "deadline", "unload" }) do
		local h, app, chat, loops, requests, reply = boot()
		reply.delay = 15
		assert(dispatch(app, "chat_agent", { duration = 10 }).ok)
		chat.receive("hello", 2, "Alice", nil, "a"); h.settle(2)
		check(action .. " has a turn in flight", #requests == 1)
		if action == "stop" then h.click(h.byName("StopChatLoops"))
		elseif action == "clear" then app.sessions.current().clear()
		elseif action == "remove" then app.sessions.remove(app.sessions.current().id)
		elseif action == "disable" then app.tools.setGroupEnabled("chat", false)
		elseif action == "deny" then app.env.require("agent/permissions").setRule("chat_agent", "deny")
		elseif action == "unload" then app.destroy() end
		h.settle(20)
		check(action .. " discards the late answer", #chat.sent == 0 and #loops.running() == 0)
		if action ~= "unload" then clean(h, app) else check("unload stays clean", #h.errors() == 0) end
	end
end)

scenario("a Sending status is a delivered message and a refusal is not", function()
	for _, case in ipairs({ { "Sending", true }, { "Success", true }, { "Floodchecked", false }, { "MessageTooLong", false } }) do
		local h, app, chat, loops = boot()
		local accepted = case[2]
		chat.addChannel("RBXGeneral", function(text)
			if accepted then chat.sent[#chat.sent + 1] = { text = text, channel = "RBXGeneral" } end
			return { Status = h.sandbox.Enum.TextChatMessageStatus[case[1]] }
		end)
		assert(dispatch(app, "chat_agent", {}).ok)
		chat.receive("hi", 2, "Alice", nil, "a"); h.settle(3)
		if accepted then
			check(case[1] .. " counts as sent", #chat.sent == 1 and loops.list()[1].sent == 1 and loops.list()[1].state == "running")
		else
			check(case[1] .. " fails without claiming delivery", #chat.sent == 0 and loops.list()[1].sent == 0
				and loops.list()[1].state == "failed" and tostring(loops.list()[1].reason):find(case[1], 1, true))
		end
		clean(h, app)
	end
end)

scenario("reply normalization is duplicate-safe and UTF-8 stays within one message", function()
	local h, app, chat, loops, requests, reply = boot()
	reply.text = "[AGENT] [AGENT] Hello!"
	assert(dispatch(app, "chat_agent", { count = 2 }).ok)
	chat.receive("hi", 2, "Alice", nil, "a"); h.settle(3)
	check("prefix appears only once", chat.sent[1].text == "[AGENT] Hello!")
	reply.text = " hello. "
	chat.receive("question two", 2, "Alice", nil, "b"); h.settle(7)
	check("case whitespace punctuation variants are suppressed", #chat.sent == 1)
	reply.text = "<skip>"
	chat.receive("nothing to answer", 2, "Alice", nil, "c"); h.settle(7)
	check("skip is never posted", #chat.sent == 1)
	reply.text = string.rep("你好🌟\n", 100)
	chat.receive("question four", 2, "Alice", nil, "d"); h.settle(7)
	check("one bounded unicode message", #chat.sent == 2 and app.env.require("runtime/gamechat").validate(chat.sent[2].text))
	check("no line breaks or broken UTF-8", not chat.sent[2].text:find("\n", 1, true)
		and app.env.require("runtime/util").validUtf8(chat.sent[2].text))
	check("reply cap completes", loops.list()[1].state == "completed" and #requests == 4)
	clean(h, app)
end)

scenario("player scope, startup validation, and provider errors are reported", function()
	local h, app, chat, loops, requests, reply = boot({ noProvider = true })
	check("missing provider rejected", not dispatch(app, "chat_agent", {}).ok and #loops.list() == 0)
	clean(h, app)
	h, app, chat, loops, requests, reply = boot()
	check("bad prefix rejected", not dispatch(app, "chat_agent", { prefix = "bad\nprefix" }).ok)
	check("unknown channel rejected", not dispatch(app, "chat_agent", { channel = "Missing" }).ok)
	check("subagent cannot start an agent", not loops.start("agent", {}, { session = app.sessions.current(), depth = 1 }))
	assert(dispatch(app, "chat_agent", { user_ids = { 2 }, prefix = "" }).ok)
	chat.receive("hello", 3, "Bob"); h.settle(3)
	check("non-target player ignored", #requests == 0)
	reply.status = 401
	chat.receive("hello", 2, "Alice"); h.settle(4)
	check("provider failure is visible and not sent", #requests >= 1 and #chat.sent == 0 and loops.list()[1].state == "failed")
	reply.status, reply.text = nil, "No tag"
	assert(dispatch(app, "chat_agent", { prefix = "", count = 1 }).ok)
	chat.receive("fresh", 2, "Alice"); h.settle(4)
	check("empty prefix supported", chat.sent[1].text == "No tag")
	clean(h, app)
end)

scenario("native Anthropic adapter supports the subagent conversation", function()
	local h, app, chat, loops, requests = boot({ anthropic = true })
	assert(dispatch(app, "chat_agent", { count = 1 }).ok)
	chat.receive("hello", 2, "Alice", nil, "a"); h.settle(4)
	check("native request uses its system field", #requests == 1 and type(requests[1].system) == "string")
	check("native reply delivered once", #chat.sent == 1 and loops.list()[1].state == "completed")
	clean(h, app)
end)

scenario("legacy message IDs and ID-less duplicate events are consumed once", function()
	local h, app, _, loops, requests = boot()
	-- Reboot in a fresh sandbox so the legacy listener is selected at mount time.
	app.destroy()
	local legacy = envMock.new()
	legacy.http.handler = h.http.handler
	local incoming = legacy.Instance.new("TextBox").FocusLost
	local sent = {}
	legacy.services.TextChatService = { ChatVersion = legacy.sandbox.Enum.ChatVersion.LegacyChatService }
	legacy.services.ReplicatedStorage = { FindFirstChild = function(_, name)
		if name == "DefaultChatSystemChatEvents" then return { FindFirstChild = function(_, child)
			if child == "SayMessageRequest" then return { FireServer = function(_, text) sent[#sent + 1] = text end } end
			if child == "OnMessageDoneFiltering" then return { OnClientEvent = incoming } end
		end } end
	end }
	app = assert(legacy.boot()); legacy.settle(1)
	app.config.set("permissions.mode", "full")
	assert(app.config.continueWithoutEncryption())
	legacy.settle(1)
	for _, existing in ipairs(app.providers.list()) do app.providers.remove(existing.id) end
	local record = app.providers.blank("custom")
	record.baseUrl, record.apiKey, record.model = "https://chatagent.test/v1", "test-key", "harness-model"
	assert(app.providers.save(record)); app.providers.setActive(record.id); legacy.settle(1)
	assert(dispatch(app, "chat_agent", { channel = "Team" }).ok)
	incoming:Fire({ Message = "hello", FromSpeaker = "Alice", SpeakerUserId = 2, OriginalChannel = "Team", ID = 42 })
	incoming:Fire({ Message = "hello", FromSpeaker = "Alice", SpeakerUserId = 2, OriginalChannel = "Team", ID = 42 })
	legacy.settle(4)
	check("legacy duplicate id produces one reply", #requests == 1 and #sent == 1)
	for index = 1, 110 do incoming:Fire({ Message = "system " .. index, FromSpeaker = "System", OriginalChannel = "Team" }) end
	legacy.settle(20)
	incoming:Fire({ Message = "hello", FromSpeaker = "Alice", SpeakerUserId = 2, OriginalChannel = "Team", ID = 42 })
	legacy.settle(4)
	check("legacy id survives history eviction", #requests == 1)
	incoming:Fire({ Message = "follow up", FromSpeaker = "Alice", SpeakerUserId = 2, OriginalChannel = "Team" })
	incoming:Fire({ Message = "follow up", FromSpeaker = "Alice", SpeakerUserId = 2, OriginalChannel = "Team" })
	legacy.settle(4)
	check("ID-less duplicate events form one input", #requests == 2
		and count(lastUser(requests[2]), "follow up") == 1)
	check("legacy repeated reply is not sent", #sent == 1)
	clean(legacy, app)
end)

scenario("stopped turns cannot answer for a replacement agent", function()
	local h, app, chat, loops, requests, reply = boot()
	reply.delay = 15
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("old agent", 2, "Alice", nil, "old"); h.settle(2)
	loops.stop()
	reply.delay, reply.text = 0, "Replacement agent reply."
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("new agent", 2, "Alice", nil, "new"); h.settle(20)
	check("only the replacement reply is sent", #requests == 2 and #chat.sent == 1
		and chat.sent[1].text == "[AGENT] Replacement agent reply.")
	check("old generation remains stopped", loops.list()[1].state == "stopped" and loops.list()[2].state == "running")
	clean(h, app)
end)

scenario("the final send rechecks duplicates that arrived while waiting for the shared sender", function()
	local h, app, chat, loops, requests, reply = boot()
	assert(dispatch(app, "auto_chat", { messages = { "Team update" }, channel = "Team", count = 1 }).ok)
	h.settle(1)
	assert(dispatch(app, "chat_agent", {}).ok)
	chat.receive("question", 2, "Alice", nil, "a"); h.settle(3)
	check("the agent waits behind global pacing", #requests == 1 and #chat.sent == 1 and loops.list()[2].pending ~= nil)
	chat.receive("[AGENT] " .. reply.text, 1, "TestPlayer", nil, "manual")
	h.settle(6)
	check("the manual echo prevents a duplicate send", #chat.sent == 1 and loops.list()[2].pending == nil)
	clean(h, app)
end)

scenario("skipped answers have a turn budget", function()
	local h, app, chat, loops, requests, reply = boot()
	reply.text = "<skip>"
	assert(dispatch(app, "chat_agent", { count = 1 }).ok)
	for index = 1, 4 do chat.receive("question " .. index, 2, "Alice", nil, "q" .. index); h.settle(7) end
	check("skip cannot create unbounded turns", #requests == 3 and #chat.sent == 0 and loops.list()[1].state == "completed")
	clean(h, app)
end)

print(string.format("chat agent: %d checks passed, %d scenarios failed", passed, failed))
os.exit(failed > 0 and 1 or 0)
