-- Bounded literal search: words, quoted phrases and -excluded terms. Never patterns.
return function(env)
	local util = env.require("runtime/util")
	local M = { hint = 'Use words, "exact phrases", or -exclude.' }
	local function fold(value, limit)
		return util.sanitise(tostring(value or ""):sub(1, limit)):lower():gsub("[_%-]+", " "):gsub("%s+", " ")
	end
	function M.terms(query)
		local text = util.sanitise(tostring(query or ""):sub(1, 256))
		local terms, seen, at = {}, {}, 1
		while at <= #text and #terms < 16 do
			local first = text:find("%S", at); if not first then break end
			local excluded = text:sub(first, first) == "-"; if excluded then first = first + 1 end
			local last, after
			if text:sub(first, first) == '"' then
				first = first + 1; last = text:find('"', first, true)
				after = last and last + 1 or #text + 1; last = last and last - 1 or #text
			else last = text:find("%s", first); after = last or #text + 1; last = (last or #text + 1) - 1 end
			local value = fold(text:sub(first, last), 256):gsub("^%s+", ""):gsub("%s+$", "")
			local key = (excluded and "-" or "+") .. value
			if value ~= "" and not seen[key] then terms[#terms + 1] = { value = value, excluded = excluded }; seen[key] = true end
			at = math.max(at + 1, after)
		end
		return terms
	end
	function M.compile(query)
		local terms, positive = M.terms(query), {}
		for _, term in ipairs(terms) do if not term.excluded then positive[#positive + 1] = term.value end end
		local phrase = table.concat(positive, " ")
		return function(...)
			if #terms == 0 then return 0 end
			local fields = {}
			for index = 1, math.min(select("#", ...), 16) do fields[index] = fold(select(index, ...), 16384) end
			local score = 0
			for _, term in ipairs(terms) do
				local found = false
				for index, field in ipairs(fields) do
					if field:find(term.value, 1, true) then
						found = true; if not term.excluded then score = score + (index == 1 and 20 or 1) end; break
					end
				end
				if term.excluded and found or not term.excluded and not found then return nil end
			end
			if phrase ~= "" and fields[1] == phrase then score = score + 1000
			elseif phrase ~= "" and fields[1] and fields[1]:sub(1, #phrase) == phrase then score = score + 100 end
			return score
		end
	end
	return M
end
