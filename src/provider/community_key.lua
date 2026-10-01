-- Public, opt-in community credentials. Importing this module never changes a
-- provider or sends traffic; the setup editor applies a key only after a click.
return function(env)
	local url = env.require("net/url")
	local M = {}
	local key = "sk-ysUaToxuHpUyGBsqxcbBne8x7u4Qr7L6wAclRAG2VuhM1luY"
	function M.eligible(record)
		if type(record) ~= "table" or record.preset ~= "hcnsec" then return false end
		local base = url.normaliseBase(record.baseUrl)
		local parsed = url.parse(base)
		return parsed ~= nil and parsed.scheme == "https" and parsed.authority:lower() == "api.hcnsec.cn"
			and parsed.path == "/v1" and (not parsed.query or parsed.query == "")
	end
	function M.apply(record)
		if not M.eligible(record) then return nil, "Select the official HCNSEC endpoint to use its community key." end
		record.apiKey = key
		record.keyRotation = nil
		return true
	end
	return M
end
