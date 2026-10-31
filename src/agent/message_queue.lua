-- Bounded pending user messages. Preparation reserves order before file I/O can
-- yield. Only compact prepared content is persisted; restoration never starts work.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local images = env.require("runtime/images")
	local M = { LIMIT = 16, BYTES = 128000, PREPARING_BYTES = 32 * 1024 * 1024 }

	function M.new(session, changed)
		local items, receipts, receiptOrder = {}, {}, {}
		local held, reason = false, nil
		local Q = {}
		local function notify()
			if #items == 0 then held, reason = false, nil end
			session.preparing = Q.preparing() and true or nil
			session.emit("queue:state", { count = #items, held = held, reason = reason })
			if changed then changed() end
		end
		local function remember(entry)
			receipts[entry.id] = { messageId = entry.id, queued = entry.queued }
			receiptOrder[#receiptOrder + 1] = entry.id
			while #receiptOrder > 128 do receipts[table.remove(receiptOrder, 1)] = nil end
		end
		local function detach(entry)
			for index, item in ipairs(items) do
				if item == entry then table.remove(items, index); entry.active = false; return true end
			end
			return false
		end
		function Q.pending() return #items end
		function Q.peek() return items[1] end
		function Q.held() return held end
		function Q.preparing()
			for _, entry in ipairs(items) do if entry.state == "preparing" then return true end end
			return false
		end
		function Q.receipt(id)
			if receipts[id] then return util.copy(receipts[id]) end
		end
		function Q.reserve(text, files, pictures, onDone, id, queued, rawBytes)
			if type(id) ~= "string" or #id == 0 or #id > 120 or not id:match("^[%w_-]+$") then return nil, "invalid message id" end
			for _, item in ipairs(items) do if item.id == id then return nil, "message is still being prepared" end end
			if #items >= M.LIMIT then return nil, "The follow-up queue is full (16 messages); remove one or wait for the next step" end
			local preparingBytes = rawBytes or #text
			for _, item in ipairs(items) do if item.state == "preparing" then preparingBytes = preparingBytes + item.rawBytes end end
			if preparingBytes > M.PREPARING_BYTES then return nil, "Queued message preparation exceeds 32 MiB; wait for an attachment to finish" end
			local entry = { id = id, text = util.ellipsis(text, 8000), files = util.deepCopy(files), images = pictures,
				onDone = onDone, at = clock.ms(), state = "preparing", active = true, queued = queued, rawBytes = rawBytes or #text }
			items[#items + 1] = entry
			notify()
			return entry
		end
		function Q.commit(entry, text)
			if not entry.active then return nil, "message preparation was cancelled; your draft was kept" end
			local bytes = #text
			for _, item in ipairs(items) do if item ~= entry then bytes = bytes + #item.text end end
			if bytes > M.BYTES then return nil, "The follow-up queue text limit was reached; remove a message or wait for the next step" end
			entry.text, entry.state, entry.needsValidation = text, "queued", held
			remember(entry)
			session.emit("message:queued", { messageId = entry.id, text = text, queued = entry.queued, count = #items })
			notify()
			return Q.receipt(entry.id)
		end
		function Q.reject(entry, why)
			if not detach(entry) then return false end
			session.emit("message:removed", { messageId = entry.id, reason = why, prepared = false })
			notify(); return true
		end
		function Q.take()
			local entry = items[1]
			if held or not entry or entry.state ~= "queued" then return nil end
			table.remove(items, 1); entry.active = false
			return entry
		end
		function Q.consumed(entry)
			session.emit("message:consumed", { messageId = entry.id, count = #items })
			notify()
		end
		function Q.remove(id, why)
			for _, entry in ipairs(items) do
				if entry.id == id then
					detach(entry)
					if entry.state == "queued" and entry.onDone then pcall(entry.onDone, nil, { status = "cancelled", messageId = id, reason = why or "removed" }) end
					session.emit("message:removed", { messageId = id, reason = why or "removed" })
					notify(); return true
				end
			end
			return false, "queued message no longer exists"
		end
		function Q.edit(id, text, expected)
			if type(text) ~= "string" or type(expected) ~= "string" then return false, "invalid queued message edit" end
			if #text > 8000 or #expected > 16000 then return false, "An edited follow-up supports up to 8,000 bytes; attach longer input in a new message" end
			text = util.trim(text)
			if not util.validUtf8(text) then return false, "Queued message text must be valid UTF-8" end
			if text == "" or #text > 8000 then return false, "Use 1 to 8,000 bytes for an edited follow-up; attach longer input in a new message" end
			for _, entry in ipairs(items) do
				if entry.id == id then
					if entry.state ~= "queued" then return false, "Wait for this message to finish preparing" end
					if #(entry.files or {}) > 0 then return false, "File-backed messages keep their verified attachment text; remove and compose a new message to replace it" end
					if entry.text ~= expected then return false, "This follow-up changed. Review its latest text before editing again" end
					local bytes = #text
					for _, item in ipairs(items) do if item ~= entry then bytes = bytes + #item.text end end
					if bytes > M.BYTES then return false, "The follow-up queue text limit was reached" end
					entry.text = text
					session.emit("message:edited", { messageId = id, text = text })
					notify(); return true
				end
			end
			return false, "queued message no longer exists"
		end
		function Q.move(id, direction, neighborId)
			if direction ~= -1 and direction ~= 1 then return false, "invalid queue direction" end
			for index, entry in ipairs(items) do
				if entry.id == id then
					local neighbor = items[index + direction]
					if not neighbor or neighbor.id ~= neighborId then return false, "The queue order changed. Review the latest order before moving this message" end
					if entry.state ~= "queued" or neighbor.state ~= "queued" then return false, "Messages still preparing retain their place in the queue" end
					items[index], items[index + direction] = neighbor, entry
					session.emit("message:moved", { messageId = id, position = index + direction })
					notify(); return true
				end
			end
			return false, "queued message no longer exists"
		end
		function Q.clearSelected(ids)
			if type(ids) ~= "table" or not util.isArray(ids) or #ids > M.LIMIT then return false, "invalid queued message selection" end
			for _, id in ipairs(ids) do if type(id) ~= "string" then return false, "invalid queued message id" end end
			-- Only remove the reviewed identities. Newly queued messages survive, even
			-- if a completion callback or another client adds one during this action.
			local selected = util.copy(ids)
			for _, id in ipairs(selected) do Q.remove(id, "queue cleared") end
			return true
		end
		function Q.cancelPreparations(why)
			local pending = util.copy(items)
			for _, entry in ipairs(pending) do if entry.state == "preparing" then Q.reject(entry, why) end end
		end
		function Q.hold(why)
			held, reason = #items > 0, why
			for _, entry in ipairs(items) do if entry.state == "queued" then entry.needsValidation = true end end
			notify()
		end
		function Q.release() held, reason = false, nil; notify() end
		function Q.clear(why)
			while items[1] do Q.remove(items[1].id, why) end
		end
		function Q.snapshot()
			local out = {}
			for _, entry in ipairs(items) do
				out[#out + 1] = { id = entry.id, text = entry.text, files = util.deepCopy(entry.files),
					images = util.deepCopy(entry.images), at = entry.at, state = entry.state }
			end
			return { items = out, count = #out, limit = M.LIMIT, held = held, reason = reason,
				operations = { edit = true, move = true, clear = true } }
		end
		function Q.serialise()
			local out = {}
			for _, entry in ipairs(Q.snapshot().items) do if entry.state == "queued" then out[#out + 1] = entry end end
			return { version = 1, items = out }
		end
		function Q.restore(saved)
			if saved == nil then return true end
			if type(saved) ~= "table" or saved.version ~= 1 or type(saved.items) ~= "table" or not util.isArray(saved.items)
				or #saved.items > M.LIMIT then return false, "invalid saved follow-up queue" end
			local restored, seen, bytes = {}, {}, 0
			for _, entry in ipairs(saved.items) do
				if type(entry) ~= "table" or entry.state ~= "queued" or type(entry.id) ~= "string" or #entry.id > 120 or not entry.id:match("^[%w_-]+$")
					or seen[entry.id] or type(entry.text) ~= "string" or util.trim(entry.text) == "" or #entry.text > 16000
					or type(entry.files or {}) ~= "table" or not util.isArray(entry.files or {}) or #(entry.files or {}) > 32 then
					return false, "invalid saved queued message"
				end
				local pictures, why = images.validate(entry.images, session.id)
				if not pictures then return false, why end
				local files = {}
				for _, file in ipairs(entry.files or {}) do
					if type(file) ~= "table" or type(file.path) ~= "string" or #file.path == 0 or #file.path > 1000
						or type(file.bytes) ~= "number" or file.bytes ~= file.bytes or file.bytes < 0 or file.bytes % 1 ~= 0
						or file.bytes > 10 * 1024 * 1024 then return false, "invalid saved file attachment" end
					if file.sha256 ~= nil and not env.require("runtime/attachment_identity").valid(file.sha256) then return false, "invalid saved attachment digest" end
					files[#files + 1] = { path = file.path, bytes = file.bytes, sha256 = file.sha256 }
				end
				bytes = bytes + #entry.text; if bytes > M.BYTES then return false, "saved follow-up queue exceeds text limit" end
				seen[entry.id] = true
				restored[#restored + 1] = { id = entry.id, text = entry.text, files = files, images = pictures,
					at = type(entry.at) == "number" and entry.at >= 0 and entry.at < math.huge and entry.at or clock.ms(),
					state = "queued", active = true, queued = true, needsValidation = true }
			end
			items = restored
			for _, entry in ipairs(items) do remember(entry) end
			if #items > 0 then held, reason = true, "Restored follow-ups are waiting for Resume" end
			return true
		end
		return Q
	end
	return M
end
