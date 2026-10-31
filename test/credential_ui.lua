-- Exercise storage decisions and explicit private exports through real controls.
-- All credentials and executor files below are synthetic, held by the offline mock.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Credential storage UI")
local case, check = suite.case, suite.check

local function fixture(legacy)
	local f = F.ui(390, 700)
	f.config = f.env.require("runtime/config")
	f.util = f.env.require("runtime/util")
	local data = f.util.deepCopy(f.config.defaults)
	data.providers = { active = "private-fixture", list = { {
		id = "private-fixture", label = "Private fixture", preset = "custom", api = "openai", authStyle = "bearer",
		baseUrl = "https://credential.fixture/v1?session=fixture-url-secret", apiKey = "fixture-key-first-1111\nfixture-key-second-2222",
		model = "fixture-model", models = { "fixture-model" }, enabled = true,
		keyNames = { "First", "Second" }, keyMode = "single", selectedKey = 2,
		headers = { ["X-Custom-Access"] = "fixture-header-secret" }, query = { access = "fixture-query-secret" },
		params = { nested = { credential = "fixture-body-secret" } },
		keyRotation = { index = 1, cooldowns = { ["fixture-key-first-1111"] = 1000 } },
	} } }
	data.bridge.token, data.relay.token = "fixture-bridge-token", "fixture-relay-token"
	if legacy then data.security = nil end
	f.h.files["UAI/config.json"] = f.util.encode(data)
	f.config.load()
	f.record = f.config.get("providers.list")[1]
	return f
end

local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name))
	f.h.settle(0.3)
end

case("Privacy explains verified password migration and preserves legacy keys", function()
	local f = fixture(true)
	-- The registry supplies missing accounting IDs before the app renders panes.
	f.env.require("provider/registry").list()
	local before = f.util.encode(f.config.data)
	f.env.require("ui/settingspanes").render("privacy", f.host)
	f.h.settle(0.3)
	local status = assert(f.h.byName("CredentialStorageStatus"))
	check("password setup explains carryover after verification", status.Text:find("Set a master password", 1, true)
		and status.Text:find("carry over after storage is verified", 1, true))
	check("Privacy keeps storage changes in the explicit vault controls", f.h.byName("RememberCredentialsSwitch") == nil
		and not f.h.textOf():find("Optionally encrypt", 1, true))
	check("rendering storage settings preserves complete legacy keys", f.util.encode(f.config.data) == before
		and f.record.apiKey == "fixture-key-first-1111\nfixture-key-second-2222" and f.record.selectedKey == 2)
	check("the privacy destination list hides URL credentials", not f.h.textOf():find("fixture-url-secret", 1, true))
	check("storage explanations do not reveal keys", not f.h.textOf():find("fixture-key-", 1, true))
	f.healthy(); f.host:Destroy(); f.close()
end)

case("Project UAI keeps the stable Settings identifier and truthful identity text", function()
	local f = fixture(true)
	local panes = f.env.require("ui/settingspanes")
	local entry = assert(panes.pane("claude_code"))
	check("the existing Settings ID has the requested navigation label", entry.id == "claude_code" and entry.label == "Project UAI")
	assert(panes.render("claude_code", f.host)); f.h.settle(0.3)
	check("the pane heading uses the new label", f.h.byName("SettingsPaneTitle").Text == "Project UAI")
	assert(panes.render("developer", f.host)); f.h.settle(0.3)
	check("the transport still identifies its Claude Code protocol", f.h.textOf():find("Claude Code", 1, true) ~= nil)
	f.healthy(); f.host:Destroy(); f.close()
end)

case("key management follows the live storage preference and distinguishes request rotation", function()
	local f = fixture(true)
	local modal = assert(f.env.require("ui/providerkeys").open({ record = f.record }))
	f.h.settle(0.3)
	local status = assert(f.h.byName("KeyStorageSummary"))
	check("key manager identifies encoding and its limits", status.Text:find("byte-encoded", 1, true)
		and status.Text:find("not encryption", 1, true))
	check("request rotation is not described as revocation", f.h.textOf():find("only takes turns", 1, true)
		and f.h.textOf():find("revoke the old ones", 1, true))
	assert(f.config.setRememberCredentials(false))
	check("an open manager refreshes after the preference changes", status.Text:find("session-only", 1, true))
	check("storage status never renders the complete keys", not f.h.textOf():find("fixture-key-", 1, true))
	modal.close(); f.h.settle(0.3)
	assert(f.config.setRememberCredentials(true))
	f.healthy(); f.host:Destroy(); f.close()
end)

case("ordinary and diagnostic copies omit credentials while private copy requires its own action", function()
	local f = fixture(true)
	f.env.require("ui/settingspanes").render("import_export", f.host)
	f.h.settle(0.3)
	click(f, "CopyFullConfig")
	local ordinary = f.h.sandbox.__clipboard
	check("default copy excludes keys and alternate authentication", type(ordinary) == "string"
		and not ordinary:find("fixture-key-", 1, true) and not ordinary:find("fixture-header-secret", 1, true)
		and not ordinary:find("fixture-query-secret", 1, true) and not ordinary:find("fixture-body-secret", 1, true)
		and not ordinary:find("fixture-url-secret", 1, true))
	check("default copy excludes connection tokens", not ordinary:find("fixture-bridge-token", 1, true)
		and not ordinary:find("fixture-relay-token", 1, true))
	check("default copy declares its credential policy", f.util.decode(ordinary).credentialsIncluded == false)
	click(f, "CopyPrivateConfig")
	local private = f.h.sandbox.__clipboard
	local restoredPrivate = assert(f.env.require("runtime/config_transfer").preview(private)).config
	check("explicit private copy encodes provider credentials", not private:find("fixture-key-first-1111", 1, true)
		and not private:find("fixture-header-secret", 1, true) and not private:find("fixture-query-secret", 1, true)
		and not private:find("fixture-body-secret", 1, true) and not private:find("fixture-url-secret", 1, true)
		and f.util.decode(private).credentialsIncluded == true)
	check("private copy restores exact provider credentials and retains connection tokens", restoredPrivate.providers.list[1].apiKey == f.record.apiKey
		and restoredPrivate.providers.list[1].headers["X-Custom-Access"] == "fixture-header-secret"
		and restoredPrivate.bridge.token == "fixture-bridge-token" and restoredPrivate.relay.token == "fixture-relay-token")
	click(f, "ExportClipboard")
	local diagnostic = f.h.sandbox.__clipboard
	check("diagnostic export uses the same credential exclusions", not diagnostic:find("fixture-key-", 1, true)
		and not diagnostic:find("fixture-header-secret", 1, true) and not diagnostic:find("fixture-query-secret", 1, true)
		and not diagnostic:find("fixture-body-secret", 1, true) and not diagnostic:find("fixture-relay-token", 1, true))
	click(f, "PasteFullConfig")
	local field = assert(f.h.byName("ConfigImportJSON")):FindFirstChildWhichIsA("TextBox")
	f.h.type(field, ordinary)
	click(f, "ReviewConfigImport")
	local preview = assert(f.h.byName("ConfigImportStatus"))
	check("import explicitly warns that missing credentials require re-entry", preview.Text:find("Credentials excluded", 1, true)
		and preview.Text:find("enter your credentials again", 1, true))
	check("import reports this device's storage setting", preview.Text:find("byte encoding", 1, true))
	check("copying and previewing never change current credentials", f.record.apiKey == "fixture-key-first-1111\nfixture-key-second-2222")
	f.healthy(); f.host:Destroy(); f.close()
end)

case("omitted authentication needs an explicit full connection review after key entry", function()
	local f = fixture(true)
	assert(f.config.setRememberCredentials(false))
	f.config.load()
	f.record = f.config.get("providers.list")[1]
	local registry = f.env.require("provider/registry")
	local panel = f.env.require("ui/panels/providers")
	check("reload retains the omitted credential guard", f.record.credentialsOmitted == true and f.record.apiKey == "")
	assert(panel.manageKeys(f.record))
	f.h.settle(0.3)
	check("key manager explains the connection review step", f.h.byName("KeyRestorationRequired") ~= nil)
	click(f, "AddKey")
	f.h.type(assert(f.h.byName("PromptField")):FindFirstChildWhichIsA("TextBox"), "fixture-restored-3333")
	f.h.settle(0.3)
	-- Add supports multiline input, so confirm using its named action label.
	local overlay = f.env.require("ui/overlay")
	if f.h.byName("PromptField") then
		local prompt = overlay.open[#overlay.open]
		for _, node in ipairs(prompt.footer:GetDescendants()) do
			if node.ClassName == "TextLabel" and node.Text == "Save key" then
				local button = node.Parent
				while button and not button:IsA("TextButton") do button = button.Parent end
				f.h.click(assert(button)); break
			end
		end
		f.h.settle(0.3)
	end
	click(f, "ApplyKeys")
	local updated = assert(registry.get(f.record.id))
	check("adding a key preserves the guard for omitted custom authentication", updated.apiKey == "fixture-restored-3333"
		and updated.credentialsOmitted == true and registry.protocolProblem(updated) ~= nil)
	panel.editor(updated)
	f.h.settle(0.3)
	check("full editor explains what its Save confirms", f.h.byName("RestoreProviderCredentials") ~= nil)
	click(f, "SaveProvider")
	check("explicit connection Save enables the reviewed configuration", registry.get(updated.id).credentialsOmitted ~= true
		and registry.protocolProblem(registry.get(updated.id)) == nil)
	f.healthy(); f.host:Destroy(); f.close()
end)

local function bootStored(publicOnly, failMigration)
	local f = fixture(true)
	local data = f.util.deepCopy(f.config.data)
	data.security = nil
	data.ui.tutorial.seen, data.ui.communityInvite.disabled = true, true
	data.agent.autoFreeRouting = false
	if publicOnly then
		local record = f.env.require("provider/registry").blank("projectuai-free")
		record.id = "community-fixture"
		data.providers = { active = record.id, list = { record } }
		data.security = { rememberCredentials = true }
	end
	local encoded = f.util.encode(data)
	f.host:Destroy(); f.close()
	local h = require("env").new()
	h.files["UAI/config.json"] = encoded
	if failMigration then h.sandbox.writefile = function() error("fixture-write-refused") end end
	local handle = assert(h.boot("dist/uai.lua"))
	h.settle(1)
	return h, handle
end

case("existing and community-only configurations both require password setup", function()
	for _, publicOnly in ipairs({ false, true }) do
		local h, handle = bootStored(publicOnly)
		local function find(name) return h.byName(name, h.coreGui) end
		local description = assert(find("VaultDescription"))
		check("startup requires a master password before opening the app", find("VaultHeading").Text == "Set a master password"
			and handle.config.vaultStatus().required and not handle.config.vaultStatus().ready and not handle.app.window.visible)
		check("startup describes verified migration without revealing keys", description.Text:find("existing keys", 1, true)
			and not h.textOf(handle.app.screen):find("fixture-key-first-1111", 1, true))
		h.click(assert(find("VaultCancel"))); h.press("Escape"); h.settle(0.4)
		handle.app.mount(); handle.app.rebuild("credential setup fixture"); h.settle(0.5)
		check("cancelling and rebuilding retain one required setup", #h.allByName("CredentialVault", h.coreGui) == 1
			and not handle.app.window.visible and not handle.app.launcher.Visible)
		check("required startup stays healthy", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
		handle.destroy(); h.settle(0.3)
	end
end)

case("failed password migration retains the gate and the loaded legacy keys", function()
	local h, handle = bootStored(false, true)
	local function find(name) return h.byName(name, h.coreGui) end
	local before = h.files["UAI/config.json"]
	handle.config.enableVault = function()
		return false, "Could not verify the staged encrypted file. Your existing configuration is unchanged."
	end
	find("VaultPassword"):FindFirstChildOfClass("TextBox").Text = "fixture migration password"
	find("VaultConfirmPassword"):FindFirstChildOfClass("TextBox").Text = "fixture migration password"
	h.click(assert(find("VaultSubmit"))); h.settle(0.4)
	check("failed setup remains visible and blocks the main interface", find("VaultOperationStatus").Text:find("existing configuration is unchanged", 1, true)
		and not handle.config.vaultStatus().ready and not handle.app.window.visible)
	check("failure preserves the previously loaded key pool and saved file", handle.config.get("providers.list")[1].apiKey == "fixture-key-first-1111\nfixture-key-second-2222"
		and h.files["UAI/config.json"] == before)
	check("failure UI clears the password and does not print a credential", find("VaultPassword"):FindFirstChildOfClass("TextBox").Text == ""
		and not h.textOf(handle.app.screen):find("fixture-key-first-1111", 1, true))
	check("migration failure remains a handled error", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	handle.destroy(); h.settle(0.3)
end)

suite.finish()
