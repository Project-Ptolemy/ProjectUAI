-- Bundled desktop capability discovery and cancellation; no live server or key.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local h = envMock.new()
local ready, delay, requests = true, 0, 0
h.http.handler = function(req)
	if req.url:find("/api/hello", 1, true) then
		return { StatusCode = 200, Body = json.encode({ protocol = 2, capabilities = {
			opencode = { schema = 1, enabled = true, available = ready, state = ready and "ready" or "missing", version = "fixture-cli" },
		} }) }
	end
	if req.url:find("/api/opencode/models", 1, true) then
		requests = requests + 1
		check("model list uses bridge auth only", req.headers.Authorization == "Bearer fixture-token" and req.headers["x-api-key"] == nil)
		return { StatusCode = 200, Body = '{"data":[{"id":"fixture-free"}]}', delay = delay }
	end
	if req.url:find("/api/agent/inbox", 1, true) then return { StatusCode = 200, Body = '{"commands":[]}' } end
	return { StatusCode = 204, Body = "" }
end
local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.3)
app.config.set("bridge.token", "fixture-token")
app.config.set("bridge.enabled", true); h.settle(0.5)
check("authenticated hello advertises native CLI", app.bridge.opencodeStatus().available and app.bridge.opencodeStatus().version == "fixture-cli")
local result, why
h.sched.spawn(function() result, why = app.bridge.opencodeModels() end); h.settle(0.2)
check("authenticated native catalog returns exact models", result and result.data[1].id == "fixture-free" and why == nil)
delay = 1
h.sched.spawn(function() result, why = app.bridge.opencodeModels() end); h.settle(0.1)
app.config.set("bridge.token", "replacement-token"); h.settle(1.2)
check("connection changes discard pending model response", result == nil and tostring(why):find("aborted", 1, true))
ready = false; h.settle(5)
check("CLI shutdown invalidates availability", not app.bridge.opencodeStatus().available)
local before = requests
result, why = app.bridge.opencodeModels()
check("missing CLI explains optional desktop path and mobile relay", not result and requests == before and why:find("UAI Relay app", 1, true) and why:find("discord.gg/9xYyyYuKap", 1, true))
app.bridge.stop()
check("disconnect clears cached capability", app.bridge.opencodeStatus().state == "disconnected")
app.destroy(); h.settle(1)
check("callbacks release without errors", #h.errors() == 0)
print("OpenCode bridge: " .. passed .. " assertions")
