-- Persisted host policy must survive restore without silently broadening tools.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local h = envMock.new({ context = { ui = false, reuse = true } })
local uai = assert(h.boot())
local sessions = uai.sessions
for _, opts in ipairs({ { title = 1 }, { maxTurns = 1.5 }, { budgetSeconds = 0 }, { depth = -1 },
	{ stream = "false" }, { ephemeral = 1 }, { activate = "false" }, { headless = 1 }, { unlimited = 1 },
	{ toolFilter = { "host_read" } }, { toolGroups = { host = "yes" } }, { toolExclude = { [""] = true } },
	{ maxTurns = math.huge }, { depth = 0 / 0 } }) do
	local before = #sessions.list()
	local session, why = sessions.newThread(opts)
	check("invalid options rejected without registering a conversation", session == nil and type(why) == "string" and #sessions.list() == before)
end
local options = { title = "Restricted host", toolFilter = { host_read = true, host_write = false },
	toolGroups = { host = true }, toolExclude = { host_delete = true }, maxTurns = 3, budgetSeconds = 12.5,
	unlimited = false, stream = false }
local original = assert(sessions.open("host-policy", options))
options.toolFilter.host_write, options.toolGroups.host, options.toolExclude.host_delete = true, false, false
check("constructor detaches policy from caller options", original.toolFilter.host_write == false and original.toolGroups.host and original.toolExclude.host_delete)
original.ctx.pushUser("Retained restricted history")
assert(sessions.persist(original))
local path = "UAI/sessions/host-policy.json"
local stored = h.json.decode(h.files[path])
check("saved policy explicitly versions restrictions and preferences", stored.policy.version == 1 and stored.policy.toolFilter.host_read and stored.policy.stream == false and stored.policy.budgetSeconds == 12.5)
local malformed = h.json.decode(h.files[path]); malformed.id = "invalid-policy"; malformed.policy.toolFilter = { "host_read" }
local future = h.json.decode(h.files[path]); future.id = "future-policy"; future.policy.version = 2
local legacy = h.json.decode(h.files[path]); legacy.id = "legacy-policy"; legacy.policy = nil
h.files["UAI/sessions/invalid-policy.json"] = h.json.encode(malformed)
h.files["UAI/sessions/future-policy.json"] = h.json.encode(future)
h.files["UAI/sessions/legacy-policy.json"] = h.json.encode(legacy)
local invalidBytes, futureBytes = h.files["UAI/sessions/invalid-policy.json"], h.files["UAI/sessions/future-policy.json"]
uai.unload(); h.settle(0.2)
local restored = assert(h.boot()); sessions = restored.sessions
local current = assert(sessions.get("host-policy"))
check("restored host restrictions and work budgets are retained", current.toolFilter.host_read and current.toolFilter.host_write == false
	and current.toolGroups.host and current.toolExclude.host_delete and current.maxTurns == 3 and current.budgetSeconds == 12.5 and current.stream == false and not current.unlimited)
check("restored policy accompanies the original history", current.ctx.last("user").content == "Retained restricted history")
local same, created = sessions.open("host-policy", { toolFilter = {} })
check("open cannot silently replace a restored policy", same == current and not created and same.toolFilter.host_read)
check("invalid and future policies are not restored unrestricted", sessions.get("invalid-policy") == nil and sessions.get("future-policy") == nil)
check("unloaded saved identities cannot be overwritten by open", sessions.open("future-policy") == nil and sessions.newThread({ id = "invalid-policy" }) == nil)
check("skipped policy files retain their exact contents", h.files["UAI/sessions/invalid-policy.json"] == invalidBytes and h.files["UAI/sessions/future-policy.json"] == futureBytes)
check("legacy saves remain readable with legacy defaults", sessions.get("legacy-policy") and sessions.get("legacy-policy").toolFilter == nil)

-- Fill the in-memory window at one timestamp. A lexically late stable ID must
-- not evict itself while opening in the background.
for index = 1, 70 do
	local opened = assert(sessions.open(string.format("bounded-%03d", index)))
	check("new background conversation remains registered after trimming", sessions.get(opened.id) == opened and not opened.removed)
end
local last = assert(sessions.open("zz-host-background"))
check("thread trimming protects the just-created background session", sessions.get(last.id) == last and #sessions.list() <= sessions.limits.threads)
restored.unload(); h.settle(0.5)
check("policy scenarios leave no asynchronous errors", #h.errors() == 0)
print("Embedding sessions: " .. passed .. " checks passed")
