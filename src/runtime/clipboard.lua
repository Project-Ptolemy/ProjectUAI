-- Executor clipboard writes have no readback API. A false result or exception is
-- failure; nil is the normal success result in several supported executors.
return function(env)
	local caps = env.require("runtime/caps")
	local M = {}
	function M.write(text)
		if type(text) ~= "string" then return false, "Clipboard text must be a string." end
		if not caps.clipboard or type(caps.fn.clipboard) ~= "function" then
			return false, "Clipboard is unavailable in this executor."
		end
		local ok, result = pcall(caps.fn.clipboard, text)
		-- Native exceptions can echo the copied payload; do not display or log them.
		if not ok or result == false then return false, "Could not write to the clipboard." end
		return true
	end
	return M
end
