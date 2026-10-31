-- User-facing input measurements count bytes separately from visible characters.
return function(env)
	local M = {}
	function M.measure(value)
		local text = tostring(value or "")
		local words, lines, characters = 0, 1, 0
		for _ in text:gmatch("%S+") do words = words + 1 end
		for _ in text:gmatch("\n") do lines = lines + 1 end
		for _ in text:gmatch("[^\128-\191]") do characters = characters + 1 end
		return { bytes = #text, words = words, lines = lines, characters = characters }
	end
	function M.label(value)
		local measured = M.measure(value)
		return tostring(measured.words) .. (measured.words == 1 and " word" or " words") .. " / "
			.. tostring(measured.bytes) .. " bytes", measured
	end
	return M
end
