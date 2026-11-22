-- Once-per-release notices use saved version identity, ready access and app lifetime.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F, envMock, luau = require("coding_fixture"), require("env"), require("luau")
local suite = F.suite("Release changelog")
local case, check = suite.case, suite.check
local MARKER = "ui.changelogAutoShownVersion"
local function fixture()
	local f = F.ui(900, 650); f.env.info.version = "4.1.1"
	f.notes, f.ui, f.config = f.env.require("runtime/changelog"), f.env.require("ui/changelog"), f.env.require("runtime/config")
	f.app = { screen = f.env.root, window = { visible = true }, startupReady = true }
	return f
end
local function card(f, version) return f.h.byName("Release_" .. (version or f.env.info.version)) end
local function close(f) f.env.require("ui/overlay").closeAll(); f.h.settle(0.3) end
local function release(version)
	return { version = version, revision = "fixture-revision", title = "Synthetic release", date = "Fixture date",
		sections = { { category = "fixed", items = { "Synthetic release note" } } } }
end

case("numeric ordering and exact current release control automatic notices", function()
	local f = fixture()
	f.notes.ENTRIES[#f.notes.ENTRIES + 1] = release("4.9.0")
	f.notes.ENTRIES[#f.notes.ENTRIES + 1] = release("4.10.0")
	local all = f.notes.all()
	check("two-digit versions sort numerically", all[1].version == "4.10.0" and all[2].version == "4.9.0")
	f.env.info.version = "4.9.0"
	check("the selector identifies this client instead of a future notes entry", f.notes.current().version == "4.9.0")
	f.ui.oncePerRelease(f.app); f.h.sched.advance(2)
	check("the automatic modal shows this release and excludes future notes", card(f, "4.9.0") ~= nil and card(f, "4.10.0") == nil
		and f.config.get(MARKER) == "4.9.0" and f.config.get("ui.lastSeenVersion") == "4.9.0")
	close(f); f.env.info.version = "4.10.0"
	f.ui.oncePerRelease(f.app); f.h.sched.advance(2)
	check("the next numeric release is shown once", card(f, "4.10.0") ~= nil and f.config.get(MARKER) == "4.10.0")
	close(f); f.env.info.version = "4.9.0"
	check("a downgrade does not repeat an older release notice", not f.notes.shouldShowAutomatically())
	f.env.info.version = "4.11.0"
	check("missing current notes cannot show another version as this release", f.notes.current() == nil and not f.notes.shouldShowAutomatically())
	f.healthy(); f.close()
end)

case("notes wait for completed startup and verified credential access", function()
	local f = fixture(); f.app.startupReady = false
	f.config.requireVault()
	f.ui.oncePerRelease(f.app); f.h.sched.advance(3)
	check("incomplete startup leaves notes and the marker untouched", card(f) == nil and f.config.get(MARKER) == "0.0.0" and f.notes.isUnread())
	f.app.startupReady = true; f.h.sched.advance(3)
	check("ready bootstrap still defers a required storage choice", card(f) == nil and f.config.get(MARKER) == "0.0.0")
	assert(f.run(function() return f.config.continueWithoutEncryption() end, 1))
	f.h.sched.advance(2)
	check("verified storage permits the pending notice", card(f) ~= nil and f.config.get(MARKER) == f.env.info.version)
	close(f); f.healthy(); f.close()
end)

case("hidden and busy windows retain a pending notice without covering work", function()
	local f = fixture(); f.app.window.visible = false
	local cancel = f.ui.oncePerRelease(f.app)
	local function absent(label)
		f.h.sched.advance(3)
		check(label, card(f) == nil and f.config.get(MARKER) == "0.0.0" and f.notes.isUnread())
	end
	absent("hidden windows do not mark notes read")
	f.app.window.visible = true; f.app.screen.Enabled = false
	absent("disabled screens do not consume the release")
	f.app.screen.Enabled = true
	local other = f.env.require("ui/overlay").modal({ title = "Unfinished connection" })
	absent("an existing form keeps its overlay")
	other.close(); f.h.settle(0.3)
	local field = f.h.Instance.new("TextBox", f.host); field:CaptureFocus()
	absent("typing keeps native focus")
	check("focus remains on the user's field", field:IsFocused())
	field:ReleaseFocus(false)
	local sessions = f.env.require("agent/session"); local busy = sessions.busyCount
	sessions.busyCount = function() return 1 end
	absent("active inference keeps its screen")
	sessions.busyCount = busy; f.h.sched.advance(2)
	check("the visible available window receives the deferred notice", card(f) ~= nil and not f.notes.shouldShowAutomatically())
	close(f); f.ui.oncePerRelease(f.app); f.h.sched.advance(3)
	check("later scheduling and execution in this release keep it closed", card(f) == nil)
	cancel(); cancel(); f.healthy(); f.close()
end)

case("manual viewing consumes the pending notice while revision markers stay independent", function()
	local f = fixture()
	f.ui.oncePerRelease(f.app)
	local modal = assert(f.ui.show()); modal.close(); f.h.sched.advance(3)
	check("manual dismissal cannot be followed by a duplicate automatic open", card(f) == nil and not f.notes.shouldShowAutomatically())
	local current = f.notes.ENTRIES[1]; current.revision = current.revision .. "-edited"
	check("revised prose restores only the menu's unread marker", f.notes.isUnread() and not f.notes.shouldShowAutomatically()
		and f.ui.menuLabel():find("What's new", 1, true))
	f.ui.oncePerRelease(f.app); f.h.sched.advance(3)
	check("a note revision does not reopen the modal", card(f) == nil)
	assert(f.ui.show()); check("manual revision review clears unread", not f.notes.isUnread())
	close(f); f.healthy(); f.close()
end)

case("cancelled and destroyed notice owners cannot open or persist a release", function()
	local f = fixture()
	local cancel = f.ui.oncePerRelease(f.app)
	local nativeCancel = f.h.sandbox.task.cancel; f.h.sandbox.task.cancel = function() end
	cancel(); cancel(); f.h.sandbox.task.cancel = nativeCancel; f.h.sched.advance(3)
	check("cooperative cancellation remains effective without host task cancellation", card(f) == nil and f.config.get(MARKER) == "0.0.0")
	f.app.window.visible = false; f.ui.oncePerRelease(f.app); f.app.screen:Destroy(); f.h.sched.advance(3)
	check("screen destruction leaves the release pending for a future client", f.config.get(MARKER) == "0.0.0" and f.notes.isUnread())
	f.healthy(); f.close()
end)

local sourceFile = assert(io.open("dist/uai.lua", "rb")); local source = sourceFile:read("*a"); sourceFile:close()
local compiled = {}
local function boot(h, context, build)
	local id = build or "current"
	if not compiled[id] then
		local body = source
		if build then body = body:gsub('local __UAI_BUILD = "[^"]+"', 'local __UAI_BUILD = "' .. build .. '"', 1) end
		compiled[id] = assert(luau.load(body, "release-notice-" .. id, { entry = true }))
	end
	setfenv(compiled[id], h.sandbox)
	local handle = assert(compiled[id](context)); h.settle(1)
	return handle
end
local function named(h, name) return h.find(h.coreGui, function(node) return node.Name == name end)[1] end
local function seed(h, protection)
	h.files["UAI/config.json"] = h.json.encode({ version = 1,
		ui = { tutorial = { seen = true }, communityInvite = { disabled = true } }, bridge = { autoDiscover = false },
		security = { rememberCredentials = true, credentialProtection = protection or "undecided" },
	})
end
local function healthy(h) check("the shipping bootstrap has no asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0) end
local function run(h, fn, ...)
	local result, args = nil, { ... }
	h.sched.spawn(function() result = { fn(unpack(args)) } end); h.sched.advance(1)
	assert(result, "release fixture storage operation did not finish")
	return unpack(result)
end
local function cheapKdf(env)
	local crypto, sha = env.require("runtime/credential_crypto"), env.require("runtime/credential_sha256")
	crypto.derive = function(password, salt, _, progress)
		if progress and progress(0, 1) == false then return nil, crypto.error end
		local key = sha.digest(password .. "\0" .. salt) .. sha.digest(salt .. "\0" .. password)
		if progress and progress(1, 1) == false then return nil, crypto.error end
		return key
	end
end

case("hidden shipping clients defer until show and persist across reuse and changed builds", function()
	local h = envMock.new(); seed(h, "unprotected")
	local context = { ui = false, reuse = true }; local handle = boot(h, context)
	h.sched.advance(3)
	check("full hidden startup leaves notes unread and pending", handle.app.startupReady and handle.config.vaultStatus().ready and not handle.app.window.visible
		and named(h, "Release_" .. handle.version) == nil and handle.config.get(MARKER) == "0.0.0")
	assert(handle.show("chat")); h.sched.advance(2)
	check("explicit SDK show presents this release", named(h, "Release_" .. handle.version) ~= nil and handle.config.get(MARKER) == handle.version)
	handle.env.require("ui/overlay").closeAll(); h.settle(0.3); assert(handle.config.saveNow())
	local reused = boot(h, context); h.sched.advance(3)
	check("same-build reuse keeps the existing prompt closed", reused == handle and named(h, "Release_" .. handle.version) == nil)
	local updated = boot(h, context, "release-notice-next-build"); h.sched.advance(3)
	check("changed-build handoff retains the displayed-release marker", updated ~= handle and updated.config.get(MARKER) == updated.version
		and named(h, "Release_" .. updated.version) == nil)
	updated.destroy(); local cold = boot(h, context); h.sched.advance(3)
	check("cold restart reads the persisted marker", cold.config.get(MARKER) == cold.version and named(h, "Release_" .. cold.version) == nil)
	healthy(h); cold.destroy()
end)

case("shipping vault challenges defer first display and never repeat a shown release", function()
	local h = envMock.new(); seed(h)
	local handle = boot(h); local password = "release fixture master passphrase"
	h.sched.advance(3)
	check("required password setup receives no release modal", named(h, "CredentialVault") ~= nil
		and named(h, "Release_" .. handle.version) == nil and handle.config.get(MARKER) == "0.0.0")
	cheapKdf(handle.env); assert(run(h, handle.config.enableVault, password)); h.sched.advance(2)
	check("verified vault setup releases the first prompt", handle.config.vaultStatus().ready
		and named(h, "Release_" .. handle.version) ~= nil and handle.config.get(MARKER) == handle.version)
	handle.env.require("ui/overlay").closeAll(); h.settle(0.3); assert(handle.config.saveNow())
	local context = { reuse = true }; local reused = boot(h, context)
	check("same-build execution requires its normal password challenge", reused == handle and not reused.config.vaultStatus().ready)
	assert(run(h, reused.config.unlockVault, password)); h.sched.advance(2)
	check("warm unlock does not repeat this release", named(h, "Release_" .. reused.version) == nil)
	local updated = boot(h, context, "release-vault-next-build"); cheapKdf(updated.env)
	check("changed-build vault handoff stays gated with its release marker", not updated.config.vaultStatus().ready and updated.config.get(MARKER) == updated.version)
	assert(run(h, updated.config.unlockVault, password)); h.sched.advance(2)
	check("handoff unlock keeps already shown notes closed", named(h, "Release_" .. updated.version) == nil)
	updated.destroy(); local cold = boot(h, context); cheapKdf(cold.env)
	assert(run(h, cold.config.unlockVault, password)); h.sched.advance(2)
	check("a cold vault unlock also keeps the persisted release closed", cold.config.get(MARKER) == cold.version and named(h, "Release_" .. cold.version) == nil)
	healthy(h); cold.destroy()
end)

suite.finish()
