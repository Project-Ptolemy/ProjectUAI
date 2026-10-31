-- One model-ID boundary for manual entry, selection and remote catalogs.
return function(env)
	local util = env.require("runtime/util")
	local M = { maxBytes = 160 }
	function M.parse(value)
		if type(value) ~= "string" then return nil, "enter a model id as text" end
		local clean = util.trim(value)
		if clean == "" then return nil, "type a model id" end
		if #clean > M.maxBytes or not util.validUtf8(clean) or clean:find("[%z\1-\31\127]")
			or clean:find("\194[\128-\159]") or clean:find("\226\128\168", 1, true) or clean:find("\226\128\169", 1, true) then
			return nil, "enter one valid UTF-8 model id of at most 160 bytes, without control characters"
		end
		return clean
	end
	return M
end
