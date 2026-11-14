-- Executor-local technical knowledge. Reads are data; no note or recipe is executed.
return function(env)
	local util = env.require("runtime/util")
	local fsx = env.require("runtime/fsx")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local codec = env.require("runtime/vault_document")
	local seed = env.require("runtime/master_vault_seed")
	local M = { changed = env.require("runtime/signal").new("master_vault"),
		MAX_NOTES = 256, MAX_SCAN_BYTES = 4 * 1024 * 1024, MAX_ENTRIES = 512 }
	local DIR, observed, uncertain, sequence = "vault/notes", {}, {}, 0
	local observedCount, observedBytes, busy, alive, mutationGeneration = 0, 0, false, true, 0
	-- A content hash alone cannot distinguish two readers after a hash collision.
	-- Keep revisions opaque and local to this runtime, with a fresh observation
	-- generation whenever the retained original bytes change or are evicted.
	local epoch = tostring(M):gsub("[^%w]", ""):sub(-24)
	local guidOk, guid = pcall(function() return env.hs:GenerateGUID(false) end)
	if guidOk and type(guid) == "string" and #guid <= 36 and guid:match("^[%x%-]+$") then
		local compact = guid:gsub("%-", "")
		if #compact == 32 then epoch = compact .. "." .. epoch end
	end
	local starters, starterOrder = {}, {}
	assert(seed.version == 1 and type(seed.entries) == "table", "Unsupported bundled vault collection")
	local function stopped(options)
		return not alive or options and options.aborted and options.aborted()
	end
	local function forget(id)
		local old = observed[id]
		if old then observedCount, observedBytes = observedCount - 1, observedBytes - #old.source; observed[id] = nil end
	end
	local function remember(id, source, path)
		sequence = sequence + 1
		local old = observed[id]
		if old and old.source == source and old.path == path then
			old.used = sequence
			return old.revision
		end
		forget(id)
		while observedCount >= 64 or observedBytes + #source > M.MAX_SCAN_BYTES do
			local oldest, stamp
			for key, value in pairs(observed) do if not stamp or value.used < stamp then oldest, stamp = key, value.used end end
			if not oldest then break end
			forget(oldest)
		end
		local revision = codec.revision(source) .. ":" .. epoch .. ":" .. string.format("%.0f", sequence)
		observed[id] = { source = source, path = path, revision = revision, used = sequence }
		observedCount, observedBytes = observedCount + 1, observedBytes + #source
		return revision
	end
	local function pathFor(id)
		if type(id) ~= "string" or #id > 140 or not util.validUtf8(id) then return nil, "Invalid vault note ID" end
		local name = id:match("^note:(.+)$")
		if not name or name:find("[/\\]") or name:sub(1, 1) == "." then return nil, "Use an exact note: ID from the vault" end
		local path, why = fsx.sanitise(DIR .. "/" .. name .. ".md")
		if not path then return nil, why end
		return path
	end
	local function directoryExists()
		if not fsx.enabled or type(caps.fn.isfolder) ~= "function" then return nil end
		local full = fsx.resolve(DIR)
		local ok, result = pcall(caps.fn.isfolder, full)
		if not ok or type(result) ~= "boolean" then return nil end
		return result
	end
	local function inventory(options)
		if not fsx.enabled then return {}, true, 0, "This host cannot read executor notes" end
		if directoryExists() == false then return {}, false, 0 end
		local entries, why = fsx.list(DIR, { maxEntries = M.MAX_ENTRIES })
		local paths, aliases, incomplete, visited = {}, {}, why ~= nil, 0
		for _, entry in ipairs(entries) do
			if stopped(options) then return nil, "Vault search stopped" end
			visited = visited + 1
			if visited > M.MAX_ENTRIES then incomplete = true; break end
			local name = type(entry.path) == "string" and entry.path:match("^vault/notes/([^/]+)%.md$")
			if name and not entry.isDir then
				local id = "note:" .. name
				local safe = pathFor(id)
				if safe == entry.path then
					paths[#paths + 1] = { id = id, path = safe }
					aliases[id:lower()] = (aliases[id:lower()] or 0) + 1
				else incomplete = true end
			elseif entry.isDir or tostring(entry.path or ""):sub(-3):lower() == ".md" then incomplete = true end
			if visited % 16 == 0 then task.wait() end
		end
		local valid = {}
		for _, entry in ipairs(paths) do
			if aliases[entry.id:lower()] == 1 then valid[#valid + 1] = entry else incomplete = true end
		end
		table.sort(valid, function(a, b) return a.id < b.id end)
		return valid, incomplete, #paths, why
	end
	local function metadata(document)
		return { id = document.id, title = document.title, description = document.description, kind = document.kind,
			scope = document.scope, placeId = document.placeId, project = document.project, tags = util.copy(document.tags),
			status = document.status, revision = document.revision, readOnly = document.readOnly, updatedAt = document.updatedAt,
			sourceCount = #document.sources, hasVerification = document.verification ~= nil }
	end
	for _, entry in ipairs(seed.entries or {}) do
		assert(type(entry.id) == "string" and entry.id:match("^starter:[a-z0-9_-]+$") and not starters[entry.id], "Invalid bundled vault ID")
		local document, why = codec.parse(entry.markdown)
		assert(document, "Invalid bundled vault document: " .. tostring(why))
		document.id, document.readOnly, document.revision = entry.id, true, codec.revision(entry.markdown)
		starters[entry.id] = { document = document, markdown = entry.markdown }
		starterOrder[#starterOrder + 1] = entry.id
	end
	function M.parse(markdown) return codec.parse(markdown) end
	function M.format(document) return codec.format(document) end
	function M.isBusy() return busy end
	local function readSource(id, options)
		local path, why = pathFor(id); if not path then return nil, why end
		if stopped(options) then return nil, "Vault read stopped" end
		local exists = fsx.probe(path)
		if stopped(options) then return nil, "Vault read stopped" end
		if exists == nil then return nil, "The host could not verify this vault note" end
		if not exists then
			return nil, "This vault note does not exist", { id = id, missing = true }
		end
		if fsx.isDir(path) then return nil, "The note path is a directory" end
		local source = fsx.read(path)
		if source == nil then return nil, "The host could not read this vault note" end
		if stopped(options) then return nil, "Vault read stopped" end
		if #source > codec.MAX_FILE then return nil, "This vault note exceeds 80000 bytes" end
		return source, path
	end
	function M.read(id, options)
		if stopped(options) then return nil, "Vault read stopped" end
		local starter = type(id) == "string" and starters[id]
		if starter then return util.deepCopy(starter.document) end
		if busy then return nil, "A Master Vault write is in progress; read the current note after it finishes" end
		local generation = mutationGeneration
		local source, path, detail = readSource(id, options)
		if busy or mutationGeneration ~= generation then return nil, "A vault mutation overlapped this read; read the current note again after it finishes" end
		if not source then
			if detail and detail.missing then forget(id); uncertain[id] = nil end
			return nil, path, detail
		end
		local document, why = codec.parse(source); if not document then return nil, why end
		document.id, document.readOnly, document.revision = id, false, remember(id, source, path)
		uncertain[id] = nil
		return document
	end
	local function validOptions(options)
		if options == nil then options = {} end
		if type(options) ~= "table" then return nil, "Vault options must be an object" end
		local out = util.copy(options)
		if out.query ~= nil and (type(out.query) ~= "string" or #out.query > 256 or not util.validUtf8(out.query)
			or out.query:find("[%z\1-\31\127]")) then return nil, "Search must be one line of at most 256 UTF-8 bytes" end
		out.query = util.trim(out.query or ""):lower()
		out.scope = out.scope or "all"
		if out.scope ~= "all" and out.scope ~= "relevant" and out.scope ~= "global" and out.scope ~= "game" and out.scope ~= "project" then return nil, "Unknown vault search scope" end
		out.origin = out.origin or "all"
		if out.origin ~= "all" and out.origin ~= "notes" and out.origin ~= "starters" then return nil, "Unknown vault entry origin" end
		local function member(values, value)
			for _, candidate in ipairs(values) do if candidate == value then return true end end
			return false
		end
		if out.kind and not member(codec.kinds, out.kind) then return nil, "Unknown vault document kind" end
		if out.status and not member(codec.statuses, out.status) then return nil, "Unknown vault verification status" end
		if out.placeId ~= nil and (type(out.placeId) ~= "number" or out.placeId ~= out.placeId or out.placeId < 1
			or out.placeId >= 9007199254740991 or out.placeId ~= math.floor(out.placeId)) then return nil, "Search PlaceId must be a positive integer" end
		if out.project ~= nil and (type(out.project) ~= "string" or #out.project > 160 or not util.validUtf8(out.project)
			or out.project:find("[%z\1-\31\127]")) then return nil, "Search project must be one line of at most 160 UTF-8 bytes" end
		out.project = out.project and util.trim(out.project) or nil
		if out.scope == "relevant" and out.placeId == nil and (not out.project or out.project == "") then return nil, "Relevant search needs a PlaceId or project" end
		if out.scope == "game" and out.placeId == nil then return nil, "Game search needs a PlaceId" end
		if out.scope == "project" and (not out.project or out.project == "") then return nil, "Project search needs a project name" end
		for _, key in ipairs({ "offset", "limit" }) do
			local number = out[key]
			if number ~= nil and (type(number) ~= "number" or number ~= number or number < 1 or number == math.huge or number ~= math.floor(number)) then return nil, key .. " must be a positive integer" end
		end
		out.offset, out.limit = out.offset or 1, math.min(out.limit or 20, 50)
		return out
	end
	local function match(document, options)
		local relevant = document.scope == "global" or document.scope == "game" and document.placeId == options.placeId
			or document.scope == "project" and document.project == options.project
		if options.scope == "relevant" and not relevant then return nil end
		if options.scope ~= "all" and options.scope ~= "relevant" and document.scope ~= options.scope then return nil end
		if options.scope == "game" and document.placeId ~= options.placeId then return nil end
		if options.scope == "project" and document.project ~= options.project then return nil end
		if options.kind and document.kind ~= options.kind or options.status and document.status ~= options.status then return nil end
		local query, score = options.query, relevant and document.scope ~= "global" and 20 or 0
		if query == "" then return score end
		local title = document.title:lower()
		if title == query then return score + 1000 end
		if title:find(query, 1, true) then return score + 100 end
		if table.concat(document.tags, " "):lower():find(query, 1, true) then return score + 50 end
		if document.description:lower():find(query, 1, true) then return score + 20 end
		if document.content:lower():find(query, 1, true) then return score + 1 end
		return nil
	end
	function M.list(options)
		local opts, why = validOptions(options); if not opts then return nil, why end
		if stopped(opts) then return nil, "Vault search stopped" end
		local candidates, notes, bytes, incomplete, skipped = {}, 0, 0, false, 0
		local function consider(document)
			local score = match(document, opts)
			if score ~= nil then candidates[#candidates + 1] = { document = document, score = score } end
		end
		if opts.origin ~= "notes" then for _, id in ipairs(starterOrder) do consider(starters[id].document) end end
		if opts.origin ~= "starters" then
			local paths, limited = inventory(opts)
			if not paths then return nil, limited end
			incomplete = limited
			for index, entry in ipairs(paths) do
				if stopped(opts) then return nil, "Vault search stopped" end
				if index > M.MAX_NOTES or bytes >= M.MAX_SCAN_BYTES then incomplete = true; break end
				local source = fsx.read(entry.path)
				if type(source) == "string" then
					bytes = bytes + #source
					local document = codec.parse(source)
					if document then
						local baseline = observed[entry.id]
						document.id, document.readOnly = entry.id, false
						-- Discovery does not retain originals or authorize list-only edits.
						document.revision = baseline and baseline.source == source and baseline.path == entry.path and baseline.revision or nil
						notes = notes + 1; consider(document)
					else skipped, incomplete = skipped + 1, true end
				else skipped, incomplete = skipped + 1, true end
				if index % 8 == 0 then task.wait() end
			end
		end
		if stopped(opts) then return nil, "Vault search stopped" end
		table.sort(candidates, function(a, b)
			if a.score ~= b.score then return a.score > b.score end
			local first, second = a.document.title:lower(), b.document.title:lower()
			return first == second and a.document.id < b.document.id or first < second
		end)
		if opts.offset > #candidates + 1 then return nil, "offset is past the end of this vault listing" end
		local items = {}
		for index = opts.offset, math.min(#candidates, opts.offset + opts.limit - 1) do items[#items + 1] = metadata(candidates[index].document) end
		local nextOffset = opts.offset + #items <= #candidates and opts.offset + #items or nil
		return { items = items, total = #candidates, offset = opts.offset, nextOffset = nextOffset, incomplete = incomplete,
			noteCount = notes, starterCount = #starterOrder, scannedBytes = bytes, skipped = skipped, filesystem = fsx.enabled == true }
	end
	function M.stats()
		local listed, why = M.list({ limit = 1 })
		if not listed then return { notes = 0, starters = #starterOrder, total = #starterOrder, incomplete = true,
			filesystem = fsx.enabled == true, writable = false, error = why } end
		return { notes = listed.noteCount, starters = #starterOrder, total = listed.noteCount + #starterOrder,
			incomplete = listed.incomplete, filesystem = fsx.enabled == true,
			writable = alive and fsx.enabled == true and type(caps.fn.isfile) == "function" and type(caps.fn.writefile) == "function" }
	end
	local function mutate(operation, faultDetail)
		if not alive then return nil, "The client is unloaded" end
		if not fsx.enabled then return nil, "This host cannot save executor vault notes" end
		if busy then return nil, "A Master Vault write is already in progress" end
		busy, mutationGeneration = true, mutationGeneration + 1
		local ok, value, why, detail = pcall(operation)
		busy = false
		if not ok then return nil, "The vault operation stopped unexpectedly; read the current note before continuing", faultDetail and faultDetail() or nil end
		return value, why, detail
	end
	function M.save(document, expectedRevision, options)
		local clean, why = codec.normalize(document); if not clean then return nil, why end
		if document.id ~= nil and type(document.id) ~= "string" then return nil, "Invalid vault document ID" end
		if document.id and document.id:sub(1, 8) == "starter:" then return nil, "Bundled starters are read-only; copy one as a new note" end
		local recovery
		local saved, err, detail = mutate(function()
			if stopped(options) then return nil, "Vault save stopped before writing" end
			local id, path, original = document.id, nil, nil
			if id then
				local reason; path, reason = pathFor(id); if not path then return nil, reason end
				if uncertain[id] then return nil, "Read the current note before retrying an unconfirmed save", { id = id, uncertain = true } end
				local baseline = observed[id]
				if type(expectedRevision) ~= "string" or not baseline or baseline.revision ~= expectedRevision then return nil, "Read the note and provide its current revision before updating" end
				original = fsx.read(path)
				if original == nil then return nil, "The current vault note could not be read" end
				if original ~= baseline.source then return nil, "This vault note changed; read its current version before saving" end
			else
				if expectedRevision ~= nil then return nil, "A new note cannot have an expected revision" end
				local paths, incomplete, count = inventory(options)
				if not paths then return nil, incomplete end
				if incomplete then return nil, "Vault inventory is incomplete; resolve it before adding a note" end
				if count >= M.MAX_NOTES then return nil, "The vault already has 256 notes; export or remove an entry first" end
				for attempt = 1, 32 do
					id = "note:" .. util.uid("note")
					path = pathFor(id)
					local exists = fsx.probe(path)
					if exists == nil then return nil, "The host could not verify a new note destination" end
					if not exists then break end
					path = nil
				end
				if not path then return nil, "Could not allocate a new vault note ID" end
			end
			clean.updatedAt = math.floor(clock.ms())
			local body, reason = codec.format(clean); if not body then return nil, reason end
			if stopped(options) then return nil, "Vault save stopped before writing" end
			-- Recheck after all preparation and before entering the only write.
			if id and document.id then
				if fsx.read(path) ~= original then return nil, "This vault note changed before saving" end
			else
				local exists = fsx.probe(path)
				if exists ~= false then return nil, "The new note destination is no longer verified empty" end
			end
			if stopped(options) then return nil, "Vault save stopped before writing" end
			uncertain[id] = true; forget(id)
			recovery = { id = id, uncertain = true }
			-- Sensitive suppresses raw host errors, which may contain the note payload.
			fsx.write(path, body, { sensitive = true })
			local after = fsx.read(path)
			if after ~= body then return nil, "Save could not be confirmed; read the current note before another save", { id = id, uncertain = true } end
			if stopped(options) then return nil, "Save finished after the request stopped; read the current note before continuing", recovery end
			clean.id, clean.readOnly, clean.revision = id, false, remember(id, body, path)
			uncertain[id] = nil
			return util.deepCopy(clean)
		end, function() return recovery end)
		if saved then M.changed:fire(metadata(saved)) end
		return saved, err, detail
	end
	function M.delete(id, expectedRevision, options)
		if type(id) == "string" and id:sub(1, 8) == "starter:" then return false, "Bundled starters cannot be deleted" end
		local recovery
		local deleted, why, detail = mutate(function()
			local path, err = pathFor(id); if not path then return nil, err end
			if stopped(options) then return nil, "Vault deletion stopped before writing" end
			if uncertain[id] then return nil, "Read the current note before another mutation", { id = id, uncertain = true } end
			local baseline = observed[id]
			if type(expectedRevision) ~= "string" or not baseline or baseline.revision ~= expectedRevision then return nil, "Read the note and provide its current revision before deleting" end
			local source = fsx.read(path)
			if source == nil or source ~= baseline.source then return nil, "This vault note changed; read it before deleting" end
			if type(caps.fn.delfile) ~= "function" then return nil, "This host cannot delete files" end
			if stopped(options) then return nil, "Vault deletion stopped before writing" end
			if fsx.read(path) ~= source or fsx.isDir(path) then return nil, "The note changed before deletion" end
			if stopped(options) then return nil, "Vault deletion stopped before writing" end
			uncertain[id] = true; forget(id)
			recovery = { id = id, uncertain = true }
			-- File-only deletion cannot turn a changed target into a recursive folder delete.
			pcall(caps.fn.delfile, fsx.resolve(path))
			local exists = fsx.probe(path)
			if exists ~= false then return nil, "Deletion could not be confirmed; read the current note", { id = id, uncertain = true } end
			if stopped(options) then return nil, "Deletion finished after the request stopped; review the current note before continuing", recovery end
			uncertain[id] = nil
			return true
		end, function() return recovery end)
		if deleted then M.changed:fire({ id = id, deleted = true }) end
		return deleted == true, why, detail
	end
	env.require("runtime/dispose").add(function()
		alive = false; observed, uncertain = {}, {}; observedCount, observedBytes = 0, 0; M.changed:clear()
	end, "Master Vault lifetime")
	return M
end
