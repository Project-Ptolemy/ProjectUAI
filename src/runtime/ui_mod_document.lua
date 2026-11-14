-- Portable visual specifications and unrestricted script source. Validation never executes source.
return function(env)
	local util = env.require("runtime/util")
	local M = { limits = { source = 262144, json = 786432, visualJson = 32768,
		panels = 4, widgets = 12, body = 2000, sources = 8, depth = 8, nodes = 160 },
		kinds = { "visual", "script" }, metrics = { "tokens", "context", "goals", "tools", "requests" },
		actions = { "chat", "code", "vault", "agents", "providers", "tools", "settings", "logs", "micro_goals", "commands" },
		enums = {
			theme = { "default", "newyear", "valentine", "earthday", "pride", "peace", "halloween", "christmas" },
			accent = { "claude", "aurora", "indigo", "amber", "rose" }, density = { "comfortable", "compact" },
			interfaceFont = { "montserrat", "builder", "arimo", "roboto", "nunito", "titillium", "ubuntu", "source", "gotham" },
			codeFont = { "code", "roboto" }, codeTheme = { "dark", "light" }, transcriptWidth = { "narrow", "medium", "wide" },
		} }
	local appearanceOrder = { "theme", "accent", "density", "fontScale", "interfaceFont", "codeFont", "codeTheme", "transcriptWidth" }
	local function member(list, value)
		for _, candidate in ipairs(list) do if candidate == value then return true end end
		return false
	end
	local function text(value, maximum, required, multiline)
		return type(value) == "string" and #value <= maximum and util.validUtf8(value)
			and not value:find(multiline and "[%z\1-\8\11\12\14-\31\127]" or "[%z\1-\31\127]")
			and (not required or util.trim(value) ~= "")
	end
	local function slug(value)
		return type(value) == "string" and #value >= 1 and #value <= 48 and value:match("^[a-z0-9][a-z0-9_-]*$") ~= nil
	end
	M.validId = slug
	local function plainLabel(value, maximum)
		if not text(value, maximum, true) or value:find("[<>`*#%[%]|]") then return false end
		-- Labels stay words and punctuation; visual mods do not supply icon glyphs.
		local at = 1
		while at <= #value do
			local byte, point, width = value:byte(at), value:byte(at), 1
			if byte >= 240 then point, width = byte - 240, 4
			elseif byte >= 224 then point, width = byte - 224, 3
			elseif byte >= 192 then point, width = byte - 192, 2 end
			for offset = 1, width - 1 do point = point * 64 + value:byte(at + offset) - 128 end
			if point >= 0x2190 and point <= 0x2bff or point >= 0x1f000 and point <= 0x1faff
				or point == 0x2022 or point == 0x2023 or point == 0x200d or point == 0xfe0f then return false end
			at = at + width
		end
		return true
	end
	local function object(value, allowed, maximum)
		if type(value) ~= "table" then return false end
		local count = 0
		for key in pairs(value) do
			count = count + 1
			if count > maximum or type(key) ~= "string" or not allowed[key] then return false end
		end
		return true
	end
	local function array(value, maximum)
		if type(value) ~= "table" or #value > maximum then return false end
		local count = 0
		for key in pairs(value) do
			count = count + 1
			if count > maximum or type(key) ~= "number" or key < 1 or key > #value or key ~= math.floor(key) then return false end
		end
		return count == #value
	end
	local common = { version = true, kind = true, id = true, name = true, description = true, author = true, sources = true,
		source = true, appearance = true, panels = true }
	local appearanceFields = {}; for _, key in ipairs(appearanceOrder) do appearanceFields[key] = true end
	local sourceFields = { label = true, url = true }
	local panelFields = { id = true, title = true, description = true, widgets = true }
	local widgetFields = { id = true, type = true, body = true, label = true, selector = true, action = true }
	local function normalize(value)
		if not object(value, common, 10) or value.version ~= 1 then return nil, "Provide a supported version-1 UI mod object with documented fields" end
		if not slug(value.id) then return nil, "Mod IDs use 1-48 lowercase ASCII letters, digits, underscores or hyphens" end
		if not member(M.kinds, value.kind) then return nil, "Mod kind must be visual or script" end
		if not plainLabel(value.name, 100) then return nil, "Mod names must be plain text within 100 UTF-8 bytes" end
		if value.description ~= nil and not text(value.description, 500, false) then return nil, "Description must be one line within 500 UTF-8 bytes" end
		if value.author ~= nil and not text(value.author, 160, true) then return nil, "Author must be nonblank text within 160 UTF-8 bytes" end
		local clean = { version = 1, kind = value.kind, id = value.id, name = util.trim(value.name),
			description = util.trim(value.description or ""), sources = {} }
		if value.author then clean.author = util.trim(value.author) end
		local references = value.sources == nil and {} or value.sources
		if not array(references, M.limits.sources) then return nil, "Provide at most eight source references" end
		for _, source in ipairs(references) do
			if not object(source, sourceFields, 2) or not text(source.label, 160, true)
				or source.url ~= nil and not text(source.url, 500, true) then return nil, "Source references need a label and optional URL/document reference" end
			clean.sources[#clean.sources + 1] = { label = util.trim(source.label), url = source.url and util.trim(source.url) or nil }
		end
		if value.kind == "script" then
			if value.appearance ~= nil or value.panels ~= nil then return nil, "Script mods use source; visual appearance and panels belong to visual mods" end
			if not text(value.source, M.limits.source, true, true) then return nil, "Script source must contain valid UTF-8 text within 262144 bytes" end
			clean.source = value.source
			return clean
		end
		if value.source ~= nil then return nil, "Visual mods do not contain executable source; use kind=script for Lua mods" end
		local appearance = value.appearance == nil and {} or value.appearance
		if not object(appearance, appearanceFields, 8) then return nil, "Appearance accepts only documented UI preferences" end
		clean.appearance = {}
		for _, key in ipairs(appearanceOrder) do
			local option = appearance[key]
			if option ~= nil then
				if key == "fontScale" then
					if type(option) ~= "number" or option ~= option or option < 0.85 or option > 1.4 then return nil, "fontScale must be a finite number from 0.85 to 1.4" end
				elseif not member(M.enums[key], option) then return nil, "Unsupported appearance preference: " .. key end
				clean.appearance[key] = option
			end
		end
		local panels = value.panels == nil and {} or value.panels
		if not array(panels, M.limits.panels) then return nil, "A visual mod supports at most four panels" end
		clean.panels = {}
		local panelIds, widgetIds, widgetCount = {}, {}, 0
		for _, panel in ipairs(panels) do
			if not object(panel, panelFields, 4) or not slug(panel.id) or panelIds[panel.id]
				or not plainLabel(panel.title, 100) or panel.description ~= nil and not text(panel.description, 500, false)
				or not array(panel.widgets, M.limits.widgets) then return nil, "Panels need unique stable IDs, plain titles and a bounded widgets array" end
			panelIds[panel.id] = true
			local row = { id = panel.id, title = util.trim(panel.title), description = util.trim(panel.description or ""), widgets = {} }
			for _, widget in ipairs(panel.widgets) do
				widgetCount = widgetCount + 1
				if widgetCount > M.limits.widgets or not object(widget, widgetFields, 6) or not slug(widget.id) or widgetIds[widget.id] then
					return nil, "A mod supports at most twelve widgets with unique stable IDs"
				end
				widgetIds[widget.id] = true
				local item = { id = widget.id, type = widget.type }
				if widget.type == "text" then
					if not text(widget.body, M.limits.body, true, true) or widget.label ~= nil or widget.selector ~= nil or widget.action ~= nil then
						return nil, "Text widgets accept only a nonblank plain body within 2000 UTF-8 bytes"
					end
					item.body = widget.body
				elseif widget.type == "metric" then
					if not plainLabel(widget.label, 100) or not member(M.metrics, widget.selector) or widget.body ~= nil or widget.action ~= nil then
						return nil, "Metric widgets need a plain label and one documented aggregate selector"
					end
					item.label, item.selector = util.trim(widget.label), widget.selector
				elseif widget.type == "action" then
					if not plainLabel(widget.label, 100) or not member(M.actions, widget.action) or widget.body ~= nil or widget.selector ~= nil then
						return nil, "Action widgets need a plain label and one documented navigation action"
					end
					item.label, item.action = util.trim(widget.label), widget.action
				else return nil, "Widget type must be text, metric or action" end
				row.widgets[#row.widgets + 1] = item
			end
			clean.panels[#clean.panels + 1] = row
		end
		return clean
	end
	local function fields(value, order)
		local parts = {}
		for _, key in ipairs(order) do if value[key] ~= nil then parts[#parts + 1] = util.encode(key) .. ":" .. util.encode(value[key]) end end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	local function encode(value)
		local parts = {}
		for _, key in ipairs({ "version", "kind", "id", "name", "description", "author" }) do
			if value[key] ~= nil then parts[#parts + 1] = util.encode(key) .. ":" .. util.encode(value[key]) end
		end
		local sources = {}; for _, source in ipairs(value.sources) do sources[#sources + 1] = fields(source, { "label", "url" }) end
		parts[#parts + 1] = '"sources":[' .. table.concat(sources, ",") .. "]"
		if value.kind == "script" then parts[#parts + 1] = '"source":' .. util.encode(value.source)
		else
			parts[#parts + 1] = '"appearance":' .. fields(value.appearance, appearanceOrder)
			local panels = {}
			for _, panel in ipairs(value.panels) do
				local widgets = {}; for _, widget in ipairs(panel.widgets) do widgets[#widgets + 1] = fields(widget, { "id", "type", "body", "label", "selector", "action" }) end
				panels[#panels + 1] = '{"id":' .. util.encode(panel.id) .. ',"title":' .. util.encode(panel.title)
					.. ',"description":' .. util.encode(panel.description) .. ',"widgets":[' .. table.concat(widgets, ",") .. "]}"
			end
			parts[#parts + 1] = '"panels":[' .. table.concat(panels, ",") .. "]"
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	function M.validate(value)
		local clean, why = normalize(value); if not clean then return nil, why end
		local json = encode(clean)
		if #json > (clean.kind == "visual" and M.limits.visualJson or M.limits.json) then return nil, "The portable UI mod exceeds its JSON byte limit" end
		return clean
	end
	function M.format(value)
		local clean, why = M.validate(value); if not clean then return nil, why end
		return encode(clean)
	end
	-- Bound depth/member allocation and reject duplicate object keys before native JSON decoding.
	function M.decodeJson(json, maximum, maxDepth, maxNodes)
		if not text(json, maximum or M.limits.json, true, true) then return nil, "JSON must be valid bounded UTF-8 text" end
		local stack, quoted, escaped, start, nodes = {}, false, false, 0, 0
		for at = 1, #json do
			local char = json:sub(at, at)
			if quoted then
				if escaped then escaped = false
				elseif char == "\\" then escaped = true
				elseif char == '"' then
					quoted = false
					local tail = at + 1; while json:sub(tail, tail):match("%s") do tail = tail + 1 end
					if json:sub(tail, tail) == ":" then
						local context = stack[#stack]
						if not context or context.kind ~= "{" or at - start > 192 then return nil, "Invalid JSON object key" end
						local key = util.decode(json:sub(start, at))
						if type(key) ~= "string" or #key > 64 or context.keys[key] then return nil, "JSON object keys must be unique and bounded" end
						context.keys[key] = true
					end
				elseif char:byte() < 32 then return nil, "JSON strings must escape control characters" end
			elseif char == '"' then quoted, start = true, at
			elseif char == "{" or char == "[" then
				nodes = nodes + 1
				if #stack >= (maxDepth or M.limits.depth) or nodes > (maxNodes or M.limits.nodes) then return nil, "JSON nesting or entry count exceeds the limit" end
				stack[#stack + 1] = { kind = char, keys = {} }
			elseif char == "," then
				nodes = nodes + 1
				if nodes > (maxNodes or M.limits.nodes) then return nil, "JSON nesting or entry count exceeds the limit" end
			elseif char == "}" or char == "]" then
				local context = stack[#stack]
				if not context or context.kind ~= (char == "}" and "{" or "[") then return nil, "Invalid JSON structure" end
				stack[#stack] = nil
			end
		end
		if quoted or escaped or #stack ~= 0 then return nil, "Incomplete JSON structure" end
		local value = util.decode(json)
		if type(value) ~= "table" then return nil, "JSON must contain an object" end
		return value
	end
	function M.parse(json)
		local value, why = M.decodeJson(json); if not value then return nil, why end
		if value.kind == "visual" and #json > M.limits.visualJson then return nil, "Visual mod JSON exceeds 32768 bytes" end
		return M.validate(value)
	end
	function M.fingerprint(json)
		local first, second = 5381, 2166136261
		for index = 1, #json do local byte = json:byte(index); first, second = (first * 33 + byte) % 4294967296, (second * 65599 + byte) % 4294967296 end
		return string.format("%08x%08x:%d", first, second, #json)
	end
	return M
end
