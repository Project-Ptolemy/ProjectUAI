-- Large conversation histories must not be rewritten just to unload the client.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F, envMock = require("workspace_fixture"), require("env")
local suite = F.suite("Session unload")
local case, check = suite.case, suite.check

case("64 saved conversations unload without serialization, writes or list events", function()
	local h = envMock.new({ context = { ui = false } })
	local uai = assert(h.boot())
	local sessions = uai.sessions
	while #sessions.list() < 64 do assert(sessions.newThread({ activate = false })) end
	for _, session in ipairs(sessions.list()) do
		local text = string.rep("Saved history. ", 600)
		session.ctx.pushUser(text); session.emit("user", { text = text })
		assert(session.persist())
	end
	local function verifyUnload(host, handle)
		local encoded, writes, notifications = 0, 0, 0
		local disk = {}
		for _, session in ipairs(handle.sessions.list()) do
			local snapshot = session.ctx.serialise
			session.ctx.serialise = function() encoded = encoded + 1; return snapshot() end
			local path = "UAI/sessions/" .. session.id .. ".json"
			disk[path] = assert(host.files[path])
		end
		local fs = handle.env.require("runtime/fsx")
		local write = fs.writeJson
		fs.writeJson = function(path, value)
			if path:match("^sessions/") then writes = writes + 1 end
			return write(path, value)
		end
		handle.sessions.listChanged:connect(function() notifications = notifications + 1 end)
		handle.destroy()
		check("saved history is never reserialized", encoded == 0)
		check("saved history is never rewritten", writes == 0)
		check("unload does not refresh the conversation list", notifications == 0)
		for path, body in pairs(disk) do assert(host.files[path] == body, "history changed: " .. path) end
		check("all 64 saved histories remain intact", #handle.sessions.list() == 64)
		check("shutdown completes cleanly and only once", not handle.cleanupFailed and handle.destroy() == 0)
	end
	verifyUnload(h, uai)
	local restored = envMock.new({ context = { ui = false } })
	for path, value in pairs(h.files) do restored.files[path] = value end
	for path, value in pairs(h.folders) do restored.folders[path] = value end
	local nextClient = assert(restored.boot())
	check("all saved sessions restore", #nextClient.sessions.list() == 64)
	verifyUnload(restored, nextClient)
end)

case("dirty histories and pending follow-ups save once despite repeated cleanup", function()
	local f = F.new()
	local providers = f.env.require("provider/registry")
	local provider = providers.blank("custom")
	provider.id, provider.label = "unload-fixture", "Unload fixture"
	provider.baseUrl, provider.apiKey, provider.model = "https://unload.fixture/v1", "fixture-key", "fixture-model"
	assert(providers.save(provider, { force = true }))
	local sessions, fs = f.env.require("agent/session"), f.env.require("runtime/fsx")
	local changed = assert(sessions.newThread({ id = "changed" }))
	local failed = assert(sessions.newThread({ id = "failed-save" }))
	local active = assert(sessions.newThread({ id = "active" }))
	assert(changed.persist()); assert(failed.persist())
	changed.emit("user", { text = "Unsaved history" })
	local original = fs.writeJson
	fs.writeJson = function(path, value)
		if path == "sessions/failed-save.json" then return false, "fixture write failure" end
		return original(path, value)
	end
	assert(failed.rename("Keep this rename"))
	fs.writeJson = original
	f.loaded["agent/loop"] = { run = function() f.h.sched.wait(1); return "Late completion" end }
	assert(active.send("Original request"))
	local cancelled = 0
	assert(active.send("Keep this follow-up", function(_, result)
		if result.status == "cancelled" then cancelled = cancelled + 1 end
	end))
	active.emit("assistant:text", { text = "Partial response" })
	local contexts = { changed.toolContext(), failed.toolContext(), active.toolContext() }
	local writes, notifications = {}, 0
	fs.writeJson = function(path, value)
		if path:match("^sessions/") then
			for _, context in ipairs(contexts) do assert(context.aborted(), "save started before all workers were stopped") end
			assert(not active.send("Must not start"), "unload admitted work")
			writes[path] = (writes[path] or 0) + 1
		end
		return original(path, value)
	end
	sessions.listChanged:connect(function() notifications = notifications + 1 end)
	-- SDK request cleanup can abort the same session before its module cleanup.
	f.env.require("runtime/dispose").add(active.abort, "extra request cleanup")
	sessions.beginShutdown(); f.close(); active.abort()
	check("only changed histories save, once each", writes["sessions/changed.json"] == 1 and writes["sessions/failed-save.json"] == 1 and writes["sessions/active.json"] == 1)
	local saved = f.h.json.decode(f.h.files["UAI/sessions/active.json"])
	check("pending follow-up survives repeated aborts on disk", #saved.queue.items == 1 and saved.queue.items[1].text == "Keep this follow-up")
	check("pending callback is cancelled exactly once", cancelled == 1 and not active.hasQueued())
	check("failed earlier save is retried on unload", f.h.json.decode(f.h.files["UAI/sessions/failed-save.json"]).title == "Keep this rename")
	check("cleanup emits no list redraws", notifications == 0)
	f.h.sched.advance(2)
	check("late worker completion cannot overwrite the saved queue", writes["sessions/active.json"] == 1 and cancelled == 1)
	f.healthy()
end)

case("64 unsaved conversations yield between bounded save batches", function()
	local f = F.new()
	local sessions, fs, clock = f.env.require("agent/session"), f.env.require("runtime/fsx"), f.env.require("runtime/clock")
	for index = 1, 64 do assert(sessions.newThread({ id = "unsaved-" .. index, activate = false })) end
	local elapsed, writes, frames = 0, 0, {}
	clock.ms = function() return elapsed end
	local original = fs.writeJson
	fs.writeJson = function(path, value)
		if path:match("^sessions/") then
			writes = writes + 1; elapsed = elapsed + 5
			frames[f.h.sched.now] = true
			for _, session in pairs(sessions.threads) do assert(session.aborted(), "all sessions must stop before saving") end
		end
		return original(path, value)
	end
	f.run(f.close, 1)
	local count = 0; for _ in pairs(frames) do count = count + 1 end
	check("every unsaved conversation is preserved once", writes == 64)
	check("save work spans frames instead of monopolizing one frame", count >= 16)
	check("new sessions cannot start during or after shutdown", sessions.newThread() == nil)
	f.healthy()
end)

suite.finish()
