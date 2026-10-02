-- Explicit file projects, source snapshots, dependency checks and deterministic bundles.
return function(env)
	local fs = env.require("runtime/fsx")
	local util = env.require("runtime/util")
	local source = env.require("runtime/project_source")
	local caps = env.require("runtime/caps")
	local M = { MAX_BYTES = 1024 * 1024, MAX_MODULES = 64 }
	local scope = { scope = "files" }
	function M.path(path)
		local clean, area, why = fs.userPath(path)
		if not clean or clean == "" or (area and area ~= "files") then return nil, why or "Use a path under files/" end
		return clean
	end
	function M.read(path)
		local clean, why = M.path(path); if not clean then return nil, why end
		local text, err = fs.read(clean, scope)
		if text == nil then return nil, err end
		if not source.valid(text) then return nil, "Source must be UTF-8 text without NUL, at most 256000 bytes: " .. clean end
		return text, clean
	end
	local function idValid(id)
		if type(id) ~= "string" or #id > 100 or not id:match("^[%w_%-/]+$") then return false end
		return id:sub(1, 1) ~= "/" and id:sub(-1) ~= "/" and not id:find("//", 1, true)
	end
	function M.load(path, ctx)
		local body, manifestPath = M.read(path)
		if not body then return nil, manifestPath end
		if #body > 32000 then return nil, "Project manifest exceeds 32000 bytes" end
		local manifest, why = util.decode(body)
		if type(manifest) ~= "table" or manifest.version ~= 1 or type(manifest.modules) ~= "table" then return nil, why or "Expected version=1 and a modules map" end
		for key in pairs(manifest) do if key ~= "version" and key ~= "entry" and key ~= "modules" and key ~= "tests" then return nil, "Unknown project field: " .. tostring(key) end end
		local ids = util.keys(manifest.modules, true)
		if #ids < 1 or #ids > M.MAX_MODULES then return nil, "Declare 1-64 modules" end
		if not idValid(manifest.entry) or not manifest.modules[manifest.entry] then return nil, "Entry must name a declared module" end
		local root = manifestPath:match("^(.*)/[^/]+$") or ""
		local project = { manifest = manifestPath, manifestSource = body, entry = manifest.entry, modules = {}, ids = ids, tests = {}, bytes = 0 }
		local seen = { [manifestPath:lower()] = true }
		for _, id in ipairs(ids) do
			if not idValid(id) then return nil, "Module IDs use letters, digits, underscores, hyphens and slash segments" end
			local relative = manifest.modules[id]
			if type(relative) ~= "string" then return nil, "Module paths must be strings" end
			local clean, err = fs.sanitise(relative)
			if not clean or clean ~= relative or not (clean:match("%.lua$") or clean:match("%.luau$")) then return nil, err or "Use exact relative .lua/.luau module paths" end
			local full = root ~= "" and root .. "/" .. clean or clean
			if seen[full:lower()] then return nil, "Duplicate or aliased project path: " .. full end
			seen[full:lower()] = true
			local text, readErr = fs.read(full, scope)
			if not source.valid(text) then return nil, readErr or "Invalid or oversized source: " .. full end
			project.bytes = project.bytes + #text
			if project.bytes > M.MAX_BYTES then return nil, "Project sources exceed 1 MiB" end
			local outline, scanErr = source.scan(text, ctx); if not outline then return nil, scanErr end
			project.modules[id] = { id = id, path = full, source = text, outline = outline }
			if ctx and ctx.aborted and ctx.aborted() then return nil, "Project read cancelled" end
		end
		if manifest.tests ~= nil and (type(manifest.tests) ~= "table" or not util.isArray(manifest.tests) or #manifest.tests > 16) then return nil, "tests must be an array of at most 16 module IDs" end
		local testIds = {}
		for _, id in ipairs(manifest.tests or {}) do
			if not idValid(id) or not project.modules[id] or testIds[id] then return nil, "Tests must name distinct declared modules" end
			testIds[id] = true; project.tests[#project.tests + 1] = id
		end
		return project
	end
	function M.current(project)
		if fs.read(project.manifest, scope) ~= project.manifestSource then return false, "Project manifest changed; inspect again" end
		for _, id in ipairs(project.ids) do
			local item = project.modules[id]
			if fs.read(item.path, scope) ~= item.source then return false, "Project source changed: " .. item.path end
		end
		return true
	end
	function M.analyze(project)
		local diagnostics, errors, warnings, omitted = {}, 0, 0, 0
		local function report(item, severity, code, message, line, column)
			if severity == "error" then errors = errors + 1 else warnings = warnings + 1 end
			if #diagnostics < 512 then diagnostics[#diagnostics + 1] = { path = item.path, severity = severity, code = code, message = util.ellipsis(message, 1200), line = line, column = column }
			else omitted = omitted + 1 end
		end
		for _, id in ipairs(project.ids) do
			local item = project.modules[id]
			if caps.fn.loadstring then
				local ok, fn, err = pcall(caps.fn.loadstring, item.source, "@" .. item.path)
				if not ok or not fn then
					local message = tostring(ok and err or fn)
					report(item, "error", "syntax", message, tonumber(message:match(":(%d+):")))
				end
			end
			for _, dependency in ipairs(item.outline.imports) do
				if dependency.dynamic then report(item, "warning", "dynamic_require", "Cannot statically resolve this require; only declared project IDs resolve at runtime", dependency.line, dependency.column)
				elseif not project.modules[dependency.id] then report(item, "error", "missing_module", "Undeclared project module: " .. dependency.id, dependency.line, dependency.column) end
			end
			if item.outline.omitted > 0 then report(item, "warning", "outline_limit", "Additional symbols/imports were omitted") end
		end
		local visiting, visited = {}, {}
		local function visit(id)
			if visited[id] then return end
			if visiting[id] then report(project.modules[id], "error", "dependency_cycle", "Literal require cycle reaches " .. id); return end
			visiting[id] = true
			for _, dep in ipairs(project.modules[id].outline.imports) do if dep.id and project.modules[dep.id] then visit(dep.id) end end
			visiting[id], visited[id] = nil, true
		end
		for _, id in ipairs(project.ids) do visit(id) end
		return { ok = errors == 0, errors = errors, warnings = warnings, diagnostics = diagnostics, omittedDiagnostics = omitted,
			compilerAvailable = caps.fn.loadstring ~= nil, typeChecked = false,
			coverage = "Host syntax compiler plus literal project dependency checks. Lexical imports may be shadowed. No Roblox API/type analysis or runtime validation." }
	end
	function M.bundle(project, entry, testing)
		if not project.modules[entry] then return nil, "Entry must name a declared module" end
		local chunks, line, locations = {}, 1, {}
		local function append(text)
			chunks[#chunks + 1] = text
			local _, lines = text:gsub("\n", ""); line = line + lines
		end
		append("-- Project UAI bundle v1; project-local require; no source is executed by building.\nlocal __modules = {}\n")
		for _, id in ipairs(project.ids) do
			local item = project.modules[id]
			append("__modules[" .. string.format("%q", id) .. "] = function(require, fixtures)\n")
			locations[#locations + 1] = { id = id, path = item.path, firstLine = line, lastLine = line + item.outline.lines - 1, hash = item.outline.hash }
			append(item.source .. "\nend\n")
		end
		append([[local function __newRequire(fixtures)
	local cache, loaded, active = {}, {}, {}
	local function require(id)
		if loaded[id] then return cache[id] end
		local factory = __modules[id]
		if not factory then error("Undeclared project module: " .. tostring(id), 2) end
		if active[id] then error("Project require cycle: " .. tostring(id), 2) end
		active[id] = true
		local ok, value = pcall(factory, require, fixtures)
		active[id] = nil
		if not ok then error(value, 0) end
		if value == nil then value = true end
		cache[id], loaded[id] = value, true
		return value
	end
	return require
end
]])
		if testing then append(testing)
		else append("return __newRequire({})(" .. string.format("%q", entry) .. ")\n") end
		local output = table.concat(chunks)
		if #output > M.MAX_BYTES + 64000 then return nil, "Generated bundle exceeds its size budget" end
		return output, locations
	end
	return M
end
