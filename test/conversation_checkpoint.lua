-- A yielding older checkpoint cannot overwrite a newer checkpoint out of order.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Conversation checkpoint")
local check, case = suite.check, suite.case
case("overlapping writes serialize and preserve pending dirty state", function()
	local f = F.new(); local checkpoint = f.env.require("agent/checkpoint")
	local session = { persistenceRevision = 1, persistenceDirty = true }
	local writes, delayed, firstResult = {}, 0, nil
	f.h.sched.spawn(function()
		firstResult = checkpoint.write(session, function()
			f.h.sched.wait(0.2); writes[#writes + 1] = "old"; return true
		end, function() delayed = delayed + 1 end)
	end)
	f.h.sched.advance(0.05)
	session.persistenceRevision = 2
	local second = checkpoint.write(session, function() writes[#writes + 1] = "new"; return true end)
	check("second writer does not race the first", second == false and #writes == 0)
	f.h.sched.advance(0.3)
	check("old completion retains dirty state", firstResult and session.persistenceDirty and delayed == 1)
	check("explicit latest checkpoint settles", checkpoint.write(session, function() writes[#writes + 1] = "new"; return true end))
	check("latest write is last and clean", table.concat(writes, ",") == "old,new" and not session.persistenceDirty)
	f.healthy(); f.close()
end)
case("throwing or failed writes release ownership and stay dirty", function()
	local f = F.new(); local checkpoint = f.env.require("agent/checkpoint")
	local session = { persistenceRevision = 1 }
	check("exception is returned as failure", not checkpoint.write(session, function() error("unavailable") end))
	check("exception leaves retryable ownership", not session.persistenceWriting and session.persistenceDirty)
	check("refused save stays dirty", not checkpoint.write(session, function() return false, "disk full" end) and session.persistenceDirty)
	f.close()
end)
case("a yielding save cannot recreate no-save or deleted history", function()
	for _, mode in ipairs({ "ephemeral", "removed" }) do
		local f = F.new(); local sessions = f.env.require("agent/session")
		local session = assert(sessions.newThread({ id = "retired-checkpoint", title = "Old conversation" }))
		assert(session.persist())
		local fsx = f.env.require("runtime/fsx"); local writeJson = fsx.writeJson
		fsx.writeJson = function(path, snapshot)
			if path == "sessions/retired-checkpoint.json" then f.h.sched.wait(0.2) end
			return writeJson(path, snapshot)
		end
		local result
		f.h.sched.spawn(function() result = session.persist() end)
		f.h.sched.advance(0.05)
		if mode == "ephemeral" then session.setEphemeral(true)
		else
			assert(sessions.remove(session.id))
			local replacement, why = sessions.newThread({ id = session.id })
			check("retired writer reserves its id", replacement == nil and why:find("still being", 1, true) ~= nil)
		end
		f.h.sched.advance(0.3)
		check(mode .. " completion does not report a saved checkpoint", result == false)
		check(mode .. " history stays absent", f.h.files["UAI/sessions/retired-checkpoint.json"] == nil)
		fsx.writeJson = writeJson
		if mode == "removed" then
			local replacement = assert(sessions.newThread({ id = session.id, title = "Replacement conversation" }))
			check("finished removal releases the id", replacement.persist())
			check("retired session cannot change replacement storage", session.setEphemeral(true) == false)
			check("replacement owns its new history", f.h.json.decode(f.h.files["UAI/sessions/retired-checkpoint.json"]).title == "Replacement conversation")
		end
		f.healthy(); f.close()
	end
end)
suite.finish()
