-- Obsidian uses authenticated loopback bridge requests, never executor files.
return function(env)
	local util = env.require("runtime/util")
	local config = env.require("runtime/config")
	local http = env.require("net/http")
	local connection = env.require("net/bridge_connection")
	local bridge = env.require("net/bridge")
	local M = {}
	function M.request(input, options)
		options = options or {}
		local access = config.accessProblem()
		if access then return nil, access end
		if not bridge.status().online then return nil, "Connect UAI Bridge in Cowork before using Obsidian vaults. Vaults are stored on the bridge computer." end
		local settings = connection.get()
		local token, port = settings.token, settings.port
		local writing = options.config and input ~= nil or input and (input.action == "create" or input.action == "update" or input.action == "append")
		local function changed()
			local current = connection.get()
			return current.enabled ~= settings.enabled or current.token ~= token or current.port ~= port or current.instance ~= settings.instance
		end
		local function aborted()
			return changed() or config.accessProblem() ~= nil or options.aborted and options.aborted()
		end
		if not settings.enabled or aborted() then return nil, "The vault request was cancelled or the bridge connection changed." end
		local response, err = http.request({ url = "http://127.0.0.1:" .. tostring(port) .. (options.config and "/api/vaults/config" or "/api/vaults"),
			method = input and "POST" or "GET", body = input and util.encode(input) or nil,
			headers = { Authorization = "Bearer " .. token, ["Content-Type"] = "application/json" },
			identity = "none", tag = "obsidian", silent = true, timeout = 20, requiresAccess = true, waitForSlot = true,
			aborted = aborted })
		if aborted() or not bridge.status().online then return nil, "The bridge connection changed or the request was cancelled. Check this vault before repeating an edit." end
		local value = response and type(response.body) == "string" and #response.body <= 2097152 and util.decode(response.body)
		if not response and writing then return nil, "The save could not be confirmed. Read the note or refresh vault connections before repeating this action." end
		if not response or not response.ok then return nil, type(value) == "table" and value.error or err or "The bridge could not read this vault. Update UAI Bridge if vault support is unavailable." end
		if type(value) ~= "table" or value.error then return nil, type(value) == "table" and value.error or "The bridge returned an invalid vault response." end
		return value
	end
	local function listing(value, why)
		if not value then return nil, why end
		if type(value.vaults) ~= "table" or #value.vaults > 16 then return nil, "The bridge returned an invalid vault list." end
		for _, entry in ipairs(value.vaults) do
			if type(entry) ~= "table" or type(entry.id) ~= "string" or not entry.id:match("^[%w_-]+$") or #entry.id > 80
				or type(entry.name) ~= "string" or #entry.name > 320 or type(entry.readOnly) ~= "boolean" or type(entry.available) ~= "boolean" then return nil, "The bridge returned an invalid vault entry." end
		end
		return value
	end
	function M.list(options) return listing(M.request(nil, options)) end
	function M.configure(input, options)
		options = util.copy(options or {}); options.config = true
		return listing(M.request(input, options))
	end
	function M.readNote(vault, path, options)
		local clean, why = env.require("runtime/obsidian").path(path)
		if not clean then return nil, why end
		local reader = env.require("runtime/obsidian_document").reader(vault, clean)
		for _ = 1, 90 do
			local page, problem = M.request({ action = "read", vault = vault, path = clean, offset = reader.offset,
				limit = 12000, revision = reader.revision, metadata = reader.offset == 1 }, options)
			if not page then return nil, problem end
			local document, invalid = reader.accept(page)
			if invalid then return nil, invalid end
			if document then return document end
		end
		return nil, "This note exceeded the read page limit."
	end
	function M.saveNote(document, text, options)
		local notes = env.require("runtime/obsidian")
		local contract = env.require("runtime/obsidian_document")
		local path, why = notes.path(document.path)
		if not path then return nil, why end
		local content = contract.savedText(document, text)
		if #content > notes.MAX_BYTES or not util.validUtf8(content) then return nil, "Notes must contain valid UTF-8 and fit within 1 MiB." end
		if document.revision ~= nil and not contract.revision(document.revision) then return nil, "Read the complete current note before editing it." end
		local result, problem = M.request({ action = document.revision and "update" or "create", vault = document.vault,
			path = path, revision = document.revision, content = content }, options)
		if not result then return nil, problem end
		if result.path ~= path or not contract.revision(result.revision) or result.bytes ~= #content then
			return nil, "The save could not be verified. Your draft is kept; read the note before saving again."
		end
		return { vault = document.vault, path = path, content = content, revision = result.revision, bytes = result.bytes,
			modifiedAt = result.modifiedAt }
	end
	return M
end
