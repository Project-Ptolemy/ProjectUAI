-- Model discovery and the record's own model list.
--
-- The endpoint is the only authority on what it serves, so nothing here invents a
-- model id. Two sources, in this order:
--
--   1. what the user added by hand, which always wins because they typed it
--   2. what GET /v1/models reported, cached for the session
--
-- Generic lists retain all IDs. Documented catalog schemas can explicitly
-- exclude non-chat APIs without guessing capabilities from a model's name.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local http = env.require("net/http")
	local registry = env.require("provider/registry")
	local proxy = env.require("provider/proxy")
	local signal = env.require("runtime/signal")
	local urls = env.require("net/url")
	local modelCatalog = env.require("provider/model_catalog")
	local modelId = env.require("provider/model_id")
	local communityKey = env.require("provider/community_key")
	local support = env.require("runtime/support")
	local providerKeys = env.require("runtime/provider_keys")
	local config = env.require("runtime/config")

	local CACHE_MS = 10 * 60 * 1000

	local M = {
		cache = setmetatable({}, { __mode = "k" }),
		changed = signal.new("models"),
	}

	local pending = setmetatable({}, { __mode = "k" })
	local function keyFor(record)
		return util.trim(record.id) ~= "" and record.id or record
	end
	local function scopeFor(record)
		local scope = { baseUrl = registry.normaliseBaseUrl(record.baseUrl), api = record.api or "openai",
			apiKey = record.apiKey, authStyle = record.authStyle, headers = record.headers or {}, query = record.query or {},
			keyMode = providerKeys.mode(record), selectedKey = providerKeys.mode(record) == "single" and providerKeys.selected(record) or nil,
			keyPaused = providerKeys.pauseFlags(record),
			claudeUa = record.claudeUa }
		if registry.isOpencodeZen(record) then
			scope.opencode = env.require("net/bridge").opencodeStatus()
			scope.bridge = env.require("net/bridge_connection").get()
		end
		if registry.isCline(record) then
			local status = env.require("net/bridge").clineStatus()
			-- Signing in can finish during an explicit refresh. Transient status
			-- text does not change the authenticated owner of its catalog.
			scope.cline = { enabled = status.enabled, version = status.version }
			scope.bridge = env.require("net/bridge_connection").get()
			scope.bridge.instance = env.require("net/bridge").status().instance or scope.bridge.instance
		end
		return util.deepCopy(scope)
	end
	local function same(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end

	function M.cached(recordOrId)
		local record = type(recordOrId) == "table" and recordOrId or registry.get(recordOrId)
		local entry = M.cache[record and keyFor(record) or recordOrId]
		if not entry then return nil end
		if clock.since(entry.at) > CACHE_MS then return nil end
		if record and not same(entry.scope, scopeFor(record)) then return nil end
		return entry.models
	end

	function M.discovered(record)
		return M.cached(record) or {}
	end

	-- A catalog label is not permission to use the model. Zen documents Big
	-- Pickle as free despite its unsuffixed id; only apply that alias on Zen.
	-- Other ids use a distinct "free" token rather than matching "freedom".
	function M.isFree(record, id)
		if communityKey.isApplied(record) then return true end
		if registry.isCline(record) then return env.require("net/bridge").clineHasModel(id) == true end
		if registry.isOpencodeGo(record) then return false end
		local name = tostring(id or ""):lower()
		if registry.isOpencodeZen(record) and name == "big-pickle" then return true end
		return name:find("%f[%a]free%f[%A]") ~= nil
	end

	-- Manual entry. The id is stored on the record, so it survives a restart and is
	-- offered first from then on.
	local function mutationProblem(opts)
		if opts.persist == false then return nil end
		local access = config.accessProblem()
		if access then return access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return "Unlock the credential vault and finish any vault operation before editing models." end
	end
	local function commitModels(record, known, selected, opts)
		local previous, previousModel = record.models, record.model
		record.models, record.model = known, selected
		if opts.persist ~= false then
			local ok, why = registry.save(record, { force = true })
			if not ok then
				record.models, record.model = previous, previousModel
				return false, type(why) == "table" and table.concat(why, "; ") or why
			end
			if selected ~= previousModel and util.trim(selected) ~= "" then env.require("provider/model_preferences").remember(record, selected) end
		end
		M.changed:fire(record.id, known)
		return true
	end
	function M.add(record, id, opts)
		opts = opts or {}
		local problem = mutationProblem(opts)
		if problem then return false, problem end
		local clean, why = modelId.parse(id)
		if not clean then return false, why end
		local known = util.deepCopy(record.models or {})
		for _, existing in ipairs(known) do
			if existing == clean then
				if opts.select and record.model ~= clean then
					local ok, problem = commitModels(record, known, clean, opts)
					return ok, ok and clean or problem
				end
				return false, "already in the list"
			end
		end
		table.insert(known, 1, clean)
		local ok, problem = commitModels(record, known, opts.select ~= false and clean or record.model, opts)
		return ok, ok and clean or problem
	end

	function M.remove(record, id, opts)
		opts = opts or {}
		local problem = mutationProblem(opts)
		if problem then return false, problem end
		local kept = {}
		local removed = false
		for _, existing in ipairs(record.models or {}) do
			if existing == id then
				removed = true
			else
				kept[#kept + 1] = existing
			end
		end
		if removed then
			return commitModels(record, kept, record.model == id and (kept[1] or "") or record.model, opts)
		end
		return removed
	end

	-- The merged list, without touching the network.
	function M.list(record)
		local out, seen = {}, {}
		for _, id in ipairs(record.models or {}) do
			if util.trim(id) ~= "" and not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
		for _, id in ipairs(M.cached(record) or {}) do
			if not seen[id] then
				seen[id] = true
				out[#out + 1] = id
			end
		end
		return out
	end

	-- Yields. Returns the discovered ids and a note describing what happened, which
	-- the panel shows next to the fetch control. A provider with no /models route is
	-- a normal outcome, not an error: the user types the id instead.
	function M.discover(record, opts)
		opts = opts or {}
		local problem = registry.protocolProblem(record, { discovery = true })
		if problem then return {}, support.error(problem) end
		if not opts.force then
			local hit = M.cached(record)
			if hit then return hit, "cached" end
		end

		local key, token, scope = keyFor(record), {}, scopeFor(record)
		pending[key] = token
		local snapshot = registry.shareKeyRotation(record, util.deepCopy(record))
		local nativeGemini = env.require("provider/chat").styleOf(snapshot) == "gemini"
		if nativeGemini and (snapshot.query and snapshot.query.alt ~= nil or tostring(snapshot.baseUrl):find("[?&]alt=")) then
			snapshot.query = util.copy(snapshot.query or {}); snapshot.query.alt = "json"
		end
		local url = registry.endpoint(snapshot, "/models")
		local headers = env.require("provider/chat").headers(snapshot)
		local deadline = env.require("net/deadline").at(opts.timeout, opts.deadlineMs)
		local recovery = proxy.new(record, { aborted = opts.aborted, onRetry = opts.onRetry, deadlineMs = deadline })
		local function fetch()
			return http.send({
				requiresAccess = true,
				url = url,
				method = "GET",
				headers = headers,
				identity = registry.identityFor(snapshot),
				identityRequired = registry.requiresClaude(snapshot),
				attempts = 2,
				timeout = opts.timeout,
				deadlineMs = deadline,
				aborted = opts.aborted,
				tag = "models:" .. tostring(record.id or "draft"),
			})
		end
		local res, err, decoded, decodeError
		local cli = registry.isCline(snapshot) and "cline" or scope.opencode and scope.opencode.available == true and "opencode"
		if cli then
			if cli == "cline" then decoded, err = env.require("net/bridge").clineModels(opts)
			else decoded, err = env.require("net/bridge").opencodeModels(opts) end
			if decoded then res = { ok = true, status = 200 } end
		else
			res, err = fetch()
		end
		if not cli and pending[key] == token and same(scope, scopeFor(record)) and recovery.recover(res, err) then
			scope = scopeFor(record)
			snapshot = util.deepCopy(record)
			url = registry.endpoint(snapshot, "/models")
			if pending[key] == token then res, err = fetch() end
		end
		if res and not cli then decoded, decodeError = util.decode(res.body) end
		err = err or decodeError
		local partial = false
		if nativeGemini and res and res.ok and type(decoded) == "table" and type(decoded.models) == "table" then
			local rows, tokens, pages = {}, {}, 1
			for index, row in ipairs(decoded.models) do if index > 10000 then partial = true; break end; rows[#rows + 1] = row end
			local pageToken = decoded.nextPageToken
			while type(pageToken) == "string" and pageToken ~= "" and pages < 10 and #rows < 10000 do
				if #pageToken > 4096 or tokens[pageToken] then err = "invalid Gemini model pagination"; res = nil; break end
				if pending[key] ~= token or not same(scope, scopeFor(record)) then break end
				tokens[pageToken], pages = true, pages + 1
				local page = util.copy(snapshot); page.query = util.copy(snapshot.query or {}); page.query.pageToken = pageToken
				url = registry.endpoint(page, "/models")
				res, err = fetch()
				local nextPage = res and res.ok and util.decode(res.body)
				if type(nextPage) ~= "table" or type(nextPage.models) ~= "table" then err = err or "could not read the next Gemini model page"; res = nil; break end
				for _, row in ipairs(nextPage.models) do if #rows >= 10000 then partial = true; break end; rows[#rows + 1] = row end
				pageToken = nextPage.nextPageToken
			end
			partial = partial or type(pageToken) == "string" and pageToken ~= ""
			decoded.models = rows
		end

		if pending[key] ~= token or not same(scope, scopeFor(record)) then
			if pending[key] == token then pending[key] = nil end
			return {}, support.error("model discovery was superseded or the connection changed -- fetch again")
		end
		pending[key] = nil
		if not res or not res.ok or type(decoded) ~= "table" or decoded.error ~= nil then
			if cli then return {}, support.error(err or (cli == "cline" and "Could not read Cline's free model list." or "Could not read the OpenCode CLI model list.")) end
			local note = "could not read the model list"
			if res and res.status == 404 then note = "this endpoint has no /models route -- add a model by hand" end
			if res and res.status == 401 then note = "the API key was rejected" end
			if res and res.status == 403 then note = "the key is not allowed to list models" end
			if proxy.isClientRefusal(res) or registry.isOpencode(record) then
				note = "the endpoint rejected this client: " .. env.require("provider/chat").errorText(snapshot, res, err)
			elseif res and res.status ~= 401 and res.status ~= 403 and res.status ~= 404 then
				note = note .. ": " .. env.require("provider/chat").errorText(snapshot, res, err)
			end
			log.info("models", tostring(record.label) .. ": " .. note, err)
			return {}, support.error(note)
		end

		-- The documented shape is { data = { { id = ... } } }. Some servers answer
		-- with a bare array, and Ollama answers with { models = { { name = ... } } }.
		local rows = decoded.data or decoded.models or decoded
		local found, seen, excluded, invalid = {}, {}, 0, 0
		if type(rows) == "table" then
			for index, row in ipairs(rows) do
				if index > 10000 then partial = true; break end
				local id
				if type(row) == "string" then
					id = row
				elseif type(row) == "table" then
					id = row.id or row.name or row.model
				end
				id = type(id) == "string" and util.trim(id) or ""
				if id ~= "" and not modelCatalog.accepts(url, row) then
					id, excluded = "", excluded + 1
				end
				if nativeGemini then
					id = id:gsub("^models/", "")
					if type(row) == "table" and type(row.supportedGenerationMethods) == "table" then
						local generates = false
						for _, method in ipairs(row.supportedGenerationMethods) do if method == "generateContent" or method == "streamGenerateContent" then generates = true end end
						if not generates then id = "" end
					end
				end
				if id ~= "" then
					local clean = modelId.parse(id)
					if not clean then invalid = invalid + 1 end
					id = clean or ""
				end
				if id ~= "" and not seen[id] then
					seen[id] = true
					found[#found + 1] = id
				end
			end
		end

		table.sort(found)
		if #found == 0 then
			M.cache[key] = nil
			if invalid > 0 then return {}, support.error("the catalog returned invalid model ids -- enter an exact valid id manually") end
			if excluded > 0 then return {}, support.error("the catalog has no compatible chat models -- check the provider's API documentation or add an id manually") end
			return {}, support.error("the endpoint returned an empty list -- add a model by hand")
		end
		M.cache[key] = { at = clock.ms(), models = found, scope = scope }
		M.changed:fire(record.id, found)
		local note = string.format("%d model%s from %s", #found, #found == 1 and "" or "s",
			cli == "cline" and "Cline through Project UAI Bridge" or cli and "OpenCode CLI through Project UAI Bridge" or urls.display(url))
		if partial then note = note .. "; catalog page limit reached, additional IDs may be entered manually" end
		if excluded > 0 then note = note .. string.format("; %d non-chat entries hidden", excluded) end
		if invalid > 0 then note = note .. string.format("; %d invalid model ids hidden", invalid) end
		if registry.isOpencodeGo(record) then note = note .. "; public list -- subscription access is checked when you send" end
		return found, note
	end

	function M.invalidate(providerId)
		if providerId then
			local key = type(providerId) == "table" and keyFor(providerId) or providerId
			M.cache[key], pending[key] = nil, nil
		else
			M.cache = setmetatable({}, { __mode = "k" })
			pending = setmetatable({}, { __mode = "k" })
		end
	end

	return M
end
