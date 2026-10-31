-- A retained digest catches same-size edits between attaching and sending a file.
return function(env)
	local sha = env.require("runtime/credential_sha256")
	local clock = env.require("runtime/clock")
	local M = {}
	function M.valid(value) return type(value) == "string" and #value == 64 and value:match("^[a-f0-9]+$") ~= nil end
	function M.digest(content, aborted)
		if aborted and aborted() then return nil, "Attachment preparation was cancelled" end
		if sha.available == false then return nil end
		local cancelled = false
		local yieldable = coroutine.running() and (not coroutine.isyieldable or coroutine.isyieldable())
		local slice = os.clock()
		local function progress(completed, total)
			cancelled = cancelled or aborted and aborted() or false
			if cancelled then return false end
			if yieldable and completed > 0 and completed < total and os.clock() - slice >= 0.02 then
				clock.wait(); slice = os.clock()
			end
			cancelled = cancelled or aborted and aborted() or false
			return not cancelled
		end
		local ok, raw = pcall(sha.digest, content, progress)
		if cancelled then return nil, "Attachment preparation was cancelled" end
		if not ok or type(raw) ~= "string" or #raw ~= 32 then return nil, "Could not fingerprint the attachment" end
		return (raw:gsub(".", function(char) return string.format("%02x", char:byte()) end))
	end
	function M.matches(file, content, aborted)
		if type(content) ~= "string" or #content ~= file.bytes then return false end
		if file.sha256 == nil then return true end
		return M.valid(file.sha256) and M.digest(content, aborted) == file.sha256
	end
	return M
end
