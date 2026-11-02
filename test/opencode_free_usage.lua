-- Complete OpenCode free-access refusals stop replay; generic limits still retry.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("OpenCode free API usage")
local check, case = suite.check, suite.case
local refusalMessage = "Free usage limit reached. Free models work in OpenCode (https://opencode.ai); subscribe to OpenCode Go to keep going: https://opencode.ai/go"

case("classification requires a complete explicit error", function()
	local f = F.new(); local http = f.env.require("net/http")
	for _, payload in ipairs({
		{ error = { type = "FreeUsageLimitError", message = refusalMessage } },
		{ error = { name = "RateLimit.FreeUsageLimitError", message = "Access denied" } },
		{ error = { type = "invalid_request_error", code = "FreeUsageLimitError", message = "Access denied" } },
		{ error = { type = "invalid_request_error", message = refusalMessage } },
		{ error = refusalMessage },
		{ type = "error", message = refusalMessage },
		{ type = "FreeUsageLimitError", message = refusalMessage },
	}) do
		local body = f.h.json.encode(payload)
		for _, status in ipairs({ 200, 403, 429, 503 }) do
			local res = { ok = status == 200, status = status, body = body, headers = { ["retry-after"] = "1" } }
			check("explicit free usage never retries", http.shouldRetry(res, nil, { elapsed = 12 }) == false)
			check("same classifier suppresses key rotation", http.isOpencodeFreeUsageRefusal(res))
		end
	end
	for _, body in ipairs({
		'{"error":{"type":"FreeUsageLimitError","message":"incomplete"}',
		'data: {"error":{"type":"FreeUsageLimitError"}}\n\n',
		f.h.json.encode({ choices = { { message = { content = refusalMessage } } } }),
		f.h.json.encode({ error = { type = "rate_limit_error", message = "free usage limit reached" } }),
		f.h.json.encode({ error = { type = "rate_limit_error", message = "A response can mention FreeUsageLimitError" } }),
		f.h.json.encode({ error = { type = "rate_limit_error", message = "rate limit exceeded" } }),
	}) do
		local res = { ok = false, status = 429, body = body }
		check("unproven or generic refusal keeps ordinary transport retry", http.shouldRetry(res, nil, { elapsed = 12 }) == true)
		check("unproven refusal cannot suppress key rotation", not http.isOpencodeFreeUsageRefusal(res))
	end
	f.healthy(); f.close()
end)

local function fixture(protocol, pool)
	local f = F.new(); local registry = f.env.require("provider/registry")
	f.record = registry.blank("zen")
	f.record.id, f.record.label = "opencode-usage-fixture", "OpenCode usage fixture"
	f.record.model = protocol == "responses" and "muse-spark-1.3-contributor-free" or "deepseek-v4.1-flash-free"
	f.record.models, f.record.apiKey = { f.record.model }, pool and "fixture-one\nfixture-two" or "fixture-one"
	f.seen, f.retries = {}, 0
	function f.observe(entry)
		f.seen[#f.seen + 1] = { url = entry.url, key = f.env.require("net/headers").get(entry.headers, "Authorization") }
	end
	function f.complete()
		return f.run(function()
			return f.env.require("provider/openai").complete(f.record, {
				messages = { { role = "user", content = "Reply ready" } }, stream = true, attempts = 3,
				onRetry = function() f.retries = f.retries + 1 end,
			})
		end, 8)
	end
	function f.success()
		local body = protocol == "responses"
			and { status = "completed", output = { { type = "message", content = { { type = "output_text", text = "ready" } } } } }
			or { choices = { { message = { role = "assistant", content = "ready" }, finish_reason = "stop" } } }
		return { StatusCode = 200, Body = f.h.json.encode(body) }
	end
	return f
end

for _, protocol in ipairs({ "chat", "responses" }) do
	for _, pool in ipairs({ false, true }) do
		case(protocol .. (pool and " key pool" or " single key") .. " refuses once without retries or cooling", function()
			local f = fixture(protocol, pool)
			f.h.http.handler = function(entry)
				f.observe(entry)
				return { StatusCode = 429, Body = f.h.json.encode({ error = { type = "FreeUsageLimitError", message = refusalMessage } }) }
			end
			local result, why, res = f.complete()
			check("provider preserves the exact status and detail", result == nil and res.status == 429 and why:find(refusalMessage, 1, true))
			check("refusal dispatches once without protocol or transport retry", #f.seen == 1 and f.retries == 0)
			check("current key is not cooled or replaced", f.seen[1].key == "Bearer fixture-one"
				and next(f.env.require("provider/registry").keyCooldowns(f.record) or {}) == nil)
			check("tunnel advice survives both adapters", why:find("installed OpenCode tunnel", 1, true))
			check("bridge API-key advice survives both adapters", why:find("Desktop Bridge for API-key access", 1, true))
			check("refusal does not teach a protocol switch", not f.env.require("provider/responses").remembered(f.record))
			f.healthy(); f.close()
		end)
	end
	case(protocol .. " ordinary 429 still retries one key", function()
		local f = fixture(protocol, false)
		f.h.http.handler = function(entry)
			f.observe(entry)
			if #f.seen == 1 then return { StatusCode = 429, Body = '{"error":{"type":"rate_limit_error","message":"rate limit exceeded"}}', Headers = { ["retry-after"] = "0" } } end
			return f.success()
		end
		local result = f.complete()
		check("generic rate limit retries to success", result and result.content == "ready" and #f.seen == 2 and f.retries == 1)
		check("transport retry preserves the request key", f.seen[1].key == f.seen[2].key)
		f.healthy(); f.close()
	end)
	case(protocol .. " ordinary 429 still rotates pooled keys", function()
		local f = fixture(protocol, true)
		f.h.http.handler = function(entry)
			f.observe(entry)
			if #f.seen == 1 then return { StatusCode = 429, Body = '{"error":{"message":"rate limit exceeded"}}' } end
			return f.success()
		end
		local result = f.complete()
		check("generic rate limit rotates to success", result and result.content == "ready" and #f.seen == 2 and f.retries == 1)
		check("rotation chooses the next key", f.seen[1].key == "Bearer fixture-one" and f.seen[2].key == "Bearer fixture-two")
		check("only the actually limited key cools", f.env.require("provider/registry").keyCooldowns(f.record)["fixture-one"] ~= nil
			and f.env.require("provider/registry").keyCooldowns(f.record)["fixture-two"] == nil)
		f.healthy(); f.close()
	end)
end

suite.finish()
