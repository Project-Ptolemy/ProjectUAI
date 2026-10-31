-- Every project writer respects unsaved documents bound to the same files.
return function(env)
	local M = {}
	function M.check(plan)
		local files, store = env.require("runtime/code_files"), env.require("runtime/code_store")
		for _, item in ipairs(plan.items) do
			for id, binding in pairs(files.bindings) do
				if binding.path:lower() == ("files/" .. item.path):lower() then
					local doc = store.resolve(id)
					if doc and doc.source ~= binding.base then
						return false, "Unsaved Code draft exists for files/" .. item.path .. "; save or edit that document first"
					end
				end
			end
		end
		return true
	end
	return M
end
