-- Relay waiters must not consume the native slots needed to poll their jobs.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock, json = require("env"), require("json")
local desktop = require("automatic_bridge_fixture")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end

local h = envMock.new()
local app = assert(h.boot()); require("password_fixture")(h, app); h.settle(0.5)
app.config.set("bridge.autoDiscover", false)
app.config.set("relay.mode", "off")
local http = app.env.require("net/http")
local clock = app.env.require("runtime/clock")
local jobs, submissions, peak, direct, deletes = {}, 0, 0, 0, 0
h.http.handler = function(req)
	peak = math.max(peak, http.workers())
	if req.url:find("/api/hello", 1, true) then
		return { StatusCode = 200, Body = '{"protocol":2,"instance":"concurrent-bridge"}', delay = 0.05 }
	elseif req.url:find("/api/agent/inbox", 1, true) then
		return { StatusCode = 200, Body = '{"commands":[]}', delay = 18 }
	elseif req.url:find("/api/agent/events", 1, true) then
		return { StatusCode = 204, Body = "", delay = 0.05 }
	elseif req.url:match("/api/inference$") then
		local input = json.decode(req.body)
		submissions = submissions + 1
		jobs[input.id] = jobs[input.id] or { readyAt = clock.ms() + 15000 }
		return { StatusCode = 202, Body = json.encode({ id = input.id, state = "running" }), delay = 0.05 }
	end
	local id = req.url:match("/api/inference/([^?]+)")
	if id then
		if req.method == "DELETE" then deletes = deletes + 1; return { StatusCode = 200, Body = "{}" } end
		assert(jobs[id], "poll owns an accepted job")
		local completed = clock.ms() >= jobs[id].readyAt
		return { StatusCode = 200, delay = 0.05, Body = json.encode({ id = id,
			state = completed and "completed" or "running", status = 200,
			body = completed and "Finished once" or nil }) }
	end
	direct = direct + 1
	return { StatusCode = 200, Body = "direct", delay = 0.5 }
end
desktop.connect(h, app, { instance = "concurrent-bridge" })
check("authenticated bridge selects Web", app.bridge.online and app.config.get("bridge.runtime") == "web")

local results, errors = {}, {}
for index = 1, 10 do
	h.sched.spawn(function()
		results[index], errors[index] = http.send({ url = "https://provider.invalid/v1/chat/completions",
			method = "POST", body = "{}", relay = true, timeout = 1, deadlineMs = clock.ms() + 500, attempts = 3 })
	end)
end
h.settle(4)
check("ten parallel relay jobs start while the inbox is open", submissions == 10 and http.relayWorkers() == 10)
check("waiting jobs do not consume native connection slots", http.workers() < http.relayWorkers() and peak <= http.limits.workers)
check("active inference does not disconnect a healthy bridge", app.bridge.online and app.config.get("bridge.runtime") == "web")
check("local deadlines do not terminate waiting relay jobs", next(results) == nil and next(errors) == nil)
h.settle(17)
local completed = 0
for index = 1, 10 do
	if results[index] and results[index].ok and results[index].body == "Finished once" and results[index].via == "web" then completed = completed + 1 end
end
check("all concurrent replies complete through the bridge", completed == 10 and next(errors) == nil)
check("polling never resubmits inference or falls back to the provider", submissions == 10 and direct == 0 and deletes == 0)
check("finished jobs release relay ownership", http.relayWorkers() == 0)

app.bridge.stop(); h.settle(19)
check("completed native calls release their slots", http.workers() == 0)
for index = 1, http.limits.workers do
	h.sched.spawn(function() http.request({ url = "https://fixture.invalid/slow", timeout = 2, silent = true }) end)
end
h.settle(0.05)
local queued, cancelled, cancelError, stop = nil, nil, nil, false
h.sched.spawn(function() queued = http.request({ url = "http://127.0.0.1/control", timeout = 2, silent = true, waitForSlot = true }) end)
h.sched.spawn(function() cancelled, cancelError = http.request({ url = "http://127.0.0.1/cancelled", timeout = 2,
	silent = true, waitForSlot = true, aborted = function() return stop end }) end)
h.settle(0.05); stop = true; h.settle(1.2)
check("a local control call waits for capacity and then dispatches", queued and queued.ok and direct == http.limits.workers + 1)
check("a cancelled capacity waiter never dispatches", cancelled == nil and cancelError == "aborted")
check("native and relay ownership return to zero", http.workers() == 0 and http.relayWorkers() == 0)
app.destroy(); h.settle(0.5)
check("concurrent bridge cleanup has no asynchronous errors", #h.errors() == 0)
print("bridge concurrency: " .. passed .. " checks passed")
