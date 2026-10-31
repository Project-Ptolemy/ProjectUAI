-- Provider records: creation, validation, persistence, health and fallback order.
--
-- A record is the whole description of one endpoint, so switching provider is a
-- data change rather than a code path. Nothing above this module knows which
-- vendor is in use.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local caps = env.require("runtime/caps")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local signal = env.require("runtime/signal")
	local catalog = env.require("provider/catalog")
	local communityKey = env.require("provider/community_key")
	local providerKeys = env.require("runtime/provider_keys")
	local urls = env.require("net/url")

	local COOLDOWN_AFTER = 3
	local COOLDOWN_SECONDS = 45

	local M = {
		changed = signal.new("providers"),
	}
	local requestSnapshots = setmetatable({}, { __mode = "k" })

	-- Per-request model routing must not replace a saved provider when an adapter
	-- learns a limit. Its owner merges scoped lessons after the request settles.
	function M.requestSnapshot(record)
		local snapshot = M.shareKeyRotation(record, util.deepCopy(record))
		snapshot.health = record.health
		requestSnapshots[snapshot] = true
		return snapshot
	end

	-- Key pool ------------------------------------------------------------
	--
	-- One record may carry several keys, pasted one per line (or comma
	-- separated). The pool is what beats a free-tier RPM ceiling: Google AI
	-- Studio hands out keys in batches and caps each at 10-15 requests a
	-- minute, so N keys in one record is N times the ceiling with no second
	-- provider to configure.
	--
	-- New requests rotate through ready keys. Selection advances before any
	-- network yield, so overlapping requests share the pool in order. Quota
	-- refusals additionally bench the rejected key until its cooldown expires.
	local KEY_COOLDOWN_SECONDS = 30

	function M.keysOf(record)
		return providerKeys.keys(record)
	end
	M.requestKeys = providerKeys.requestKeys

	function M.keyPoolSize(record)
		return #M.keysOf(record)
	end

	-- Rotation state is kept on the record, not in this module's memory, so it
	-- survives nothing it should not and is visible to the health views. It is
	-- deliberately NOT persisted to config: which key is current is a fact about
	-- this session, and a saved index would be stale on the next start.
	local function keyState(record)
		record.keyRotation = record.keyRotation or { index = 1, cooldowns = {} }
		return record.keyRotation
	end

	-- Request snapshots keep their existing copy semantics, but own one shared
	-- cursor with the record they were copied from, even before the first request.
	function M.shareKeyRotation(record, snapshot)
		providerKeys.ensureIds(record)
		if table.concat(M.keysOf(record), "\n") == table.concat(M.keysOf(snapshot), "\n") then
			snapshot.keyIds = util.deepCopy(record.keyIds)
		else
			providerKeys.ensureIds(snapshot)
		end
		if providerKeys.mode(record) == "rotate" and providerKeys.mode(snapshot) == "rotate" and M.keyPoolSize(record) > 1 then
			snapshot.keyRotation = keyState(record)
		end
		return snapshot
	end

	-- The next ready key, advancing past it for the following request. When every key is cooling,
	-- the one whose cooldown expires soonest -- a pool that is entirely spent
	-- is a pool that was just load-balanced, and waiting out the shortest
	-- remaining bench is faster than hammering any single key.
	function M.nextKey(record)
		local keys = M.requestKeys(record)
		if #keys == 0 then return nil end
		if #keys == 1 then return keys[1] end

		local state = keyState(record)
		local now = clock.ms()
		local function ready(index)
			local until_ = state.cooldowns[keys[index]]
			return until_ == nil or until_ <= now
		end

		-- Walk the pool from the current index, wrapping once.
		for offset = 0, #keys - 1 do
			local index = ((state.index - 1 + offset) % #keys) + 1
			if ready(index) then
				state.index = index % #keys + 1
				return keys[index]
			end
		end

		-- All cooling: soonest to expire.
		local best, bestAt, bestIndex = nil, math.huge, nil
		for index = 1, #keys do
			local until_ = state.cooldowns[keys[index]] or 0
			if until_ < bestAt then
				best, bestAt, bestIndex = keys[index], until_, index
			end
		end
		if bestIndex then state.index = bestIndex % #keys + 1 end
		return best
	end

	-- Bench one key after it was refused. `seconds` may be overridden by a
	-- caller that read a Retry-After header, which outranks our default.
	function M.cooldownKey(record, key, seconds)
		local keys = M.requestKeys(record)
		if #keys < 2 then return false end
		local state = keyState(record)
		state.cooldowns[key] = clock.ms() + (seconds or KEY_COOLDOWN_SECONDS) * 1000
		return true
	end

	function M.keyCooldowns(record)
		local state = record and record.keyRotation
		if type(state) ~= "table" then return nil end
		return state.cooldowns
	end

	-- Base URL normalisation, done once on save so no request path has to guess.
	--
	--   api.openai.com            -> https://api.openai.com/v1
	--   https://x.dev/            -> https://x.dev/v1
	--   https://x.dev/openai/v1   -> unchanged (it already names a path)
	--   https://x.dev/v1/chat/completions -> unchanged, used verbatim
	local PROXY_HOST = "puai-proxy.davidzk.tech"
	-- Historical OpenCode settings are migrated away from this retired address.
	-- It is never recognized as an active proxy or offered as a fallback.
	local RETIRED_OPENCODE_WORKER = "puai-free-gateway.renern.workers.dev"
	local function retiredOpencode(raw)
		local parsed = urls.parse(urls.normaliseBase(raw))
		if not parsed or (parsed.host ~= PROXY_HOST and parsed.host ~= RETIRED_OPENCODE_WORKER) then return false end
		if parsed.scheme ~= "https" and parsed.scheme ~= "http" then return false end
		local port = parsed.authority:match(":(%d+)$")
		if port and port ~= (parsed.scheme == "https" and "443" or "80") then return false end
		local path = parsed.path:lower():gsub("/+$", "")
		return path == "/opencode" or path:sub(1, 10) == "/opencode/"
	end
	function M.normaliseBaseUrl(raw)
		if retiredOpencode(raw) then return "https://opencode.ai/zen/v1" end
		return urls.normaliseBase(raw)
	end

	function M.isFullEndpoint(url)
		return urls.isFullEndpoint(url)
	end

	function M.endpoint(record, suffix)
		return urls.endpoint(M.normaliseBaseUrl(record.baseUrl or ""), suffix, record.query)
	end

	function M.authHeaders(record, explicitKey)
		local key = util.trim(explicitKey or M.nextKey(record))
		local style = record.authStyle or "bearer"
		if key == "" or style == "none" then return {} end
		if style == "x-api-key" then return { ["x-api-key"] = key } end
		if style == "api-key" then return { ["api-key"] = key } end
		if style == "x-goog-api-key" then return { ["x-goog-api-key"] = key } end
		if style == "both" then
			return { ["Authorization"] = "Bearer " .. key, ["x-api-key"] = key }
		end
		return { ["Authorization"] = "Bearer " .. key }
	end

	function M.needsExecutor(record)
		return urls.isLocalHost(urls.host(M.normaliseBaseUrl(record.baseUrl)))
	end

	function M.protocolProblem(record, opts)
		if not (opts and opts.configuration) then
			local access = config.accessProblem()
			if access then return access end
			if config.vaultStatus().locked then
				return "The credential vault is locked. Unlock it in Settings > Privacy before making requests."
			end
			if record.credentialStorageError or config.get("identity.credentialStorageError") then
				return "Saved credentials could not be decoded. The stored data has been preserved. Re-enter the affected credentials and save the connection before making requests."
			end
			if record.communityCredential == true and util.trim(record.apiKey) == "" then
				return "Included credentials can only be restored for the official Project UAI Free endpoint. Edit this connection and enter your own credentials or select Project UAI Free."
			end
			local availability = communityKey.problem(record)
			if availability then return availability end
			if record.credentialsOmitted == true then
				return "Provider credentials were not saved. Enter this session's API key or custom connection credentials, then save the provider. Settings > Privacy controls credential storage."
			end
		end
		if record.preset == "projectuai-free" and not communityKey.isApplied(record) then
			return "Project UAI Free uses community access at its official endpoint. Choose the separate HCNSEC provider for a personal key, or Custom endpoint for another server."
		end
		-- Pausing is a valid saved configuration, but must stop dispatch before a
		-- missing effective key could become an anonymous HTTP request.
		if not (opts and opts.configuration) and #M.requestKeys(record) == 0 then
			if providerKeys.mode(record) == "single" then
				if providerKeys.paused(record, providerKeys.selected(record)) then
					return "the selected API key is paused; resume it, choose another key, or turn on key rotation"
				end
				return "choose an existing API key or turn on key rotation"
			end
			if M.keyPoolSize(record) > 0 then return "all API keys are paused; resume a key before making requests" end
		end
		if record.api ~= nil and record.api ~= "openai" and record.api ~= "anthropic" and record.api ~= "gemini" then
			return "choose Chat completions, Anthropic messages or Google Gemini; this API protocol is not implemented"
		end
		local parsed = urls.parse(M.normaliseBaseUrl(record.baseUrl))
		local tunnel = env.require("net/tunnel_route")
		if tunnel.reserved(M.normaliseBaseUrl(record.baseUrl)) then
			if not M.isCline(record) or record.api ~= nil and record.api ~= "openai" then
				return "Cline requires the desktop bridge's Chat completions preset."
			end
			if util.trim(record.wsUrl) ~= "" or record.query ~= nil and (type(record.query) ~= "table" or next(record.query) ~= nil) then
				return "Cline uses the desktop bridge; custom sockets and query parameters are not supported."
			end
			if util.trim(record.apiKey) ~= "" or tunnel.hasCredentials(record.headers) then
				return "Cline uses its desktop sign-in. Remove provider keys and credential headers from this route."
			end
		end
		local path = parsed and parsed.path:gsub("/+$", "") or ""
		if path:match("/api/chat$") or path:match("/api/generate$") then
			return "Ollama's native /api routes use a different protocol; use its OpenAI-compatible base URL, usually http://127.0.0.1:11434/v1"
		end
		if (path:match("/responses$") and not M.isOpencodeGo(record) and not M.isAgentRouter(record))
			or (path:match(":generateContent$") or path:match(":streamGenerateContent$") or path:match("/generateContent$"))
				and record.api ~= "gemini" and M.opencodeGoProtocol(record) ~= "gemini" then
			return "this route uses a different API; select the matching Chat completions, Anthropic messages or Google Gemini protocol"
		end
	end

	-- Limits and learned request repairs belong to one endpoint, protocol and model.
	function M.compatibilityKey(record)
		return table.concat({ record.api or "openai", M.endpoint(record, "/models"), record.model or "" }, "\n")
	end

	local function providerRoute(record)
		local parsed = urls.parse(M.normaliseBaseUrl(record and record.baseUrl or ""))
		if not parsed then return nil end
		local path = parsed.path:gsub("/+$", "")
		local base = path:match("^(.*)/chat/completions$") or path:match("^(.*)/messages$") or path:match("^(.*)/models$")
			or path:match("^(.*)/responses$") or path:match("^(.*)/models/[^/]+:generateContent$") or path:match("^(.*)/models/[^/]+:streamGenerateContent$")
		return parsed, base or path
	end

	-- Only these exact HTTPS proxy routes inherit vendor behavior. A preset label
	-- or a matching substring cannot attach an identity to an unrelated endpoint.
	function M.proxyProvider(record)
		local parsed, path = providerRoute(record)
		if not parsed or parsed.scheme ~= "https" or parsed.host ~= PROXY_HOST then return nil end
		local port = parsed.authority:match(":(%d+)$")
		if port and port ~= "443" then return nil end
		if path == "/agentrouter/v1" then return "agentrouter" end
	end

	-- Custom hosts, paths and nonstandard ports are never silently rewritten.
	function M.proxyTarget(record)
		local parsed, path = providerRoute(record)
		if not parsed or (parsed.scheme ~= "https" and parsed.scheme ~= "http") then return nil end
		local port = parsed.authority:match(":(%d+)$")
		if port and port ~= (parsed.scheme == "https" and "443" or "80") then return nil end
		local vendor
		if (parsed.host == "agentrouter.org" or parsed.host:match("^[%w%.%-]+%.agentrouter%.org$")) and path == "/v1" then vendor = "agentrouter" end
		if not vendor then return nil end
		return "https://" .. PROXY_HOST .. "/" .. vendor .. "/v1"
			.. (parsed.query and parsed.query ~= "" and ("?" .. parsed.query) or "")
	end

	-- OpenCode compatibility metadata belongs to the official host. Retired UAI
	-- routes normalize back to Zen; they never regain proxy recovery behavior.
	function M.isOpencode(record)
		local parsed = urls.parse(M.normaliseBaseUrl(record and record.baseUrl or ""))
		return parsed ~= nil and parsed.host == "opencode.ai"
	end

	function M.isCline(record)
		return env.require("net/tunnel_route").isClineBase(M.normaliseBaseUrl(record and record.baseUrl or ""))
	end

	function M.isAgentRouter(record)
		return env.require("provider/agentrouter").matches(record)
	end

	local function officialOpencodeRoute(record)
		local parsed, path = providerRoute(record)
		if not parsed or parsed.scheme ~= "https" or parsed.host ~= "opencode.ai" then return nil end
		local port = parsed.authority:match(":(%d+)$")
		if port and port ~= "443" then return nil end
		return path:lower()
	end

	function M.isOpencodeGo(record)
		local path = officialOpencodeRoute(record)
		return path == "/inference/go/v1" or path == "/zen/go/v1"
	end

	function M.isOpencodeZen(record)
		local path = officialOpencodeRoute(record)
		return path == "/zen/v1" or path == "/inference/v1" or path == "/inference/openai/v1"
	end

	-- Go documents different wire protocols by model family. Its catalog stays
	-- separate from Zen, and unknown ids retain the user-selected protocol.
	function M.opencodeGoProtocol(record)
		if not M.isOpencodeGo(record) then return nil end
		local model = util.trim(tostring(record.model or "")):lower()
		if model:match("^gemini%-") then return "gemini" end
		if model:match("^gpt%-") or model:match("^grok%-") or model:match("^muse%-") then return "responses" end
		if model:match("^claude%-") or model:match("^minimax%-") or model:match("^qwen") then return "anthropic" end
		if model:match("^deepseek%-") then return "openai" end
		return nil
	end

	-- Host based so manually entered gateways keep the same required identity.
	function M.requiresClaude(record)
		if M.isAgentRouter(record) or M.proxyProvider(record) == "agentrouter" then return true end
		local base = util.trim(tostring(record and record.baseUrl or "")):lower()
		local authority = base:match("^https?://([^/%?#]+)")
		if not authority or authority:find("@", 1, true) then return false end
		local host = authority:gsub(":%d+$", ""):gsub("%.$", "")
		return host == "agentrouter.org" or host:match("^[%w%.%-]+%.agentrouter%.org$") ~= nil
	end

	function M.identityFor(record)
		-- A manually entered Zen endpoint gets the same compatibility identity as
		-- the preset without competing Claude/Stainless headers.
		if M.isOpencode(record) or M.isCline(record) then return "none" end
		if M.requiresClaude(record) then return "claude" end
		return (record.claudeUa ~= false) and "claude" or "none"
	end

	-- The native backend authenticates free models itself. Only waive personal
	-- credentials after its authenticated discovery confirmed this exact model;
	-- unrelated paths, paid models and direct desktop requests retain normal auth.
	function M.opencodeKeyOptional(record)
		if (record.api or "openai") ~= "openai" then return false end
		if not M.isOpencodeZen(record) then return false end
		local model = tostring(record.model or "")
		local name = model:lower()
		if name ~= "big-pickle" and not name:find("%f[%a]free%f[%A]") then return false end
		local bridge = env.require("net/bridge")
		local status = bridge.opencodeStatus()
		return status.available == true and status.state == "ready" and bridge.opencodeHasModel(model) == true
			and env.require("net/transport").coworkWeb()
	end

	local BASE62 = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	local function randomBase62(len)
		local t = {}
		for i = 1, len do
			local r = math.random(1, 62)
			t[i] = BASE62:sub(r, r)
		end
		return table.concat(t)
	end

	-- OpenCode edge gateways validate that session and request IDs carry a valid
	-- 48-bit millisecond timestamp (with a 12-bit counter). Session IDs (ses_)
	-- invert the timestamp bytes (~n) in big-endian hex, followed by 14 Base62
	-- characters. Request IDs (req_) use uninverted timestamp bytes.
	local lastOpencodeMs, opencodeCounter = 0, 0
	local function opencodeId(prefix)
		prefix = prefix or "ses_"
		local ms = math.floor((clock and clock.ms and clock.ms()) or (os.time() * 1000))
		if ms ~= lastOpencodeMs then
			lastOpencodeMs = ms
			opencodeCounter = 0
		end
		opencodeCounter = (opencodeCounter + 1) % 4096
		local n = ms * 4096 + opencodeCounter
		local inverted = (prefix == "ses_")
		local bytes = {}
		local temp = n
		for i = 6, 1, -1 do
			local b = math.floor(temp % 256)
			temp = math.floor(temp / 256)
			if inverted then
				b = 255 - b
			end
			bytes[i] = string.format("%02x", b)
		end
		return prefix .. table.concat(bytes) .. randomBase62(14)
	end
	M.opencodeId = opencodeId

	local function validOpencodeSession(id)
		if type(id) ~= "string" or #id ~= 30 or not id:match("^ses_%x%x%x%x%x%x%x%x%x%x%x%x")
			or not id:sub(17):match("^[A-Za-z0-9]+$") then
			return false
		end
		local hex = id:sub(5, 16)
		local recovered = 0
		for i = 1, 12, 2 do
			local b = 255 - (tonumber(hex:sub(i, i + 1), 16) or 0)
			recovered = recovered * 256 + b
		end
		local sesMs = math.floor(recovered / 4096)
		local nowMs = math.floor(((clock and clock.ms and clock.ms()) or (os.time() * 1000))) % (2 ^ 36)
		local diff = (nowMs - sesMs) % (2 ^ 36)
		return diff < 2592000000 or diff > (2 ^ 36 - 600000)
	end
	M.validOpencodeSession = validOpencodeSession

	local sessionCache = {}
	M.opencodeSessionCache = sessionCache

	function M.opencodeSessionFor(record, context)
		local session = nil
		local sessionId = nil
		if type(context) == "table" then
			if context.session then
				session = context.session
				sessionId = session.id or context.sessionId
			elseif context.id and (type(context.emit) == "function" or type(context.send) == "function") then
				session = context
				sessionId = session.id
			elseif context.sessionId then
				sessionId = context.sessionId
			end
		elseif type(context) == "string" and context ~= "" then
			sessionId = context
		end

		if session then
			local existing = session.opencodeSession
			if validOpencodeSession(existing) then
				if session.id then sessionCache[session.id] = existing end
				return existing
			end
			if session.id and validOpencodeSession(sessionCache[session.id]) then
				session.opencodeSession = sessionCache[session.id]
				return sessionCache[session.id]
			end
			local created = opencodeId("ses_")
			session.opencodeSession = created
			if session.id then sessionCache[session.id] = created end
			return created
		end

		if sessionId then
			if validOpencodeSession(sessionCache[sessionId]) then
				return sessionCache[sessionId]
			end
			local created = opencodeId("ses_")
			sessionCache[sessionId] = created
			return created
		end

		if not validOpencodeSession(record.opencodeSession) then
			record.opencodeSession = opencodeId("ses_")
			-- Header construction also runs for unsaved provider-editor drafts.
			if M.get(record.id) == record then M.save(record, { quiet = true }) end
		end
		return record.opencodeSession
	end

	function M.opencodeHeaders(record, context)
		if not M.isOpencode(record) then return {} end
		if M.isOpencodeGo(record) then
			return {
				["User-Agent"] = "ProjectUAI/" .. tostring(env.info and env.info.version or "3.2.0"),
				["x-opencode-session"] = M.opencodeSessionFor(record, context),
			}
		end
		-- Direct Chat and Responses were verified with this desktop fingerprint.
		-- The CLI fingerprint and its project/request headers trigger FreeTierError.
		local version, client, channel = "2.0.27", "desktop", "latest"
		if type(record.opencode) == "table" then
			local configuredVersion = util.trim(tostring(record.opencode.version or ""))
			local configuredClient = util.trim(tostring(record.opencode.client or ""))
			if configuredVersion ~= "" then version, channel = configuredVersion, "stable" end
			if configuredClient ~= "" then client = configuredClient end
		end
		local sessionId = M.opencodeSessionFor(record, context)
		local ua
		if version:find("^opencode/") then
			ua = version
		elseif version:find("/", 1, true) then
			ua = "opencode/" .. version
		else
			ua = "opencode/" .. channel .. "/" .. version .. "/" .. client
		end
		return {
			["x-opencode-session"] = sessionId,
			["x-opencode-session-id"] = sessionId,
			["x-session-affinity"] = sessionId,
			["X-Session-Id"] = sessionId,
			["x-opencode-client"] = client,
			["User-Agent"] = ua,
			["accept"] = "*/*",
		}
	end

	-- A record always has every field, so no consumer needs a nil check.
	function M.blank(presetId)
		local preset = catalog.get(presetId or "custom") or catalog.get("custom")
		local record = {
			id = "",
			preset = preset.id,
			label = preset.label,
			baseUrl = preset.baseUrl,
			apiKey = "",
			authStyle = preset.authStyle or "bearer",
			-- Which wire protocol the record speaks. Absent means chat completions,
			-- which is what every record saved before the second adapter existed has.
			api = preset.api or "openai",
			models = preset.defaultModel and { preset.defaultModel } or util.deepCopy(preset.models or {}),
			model = preset.defaultModel or (preset.models or {})[1] or "",
			headers = util.deepCopy(preset.headers or {}),
			params = util.deepCopy(preset.params or {}),
			query = util.deepCopy(preset.query or {}),

			stream = true,
			-- `~= false` rather than an and/or chain: `(x == false) and false or true`
			-- is still true when x is false, which is the trap both forms of this line
			-- fell into. A preset's deliberate `false` has to survive the copy.
			claudeUa = preset.claudeUa ~= false,
			enabled = true,
			order = 0,
			wsUrl = "",
			note = preset.note,
			requires = preset.requires,
			health = { ok = 0, fail = 0, streak = 0, lastError = "", cooldownUntil = 0, lastMs = 0 },
		}
		if preset.free then communityKey.apply(record) end
		return record
	end

	local function ensureId(wanted)
		local base = util.trim(wanted):lower():gsub("[^%w%-_]", "-"):gsub("%-+", "-"):gsub("^%-", "")
		if base == "" then base = "provider" end
		local taken = {}
		for _, record in ipairs(M.list()) do taken[record.id] = true end
		if not taken[base] then return base end
		for index = 2, 99 do
			local candidate = base .. "-" .. tostring(index)
			if not taken[candidate] then return candidate end
		end
		return base .. "-" .. tostring(clock.ms())
	end

	function M.list()
		M.migrate()
		local vault = config.vaultStatus()
		local stored = config.get("providers.list", {})
		if type(stored) ~= "table" then return {} end
		local out, migrated = {}, false
		for _, record in ipairs(stored) do
			if type(record) == "table" then
				if not vault.locked and not vault.busy and providerKeys.ensureIds(record) then migrated = true end
				out[#out + 1] = record
			end
		end
		if migrated then config.save() end
		table.sort(out, function(a, b)
			if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
			return tostring(a.id) < tostring(b.id)
		end)
		return out
	end

	function M.get(id)
		for _, record in ipairs(M.list()) do
			if record.id == id then return record end
		end
		return nil
	end

	function M.count()
		return #M.list()
	end

	-- Validation is deliberately about reachability, not taste: a record with a
	-- plausible URL and, where needed, a key is allowed even if the vendor turns
	-- out to reject it. The health counters are what report that.
	function M.validate(record)
		local problems = {}
		if util.trim(record.label) == "" then problems[#problems + 1] = "give the provider a name" end
		local base, urlError = M.normaliseBaseUrl(record.baseUrl)
		if base == "" then
			problems[#problems + 1] = "base URL is required"
		elseif urlError then
			problems[#problems + 1] = urlError
		end
		local protocolProblem = M.protocolProblem(record, { configuration = true })
		if protocolProblem then problems[#problems + 1] = protocolProblem end
		if util.trim(record.wsUrl) ~= "" then
			local socketUrl = urls.parse(record.wsUrl)
			if not socketUrl or (socketUrl.scheme ~= "ws" and socketUrl.scheme ~= "wss") then
				problems[#problems + 1] = "socket URL must be a ws:// or wss:// gateway that implements UAI's envelope protocol"
			end
		end
		if (record.authStyle or "bearer") ~= "none" and util.trim(record.apiKey) == "" and not M.opencodeKeyOptional(record) then
			problems[#problems + 1] = "an API key is required for this auth style"
		end
		local keysValid, keysProblem = providerKeys.validate(record)
		if not keysValid then problems[#problems + 1] = keysProblem end
		local headersValid, headersProblem = env.require("net/headers").validate(record.headers)
		if not headersValid then problems[#problems + 1] = headersProblem end
		-- Azure takes the model from the deployment in the URL; everyone else needs
		-- one named, and nothing here will guess it.
		if record.preset ~= "azure" and util.trim(record.model) == "" then
			problems[#problems + 1] = "fetch the model list or add a model id"
		elseif util.trim(record.model) ~= "" then
			local clean, why = env.require("provider/model_id").parse(record.model)
			if not clean then problems[#problems + 1] = why end
		end
		if M.needsExecutor(record) and caps.http ~= "executor" then
			problems[#problems + 1] = "local/private endpoints need an executor HTTP function on the machine that can reach the server; this host has none"
		end
		return #problems == 0, problems
	end

	function M.save(record, opts)
		if requestSnapshots[record] then return true end
		local access = config.accessProblem()
		if access then return false, { access } end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return false, { "Unlock the credential vault and finish any vault operation before editing providers" } end
		opts = opts or {}
		record.baseUrl = M.normaliseBaseUrl(record.baseUrl)
		if M.requiresClaude(record) then record.claudeUa = true end
		local ok, problems = M.validate(record)
		if not ok and not opts.force then return false, problems end
		providerKeys.ensureIds(record)
		if opts.credentialsRestored then
			record.credentialsOmitted = nil
			record.storedCredentials, record.credentialStorageError = nil, nil
			if not communityKey.isApplied(record) then record.communityCredential, record.communityKeyState = nil, nil end
		end

		local list = config.get("providers.list", {})
		if type(list) ~= "table" then list = {} end
		if util.trim(record.id) == "" then
			record.id = ensureId(record.label ~= "" and record.label or record.preset)
			record.order = #list + 1
			list[#list + 1] = record
		else
			local replaced = false
			for index, existing in ipairs(list) do
				if existing.id == record.id then
					list[index] = record
					replaced = true
				end
			end
			if not replaced then
				record.order = #list + 1
				list[#list + 1] = record
			end
		end
		config.set("providers.list", list)
		if util.trim(config.get("providers.active", "")) == "" then
			config.set("providers.active", record.id)
		end
		M.changed:fire("save", record)
		return true, record
	end

	-- The OpenRouter attribution URL moved with the repository. A record saved
	-- before the move carries the retired value in the headers copied from its
	-- preset at creation, and saved headers deliberately override the built-in
	-- default, so the old app would keep receiving that client's traffic forever.
	-- Rewrite only the exact retired value: a referer the user set themselves is
	-- left alone. Idempotent, and writes nothing when there is nothing to change.
	local RETIRED_REFERER = "https://carldv.github.io/ProjectUAI/"
	function M.migrate()
		local vault = config.vaultStatus()
		if config.accessProblem() or vault.locked or vault.busy then return 0 end
		local preset = catalog.get("openrouter")
		local replacement = preset and preset.headers and preset.headers["HTTP-Referer"]
		local stored = config.get("providers.list", {})
		if type(stored) ~= "table" then return 0 end
		local retired = string.gsub(RETIRED_REFERER, "/+$", "")
		local changed = 0
		for _, record in ipairs(stored) do
			if type(record) == "table" then
				local migrated = communityKey.migrate(record)
				local restored = communityKey.restore(record)
				local separated = communityKey.separate(record)
				if migrated or restored or separated then changed = changed + 1 end
			end
			if type(record) == "table" and retiredOpencode(record.baseUrl) then
				record.baseUrl = "https://opencode.ai/zen/v1"
				record.wsUrl = ""
				changed = changed + 1
			end
			local headers = type(record) == "table" and record.headers
			if type(headers) == "table" and type(replacement) == "string" and replacement ~= "" then
				for key, value in pairs(headers) do
					if type(key) == "string" and key:lower() == "http-referer" and type(value) == "string"
						and string.gsub(value, "/+$", "") == retired then
						headers[key] = replacement
						changed = changed + 1
					end
				end
			end
		end
		if changed > 0 then
			config.set("providers.list", stored)
			config.save()
		end
		return changed
	end

	function M.remove(id)
		local access = config.accessProblem()
		if access then return false, access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return false, "Unlock the credential vault and finish any vault operation before removing providers." end
		local list = config.get("providers.list", {})
		local kept = {}
		for _, record in ipairs(list) do
			if record.id ~= id then kept[#kept + 1] = record end
		end
		config.set("providers.list", kept)
		if config.get("providers.active", "") == id then
			config.set("providers.active", kept[1] and kept[1].id or "")
		end
		env.require("provider/model_preferences").forget(id)
		M.changed:fire("remove", id)
		return true
	end

	function M.setActive(id)
		local access = config.accessProblem()
		if access then return false, access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return false, "Unlock the credential vault and finish any vault operation before changing providers." end
		if not M.get(id) then return false, "unknown provider" end
		config.set("providers.active", id)
		M.changed:fire("active", id)
		return true
	end

	function M.active()
		local wanted = config.get("providers.active", "")
		local record = M.get(wanted)
		if record then return record end
		for _, candidate in ipairs(M.list()) do
			if candidate.enabled ~= false then return candidate end
		end
		return nil
	end

	function M.setModel(id, model)
		local access = config.accessProblem()
		if access then return false, access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return false, "Unlock the credential vault and finish any vault operation before editing providers." end
		local record = M.get(id)
		if not record then return false end
		local clean, why = env.require("provider/model_id").parse(model)
		if not clean then return false, why end
		local previousModel, previous = record.model, record.models
		record.model, record.models = clean, util.deepCopy(record.models or {})
		if not util.find(record.models, function(item) return item == clean end) then
			table.insert(record.models, 1, clean)
		end
		local ok, problems = M.save(record, { force = true })
		if not ok then
			record.model, record.models = previousModel, previous
			return false, type(problems) == "table" and table.concat(problems, "; ") or problems
		end
		env.require("provider/model_preferences").remember(record, clean)
		M.changed:fire("model", record)
		return true
	end

	function M.reorder(id, direction)
		local access = config.accessProblem()
		if access then return false, access end
		local vault = config.vaultStatus()
		if vault.locked or vault.busy then return false, "Unlock the credential vault and finish any vault operation before editing providers." end
		local list = M.list()
		for index, record in ipairs(list) do
			if record.id == id then
				local swapWith = list[index + direction]
				if not swapWith then return false end
				local mine, theirs = record.order or index, swapWith.order or (index + direction)
				record.order, swapWith.order = theirs, mine
				config.set("providers.list", list)
				M.changed:fire("order", id)
				return true
			end
		end
		return false
	end

	-- Health -----------------------------------------------------------------

	local function health(record)
		local clean = env.require("provider/health").read(record)
		record.health = type(record.health) == "table" and record.health or {}
		for key, value in pairs(clean) do record.health[key] = value end
		return record.health
	end

	function M.markOk(record, ms)
		local state = health(record)
		state.ok = state.ok + 1
		state.streak = 0
		state.lastError = ""
		state.cooldownUntil = 0
		state.lastMs = ms or state.lastMs
		M.changed:fire("health", record)
	end

	-- Consecutive failures put a provider on the bench rather than the first one:
	-- a single 500 from an otherwise healthy endpoint is noise, and demoting on it
	-- would flap the active provider on every hiccup.
	function M.markFail(record, message)
		local state = health(record)
		state.fail = state.fail + 1
		-- Account- or model-scope refusals are not endpoint health: free-tier
		-- lockout and unsupported-protocol refusals persist past any cooldown,
		-- so benching on them only delays the inevitable message.
		local text = tostring(message or "")
		local scopeError = text:find("free tier can only be used from within OpenCode", 1, true) ~= nil
			or text:find("does not support this protocol", 1, true) ~= nil
			or text:find("ModelProtocolUnsupported", 1, true) ~= nil
		if not scopeError then
			state.streak = state.streak + 1
		end
		state.lastError = util.ellipsis(message or "request failed", 200)
		if state.streak >= COOLDOWN_AFTER then
			state.cooldownUntil = clock.ms() + COOLDOWN_SECONDS * 1000
			log.warn("provider", record.label .. " benched for " .. tostring(COOLDOWN_SECONDS) .. "s", state.lastError)
		end
		M.changed:fire("health", record)
	end

	function M.cooling(record)
		local state = health(record)
		return (state.cooldownUntil or 0) > clock.ms()
	end

	-- Ordered attempt list: the active provider, then every other enabled one that
	-- is not cooling down, then -- if that leaves nothing -- the cooling ones
	-- anyway, because refusing to try at all is worse than trying a bad endpoint.
	function M.chain()
		local out = {}
		local seen = {}
		local activeRecord = M.active()
		if activeRecord and activeRecord.enabled ~= false then
			out[#out + 1] = activeRecord
			seen[activeRecord.id] = true
		end
		if config.get("agent.fallback", true) then
			for _, record in ipairs(M.list()) do
				if not seen[record.id] and record.enabled ~= false and not M.cooling(record) then
					out[#out + 1] = record
					seen[record.id] = true
				end
			end
			if #out == 0 then
				for _, record in ipairs(M.list()) do
					if record.enabled ~= false then out[#out + 1] = record end
				end
			end
		end
		return out
	end

	function M.summary(record)
		if not record then return "no provider configured" end
		local state = health(record)
		local bits = { record.label }
		if record.model ~= "" then bits[#bits + 1] = record.model end
		if M.cooling(record) then bits[#bits + 1] = "cooling down" end
		if state.lastMs and state.lastMs > 0 then bits[#bits + 1] = util.formatDuration(state.lastMs) end
		return table.concat(bits, " | ")
	end

	env.require("runtime/dispose").add(config.changed:connect(function(path)
		if path == "security.vault" then
			local vault = config.vaultStatus()
			if not vault.locked and not vault.busy then M.migrate() end
			M.changed:fire("vault")
		end
	end), "provider vault state")
	return M
end
