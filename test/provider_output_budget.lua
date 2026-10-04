-- Real adapter-body checks for temporary context/reply allowances.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider output budget")
local check, case = suite.check, suite.case
local function fixture(style)
	local f = F.new()
	local record = { id = "output-budget", label = "Budget fixture", model = "budget-fixture",
		baseUrl = "https://budget.test/v1", api = style, params = {} }
	local adapter = f.env.require("provider/" .. style)
	return f, record, adapter
end
local function request()
	return { messages = { { role = "user", content = "Continue the task." } }, maxTokens = 128000,
		outputCeiling = 640, extra = {} }
end

case("both adapters enforce the temporary allowance after raw overrides", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record, adapter = fixture(style)
		local req = request()
		record.params.max_tokens = 900000
		req.extra.max_tokens = 700000
		local body = adapter.buildBody(record, req)
		check(style .. " applies ceiling last", body.max_tokens == 640)
		check(style .. " does not mutate raw overrides", record.params.max_tokens == 900000 and req.extra.max_tokens == 700000)
		check(style .. " does not teach a permanent cap", record.maxTokensCap == nil)
		check(style .. " does not expose internal accounting in the wire body", body.outputCeiling == nil)
		req.outputCeiling = 2400
		check(style .. " allows a larger next request", adapter.buildBody(record, req).max_tokens == 2400)
		f.healthy(); f.close()
	end
end)

case("smaller raw overrides and known output limits stay effective", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record, adapter = fixture(style)
		local req = request()
		record.params.max_tokens, req.extra.max_tokens = 400, 128
		check(style .. " retains explicit smaller override", adapter.buildBody(record, req).max_tokens == 128)
		record.model, record.params.max_tokens, req.extra.max_tokens = "claude-opus-4-6", 900000, 900000
		req.outputCeiling = 500000
		check(style .. " also honors documented output cap", adapter.buildBody(record, req).max_tokens == 128000)
		record.maxTokensCap = { model = record.model, tokens = 256,
			scope = f.env.require("provider/registry").compatibilityKey(record) }
		req.outputCeiling = 640
		check(style .. " retains an existing learned smaller cap", adapter.buildBody(record, req).max_tokens == 256)
		check(style .. " does not replace the learned lesson", record.maxTokensCap.tokens == 256)
		f.healthy(); f.close()
	end
end)

case("alternate completion limits cannot bypass the allowance", function()
	local f, record, adapter = fixture("openai")
	local req = request()
	record.params.max_completion_tokens = 900000
	local body = adapter.buildBody(record, req)
	check("alternate field and default field are bounded", body.max_completion_tokens == 640 and body.max_tokens == 640)
	req.extra.max_completion_tokens = 123
	check("smaller explicit completion limit remains", adapter.buildBody(record, req).max_completion_tokens == 123)
	check("raw completion override is unchanged", record.params.max_completion_tokens == 900000 and req.extra.max_completion_tokens == 123)
	f.healthy(); f.close()
end)

case("summary-sized ceilings survive bad raw limits without affecting ordinary calls", function()
	for _, style in ipairs({ "openai", "anthropic" }) do
		local f, record, adapter = fixture(style)
		local req = request()
		req.maxTokens, req.outputCeiling = 512, 512
		for _, override in ipairs({ 999999, 0, -2, "unlimited", false }) do
			req.extra.max_tokens = override
			check(style .. " summary remains bounded", adapter.buildBody(record, req).max_tokens == 512)
		end
		req.outputCeiling, req.extra.max_tokens = nil, 9999
		check(style .. " preserves existing behavior without an allowance", adapter.buildBody(record, req).max_tokens == 9999)
		f.healthy(); f.close()
	end
end)

suite.finish()
