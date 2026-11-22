-- Edit individual credentials through the real provider controls; all keys are synthetic.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Provider key entries")
local case, check = suite.case, suite.check

local function click(f, name)
	if name == "SaveProvider" and f.h.byName("APIKeyManager") then
		f.h.click(assert(f.h.byName("ApplyKeys")))
	end
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.2)
end

local function fixture(raw, saved, metadata)
	local f = F.ui(390, 700)
	f.registry = f.env.require("provider/registry")
	f.record = f.registry.blank("custom")
	f.record.label, f.record.baseUrl = "Key entry fixture", "https://keys.fixture/v1"
	f.record.apiKey, f.record.model, f.record.models = raw, "fixture-model", { "fixture-model" }
	for name, value in pairs(metadata or {}) do f.record[name] = value end
	if saved then assert(f.registry.save(f.record)) end
	f.env.require("ui/panels/providers").editor(f.record, function(id) f.saved = f.registry.get(id) end)
	f.h.settle(0.3)
	click(f, "ManageKeys")
	return f
end

local function confirmPrompt(f, label)
	local surfaces = f.env.require("ui/overlay").open
	for _, node in ipairs(surfaces[#surfaces].footer:GetDescendants()) do
		if node.ClassName == "TextLabel" and node.Text == label then
			local button = node.Parent
			while button and button.ClassName ~= "TextButton" do button = button.Parent end
			assert(button, "missing key confirmation")
			f.h.click(button); f.h.settle(0.3)
			return
		end
	end
	error("missing " .. label .. " button")
end

local function submitKey(f, control, text)
	if not f.h.byName("APIKeyManager") then click(f, "ManageKeys") end
	click(f, control)
	local field = assert(f.h.byName("PromptField")):FindFirstChildOfClass("TextBox")
	check("credential prompts never prefill a saved secret", field.Text == "")
	field.Text = text
	f.h.settle(0.1)
	confirmPrompt(f, "Save key")
end

local function rename(f, index, name, previous)
	click(f, "RenameKey_" .. index)
	local field = assert(f.h.byName("PromptField")):FindFirstChildOfClass("TextBox")
	check("renaming starts from the label, never the credential", field.Text == (previous or ""))
	field.Text = name
	confirmPrompt(f, "Save name")
end

case("replacing the middle of a legacy key pool preserves every other credential", function()
	local raw = "fixture-first-1111, fixture-second-2222\nfixture-third-3333\nfixture-first-1111"
	local f = fixture(raw, true)
	for index = 1, 3 do
		check("legacy key " .. index .. " gets an individual entry", f.h.byName("APIKeyLabel_" .. index).Text == "API key " .. index)
	end
	check("duplicate legacy credentials do not create extra entries", f.h.byName("APIKey_4") == nil)
	check("opening the editor masks every stored credential", not f.h.textOf():find("fixture-first", 1, true)
		and not f.h.textOf():find("fixture-second", 1, true) and not f.h.textOf():find("fixture-third", 1, true))
	submitKey(f, "ReplaceKey_2", "fixture-replacement-4444")
	check("only the second entry's mask changes", f.h.byName("APIKeyMask_1").Text:find("1111", 1, true)
		and f.h.byName("APIKeyMask_2").Text:find("4444", 1, true) and f.h.byName("APIKeyMask_3").Text:find("3333", 1, true))
	check("a draft replacement cannot change saved credentials", f.registry.get(f.record.id).apiKey == raw)
	click(f, "SaveProvider")
	check("saving retains ordered untouched keys", f.saved and f.saved.apiKey == "fixture-first-1111\nfixture-replacement-4444\nfixture-third-3333")
	check("existing rotation uses the edited pool", f.registry.nextKey(f.saved) == "fixture-first-1111"
		and f.registry.nextKey(f.saved) == "fixture-replacement-4444" and f.registry.nextKey(f.saved) == "fixture-third-3333"
		and f.registry.nextKey(f.saved) == "fixture-first-1111")
	check("editing and saving send no provider requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("bulk additions append and removing a row only removes that key", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222\nfixture-third-3333")
	submitKey(f, "AddKey", "fixture-fourth-4444, fixture-fifth-5555\nfixture-first-1111")
	check("bulk paste appends unique keys", f.h.byName("APIKey_5") ~= nil and f.h.byName("APIKey_6") == nil)
	click(f, "RemoveKey_2")
	check("remaining rows are numbered in order", f.h.byName("APIKeyLabel_4").Text == "API key 4" and f.h.byName("APIKey_5") == nil
		and f.h.byName("APIKeyMask_2").Text:find("3333", 1, true))
	submitKey(f, "AddKey", "fixture-sixth-6666")
	click(f, "SaveProvider")
	check("add and remove preserve unrelated keys", f.saved and f.saved.apiKey == "fixture-first-1111\nfixture-third-3333\nfixture-fourth-4444\nfixture-fifth-5555\nfixture-sixth-6666")
	f.healthy(); f.close()
end)

case("short credentials stay masked in both numbered entries and the pool summary", function()
	local f = fixture("k11\nk222")
	local visible = f.h.textOf()
	check("the pool summary never reveals a complete short credential", not visible:find("k11", 1, true) and not visible:find("k222", 1, true))
	check("numbered entries only acknowledge that short credentials are set", f.h.byName("APIKeyMask_1").Text == "set"
		and f.h.byName("APIKeyMask_2").Text == "set")
	click(f, "ReplaceKey_1")
	-- The existing harness submits Enter here, exercising the single-line prompt's
	-- keyboard confirmation independently of the Save key button used above.
	f.h.type(f.h.byName("PromptField"):FindFirstChildOfClass("TextBox"), "k333")
	f.h.settle(0.2)
	check("Enter confirms exactly one replacement and closes its prompt", f.h.byName("PromptField") == nil
		and not f.h.textOf():find("k333", 1, true))
	click(f, "SaveProvider")
	check("masking and keyboard replacement preserve the other key", f.saved and f.saved.apiKey == "k333\nk222")
	f.healthy(); f.close()
end)

case("empty, duplicate and multiple replacement values leave the pool intact", function()
	local original = "fixture-first-1111\nfixture-second-2222"
	local f = fixture(original)
	submitKey(f, "ReplaceKey_1", "   ")
	submitKey(f, "ReplaceKey_1", "fixture-second-2222")
	submitKey(f, "ReplaceKey_1", "fixture-other-3333,fixture-another-4444")
	submitKey(f, "AddKey", "fixture-first-1111\nfixture-second-2222")
	click(f, "SaveProvider")
	check("invalid replacements cannot silently delete an entry", f.saved and f.saved.apiKey == original)
	f.healthy(); f.close()
end)

case("cancelled prompts and dismissed saved-provider edits preserve stored keys", function()
	local original = "fixture-first-1111\nfixture-second-2222"
	local f = fixture(original, true)
	click(f, "ReplaceKey_1")
	f.h.byName("PromptField"):FindFirstChildOfClass("TextBox").Text = "fixture-cancelled-3333"
	f.h.press("Escape"); f.h.settle(0.3)
	check("cancelling replacement keeps the original entry", f.h.byName("APIKeyMask_1").Text:find("1111", 1, true))
	submitKey(f, "ReplaceKey_2", "fixture-unsaved-4444")
	click(f, "RemoveKey_1")
	f.h.press("Escape"); f.h.settle(0.3)
	check("closing connection edits keeps the saved pool", f.registry.get(f.record.id).apiKey == original)
	check("cancelled edits never saved a new record", f.saved == nil and f.registry.count() == 1)
	f.healthy(); f.close()
end)

case("new-provider drafts retain all keys and allow further additions after reopening", function()
	local f = fixture("fixture-first-1111")
	local additions = {}
	for index = 2, 40 do additions[#additions + 1] = "fixture-key-" .. index end
	submitKey(f, "AddKey", table.concat(additions, "\n"))
	check("key additions have no small fixed row limit", f.h.byName("APIKeyLabel_40").Text == "API key 40")
	click(f, "ApplyKeys")
	f.h.press("Escape"); f.h.settle(0.3)
	f.env.require("ui/panels/providers").add(function(id) f.saved = f.registry.get(id) end)
	f.h.settle(0.3)
	click(f, "ManageKeys")
	check("reopening a new connection keeps the complete draft", f.h.byName("APIKey_40") ~= nil and f.registry.count() == 0)
	submitKey(f, "AddKey", "fixture-key-41")
	click(f, "SaveProvider")
	check("saving includes every retained and newly appended key", f.saved and #f.registry.keysOf(f.saved) == 41
		and f.registry.keysOf(f.saved)[1] == "fixture-first-1111" and f.registry.keysOf(f.saved)[41] == "fixture-key-41")
	f.healthy(); f.close()
end)

case("removing the last required key stays a draft until access is restored", function()
	local f = fixture("fixture-first-1111", true)
	click(f, "RemoveKey_1")
	click(f, "SaveProvider")
	check("a required empty pool cannot replace a saved credential", f.saved == nil and f.h.byName("Problem").Visible
		and f.registry.get(f.record.id).apiKey == "fixture-first-1111")
	submitKey(f, "AddKey", "fixture-restored-2222")
	click(f, "SaveProvider")
	check("the emptied draft can be repaired and saved", f.saved and f.saved.apiKey == "fixture-restored-2222")
	f.healthy(); f.close()
end)

case("named keys retain their identity when replaced, selected and removed", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222\nfixture-third-3333", true,
		{ keyNames = { "Personal", "Work", "Backup" } })
	check("legacy and new pools default to rotation", f.h.byName("KeyModeHelp").Text:find("take turns", 1, true))
	rename(f, 2, "Work account", "Work")
	submitKey(f, "ReplaceKey_2", "fixture-work-replacement-4444")
	check("replacement keeps the custom name", f.h.byName("APIKeyLabel_2").Text == "Work account")
	click(f, "Segment_single")
	click(f, "UseKey_2")
	check("the chosen key is obvious and other keys are excluded", f.h.textOf(f.h.byName("UseKey_2")) == "Selected"
		and not f.h.byName("UseKey_2").Active and f.h.byName("KeyModeHelp").Text:find("Only Work account", 1, true)
		and f.h.byName("KeyModeHelp").Text:find("Other keys will not be tried", 1, true))
	click(f, "RemoveKey_1")
	check("removing an earlier row preserves the chosen key and its name", f.h.byName("APIKeyLabel_1").Text == "Work account"
		and f.h.textOf(f.h.byName("UseKey_1")) == "Selected" and f.h.byName("APIKeyLabel_2").Text == "Backup")
	check("manager edits cannot change the original provider", f.record.keyNames[2] == "Work"
		and f.env.require("runtime/provider_keys").mode(f.record) == "rotate")
	click(f, "SaveProvider")
	check("names and the single-key selection persist with the provider", f.saved and f.saved.keyMode == "single"
		and f.saved.selectedKey == 1 and f.saved.keyNames[1] == "Work account" and f.saved.keyNames[2] == "Backup"
		and f.saved.apiKey == "fixture-work-replacement-4444\nfixture-third-3333")
	check("single mode repeatedly chooses only that credential", f.registry.nextKey(f.saved) == "fixture-work-replacement-4444"
		and f.registry.nextKey(f.saved) == "fixture-work-replacement-4444")
	f.healthy(); f.close()
end)

case("a retired key selection requires the full connection review after keys are applied", function()
	local f = F.ui(390, 700)
	f.registry = f.env.require("provider/registry")
	local record = f.registry.blank("custom")
	record.label, record.baseUrl, record.model = "Reviewed personal account", "https://keys.fixture/v1", "fixture-model"
	record.apiKey, record.models = "fixture-personal-1111\nfixture-backup-2222", { "fixture-model" }
	record.keyNames, record.keyPaused = { "Personal", "Backup" }, { false, false }
	record.keyIds = { "11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222" }
	record.credentialsOmitted = true
	assert(f.registry.save(record))
	local ui = f.env.require("ui/panels/providers")
	ui.manageKeys(record); f.h.settle(0.3)
	check("retained keys are visible behind a connection review notice", f.h.byName("KeyRestorationRequired").Text:find("selected key", 1, true)
		and f.h.byName("APIKeyLabel_1").Text == "Personal" and f.h.byName("APIKeyLabel_2").Text == "Backup")
	click(f, "Segment_single"); click(f, "UseKey_2"); click(f, "ApplyKeys")
	local updated = assert(f.registry.get(record.id))
	check("keys-only Apply preserves the admission guard and explicit selection", updated.credentialsOmitted == true
		and updated.keyMode == "single" and updated.selectedKey == 2 and updated.keyIds[2] == record.keyIds[2]
		and not f.env.require("provider/availability").describe(updated).ready)
	ui.editor(updated, function(id) f.saved = f.registry.get(id) end); f.h.settle(0.3)
	check("the full editor asks to review the surviving key selection", f.h.byName("RestoreProviderCredentials").Text:find("selected key", 1, true))
	click(f, "SaveProvider")
	check("reviewed Save admits only the chosen surviving credential", f.saved and f.saved.credentialsOmitted == nil
		and f.saved.keyMode == "single" and f.saved.selectedKey == 2 and f.saved.apiKey == record.apiKey
		and f.saved.keyNames[1] == "Personal" and f.saved.keyIds[2] == record.keyIds[2]
		and f.env.require("provider/availability").describe(f.saved).ready
		and f.registry.nextKey(f.saved) == "fixture-backup-2222" and f.registry.nextKey(f.saved) == "fixture-backup-2222")
	check("review controls send no provider requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("removing the selected key visibly returns to rotation", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222\nfixture-third-3333", false,
		{ keyNames = { "Personal", "Work", "Backup" }, keyMode = "single", selectedKey = 2 })
	click(f, "RemoveKey_2")
	check("deleting the selected key explains the mode change", f.h.byName("KeyManagerNotice").Visible
		and f.h.byName("KeyManagerNotice").Text:find("Rotation is on", 1, true))
	check("the remaining names stay paired with their credentials", f.h.byName("APIKeyLabel_1").Text == "Personal"
		and f.h.byName("APIKeyLabel_2").Text == "Backup" and not f.h.byName("UseKey_1").Visible)
	click(f, "SaveProvider")
	check("saving retains the explained rotation policy", f.saved and f.saved.keyMode == "rotate"
		and f.saved.keyNames[2] == "Backup" and f.registry.nextKey(f.saved) == "fixture-first-1111"
		and f.registry.nextKey(f.saved) == "fixture-third-3333")
	f.healthy(); f.close()
end)

case("invalid names are rejected and clearing a name restores its number", function()
	local f = fixture("fixture-first-1111", false, { keyNames = { "Personal" } })
	for _, invalid in ipairs({ "bad\nname", string.rep("x", 121), "bad\1name" }) do
		rename(f, 1, invalid, "Personal")
		check("invalid names leave the previous name intact", f.h.byName("APIKeyLabel_1").Text == "Personal"
			and f.h.byName("KeyManagerNotice").Visible)
	end
	rename(f, 1, "   ", "Personal")
	check("an empty name returns to automatic numbering", f.h.byName("APIKeyLabel_1").Text == "API key 1")
	click(f, "SaveProvider")
	check("clearing the name preserves the credential", f.saved and f.saved.keyNames[1] == "" and f.saved.apiKey == "fixture-first-1111")
	f.healthy(); f.close()
end)

case("Cancel and Escape discard complete manager drafts", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222", false, { keyNames = { "Personal", "Work" } })
	rename(f, 1, "Not saved", "Personal")
	click(f, "Segment_single"); click(f, "UseKey_2"); click(f, "CancelKeys")
	check("Cancel returns to provider setup", f.h.byName("APIKeyManager") == nil and f.h.byName("SaveProvider") ~= nil)
	click(f, "ManageKeys")
	check("cancelled names and routing do not enter the provider draft", f.h.byName("APIKeyLabel_1").Text == "Personal"
		and not f.h.byName("UseKey_2").Visible)
	click(f, "RemoveKey_1"); f.h.press("Escape"); f.h.settle(0.3)
	click(f, "ManageKeys")
	check("Escape also discards removed rows", f.h.byName("APIKeyLabel_1").Text == "Personal"
		and f.h.byName("APIKeyLabel_2").Text == "Work")
	click(f, "SaveProvider")
	check("provider Save cannot commit cancelled manager edits", f.saved and f.saved.keyNames[1] == "Personal"
		and f.saved.keyMode == "rotate" and f.saved.apiKey == "fixture-first-1111\nfixture-second-2222")
	f.healthy(); f.close()
end)

case("empty pools explain single-key requirements and manager application can be retried", function()
	local f = F.ui(900, 650)
	local record = { label = "Fixture", apiKey = "" }
	local attempts, closed, applied = 0, 0, nil
	local manager = f.env.require("ui/providerkeys").open({ record = record,
		onApply = function(candidate)
			attempts = attempts + 1
			if attempts == 1 then return false end
			applied = candidate; return true
		end, onClose = function() closed = closed + 1 end })
	click(f, "Segment_single")
	check("single mode cannot choose a nonexistent key", f.h.byName("NoAPIKeys") ~= nil
		and f.h.byName("KeyManagerNotice").Text:find("Add an API key", 1, true))
	submitKey(f, "AddKey", "fixture-first-1111")
	click(f, "Segment_single")
	click(f, "ApplyKeys")
	check("a rejected application leaves the draft available", not manager.closed and attempts == 1
		and f.h.byName("APIKeyMask_1").Text:find("1111", 1, true) and record.apiKey == "")
	click(f, "ApplyKeys")
	check("a successful retry applies once and closes once", manager.closed and attempts == 2 and closed == 1
		and applied.apiKey == "fixture-first-1111" and applied.keyMode == "single" and applied.selectedKey == 1)
	check("callbacks receive only key settings", applied.label == nil and applied.baseUrl == nil and applied.keyRotation == nil)
	f.healthy(); f.close()
end)

case("manager destruction closes its owned prompt without applying", function()
	local f = F.ui(900, 650)
	local applied, closed = 0, 0
	local manager = f.env.require("ui/providerkeys").open({ record = { apiKey = "fixture-first-1111" },
		onApply = function() applied = applied + 1 end, onClose = function() closed = closed + 1 end })
	click(f, "ReplaceKey_1")
	f.h.byName("PromptField"):FindFirstChildOfClass("TextBox").Text = "fixture-unsaved-2222"
	manager.scrim:Destroy(); f.h.settle(0.3)
	check("destroying the manager closes both surfaces", manager.closed and f.h.byName("PromptField") == nil
		and #f.env.require("ui/overlay").open == 0 and applied == 0 and closed == 1)
	f.healthy(); f.close()
end)

case("renaming preserves legacy credential text and invalid single selections require repair", function()
	local f = F.ui(900, 650)
	local raw = "fixture-first-1111, fixture-second-2222\nfixture-first-1111"
	local applied
	local manager = f.env.require("ui/providerkeys").open({ record = { apiKey = raw,
		keyMode = "single", selectedKey = 99 }, onApply = function(candidate) applied = candidate end })
	check("an invalid pinned index is not presented as a selected first key", f.h.byName("KeyModeHelp").Text:find("No key is selected", 1, true)
		and f.h.textOf(f.h.byName("UseKey_1")) == "Use this key")
	click(f, "ApplyKeys")
	check("an invalid pin cannot be applied", not manager.closed and applied == nil and f.h.byName("KeyManagerNotice").Visible)
	click(f, "Segment_rotate")
	rename(f, 2, "Work")
	click(f, "ApplyKeys")
	check("repair and rename retain the original authentication string", applied and applied.apiKey == raw
		and applied.keyNames[2] == "Work" and applied.keyMode == "rotate" and applied.selectedKey == 1)
	f.healthy(); f.close()
end)

case("the saved-provider shortcut applies only keys and preserves a live rotation cursor", function()
	local f = F.ui(1000, 800)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl = "Saved keys", "https://keys.fixture/v1"
	record.apiKey = "fixture-first-1111, fixture-second-2222"
	record.keyNames = { "Personal", "Work" }
	record.model, record.models = "fixture-model", { "fixture-model" }
	record.health = { ok = 7, fail = 0, lastError = "", cooldownUntil = 0 }
	assert(registry.save(record))
	check("a request advances the live cursor", registry.nextKey(record) == "fixture-first-1111")
	local cursor, health = record.keyRotation, record.health
	local providers = f.env.require("ui/panels/providers")
	local panel = providers.new(f.host)
	panel.select(record.id); f.h.settle(0.3)
	click(f, "ManageProviderKeys")
	check("the direct shortcut opens keys without a connection editor", f.h.byName("APIKeyManager") ~= nil
		and f.h.byName("SaveProvider") == nil)
	rename(f, 2, "Work account", "Work")
	-- An unrelated model change made while this manager is open must survive its
	-- later key-only Apply, and active requests still own the same rotation table.
	record.model, record.models = "concurrent-model", { "fixture-model", "concurrent-model" }
	assert(registry.save(record))
	click(f, "ApplyKeys")
	local saved = assert(registry.get(record.id))
	check("direct Apply saves the name without rewriting legacy authentication text", saved.keyNames[2] == "Work account"
		and saved.apiKey == "fixture-first-1111, fixture-second-2222")
	check("concurrent model changes survive a key-only save", saved.model == "concurrent-model" and #saved.models == 2)
	check("name-only changes preserve cursor and health identity", saved.keyRotation == cursor and saved.health == health
		and registry.nextKey(saved) == "fixture-second-2222")
	providers.manageKeys(saved)
	rename(f, 1, "Discard this", "Personal")
	click(f, "CancelKeys")
	check("direct Cancel leaves saved names and the live cursor untouched", registry.get(record.id) == saved
		and saved.keyNames[1] == "Personal" and saved.keyRotation == cursor)
	check("direct key management never requests inference", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("closing the connection editor also closes its key manager and prompt", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222")
	local overlays = f.env.require("ui/overlay").open
	local editor = overlays[1]
	click(f, "RenameKey_2")
	f.h.byName("PromptField"):FindFirstChildOfClass("TextBox").Text = "Discarded label"
	editor.close(); f.h.settle(0.3)
	check("the editor owns both child surfaces", f.h.byName("APIKeyManager") == nil
		and f.h.byName("PromptField") == nil and #overlays == 0)
	check("closing the parent cannot apply child edits", f.env.require("runtime/provider_keys").entries(f.record)[2].name == ""
		and f.saved == nil and f.registry.count() == 0)
	f.healthy(); f.close()
end)

case("saving a name-only connection edit preserves requests advanced while it was open", function()
	local f = fixture("fixture-first-1111\nfixture-second-2222\nfixture-third-3333", true,
		{ keyNames = { "Personal", "Work", "Backup" } })
	local live = f.registry.get(f.record.id)
	check("requests continue rotating while setup is open", f.registry.nextKey(live) == "fixture-first-1111"
		and f.registry.nextKey(live) == "fixture-second-2222")
	local cursor = live.keyRotation
	rename(f, 2, "Work account", "Work")
	click(f, "SaveProvider")
	check("the connection save preserves the latest shared cursor", f.saved and f.saved.keyRotation == cursor
		and f.saved.keyNames[2] == "Work account" and f.registry.nextKey(f.saved) == "fixture-third-3333")
	f.healthy(); f.close()
end)

for _, size in ipairs({ { 1000, 800 }, { 320, 568 }, { 844, 220 } }) do
	case("key manager fits and keeps its draft across keyboard changes at " .. size[1] .. "x" .. size[2], function()
		local f = F.ui(size[1], size[2])
		f.env.uis.TouchEnabled, f.env.uis.MouseEnabled = size[1] ~= 1000, size[1] == 1000
		local responsive, theme = f.env.require("ui/responsive"), f.env.require("ui/theme")
		responsive.init(f.env.root); theme.rebuild()
		local manager = f.env.require("ui/providerkeys").open({ record = { label = "Fixture",
			apiKey = "fixture-first-1111\nfixture-second-2222", keyNames = { "Personal", "Work" } } })
		local layout = manager.content:FindFirstChildOfClass("UIListLayout")
		layout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 300)
		f.h.sched.advance(0.2)
		local shortHeight = manager.card.Size.Y.Offset
		if size[1] == 1000 then check("short key lists fit without an empty band", shortHeight < theme.size.modalTall) end
		layout.AbsoluteContentSize = f.h.dt.Vector2.new(240, 2400)
		f.h.sched.advance(0.2)
		check("long key lists stay within the viewport", manager.card.AbsolutePosition.Y >= 0
			and manager.card.AbsolutePosition.Y + manager.card.AbsoluteSize.Y <= size[2] + 1
			and manager.scroll.instance.Size.Y.Offset < 2400)
		click(f, "RenameKey_2")
		local field = f.h.byName("PromptField"):FindFirstChildOfClass("TextBox")
		field.Text, field.CursorPosition, field.SelectionStart = "Work draft", 5, 2
		f.env.uis.OnScreenKeyboardSize = f.h.dt.Vector2.new(size[1], math.floor(size[2] * 0.55))
		f.env.uis.OnScreenKeyboardVisible = true
		f.env.uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); f.h.sched.advance(0.2)
		check("keyboard changes preserve the original name input and selection", f.h.byName("PromptField"):FindFirstChildOfClass("TextBox") == field
			and field.Text == "Work draft" and field.CursorPosition == 5 and field.SelectionStart == 2)
		f.env.uis.OnScreenKeyboardVisible = false
		f.env.uis:GetPropertyChangedSignal("OnScreenKeyboardVisible"):Fire(); f.h.sched.advance(0.2)
		confirmPrompt(f, "Save name")
		check("returning from the keyboard retains named rows", f.h.byName("APIKeyLabel_1").Text == "Personal"
			and f.h.byName("APIKeyLabel_2").Text == "Work draft")
		manager.close(); f.h.settle(0.3)
		f.healthy(); f.close()
	end)
end

suite.finish()
