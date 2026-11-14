-- Durable knowledge, conflict guards and native-outcome recovery against the offline filesystem.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Master Vault runtime")
local check, case = suite.check, suite.case
local function note(title, content, extra)
	local value = { title = title, content = content or "Observed result", kind = "recipe", scope = "global", status = "draft",
		tags = { "fixture" }, sources = { { label = "Offline fixture" } } }
	for key, item in pairs(extra or {}) do value[key] = item end
	return value
end
local function storedPath(id) return "UAI/vault/notes/" .. assert(id:match("^note:(.+)$")) .. ".md" end
case("portable Markdown preserves Unicode and exact body bytes", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local value = note("界 note", "# Exact body\r\n界\r\n\tline\r\n", { scope = "game", placeId = 123, status = "verified",
		verification = "Fixture author: checked the retained text bytes.", description = "Quoted \"text\"", tags = { "界", "source" } })
	local markdown = assert(vault.format(value)); local restored = assert(vault.parse(markdown))
	check("body line endings and Unicode survive", restored.content == value.content and restored.title == value.title)
	check("scope and evidence survive", restored.placeId == 123 and restored.verification == value.verification and restored.status == "verified")
	check("canonical export round trips", vault.format(restored) == markdown)
	check("ordinary Markdown imports", vault.parse("# A plain note\nBody").title == "A plain note")
	check("future versions stay unreadable", vault.parse("---\nuai_vault: 2\ntitle: Future\n---\nBody") == nil)
	check("unknown frontmatter is not silently discarded", vault.parse("---\ntitle: Name\nunsupported: value\n---\nBody") == nil)
	check("JSON objects cannot masquerade as empty arrays", vault.parse("---\ntitle: Name\ntags: {}\n---\nBody") == nil)
	check("verified needs evidence", vault.format(note("No evidence", "Body", { status = "verified" })) == nil)
	check("invalid UTF-8 and NUL are refused", vault.parse("# Bad\n\255") == nil and vault.parse("# Bad\n\0") == nil)
	check("oversized bodies are refused intact", vault.format(note("Large", string.rep("x", 64001))) == nil)
	f.close()
end)
case("bundled knowledge reads without a filesystem or execution", function()
	local f = F.new(); local fsx = f.env.require("runtime/fsx"); fsx.enabled = false
	local vault = f.env.require("runtime/master_vault")
	local before = #f.h.http.log
	local listed = f.run(function() return vault.list({ origin = "starters", limit = 50 }) end)
	check("substantive starter collection is available", listed.total >= 13 and not listed.incomplete)
	local defaults = f.run(function() return vault.list() end)
	check("default search initializes scope and page options", defaults.total == listed.total and defaults.offset == 1 and defaults.incomplete)
	local first = assert(vault.read(listed.items[1].id))
	check("starters retain sources and read-only identity", first.readOnly and #first.sources > 0 and first.id:find("starter:", 1, true) == 1)
	first.content, first.sources[1].label = "changed", "changed"
	check("reads are detached", vault.read(first.id).content ~= "changed" and vault.read(first.id).sources[1].label ~= "changed")
	check("writes honestly fail", vault.save(note("Unavailable")) == nil)
	check("reads made no HTTP requests", #f.h.http.log == before)
	local stats = vault.stats()
	check("availability is honest", not stats.filesystem and not stats.writable and stats.incomplete)
	f.close()
end)
case("notes survive a fresh runtime and reject stale writers", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Persistent note", "Original")) end))
	check("ordinary Markdown is stored in the vault folder", f.h.files[storedPath(saved.id)]:find("Original", 1, true) ~= nil)
	local original = f.h.files[storedPath(saved.id)]
	local read = assert(vault.read(saved.id)); read.content = "Replacement"
	check("missing revision cannot replace a note", vault.save(read) == nil and f.h.files[storedPath(saved.id)] == original)
	local updated = assert(f.run(function() return vault.save(read, saved.revision) end))
	check("verified replacement advances revision", updated.revision ~= saved.revision and vault.read(saved.id).content == "Replacement")
	check("old revision cannot replace newer work", vault.save(read, saved.revision) == nil)
	local fresh = F.new()
	for path, body in pairs(f.h.files) do fresh.h.sandbox.writefile(path, body) end
	local restored = assert(fresh.env.require("runtime/master_vault").read(saved.id))
	check("cold runtime reads stored note with a fresh local revision", restored.content == "Replacement" and restored.revision ~= updated.revision)
	fresh.close(); f.close()
end)
case("scoped literal search and pagination cover full note bodies", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local definitions = {
		note("scope fixture global", "global"),
		note("scope fixture game", "game", { scope = "game", placeId = 123 }),
		note("scope fixture other", "other", { scope = "game", placeId = 456 }),
		note("scope fixture project", "project", { scope = "project", project = "Helper" }),
		note("scope fixture long", string.rep("x", 20000) .. "late-literal-[x]", { status = "outdated" }),
	}
	for _, value in ipairs(definitions) do assert(f.run(function() return vault.save(value) end)) end
	local seen, offset = {}, 1
	repeat
		local page = f.run(function() return vault.list({ query = "scope fixture", scope = "relevant", placeId = 123, project = "Helper", offset = offset, limit = 1 }) end)
		check("one matching entry per page", #page.items == 1 and not seen[page.items[1].id])
		seen[page.items[1].id], offset = true, page.nextOffset
		check("unrelated game stays excluded", page.items[1].placeId ~= 456)
	until not offset
	local total = 0; for _ in pairs(seen) do total = total + 1 end
	check("global, game and project notes combine", total == 4)
	local late = f.run(function() return vault.list({ query = "late-literal-[x]", origin = "notes" }) end)
	check("body search reaches beyond 16 KiB and treats symbols literally", late.total == 1 and late.items[1].status == "outdated")
	check("list excludes full bodies", late.items[1].content == nil and late.items[1].sources == nil)
	check("invalid relevant scope is refused", vault.list({ scope = "relevant", project = "" }) == nil)
	f.close()
end)
case("unsupported and ambiguous files disclose incomplete coverage", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local body = assert(vault.format(note("Manual file")))
	f.h.sandbox.makefolder("UAI/vault/notes")
	f.h.sandbox.writefile("UAI/vault/notes/manual.md", body)
	f.h.sandbox.writefile("UAI/vault/notes/corrupt.md", "---\nuai_vault: 9\n---\nUnknown")
	f.h.sandbox.writefile("UAI/vault/notes/Case.md", body)
	f.h.sandbox.writefile("UAI/vault/notes/case.md", body)
	f.h.sandbox.writefile("UAI/vault/notes/nested/note.md", body)
	local listed = f.run(function() return vault.list({ origin = "notes", limit = 50 }) end)
	check("usable note remains available", listed.total == 1 and listed.items[1].id == "note:manual")
	check("omissions are explicit", listed.incomplete and listed.skipped >= 1)
	check("path traversal and hidden names are refused", vault.read("note:../config") == nil and vault.read("note:.hidden") == nil)
	check("incomplete inventory prevents unsafe capacity admission", f.run(function() return vault.save(note("New")) end) == nil)
	f.close()
end)
case("revision collisions cannot overwrite externally changed bytes", function()
	local f = F.new(); local codec = f.env.require("runtime/vault_document"); codec.revision = function() return "collision" end
	local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Collision", "original-body")) end))
	local read = assert(vault.read(saved.id)); read.content = "my-draft"
	f.h.files[storedPath(saved.id)] = f.h.files[storedPath(saved.id)]:gsub("original%-body", "external-body")
	local result, why = vault.save(read, saved.revision)
	check("full-byte guard detects a same-revision change", result == nil and why:find("changed", 1, true) and f.h.files[storedPath(saved.id)]:find("external-body", 1, true))
	f.close()
end)
case("a second reader cannot reauthorize a colliding stale revision", function()
	local f = F.new(); local codec = f.env.require("runtime/vault_document"); codec.revision = function() return "collision" end
	local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Two readers", "original-body")) end))
	local first = assert(vault.read(saved.id)); first.content = "first-reader-draft"
	f.h.files[storedPath(saved.id)] = f.h.files[storedPath(saved.id)]:gsub("original%-body", "external-body")
	local external = f.h.files[storedPath(saved.id)]
	local listed = f.run(function() return vault.list({ origin = "notes" }) end)
	check("discovery omits a revision for unreviewed changed bytes", listed.items[1].revision == nil)
	local second = assert(vault.read(saved.id))
	check("changed observations get distinct opaque tokens", first.revision ~= second.revision)
	check("unchanged rereads retain their continuation token", vault.read(saved.id).revision == second.revision)
	check("stale writer cannot replace the second reader's bytes", vault.save(first, first.revision) == nil and f.h.files[storedPath(saved.id)] == external)
	check("stale deletion cannot remove the second reader's bytes", not vault.delete(first.id, first.revision) and f.h.files[storedPath(saved.id)] == external)
	second.content = "second-reader-reviewed"
	check("the reviewed reader can explicitly save", vault.save(second, second.revision) ~= nil)
	f.close()
end)
case("retained original eviction requires a fresh read token", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local body = assert(vault.format(note("Retention fixture")))
	f.h.sandbox.makefolder("UAI/vault/notes")
	for index = 1, 65 do f.h.sandbox.writefile("UAI/vault/notes/r" .. index .. ".md", body) end
	local first = assert(vault.read("note:r1")); first.content = "retained draft"
	for index = 2, 65 do assert(vault.read("note:r" .. index)) end
	check("evicted baselines cannot authorize writes", vault.save(first, first.revision) == nil and f.h.files[storedPath(first.id)] == body)
	local reviewed = assert(vault.read(first.id))
	check("a new observation never revives the old token", reviewed.revision ~= first.revision)
	check("unchanged reviewed bytes permit the retained draft", vault.save(first, reviewed.revision) ~= nil)
	f.close()
end)
case("a fresh runtime cannot revive tokens even when a host repeats its GUID", function()
	local f = F.new(); local fresh = F.new()
	local function reusedGuid() return "00000000-0000-4000-8000-000000000001" end
	f.env.hs.GenerateGUID, fresh.env.hs.GenerateGUID = reusedGuid, reusedGuid
	f.env.require("runtime/vault_document").revision = function() return "collision" end
	fresh.env.require("runtime/vault_document").revision = function() return "collision" end
	local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Runtime token", "original")) end))
	local old = assert(vault.read(saved.id)); old.content = "old-runtime-draft"
	fresh.h.sandbox.writefile(storedPath(saved.id), f.h.files[storedPath(saved.id)])
	local currentVault = fresh.env.require("runtime/master_vault"); local current = assert(currentVault.read(saved.id))
	check("repeated host GUIDs do not duplicate observation identity", current.revision ~= old.revision)
	check("a transcript's old token cannot authorize a current write", currentVault.save(old, old.revision) == nil)
	fresh.close(); f.close()
end)
case("uncertain creates expose a recoverable identity and verified absence", function()
	local f = F.new(); local caps = f.env.require("runtime/caps"); local base = caps.fn.writefile
	local vault = f.env.require("runtime/master_vault")
	caps.fn.writefile = function(path, content)
		if path:find("/vault/notes/", 1, true) then return true end
		return base(path, content)
	end
	local saved, why, detail = f.run(function() return vault.save(note("Unconfirmed create")) end)
	check("unconfirmed save returns ID without claiming success", saved == nil and why and detail and detail.uncertain and detail.id:find("note:", 1, true) == 1)
	local missing, _, reviewed = vault.read(detail.id)
	check("absence has structured evidence", missing == nil and reviewed and reviewed.missing and reviewed.id == detail.id)
	caps.fn.writefile = base
	check("a new save can proceed after reviewed absence", f.run(function() return vault.save(note("Explicit new save")) end) ~= nil)
	f.close()
end)
case("unknown updates retain the draft and require a current read", function()
	local f = F.new(); local caps = f.env.require("runtime/caps"); local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Unknown update", "original")) end))
	local read = assert(vault.read(saved.id)); read.content = "draft-text"
	local baseWrite, baseRead, failRead = caps.fn.writefile, caps.fn.readfile, false
	caps.fn.writefile = function(path, content) local result = baseWrite(path, content); failRead = true; return result end
	caps.fn.readfile = function(path)
		if failRead then failRead = false; error("payload-bearing host error") end
		return baseRead(path)
	end
	local updated, why, detail = f.run(function() return vault.save(read, saved.revision) end)
	check("a lost verification is uncertain", updated == nil and detail.uncertain and detail.id == saved.id)
	check("raw host errors stay out of the public failure", not why:find("payload-bearing", 1, true))
	check("unreviewed retries are refused", vault.save(read, saved.revision) == nil)
	caps.fn.writefile, caps.fn.readfile = baseWrite, baseRead
	local current = assert(vault.read(saved.id))
	check("reread establishes the actual write outcome", current.content == "draft-text")
	current.content = "reviewed-next"
	check("reviewed revision permits an explicit next save", vault.save(current, current.revision) ~= nil)
	f.close()
end)
case("concurrent mutations serialize while native work yields", function()
	local f = F.new(); local caps = f.env.require("runtime/caps"); local vault = f.env.require("runtime/master_vault")
	local base, first = caps.fn.writefile, nil
	caps.fn.writefile = function(path, content)
		if path:find("/vault/notes/", 1, true) then f.h.sched.wait(0.05) end
		return base(path, content)
	end
	f.h.sched.spawn(function() first = { vault.save(note("First native write")) } end)
	f.h.sched.advance(0.01)
	check("native save owns mutation admission", vault.isBusy())
	local second, why = vault.save(note("Second native write"))
	check("a concurrent writer is refused", second == nil and why:find("already in progress", 1, true))
	f.h.sched.advance(0.1)
	check("ownership ends only after native completion", first and first[1] and not vault.isBusy())
	f.close()
end)
case("recovery reads wait for pending native write outcomes", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Pending recovery", "original")) end))
	local draft = assert(vault.read(saved.id)); draft.content = "pending draft"
	local caps = f.env.require("runtime/caps"); local baseWrite, outcome = caps.fn.writefile, nil
	caps.fn.writefile = function(path, content)
		if path == storedPath(saved.id) then f.h.sched.wait(0.05); return false end
		return baseWrite(path, content)
	end
	f.h.sched.spawn(function() outcome = { vault.save(draft, draft.revision) } end)
	f.h.sched.advance(0.01)
	local current, why = vault.read(saved.id)
	check("a pending native write cannot be reviewed prematurely", vault.isBusy() and current == nil and why:find("in progress", 1, true))
	f.h.sched.advance(0.1)
	check("the final refusal remains uncertain", outcome and outcome[1] == nil and outcome[3] and outcome[3].uncertain)
	local retry, _, detail = vault.save(draft, draft.revision)
	check("premature recovery did not authorize a retry", retry == nil and detail and detail.uncertain)
	caps.fn.writefile = baseWrite
	local reviewed = assert(vault.read(saved.id)); reviewed.content = "reviewed draft"
	check("a post-operation read permits an explicit retry", vault.save(reviewed, reviewed.revision) ~= nil)
	f.close()
end)
case("a yielded read cannot retain a snapshot across a mutation", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Overlapping read", "original")) end))
	local caps = f.env.require("runtime/caps"); local baseRead, delay, outcome = caps.fn.readfile, true, nil
	caps.fn.readfile = function(path)
		if path == storedPath(saved.id) and delay then
			delay = false; local snapshot = baseRead(path); f.h.sched.wait(0.05); return snapshot
		end
		return baseRead(path)
	end
	f.h.sched.spawn(function() outcome = { vault.read(saved.id) } end)
	f.h.sched.advance(0.01)
	saved.content = "current version"
	assert(vault.save(saved, saved.revision))
	f.h.sched.advance(0.1)
	check("overlapping reads fail without retaining stale source", outcome and outcome[1] == nil and outcome[2]:find("overlapped", 1, true))
	check("a fresh read sees the confirmed replacement", vault.read(saved.id).content == "current version")
	f.close()
end)
case("cancellation preserves observed effects without publishing success", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	check("early cancellation makes no writes", vault.save(note("Early stop"), nil, { aborted = function() return true end }) == nil)
	local caps, stopped = f.env.require("runtime/caps"), false
	local base = caps.fn.writefile
	caps.fn.writefile = function(path, content) local result = base(path, content); stopped = true; return result end
	local saved, _, detail = f.run(function() return vault.save(note("Late stop", "applied"), nil, { aborted = function() return stopped end }) end)
	check("late stop returns a recovery ID", saved == nil and detail and detail.uncertain)
	check("the real effect remains inspectable", vault.read(detail.id).content == "applied")
	f.close()
end)
case("deletion checks current bytes and remains file-only", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local saved = assert(f.run(function() return vault.save(note("Delete fixture")) end))
	check("stale deletion preserves the file", not vault.delete(saved.id, "wrong") and f.h.files[storedPath(saved.id)] ~= nil)
	local caps = f.env.require("runtime/caps"); caps.fn.delfolder = function() error("must not recursively delete") end
	check("valid deletion succeeds and verifies absence", vault.delete(saved.id, saved.revision) and f.h.files[storedPath(saved.id)] == nil)
	check("bundled reference cannot be removed", not vault.delete("starter:project-knowledge", "wrong"))
	f.close()
end)
case("scan and retention bounds disclose what was not read", function()
	local f = F.new(); local vault = f.env.require("runtime/master_vault")
	local body = assert(vault.format(note("Capacity fixture")))
	f.h.sandbox.makefolder("UAI/vault/notes")
	for index = 1, 257 do f.h.sandbox.writefile("UAI/vault/notes/n" .. index .. ".md", body) end
	local listed = f.run(function() return vault.list({ origin = "notes", limit = 50 }) end, 2)
	check("only bounded notes are scanned", listed.noteCount == 256 and listed.incomplete)
	check("capacity does not silently evict user notes", f.run(function() return vault.save(note("Overflow")) end, 2) == nil and f.h.files["UAI/vault/notes/n1.md"] == body)
	f.close()
end)
suite.finish()
