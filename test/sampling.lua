-- Focused temperature policy and refusal recovery through real adapters.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider sampling compatibility")
local case, check = suite.case, suite.check

local function fixture(api)
	local f = F.new()
	local record = f.env.require("provider/registry").blank("custom")
	record.id, record.label = "sampling-fixture", "Sampling fixture"
	record.api, record.baseUrl, record.model = api == "responses" and "openai" or api, "https://sampling.fixture/v1", "sampling-model"
	if api == "responses" then
		record.baseUrl, record.model = "https://api.openai.com/v1", "gpt-6-sol"
		-- Disable reasoning so this fixture sends temperature before the refusal.
		record.params = { reasoning = { effort = "none" } }
	end
	record.apiKey, record.authStyle = "fixture-key", "bearer"
	return f, record
end
local function request()
	return { messages = { { role = "user", content = "hello" } }, stream = false, temperature = 0.2, attempts = 1, maxTokens = 32 }
end
local function reply(f, api)
	local body
	if api == "anthropic" then
		body = { type = "message", role = "assistant", content = { { type = "text", text = "ready" } }, stop_reason = "end_turn" }
	elseif api == "responses" then
		body = { object = "response", id = "resp-sampling-fixture", model = "gpt-6-sol", status = "completed",
			output = { { type = "message", id = "msg-sampling-fixture", role = "assistant", status = "completed",
				content = { { type = "output_text", text = "ready" } } } } }
	else body = { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } } end
	return { StatusCode = 200, Body = f.h.json.encode(body) }
end

case("manual omission wins after saved and per-request sampling parameters", function()
	local f, record = fixture("openai")
	local sampling = f.env.require("provider/sampling")
	check("model ids normalize", sampling.set(" SAMPLING-MODEL ", "omit"))
	record.params = { temperature = 0.9, top_p = 0.8, top_k = 20 }
	for _, api in ipairs({ "openai", "anthropic", "responses" }) do
		record.api = api
		local req = request(); req.extra = { temperature = 1.5, topP = 0.7, topK = 15 }
		local body = f.env.require("provider/" .. api).buildBody(record, req)
		check(api .. " strips all forbidden sampling fields", body.temperature == nil and body.top_p == nil
			and body.top_k == nil and body.topP == nil and body.topK == nil)
	end
	check("metadata identifies the user choice", f.env.require("net/bridge_metadata").model(record).temperatureOverride == "omit")
	check("auto clears a manual choice", sampling.set(record.model, "auto") and sampling.state(record).override == "auto")
	f.healthy(); f.close()
end)

case("documented restrictions and provider defaults allow an explicit user override", function()
	local f, record = fixture("openai"); local sampling = f.env.require("provider/sampling")
	record.model = "claude-opus-4-7"
	check("documented model rejects temperature automatically", not sampling.state(record).allowed and sampling.state(record).source == "documented")
	sampling.set(record.model, "send")
	check("manual send takes precedence over documentation", sampling.apply(record, { temperature = 0 }, {}).temperature == 0)
	sampling.set(record.model, "auto"); record.model = "sampling-model"
	check("provider default stays omitted", sampling.apply(record, {}, {}, { defaultOmit = true }).temperature == nil)
	check("explicit zero survives provider-default mode", sampling.apply(record, { temperature = 0 }, {}, { defaultOmit = true }).temperature == 0)
	check("nonfinite input cannot leak to JSON", sampling.apply(record, { temperature = math.huge }, {}).temperature == nil)
	check("explicit false omits temperature", sampling.apply(record, { temperature = false }, {}).temperature == nil)
	sampling.set(record.model, "send")
	check("manual send uses configured temperature", sampling.apply(record, {}, {}, { defaultOmit = true }).temperature == 0.4)
	f.healthy(); f.close()
end)

for _, api in ipairs({ "openai", "anthropic", "responses" }) do
	case(api .. " learns only an explicit refusal and retries the original request once", function()
		local f, record = fixture(api); local seen = {}
		f.h.http.handler = function(entry)
			seen[#seen + 1] = f.h.json.decode(entry.body)
			if #seen == 1 then return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "temperature is not supported by this model" } }) } end
			return reply(f, api)
		end
		local adapter = f.env.require("provider/" .. api)
		local result = f.run(function() return adapter.complete(record, request()) end)
		check("refused request recovers once", result and result.content == "ready" and #seen == 2)
		check("retry only removes temperature", seen[1].temperature == 0.2 and seen[2].temperature == nil)
		check("learning is scoped to the endpoint/model", record.repairScope == f.env.require("provider/registry").compatibilityKey(record)
			and f.env.require("provider/sampling").state(record).source == "learned")
		result = f.run(function() return adapter.complete(record, request()) end)
		check("next request skips a known rejected parameter", result and #seen == 3 and seen[3].temperature == nil)
		record.model = "other-model"
		check("changed model does not inherit stale refusal", adapter.buildBody(record, request()).temperature == 0.2)
		f.healthy(); f.close()
	end)
end

case("range errors, terminal outcomes and changed scopes never trigger omission retries", function()
	local f, record = fixture("anthropic"); local sampling = f.env.require("provider/sampling")
	local scope = f.env.require("provider/registry").compatibilityKey(record)
	for _, item in ipairs({
		{ res = { status = 400 }, message = "temperature must be between 0 and 1", scope = scope },
		{ res = { status = 500 }, message = "unsupported temperature", scope = scope },
		{ res = { status = 400, terminal = true }, message = "unsupported temperature", scope = scope },
		{ res = { status = 400 }, message = "unsupported temperature", scope = "old-scope" },
	}) do
		local body = { temperature = 0.2 }
		check("nonrepairable outcome is untouched", not sampling.repair(record, body, item.res, item.message, item.scope) and body.temperature == 0.2)
	end
	local calls = 0
	f.h.http.handler = function()
		calls = calls + 1
		return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "temperature must be between 0 and 1" } }) }
	end
	local result = f.run(function() return f.env.require("provider/anthropic").complete(record, request()) end)
	check("ordinary validation error sends once", not result and calls == 1 and not record.repairs)
	f.healthy(); f.close()
end)

case("stop during an explicit refusal prevents resubmission and learning", function()
	for _, api in ipairs({ "openai", "anthropic", "responses" }) do
		local f, record = fixture(api); local stopped, calls = false, 0
		f.h.http.handler = function()
			calls, stopped = calls + 1, true
			return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "unsupported temperature" } }) }
		end
		local req = request(); req.aborted = function() return stopped end
		local result = f.run(function() return f.env.require("provider/" .. api).complete(record, req) end)
		check(api .. " respects Stop before retry", not result and calls == 1 and #(record.repairs or {}) == 0)
		f.healthy(); f.close()
	end
end)

case("late refusals cannot restore removed providers or overwrite saved editor changes", function()
	for _, api in ipairs({ "openai", "anthropic", "responses" }) do
		for _, remove in ipairs({ false, true }) do
			local f, record = fixture(api); local registry = f.env.require("provider/registry")
			registry.save(record, { force = true })
			local calls, replacement = 0
			f.h.http.handler = function()
				calls = calls + 1
				if remove then registry.remove(record.id)
				else
					replacement = f.env.require("runtime/util").deepCopy(record)
					replacement.model, replacement.apiKey = "new-model", "new-key"
					registry.save(replacement, { force = true })
				end
				return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "unsupported temperature" } }) }
			end
			local result = f.run(function() return f.env.require("provider/" .. api).complete(record, request()) end)
			check(api .. " lost owner cannot retry", not result and calls == 1 and #(record.repairs or {}) == 0)
			check(api .. " current saved state is retained", registry.get(record.id) == replacement)
			f.healthy(); f.close()
		end
	end
end)

case("testing an unsaved draft learns locally without adding or replacing a provider", function()
	for _, api in ipairs({ "openai", "anthropic", "responses" }) do
		local f, draft = fixture(api); local registry = f.env.require("provider/registry")
		local existing = f.env.require("runtime/util").deepCopy(draft)
		existing.model = "saved-model"; registry.save(existing, { force = true })
		local calls = 0
		f.h.http.handler = function()
			calls = calls + 1
			if calls == 1 then return { StatusCode = 400, Body = f.h.json.encode({ error = { message = "unsupported temperature" } }) } end
			return reply(f, api)
		end
		local result = f.run(function() return f.env.require("provider/" .. api).complete(draft, request()) end)
		check(api .. " draft can recover locally", result and calls == 2 and draft.repairs[1] == "temperature")
		check(api .. " connection test does not save draft", registry.get(existing.id) == existing and existing.model == "saved-model" and #(existing.repairs or {}) == 0)
		f.healthy(); f.close()
	end
end)

case("protocol handoff cannot regain ownership after provider replacement", function()
	for _, mode in ipairs({ "response", "retry", "inplace" }) do
		local f, record = fixture("openai"); local registry = f.env.require("provider/registry")
		record.baseUrl, record.model = "https://opencode.ai/zen/v1", "sampling-model"
		registry.save(record, { force = true })
		local calls, replacement = 0
		local function replace()
			replacement = mode == "inplace" and record or f.env.require("runtime/util").deepCopy(record)
			replacement.model = "changed-model"; registry.save(replacement, { force = true })
		end
		f.h.http.handler = function()
			calls = calls + 1
			if mode == "response" then replace() end
			return { StatusCode = 400, Body = f.h.json.encode({ error = { type = "ModelProtocolUnsupported", message = "Model does not support this protocol" } }) }
		end
		local req = request(); if mode ~= "response" then req.onRetry = replace end
		local result = f.run(function() return f.env.require("provider/openai").complete(record, req) end)
		check("protocol switch keeps original owner guard", not result and calls == 1 and registry.get(record.id) == replacement)
		f.healthy(); f.close()
	end
end)

suite.finish()
