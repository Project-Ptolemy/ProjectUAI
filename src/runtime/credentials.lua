-- Credential projections for disk and explicit configuration transfers.
-- This reduces saved exposure; executor peers can still inspect live memory.
return function(env)
	local util = env.require("runtime/util")
	local codec = env.require("runtime/credential_codec")
	local vault = env.require("runtime/credential_vault")
	local retirement = env.require("runtime/provider_retirement")
	local M = {}
	local SECRET_FIELDS = {
		key = true, apikey = true, apikeys = true, token = true, accesstoken = true,
		refreshtoken = true, idtoken = true, password = true, secret = true,
		clientsecret = true, credential = true, credentials = true, authorization = true,
		proxyauthorization = true, cookie = true, setcookie = true, xapikey = true,
		keyrotation = true, storedcredentials = true, credentialvault = true,
		credentialvaultlocked = true,
	}
	local PROVIDER_FIELDS = { "apiKey", "keyNames", "keyIds", "keyPaused", "keyMode", "selectedKey",
		"headers", "query", "params", "baseUrl", "wsUrl", "health", "repairs", "repairScope", "maxTokensCap",
		"toolsCap", "opencodeSession", "credentialsOmitted" }
	-- Read old vaults/byte envelopes before dropping their obsolete reference.
	local LEGACY_PROVIDER_FIELDS = util.deepCopy(PROVIDER_FIELDS)
	LEGACY_PROVIDER_FIELDS[#LEGACY_PROVIDER_FIELDS + 1] = "communityKeyState"
	local FIELD_TYPES = { apiKey = "string", baseUrl = "string", wsUrl = "string", repairScope = "string",
		opencodeSession = "string", keyMode = "string", selectedKey = "number", credentialsOmitted = "boolean",
		keyNames = "table", keyIds = "table", keyPaused = "table", headers = "table", query = "table", params = "table",
		health = "table", repairs = "table", maxTokensCap = "table", toolsCap = "table", communityKeyState = "table", extraHeaders = "table" }
	local function records(snapshot)
		return type(snapshot) == "table" and type(snapshot.providers) == "table"
			and type(snapshot.providers.list) == "table" and snapshot.providers.list or {}
	end
	local function secretField(name)
		local clean = tostring(name):lower():gsub("[_%-%s]", "")
		return SECRET_FIELDS[clean] == true
	end

	-- Query names are provider-defined, so none are assumed safe. A token can
	-- also appear in userinfo or a fragment, even without an explicit scheme.
	function M.cleanUrl(value)
		if type(value) ~= "string" then return value end
		local clean = util.trim(value):match("^[^?#]*") or ""
		local scheme, rest = clean:match("^(%a[%w+%.%-]*://)(.*)$")
		if not scheme then
			if clean:sub(1, 2) == "//" then scheme, rest = "//", clean:sub(3)
			else scheme, rest = "", clean end
		end
		local authority, path = rest:match("^([^/]*)(.*)$")
		return scheme .. (authority or ""):gsub("^.*@", "") .. (path or "")
	end

	local function scrub(value, path)
		if type(value) ~= "table" then return value end
		local out = {}
		for key, item in pairs(value) do
			local name = tostring(key):lower()
			local memoryName = path == "memory.entries[]" and name == "key"
			if not secretField(key) or memoryName then
				if name == "headers" or name == "extraheaders" or name == "query" then out[key] = {}
				elseif name == "baseurl" or name == "wsurl" or name == "url" then out[key] = M.cleanUrl(item)
				else
					local child = type(key) == "number" and (path .. "[]") or (path == "" and key or path .. "." .. tostring(key))
					out[key] = scrub(item, child)
				end
			end
		end
		return out
	end

	local function provider(record)
		if type(record) ~= "table" then return record end
		local out = scrub(record, "provider")
		local omitted = util.trim(record.apiKey) ~= ""
			or M.cleanUrl(record.baseUrl) ~= record.baseUrl or M.cleanUrl(record.wsUrl) ~= record.wsUrl
		for _, field in ipairs({ "headers", "query", "params" }) do
			if type(record[field]) == "table" and next(record[field]) ~= nil then omitted = true end
		end
		-- Custom body fields can carry authentication under arbitrary names.
		out.headers, out.query, out.params = {}, {}, {}
		out.apiKey = ""
		out.communityCredential, out.communityKeyState = nil, nil
		out.credentialsOmitted = omitted or record.credentialsOmitted == true or nil
		out.keyRotation = nil
		-- Compatibility lessons duplicate the complete URL, including query
		-- authentication. Relearn them after credentials are supplied again.
		out.repairs, out.repairScope, out.maxTokensCap, out.toolsCap = nil, nil, nil, nil
		if out.apiKey == "" then
			out.keyNames, out.keyIds, out.keyPaused = nil, nil, nil
			out.keyMode, out.selectedKey = "rotate", 1
		end
		-- Error bodies may echo arbitrary credentials; they are transient when
		-- credentials are not being retained, even if they do not look like a key.
		if type(out.health) == "table" then out.health.lastError = "" end
		out.opencodeSession = nil
		return out
	end

	local function projectProviders(snapshot)
		local records = type(snapshot.providers) == "table" and snapshot.providers.list
		local headers = type(snapshot.identity) == "table" and snapshot.identity.extraHeaders
		local omittedIdentity = type(headers) == "table" and next(headers) ~= nil
		if type(records) == "table" then
			for index, record in pairs(records) do
				records[index] = provider(record)
				-- Unreadable saved data remains recoverable until an explicit edit.
				if type(record) == "table" and record.storedCredentials ~= nil then
					records[index].storedCredentials = util.deepCopy(record.storedCredentials)
				end
				if omittedIdentity and type(records[index]) == "table" then records[index].credentialsOmitted = true end
			end
		end
		if type(snapshot.identity) == "table" then snapshot.identity.extraHeaders = {} end
		return snapshot
	end

	function M.hasProviderCredentials(snapshot)
		local records = type(snapshot.providers) == "table" and snapshot.providers.list
		for _, record in pairs(type(records) == "table" and records or {}) do
			if type(record) == "table" then
				if util.trim(record.apiKey) ~= "" then return true end
				for _, field in ipairs({ "headers", "query", "params" }) do
					if type(record[field]) == "table" and next(record[field]) ~= nil then return true end
				end
				if M.cleanUrl(record.baseUrl) ~= record.baseUrl or M.cleanUrl(record.wsUrl) ~= record.wsUrl then return true end
			end
		end
		local headers = type(snapshot.identity) == "table" and snapshot.identity.extraHeaders
		return type(headers) == "table" and next(headers) ~= nil
	end

	local function validPayload(value, kind, fields)
		if type(value) ~= "table" or value.kind ~= kind or type(value.fields) ~= "table" then return false end
		for name in pairs(value) do if name ~= "kind" and name ~= "fields" then return false end end
		local allowed = {}
		for _, field in ipairs(fields) do allowed[field] = true end
		for name, item in pairs(value.fields) do
			if not allowed[name] or type(item) ~= FIELD_TYPES[name] then return false end
		end
		if kind == "provider" then
			local metadata = value.fields
			if metadata.keyMode ~= nil and metadata.keyMode ~= "rotate" and metadata.keyMode ~= "single" then return false end
			if metadata.selectedKey ~= nil and (metadata.selectedKey < 1 or metadata.selectedKey % 1 ~= 0) then return false end
			-- Partial legacy records can omit the key entirely. When a key is
			-- present, its pool determines all metadata array/index bounds.
			if metadata.apiKey ~= nil and not env.require("runtime/provider_keys").validate(metadata) then return false end
		end
		return true
	end
	local function readEnvelope(holder, kind, fields)
		if holder.storedCredentials == nil then return true end
		local value = codec.decode(holder.storedCredentials)
		if not validPayload(value, kind, fields) then
			holder.credentialsOmitted, holder.credentialStorageError = true, codec.error
			return false
		end
		for _, field in ipairs(fields) do holder[field] = util.deepCopy(value.fields[field]) end
		holder.storedCredentials, holder.credentialStorageError = nil, nil
		return true
	end

	function M.withoutVault(snapshot)
		local out = util.deepCopy(snapshot)
		out.credentialVault, out.credentialVaultLocked = nil, nil
		for _, record in pairs(records(out)) do
			if type(record) == "table" then record.credentialVaultLocked = nil end
		end
		if type(out.identity) == "table" then out.identity.credentialVaultLocked = nil end
		return out
	end
	function M.lockedVault(snapshot, persisted)
		local out = projectProviders(M.withoutVault(snapshot))
		out.credentialVault = util.deepCopy(snapshot.credentialVault)
		out.credentialVaultLocked = not persisted or nil
		out.security = type(out.security) == "table" and out.security or {}
		out.security.rememberCredentials = true
		local original = {}
		for _, record in pairs(records(snapshot)) do if type(record) == "table" and record.id then original[record.id] = record end end
		for _, record in pairs(records(out)) do
			if type(record) == "table" then
				record.storedCredentials = nil
				record.credentialVaultLocked = not persisted or nil
				-- This old public reference must survive until its matching vault
				-- payload has authenticated; it never reconstructs a credential.
				local source = original[record.id]
				record.communityCredential = source and source.communityCredential == true or nil
			end
		end
		if type(out.identity) == "table" then
			out.identity.storedCredentials = nil
			out.identity.credentialVaultLocked = not persisted or nil
		end
		return out
	end
	local function protectedFields(holder, fields)
		local values = {}
		for _, field in ipairs(fields) do values[field] = util.deepCopy(holder[field]) end
		return values
	end
	function M.sealVault(snapshot, envelope, key)
		local source = M.withoutVault(snapshot)
		retirement.apply(source)
		local payload = { version = 1, providers = {}, identity = {} }
		local ids = {}
		for _, record in ipairs(records(source)) do
			if type(record) ~= "table" or type(record.id) ~= "string" or record.id == "" or ids[record.id]
				or record.storedCredentials ~= nil or record.credentialStorageError ~= nil then
				return nil, "Replace unreadable credentials before enabling the vault."
			end
			ids[record.id] = true
			payload.providers[#payload.providers + 1] = { id = record.id, fields = protectedFields(record, PROVIDER_FIELDS) }
		end
		if type(source.identity) == "table" then
			if source.identity.storedCredentials ~= nil or source.identity.credentialStorageError ~= nil then
				return nil, "Replace unreadable identity headers before enabling the vault."
			end
			payload.identity = protectedFields(source.identity, { "extraHeaders", "credentialsOmitted" })
		end
		local encrypted, why = vault.seal(envelope, key, payload)
		if not encrypted then return nil, why end
		local out = projectProviders(source)
		out.credentialVault, out.credentialVaultLocked = encrypted, nil
		out.security = type(out.security) == "table" and out.security or {}
		out.security.rememberCredentials = true
		return out
	end
	function M.openVault(snapshot, key)
		local payload, why = vault.open(snapshot.credentialVault, key)
		if not payload then return nil, why end
		if payload.version ~= 1 or type(payload.providers) ~= "table" or type(payload.identity) ~= "table" then return nil, vault.error end
		for name in pairs(payload) do if name ~= "version" and name ~= "providers" and name ~= "identity" then return nil, vault.error end end
		local byId, count = {}, 0
		for index, entry in pairs(payload.providers) do
			if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #payload.providers
				or type(entry) ~= "table" or type(entry.id) ~= "string" or entry.id == "" or byId[entry.id]
				or not validPayload({ kind = "provider", fields = entry.fields }, "provider", LEGACY_PROVIDER_FIELDS) then return nil, vault.error end
			for name in pairs(entry) do if name ~= "id" and name ~= "fields" then return nil, vault.error end end
			byId[entry.id], count = entry.fields, count + 1
		end
		if count ~= #payload.providers or not validPayload({ kind = "identity", fields = payload.identity }, "identity", { "extraHeaders", "credentialsOmitted" }) then return nil, vault.error end
		local out, seen = M.withoutVault(snapshot), {}
		for _, record in ipairs(records(out)) do
			if type(record) ~= "table" or not byId[record.id] or seen[record.id] then return nil, vault.error end
			seen[record.id] = true
			for _, field in ipairs(LEGACY_PROVIDER_FIELDS) do record[field] = util.deepCopy(byId[record.id][field]) end
			record.storedCredentials, record.credentialStorageError = nil, nil
		end
		if #records(out) ~= count then return nil, vault.error end
		out.identity = type(out.identity) == "table" and out.identity or {}
		for _, field in ipairs({ "extraHeaders", "credentialsOmitted" }) do out.identity[field] = util.deepCopy(payload.identity[field]) end
		out.identity.storedCredentials, out.identity.credentialStorageError = nil, nil
		out.credentialVault, out.credentialVaultLocked = util.deepCopy(snapshot.credentialVault), false
		out.security = type(out.security) == "table" and out.security or {}
		out.security.rememberCredentials = true
		return out
	end
	-- Apply only credential fields, retaining provider and identity table identity.
	-- Accepted request snapshots remain separate and are not retroactively erased.
	function M.applyVault(target, source)
		local byId = {}
		for _, record in ipairs(records(source)) do byId[record.id] = record end
		local removed = {}
		for _, record in ipairs(records(target)) do
			local other = byId[record.id]
			if other then
				for _, field in ipairs(LEGACY_PROVIDER_FIELDS) do record[field] = util.deepCopy(other[field]) end
				record.communityCredential = other.communityCredential
				record.storedCredentials, record.credentialStorageError = other.storedCredentials, other.credentialStorageError
				record.credentialVaultLocked = other.credentialVaultLocked
				record.keyRotation = nil
			else removed[record.id] = true
			end
		end
		-- Authenticated migrations can remove IDs from the protected payload.
		-- Reconcile those removals while retaining each surviving live table.
		if next(removed) then
			local list = records(target)
			for index = #list, 1, -1 do if removed[list[index].id] then table.remove(list, index) end end
			if removed[target.providers.active] then target.providers.active = source.providers.active or "" end
			for _, field in ipairs({ "modelFavorites", "recentModels" }) do
				local buckets = type(target.ui) == "table" and target.ui[field]
				if type(buckets) == "table" then for id in pairs(removed) do buckets[id] = nil end end
			end
		end
		target.identity = type(target.identity) == "table" and target.identity or {}
		for _, field in ipairs({ "extraHeaders", "credentialsOmitted", "storedCredentials", "credentialStorageError", "credentialVaultLocked" }) do
			target.identity[field] = util.deepCopy((source.identity or {})[field])
		end
		target.credentialVault, target.credentialVaultLocked = util.deepCopy(source.credentialVault), source.credentialVaultLocked
	end

	-- Decode only recognized fields. Failed envelopes remain intact and unusable;
	-- ordinary saves cannot replace an unreadable credential with an empty value.
	function M.restore(snapshot)
		local out = util.deepCopy(snapshot)
		if type(out) ~= "table" then return out end
		if out.credentialVault ~= nil then return M.lockedVault(out) end
		for _, record in pairs(records(out)) do
			if type(record) == "table" then readEnvelope(record, "provider", LEGACY_PROVIDER_FIELDS) end
		end
		if type(out.identity) == "table" then readEnvelope(out.identity, "identity", { "extraHeaders", "credentialsOmitted" }) end
		retirement.apply(out)
		return out
	end

	local function storeEnvelope(holder, kind, fields)
		local values = {}
		for _, field in ipairs(fields) do values[field] = util.deepCopy(holder[field]) end
		return codec.encode({ kind = kind, fields = values })
	end

	local function projection(snapshot, remember)
		local out = M.restore(snapshot)
		if not remember then return projectProviders(out) end
		for index, record in pairs(records(out)) do
			if type(record) == "table" then
				local envelope, why = record.storedCredentials
				if envelope == nil then
					envelope, why = storeEnvelope(record, "provider", PROVIDER_FIELDS)
					if not envelope then return nil, why end
				end
				local visible = provider(record)
				visible.storedCredentials = envelope
				records(out)[index] = visible
			end
		end
		if type(out.identity) == "table" then
			local envelope, why = out.identity.storedCredentials
			if envelope == nil then
				envelope, why = storeEnvelope(out.identity, "identity", { "extraHeaders", "credentialsOmitted" })
				if not envelope then return nil, why end
			end
			out.identity.extraHeaders, out.identity.storedCredentials = {}, envelope
		end
		return out
	end

	-- Provider credentials are remembered as reversible bytes unless explicitly
	-- disabled. Bridge and companion pairing storage remain independent.
	function M.persistent(snapshot)
		if snapshot.credentialVault ~= nil then
			if not vault.validate(snapshot.credentialVault) then return nil, vault.error end
			local key = vault.key(snapshot.credentialVault)
			if snapshot.credentialVaultLocked == false then
				if not key then return nil, "Unlock the credential vault before saving changed credentials." end
				return M.sealVault(snapshot, snapshot.credentialVault, key)
			end
			return M.lockedVault(snapshot, true)
		end
		local remember = not (type(snapshot.security) == "table" and snapshot.security.rememberCredentials == false)
		return projection(snapshot, remember)
	end
	function M.privateCopy(snapshot)
		if snapshot.credentialVault ~= nil then return M.persistent(snapshot) end
		return projection(snapshot, true)
	end

	-- This is a settings copy, not a promise that user-authored text is public.
	-- In particular, memory, instructions and labels still need personal review.
	function M.sanitise(snapshot)
		local out = M.withoutVault(snapshot)
		if snapshot.credentialVault ~= nil then
			for _, record in pairs(records(out)) do
				if type(record) == "table" then record.credentialsOmitted = true end
			end
		end
		retirement.apply(out)
		out = projectProviders(out)
		out = scrub(out, "")
		for _, record in pairs(type(out.providers) == "table" and type(out.providers.list) == "table" and out.providers.list or {}) do
			if type(record) == "table" then record.apiKey, record.communityKeyState, record.storedCredentials = "", nil, nil end
		end
		if type(out.identity) == "table" then out.identity.storedCredentials = nil end
		out.security = type(out.security) == "table" and out.security or {}
		out.security.rememberCredentials = false
		if type(out.bridge) == "table" then out.bridge.enabled, out.bridge.port, out.bridge.token = nil, nil, nil end
		if type(out.relay) == "table" then out.relay.token = "" end
		return out
	end
	return M
end
