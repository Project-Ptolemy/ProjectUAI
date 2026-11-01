-- Bundled UI admission, retained drafts and provider setup navigation.
-- Geometry checks use supplied mock bounds, not native text/layout validation.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local suite = require("workspace_fixture").suite("Provider admission UI")
local case, check = suite.case, suite.check
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end
local function fixture(mobile)
	local h = envMock.new()
	if mobile then h.services.UserInputService.TouchEnabled = true; h.setViewport(390, 844) end
	local app = assert(h.boot()); h.settle(0.5)
	local allowed
	h.sched.spawn(function() allowed = app.config.continueWithoutEncryption() end)
	h.settle(1)
	assert(allowed and app.config.vaultStatus().ready, "UI admission fixture must complete credential setup")
	app.app.show("chat"); h.settle(0.5)
	app.config.set("bridge.autoDiscover", false)
	local f = { h = h, app = app, composer = app.app.chatPanel.composer,
		session = app.sessions.current(), quick = app.env.require("ui/quickchat"), attempts = 0 }
	f.session.send = function() f.attempts = f.attempts + 1; return true end
	function f.node(name) return assert(h.byName(name, f.composer.shell), "missing " .. name) end
	function f.add(enabled)
		local record = app.providers.blank("custom")
		record.label, record.baseUrl, record.apiKey = "UI admission fixture", "https://admission.fixture/v1", "fixture-key"
		record.model, record.models, record.enabled = "fixture-model", { "fixture-model" }, enabled ~= false
		assert(app.providers.save(record)); return record
	end
	function f.close()
		app.destroy(); h.settle(0.5)
		check("UI admission releases without asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
	end
	return f
end

case("Chat explains setup beside existing messages and blocks click and Enter without losing attachments", function()
	local f = fixture()
	local composer, h = f.composer, f.h
	f.session.emit("user", { text = "Previously saved message" })
	h.settle(0.5)
	check("existing transcript does not hide the provider setup notice", f.node("ProviderSetupNotice").Visible
		and has(h.textOf(f.app.app.chatPanel.view.scroll.instance), "Previously saved message"))
	check("setup says sending is disabled and gives explicit steps", has(f.node("ProviderSetupTitle").Text, "Set up a provider")
		and has(f.node("ProviderSetupDescription").Text, "Sending is disabled")
		and has(f.node("ProviderSetupDescription").Text, "Open Providers") and has(f.node("ProviderSetupDescription").Text, "click Save"))
	check("prompt explains setup before submission", has(composer.field.instance.PlaceholderText, "provider before sending"))
	local fsx = f.app.env.require("runtime/fsx")
	assert(fsx.write("admission-context.txt", "RETAINED_CONTEXT", { scope = "files" }))
	h.click(f.node("AddContext")); h.click(assert(h.byName("Option_file:admission-context.txt")))
	check("file is attached through the real menu", #composer.attachments == 1)
	local originalLog, originalMessages = #f.session.log, #f.session.ctx.messages
	h.type(composer.field.instance, "Keep this draft")
	h.click(f.node("Send"))
	check("missing setup disables the button and guards keyboard sends", not f.node("Send").Active and not f.node("Send").Selectable and f.attempts == 0)
	check("blocked submission retains draft and attachments without changing conversation", composer.field.get() == "Keep this draft"
		and #composer.attachments == 1 and #f.session.log == originalLog and #f.session.ctx.messages == originalMessages
		and f.session.queueSnapshot().count == 0)
	h.click(f.node("OpenProviderSetup"))
	check("setup action opens Providers directly and retains the draft", f.app.app.panel == "providers" and composer.field.get() == "Keep this draft")
	f.add()
	check("saving an enabled provider clears setup and enables the retained draft", not f.node("ProviderSetupNotice").Visible and f.node("Send").Active)
	f.app.app.show("chat"); h.click(f.node("Send"))
	check("the retained draft is accepted exactly once after setup", f.attempts == 1 and composer.field.get() == "" and #composer.attachments == 0)
	f.close()
end)

case("Quick Chat blocks keyboard and button sends and reacts to provider disable and removal", function()
	local f = fixture()
	local quick, h = f.quick, f.h
	quick.show(); h.settle(0.3)
	h.type(quick.field.instance, "Keep my quick draft"); h.click(quick.sendButton.instance)
	check("unconfigured Quick Chat blocks both submission paths", f.attempts == 0 and not quick.sendButton.instance.Active
		and quick.visible and quick.field.get() == "Keep my quick draft")
	check("Quick Chat explains setup and supplies a direct action", has(quick.hint.Text, "Sending is disabled")
		and has(quick.hint.Text, "click Save") and quick.providerSetupButton.instance.Visible)
	h.click(quick.providerSetupButton.instance)
	check("Quick Chat setup opens Providers while retaining its draft", not quick.visible and f.app.app.panel == "providers"
		and quick.field.get() == "Keep my quick draft")
	local record = f.add()
	quick.show(); h.settle(0.3)
	check("saved setup restores Quick Chat sending", quick.sendButton.instance.Active and not quick.providerSetupButton.instance.Visible)
	record.enabled = false; assert(f.app.providers.save(record))
	check("disabling setup refreshes the open Quick Chat", not quick.sendButton.instance.Active and quick.providerSetupButton.instance.Visible
		and has(quick.hint.Text, "turn on Enabled"))
	h.type(quick.field.instance, "Keep disabled draft"); h.click(quick.sendButton.instance)
	check("disabled-provider submission preserves the Quick Chat draft", f.attempts == 0 and quick.field.get() == "Keep disabled draft")
	record.enabled = true; assert(f.app.providers.save(record)); assert(f.app.providers.remove(record.id))
	check("removal restores the setup notice in both surfaces", f.node("ProviderSetupNotice").Visible
		and not f.node("Send").Active and has(quick.hint.Text, "Set up a provider") and not quick.sendButton.instance.Active)
	f.add(); h.click(quick.sendButton.instance)
	check("restored setup sends and clears the quick draft once", f.attempts == 1 and quick.field.get() == "" and not quick.visible)
	f.close()
end)

case("fallback configuration changes refresh admission on both surfaces", function()
	local f = fixture()
	local disabled = f.add(false)
	f.add(); assert(f.app.providers.setActive(disabled.id))
	f.composer.field.set("Main draft"); f.quick.show(); f.quick.field.set("Quick draft")
	f.app.config.set("agent.fallback", false)
	check("fallback off explains the disabled selection and blocks both buttons", f.node("ProviderSetupNotice").Visible
		and has(f.node("ProviderSetupTitle").Text, "Select a provider") and not f.node("Send").Active
		and has(f.quick.hint.Text, "Use this provider") and not f.quick.sendButton.instance.Active)
	f.app.config.set("agent.fallback", true)
	check("fallback on removes stale setup notices immediately", not f.node("ProviderSetupNotice").Visible and f.node("Send").Active
		and not f.quick.providerSetupButton.instance.Visible and f.quick.sendButton.instance.Active)
	local agent = f.app.env.require("runtime/util").deepCopy(f.app.config.get("agent"))
	agent.fallback = false; f.app.config.set("agent", agent)
	check("whole agent configuration replacement refreshes both surfaces", f.node("ProviderSetupNotice").Visible and not f.node("Send").Active
		and f.quick.providerSetupButton.instance.Visible and not f.quick.sendButton.instance.Active)
	check("configuration changes preserve both drafts", f.composer.field.get() == "Main draft" and f.quick.field.get() == "Quick draft")
	f.close()
end)

case("mobile setup controls fit supplied narrow bounds and remain usable with the keyboard", function()
	local f = fixture(true)
	local h, composer = f.h, f.composer
	local chat = assert(composer.shell.Parent)
	local V = h.dt.Vector2
	chat.AbsoluteSize = V.new(320, 400)
	composer.shell.AbsoluteSize = V.new(320, composer.shell.Size.Y.Offset)
	composer.syncContext()
	local notice, surface = f.node("ProviderSetupNotice"), f.node("ComposerSurface")
	check("narrow provider notice has reserved space above the typing surface", notice.Size.Y.Offset > 0
		and surface.Position.Y.Offset >= notice.Position.Y.Offset + notice.Size.Y.Offset and composer.shell.Size.Y.Offset <= 400)
	check("provider action retains the mobile target size", f.node("OpenProviderSetup").Size.Y.Offset >= f.app.env.require("ui/responsive").minTarget())
	composer.setExpanded(true)
	h.services.UserInputService.OnScreenKeyboardVisible = true
	h.services.UserInputService.OnScreenKeyboardSize = V.new(390, 300)
	f.app.env.require("ui/responsive").refresh("keyboard")
	chat.AbsoluteSize = V.new(320, 300); composer.syncContext()
	check("keyboard bounds retain setup and the typing surface without overlap", composer.shell.Size.Y.Offset <= 300
		and surface.Position.Y.Offset >= notice.Position.Y.Offset + notice.Size.Y.Offset and not f.node("Send").Active)
	check("expanded prompt keeps the setup instruction", has(composer.field.instance.PlaceholderText, "provider before sending"))
	f.quick.show(); h.settle(0.3)
	local rect = f.app.env.require("ui/responsive").usableRect(f.quick.root.Parent, f.app.env.require("ui/theme").space.md)
	check("Quick Chat uses a bounded scroll viewport under the keyboard", f.quick.card.Size.X.Offset <= rect.width
		and f.quick.card.Size.Y.Offset <= rect.height and h.byName("QuickBody", f.quick.card).ScrollingEnabled)
	f.close()
end)

suite.finish()
