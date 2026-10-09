-- Filesystem facade.
--
-- Executor filesystems are sandboxed to the executor's own workspace folder, so
-- paths here are relative to one app folder and never absolute. `..` is rejected
-- rather than normalised: a model-authored path is untrusted input, and the file
-- tools hand their argument straight to this module.
return function(env)
	local util = env.require("runtime/util")
	local caps = env.require("runtime/caps")
	local log = env.require("runtime/log")

	local M = {}

	M.enabled = caps.fs
	M.root = (env.info and env.info.folder) or "UAI"

	local knownFolders = {}

	function M.sanitise(path, limit)
		local original = tostring(path or "")
		if not util.validUtf8(original) then return nil, "path must contain valid UTF-8" end
		if original:match("^[\\/]") or original:match("^%a:") then return nil, "absolute paths are not allowed" end
		local clean = tostring(path or ""):gsub("\\", "/"):gsub("^/+", ""):gsub("/+", "/")
		if clean == "" then return nil, "empty path" end
		for _, part in ipairs(util.split(clean, "/")) do
			local device = part:upper():match("^[^%.]+") or ""
			if device == "CON" or device == "PRN" or device == "AUX" or device == "NUL" or device:match("^COM[1-9]$") or device:match("^LPT[1-9]$")
				or device:match("^COM\194[\178\179\185]$") or device:match("^LPT\194[\178\179\185]$") then return nil, "path contains a reserved device name" end
			if part == ".." then return nil, "path may not contain '..'" end
			if part == "." then return nil, "path may not contain '.'" end
			if part:find("[%z\1-\31\127]") then return nil, "path contains a control character" end
			-- Windows strips these suffixes, so '.. ' otherwise escapes a scope even
			-- though it passed the literal '..' check above.
			if part:match("[%. ]$") then return nil, "path segments may not end in a dot or space" end
			if part:find('[<>:"|%?%*]') then return nil, "path contains a reserved character" end
		end
		if #clean > (limit or 180) then return nil, "path is too long" end
		return clean
	end

	-- Absolute form used with the executor functions: everything the client owns
	-- lives under one folder so an uninstall is one delete.
	--
	-- `opts.scope` names a subfolder the path is resolved inside -- "files" for the
	-- agent's own workspace, "pastes" for long-message overflow. It exists so the
	-- model-authored files and the client's own state (config.json, sessions/,
	-- stats.json) never share a directory: a folder full of both is the "very messy"
	-- problem, and the fix is a prefix applied in one place rather than remembered by
	-- every caller.
	local SCOPES = { files = true, pastes = true, skills = true }

	function M.resolve(path, opts)
		opts = opts or {}
		local clean, err = M.sanitise(path)
		if not clean then return nil, err end
		if opts.raw then return clean end
		local base = M.root
		if opts.scope and SCOPES[opts.scope] then base = base .. "/" .. opts.scope end
		return base .. "/" .. clean
	end

	function M.ensure(dir)
		if not M.enabled or not caps.fn.makefolder then return false end
		local clean = M.sanitise(dir)
		if not clean then return false end
		local walk = ""
		for _, part in ipairs(util.split(clean, "/")) do
			walk = (walk == "") and part or (walk .. "/" .. part)
			if not knownFolders[walk] then
				local exists = false
				if caps.fn.isfolder then
					local ok, result = pcall(caps.fn.isfolder, walk)
					exists = ok and result == true
				end
				if not exists then
					local ok, made = pcall(caps.fn.makefolder, walk)
					if not ok or made == false then return false end
				end
				knownFolders[walk] = true
			end
		end
		return true
	end

	-- Every path-taking function accepts `opts` so a scoped caller can stay inside
	-- its folder without recomputing full paths: `M.read("notes.txt", { scope = "files" })`.
	-- The existence checks resolve the same way, or a scoped write would always think
	-- it was overwriting.
	function M.exists(path, opts)
		if not M.enabled or not caps.fn.isfile then return false end
		local full = M.resolve(path, opts)
		if not full then return false end
		local ok, result = pcall(caps.fn.isfile, full)
		return ok and result == true
	end

	function M.isDir(path, opts)
		if not M.enabled or not caps.fn.isfolder then return false end
		local full = M.resolve(path, opts)
		if not full then return false end
		local ok, result = pcall(caps.fn.isfolder, full)
		return ok and result == true
	end

	function M.read(path, opts)
		if not M.enabled then return nil, caps.reason("fs") end
		local full, err = M.resolve(path, opts)
		if not full then return nil, err end
		if not M.exists(path, opts) then return nil, "no such file: " .. full end
		local ok, content = pcall(caps.fn.readfile, full)
		if not ok then return nil, tostring(content) end
		if type(content) ~= "string" then return nil, "host returned no file contents: " .. full end
		return content
	end

	function M.write(path, content, opts)
		if not M.enabled then return false, caps.reason("fs") end
		local full, err = M.resolve(path, opts)
		if not full then return false, err end
		M.ensure(full:match("^(.*)/[^/]*$") or M.root)
		local ok, writeErr = pcall(caps.fn.writefile, full, tostring(content))
		if not ok or writeErr == false then
			if writeErr == false then writeErr = "host refused to write " .. full end
			log.warn("fsx", "write failed: " .. full, writeErr)
			return false, tostring(writeErr)
		end
		return true, full
	end

	-- Explicit user-file prefixes always win, even if a workspace file has the
	-- same name. Client state under the app root is never a fallback scope.
	function M.userPath(path)
		local clean, err = M.sanitise(path, 180 + #M.root + 8)
		if not clean then return nil, nil, err end
		if util.startsWith(clean, M.root .. "/") then clean = clean:sub(#M.root + 2) end
		for _, scope in ipairs({ "pastes", "files" }) do
			if clean == scope then return "", scope end
			if util.startsWith(clean, scope .. "/") then
				local name = clean:sub(#scope + 2)
				if name == "" then return "", scope end
				local safe, why = M.sanitise(name)
				return safe, scope, why
			end
		end
		local safe, why = M.sanitise(clean)
		return safe, nil, why
	end

	-- Model-facing paths share one namespace for every operation. Strip the
	-- advertised files/ prefix exactly once: files/files/x is a real nested
	-- directory, not a reason to silently redirect or delete an existing file.
	function M.workspacePath(path, allowRoot)
		if allowRoot and util.trim(path) == "" then return "", nil, "files/" end
		local clean, scope, err = M.userPath(path)
		if not clean then return nil, err end
		if scope and scope ~= "files" then return nil, scope .. "/ is read-only through workspace tools" end
		clean = clean:gsub("/+$", "")
		if clean == "" and not allowRoot then return nil, "a file or subfolder inside files/ is required" end
		return clean, nil, "files/" .. clean
	end

	function M.readUser(path)
		local name, scope, err = M.userPath(path)
		if not name then return nil, err end
		if scope then
			local content, why = M.read(name, { scope = scope })
			return content, why, scope .. "/" .. name
		end
		local content, why = M.read(name, { scope = "files" })
		if content ~= nil or M.exists(name, { scope = "files" }) then return content, why, "files/" .. name end
		content, why = M.read(name, { scope = "pastes" })
		return content, why, "pastes/" .. name
	end

	function M.append(path, content, opts)
		if not M.enabled then return false, caps.reason("fs") end
		local full, err = M.resolve(path, opts)
		if not full then return false, err end
		M.ensure(full:match("^(.*)/[^/]*$") or M.root)
		if caps.fn.appendfile then
			local ok, appendErr = pcall(caps.fn.appendfile, full, tostring(content))
			if ok and appendErr ~= false then return true, full end
			if appendErr == false then appendErr = "host refused to append to " .. full end
			return false, tostring(appendErr)
		end
		-- Not every host has appendfile; read-modify-write is correct, just worse.
		local existing, readErr = M.read(path, opts)
		if existing == nil then
			if M.exists(path, opts) then return false, readErr end
			existing = ""
		end
		return M.write(path, existing .. tostring(content), opts)
	end

	function M.delete(path, opts)
		if not M.enabled then return false, caps.reason("fs") end
		local full, err = M.resolve(path, opts)
		if not full then return false, err end
		if M.isDir(path, opts) then
			if not caps.fn.delfolder then return false, "this host cannot delete folders" end
			local ok, delErr = pcall(caps.fn.delfolder, full)
			ok = ok and delErr ~= false
			if delErr == false then delErr = "host refused to delete " .. full end
			if ok then
				-- A later write must recreate this directory and every cached descendant.
				local removed = full:gsub("/+$", "")
				local prefix = removed .. "/"
				for folder in pairs(knownFolders) do
					if folder == removed or folder:sub(1, #prefix) == prefix then knownFolders[folder] = nil end
				end
			end
			return ok, ok and full or tostring(delErr)
		end
		if not caps.fn.delfile then return false, "this host cannot delete files" end
		local ok, delErr = pcall(caps.fn.delfile, full)
		ok = ok and delErr ~= false
		if delErr == false then delErr = "host refused to delete " .. full end
		return ok, ok and full or tostring(delErr)
	end

	-- listfiles returns host-shaped paths: some absolute, some backslashed, some
	-- already relative. They are normalised back to app-relative so a caller
	-- never has to care which executor it is on.
	function M.list(path, opts)
		if not M.enabled or not caps.fn.listfiles then return {}, caps.reason("fs") end
		opts = opts or {}
		-- The empty path is the root of whatever is being listed -- the whole app
		-- folder, or the whole scope. sanitise() refuses it because an empty path is
		-- no path at all for every other operation; here it is the one thing that
		-- means "everything".
		local base = M.root
		if opts.scope and SCOPES[opts.scope] then base = base .. "/" .. opts.scope end
		local trimmed = tostring(path or ""):gsub("\\", "/"):gsub("/+$", "")
		local full
		if trimmed == "" then
			full = base
		else
			local clean = M.sanitise(trimmed)
			if not clean then return {}, "bad path" end
			trimmed = clean
			full = base .. "/" .. clean
		end
		local scopePrefix = (base ~= M.root) and (base:sub(#M.root + 2) .. "/") or ""
		local ok, entries = pcall(caps.fn.listfiles, full)
		if not ok then return {}, tostring(entries) end
		if type(entries) ~= "table" then return {}, "host returned an invalid file listing" end
		local out, rejected, seen = {}, 0, {}
		for _, entry in ipairs(entries) do
			local normal = tostring(entry):gsub("\\", "/"):gsub("/+$", "")
			local candidates, checked = {}, {}
			local function consider(relative)
				if checked[relative] then return end
				checked[relative] = true
				if not M.sanitise(relative) or relative == trimmed
					or (trimmed ~= "" and not util.startsWith(relative, trimmed .. "/")) then return end
				local directory = M.isDir(relative, opts)
				if directory or M.exists(relative, opts) then
					candidates[#candidates + 1] = { path = relative, name = relative:match("[^/]+$"), isDir = directory }
				end
			end
			-- Explicit host-root paths have one meaning. Relative host listings can
			-- be app-, scope- or directory-relative; resolve only an existing unique
			-- candidate inside the requested directory. Never strip a real files/
			-- child blindly, and never return corrupt names the host cannot open.
			if util.startsWith(normal, base .. "/") then consider(normal:sub(#base + 2))
			elseif normal:match("^/") or normal:match("^%a:") then
				local at = normal:find("/" .. base .. "/", 1, true)
				if at then consider(normal:sub(at + #base + 2)) end
			else
				consider(normal)
				if scopePrefix ~= "" and util.startsWith(normal, scopePrefix) then consider(normal:sub(#scopePrefix + 1)) end
				if trimmed ~= "" then consider(trimmed .. "/" .. normal) end
			end
			if #candidates == 1 then
				local item = candidates[1]
				if not seen[item.path] then out[#out + 1] = item; seen[item.path] = true end
			else rejected = rejected + 1 end
		end
		table.sort(out, function(a, b) return a.path < b.path end)
		return out, rejected > 0 and "host listing contains ambiguous, inaccessible or unsupported paths; listing is incomplete" or nil
	end

	function M.readJson(path, fallback)
		local content = M.read(path)
		if not content then return fallback end
		local value, err = util.decode(content)
		if value == nil then
			log.warn("fsx", "corrupt json at " .. tostring(path), err)
			return fallback
		end
		return value
	end

	function M.writeJson(path, value)
		local ok, body = pcall(util.encode, value)
		if not ok then return false, tostring(body) end
		return M.write(path, body)
	end

	-- Migration ----------------------------------------------------------------
	--
	-- Before the workspace split, everything the agent wrote landed in the app
	-- folder's root beside the client's own config.json, sessions/ and stats.json.
	-- The tools now resolve inside files/, which made every one of those older files
	-- invisible overnight -- "tidy" and "where did my files go" are the same change
	-- seen from two sides. This moves them into files/ once: anything at the root
	-- that is not the client's own state and not itself a scope folder is relocated
	-- verbatim.
	local CLIENT_STATE = {
		["code"] = true,
		["config.json"] = true,
		["stats.json"] = true,
		["workspace.json"] = true,
		["sessions"] = true,
		["export"] = true,
		["icons"] = true,
		["bridge"] = true,
	}

	function M.migrate(onProgress)
		if not M.enabled then return 0 end
		local function transfer(source, sourceOpts, target, targetOpts)
			local body = M.read(source, sourceOpts)
			if body == nil then return false end
			if M.exists(target, targetOpts) then
				if M.read(target, targetOpts) ~= body then return false end
			else
				local ok = M.write(target, body, targetOpts)
				if not ok or M.read(target, targetOpts) ~= body then return false end
			end
			-- Verification and conflict checks precede deletion, including skill
			-- recovery. A refused or partial write must never destroy the source.
			return M.delete(source, sourceOpts)
		end
		local function removeEmpty(path, opts)
			local entries, err = M.list(path, opts)
			if not err and #entries == 0 then M.delete(path, opts) end
		end

		-- Recovery: if a previous buggy migration moved playbooks from skills/ into files/skills/,
		-- restore them back to the skills scope so the user does not lose their installed skills.
		if M.isDir("skills", { scope = "files" }) then
			local displaced = M.list("skills", { scope = "files" })
			local recovered = 0
			for _, file in ipairs(displaced) do
				if not file.isDir and tostring(file.name):sub(-3):lower() == ".md" then
					if transfer(file.path, { scope = "files" }, file.name, { scope = "skills" }) then
						recovered = recovered + 1
					end
				end
			end
			removeEmpty("skills", { scope = "files" })
			if recovered > 0 then
				log.info("fsx", string.format("recovered %d misplaced skill(s) from files/skills/ into skills/", recovered))
			end
		end

		-- Idempotent: once the root holds only client state and scope folders, the
		-- sweep finds nothing and costs a single listfiles.
		--
		-- Top-level entries only. Some hosts (and the mock) list recursively, so the
		-- root listing can include files already inside files/ -- treating those as
		-- legacy is what moves a file into files/files/ on the second boot, and worse,
		-- what walks the client's own sessions/ transcripts into the workspace.
		local entries = M.list("")
		local moved, skipped = 0, 0
		local visited, visitedCount = {}, 0
		local function moveFile(path)
			if transfer(path, nil, path, { scope = "files" }) then
				moved = moved + 1
				if onProgress then onProgress(moved, path) end
			end
		end
		local function moveDirectory(path, depth)
			if visited[path] or depth > 32 or visitedCount >= 512 then return end
			visited[path], visitedCount = true, visitedCount + 1
			for _, file in ipairs(M.list(path)) do
				if util.startsWith(file.path, path .. "/") then
					if file.isDir then moveDirectory(file.path, depth + 1)
					else moveFile(file.path) end
				end
			end
			-- Shallow host listings must not mistake a remaining child directory
			-- for an empty tree and recursively remove its untransferred data.
			removeEmpty(path)
		end
		for _, entry in ipairs(entries) do
			-- Anything nested is somebody else's subdirectory, not a legacy root file.
			if tostring(entry.path or ""):find("/", 1, true) then
				skipped = skipped + 1
			else
				local name = tostring(entry.name or "")
				local isScope = SCOPES[name:lower()] == true
				local isState = CLIENT_STATE[name:lower()] == true
				if entry.isDir and not isScope and not isState then
					-- A folder the agent made for itself (notes/, builds/). Rewritten
					-- under files/ by full relative path, which keeps nested structure:
					-- executors offer no rename across directories, so a directory copy
					-- is a loop over listfiles.
					moveDirectory(entry.path, 1)
				elseif not entry.isDir and not isState and not isScope then
					moveFile(entry.path)
				else
					skipped = skipped + 1
				end
			end
		end
		if moved > 0 then
			log.info("fsx", string.format("migrated %d file(s) into files/", moved))
		end
		return moved, skipped
	end

	return M
end
