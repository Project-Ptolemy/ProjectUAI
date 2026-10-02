-- File/script authoring tools in the existing Code workspace permission group.
return function(env)
	local project = env.require("runtime/script_project")
	local patch = env.require("runtime/project_patch")
	local source = env.require("runtime/project_source")
	local fs = env.require("runtime/fsx")
	local util = env.require("runtime/util")
	local N = env.require("tools/native_helpers")
	local H = env.require("tools/helpers")
	local execution = env.require("tools/execution")
	local testing = env.require("tools/project_testing")
	local tools, scope = {}, { scope = "files" }
	local str = { type = "string", minLength = 1, maxLength = 220 }
	local function add(name, risk, description, properties, required, run, prepare, needs)
		local tool = N.add(tools, name, risk, description, properties, required, run, prepare)
		tool.needs = needs or { "fs" }
		return tool
	end
	local function result(value, why) return value and N.result(value, why or value.status or "Completed") or N.fail(why) end
	local function bindPatch(args, ctx) return patch.get(args.patch_id, ctx) end
	local function draftGuard(plan)
		local files, store = env.require("runtime/code_files"), env.require("runtime/code_store")
		for _, item in ipairs(plan.items) do
			for id, binding in pairs(files.bindings) do
				if binding.path:lower() == ("files/" .. item.path):lower() then
					local doc = store.resolve(id)
					if doc and doc.source ~= binding.base then return false, "Unsaved Code draft exists for files/" .. item.path .. "; save or edit that document first" end
				end
			end
		end
		return true
	end
	local function load(args, ctx) return project.load(args.manifest, ctx) end
	local function ready(value)
		local analysis = project.analyze(value)
		if not analysis.compilerAvailable then return nil, "This host has no source compiler" end
		if not analysis.ok then return nil, "Project has syntax/dependency errors; inspect script_analyze" end
		return analysis
	end
	add("project_map", "read", "Read a version-1 project manifest and return file hashes, lexical function/local outlines and literal require dependencies without full source. Modules map IDs to relative .lua/.luau files; entry names an ID; tests is an optional array of test IDs. Use project_scaffold for a working example. Lexical hints are not type analysis.",
		{ manifest = str }, { "manifest" }, function(args, ctx)
			local value, why = load(args, ctx); if not value then return N.fail(why) end
			local items = {}
			for _, id in ipairs(value.ids) do
				local item = value.modules[id]; local row = util.copy(item.outline)
				row.id, row.path = id, "files/" .. item.path; items[#items + 1] = row
			end
			return result({ manifest = "files/" .. value.manifest, manifestHash = source.hash(value.manifestSource), entry = value.entry,
				tests = value.tests, bytes = value.bytes, items = items, source = "saved files; unsaved Code drafts are separate" }, "Project source map; hashes identify saved versions")
		end)
	add("project_patch", "write", "Stage 1-20 coordinated file creates/replacements/exact edits without writing files. Existing targets require expected_hash from project_map or script_analyze; new targets require create=true. Review with project_patch_read, then apply. Proposals/checkpoints are conversation-owned, expire in ten minutes and do not persist across unload.",
		{ operations = { type = "array", minItems = 1, maxItems = 20, items = { type = "object", properties = {
			path = str, create = { type = "boolean" }, expected_hash = str,
			content = { type = "string", maxLength = 256000 },
			edits = { type = "array", minItems = 1, maxItems = 20, items = { type = "object", properties = {
				old_text = { type = "string", minLength = 1, maxLength = 256000 }, new_text = { type = "string", maxLength = 256000 },
			}, required = { "old_text", "new_text" } } },
		}, required = { "path" } } } }, { "operations" }, function(args, ctx)
			local plan, why = patch.stage(args.operations, ctx)
			return plan and result(patch.describe(plan), "Staged proposal; inspect before applying") or N.fail(why)
		end)
	add("project_patch_read", "read", "Read a staged file's before/after source or a bounded line diff. Without path, list proposal metadata. Follow source continuation offsets or retained workspace_result_read fields. Reading never applies a proposal.",
		{ patch_id = str, path = str, section = { type = "string", enum = { "before", "after", "diff" } }, offset = { type = "integer", minimum = 1 }, limit = { type = "integer", minimum = 100, maximum = 6000 } }, { "patch_id" }, function(args, ctx)
			local plan, why = patch.get(args.patch_id, ctx); if not plan then return N.fail(why) end
			if not args.path then return result(patch.describe(plan)) end
			local path, pathErr = project.path(args.path); if not path then return N.fail(pathErr) end
			for _, item in ipairs(plan.items) do
				if item.path == path then
					if args.section == "diff" then
						local diff = env.require("runtime/code_diff").compare(item.before or "", item.after)
						local rows = {}; local offset = args.offset or 1
						for i = offset, math.min(#diff.rows, offset + 19) do rows[#rows + 1] = diff.rows[i] end
						return result({ rows = rows, added = diff.added, removed = diff.removed, replacement = diff.replacement,
							nextOffset = offset + #rows <= #diff.rows and offset + #rows or nil }, "Diff rows; offset counts rows")
					end
					return H.readSlice("files/" .. path .. " (" .. (args.section or "after") .. ")", args.section == "before" and (item.before or "") or item.after, args, 3500)
				end
			end
			return N.fail("Path is not in this proposal")
		end)
	add("project_patch_apply", "write", "Apply the exact staged proposal after all file versions and unsaved editor drafts are checked. Writes are verified one by one, not filesystem-atomic. Partial failures retain original and proposed source for conditional recovery; inspect results before continuing.",
		{ patch_id = str }, { "patch_id" }, function(args, ctx, prepared)
			local plan, why = patch.get(args.patch_id, ctx); if not plan or plan ~= prepared then return N.fail(why or "Proposal changed") end
			local value, err = patch.apply(plan, ctx, draftGuard); return result(value, err)
		end, bindPatch)
	add("project_patch_restore", "danger", "Restore an applied checkpoint only while files still match its recorded versions. Removes files that checkpoint created. Refuses external changes and unverified partial bytes; never claims to undo executed scripts or game effects.",
		{ patch_id = str }, { "patch_id" }, function(args, ctx, prepared)
			local plan, why = patch.get(args.patch_id, ctx); if not plan or plan ~= prepared then return N.fail(why or "Checkpoint changed") end
			local value, err = patch.restore(plan, ctx, draftGuard); return result(value, err)
		end, bindPatch)
	add("project_patch_discard", "write", "Release a staged proposal or recovery checkpoint. Does not change files; discarded recovery source is no longer available.",
		{ patch_id = str }, { "patch_id" }, function(args, ctx) local value, why = patch.discard(args.patch_id, ctx); return result(value, why) end)
	add("project_scaffold", "write", "Stage a working modular script project: uai.project.json, main.lua, settings.lua and tests/settings.lua. All destinations must be new. Returns a proposal for review/apply; nothing runs. Generated require uses declared project IDs. Add interfaces through Project UAI UI LIB.",
		{ directory = str }, { "directory" }, function(args, ctx)
			local directory, why = project.path(args.directory); if not directory then return N.fail(why) end
			local manifest = util.encode({ version = 1, entry = "main", modules = { main = "main.lua", settings = "settings.lua", ["tests/settings"] = "tests/settings.lua" }, tests = { "tests/settings" } })
			local files = {
				{ path = directory .. "/uai.project.json", content = manifest },
				{ path = directory .. "/main.lua", content = 'local settings = require("settings")\nreturn { name = settings.name, enabled = settings.enabled }\n' },
				{ path = directory .. "/settings.lua", content = 'return { name = "My script", enabled = true }\n' },
				{ path = directory .. "/tests/settings.lua", content = 'local settings = require("settings")\nreturn {\n\tdefaults = function(t)\n\t\tt.equal(settings.name, "My script")\n\t\tt.truthy(settings.enabled)\n\tend,\n}\n' },
			}
			for _, file in ipairs(files) do file.create = true end
			local plan, err = patch.stage(files, ctx); if not plan then return N.fail(err) end
			local value = patch.describe(plan); value.manifest = "files/" .. directory .. "/uai.project.json"
			return result(value, "Staged starter project; review source, then project_patch_apply")
		end)
	add("script_analyze", "read", "Compile saved source without executing it and return hashes, lexical outlines and structured diagnostics. Supply path for one file or manifest for project-wide syntax and literal require checks. Explicitly reports compiler availability; does NOT claim Luau type checking or Roblox API validation.",
		{ path = str, manifest = str }, {}, function(args, ctx)
			if (args.path ~= nil) == (args.manifest ~= nil) then return N.fail("Provide path or manifest, not both") end
			local value, why
			if args.manifest then value, why = load(args, ctx)
			else
				local text, path = project.read(args.path); if not text then return N.fail(path) end
				local outline, err = source.scan(text, ctx); if not outline then return N.fail(err) end
				value = { ids = { "source" }, modules = { source = { source = text, path = path, outline = outline } } }
			end
			if not value then return N.fail(why) end
			-- Single-file requires lack a declared project graph; report their hints, not missing-module errors.
			local imports
			if args.path then imports = value.modules.source.outline.imports; value.modules.source.outline.imports = {} end
			local analysis = project.analyze(value)
			if args.path then analysis.path, analysis.hash, analysis.imports = "files/" .. value.modules.source.path, value.modules.source.outline.hash, imports end
			return result(analysis, string.format("%d error(s), %d warning(s); compiler %s; typeChecked=false", analysis.errors, analysis.warnings, analysis.compilerAvailable and "available" or "unavailable"))
		end)
	local testTool = add("script_test", "danger", "Run declared project test modules (tables of named functions receiving t and fixtures). t.equal, t.truthy and t.raises are provided. Fresh module cache/fixtures per case; native game state is shared. Uses managed run_luau deadlines, not a security sandbox or isolated Roblox process. Returns assertions, errors and bundle source locations. Review source before running.",
		{ manifest = str, fixtures = { type = "object" }, timeout = { type = "number", minimum = 1, maximum = 60 } }, { "manifest" }, function(args, ctx, prepared)
			if not prepared then return N.fail("Missing project snapshot") end
			local current, why = project.current(prepared); if not current then return N.fail(why) end
			local analysis, err = ready(prepared); if not analysis then return N.fail(err) end
			if #prepared.tests == 0 then return N.fail("Declare test module IDs in the manifest's tests array") end
			local fixtures, fixtureErr = testing.fixtures(args.fixtures); if not fixtures then return N.fail(fixtureErr) end
			local code, locations = project.bundle(prepared, prepared.entry, testing.program(prepared.tests)); if not code then return N.fail(locations) end
			local report
			local run = execution.run({ code = code, timeout = args.timeout, parameters = { n = 1, fixtures } }, ctx, function(value) report = value end)
			if type(report) ~= "table" then return run end
			local unchanged = project.current(prepared)
			report.ok, report.sourcesCurrent, report.locations = run.ok and report.failed == 0 and unchanged, unchanged, locations
			report.execution, report.coverage = run.data, "Managed client tests; native game state is shared; host input/rendering not validated"
			return result(report, string.format("%d passed, %d failed; source versions %s.\n%s", report.passed, report.failed, unchanged and "unchanged" or "changed during tests", run.text))
		end, load, { "fs", "exec" })
	testTool.timeout = function(args) return execution.timeout(args) + 5 end
	add("project_build", "write", "Compile/check a saved project and export one deterministic .lua bundle without running it. Module-local require resolves declared IDs only. Refuses output paths that overwrite project inputs. Existing output requires expected_hash; new output is created. Returns source line locations and a recovery checkpoint. Review inputs before building and output before tests.",
		{ manifest = str, output = str, expected_hash = str }, { "manifest", "output" }, function(args, ctx, prepared)
			if not prepared then return N.fail("Missing build snapshot") end
			local current, why = project.current(prepared); if not current then return N.fail(why) end
			local analysis, err = ready(prepared); if not analysis then return N.fail(err) end
			local output, outputErr = project.path(args.output); if not output then return N.fail(outputErr) end
			if not output:match("%.lua$") then return N.fail("Output must end in .lua") end
			if output:lower() == prepared.manifest:lower() then return N.fail("Output would overwrite the manifest") end
			for _, id in ipairs(prepared.ids) do if prepared.modules[id].path:lower() == output:lower() then return N.fail("Output would overwrite a project source") end end
			local code, locations = project.bundle(prepared, prepared.entry); if not code then return N.fail(locations) end
			if #code > source.MAX_FILE then return N.fail("Bundle exceeds the 256000-byte editable output limit; split the project") end
			local checked = execution.check(code); if not checked.ok then return checked end
			local plan, stageErr = patch.stage({ { path = "files/" .. output, content = code, create = not fs.exists(output, scope), expected_hash = args.expected_hash } }, ctx)
			if not plan then return N.fail(stageErr) end
			local value, applyErr = patch.apply(plan, ctx, function(p)
				local valid, changed = project.current(prepared); if not valid then return false, changed end
				return draftGuard(p)
			end)
			if not value then return N.fail(applyErr) end
			value.output, value.hash, value.locations, value.warnings = "files/" .. output, source.hash(code), locations, analysis.warnings
			return result(value, "Bundle " .. value.status .. "; no script executed")
		end, load, { "fs", "exec" })
	return tools
end
