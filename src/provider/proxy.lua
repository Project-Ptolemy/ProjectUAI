-- One bounded recovery from an explicit official-client refusal. HTTP remains
-- owned by net/http; this module owns classification and guarded URL changes.
return function(env)
	local util = env.require("runtime/util")
	local clock = env.require("runtime/clock")
	local log = env.require("runtime/log")
	local registry = env.require("provider/registry")
	local M = {}

	local function clientRefusal(value)
		if type(value) ~= "string" then return false end
		local text = value:lower():gsub("[_%-]", " "):gsub("%s+", " ")
		return text:find("%f[%a]unauthori[sz]ed client%f[%A]") ~= nil
			or text:find("%f[%a]unauthori[sz]edclient%f[%A]") ~= nil
			or text:find("%f[%a]unauthori[sz]edclienterror%f[%A]") ~= nil
			or text:find("%f[%a]client is not authorized%f[%A]") ~= nil
			or text:find("%f[%a]client is not authorised%f[%A]") ~= nil
	end

	local function credentialOrAccountRefusal(value)
		if type(value) ~= "string" then return false end
		local text = value:lower():gsub("[_%-]", " "):gsub("%s+", " ")
		return text:find("invalid api key", 1, true) ~= nil or text:find("incorrect api key", 1, true) ~= nil
			or text:find("expired api key", 1, true) ~= nil or text:find("api key is invalid", 1, true) ~= nil
			or text:find("api key expired", 1, true) ~= nil or text:find("invalid key", 1, true) ~= nil
			or text:find("freetiererror", 1, true) ~= nil or text:find("insufficient permissions", 1, true) ~= nil
	end

	local function errorObject(value)
		for _, key in ipairs({ "type", "code", "message", "name", "detail" }) do
			if credentialOrAccountRefusal(value[key]) then return false end
		end
		return clientRefusal(value.type) or clientRefusal(value.code) or clientRefusal(value.message)
			or clientRefusal(value.name) or clientRefusal(value.detail)
	end

	function M.isClientRefusal(res)
		if type(res) ~= "table" then return false end
		local status = tonumber(res.status)
		if status ~= 400 and status ~= 401 and status ~= 403 and status ~= 200 then return false end
		local body = tostring(res.body or "")
		if #body > 65536 then return false end
		local decoded = util.decode(body)
		if type(decoded) == "table" then
			-- Never search the whole body: a successful answer can quote this phrase.
			local failure = decoded.error
			if type(failure) == "string" then return not credentialOrAccountRefusal(failure) and clientRefusal(failure) end
			if type(failure) == "table" then return errorObject(failure) end
			if status == 200 and decoded.type ~= "error" then return false end
			return errorObject(decoded)
		end
		-- Some gateways return a short plain-text refusal. HTML and streams never
		-- qualify, and a 200 without a structured error is never a retry trigger.
		return status ~= 200 and #body <= 512 and not body:find("<", 1, true)
			and not body:find("data:", 1, true) and not credentialOrAccountRefusal(body) and clientRefusal(body)
	end

	local function same(a, b)
		if type(a) ~= type(b) then return false end
		if type(a) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end

	local function connection(record)
		return { baseUrl = registry.normaliseBaseUrl(record.baseUrl), api = record.api or "openai",
			model = record.model, apiKey = record.apiKey, authStyle = record.authStyle,
			headers = record.headers or {}, query = record.query or {}, claudeUa = record.claudeUa,
			wsUrl = record.wsUrl }
	end

	-- A recovery belongs to one operation, not a provider-global retry loop. Drafts
	-- change locally; only the registered live record can update saved settings.
	function M.new(record, opts)
		opts = opts or {}
		local source = util.deepCopy(connection(record))
		local registered = registry.get(record.id) == record
		local attempted = false
		local handle = {}
		function handle.recover(res, err)
			if attempted or err or not M.isClientRefusal(res) then return false end
			local target = registry.proxyTarget(record)
			if not target or not same(source, connection(record)) then return false end
			if registered and registry.get(record.id) ~= record then return false end
			if opts.deadlineMs and clock.ms() >= opts.deadlineMs then return false end
			if opts.aborted then
				local ok, stopped = pcall(opts.aborted)
				if not ok or stopped then return false end
			end
			attempted = true
			record.baseUrl = target
			if registry.requiresClaude(record) then record.claudeUa = true end
			local expected = util.deepCopy(connection(record))
			if registered then registry.save(record, { force = true }) end
			local reason = "unauthorized client; switched to the Project UAI proxy"
			log.info("provider", tostring(record.label or "Provider") .. ": " .. reason)
			registry.changed:fire("proxy", record)
			if opts.onRetry then
				if not pcall(opts.onRetry, { attempt = 1, attempts = 2, wait = 0,
					reason = reason, status = res.status, proxy = true }) then
					log.warn("provider", "proxy retry callback failed safely")
				end
			end
			-- Observers may edit or remove the provider while being notified.
			if not same(expected, connection(record)) or (registered and registry.get(record.id) ~= record) then return false end
			return true
		end
		return handle
	end

	return M
end
