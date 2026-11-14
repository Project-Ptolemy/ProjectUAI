-- Per-key usage/pause controls and conversation counts use the live accounting store.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local authenticate = require("password_fixture")
local suite = F.suite("Request usage UI")
local case, check = suite.case, suite.check
local FIRST, SECOND = "fixture-first-1111", "fixture-second-2222"

local function click(f, name)
	f.h.click(assert(f.h.byName(name), "missing " .. name)); f.h.settle(0.2)
end

local function confirm(f, text)
	local overlays = f.env.require("ui/overlay").open
	for _, node in ipairs(overlays[#overlays].footer:GetDescendants()) do
		if node.ClassName == "TextLabel" and node.Text == text then
			local button = node.Parent
			while button and not button:IsA("GuiButton") do button = button.Parent end
			f.h.click(assert(button)); f.h.settle(0.2); return
		end
	end
	error("missing prompt action " .. text)
end

local function provider(env)
	local registry = env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl = "Usage fixture", "https://usage.fixture/v1"
	record.apiKey, record.keyNames = FIRST .. "\n" .. SECOND, { "Personal", "Work" }
	record.model, record.models = "fixture-model", { "fixture-model" }
	assert(registry.save(record))
	return registry, record
end

local function fixture()
	local f = F.ui(900, 700)
	f.registry, f.record = provider(f.env)
	f.stats = f.env.require("agent/stats"); f.stats.load(); f.stats.observe()
	f.sessions = f.env.require("agent/session")
	f.keys = f.env.require("runtime/provider_keys")
	f.providers = f.env.require("ui/panels/providers")
	return f
end

local function request(env, record, session, key, input, output)
	local tracker = env.require("runtime/request_accounting").new(record, { session = session })
	tracker.dispatch(key)
	tracker.attach({ usage = { prompt_tokens = input, completion_tokens = output } })
	return tracker
end

case("pause and resume stay isolated until Apply and survive saved-provider reopening", function()
	local f = fixture()
	f.providers.manageKeys(f.record); click(f, "PauseKey_1")
	check("the paused row and active count are visible", f.h.byName("APIKeyState_1").Text:find("Paused", 1, true)
		and f.h.byName("KeyCount").Text:find("1 active", 1, true) and f.h.textOf(f.h.byName("PauseKey_1")) == "Resume")
	check("pausing a draft does not change saved routing", #f.keys.requestKeys(f.record) == 2)
	click(f, "CancelKeys")
	check("Cancel preserves both active keys", #f.keys.requestKeys(f.registry.get(f.record.id)) == 2)
	f.providers.manageKeys(f.registry.get(f.record.id)); click(f, "PauseKey_1"); click(f, "ApplyKeys")
	local saved = f.registry.get(f.record.id)
	check("Apply persists pause without removing or renaming credentials", saved.apiKey == f.record.apiKey
		and saved.keyNames[1] == "Personal" and saved.keyNames[2] == "Work" and saved.keyPaused[1] == true
		and table.concat(f.keys.requestKeys(saved), ",") == SECOND)
	f.providers.manageKeys(saved)
	check("the saved row reopens with Resume", f.h.textOf(f.h.byName("PauseKey_1")) == "Resume")
	click(f, "PauseKey_1"); click(f, "ApplyKeys")
	check("Resume restores the original pool", #f.keys.requestKeys(f.registry.get(saved.id)) == 2)
	check("managing pause never sends a provider request", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("pausing a selected key keeps the preference and explains how to resume", function()
	local f = fixture()
	assert(f.keys.setMode(f.record, "single", 2)); assert(f.registry.save(f.record))
	f.providers.manageKeys(f.record); click(f, "PauseKey_2")
	check("the manager explains a paused selected key", f.h.byName("KeyModeHelp").Text:find("selected key is paused", 1, true))
	click(f, "ApplyKeys")
	local saved = f.registry.get(f.record.id)
	check("a paused selected key can be saved without falling through to another key", saved.keyMode == "single"
		and saved.selectedKey == 2 and saved.keyPaused[2] == true and #f.keys.requestKeys(saved) == 0)
	f.providers.manageKeys(saved); click(f, "PauseKey_1")
	check("paused keys cannot be selected through Use this key", f.h.byName("UseKey_1").Active == false)
	click(f, "CancelKeys")
	f.providers.manageKeys(saved); click(f, "PauseKey_2"); click(f, "ApplyKeys")
	check("resuming the chosen key restores only that credential", table.concat(f.keys.requestKeys(f.registry.get(saved.id)), ",") == SECOND)
	f.healthy(); f.close()
end)

case("switching to one key selects an active entry when the first is paused", function()
	local f = fixture()
	f.providers.manageKeys(f.record); click(f, "PauseKey_1"); click(f, "Segment_single")
	check("the remaining active key becomes selected", f.h.byName("KeyModeHelp").Text:find("Only Work", 1, true)
		and f.h.textOf(f.h.byName("UseKey_2")) == "Selected" and f.h.byName("UseKey_1").Active == false)
	click(f, "ApplyKeys")
	local saved = f.registry.get(f.record.id)
	check("the usable single-key preference applies without resuming the first key", not f.h.byName("APIKeyManager")
		and saved.keyMode == "single" and saved.selectedKey == 2 and saved.keyPaused[1]
		and table.concat(f.keys.requestKeys(saved), ",") == SECOND)
	f.healthy(); f.close()
end)

case("usage updates preserve rows, an open name prompt and pending edits", function()
	local f = fixture()
	local before = f.sessions.usageChanged:count()
	local modal = f.providers.manageKeys(f.record)
	local row, usage = f.h.byName("APIKey_1"), f.h.byName("APIKeyUsage_1")
	check("new key usage starts at zero", usage.Text:find("0 requests", 1, true) and usage.Text:find("0 input / 0 output", 1, true))
	click(f, "RenameKey_1")
	local field = assert(f.h.byName("PromptField")):FindFirstChildOfClass("TextBox")
	field.Text, field.CursorPosition, field.SelectionStart = "Personal draft", 5, 2
	request(f.env, f.record, { id = "usage-owner" }, FIRST, 11, 7)
	f.h.settle(0.1)
	check("measured usage appears without rebuilding the card", f.h.byName("APIKey_1") == row and f.h.byName("APIKeyUsage_1") == usage
		and usage.Text:find("1 request", 1, true) and usage.Text:find("11 input / 7 output", 1, true))
	check("usage does not replace or reset the active name input", f.h.byName("PromptField"):FindFirstChildOfClass("TextBox") == field
		and field.Text == "Personal draft" and field.CursorPosition == 5 and field.SelectionStart == 2)
	local tracker = request(f.env, f.record, { id = "usage-owner" }, FIRST, 5, nil)
	f.env.require("runtime/request_accounting").report(tracker.latest, nil, { prompt = 100, completion = 3 })
	check("estimated token totals are labelled", usage.Text:find("2 requests", 1, true)
		and usage.Text:find("About 16 input / 10 output", 1, true))
	confirm(f, "Save name")
	check("the pending name survives usage updates", f.h.byName("APIKeyLabel_1").Text == "Personal draft"
		and f.h.byName("APIKeyUsage_1").Text:find("2 requests", 1, true))
	click(f, "ApplyKeys")
	check("closing releases the manager's usage subscription", modal.closed and f.sessions.usageChanged:count() == before)
	check("saving a name preserves recorded usage", f.sessions.keyUsage(f.registry.get(f.record.id), 1).requests == 2)
	f.healthy(); f.close()
end)

case("replacement starts new usage while removing an earlier row retains the surviving key's totals", function()
	local f = fixture()
	request(f.env, f.record, nil, FIRST, 11, 7)
	request(f.env, f.record, nil, SECOND, 21, 9)
	request(f.env, f.record, nil, SECOND, 21, 9)
	f.providers.manageKeys(f.record); click(f, "ReplaceKey_1")
	local field = f.h.byName("PromptField"):FindFirstChildOfClass("TextBox")
	field.Text = "fixture-replacement-3333"; confirm(f, "Save key")
	check("replacement shows fresh usage while unrelated usage remains", f.h.byName("APIKeyUsage_1").Text:find("0 requests", 1, true)
		and f.h.byName("APIKeyUsage_2").Text:find("2 requests", 1, true))
	click(f, "CancelKeys")
	check("cancel keeps the original usage identity", f.sessions.keyUsage(f.registry.get(f.record.id), 1).requests == 1)
	f.providers.manageKeys(f.registry.get(f.record.id)); click(f, "RemoveKey_1")
	check("usage follows the surviving key after its index shifts", f.h.byName("APIKeyLabel_1").Text == "Work"
		and f.h.byName("APIKeyUsage_1").Text:find("2 requests", 1, true)
		and f.h.byName("APIKeyUsage_1").Text:find("42 input / 18 output", 1, true))
	click(f, "ApplyKeys")
	check("the shifted usage identity persists", f.sessions.keyUsage(f.registry.get(f.record.id), 1).requests == 2)
	f.healthy(); f.close()
end)

for _, size in ipairs({ { 1280, 840 }, { 390, 844 }, { 844, 220 } }) do
	case("conversation counts stay local and visible at " .. size[1] .. "x" .. size[2], function()
		local h = require("env").new()
		h.services.UserInputService.TouchEnabled, h.services.UserInputService.MouseEnabled = size[1] ~= 1280, size[1] == 1280
		h.setViewport(size[1], size[2])
		local handle = assert(h.boot()); authenticate(h, handle); h.settle(0.5)
		local env, app = handle.env, handle.app
		local function find(name) return h.byName(name, app.screen) end
		local sessions = env.require("agent/session")
		local _, record = provider(env)
		local first = assert(sessions.newThread({ id = "counter-first", title = "First conversation" }))
		local second = assert(sessions.newThread({ id = "counter-second", title = "Second conversation", activate = false }))
		app.openSession(first.id); h.settle(0.3)
		local counter = assert(find("ConversationRequests"))
		check("the current conversation begins with a visible zero", counter.Visible and counter.Text:find("0 req", 1, true))
		local composer = app.chatPanel.composer
		local field = composer.field
		field.set("Unsent question")
		first.busy = true
		request(env, record, first, FIRST, 11, 7); h.settle(0.1)
		check("dispatch updates the counter without resetting the composer or running state", find("ConversationRequests") == counter
			and counter.Text:find("1 req", 1, true) and app.chatPanel.composer == composer and composer.field == field
			and field.get() == "Unsent question" and first.busy)
		request(env, record, second, SECOND, 21, 9)
		request(env, record, second, SECOND, 21, 9); h.settle(0.1)
		check("background requests do not inflate the visible conversation", counter.Text:find("1 req", 1, true)
			and sessions.conversationUsage(second).requests == 2 and sessions.current() == first)
		local inspector = env.require("ui/chat/context").open(first); h.settle(0.2)
		local detail = assert(find("ConversationRequestTotal"))
		check("context details explain the same local counter", detail.Text == "This conversation: 1 AI request"
			and find("ConversationRequestHint").Text:find("including retries", 1, true))
		request(env, record, first, FIRST, 11, 7); h.settle(0.2)
		check("the open context counter updates in place", find("ConversationRequestTotal") == detail
			and detail.Text == "This conversation: 2 AI requests")
		inspector.close(); h.settle(0.2)
		app.openSession(second.id); h.settle(0.2)
		check("switching shows that conversation's requests", counter.Text:find("2 req", 1, true) and sessions.current() == second and first.busy)
		local nested = { id = "nested-counter", headless = true, depth = 1, accountingParent = first }
		request(env, record, nested, FIRST, 4, 2); h.settle(0.1)
		check("subagent calls belong to the parent without switching the view", counter.Text:find("2 req", 1, true)
			and sessions.conversationUsage(first).requests == 3)
		app.openSession(first.id); h.settle(0.2)
		check("returning restores the latest count and the original draft", counter.Text:find("3 req", 1, true)
			and app.chatPanel.composer.field.get() == "Unsent question")
		-- The offline mock does not solve flex width. Supply measured narrow/wide
		-- geometry, then fire the size notification Roblox publishes after layout.
		local detailRow, primitives = counter.Parent, env.require("ui/primitives")
		local originalSize = detailRow.Size
		local compactWidth = math.ceil(primitives.measureText("3 req.", { role = "caption" }).X) + 1
		detailRow.Size = h.sandbox.UDim2.fromOffset(compactWidth, originalSize.Y.Offset)
		detailRow:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		check("a narrow header shows the entire compact counter", counter.Text == "3 req."
			and primitives.measureText(counter.Text, { role = "caption" }).X <= detailRow.AbsoluteSize.X)
		detailRow.Size = h.sandbox.UDim2.fromOffset(240, originalSize.Y.Offset)
		detailRow:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		check("widening restores the full label without rebuilding it", counter.Text:find("3 requests", 1, true)
			and find("ConversationRequests") == counter)
		detailRow.Size = originalSize
		detailRow:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		app.show("providers"); h.settle(0.2)
		check("unrelated panels do not show a conversation counter", not counter.Visible)
		first.busy = false
		handle.unload()
		check("counter interactions do not cause asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	end)
end

suite.finish()
