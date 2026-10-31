-- Same-size attachment edits must not silently replace what the user attached.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Attachment identity")
local check, case = suite.check, suite.case
local function slowCpu(f)
	local elapsed = 0
	f.h.sandbox.os = setmetatable({ clock = function() elapsed = elapsed + 0.025; return elapsed end }, { __index = os })
end
case("file fingerprints cover exact bytes and survive draft and queue recovery", function()
	local f = F.new(); local identity = f.env.require("runtime/attachment_identity")
	local entry = f.env.require("runtime/attachments").describe("pastes/test.lua", "print('a')", "test.lua")
	check("digest is standard SHA-256", identity.digest("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
	check("original bytes match", identity.matches(entry, "print('a')"))
	check("same-size changed bytes rejected", not identity.matches(entry, "print('b')"))
	local snapshot = assert(f.env.require("runtime/draft_store").snapshot({ text = "Inspect this", attachments = { entry } }))
	check("draft keeps the fingerprint", snapshot.attachments[1].sha256 == entry.sha256)
	local queue = f.env.require("agent/message_queue").new({ id = "queue", emit = function() end })
	assert(queue.restore({ version = 1, items = { { id = "message", state = "queued", text = "Inspect this", files = { entry }, images = {} } } }))
	check("queue restore keeps fingerprint", queue.snapshot().items[1].files[1].sha256 == entry.sha256)
	f.healthy(); f.close()
end)
case("cooperative hashing matches the million-a SHA-256 vector while other work runs", function()
	local f = F.new(); slowCpu(f)
	local identity = f.env.require("runtime/attachment_identity")
	local clock = f.env.require("runtime/clock"); local ticks, ticksAtCompletion = 0, nil
	local stop = clock.interval(0.02, function() ticks = ticks + 1 end)
	local digest = f.run(function()
		local value = identity.digest(string.rep("a", 1000000))
		ticksAtCompletion = ticks; return value
	end, 5)
	stop()
	check("cooperative digest matches FIPS 180-4", digest == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
	check("hashing gives other scheduled work time before completion", ticksAtCompletion > 0)
	local sha = f.env.require("runtime/credential_sha256")
	check("cancelled progress cannot return a partial digest", sha.digest("abc", function() return false end) == nil)
	check("failed progress cannot return a digest", sha.digest("abc", function() error("cancelled progress") end) == nil)
	local waits, wait = 0, clock.wait
	f.h.sandbox.os.clock = function() return 0 end
	clock.wait = function(...) waits = waits + 1; return wait(...) end
	local fast = f.run(function() return identity.digest(string.rep("a", 65536)) end)
	check("a fast digest has no mandatory frame waits", identity.valid(fast) and waits == 0)
	f.healthy(); f.close()
end)
case("cancelled attachment preparation creates no file and finalizing uploads cannot mutate", function()
	local f = F.new(); slowCpu(f)
	local attachments = f.env.require("runtime/attachments")
	local cancelled = false
	f.env.require("runtime/clock").delay(0.04, function() cancelled = true end)
	local entry, why = f.run(function()
		return attachments.save(string.rep("x", 262144), "cancelled.txt", function() return cancelled end)
	end, 1)
	check("cancelled save returns no reference", entry == nil and why:find("cancelled", 1, true) ~= nil)
	local first
	f.h.sched.spawn(function()
		local result, err = attachments.upload("owner", { uploadId = "yielding-upload", content = string.rep("x", 131072), offset = 0, final = true })
		first = { result = result, error = err }
	end)
	f.h.sched.advance(0.02)
	local extra, reason = attachments.upload("owner", { uploadId = "yielding-upload", content = "extra", offset = 131072, final = true })
	check("finalizing upload refuses concurrent chunks", extra == nil and reason:find("finalized", 1, true) ~= nil)
	attachments.clearUploads("owner"); f.h.sched.advance(0.5)
	check("cleared upload cancels its hash before writing", first and first.result == nil and first.error:find("cancelled", 1, true) ~= nil)
	for path in pairs(f.h.files) do check("cancelled input did not reach paste storage", path:find("UAI/pastes/", 1, true) == nil) end
	f.healthy(); f.close()
end)
suite.finish()
