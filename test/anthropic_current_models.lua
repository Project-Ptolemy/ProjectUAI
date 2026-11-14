-- Native Claude 5.2 protocol restrictions from the November 14 model references.
-- Synthetic HTTP only: no account, server, model inference or executor is used.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Current Anthropic models")
local case, check = suite.case, suite.check
local MODELS = { "claude-fable-5-2", "claude-mythos-5-2" }
local TOOLS = { { type = "function", ["function"] = { name = "fixture_inspect",
	description = "Inspect the fixture", parameters = { type = "object", properties = {} } } } }
local function fixture(model)
	local f = F.new()
	local registry = f.env.require("provider/registry")
	local record = registry.blank("anthropic-messages")
	record.id, record.label, record.model, record.apiKey = "current-claude", "Current Claude fixture", model, "fixture-key"
	record.params = {}
	return f, record, f.env.require("provider/anthropic")
end
local function request()
	return { messages = { { role = "user", content = "Inspect the current state." } },
		tools = TOOLS, maxTokens = 1024, stream = false }
end
local function complete(f, adapter, record, req)
	return f.run(function() return adapter.complete(record, req) end)
end
local function reply(f, record)
	return { StatusCode = 200, Body = f.h.json.encode({ type = "message", id = "fixture-result",
		model = record.model, role = "assistant", content = { { type = "text", text = "Inspected." } },
		stop_reason = "end_turn", usage = { input_tokens = 32, output_tokens = 4 } }) }
end

case("native models keep adaptive thinking with valid automatic and disabled tools", function()
	for _, model in ipairs(MODELS) do
		local f, record, adapter = fixture(model)
		local config, bodies = f.env.require("runtime/config"), {}
		f.h.http.handler = function(entry)
			check("uses the native Messages route", entry.url == "https://api.anthropic.com/v1/messages")
			bodies[#bodies + 1] = f.h.json.decode(entry.body)
			return reply(f, record)
		end
		local req = request(); req.toolChoice = "auto"
		local result, why = complete(f, adapter, record, req)
		check("valid automatic request succeeds: " .. tostring(why), result and result.content == "Inspected.")
		config.set("ui.showReasoning", false)
		req.toolChoice = "none"
		check("valid none request succeeds", complete(f, adapter, record, req) ~= nil)
		check("keeps tools and automatic thinking", bodies[1].tool_choice.type == "auto"
			and bodies[1].thinking.type == "adaptive" and bodies[1].thinking.display == "summarized" and #bodies[1].tools == 1)
		check("hidden summaries do not disable thinking", bodies[2].tool_choice.type == "none"
			and bodies[2].thinking.type == "adaptive" and bodies[2].thinking.display == "omitted")
		check("unsupported sampling stays omitted", bodies[1].temperature == nil and bodies[1].top_p == nil and bodies[1].top_k == nil)
		check("only intended requests dispatch", f.h.http.requestCount == 2)
		f.healthy(); f.close()
	end
end)

case("incompatible raw thinking settings fail before native dispatch", function()
	for _, model in ipairs(MODELS) do
		local f, record, adapter = fixture(model)
		for _, invalid in ipairs({ false, { type = "disabled" }, { type = "enabled", budget_tokens = 100 },
			{ type = "adaptive", budget_tokens = 100 } }) do
			local req = request(); req.extra = { thinking = invalid }
			local result, why = complete(f, adapter, record, req)
			check("invalid thinking is an actionable preparation failure", result == nil
				and tostring(why):find("requires adaptive thinking", 1, true) ~= nil)
		end
		check("rejects before sending or retrying", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end
end)

case("both raw and abstract forced choices fail without reinterpreting the request", function()
	for _, model in ipairs(MODELS) do
		local f, record, adapter = fixture(model)
		for _, choice in ipairs({ { type = "any" }, { type = "tool", name = "fixture_inspect" }, "auto" }) do
			record.params.tool_choice = choice
			local result, why = complete(f, adapter, record, request())
			check("unsupported raw choice is refused", result == nil and tostring(why):find("only auto or none", 1, true) ~= nil)
		end
		record.params.tool_choice = nil
		for _, choice in ipairs({ "required", { type = "function", ["function"] = { name = "fixture_inspect" } } }) do
			local req = request(); req.toolChoice = choice
			local result, why = complete(f, adapter, record, req)
			check("explicit force is refused rather than ignored", result == nil and tostring(why):find("forced tool use", 1, true) ~= nil)
		end
		check("forced choices dispatch no inference", f.h.http.requestCount == 0)
		f.healthy(); f.close()
	end
end)

case("final compatible raw overrides retain their precedence and bytes", function()
	local f, record, adapter = fixture(MODELS[1])
	record.params = { thinking = { type = "disabled" }, tool_choice = { type = "any" } }
	local req = request()
	req.toolChoice = "required"
	req.extra = { thinking = { type = "adaptive", display = "omitted" }, tool_choice = { type = "none" } }
	local body = adapter.buildBody(record, req)
	check("compatible final settings win", body.thinking.type == "adaptive" and body.thinking.display == "omitted" and body.tool_choice.type == "none")
	check("source provider and request settings stay unchanged", record.params.thinking.type == "disabled"
		and record.params.tool_choice.type == "any" and req.toolChoice == "required" and req.extra.tool_choice.type == "none")
	f.healthy(); f.close()
end)

case("native guards do not attach to custom endpoints or older model identities", function()
	for _, row in ipairs({
		{ "https://fixture.test/v1", MODELS[1] },
		{ "https://api.anthropic.com/custom/v1", MODELS[1] },
		{ "https://api.anthropic.com:8443/v1", MODELS[2] },
		{ "https://api.anthropic.com/v1", "claude-opus-4-6" },
		{ "https://api.anthropic.com/v1", "claude-fable-5.2" },
	}) do
		local f, record, adapter = fixture(row[2]); record.baseUrl = row[1]
		record.params.thinking = { type = "disabled" }
		local req = request(); req.toolChoice = "required"
		local body = adapter.buildBody(record, req)
		check("retains explicit nonnative or older model settings", body.thinking.type == "disabled" and body.tool_choice.type == "any")
		local named = { type = "function", ["function"] = { name = "fixture_inspect" } }
		req.toolChoice = named
		body = adapter.buildBody(record, req)
		check("translates named choice without mutating its source", body.tool_choice.type == "tool"
			and body.tool_choice.name == "fixture_inspect" and named.type == "function" and named["function"].name == "fixture_inspect")
		f.healthy(); f.close()
	end
end)

suite.finish()
