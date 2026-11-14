-- Portable Master Vault Markdown. Frontmatter is a small schema, not a YAML engine.
return function(env)
	local util = env.require("runtime/util")
	local M = { MAX_CONTENT = 64000, MAX_FILE = 80000, MAX_HEADER = 12000,
		kinds = { "recipe", "bugfix", "remote", "instance", "project", "reference" },
		scopes = { "global", "game", "project" }, statuses = { "draft", "verified", "outdated" } }
	local kinds, scopes, statuses = {}, {}, {}
	for _, value in ipairs(M.kinds) do kinds[value] = true end
	for _, value in ipairs(M.scopes) do scopes[value] = true end
	for _, value in ipairs(M.statuses) do statuses[value] = true end
	local function validText(value, maximum, required, multiline)
		if type(value) ~= "string" or #value > maximum or not util.validUtf8(value) then return false end
		if value:find(multiline and "[%z\1-\8\11\12\14-\31\127]" or "[%z\1-\31\127]") then return false end
		return not required or util.trim(value) ~= ""
	end
	local function finite(value)
		return type(value) == "number" and value == value and value >= 0 and value < 9007199254740991
	end
	function M.normalize(value)
		if type(value) ~= "table" then return nil, "A vault document must be an object" end
		if not validText(value.title, 160, true) then return nil, "Title must contain 1–160 UTF-8 bytes on one line" end
		local description = value.description or ""
		if not validText(description, 500, false) then return nil, "Description must be one line of at most 500 UTF-8 bytes" end
		local kind, scope, status = value.kind or "reference", value.scope or "global", value.status or "draft"
		if not kinds[kind] then return nil, "Unknown vault document kind" end
		if not scopes[scope] then return nil, "Unknown vault document scope" end
		if not statuses[status] then return nil, "Unknown vault verification status" end
		if not validText(value.content, M.MAX_CONTENT, true, true) then
			return nil, "Content must contain text, valid UTF-8 without NUL, at most 64000 bytes"
		end
		local out = { title = util.trim(value.title), description = util.trim(description), kind = kind,
			scope = scope, status = status, content = value.content, tags = {}, sources = {}, updatedAt = value.updatedAt or 0 }
		if not finite(out.updatedAt) or out.updatedAt ~= math.floor(out.updatedAt) then return nil, "updatedAt must be a finite nonnegative integer timestamp" end
		if scope == "game" then
			if not finite(value.placeId) or value.placeId < 1 or value.placeId ~= math.floor(value.placeId) then
				return nil, "A game note needs a positive integer PlaceId"
			end
			out.placeId = value.placeId
		elseif scope == "project" then
			if not validText(value.project, 160, true) then return nil, "A project note needs a project name of 1–160 UTF-8 bytes" end
			out.project = util.trim(value.project)
		end
		local tags = value.tags or {}
		if type(tags) ~= "table" or not util.isArray(tags) or #tags > 12 then return nil, "Tags must be an array of at most 12 strings" end
		local seen = {}
		for _, tag in ipairs(tags) do
			if not validText(tag, 40, true) then return nil, "Each tag must contain 1–40 UTF-8 bytes on one line" end
			local clean = util.trim(tag)
			if seen[clean:lower()] then return nil, "Tags must not repeat" end
			seen[clean:lower()] = true; out.tags[#out.tags + 1] = clean
		end
		local sources = value.sources or {}
		if type(sources) ~= "table" or not util.isArray(sources) or #sources > 8 then return nil, "Sources must be an array of at most eight references" end
		for _, source in ipairs(sources) do
			if type(source) ~= "table" or not validText(source.label, 160, true) then return nil, "Each source needs a label of 1–160 UTF-8 bytes" end
			local row = { label = util.trim(source.label) }
			if source.url ~= nil and source.url ~= "" then
				if not validText(source.url, 500, true) then return nil, "Source references must be one line of at most 500 UTF-8 bytes" end
				row.url = util.trim(source.url)
			end
			out.sources[#out.sources + 1] = row
		end
		if value.verification ~= nil and value.verification ~= "" then
			if not validText(value.verification, 4000, true, true) then return nil, "Verification evidence must contain 1–4000 UTF-8 bytes" end
			out.verification = value.verification
		end
		if status == "verified" and not out.verification then return nil, "Verified notes need attributed verification evidence" end
		return out
	end
	local fields = { title = "title", description = "description", kind = "kind", scope = "scope", place_id = "placeId",
		project = "project", tags = "tags", sources = "sources", status = "status", verification = "verification", updated_at = "updatedAt" }
	local function scalar(raw, name)
		if name == "tags" or name == "sources" then
			if raw:sub(1, 1) ~= "[" then return nil, name .. " must use a JSON array" end
			local value = util.decode(raw)
			if type(value) ~= "table" or not util.isArray(value) then return nil, name .. " must use a JSON array" end
			return value
		end
		if name == "placeId" or name == "updatedAt" then
			local value = tonumber(raw)
			if value == nil then return nil, name .. " must be a number" end
			return value
		end
		if raw:sub(1, 1) == '"' then
			local value = util.decode(raw)
			if type(value) ~= "string" then return nil, "Invalid quoted frontmatter string" end
			return value
		end
		return raw
	end
	function M.parse(markdown)
		if not validText(markdown, M.MAX_FILE, true, true) then return nil, "Markdown must be valid UTF-8 text of at most 80000 bytes" end
		local source = markdown
		if source:sub(1, 3) == string.char(239, 187, 191) then source = source:sub(4) end
		local values, content = {}, source
		local firstEnd = source:find("\n", 1, true)
		if firstEnd and source:sub(1, firstEnd - 1):gsub("\r$", "") == "---" then
			local at, count, closed, seen = firstEnd + 1, 0, false, {}
			while at <= #source do
				local last = source:find("\n", at, true) or #source + 1
				if last > M.MAX_HEADER then return nil, "Frontmatter exceeds 12000 bytes" end
				local line = source:sub(at, last - 1):gsub("\r$", "")
				if line == "---" then content, closed = source:sub(last + 1), true; break end
				count = count + 1
				if count > 64 then return nil, "Frontmatter exceeds 64 lines" end
				if util.trim(line) ~= "" and not line:match("^%s*#") then
					local key, raw = line:match("^([%w_]+):%s*(.-)%s*$")
					if not key or seen[key] then return nil, "Frontmatter has an unsupported or repeated field" end
					seen[key] = true
					if key == "uai_vault" then
						if raw ~= "1" then return nil, "Unsupported Master Vault document version" end
					else
						local name = fields[key]
						if not name then return nil, "Unsupported frontmatter field: " .. util.ellipsis(key, 40) end
						local value, why = scalar(raw, name)
						if value == nil then return nil, why end
						values[name] = value
					end
				end
				at = last + 1
			end
			if not closed then return nil, "Frontmatter needs a closing --- line" end
		end
		values.content = content
		values.title = values.title or util.ellipsis(content:match("^#%s+([^\r\n]+)") or "Imported note", 160)
		return M.normalize(values)
	end
	local function sourcesText(sources)
		local rows = {}
		for _, source in ipairs(sources) do
			local row = '{"label":' .. util.encode(source.label)
			if source.url then row = row .. ',"url":' .. util.encode(source.url) end
			rows[#rows + 1] = row .. "}"
		end
		return "[" .. table.concat(rows, ",") .. "]"
	end
	function M.format(document)
		local value, why = M.normalize(document); if not value then return nil, why end
		local lines = { "---", "uai_vault: 1", "title: " .. util.encode(value.title), "description: " .. util.encode(value.description),
			"kind: " .. value.kind, "scope: " .. value.scope }
		if value.placeId then lines[#lines + 1] = "place_id: " .. string.format("%.0f", value.placeId) end
		if value.project then lines[#lines + 1] = "project: " .. util.encode(value.project) end
		lines[#lines + 1] = "tags: " .. util.encode(value.tags)
		lines[#lines + 1] = "sources: " .. sourcesText(value.sources)
		lines[#lines + 1] = "status: " .. value.status
		if value.verification then lines[#lines + 1] = "verification: " .. util.encode(value.verification) end
		lines[#lines + 1] = "updated_at: " .. string.format("%.0f", value.updatedAt)
		lines[#lines + 1] = "---"
		local header = table.concat(lines, "\n") .. "\n"
		if #header > M.MAX_HEADER or #header + #value.content > M.MAX_FILE then return nil, "Formatted note exceeds the document limit" end
		return header .. value.content
	end
	-- Revision identifiers detect conflicts; retained original bytes remain the write guard.
	function M.revision(source)
		local first, second = 5381, 2166136261
		for index = 1, #source do
			local byte = source:byte(index)
			first, second = (first * 33 + byte) % 4294967296, (second * 65599 + byte) % 4294967296
		end
		return string.format("%08x%08x:%d", first, second, #source)
	end
	return M
end
