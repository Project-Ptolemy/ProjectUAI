-- Public authentication follows fresh official catalog facts, never model names.
return function(env)
	local util = env.require("runtime/util")
	local urls = env.require("net/url")
	local keys = env.require("runtime/provider_keys")
	local clock = env.require("runtime/clock")
	local M = {}
	local catalogs, TTL_MS = {}, 10 * 60 * 1000
	local BASES = { ["/zen/v1"] = true, ["/inference/v1"] = true, ["/inference/openai/v1"] = true }
	local function access()
		local config = env.require("runtime/config")
		local vault = config.vaultStatus()
		return not config.accessProblem() and not vault.locked and not vault.busy
	end
	local function same(a, b, depth)
		depth = (depth or 0) + 1
		if depth > 32 then return false end
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key], depth) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end
	local function credentialHeaders(headers)
		for name in pairs(headers or {}) do
			local lower = tostring(name):lower()
			if lower:find("auth", 1, true) or lower:find("api[-_]?key") or lower:find("token", 1, true)
				or lower:find("secret", 1, true) or lower:find("cookie", 1, true) or lower:find("credential", 1, true)
				or lower:find("organization", 1, true) or lower:find("%f[%a]org%f[%A]") or lower:find("[-_]org[-_]?id$") then return true end
		end
		return false
	end
	function M.route(record)
		if type(record) ~= "table" or (record.api or "openai") ~= "openai" then return false end
		local raw = util.trim(record.baseUrl)
		if raw:find("[?#]") or util.trim(record.wsUrl) ~= "" then return false end
		if record.query ~= nil and (type(record.query) ~= "table" or next(record.query) ~= nil) then return false end
		local parsed = urls.parse(urls.normaliseBase(raw))
		if not parsed or parsed.scheme ~= "https" then return false end
		local authority = parsed.authority:lower()
		if authority ~= "opencode.ai" and authority ~= "opencode.ai:443" then return false end
		local path = parsed.path:gsub("/+$", "")
		path = path:match("^(.*)/chat/completions$") or path:match("^(.*)/models$") or path
		return BASES[path] == true
	end
	local function scope(record)
		if not env.require("net/headers").validate(record.headers) then return nil end
		local raw = { baseUrl = urls.normaliseBase(record.baseUrl), api = record.api or "openai", authStyle = record.authStyle or "bearer",
			apiKey = record.apiKey, headers = record.headers or {}, query = record.query or {}, wsUrl = record.wsUrl or "", params = record.params or {}, keyMode = keys.mode(record),
			selectedKey = keys.mode(record) == "single" and keys.selected(record) or nil, keyPaused = keys.pauseFlags(record),
			credentialsOmitted = record.credentialsOmitted, credentialStorageError = record.credentialStorageError,
			storedCredentials = record.storedCredentials ~= nil }
		local nodes, seen = 0, {}
		local function copy(value, depth)
			nodes = nodes + 1
			if nodes > 8192 or depth > 30 then error("invalid catalog scope", 0) end
			local kind = type(value)
			if kind == "number" then
				if value ~= value or math.abs(value) == math.huge then error("invalid catalog scope", 0) end
				return value
			elseif kind == "string" or kind == "boolean" then return value
			elseif kind ~= "table" or seen[value] then error("invalid catalog scope", 0) end
			seen[value] = true
			local out = {}
			for key, child in pairs(value) do
				if type(key) ~= "string" and type(key) ~= "number" then error("invalid catalog scope", 0) end
				out[key] = copy(child, depth + 1)
			end
			seen[value] = nil
			return out
		end
		local ok, out = pcall(copy, raw, 0)
		return ok and out or nil
	end
	function M.credentials(record)
		if not M.route(record) or (record.authStyle or "bearer") ~= "bearer" or #keys.keys(record) > 0 or keys.mode(record) == "single" then return false end
		if record.credentialsOmitted or record.credentialStorageError or record.storedCredentials ~= nil then return false end
		if not scope(record) or credentialHeaders(record.headers) then return false end
		if record.params ~= nil and type(record.params) ~= "table" then return false end
		return true
	end
	local function selectedModel(record)
		return not record.params or record.params.model == nil or record.params.model == record.model
	end
	local function array(value, limit)
		if not util.isArray(value) or #value == 0 or #value > limit then return false end
		for key in pairs(value) do if key < 1 or key > #value or key ~= math.floor(key) then return false end end
		return true
	end
	local function zero(value)
		if type(value) == "number" then return value == 0 end
		return type(value) == "table" and type(value.price) == "number" and value.price == 0
	end
	local function zeroCache(value)
		if value == nil then return true end
		if type(value) ~= "table" then return false end
		for _, price in pairs(value) do if not zero(price) then return false end end
		return true
	end
	local function zeroTier(tier)
		if type(tier) ~= "table" or not zero(tier.input) or not zero(tier.output) or not zeroCache(tier.cache) then return false end
		return (type(tier.input) ~= "table" or zeroCache(tier.input.cache))
			and (type(tier.output) ~= "table" or zeroCache(tier.output.cache))
	end
	function M.freePrices(cost)
		if type(cost) ~= "table" then return false end
		if array(cost, 1000) then
			for _, tier in ipairs(cost) do if not zeroTier(tier) then return false end end
			return true
		end
		if not zeroTier(cost.text) then return false end
		for name, tier in pairs(cost) do if type(name) ~= "string" or not zeroTier(tier) then return false end end
		return true
	end
	function M.observe(record, url, payload)
		if not access() or not M.route(record) or url ~= urls.endpoint(urls.normaliseBase(record.baseUrl), "/models", record.query) then return false end
		local current = scope(record)
		if not current then return false end
		for index = #catalogs, 1, -1 do if same(catalogs[index].scope, current) then table.remove(catalogs, index) end end
		if type(payload) ~= "table" or payload.error ~= nil or not array(payload.data, 10000) then return false end
		local rows, seen = {}, {}
		for _, row in ipairs(payload.data) do
			local id = type(row) == "table" and env.require("provider/model_id").parse(row.id) or nil
			if id and not seen[id] then
				seen[id] = true
				local api = type(row.api) == "table" and row.api or {}
				local chat = type(api["chat-completions"]) == "table" and M.route({ baseUrl = api["chat-completions"].base_url })
				local responses = type(api.responses) == "table" and M.route({ baseUrl = api.responses.base_url })
				local free = M.freePrices(row.cost)
				rows[id] = { kind = type(row.type) == "string" and row.type or nil, chat = chat == true, responses = responses == true,
					protocol = type(row.recommended_api) == "string" and row.recommended_api or nil,
					free = free, public = row.type == "chat" and chat == true and free,
					tools = type(row.capabilities) == "table" and type(row.capabilities.tools) == "table" and row.capabilities.tools.supported == true }
			elseif id then rows[id] = nil end
		end
		catalogs[#catalogs + 1] = { scope = current, at = clock.ms(), rows = rows, owners = { [record.id or record] = true } }
		if #catalogs > 32 then table.remove(catalogs, 1) end
		return true
	end
	local function catalog(record)
		if not access() or not M.route(record) then return nil end
		local current = scope(record)
		if not current then return nil end
		for index = #catalogs, 1, -1 do
			local entry = catalogs[index]
			if clock.since(entry.at) >= TTL_MS then table.remove(catalogs, index)
			elseif same(entry.scope, current) then
				entry.owners[record.id or record] = true
				return entry
			end
		end
	end
	function M.info(record, id)
		local entry = catalog(record)
		local info = entry and entry.rows[id or record.model]
		return info and util.copy(info) or nil
	end
	function M.current(record) return catalog(record) ~= nil end
	function M.available(record, body)
		if not M.credentials(record) or not selectedModel(record) then return false end
		if body ~= nil and (type(body) ~= "table" or body.model ~= record.model or type(body.messages) ~= "table" or body.input ~= nil) then return false end
		local info = M.info(record)
		return info ~= nil and info.public == true
	end
	function M.pending(record)
		return access() and M.credentials(record) and selectedModel(record) and env.require("provider/model_id").parse(record.model) ~= nil and catalog(record) == nil
	end
	function M.defaultKey(record, body) return M.available(record, body) and "public" or nil end
	function M.ensure(record, opts)
		if not M.credentials(record) or not access() then return false, "Public access requires a reviewed standard Zen connection." end
		opts = opts or {}
		if opts.aborted and opts.aborted() then return false, "aborted" end
		if env.require("net/deadline").expired(opts.deadlineMs) then return false, "deadline: request budget expired before catalog verification" end
		if M.available(record) then return true end
		if M.pending(record) then
			local _, problem = env.require("provider/models").discover(record, { force = true, timeout = opts.timeout, deadlineMs = opts.deadlineMs, aborted = opts.aborted })
			if env.require("net/http").terminal(problem) then return false, problem end
		end
		if M.available(record) then return true end
		return false, "The current Zen catalog does not verify public free Chat access for this model. Fetch the model list and choose a free Chat model, or add your own API key."
	end
	function M.invalidate(owner)
		if owner == nil then catalogs = {}; return end
		local key = type(owner) == "table" and (owner.id or owner) or owner
		for index = #catalogs, 1, -1 do if catalogs[index].owners[key] then table.remove(catalogs, index) end end
	end
	return M
end
