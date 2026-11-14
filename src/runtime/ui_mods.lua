-- Verified executor-local mod definitions. Source is compiled only by explicit checks; execution is owned elsewhere.
return function(env)
	local util = env.require("runtime/util")
	local fsx = env.require("runtime/fsx")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local document = env.require("runtime/ui_mod_document")
	local M = { changed = env.require("runtime/signal").new("ui_mods"),
		limits = { mods = 16, history = 3, file = 4 * 1024 * 1024, depth = 12, nodes = 8192 } }
	local PATH = "ui_mods/store.json"
	local records, activeId, selection = {}, nil, nil
	local loaded, loading, complete, uncertain, busy, alive, compiling = false, false, true, false, false, true, 0
	local baseline, missing, generation, tokenSequence, mutationSequence, disableSequence = nil, false, 0, 0, 0, 0
	local failure
	local epoch = tostring(M):gsub("[^%w]", ""):sub(-16)
	local guidOk, guid = pcall(function() return env.hs:GenerateGUID(false) end)
	if guidOk and type(guid) == "string" and #guid == 36 then
		local compact = guid:gsub("%-", "")
		if #compact == 32 and compact:match("^%x+$") then epoch = compact .. "." .. epoch end
	end
	local function integer(value, minimum)
		return type(value) == "number" and value == value and value >= minimum and value < 9007199254740991 and value == math.floor(value)
	end
	local function object(value, allowed, maximum)
		if type(value) ~= "table" then return false end
		local count = 0
		for key in pairs(value) do count = count + 1; if count > maximum or type(key) ~= "string" or not allowed[key] then return false end end
		return true
	end
	local function array(value, maximum)
		if type(value) ~= "table" or #value > maximum then return false end
		local count = 0
		for key in pairs(value) do count = count + 1; if count > maximum or not integer(key, 1) or key > #value then return false end end
		return count == #value
	end
	local function stopped(options) return not alive or options and options.aborted and options.aborted() end
	local function safeMode() return env.context and env.context.safeMode == true end
	local function sorted(map)
		local ids = {}; for id in pairs(map) do ids[#ids + 1] = id end
		table.sort(ids); return ids
	end
	local function encodeRecord(record)
		local history = {}
		for _, previous in ipairs(record.history) do
			history[#history + 1] = '{"version":' .. string.format("%.0f", previous.version) .. ',"updatedAt":' .. string.format("%.0f", previous.updatedAt)
				.. ',"spec":' .. previous.json .. "}"
		end
		return '{"version":' .. string.format("%.0f", record.version) .. ',"updatedAt":' .. string.format("%.0f", record.updatedAt)
			.. ',"spec":' .. record.json .. ',"history":[' .. table.concat(history, ",") .. "]}"
	end
	local function encodeStore(map, nextGeneration, selected)
		local rows = {}; for _, id in ipairs(sorted(map)) do rows[#rows + 1] = encodeRecord(map[id]) end
		local prefix = '{"version":1,"generation":' .. string.format("%.0f", nextGeneration)
		if selected then prefix = prefix .. ',"selected":{"id":' .. util.encode(selected.id) .. ',"version":' .. string.format("%.0f", selected.version) .. "}" end
		local json = prefix .. ',"records":[' .. table.concat(rows, ",") .. "]}"
		if #json > M.limits.file then return nil, "UI mod storage exceeds 4 MiB; export or remove a mod before adding more source/history" end
		return json
	end
	local recordFields = { version = true, updatedAt = true, spec = true, history = true }
	local historyFields = { version = true, updatedAt = true, spec = true }
	local function normalizeRecord(value)
		if not object(value, recordFields, 4) or not integer(value.version, 1)
			or value.updatedAt ~= nil and not integer(value.updatedAt, 0) then return nil end
		local retained = value.history == nil and {} or value.history
		if not array(retained, M.limits.history) then return nil end
		local spec = document.validate(value.spec); if not spec then return nil end
		local clean = { spec = spec, json = assert(document.format(spec)), version = value.version,
			updatedAt = value.updatedAt or 0, history = {} }
		local lastVersion = clean.version
		for _, previous in ipairs(retained) do
			if not object(previous, historyFields, 3) or not integer(previous.version, 1) or previous.version >= lastVersion
				or previous.updatedAt ~= nil and not integer(previous.updatedAt, 0) then return nil end
			local old = document.validate(previous.spec); if not old or old.id ~= spec.id then return nil end
			lastVersion = previous.version
			clean.history[#clean.history + 1] = { version = previous.version, updatedAt = previous.updatedAt or 0,
				spec = old, json = assert(document.format(old)) }
		end
		clean.bytes = encodeRecord(clean)
		return clean
	end
	local storeFields = { version = true, generation = true, selected = true, records = true }
	local selectionFields = { id = true, version = true }
	local function decodeStore(json)
		local value, why = document.decodeJson(json, M.limits.file, M.limits.depth, M.limits.nodes)
		if not value then return nil, why end
		if not object(value, storeFields, 4) or value.version ~= 1 or not integer(value.generation, 1)
			or type(value.records) ~= "table" then return nil, "Unsupported UI mod storage format" end
		local map, seen, omitted = {}, {}, 0
		local shape = array(value.records, 16384)
		if not shape then return nil, "UI mod records must be an array" end
		for index, raw in ipairs(value.records) do
			if index > M.limits.mods then omitted = omitted + 1
			else
				local record = normalizeRecord(raw)
				if record then
					local id = record.spec.id
					if seen[id] then map[id] = nil; omitted = omitted + 1
					else seen[id] = true; map[id] = record end
				else omitted = omitted + 1 end
			end
		end
		local selected
		if value.selected ~= nil then
			if object(value.selected, selectionFields, 2) and document.validId(value.selected.id)
				and integer(value.selected.version, 1) and map[value.selected.id] and map[value.selected.id].version == value.selected.version then
				selected = { id = value.selected.id, version = value.selected.version }
			else omitted = omitted + 1 end
		end
		return { records = map, generation = value.generation, selection = selected, complete = omitted == 0, omitted = omitted }
	end
	local function nextToken(version)
		tokenSequence = tokenSequence + 1
		return "mod:" .. epoch .. ":" .. string.format("%.0f", tokenSequence) .. ":" .. string.format("%.0f", version)
	end
	local function retainTokens(map)
		for id, record in pairs(map) do
			record.bytes = encodeRecord(record)
			local old = records[id]
			record.revision = old and old.bytes == record.bytes and old.revision or nextToken(record.version)
		end
	end
	local ensureLoaded
	local function stateSnapshot()
		local writable = alive and loaded and complete and not uncertain and fsx.enabled == true
			and type(caps.fn.isfile) == "function" and type(caps.fn.writefile) == "function"
		return { loaded = loaded, loading = loading, filesystem = fsx.enabled == true, writable = writable,
			busy = busy or loading or compiling > 0, compiling = compiling,
			incomplete = not complete, uncertain = uncertain, error = failure, count = util.count(records),
			activeId = activeId, activeRevision = activeId and records[activeId] and records[activeId].revision or nil,
			selectedId = selection and selection.id or nil, generation = generation,
			status = not alive and "unloaded" or uncertain and "unconfirmed" or not complete and "unavailable" or "ready" }
	end
	local function metadata(record)
		return { id = record.spec.id, name = record.spec.name, kind = record.spec.kind, description = record.spec.description,
			author = record.spec.author, revision = record.revision, version = record.version, updatedAt = record.updatedAt,
			active = activeId == record.spec.id, selected = selection and selection.id == record.spec.id or false,
			historyCount = #record.history, sourceBytes = record.spec.source and #record.spec.source or 0,
			panelCount = #(record.spec.panels or {}) }
	end
	local function snapshot(record)
		local out = metadata(record); out.spec, out.history = util.deepCopy(record.spec), {}
		for _, previous in ipairs(record.history) do out.history[#out.history + 1] = { version = previous.version,
			updatedAt = previous.updatedAt, spec = util.deepCopy(previous.spec) } end
		return out
	end
	local function changed(action, id, previous)
		M.changed:fire({ action = action, id = id, activeId = activeId, previousActiveId = previous,
			activeRevision = activeId and records[activeId] and records[activeId].revision or nil, state = stateSnapshot() })
	end
	local function readDisk(options)
		if stopped(options) then return nil, "UI mod read stopped" end
		local exists = fsx.probe(PATH)
		if stopped(options) then return nil, "UI mod read stopped" end
		if exists == nil then return nil, "The host could not verify UI mod storage" end
		if exists == false then return false end
		if fsx.isDir(PATH) then return nil, "UI mod storage is a directory" end
		local json = fsx.read(PATH)
		if stopped(options) then return nil, "UI mod read stopped" end
		if type(json) ~= "string" then return nil, "The host could not read UI mod storage" end
		if #json > M.limits.file then return nil, "UI mod storage exceeds 4 MiB" end
		return json
	end
	function M.reload(options)
		if not alive then return nil, "The client is unloaded" end
		if busy or loading then return nil, "UI mod storage has an operation in progress" end
		if not fsx.enabled then loaded, complete, failure = true, false, "This host cannot read or save executor UI mods"; return nil, failure end
		loading = true
		local sequence, previous, disableAt = mutationSequence, activeId, disableSequence
		local ok, json, why = pcall(readDisk, options)
		loading = false
		if not ok then complete, failure = false, "UI mod storage could not be read"; loaded = true; return nil, failure end
		if stopped(options) or busy or sequence ~= mutationSequence then return nil, "A mutation overlapped UI mod loading; reload after it finishes" end
		if json == nil then complete, failure, loaded = false, why, true; return nil, why end
		local candidate, reason
		if json == false then candidate = { records = {}, generation = 0, complete = true }
		else candidate, reason = decodeStore(json) end
		if stopped(options) or busy or sequence ~= mutationSequence then return nil, "A mutation overlapped UI mod loading; reload after it finishes" end
		if not candidate then complete, failure, loaded = false, reason, true; return nil, reason end
		if not candidate.complete and loaded and util.count(records) > 0 then
			complete, failure = false, "UI mod storage contains unsupported or malformed records; the last known good mods are retained"
			return nil, failure
		end
		retainTokens(candidate.records)
		local nextActive
		if candidate.complete and not safeMode() and candidate.selection and disableSequence == disableAt then
			local chosen = candidate.records[candidate.selection.id]
			local current = activeId and records[activeId]
			if chosen.spec.kind == "visual" or current and current.revision == chosen.revision and activeId == chosen.spec.id then nextActive = chosen.spec.id end
		end
		records, generation, selection, activeId = candidate.records, candidate.generation, disableSequence == disableAt and candidate.selection or nil, nextActive
		baseline, missing, loaded, complete, uncertain = json ~= false and json or nil, json == false, true, candidate.complete, false
		failure = not complete and "Some unsupported or malformed UI mod records remain on disk; storage is read-only until resolved" or nil
		changed("reload", nil, previous)
		return stateSnapshot()
	end
	ensureLoaded = function(options)
		if not loaded then M.reload(options) end
		return loaded and alive
	end
	function M.state() ensureLoaded(); return stateSnapshot() end
	function M.isBusy() return busy or loading or compiling > 0 end
	function M.validate(value) return document.validate(value) end
	function M.parse(json) return document.parse(json) end
	function M.format(value) return document.format(value) end
	function M.getActive()
		ensureLoaded(); local record = activeId and records[activeId]
		return record and snapshot(record) or nil
	end
	function M.appearance()
		ensureLoaded(); local record = activeId and records[activeId]
		return record and record.spec.kind == "visual" and util.copy(record.spec.appearance) or {}
	end
	function M.list(options)
		options = options or {}
		if not ensureLoaded(options) then return nil, "UI mods are unavailable" end
		if stopped(options) then return nil, "UI mod listing stopped" end
		if options.refresh then local refreshed, why = M.reload(options); if not refreshed then return nil, why end end
		if options.kind ~= nil and options.kind ~= "visual" and options.kind ~= "script" then return nil, "Unknown UI mod kind" end
		if options.query ~= nil and (type(options.query) ~= "string" or #options.query > 160 or not util.validUtf8(options.query)
			or options.query:find("[%z\1-\31\127]")) then return nil, "Search must be one line within 160 UTF-8 bytes" end
		local offset, limit = options.offset or 1, options.limit or 16
		if not integer(offset, 1) or not integer(limit, 1) or limit > 16 then return nil, "Listing needs a positive offset and limit from 1 to 16" end
		local query, matches = util.trim(options.query or ""):lower(), {}
		for _, id in ipairs(sorted(records)) do
			local record = records[id]
			if (not options.kind or record.spec.kind == options.kind) and (query == "" or (id .. " " .. record.spec.name .. " " .. record.spec.description):lower():find(query, 1, true)) then
				matches[#matches + 1] = record
			end
		end
		if offset > #matches + 1 then return nil, "offset is past the end of the UI mod listing" end
		local items = {}; for index = offset, math.min(#matches, offset + limit - 1) do items[#items + 1] = metadata(matches[index]) end
		return { items = items, total = #matches, offset = offset, nextOffset = offset + #items <= #matches and offset + #items or nil, state = stateSnapshot() }
	end
	function M.read(id, options)
		if not document.validId(id) then return nil, "Use an exact UI mod ID" end
		if not ensureLoaded(options) or stopped(options) then return nil, "UI mod read stopped" end
		if options and options.refresh then local refreshed, why = M.reload(options); if not refreshed then return nil, why end end
		local record = records[id]; if not record then return nil, "This UI mod does not exist", { id = id, missing = true } end
		return snapshot(record)
	end
	function M.export(id, options)
		local record, why, detail = M.read(id, options); if not record then return nil, why, detail end
		local json, reason = document.format(record.spec); if not json then return nil, reason end
		return json, record.revision
	end
	local function mutation(operation, options, id)
		if not ensureLoaded(options) or stopped(options) then return nil, "UI mod mutation stopped" end
		if busy or loading then return nil, "A UI mod write is already in progress" end
		if not fsx.enabled then return nil, "This host cannot save executor UI mods" end
		if not complete or uncertain then return nil, "Reload current UI mod storage before another mutation", { id = id, uncertain = uncertain, incomplete = not complete } end
		busy, mutationSequence = true, mutationSequence + 1
		local disableAt = disableSequence
		local ok, value, why, detail = pcall(operation, disableAt)
		busy = false
		if not ok then return nil, "The UI mod operation stopped unexpectedly; reload current storage before continuing", { id = id, uncertain = uncertain } end
		return value, why, detail
	end
	local function commit(map, selected, desiredActive, options, id, disableAt)
		if not integer(generation + 1, 1) then return nil, "UI mod storage reached its generation limit" end
		local original, why = readDisk(options)
		if original == nil then return nil, why end
		if (missing and original ~= false) or (not missing and original ~= baseline) then
			complete, failure = false, "UI mod storage changed externally; reload it before saving"
			return nil, failure
		end
		local json, reason = encodeStore(map, generation + 1, selected); if not json then return nil, reason end
		if stopped(options) then return nil, "Stopped before writing UI mod storage" end
		local before = readDisk(options)
		if before ~= original then return nil, "UI mod storage changed before writing; reload it" end
		if stopped(options) then return nil, "Stopped before writing UI mod storage" end
		if disableSequence ~= disableAt then
			selected, desiredActive = nil, nil
			json, reason = encodeStore(map, generation + 1, nil)
			if not json then return nil, reason end
		end
		uncertain, failure = true, "UI mod save has not been confirmed; reload current storage before continuing"
		fsx.write(PATH, json, { sensitive = true })
		local after = fsx.read(PATH)
		if after ~= json then return nil, failure, { id = id, uncertain = true } end
		if stopped(options) then return nil, "Save finished after the request stopped; reload current UI mod storage", { id = id, uncertain = true } end
		retainTokens(map)
		records, baseline, missing, generation, complete, uncertain, failure = map, json, false, generation + 1, true, false, nil
		if disableSequence == disableAt then selection, activeId = selected, desiredActive
		else selection, activeId = nil, nil end
		return true, nil, { persisted = true, disabledDuringWrite = disableSequence ~= disableAt }
	end
	local function current(id, expectedRevision)
		local record = records[id]
		if not record then return nil, "This UI mod no longer exists" end
		if type(expectedRevision) ~= "string" or record.revision ~= expectedRevision then return nil, "Read the current UI mod and preserve its exact revision before changing it" end
		return record
	end
	function M.save(spec, expectedRevision, options)
		local clean, why = document.validate(spec); if not clean then return nil, why end
		local previous = activeId
		local result, reason, detail = mutation(function(disableAt)
			local old = records[clean.id]
			if old then local checked, err = current(clean.id, expectedRevision); if not checked then return nil, err end
			elseif expectedRevision ~= nil then return nil, "A new mod cannot have an expected revision" end
			if not old and util.count(records) >= M.limits.mods then return nil, "Up to sixteen UI mods can be saved; export or remove one first" end
			local version = old and old.version + 1 or 1
			if not integer(version, 1) then return nil, "This mod reached its version limit" end
			local record = { spec = clean, json = assert(document.format(clean)), version = version, updatedAt = math.floor(clock.ms()), history = {} }
			if old then
				record.history[1] = { version = old.version, updatedAt = old.updatedAt, spec = old.spec, json = old.json }
				for index = 1, math.min(#old.history, M.limits.history - 1) do record.history[#record.history + 1] = old.history[index] end
			end
			local map = util.copy(records); map[clean.id] = record
			local selected = selection and selection.id ~= clean.id and util.copy(selection) or nil
			local desired = activeId ~= clean.id and activeId or nil
			local ok, err, receipt = commit(map, selected, desired, options, clean.id, disableAt); if not ok then return nil, err, receipt end
			return snapshot(records[clean.id]), nil, receipt
		end, options, clean.id)
		if result then changed("save", clean.id, previous) end
		return result, reason, detail
	end
	function M.import(json, options)
		local spec, why = document.parse(json); if not spec then return nil, why end
		if not ensureLoaded(options) then return nil, "UI mods are unavailable" end
		if records[spec.id] then return nil, "That mod ID already exists; change the portable ID or replace it explicitly with its current revision" end
		return M.save(spec, nil, options)
	end
	function M.delete(id, expectedRevision, options)
		if not document.validId(id) then return false, "Use an exact UI mod ID" end
		local previous = activeId
		local result, why, detail = mutation(function(disableAt)
			local old, reason = current(id, expectedRevision); if not old then return nil, reason end
			local map = util.copy(records); map[id] = nil
			local selected = selection and selection.id ~= id and util.copy(selection) or nil
			local desired = activeId ~= id and activeId or nil
			return commit(map, selected, desired, options, id, disableAt)
		end, options, id)
		if result then changed("delete", id, previous) end
		return result == true, why, detail
	end
	function M.activate(id, expectedRevision, options)
		if not document.validId(id) then return nil, "Use an exact UI mod ID" end
		if safeMode() then return nil, "UI mods are disabled for this safe-mode execution. Reload normally before applying a mod." end
		local previous = activeId
		local result, why, detail = mutation(function(disableAt)
			if safeMode() then return nil, "UI mods are disabled for this safe-mode execution. Reload normally before applying a mod." end
			local record, reason = current(id, expectedRevision); if not record then return nil, reason end
			local ok, err, receipt = commit(util.copy(records), { id = id, version = record.version }, id, options, id, disableAt)
			if not ok then return nil, err, receipt end
			if receipt.disabledDuringWrite then return nil, "Activation was disabled while the native write finished; source was not authorized to start", receipt end
			return snapshot(records[id]), nil, receipt
		end, options, id)
		if result then changed("activate", id, previous) end
		return result, why, detail
	end
	function M.disable(options)
		ensureLoaded(options)
		local previous = activeId
		disableSequence, activeId, selection = disableSequence + 1, nil, nil
		changed("disable", nil, previous)
		if busy or loading then return true, "Disabled for this run; a pending native operation prevented saving that choice", { persisted = false } end
		if not complete or uncertain or not fsx.enabled then return true, "Disabled for this run; current storage could not remember that choice", { persisted = false } end
		local ok, why, detail = mutation(function(disableAt) return commit(util.copy(records), nil, nil, options, nil, disableAt) end, options)
		if not ok then return true, "Disabled for this run; " .. tostring(why), { persisted = false, uncertain = detail and detail.uncertain } end
		return true, nil, detail
	end
	function M.checkScript(spec)
		local clean, why = document.validate(spec)
		if not clean then return false, why, { ok = false, error = why, compilerAvailable = false, executed = false } end
		if not alive then
			local reason = "The client is unloaded"
			return false, reason, { ok = false, kind = clean.kind, error = reason, compilerAvailable = false, executed = false, stopped = true }
		end
		if clean.kind == "visual" then return true, nil, { ok = true, kind = "visual", executed = false } end
		if type(caps.fn.loadstring) ~= "function" then
			local reason = "This host has no Lua compiler"
			return false, reason, { ok = false, kind = "script", compilerAvailable = false, executed = false, error = reason }
		end
		compiling = compiling + 1
		local ok, compiled, reason = pcall(caps.fn.loadstring, clean.source, "@uai-mod/" .. clean.id)
		compiling = compiling - 1
		local errorText = not alive and "The client was unloaded while the compile check completed"
			or (not ok or type(compiled) ~= "function") and tostring(ok and reason or compiled or "Compilation failed") or nil
		local diagnostic = { ok = alive and ok and type(compiled) == "function", kind = "script", compilerAvailable = true, executed = false,
			error = errorText and util.ellipsis(util.sanitise(errorText), 1200) or nil, stopped = not alive or nil,
			sourceBytes = #clean.source, sourceHash = document.fingerprint(clean.source) }
		return diagnostic.ok, diagnostic.error, diagnostic
	end
	env.require("runtime/dispose").add(function()
		alive, activeId, selection = false, nil, nil
		records, baseline = {}, nil
		M.changed:clear()
	end, "UI mod definitions")
	return M
end
