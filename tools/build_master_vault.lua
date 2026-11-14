-- Deterministic, offline starter collection. Client bundle builds call this after input review.
return function(checkOnly)
	package.path = "test/?.lua;" .. package.path
	local json = require("mock/json")
	local function read(path)
		local file = assert(io.open(path, "rb"), "cannot read " .. path)
		local source = file:read("*a"); file:close()
		return source:gsub("\r\n", "\n")
	end
	local function validUtf8(value)
		local at = 1
		while at <= #value do
			local first = value:byte(at)
			local count, minimum, maximum = 1, 128, 191
			if first < 128 then count = 1
			elseif first >= 194 and first <= 223 then count = 2
			elseif first >= 224 and first <= 239 then
				count = 3
				if first == 224 then minimum = 160 elseif first == 237 then maximum = 159 end
			elseif first >= 240 and first <= 244 then
				count = 4
				if first == 240 then minimum = 144 elseif first == 244 then maximum = 143 end
			else return false end
			if at + count - 1 > #value then return false end
			for index = 1, count - 1 do
				local byte = value:byte(at + index)
				if byte < (index == 1 and minimum or 128) or byte > (index == 1 and maximum or 191) then return false end
			end
			at = at + count
		end
		return true
	end
	local util = { validUtf8 = validUtf8, trim = function(value) return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")) end,
		encode = json.encode, decode = function(text) local ok, value = pcall(json.decode, text); if ok then return value end end }
	function util.isArray(value)
		local count = 0
		for key in pairs(value) do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then return false end
			count = count + 1
		end
		return count == #value
	end
	function util.ellipsis(value, maximum)
		if #value <= maximum then return value end
		local last = maximum - 3
		while last > 0 and value:byte(last + 1) >= 128 and value:byte(last + 1) < 192 do last = last - 1 end
		return value:sub(1, last) .. "..."
	end
	local codecFactory = assert(loadfile("src/runtime/vault_document.lua"))()
	local codec = codecFactory({ require = function(id) assert(id == "runtime/util", "unexpected vault codec dependency"); return util end })
	local index = assert(json.decode(read("vault/catalog.json")))
	assert(index.version == 1 and type(index.entries) == "table" and util.isArray(index.entries)
		and #index.entries > 0 and #index.entries <= 32, "invalid Master Vault starter catalog")
	local function longString(source)
		local equals = "="
		while source:find("]" .. equals .. "]", 1, true) do equals = equals .. "=" end
		return "[" .. equals .. "[\n" .. source .. "]" .. equals .. "]"
	end
	local lines = { "-- Generated from vault/catalog.json and its Markdown by tools/build_master_vault.lua; edit the sources.",
		"return function(env)", "\treturn {", "\t\tversion = 1,", '\t\trelease = "4.0.0",', "\t\tentries = {" }
	local seen = {}
	for _, name in ipairs(index.entries) do
		assert(type(name) == "string" and name:match("^[a-z0-9_-]+%.md$") and not seen[name], "invalid or repeated starter filename")
		seen[name] = true
		local markdown = read("vault/" .. name)
		local document, why = codec.parse(markdown)
		assert(document, name .. ": " .. tostring(why))
		assert(document.scope == "global" and #document.sources > 0, name .. " needs global scope and source references")
		local id = "starter:" .. name:sub(1, -4)
		lines[#lines + 1] = "\t\t\t{ id = " .. string.format("%q", id) .. ", markdown = " .. longString(markdown) .. " },"
	end
	lines[#lines + 1] = "\t\t},"; lines[#lines + 1] = "\t}"; lines[#lines + 1] = "end"; lines[#lines + 1] = ""
	local generated, output = table.concat(lines, "\n"), "src/runtime/master_vault_seed.lua"
	if checkOnly then
		assert(read(output) == generated, output .. " is stale; run luajit tools/bundle.lua --native")
	else
		local file = assert(io.open(output, "wb"), "cannot write " .. output)
		assert(file:write(generated)); file:close()
	end
	return #index.entries, #generated
end
