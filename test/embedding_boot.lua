-- Embedding boot/lifetime contracts against the generated native bundle.
-- Run after reviewing and building: luajit test/embedding_boot.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, luau, json = require("env"), require("luau"), require("json")
local file = assert(io.open("dist/uai.lua", "rb"))
local source = file:read("*a"); file:close()
local passed, failed = 0, 0
local function check(label, value)
	assert(value, label)
	passed = passed + 1
end
local function case(name, fn)
	local ok, why = pcall(fn)
	if ok then print("ok " .. name) else failed = failed + 1; print("FAIL " .. name .. ": " .. tostring(why)) end
end
local function fixture(context)
	local h = envMock.new({ context = context })
	local nativeNew = h.sandbox.Instance.new
	h.screensCreated = 0
	h.sandbox.Instance = { new = function(class, parent)
		if class == "ScreenGui" then h.screensCreated = h.screensCreated + 1 end
		return nativeNew(class, parent)
	end }
	return h
end
local function boot(h, context, build, failure)
	local body = source
	if build then body = body:gsub('local __UAI_BUILD = "[^"]+"', 'local __UAI_BUILD = "' .. build .. '"', 1) end
	if failure then
		local changed
		body, changed = body:gsub('handle%.sdk = env%.require%("embedding/sdk"%)%.attach%(handle%)',
			'env.require("runtime/dispose").add(env.context.onDispose, "boot failure fixture"); error("simulated SDK startup failure", 0)', 1)
		assert(changed == 1, "startup failure fixture must target the current SDK attachment")
	end
	local chunk, problems = luau.load(body, "embedding-boot", { entry = true })
	assert(chunk, problems and problems[1] and problems[1].msg)
	setfenv(chunk, h.sandbox)
	local handle = chunk(context)
	h.settle(1)
	return handle
end
local function liveScreens(h)
	local count = 0
	for _, item in ipairs(h.coreGui:GetChildren()) do if item:IsA("ScreenGui") then count = count + 1 end end
	return count
end
local function clean(h, client)
	client.destroy(); h.settle(1)
	check("cleanup releases all screens", liveScreens(h) == 0)
	check("cleanup does not fail", not client.cleanupFailed)
	check("callbacks have no asynchronous errors", #h.errors() == 0)
end

case("UI-free boot runs a real turn and exposes host services without presentation", function()
	local context = { ui = false, reuse = true, prompt = "Host-owned assistant" }
	local h = fixture(context)
	h.http.handler = function(request)
		if request.url:find("/chat/completions", 1, true) then
			return { StatusCode = 200, Body = json.encode({ model = "embedding-fixture", choices = {
				{ message = { role = "assistant", content = "The host turn completed." }, finish_reason = "stop" },
			}, usage = { prompt_tokens = 8, completion_tokens = 5 } }) }
		end
		return { StatusCode = 200, Body = '{"data":[]}' }
	end
	local client = assert(boot(h, context))
	check("UI-free boot never creates a screen", h.screensCreated == 0 and not client.uiMounted and client.app == nil)
	check("standard app and boot modules remain unloaded", client.env.loadedModules["ui/app"] == nil and client.env.loadedModules["ui/boot"] == nil)
	check("host services are directly exposed", client.hooks == client.env.require("agent/hooks") and client.permissions == client.env.require("agent/permissions"))
	check("SDK attaches to every client", type(client.sdk) == "table")
	check("hide does not mount the app", client.hide() and h.screensCreated == 0)
	local record = client.providers.blank("custom")
	record.label, record.baseUrl, record.apiKey = "Embedding fixture", "https://embedding.test/v1", "fixture-key"
	record.model, record.models, record.stream = "embedding-fixture", { "embedding-fixture" }, false
	assert(client.providers.save(record))
	local reply
	local session = client.sessions.current()
	assert(session.send("Read the host status", function(text) reply = text end))
	h.settle(3)
	check("UI-free turns deliver final responses", reply == "The host turn completed." and not session.busy)
	check("ordinary turn and cleanup sweep never load the app", h.screensCreated == 0 and client.env.loadedModules["ui/app"] == nil)
	local before = session.id
	local reused = boot(h, { reuse = true, prompt = "This context is not adopted" })
	check("explicit reuse returns the same unmounted client and preserves context", reused == client and reused.env.context == context and h.screensCreated == 0)
	check("reuse retains the selected conversation", reused.sessions.current().id == before)
	clean(h, client)
	check("unloaded handles cannot remount or send", not client.show() and not client.toggle() and not client.openSession(before) and not client.ask("late"))
end)

case("host permission and question listeners work without the standard app", function()
	local h = fixture(); local client = assert(boot(h, { ui = false, reuse = true }))
	local session = client.sessions.current()
	local approvals, questions, writes = 0, 0, 0
	local off = session.events:connect(function(event)
		if event.kind == "permission:ask" then approvals = approvals + 1; event.resolve(true, false) end
		if event.kind == "ask:user" then questions = questions + 1; event.resolve("Keep the current settings") end
	end)
	assert(client.tools.register({ name = "embedding_fixture_write", group = "embedding", risk = "write",
		description = "Apply a harmless fixture write", run = function() writes = writes + 1; return "Applied" end }))
	local result, answer
	h.sandbox.task.spawn(function()
		result = client.tools.dispatch({ id = "fixture-write", name = "embedding_fixture_write", arguments = "{}" }, session.toolContext())
		answer = client.tools.dispatch({ id = "fixture-question", name = "ask_user", arguments = json.encode({ question = "Keep the settings?" }) }, session.toolContext())
	end)
	h.settle(3)
	check("a host can resolve live permission requests", result and result.ok and approvals == 1 and writes == 1)
	check("a host can answer questions through their event callback", answer and answer.ok and questions == 1 and answer.text:find("Keep the current settings", 1, true))
	check("request handling creates no presentation", h.screensCreated == 0 and client.env.loadedModules["ui/app"] == nil)
	off(); clean(h, client)
end)

case("explicit show and openSession lazily mount one normal application", function()
	local h = fixture(); local client = assert(boot(h, { ui = false, reuse = true }))
	check("invalid conversation never mounts", not client.openSession("absent") and h.screensCreated == 0)
	local session = client.sessions.newThread({ title = "Host conversation" })
	check("opening a conversation mounts and selects it", client.openSession(session.id) and client.uiMounted and client.app ~= nil and client.sessions.activeId == session.id)
	check("lazy mount creates only the app screen", h.screensCreated == 1 and liveScreens(h) == 1)
	client.hide()
	check("hiding retains the mounted app", client.uiMounted and not client.app.window.visible)
	check("show selects the requested panel", client.show("providers") and client.app.panel == "providers" and client.app.window.visible)
	client.toggle()
	check("toggle hides without reconstructing", not client.app.window.visible and h.screensCreated == 1)
	client.toggle()
	check("toggle shows the existing app", client.app.window.visible and h.screensCreated == 1)
	clean(h, client)
end)

case("UI-free updates preserve context and defer active work without UI", function()
	local context = { ui = false, reuse = true, prompt = "Persistent host context" }
	local h = fixture(); local first = assert(boot(h, context))
	local session = first.sessions.current()
	session.ctx.pushUser("Retain across a changed build")
	session.emit("user", { text = "Retain across a changed build" })
	local id = session.id
	local nextClient = assert(boot(h, nil, "embedding-next-build"))
	check("changed build replaces an idle UI-free client", nextClient ~= first and not first.alive and nextClient.alive)
	check("replacement preserves UI-free context and conversation", nextClient.env.context == context and nextClient.sessions.threads[id] and h.screensCreated == 0)
	local active = nextClient.sessions.current(); active.busy = true
	local blocked = boot(h, nil, "embedding-busy-build")
	check("busy UI-free update keeps existing work alive", blocked == nextClient and nextClient.alive and active.busy)
	check("reload notices use the console without loading UI", #h.console.warnings > 0 and h.screensCreated == 0 and nextClient.env.loadedModules["ui/app"] == nil)
	active.busy = false
	clean(h, nextClient)
end)

case("default boot and legacy same-build toggle remain available", function()
	local h = fixture(); local client = assert(boot(h))
	check("default startup mounts the standard application", client.uiMounted and client.app and client.app.window.visible and liveScreens(h) == 1)
	check("reuse suppresses the default toggle", boot(h, { reuse = true }) == client and client.app.window.visible)
	check("unqualified rerun keeps legacy toggle behavior", boot(h) == client and not client.app.window.visible)
	clean(h, client)
end)

case("startup failures drain runtime cleanup with and without a mounted app", function()
	for _, ui in ipairs({ false, true }) do
		local h, drained = fixture(), 0
		local client = boot(h, { ui = ui, onDispose = function() drained = drained + 1 end }, nil, true)
		h.settle(7)
		check("failed startup returns no published handle", client == nil and h.sandbox.UAI == nil)
		check("failed startup drains registered cleanup", drained == 1)
		check("failed startup releases screen trees", liveScreens(h) == 0)
		check("failed startup callbacks settle cleanly", #h.errors() == 0)
		if not ui then check("UI-free failure creates no boot indicator", h.screensCreated == 0) end
	end
end)

print(string.format("Embedding boot: %d checks, %d failed cases", passed, failed))
if failed > 0 then os.exit(1) end
