-- Request caps use exact inputs, isolated drafts and cancellable visible waits.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("coding_fixture")
local suite = F.suite("Request rate UI")
local case, check = suite.case, suite.check
local function input(f, name)
	return assert(assert(f.h.byName(name), "missing " .. name):FindFirstChildOfClass("TextBox"))
end
local function type(f, name, value) f.h.type(input(f, name), value) end
local function click(f, name) f.h.click(assert(f.h.byName(name), "missing " .. name)) end
local function workingLabel(f, root)
	local row = f.h.byName("WorkingStatus", root)
	if not row then return nil end
	-- WorkingStatus is the row Frame. Its primary TextLabel precedes the clock.
	for _, child in ipairs(row:GetChildren()) do
		if child:IsA("TextLabel") and child.LayoutOrder == 2 then return child end
	end
	error("WorkingStatus has no primary status TextLabel", 2)
end
local function workingText(f, root)
	local label = workingLabel(f, root)
	return label and label.Text
end
local function provider(f)
	local registry = f.env.require("provider/registry")
	local record = registry.blank("custom")
	record.label, record.baseUrl, record.apiKey = "Rate fixture", "https://rate.fixture/v1", "synthetic-rate-key"
	record.model, record.models, record.stream = "rate-fixture-model", { "rate-fixture-model" }, false
	assert(registry.save(record))
	f.h.http.handler = function()
		return { StatusCode = 200, Body = f.h.json.encode({ choices = {
			{ message = { role = "assistant", content = "ready" }, finish_reason = "stop" },
		}, usage = { prompt_tokens = 8, completion_tokens = 2 } }) }
	end
	return record, registry
end
local function prime(f, record)
	assert(f.run(function() return f.env.require("provider/chat").complete(record, {
		messages = { { role = "user", content = "Prime the allowance" } }, stream = false, attempts = 1,
	}) end, 0.4))
end

case("global caps accept exact low integers and retain invalid drafts", function()
	local f = F.ui(900, 800); local config = f.env.require("runtime/config")
	assert(f.env.require("ui/settingspanes").render("agent", f.host))
	for _, value in ipairs({ "1", "2", "0", "" }) do
		type(f, "GlobalRequestsPerMinute", value)
		check("the exact global value is persisted: " .. value, config.get("agent.requestsPerMinute") == (tonumber(value) or 0))
	end
	type(f, "GlobalRequestsPerMinute", "2")
	for _, value in ipairs({ "1.5", "-1", "1000001", "unknown" }) do
		type(f, "GlobalRequestsPerMinute", value)
		check("invalid global value preserves the cap and entered draft: " .. value,
			config.get("agent.requestsPerMinute") == 2 and input(f, "GlobalRequestsPerMinute").Text == value
			and f.h.byName("GlobalRequestsPerMinuteProblem").Visible)
	end
	type(f, "GlobalRequestsPerMinute", "1000000")
	check("the upper boundary is accepted and feedback clears", config.get("agent.requestsPerMinute") == 1000000
		and not f.h.byName("GlobalRequestsPerMinuteProblem").Visible)
	check("settings editing sends no requests", f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("provider caps stay in the connection draft and invalid values block Save and Test", function()
	local f = F.ui(900, 800); local record, registry = provider(f)
	local config = f.env.require("runtime/config")
	config.set("agent.requestsPerMinute", 2); record.requestsPerMinute = 3
	f.env.require("ui/panels/providers").editor(record)
	type(f, "ProviderRequestsPerMinute", "10")
	check("a provider cap has no effect before Save", record.requestsPerMinute == 3 and registry.get(record.id) == record)
	type(f, "ProviderRequestsPerMinute", "10.5")
	click(f, "SaveProvider"); click(f, "TestConnection"); f.h.settle(0.3)
	check("invalid provider caps retain their field and do not save or dispatch", registry.get(record.id).requestsPerMinute == 3
		and input(f, "ProviderRequestsPerMinute").Text == "10.5" and f.h.byName("Problem").Visible and f.h.http.requestCount == 0)
	type(f, "ProviderRequestsPerMinute", "10"); click(f, "SaveProvider"); f.h.settle(0.3)
	check("Save preserves the exact provider cap independently of the global cap", registry.get(record.id).requestsPerMinute == 10
		and config.get("agent.requestsPerMinute") == 2 and registry.count() == 1)
	f.healthy(); f.close()
end)

case("a connection test exposes rate waiting and closing its form cancels before dispatch", function()
	local f = F.ui(900, 800); local record = provider(f)
	f.env.require("runtime/config").set("agent.requestsPerMinute", 1)
	prime(f, record)
	f.env.require("ui/panels/providers").editor(record); click(f, "TestConnection"); f.h.settle(0.5)
	check("the waiting test has a visible label and owns no second request", f.h.textOf(f.h.byName("TestConnection")) == "Waiting for limit"
		and not f.h.byName("TestConnection").Active and f.h.http.requestCount == 1)
	local open = f.env.require("ui/overlay").open; open[#open].close()
	f.h.sched.advance(61)
	check("a closed test cannot dispatch when the allowance returns", f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

case("live rate status survives full and incremental transcript replay", function()
	local f = F.ui(900, 650); local session = f.env.require("agent/session").newThread()
	session.busy = true
	session.emit("user", { text = "Wait for this response" })
	session.emit("request:start", { provider = "Rate fixture", providerId = "rate-fixture", model = "rate-fixture-model", attempt = 1 })
	session.emit("status", { text = "Waiting for request rate limit" })
	local view = f.env.require("ui/chat/view").new(f.host); view.attach(session); f.h.settle(0.3)
	check("full replay retains the current rate wait", workingText(f) == session.status)
	view.setVisible(false); view.setVisible(true); f.h.settle(0.3)
	check("returning to a hidden transcript retains the rate wait", workingText(f) == session.status)
	session.emit("status", { text = "Waiting for response" })
	check("admission replaces the waiting text", workingText(f) == "Waiting for response")
	session.busy = false; session.emit("status", { text = "Ready" }); f.h.settle(0.2)
	check("settlement removes transient working status", f.h.byName("Working") == nil)
	view.destroy(); f.healthy(); f.close()
end)

case("manual compaction keeps Stop available and cancelled rate waits preserve context", function()
	local f = F.new(); local record = provider(f); local config = f.env.require("runtime/config")
	config.set("ui.tutorial.seen", true); config.set("ui.communityInvite.disabled", true)
	config.set("agent.requestsPerMinute", 1)
	prime(f, record)
	local app = f.env.require("ui/app"); app.mount(); app.show("chat"); f.h.settle(0.2)
	local session = f.env.require("agent/session").current()
	for index = 1, 8 do
		session.ctx.pushUser("Question " .. index)
		session.ctx.pushAssistant({ content = string.rep("Earlier technical answer. ", 100) })
	end
	local original, before = session.ctx.messages, session.ctx.tokens()
	assert(session.compact()); f.h.settle(0.5)
	local stop = assert(f.h.byName("Stop", app.window.root))
	check("compaction waits visibly while keeping Stop usable", session.busy and session.status == "Waiting for request rate limit"
		and workingText(f, app.window.root) == session.status and stop.Visible and stop.Active and f.h.http.requestCount == 1)
	f.h.click(stop); f.h.settle(0.5)
	check("Stop releases the compaction worker and leaves history intact", not session.busy and session.status == "Ready"
		and session.ctx.messages == original and session.ctx.tokens() == before and session.ctx.compactions == 0)
	f.h.sched.advance(61)
	check("cancelled compaction cannot submit a later summary", f.h.http.requestCount == 1 and f.h.byName("WorkingStatus", app.window.root) == nil)
	f.healthy(); f.close()
end)

suite.finish()
