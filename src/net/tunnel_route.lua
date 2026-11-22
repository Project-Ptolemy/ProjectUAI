-- Virtual inference routes belong to the local desktop bridge, never DNS.
return function(env)
	local urls = env.require("net/url")
	local M = {}
	local HOST, BASE = "uai-tunnel.invalid", "/cline/v1"

	function M.reserved(raw)
		local authority = tostring(raw or ""):lower():gsub("^%s+", ""):match("^[%a][%w+%.%-]*://([^/%?#]+)") or ""
		authority = authority:match("([^@]+)$") or authority
		return authority:gsub(":.*$", ""):gsub("%.$", "") == HOST
	end

	local function clineUrl(raw)
		if tostring(raw):find("%s") then return nil end
		local parsed = urls.parse(raw)
		if not parsed or parsed.scheme ~= "https" or parsed.host ~= HOST then return nil end
		local authority = parsed.authority:lower()
		if authority ~= HOST and authority ~= HOST .. ":443" then return nil end
		if tostring(raw):find("[?#]") then return nil end
		return parsed
	end

	function M.isClineBase(raw)
		local parsed = clineUrl(raw)
		if not parsed then return false end
		local path = parsed.path:gsub("/+$", "")
		return path == BASE or path == BASE .. "/chat/completions"
	end

	function M.hasCredentials(headers)
		for name in pairs(type(headers) == "table" and headers or {}) do
			local lower = tostring(name):lower()
			if lower:find("auth", 1, true) or lower:find("api[-_]?key") or lower:find("token", 1, true)
				or lower:find("secret", 1, true) or lower:find("cookie", 1, true) or lower:find("credential", 1, true)
				or lower:find("organization", 1, true) or lower:find("%f[%a]org%f[%A]") or lower:find("[-_]org[-_]?id$") then return true end
		end
		return false
	end

	function M.problem(raw, method, headers)
		local parsed = clineUrl(raw)
		if not parsed or parsed.path ~= BASE .. "/chat/completions" or tostring(method or "GET"):upper() ~= "POST" then
			return "Cline requires the desktop bridge's Chat completions route; this virtual address cannot be contacted directly."
		end
		if M.hasCredentials(headers) then return "Cline uses its desktop sign-in. Remove provider keys and credential headers from this route." end
	end

	return M
end
