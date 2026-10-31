-- HTTP header names are case-insensitive. Later maps deliberately win.
return function()
	local M = {}
	function M.validate(headers)
		if headers == nil then return true end
		if type(headers) ~= "table" then return false, "Headers must be a map of names and values." end
		local seen = {}
		for key, value in pairs(headers) do
			if type(key) ~= "string" or key == "" or key:find("[^%w!#$%%&'*+%.%^_`|~%-]") then
				return false, "Header names must use HTTP token characters without spaces."
			end
			local kind = type(value)
			if kind ~= "string" and kind ~= "number" and kind ~= "boolean" then return false, "Header values must be text, numbers or booleans." end
			if tostring(value):find("[%z\1-\8\10-\31\127]") then return false, "Header values must use one line without control characters." end
			local name = key:lower()
			if seen[name] then return false, "Use each header name once; HTTP header names ignore case." end
			seen[name] = true
		end
		return true
	end
	function M.merge(...)
		local out, names = {}, {}
		for i = 1, select("#", ...) do
			for key, value in pairs(select(i, ...) or {}) do
				if type(key) == "string" and value ~= nil then
					local name = key:lower()
					if names[name] then out[names[name]] = nil end
					names[name], out[key] = key, tostring(value)
				end
			end
		end
		return out
	end
	function M.get(headers, wanted)
		if type(wanted) ~= "string" then return nil end
		wanted = wanted:lower()
		for key, value in pairs(type(headers) == "table" and headers or {}) do if type(key) == "string" and key:lower() == wanted then return value end end
	end
	return M
end
