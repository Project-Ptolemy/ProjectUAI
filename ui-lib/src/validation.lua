return function(env)
	local C = env.require("core")
	local M = {}
	function M.input(options)
		assert(options.Validate == nil or type(options.Validate) == "function", "Input Validate must be a function")
		assert(options.Pattern == nil or type(options.Pattern) == "string", "Input Pattern must be a string")
		assert(options.Required == nil or type(options.Required) == "boolean", "Input Required must be a boolean")
		for _, name in ipairs({ "RequiredMessage", "ValidationMessage" }) do
			assert(options[name] == nil or type(options[name]) == "string", "Input " .. name .. " must be a string")
		end
		if options.Pattern then assert(pcall(string.match, "", options.Pattern), "Input Pattern is invalid") end
		return function(value)
			if options.Required and (value == nil or (type(value) == "string" and not value:find("%S"))) then
				return false, C.truncate(options.RequiredMessage or "This field is required.", 512)
			end
			if options.Pattern and not tostring(value):match(options.Pattern) then
				return false, C.truncate(options.ValidationMessage or "Enter a value in the expected format.", 512)
			end
			if options.Validate then
				local ok, valid, message = pcall(options.Validate, C.copy(value))
				if not ok then return false, "Could not validate this field." end
				if valid ~= true then return false, C.truncate(type(message) == "string" and message or options.ValidationMessage or "Check this value.", 512) end
			end
			return true
		end
	end
	return M
end
