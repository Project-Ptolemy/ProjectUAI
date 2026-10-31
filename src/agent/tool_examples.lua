-- Detached, bounded examples for on-demand help. Examples never dispatch a tool.
return function(env)
	local util = env.require("runtime/util")
	local schema = env.require("agent/schema")
	local M = {}
	function M.read(tool)
		local result, omitted = {}, 0
		for index, item in ipairs(type(tool.examples) == "table" and tool.examples or {}) do
			local valid = index <= 3 and type(item) == "table" and type(item.title) == "string" and #item.title > 0 and #item.title <= 120
				and type(item.arguments) == "table" and (item.note == nil or type(item.note) == "string" and #item.note <= 400)
			local args, errors
			if valid then
				local body = util.encode(item.arguments)
				valid = type(body) == "string" and #body <= 6000
				if valid then args, errors = schema.validate(tool.parameters, util.deepCopy(item.arguments)); valid = #errors == 0 end
			end
			if valid then result[#result + 1] = { title = item.title, arguments = args, note = item.note }
			else omitted = omitted + 1 end
		end
		return result, omitted
	end
	function M.text(tool)
		local lines = {}
		for _, example in ipairs(M.read(tool)) do
			lines[#lines + 1] = example.title .. "\n" .. util.encode(example.arguments) .. (example.note and ("\n" .. example.note) or "")
		end
		return table.concat(lines, "\n\n")
	end
	return M
end
