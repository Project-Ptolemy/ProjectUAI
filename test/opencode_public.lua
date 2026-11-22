-- Official public auth is dispatch-only and independent of optional CLI access.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local Z = require("opencode_catalog_fixture")
local suite = F.suite("OpenCode direct public API")
local check, case = suite.check, suite.case
local models = { "big-pickle", "mimo-v2.6-flash-free", "deepseek-v4.1-flash-free", "longcat-2.5-free", "iceman-free", "beam-free",
	"flint-40b-free", "nemotron-3.5-super-vl-free", "nemotron-3.5-lightning-free", "hy4-flash-free", "tidepool-alpha-free" }
local function recordFor(f)
	local record = f.env.require("provider/registry").blank("zen")
	record.baseUrl, record.model, record.apiKey = "https://opencode.ai/inference/openai/v1", "hy4-flash-free", ""
	return record
end
local function dispatchFixture()
	local f = F.new(); f.record = recordFor(f)
	f.config, f.clock = f.env.require("runtime/config"), f.env.require("runtime/clock")
	f.public, f.rate = f.env.require("provider/opencode_public"), f.env.require("runtime/inference_rate")
	f.sent, f.reads, f.accounted = {}, 0, 0
	f.env.require("runtime/dispose").add(f.env.require("runtime/request_accounting").dispatched:connect(function()
		f.accounted = f.accounted + 1
	end), "public admission fixture")
	f.h.http.handler = function(entry)
		if entry.method == "GET" then
			f.reads = f.reads + 1
			return { StatusCode = 200, Body = f.h.json.encode({ data = { Z.row(f.record.model) } }) }
		end
		local body = f.h.json.decode(entry.body)
		f.sent[#f.sent + 1] = { model = body.model, authorization = entry.headers.Authorization }
		return { StatusCode = 200, delay = f.responseDelay,
			Body = '{"choices":[{"message":{"content":"PONG"},"finish_reason":"stop"}]}' }
	end
	function f.complete(options, target)
		local request = { messages = { { role = "user", content = "PONG" } }, timeout = 90, attempts = 1 }
		for name, value in pairs(options or {}) do request[name] = value end
		return f.env.require("provider/openai").complete(target or f.record, request)
	end
	return f
end

case("current free Chat models can validate without initializing the bridge", function()
	local f = F.new(); local record = recordFor(f)
	local registry, public = f.env.require("provider/registry"), f.env.require("provider/opencode_public")
	f.loaded["net/bridge"] = { connected = function() error("public auth must not inspect a bridge") end }
	local rows = { Z.row("fixture-new-unsuffixed") }
	for _, model in ipairs(models) do rows[#rows + 1] = Z.row(model) end
	rows[#rows + 1] = Z.row("fixture-paid-free", { cost = { text = { input = { price = 1 }, output = { price = 2 } } } })
	rows[#rows + 1] = Z.row("jev-1.13-free", { kind = "decision", api = { systemone = { base_url = "https://opencode.ai/inference/systemone/v1" } } })
	Z.observe(f, record, rows)
	for _, model in ipairs(models) do
		record.model = model
		check("current exact model is eligible", public.available(record) and registry.opencodeKeyOptional(record))
		local ok = registry.validate(record)
		check("direct public model is valid with no stored key", ok)
	end
	record.model = "fixture-new-unsuffixed"
	check("an unseen name with explicit free Chat facts is eligible", public.available(record) and registry.opencodeKeyOptional(record))
	check("its free badge uses price facts", f.env.require("provider/models").isFree(record, record.model))
	for _, model in ipairs({ "cat-jam-free", "muse-spark-1.3-contributor-free", "jev-1.13-free", "deepseek-v4.1-flash", "fixture-free", "fixture-paid-free", "hy4-flash-free/paid" }) do
		record.model = model
		check("unknown, decision-only and paid ids receive no default key", not public.available(record) and public.defaultKey(record) == nil and not public.pending(record))
	end
	record.model = "fixture-paid-free"
	check("a free suffix cannot override paid catalog prices", not f.env.require("provider/models").isFree(record, record.model))
	f.healthy(); f.close()
end)

case("public auth is limited to ordinary HTTPS Chat routes and effective Chat bodies", function()
	local f = F.new(); local record = recordFor(f)
	local public, registry = f.env.require("provider/opencode_public"), f.env.require("provider/registry")
	local body = { model = record.model, messages = { { role = "user", content = "PONG" } } }
	for _, base in ipairs({ "https://opencode.ai/zen/v1", "https://opencode.ai/inference/v1", "https://opencode.ai/inference/openai/v1",
		"https://opencode.ai:443/inference/openai/v1", "https://opencode.ai/zen/v1/chat/completions", "https://opencode.ai/zen/v1/models" }) do
		record.baseUrl = base
		Z.observe(f, record)
		check("official alias sends the published token", registry.authHeaders(record, "", body).Authorization == "Bearer public")
	end
	for _, base in ipairs({ "http://opencode.ai/zen/v1", "https://opencode.ai./zen/v1", "https://opencode.ai:8443/zen/v1",
		"https://user:fixture@opencode.ai/zen/v1", "https://opencode.ai.evil.invalid/zen/v1", "https://opencode.ai/zen/v1?",
		"https://opencode.ai/zen/v1#", "https://opencode.ai/zen/v1?tenant=fixture", "https://opencode.ai/zen/v1/responses",
		"https://opencode.ai/inference/go/v1", "https://opencode.ai/zen/go/v1", "https://opencode.ai/custom/v1" }) do
		record.baseUrl = base
		check("custom semantics receive no public auth", not public.available(record, body) and next(registry.authHeaders(record, "", body)) == nil)
	end
	record.baseUrl = "https://opencode.ai/inference/openai/v1"
	Z.observe(f, record)
	for _, effective in ipairs({ { model = record.model, input = "PONG" }, { model = record.model, messages = {}, input = false },
		{ model = "gpt-6", messages = {} }, { model = record.model }, { model = record.model, messages = "invalid" } }) do
		check("Responses or conflicting dispatch bodies remain unauthenticated", public.defaultKey(record, effective) == nil)
	end
	f.healthy(); f.close()
end)

case("personal keys, paused policies, custom auth and preserved envelopes prevent fallback", function()
	local f = F.new(); local public = f.env.require("provider/opencode_public")
	local registry = f.env.require("provider/registry")
	local changes = { { apiKey = "fixture-private" }, { apiKey = "fixture-one\nfixture-two", keyPaused = { true, true } },
		{ apiKey = "fixture-private", keyMode = "single", selectedKey = 1, keyPaused = { true } },
		{ keyMode = "single" }, { credentialsOmitted = true }, { credentialStorageError = true },
		{ storedCredentials = { encoding = "unread", data = "preserved" } }, { authStyle = "none" }, { authStyle = "x-api-key" },
		{ wsUrl = "wss://opencode.ai/zen/v1" }, { query = { tenant = "fixture" } }, { query = "invalid" },
		{ headers = "invalid" }, { params = "invalid" }, { params = { model = "gpt-6" } } }
	for _, change in ipairs(changes) do
		local record = recordFor(f)
		Z.observe(f, record)
		for name, value in pairs(change) do record[name] = value end
		check("explicit saved policy excludes public fallback", not public.available(record))
		check("empty effective key never becomes public", registry.authHeaders(record, "").Authorization ~= "Bearer public")
	end
	for _, name in ipairs({ "Authorization", "Proxy-Authorization", "X-Api-Key", "X-Access-Token", "Authentication", "X-Secret",
		"X-Credential", "Cookie", "X-Org-Id", "OpenAI-Organization" }) do
		local record = recordFor(f); Z.observe(f, record); record.headers = { [name] = "fixture-custom-credential" }
		check("credential header excludes public injection", not public.available(record) and next(registry.authHeaders(record, "")) == nil)
	end
	local record = recordFor(f); record.headers = { ["X-Fixture"] = "retained" }
	Z.observe(f, record)
	check("noncredential headers allow public access", public.available(record))
	check("an explicit personal key takes precedence even for a conflicting body", registry.authHeaders(record, "fixture-explicit",
		{ model = "gpt-6", input = "PONG" }).Authorization == "Bearer fixture-explicit")
	f.healthy(); f.close()
end)

case("actual executor dispatch and tool replay keep the selected model and never store public", function()
	for _, model in ipairs(models) do
		local f = F.new(); local record = recordFor(f); record.model = model
		Z.observe(f, record)
		local openai, headers = f.env.require("provider/openai"), f.env.require("net/headers")
		local calls, session = 0, nil
		f.h.http.handler = function(entry)
			calls = calls + 1
			local body = f.h.json.decode(entry.body)
			check("direct request carries the exact selected model and public auth", entry.url == record.baseUrl .. "/chat/completions"
				and body.model == model and headers.get(entry.headers, "Authorization") == "Bearer public")
			local current = headers.get(entry.headers, "x-opencode-session")
			check("replay retains the same session", current and (not session or current == session)); session = current
			if calls == 2 then
				check("reasoning and tool identities replay exactly", body.messages[#body.messages - 1].tool_calls[1].id == "call-fixture"
					and body.messages[#body.messages - 1].reasoning_content == "Use the synthetic UAI tool."
					and body.messages[#body.messages].tool_call_id == "call-fixture" and body.messages[#body.messages].content == "PONG")
			end
			local message = calls == 1 and { role = "assistant", content = "", tool_calls = { {
				id = "call-fixture", type = "function", ["function"] = { name = "uai_ping", arguments = '{"message":"PONG"}' },
			} } } or { role = "assistant", content = "PONG" }
			return { StatusCode = 200, Body = f.h.json.encode({ choices = { { message = message, finish_reason = calls == 1 and "tool_calls" or "stop" } } }) }
		end
		local history = { { role = "user", content = "Call uai_ping with message PONG." } }
		local tools = { { type = "function", ["function"] = { name = "uai_ping", description = "Synthetic echo",
			parameters = { type = "object", properties = { message = { type = "string" } }, required = { "message" } } } } }
		local first = f.run(function() return openai.complete(record, { messages = history, tools = tools, stream = true }) end)
		check("the UAI tool is returned to its normal caller", first and first.toolCalls[1].id == "call-fixture")
		history[#history + 1] = { role = "assistant", content = "", reasoning_content = "Use the synthetic UAI tool.", toolCalls = first.toolCalls }
		history[#history + 1] = { role = "tool", tool_call_id = "call-fixture", content = "PONG" }
		local final = f.run(function() return openai.complete(record, { messages = history, tools = tools, stream = true }) end)
		check("two actual calls return the replayed result", final and final.content == "PONG" and calls == 2)
		check("public is never a saved credential or key entry", record.apiKey == "" and #f.env.require("runtime/provider_keys").keys(record) == 0
			and not f.h.json.encode(record):find("Bearer public", 1, true))
		f.healthy(); f.close()
	end
end)

case("current Chat refusals do not start an unauthenticated Responses recovery", function()
	for _, response in ipairs({ { StatusCode = 403, Body = '{"error":{"type":"FreeTierError"}}' },
		{ StatusCode = 400, Body = '{"error":{"type":"ModelProtocolUnsupported"}}' } }) do
		local f = F.new(); local record = recordFor(f); local calls = 0
		Z.observe(f, record)
		f.h.http.handler = function(entry) calls = calls + 1; return response end
		local result, why, res = f.run(function() return f.env.require("provider/openai").complete(record,
			{ messages = { { role = "user", content = "PONG" } }, attempts = 1 }) end)
		check("the original Chat refusal is preserved without a second lane", result == nil and why and res.status == response.StatusCode and calls == 1)
		check("Responses is ineligible for the reviewed Chat model", not f.env.require("provider/responses").eligible(record))
		f.healthy(); f.close()
	end
end)

case("compatibility declarations are scoped and isolated between Chat and Responses bodies", function()
	local f = F.new(); local record = recordFor(f)
	local openai, responses = f.env.require("provider/openai"), f.env.require("provider/responses")
	local request = { messages = { { role = "user", content = "PONG" } } }
	local first = openai.buildBody(record, request)
	first.tools[1]["function"].description = "Changed local body"
	first.tools[1]["function"].parameters.properties.command.type = "number"
	local second = openai.buildBody(record, request)
	check("Chat declarations do not share mutable schemas", second.tools[1]["function"].description:find("does not execute in Roblox", 1, true)
		and second.tools[1]["function"].parameters.properties.command.type == "string")
	local translated = responses.buildBody(record, request)
	translated.tools[1].parameters.properties.command.type = "boolean"
	check("Responses translations leave Chat schemas unchanged", openai.buildBody(record, request).tools[1]["function"].parameters.properties.command.type == "string")
	for _, base in ipairs({ "https://opencode.ai/inference/go/v1", "https://opencode.ai/custom/v1", "http://opencode.ai/zen/v1",
		"https://opencode.ai:8443/zen/v1", "https://opencode.ai./zen/v1", "https://opencode.ai/Zen/v1", "https://fixture.invalid/v1" }) do
		record.baseUrl = base
		local chat, other = openai.buildBody(record, request), responses.buildBody(record, request)
		check("unrelated protocols have no compatibility declarations", not chat.tools and not other.tools)
	end
	record.apiKey = "fixture-personal"
	for _, base in ipairs({ "https://opencode.ai/custom/v1", "http://opencode.ai/zen/v1", "https://opencode.ai:8443/zen/v1", "https://opencode.ai./zen/v1", "https://opencode.ai/Zen/v1" }) do
		record.baseUrl = base
		check("unrelated routes cannot switch to official Zen Responses", not responses.eligible(record) and responses.endpointFor(record) == nil)
	end
	f.healthy(); f.close()
end)

case("all price tiers, modalities and cache prices must be explicitly zero", function()
	local f = F.new(); local record = recordFor(f); local public = f.env.require("provider/opencode_public")
	local zero = { input = 0, output = 0, cache = { read = 0, write = 0 } }
	for _, cost in ipairs({ { text = zero, image = zero }, { zero, { input = { price = 0, cache = { read = 0 } }, output = { price = 0 } } } }) do
		Z.observe(f, record, { Z.row(record.model, { cost = cost }) })
		check("complete zero-price catalog formats authorize Chat", public.available(record))
	end
	for _, cost in ipairs({ {}, "invalid", { text = { input = 0 } }, { text = { input = "0", output = 0 } },
		{ text = { input = { price = 0, cache = { read = 1 } }, output = { price = 0 } } },
		{ text = { input = 0, output = { price = 0, cache = { write = 1 } } } },
		{ text = zero, image = { input = 0, output = 1 } }, { zero, { input = 1, output = 0 } },
		{ [1] = zero, [3] = { input = 1, output = 0 } }, { [1] = zero, text = { input = 1, output = 0 } },
		{ [1] = zero, extra = { input = 1, output = 0 } }, { text = zero, [2] = zero } }) do
		Z.observe(f, record, { Z.row(record.model, { cost = cost }) })
		check("partial, paid and malformed cost entries stay ineligible", not public.available(record) and not public.pending(record))
	end
	f.healthy(); f.close()
end)

case("catalog provenance, duplicate ids and advertised APIs cannot grant ambiguous access", function()
	local f = F.new(); local record = recordFor(f); local public = f.env.require("provider/opencode_public")
	local url = f.env.require("provider/registry").endpoint(record, "/models")
	Z.observe(f, record)
	for _, source in ipairs({ "https://fixture.invalid/models", "https://opencode.ai/zen/v1/models", url .. "?", url .. "#" }) do
		check("another source cannot replace verified metadata", not public.observe(record, source, { data = { Z.row(record.model) } }) and public.available(record))
	end
	for _, payload in ipairs({ { data = {} }, { data = { [1] = Z.row(record.model), [3] = Z.row("other") } },
		{ data = { Z.row(record.model), extra = Z.row("other") } }, { data = { Z.row(record.model) }, error = "ambiguous" } }) do
		check("malformed official refresh is rejected", not public.observe(record, url, payload))
		check("malformed refresh removes the older evidence", not public.available(record) and public.pending(record))
		Z.observe(f, record)
	end
	Z.observe(f, record, { Z.row(record.model), Z.row(record.model) })
	check("duplicate IDs receive no public evidence or pending exception", public.info(record) == nil and not public.available(record) and not public.pending(record))
	for _, opts in ipairs({ { kind = "decision" }, { api = {} },
		{ api = { ["chat-completions"] = { base_url = "https://fixture.invalid/v1" } } },
		{ api = { ["chat-completions"] = { base_url = "https://opencode.ai/inference/go/v1" } } },
		{ api = { responses = { base_url = "https://opencode.ai/inference/openai/v1" } }, protocol = "responses" } }) do
		Z.observe(f, record, { Z.row(record.model, opts) })
		check("explicitly incompatible APIs receive no public Chat auth", not public.available(record) and public.defaultKey(record) == nil)
	end
	f.healthy(); f.close()
end)

case("fresh metadata is detached, connection-scoped, bounded and invalidated by owner", function()
	local f = F.new(); local record = recordFor(f); local public = f.env.require("provider/opencode_public")
	local util = f.env.require("runtime/util")
	Z.observe(f, record)
	local copy = assert(public.info(record)); copy.public, copy.free = false, false
	check("caller mutation cannot alter retained facts", public.available(record) and public.info(record).free)
	local clone = util.deepCopy(record); clone.id = "another-owner"
	check("the same full connection can share evidence", public.available(clone))
	public.invalidate(clone.id)
	check("owner invalidation removes shared evidence", not public.current(record) and not public.current(clone))
	for _, change in ipairs({ { headers = { ["X-Fixture"] = "changed" } }, { params = { max_tokens = 16 } },
		{ keyMode = "single" }, { apiKey = "fixture-personal" }, { storedCredentials = {} }, { credentialsOmitted = true } }) do
		Z.observe(f, record)
		local changed = util.deepCopy(record)
		for name, value in pairs(change) do changed[name] = value end
		check("changed connection policy inherits no catalog facts", public.info(changed) == nil and not public.available(changed))
	end
	local cyclic = util.copy(record); cyclic.params = {}; cyclic.params.loop = cyclic.params
	check("cyclic custom parameters cannot gain public access", not public.credentials(cyclic) and not public.pending(cyclic))
	public.invalidate()
	for index = 1, 33 do
		local nextRecord = util.deepCopy(record); nextRecord.headers = { ["X-Fixture"] = tostring(index) }
		Z.observe(f, nextRecord)
		if index == 1 then clone = nextRecord end
	end
	check("oldest excess catalog scope is evicted", not public.current(clone))
	f.healthy(); f.close()
end)

case("TTL expiry and credential access gates stop public admission", function()
	local f = F.new(); local record = recordFor(f); local public = f.env.require("provider/opencode_public")
	Z.observe(f, record)
	f.h.sched.advance(601)
	check("expired facts authorize no token", not public.available(record) and public.defaultKey(record) == nil and public.pending(record))
	Z.observe(f, record)
	local config = f.env.require("runtime/config"); local vaultStatus, accessProblem = config.vaultStatus, config.accessProblem
	for _, state in ipairs({ { locked = true }, { busy = true }, { required = true } }) do
		config.vaultStatus = function() return state end
		config.accessProblem = function() return state.required and "password setup required" or nil end
		check("access challenge cannot become a pending key exception", not public.available(record) and not public.pending(record))
		local ok = f.run(function() return public.ensure(record) end)
		check("access challenge performs no catalog read", not ok and f.h.http.requestCount == 0)
	end
	config.vaultStatus, config.accessProblem = vaultStatus, accessProblem
	check("restored access can reuse still-fresh facts", public.available(record))
	f.healthy(); f.close()
end)

case("queued public expiry releases admission while an explicit public key stays keyed", function()
	local f = dispatchFixture(); Z.observe(f, f.record)
	f.h.sched.advance(599.5); f.config.set("agent.requestsPerMinute", 1)
	assert(f.run(f.complete, 0.1))
	local result, why, done, keyed
	local personal = f.env.require("runtime/util").deepCopy(f.record)
	personal.apiKey, personal.model = "public", "fixture-manual-not-in-catalog"
	f.h.sched.spawn(function() result, why = f.complete(); done = true end)
	f.h.sched.spawn(function() keyed = f.complete(nil, personal) end)
	f.h.sched.advance(0.1)
	check("fresh public and keyed waiters retain order without a native worker", not done and not keyed
		and f.rate.state().queued == 2 and f.env.require("net/http").workers() == 0 and #f.sent == 1)
	f.h.sched.advance(0.5)
	check("expired queued auth stops with guidance and no attempt", done and result == nil and why ~= "aborted"
		and why:find("Fetch the model list", 1, true) and f.reads == 0 and #f.sent == 1 and f.accounted == 1
		and f.rate.state().queued == 1 and f.rate.state().held == 0 and f.rate.state().tracked == 1)
	f.h.sched.advance(60.1)
	check("an unlisted model with an explicit key named public remains dispatchable", keyed and keyed.content == "PONG"
		and #f.sent == 2 and f.sent[2].model == personal.model and f.sent[2].authorization == "Bearer public"
		and f.accounted == 2 and f.rate.state().queued == 0 and f.rate.state().held == 0)
	Z.observe(f, f.record)
	local refreshed = f.run(f.complete, 61)
	check("fresh metadata can rejoin fair admission without a leaked reservation", refreshed and refreshed.content == "PONG"
		and #f.sent == 3 and f.accounted == 3 and f.reads == 0 and f.record.apiKey == ""
		and f.rate.state().queued == 0 and f.rate.state().held == 0 and f.rate.state().tracked == 1)
	f.healthy(); f.close()
end)

case("public catalog changes after reservation cannot reach native dispatch", function()
	for _, change in ipairs({ "expire", "invalidate", "paid", "decision", "missing", "headers" }) do
		local f = dispatchFixture(); Z.observe(f, f.record)
		if change == "expire" then f.h.sched.advance(599.8) end
		local spawn, delayed = f.clock.spawn, false
		f.clock.spawn = function(fn)
			if not delayed and f.rate.state().held > 0 then
				delayed = true
				return f.h.sched.delay(0.3, function()
					if change == "invalidate" then f.public.invalidate(f.record)
					elseif change == "paid" then Z.observe(f, f.record, { Z.row(f.record.model, { cost = { text = { input = 1, output = 1 } } }) })
					elseif change == "decision" then Z.observe(f, f.record, { Z.row(f.record.model, { kind = "decision" }) })
					elseif change == "missing" then Z.observe(f, f.record, { Z.row("another-catalog-model") })
					elseif change == "headers" then f.record.headers = { ["X-Secret"] = "fixture-changed-policy" } end
					fn()
				end)
			end
			return spawn(fn)
		end
		local result, why = f.run(f.complete, 1)
		f.clock.spawn = spawn
		check("the held worker rechecks current public eligibility", delayed and not result and why ~= "aborted"
			and why:find("expired or changed before dispatch", 1, true) and not f.public.available(f.record))
		check("failed public commit releases all slots without accounting or catalog reads", #f.sent == 0 and f.reads == 0
			and f.accounted == 0 and f.h.http.requestCount == 0 and f.rate.state().tracked == 0
			and f.rate.state().queued == 0 and f.rate.state().held == 0 and f.env.require("net/http").workers() == 0)
		f.healthy(); f.close()
	end
end)

case("public eligibility diagnostics never replace Stop owner or access cancellation", function()
	for _, cancellation in ipairs({ "stop", "owner", "access", "access-reopened" }) do
		local f = dispatchFixture(); local registry = f.env.require("provider/registry")
		assert(registry.save(f.record)); Z.observe(f, f.record)
		f.config.set("agent.requestsPerMinute", 1); assert(f.run(f.complete))
		local vaultStatus, stopped, changed = f.config.vaultStatus, false, false
		local result, why = f.run(function() return f.complete({ aborted = function() return stopped end,
			onRetry = function(info)
				if info.rateLimit and info.phase == "waiting" and not changed then
					changed = true; f.public.invalidate(f.record)
					if cancellation == "stop" then stopped = true
					elseif cancellation == "owner" then assert(registry.remove(f.record.id))
					else f.config.vaultStatus = function() return { locked = true } end end
				elseif info.rateLimit and info.phase == "cancelled" and cancellation == "access-reopened" then
					f.config.vaultStatus = vaultStatus
				end
			end }) end)
		f.config.vaultStatus = vaultStatus
		local state = f.rate.state()
		local diagnostic = string.format("%s cancellation preserves its cause (changed=%s; error=%s; sent=%d; reads=%d; accounted=%d; queued=%d; held=%d)",
			cancellation, tostring(changed), tostring(why):sub(1, 180), #f.sent, f.reads, f.accounted, state.queued, state.held)
		local expected = why == "aborted"
		if cancellation == "access" then
			expected = type(why) == "string" and why:find("vault_required:", 1, true) == 1
				and why:find("Unlock Project UAI with your master password", 1, true) ~= nil
		end
		check(diagnostic, changed and not result and expected and f.env.require("net/http").terminal(why)
			and #f.sent == 1 and f.reads == 0 and f.accounted == 1 and state.queued == 0 and state.held == 0)
		f.healthy(); f.close()
	end
end)

case("catalog cancellation settling after the caller deadline stays terminal", function()
	local f = dispatchFixture(); Z.observe(f, f.record)
	f.config.set("agent.requestsPerMinute", 1); assert(f.run(f.complete))
	local deadline = f.clock.ms() + 1000
	local phases, capturedBeforeDeadline, retries = {}, false, 0
	local result, why = f.run(function() return f.complete({ deadlineMs = deadline,
		onRetry = function(info)
			if not info.rateLimit then retries = retries + 1; return end
			phases[#phases + 1] = info.phase
			if info.phase == "waiting" then f.public.invalidate(f.record)
			elseif info.phase == "cancelled" then
				capturedBeforeDeadline = f.clock.ms() < deadline
				f.clock.wait(1.1)
			end
		end }) end, 1.5)
	check("expired caller budget cannot become nonterminal public guidance", capturedBeforeDeadline and f.clock.ms() >= deadline
		and not result and why == "aborted" and f.env.require("net/http").terminal(why))
	check("late cancellation releases admission without any dispatch or retry", #phases == 2 and phases[1] == "waiting" and phases[2] == "cancelled"
		and retries == 0 and #f.sent == 1 and f.h.http.requestCount == 1 and f.reads == 0 and f.accounted == 1
		and f.rate.state().tracked == 1 and f.rate.state().queued == 0 and f.rate.state().held == 0)
	f.healthy(); f.close()
end)

case("catalog expiry after POST preserves the already dispatched result and count", function()
	local f = dispatchFixture(); Z.observe(f, f.record)
	f.h.sched.advance(599.8); f.responseDelay = 0.6
	local result = f.run(f.complete, 1.2)
	check("a public request crossing TTL completes without cancellation or replay", result and result.content == "PONG"
		and not f.public.available(f.record) and #f.sent == 1 and f.reads == 0 and f.accounted == 1
		and f.rate.state().tracked == 1 and f.rate.state().held == 0 and f.env.require("net/http").workers() == 0)
	f.healthy(); f.close()
end)

case("first public inference verifies an unseen model with GET before its exact POST", function()
	local f = F.new(); local record = recordFor(f); record.model = "fixture-new-unsuffixed"
	local public, registry = f.env.require("provider/opencode_public"), f.env.require("provider/registry")
	check("pending verification permits a reviewed connection", public.pending(record) and not public.available(record) and registry.validate(record))
	local reads, posts = 0, 0
	f.h.http.handler = function(entry)
		if entry.method == "GET" then
			reads = reads + 1
			check("preflight reads the official model catalog", entry.url == record.baseUrl .. "/models" and posts == 0)
			return { StatusCode = 200, Body = f.h.json.encode({ data = { Z.row(record.model) } }) }
		end
		posts = posts + 1
		local body = f.h.json.decode(entry.body)
		check("POST follows explicit evidence and keeps model and public auth", reads == 1 and public.available(record)
			and body.model == record.model and entry.headers.Authorization == "Bearer public")
		return { StatusCode = 200, Body = '{"choices":[{"message":{"content":"PONG"},"finish_reason":"stop"}]}' }
	end
	local result = f.run(function() return f.env.require("provider/openai").complete(record, { messages = { { role = "user", content = "PONG" } } }) end)
	check("verified first inference succeeds without a stored token", result and result.content == "PONG" and reads == 1 and posts == 1 and record.apiKey == "")
	f.healthy(); f.close()
end)

case("unknown paid and decision selections fail before POST without changing model", function()
	for _, selected in ipairs({ "fixture-unknown-free", "fixture-paid-free", "jev-1.13-free" }) do
		local f = F.new(); local record = recordFor(f); record.model = selected
		local reads, posts = 0, 0
		f.h.http.handler = function(entry)
			if entry.method ~= "GET" then posts = posts + 1; error("unverified model must not be dispatched") end
			reads = reads + 1
			return { StatusCode = 200, Body = f.h.json.encode({ data = { Z.row("fixture-known-chat"),
				Z.row("fixture-paid-free", { cost = { text = { input = 1, output = 1 } } }),
				Z.row("jev-1.13-free", { kind = "decision", api = { systemone = { base_url = "https://opencode.ai/inference/systemone/v1" } } }) } }) }
		end
		local result, why = f.run(function() return f.env.require("provider/openai").complete(record, { messages = { { role = "user", content = "PONG" } } }) end)
		check("only discovery occurs and the original selection survives", not result and why and reads == 1 and posts == 0 and record.model == selected)
		check("a fresh negative fact removes the key exception", not f.env.require("provider/registry").opencodeKeyOptional(record))
		f.healthy(); f.close()
	end
end)

case("effective request overrides cannot borrow public auth from a different model", function()
	for _, override in ipairs({ "request", "connection" }) do
		local f = F.new(); local record = recordFor(f); Z.observe(f, record)
		if override == "connection" then record.params = { model = "fixture-paid-model" } end
		local result, why = f.run(function() return f.env.require("provider/openai").complete(record, {
			messages = { { role = "user", content = "PONG" } }, extra = override == "request" and { model = "fixture-paid-model" } or nil,
		}) end)
		check("conflicting effective body stops before discovery or inference", not result and why and f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end
end)

case("API discovery overrides optional CLI id lists and excludes explicit decision APIs", function()
	local f = F.new(); local record = recordFor(f); record.model, record.models = "jev-1.13-free", { "jev-1.13-free" }
	f.loaded["net/bridge"] = { opencodeStatus = function() return { enabled = true, available = true } end,
		opencodeModels = function() error("Zen API metadata must not come from CLI IDs") end }
	f.h.http.handler = function(entry)
		check("discovery uses official HTTPS catalog", entry.method == "GET" and entry.url == record.baseUrl .. "/models")
		return { StatusCode = 200, Body = f.h.json.encode({ data = { Z.row("fixture-chat"),
			{ id = "fixture-untyped" }, Z.row("jev-1.13-free", { kind = "decision" }), Z.row("fixture-embedding-free", { kind = "embedding" }) } }) }
	end
	local discovered, note = f.run(function() return f.env.require("provider/models").discover(record, { force = true }) end)
	check("documented non-chat entries are excluded without guessing names", #discovered == 2 and discovered[1] == "fixture-chat"
		and discovered[2] == "fixture-untyped" and note:find("2 non-chat entries hidden", 1, true))
	check("manual saved choice remains visible", f.env.require("provider/models").list(record)[1] == "jev-1.13-free" and record.model == "jev-1.13-free")
	check("decision selection has a protocol diagnostic", f.env.require("provider/registry").protocolProblem(record):find("non-chat API", 1, true))
	local catalog = f.env.require("provider/model_catalog")
	for _, source in ipairs({ "https://opencode.ai:8443/zen/v1/models", "https://opencode.ai/custom/v1/models", "https://opencode.ai/zen/v1/models?tenant=fixture" }) do
		check("custom catalog semantics retain their original rows", catalog.accepts(source, { type = "decision" }))
	end
	f.healthy(); f.close()
end)

case("catalog preflight spends the caller deadline and preserves Stop", function()
	for _, stop in ipairs({ false, true }) do
		local f = F.new(); local record = recordFor(f); local cancelled, reads, posts = false, 0, 0
		local deadlines = {}; local http = f.env.require("net/http"); local send = http.send
		http.send = function(spec) deadlines[#deadlines + 1] = spec.deadlineMs; return send(spec) end
		f.h.http.handler = function(entry)
			if entry.method == "GET" then reads = reads + 1; return { StatusCode = 200, delay = 0.6, Body = f.h.json.encode({ data = { Z.row(record.model) } }) } end
			posts = posts + 1
			return { StatusCode = 200, delay = 0.6, Body = '{"choices":[{"message":{"content":"PONG"},"finish_reason":"stop"}]}' }
		end
		if stop then f.h.sched.delay(0.2, function() cancelled = true end) end
		local result, why = f.run(function() return f.env.require("provider/openai").complete(record, {
			messages = { { role = "user", content = "PONG" } }, timeout = 1, aborted = function() return cancelled end,
		}) end, 1.3)
		if stop then check("Stop during catalog read prevents inference", not result and why == "aborted" and reads == 1 and posts == 0)
		else check("catalog read cannot grant another full inference budget", not result and http.terminal(why) and reads == 1 and posts == 1
			and #deadlines == 2 and deadlines[1] == deadlines[2]) end
		f.h.sched.advance(1); f.healthy(); f.close()
	end
	local f = F.new(); local record = recordFor(f)
	local result, why = f.run(function() return f.env.require("provider/openai").complete(record, {
		messages = { { role = "user", content = "PONG" } }, deadlineMs = f.env.require("runtime/clock").ms(),
	}) end)
	check("an expired caller budget remains terminal before discovery", not result and f.env.require("net/http").terminal(why) and f.h.http.requestCount == 0)
	f.healthy(); f.close()
end)

case("expired personal-key protocol lessons refresh Chat facts and retain manual keyed ids", function()
	local f = F.new(); local record = recordFor(f); record.apiKey, record.repairs = "fixture-personal", { "responses_protocol" }
	local reads, chats, responses = 0, 0, 0
	f.h.http.handler = function(entry)
		if entry.method == "GET" then reads = reads + 1; return { StatusCode = 200, Body = f.h.json.encode({ data = { Z.row(record.model) } }) } end
		if entry.url:find("/responses", 1, true) then responses = responses + 1 else chats = chats + 1 end
		return { StatusCode = 200, Body = '{"choices":[{"message":{"content":"PONG"},"finish_reason":"stop"}]}' }
	end
	local function complete() return f.run(function() return f.env.require("provider/openai").complete(record, { messages = { { role = "user", content = "PONG" } } }) end) end
	check("a saved stale Responses lesson first fetches Chat-only facts", complete() and reads == 1 and chats == 1 and responses == 0)
	f.h.sched.advance(601)
	check("TTL expiry refreshes personal-key route facts again", complete() and reads == 2 and chats == 2 and responses == 0)
	record.model = "fixture-manual-response-model"
	record.repairScope = f.env.require("provider/registry").compatibilityKey(record)
	Z.observe(f, record, { Z.row("another-catalog-model") })
	f.h.http.handler = function(entry)
		check("fresh missing manual ID preserves its explicit keyed route", entry.method == "POST" and entry.url:find("/responses", 1, true)
			and f.h.json.decode(entry.body).model == record.model and entry.headers.Authorization == "Bearer fixture-personal")
		return { StatusCode = 200, Body = '{"object":"response","status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"PONG"}]}]}' }
	end
	check("unlisted manually entered keyed model can still use its saved route", complete().content == "PONG")
	f.healthy(); f.close()
end)

case("mixed compatibility tool batches preserve ids and refuse absent host tools", function()
	local f = F.new(); local record = recordFor(f); Z.observe(f, record); f.tools({})
	local echoes = 0
	assert(f.registry.register({ name = "uai_ping", risk = "read", run = function() echoes = echoes + 1; return "PONG" end }))
	local calls = {}
	for index, name in ipairs({ "uai_ping", "bash", "read", "edit", "glob", "grep", "list", "shell" }) do
		calls[#calls + 1] = { id = "mixed-" .. index, type = "function", ["function"] = { name = name, arguments = '{"message":"PONG"}' } }
	end
	f.h.http.handler = function() return { StatusCode = 200, Body = f.h.json.encode({ choices = { {
		message = { role = "assistant", content = "", tool_calls = calls }, finish_reason = "tool_calls" } } }) } end
	local result = f.run(function() return f.env.require("provider/openai").complete(record, { messages = { { role = "user", content = "Call uai_ping." } } }) end)
	check("all eight upstream calls reach the normal tool runner", result and #result.toolCalls == 8 and echoes == 0)
	local outcomes = f.run(function() return f.registry.runAll(result.toolCalls, { env = f.env, session = {}, aborted = function() return false end }) end)
	check("only the registered synthetic UAI tool executes", echoes == 1 and outcomes[1].ok and outcomes[1].text == "PONG")
	for index = 2, 8 do check("absent host declaration returns a matching refusal", outcomes[index].id == "mixed-" .. index
		and not outcomes[index].ok and outcomes[index].error == "unknown tool") end
	f.healthy(); f.close()
end)

suite.finish()
