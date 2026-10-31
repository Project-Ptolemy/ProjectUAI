-- One writer owns a conversation checkpoint; overlapping mutations stay dirty.
return function(env)
	local M = {}
	function M.write(session, writer, later)
		if session.persistenceWriting then
			session.persistenceQueued, session.persistenceDirty = true, true
			return false, "A conversation save is already in progress."
		end
		session.persistenceWriting, session.persistenceQueued = true, false
		local revision = session.persistenceRevision
		local ok, saved, why = pcall(writer)
		local pending = session.persistenceQueued == true
		session.persistenceWriting, session.persistenceQueued = false, false
		session.persistenceDirty = not (ok and saved and not pending and session.persistenceRevision == revision)
		if pending and later then later() end
		if not ok then return false, tostring(saved) end
		return saved, why
	end
	return M
end
