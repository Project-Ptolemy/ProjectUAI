-- Master Vault tools keep note contents out of the standing prompt and preserve revisions.
return function(env)
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")
	local vault = env.require("runtime/master_vault")
	local codec = env.require("runtime/vault_document")
	local tools = {}
	local id = { type = "string", minLength = 6, maxLength = 140, description = "Exact starter: or note: ID returned by vault_list." }
	local revision = { type = "string", minLength = 1, maxLength = 100, description = "Exact revision returned by vault_read." }
	local offset = { type = "integer", minimum = 1, description = "One-based offset; preserve the returned nextOffset." }
	local limit = { type = "integer", minimum = 4, maximum = 12000, description = "Maximum bytes in a read page; the tool result budget also applies." }
	local scope = { type = "string", enum = codec.scopes }
	local place = { type = "integer", minimum = 1, maximum = 9007199254740990 }
	local project = { type = "string", minLength = 1, maxLength = 160 }
	local function options(ctx) return { aborted = ctx and ctx.aborted } end
	local function failure(why, detail)
		local result = H.fail(why); result.data = detail; return result
	end
	local function compact(document)
		return { id = document.id, title = document.title, kind = document.kind, scope = document.scope,
			placeId = document.placeId, project = document.project, status = document.status, revision = document.revision,
			readOnly = document.readOnly, updatedAt = document.updatedAt, sourceCount = #(document.sources or {}),
			hasVerification = document.verification ~= nil }
	end
	local function add(name, risk, description, properties, required, run, needs)
		tools[#tools + 1] = { name = name, group = "master_vault", risk = risk, needs = needs, description = description,
			parameters = { type = "object", properties = properties, required = required, additionalProperties = false }, run = run }
	end
	add("vault_list", "read", "Find reusable technical knowledge in the native Master Vault: bundled recipes and executor-local Markdown notes. Search is literal and case-insensitive over complete title, description, tags and body. Use scope=relevant with current place_id/project to include matching notes and global recipes. Results carry exact IDs; personal revisions appear only for unchanged retained reads. Obtain the current opaque revision from vault_read before updating or paginating a note. Follow nextOffset with the same filters, and restart after notes change. Incomplete coverage never proves absence. List returns summaries; read relevant bodies and source metadata before applying them.", {
		query = { type = "string", maxLength = 256 }, scope = { type = "string", enum = { "all", "relevant", "global", "game", "project" } },
		place_id = place, project = project, kind = { type = "string", enum = codec.kinds }, status = { type = "string", enum = codec.statuses },
		origin = { type = "string", enum = { "all", "notes", "starters" } }, offset = offset,
		limit = { type = "integer", minimum = 1, maximum = 50 },
	}, {}, function(args, ctx)
		local opts = util.copy(args); opts.placeId, opts.aborted = args.place_id, ctx and ctx.aborted
		local listed, why = vault.list(opts); if not listed then return H.fail(why) end
		local cap = H.resultBudget() - 500
		if cap < 256 then return H.fail("Increase the tool result budget to at least 756 bytes before listing vault entries") end
		local lines, rows, bytes = {}, {}, 0
		for _, item in ipairs(listed.items) do
			local row = { id = item.id, title = item.title, revision = item.revision, scope = item.scope, kind = item.kind,
				status = item.status, readOnly = item.readOnly, placeId = item.placeId, project = item.project }
			local line = item.id .. " | " .. item.title .. " [" .. item.kind .. ", " .. item.scope .. ", " .. item.status .. "]"
			if item.description ~= "" then line = line .. " — " .. util.ellipsis(item.description, 140) end
			local weight = #line + #util.encode(row) + 2
			if bytes + weight > cap then
				if #rows == 0 then return H.fail("One vault entry exceeds the result budget; increase it") end
				break
			end
			lines[#lines + 1], rows[#rows + 1], bytes = line, row, bytes + weight
		end
		local nextOffset = listed.offset + #rows <= listed.total and listed.offset + #rows or nil
		local note = listed.incomplete and "\nCoverage is incomplete; unreadable, unsupported or unscanned notes may remain." or ""
		return { text = "Master Vault" .. (#lines > 0 and "\n" .. table.concat(lines, "\n") or "\n(none)") .. note,
			data = { items = rows, offset = listed.offset, nextOffset = nextOffset, total = listed.total, count = #rows,
				incomplete = listed.incomplete, skipped = listed.skipped, scannedBytes = listed.scannedBytes,
				filesystem = listed.filesystem, noteCount = listed.noteCount, starterCount = listed.starterCount } }
	end)
	tools[#tools].examples = { { title = "Find current-game remote documentation", arguments = { query = "remote", scope = "relevant", place_id = 123 },
		note = "Replace place_id with the observed current game. Read only relevant entries; a bundled recipe contains no game-specific remote contract." } }
	local function readPage(args, ctx, exporting)
		local budget = H.resultBudget()
		if budget < 956 then return H.fail("Increase the tool result budget to at least 956 bytes before reading or exporting vault notes") end
		if (args.offset or 1) > 1 and not args.revision then return H.fail("Continuation reads require the revision from the first page") end
		local document, why, detail = vault.read(args.id, options(ctx))
		if not document then return failure(why, detail) end
		if args.revision and args.revision ~= document.revision then return H.fail("This vault note changed; restart reading at offset=1") end
		local text, label = document.content, document.title
		if exporting then
			text, why = vault.format(document); if not text then return H.fail(why) end
			label = "Markdown export " .. document.title
		elseif args.section == "metadata" then
			local data = util.copy(document); data.content = nil
			text, label = util.encode(data), "Vault metadata " .. document.title
		end
		local page = H.readSlice(label, text, args, 6000, budget - 700)
		if page.ok == false then return page end
		page.data.id, page.data.revision, page.data.status = document.id, document.revision, document.status
		page.data.readOnly, page.data.scope, page.data.placeId, page.data.project = document.readOnly, document.scope, document.placeId, document.project
		page.data.section = exporting and "markdown" or args.section or "content"
		page.data.noteBytes, page.data.sourceCount, page.data.hasVerification = #document.content, #document.sources, document.verification ~= nil
		return page
	end
	add("vault_read", "read", "Read a relevant Master Vault note as historical reference data. Default section=content reads the Markdown body; section=metadata reads complete source references, scope and attributed verification evidence. Both paginate on UTF-8 byte boundaries. Preserve revision with every continuation; changed notes reject continuation. Cite exact IDs and sources, revalidate game facts, and treat verified as the recorded evidence claim rather than automatic proof of native behavior.", {
		id = id, section = { type = "string", enum = { "content", "metadata" } }, offset = offset, limit = limit, revision = revision,
	}, { "id" }, function(args, ctx) return readPage(args, ctx, false) end)
	local documentFields = { id = id, title = { type = "string", minLength = 1, maxLength = 160 },
		description = { type = "string", maxLength = 500 }, kind = { type = "string", enum = codec.kinds }, scope = scope,
		place_id = place, project = project, status = { type = "string", enum = codec.statuses },
		tags = { type = "array", maxItems = 12, items = { type = "string", minLength = 1, maxLength = 40 } },
		sources = { type = "array", maxItems = 8, items = { type = "object", properties = {
			label = { type = "string", minLength = 1, maxLength = 160 }, url = { type = "string", maxLength = 500 },
		}, required = { "label" }, additionalProperties = false } },
		verification = { type = "string", maxLength = 4000 }, content = { type = "string", minLength = 1, maxLength = codec.MAX_CONTENT } }
	add("vault_save", "write", "Create or replace an executor-local technical note. Supply the complete document, preserving unrelated metadata. Omit document.id for a new note; an existing note requires expected_revision from vault_read and its unchanged retained original bytes. Bundled starters are immutable: copy their content into a new note with no id and status=draft. Game notes require place_id; project notes require project. Verified status requires attributed nonblank verification evidence. Record actual recipes, observed contracts and failure lessons without inventing game facts. Saves verify bytes; an uncertain result returns a recovery ID and must be reread before another mutation.", {
		document = { type = "object", properties = documentFields, required = { "title", "content", "kind", "scope", "status" }, additionalProperties = false },
		expected_revision = revision,
	}, { "document" }, function(args, ctx)
		local document = util.copy(args.document); document.placeId = document.place_id; document.place_id = nil
		local saved, why, detail = vault.save(document, args.expected_revision, options(ctx))
		if not saved then return failure(why, detail) end
		return { text = "Saved " .. saved.id .. " — " .. saved.title .. "\nrevision=" .. saved.revision, data = compact(saved) }
	end, { "fs" })
	tools[#tools].examples = { { title = "Save an observed fix", arguments = { document = { title = "A verified exact-edit workflow", kind = "bugfix", scope = "global",
		status = "draft", tags = { "files", "conflicts" }, sources = { { label = "Current tool receipt" } }, content = "Record the exact observed failure, correction, and applicable checks here." } },
		note = "Draft status is appropriate until the actual verification evidence has been recorded." } }
	add("vault_delete", "danger", "Delete one user note using its current read revision and unchanged retained bytes. Bundled starters cannot be deleted. This performs file-only deletion and verifies absence. An uncertain outcome requires reading the returned recovery ID before another mutation; it never recursively deletes folders.", {
		id = id, expected_revision = revision,
	}, { "id", "expected_revision" }, function(args, ctx)
		local ok, why, detail = vault.delete(args.id, args.expected_revision, options(ctx))
		if not ok then return failure(why, detail) end
		return { text = "Deleted " .. args.id, data = { id = args.id, deleted = true } }
	end, { "fs" })
	add("vault_import", "write", "Import supplied Markdown into a new user note. Accepts ordinary Markdown or the documented Master Vault frontmatter subset, at most 80000 bytes. It never fetches a URL, loads code, installs packages or overwrites an existing note. Optional title/scope fields replace imported metadata. Imported verification remains an attributed assertion, not a test performed by this client. Inspect content before requesting import; save verifies the resulting file.", {
		markdown = { type = "string", minLength = 1, maxLength = codec.MAX_FILE }, title = { type = "string", minLength = 1, maxLength = 160 },
		scope = scope, place_id = place, project = project,
	}, { "markdown" }, function(args, ctx)
		local document, why = vault.parse(args.markdown); if not document then return H.fail(why) end
		if args.title then document.title = args.title end
		if args.scope then document.scope = args.scope end
		if args.place_id then document.placeId = args.place_id end
		if args.project then document.project = args.project end
		local saved, err, detail = vault.save(document, nil, options(ctx))
		if not saved then return failure(err, detail) end
		return { text = "Imported " .. saved.id .. " — " .. saved.title .. "\nrevision=" .. saved.revision, data = compact(saved) }
	end, { "fs" })
	add("vault_export", "read", "Read a portable Markdown export containing a note's supported frontmatter, source references, verification evidence and exact body. Export is paged text, creates no file and sends no HTTP. Preserve revision on continuation; review personal note contents before sharing. Executor notes and bundled starters can both be exported, and runtime IDs are excluded from the portable file.", {
		id = id, offset = offset, limit = limit, revision = revision,
	}, { "id" }, function(args, ctx) return readPage(args, ctx, true) end)
	return tools
end
