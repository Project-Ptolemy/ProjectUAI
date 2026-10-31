-- Vault connections are user-owned; tools can only operate inside those roots.
return function(env)
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")
	local vault = env.require("runtime/obsidian")
	local transport = env.require("net/obsidian")
	local tools = {}
	local shared = { vault = { type = "string", description = "Stable vault id from obsidian_vaults." },
		path = { type = "string", description = "Exact vault-relative .md path, using forward slashes." },
		offset = { type = "integer", minimum = 1 }, limit = { type = "integer", minimum = 1, maximum = 100 } }
	local function request(input, ctx)
		return transport.request(input, { aborted = ctx and ctx.aborted })
	end
	local function add(name, action, description, properties, required, risk, reader)
		tools[#tools + 1] = { name = name, group = "obsidian", risk = risk or "read", needs = { "http" }, description = description,
			parameters = { type = "object", properties = properties, required = required }, run = function(args, ctx)
				local input = util.copy(args); input.action = action
				if input.path then local clean, why = vault.path(input.path); if not clean then return H.fail(why) end; input.path = clean end
				if input.folder then local clean, why = vault.path(input.folder, true); if not clean then return H.fail(why) end; input.folder = clean end
				if reader then return reader(input, ctx) end
				local value, why = request(input, ctx)
				if not value then return H.fail(why) end
				if value.data then local page, err = vault.page(value, H.resultBudget()); return page or H.fail(err) end
				return { text = util.encode(value), data = value }
			end }
	end
	add("obsidian_vaults", "vaults", "List the user's connected Obsidian vault ids, names, availability and read-only policy. Connect vault folders in Settings > Obsidian. These are files on the UAI Bridge computer, separate from executor workspace files.", { offset = shared.offset, limit = shared.limit }, {}, nil,
		function(input, ctx)
			local value, why = request(input, ctx); if not value then return H.fail(why) end
			if type(value.vaults) ~= "table" then return H.fail("The bridge returned an invalid vault list.") end
			return H.page(value.vaults, input, "Connected vaults", function(row) return util.encode(row) end)
		end)
	add("obsidian_list", "list", "List Markdown notes in a connected vault, optionally below a folder. Results paginate; preserve nextOffset. Hidden settings and linked folders are excluded; incomplete coverage is explicit.",
		{ vault = shared.vault, folder = { type = "string" }, offset = shared.offset, limit = shared.limit }, { "vault" })
	add("obsidian_search", "search", "Search note paths and content with literal case-insensitive text. Returns exact paths, matching line excerpts and revisions; paginate with nextOffset. Search is bounded and incomplete coverage is reported.",
		{ vault = shared.vault, query = { type = "string", minLength = 1, maxLength = 300 }, folder = { type = "string" }, offset = shared.offset, limit = shared.limit }, { "vault", "query" })
	add("obsidian_read", "read", "Read a UTF-8 note page and its SHA-256 revision. Preserve nextOffset and revision for later pages; a changed note rejects continuation. Use obsidian_metadata for headings, tags and frontmatter. Read before updating or appending.",
		{ vault = shared.vault, path = shared.path, offset = shared.offset, limit = { type = "integer", minimum = 4, maximum = 12000 }, revision = { type = "string" } }, { "vault", "path" }, nil,
		function(input, ctx)
			local available = H.resultBudget() - #input.path - 400
			if available < 4 then return H.fail("Increase the tool result budget before reading this note path.") end
			input.metadata = false; input.limit = math.min(input.limit or 6000, available)
			local value, why = request(input, ctx); if not value then return H.fail(why) end
			if type(value.content) ~= "string" or type(value.revision) ~= "string" then return H.fail("The bridge returned an invalid note page.") end
			local content = value.content; value.content = nil
			return { text = input.path .. "\nrevision=" .. value.revision .. "\n" .. content, data = value }
		end)
	add("obsidian_metadata", "read", "Read a note's title, headings, tags, wiki links and frontmatter. Frontmatter raw text is authoritative; parsed properties cover simple scalar values only. Code fences do not count as note links.",
		{ vault = shared.vault, path = shared.path }, { "vault", "path" }, nil,
		function(input, ctx)
			input.limit = 4
			local value, why = request(input, ctx); if not value then return H.fail(why) end
			local metadata = value.metadata or {}
			local entries = {}
			for _, key in ipairs({ "title", "frontmatter", "properties", "headings", "tags", "links", "limited" }) do entries[#entries + 1] = { field = key, value = metadata[key] } end
			local page, err = vault.page({ data = entries, total = #entries, offset = 1 }, H.resultBudget())
			if not page then return H.fail(err) end
			if page.data.nextOffset then return H.fail("This note's metadata exceeds the tool result budget. Read its text pages or increase Tool result limit.") end
			page.data.revision = value.revision; return page
		end)
	for _, operation in ipairs({ { "links", "List outgoing wiki and Markdown links with resolved exact note paths or ambiguity candidates. Resolution favors a note in the source folder, then a vault-relative path, then a unique basename." },
		{ "backlinks", "Find notes linking to this exact note path. Ambiguous basename links are not claimed as backlinks. Coverage and continuations are explicit." } }) do
		add("obsidian_" .. operation[1], operation[1], operation[2], { vault = shared.vault, path = shared.path, offset = shared.offset, limit = shared.limit }, { "vault", "path" })
	end
	local writeFields = { vault = shared.vault, path = shared.path, content = { type = "string", maxLength = vault.MAX_BYTES }, revision = { type = "string", minLength = 64, maxLength = 64 } }
	add("obsidian_create", "create", "Create a new Markdown note with parent folders. Never overwrites an existing note. Editing must be enabled by the user for this vault; content is limited to 1 MiB and verified after saving.", writeFields, { "vault", "path", "content" }, "write")
	add("obsidian_update", "update", "Replace note content using the exact revision returned by obsidian_read. A stale revision fails without changing the note. Preserve frontmatter and unrelated content. Editing must be enabled for the vault.", writeFields, { "vault", "path", "content", "revision" }, "write")
	add("obsidian_append", "append", "Append text using the exact current note revision. Include your own newline. A stale revision fails; maximum final note size is 1 MiB. Read the note before appending.", writeFields, { "vault", "path", "content", "revision" }, "write")
	return tools
end
