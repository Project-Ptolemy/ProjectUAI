-- Workers AI discovery uses the account catalog, retaining normal cache guards.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Cloudflare model discovery")
local case, check = suite.case, suite.check
local account = "0123456789abcdef0123456789abcdef"
local base = "https://api.cloudflare.com/client/v4/accounts/" .. account .. "/ai/v1"
local search = "https://api.cloudflare.com/client/v4/accounts/" .. account .. "/ai/models/search"
local function fixture()
	local f = F.new()
	f.record = f.env.require("provider/registry").blank("cloudflare")
	f.record.baseUrl, f.record.apiKey = base, "fixture-token"
	f.models = f.env.require("provider/models")
	function f.fetch() return f.run(function() return f.models.discover(f.record, { force = true }) end, 1) end
	return f
end
local function row(name, task) return { id = "opaque-catalog-record", name = name, task = { name = task or "Text Generation" } } end
local function response(f, rows, info)
	return { StatusCode = 200, Body = f.h.json.encode({ success = true, result = rows, result_info = info or { total_pages = 1 } }) }
end

case("the inference prefix lists canonical model names through the account catalog", function()
	local f = fixture()
	f.record.baseUrl = base .. "/chat/completions?locale=en"
	f.record.query, f.record.headers = { search = "llama" }, { ["X-Fixture"] = "preserved" }
	f.record.models, f.record.model = { "manual-model" }, "manual-model"
	f.h.http.handler = function(request)
		if request.url:find("/ai/v1/models", 1, true) then
			return { StatusCode = 405, Body = '{"success":false,"errors":[{"code":7001,"message":"GET method not supported for the requested URI"}]}' }
		end
		check("discovery uses the documented GET route", request.method == "GET" and request.url:find(search, 1, true) == 1)
		check("paging and configured query survive", request.url:find("locale=en", 1, true) and request.url:find("search=llama", 1, true)
			and request.url:find("page=1", 1, true) and request.url:find("per_page=100", 1, true))
		check("the original token and headers authenticate discovery", request.headers.Authorization == "Bearer fixture-token" and request.headers["X-Fixture"] == "preserved")
		return response(f, { row("@cf/meta/llama-3.1-8b-instruct"), row("@cf/baai/bge-large-en-v1.5", "Text Embeddings"),
			row("@cf/black-forest-labs/flux-1-schnell", "Text-to-Image"), row("@cf/meta/llama-3.1-8b-instruct") })
	end
	local found, note = f.fetch()
	check("catalog names, rather than opaque IDs, reach the picker", #found == 1 and found[1] == "@cf/meta/llama-3.1-8b-instruct")
	check("non-chat omissions are explained", note:find("2 non-chat entries hidden", 1, true))
	check("discovery cannot replace manual choices or the inference URL", f.models.list(f.record)[1] == "manual-model"
		and f.record.model == "manual-model" and #f.record.models == 1 and f.record.baseUrl == base .. "/chat/completions?locale=en")
	local cached, cacheNote = f.run(function() return f.models.discover(f.record) end)
	check("the completed catalog is cached", cached[1] == found[1] and cacheNote == "cached" and f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

case("custom origins and account paths keep their configured generic catalogs", function()
	for _, configured in ipairs({ "https://api.cloudflare.com.evil.test/client/v4/accounts/" .. account .. "/ai/v1",
		"http://api.cloudflare.com/client/v4/accounts/" .. account .. "/ai/v1", "https://api.cloudflare.com:8443/client/v4/accounts/" .. account .. "/ai/v1",
		"https://api.cloudflare.com/proxy/client/v4/accounts/" .. account .. "/ai/v1", "https://fixture.test/v1" }) do
		local f = fixture(); f.record.baseUrl = configured
		f.h.http.handler = function(request)
			check("custom catalog route remains exact", request.url == configured .. "/models")
			return { StatusCode = 200, Body = f.h.json.encode({ data = { { id = "custom-model", name = "different-name", task = { name = "Text Embeddings" } } } }) }
		end
		check("custom schemas remain generic", f.fetch()[1] == "custom-model")
		f.healthy(); f.close()
	end
end)

case("catalog pages merge once within the original credentials and query", function()
	local f = fixture(); f.record.query = { search = "model", hide_experimental = true }
	f.h.http.handler = function(request)
		local page = tonumber(request.url:match("[?&]page=(%d+)"))
		check("every page keeps the account catalog route", request.url:find(search .. "?", 1, true) == 1)
		check("all pages retain authentication and filters", request.headers.Authorization == "Bearer fixture-token"
			and request.url:find("search=model", 1, true) and request.url:find("hide_experimental=true", 1, true))
		return response(f, page == 1 and { row("@cf/test/z"), row("@cf/test/shared") } or { row("@cf/test/a"), row("@cf/test/shared") }, { page = page, total_pages = 2 })
	end
	local found = f.fetch()
	check("all pages are sorted and deduplicated", #found == 3 and found[1] == "@cf/test/a" and found[3] == "@cf/test/z" and f.h.http.requestCount == 2)
	f.healthy(); f.close()
end)

case("missing totals follow the official empty-page termination", function()
	local f = fixture()
	f.h.http.handler = function(request)
		local page = tonumber(request.url:match("[?&]page=(%d+)"))
		return response(f, page == 1 and { row("@cf/test/only") } or {}, {})
	end
	local found = f.fetch()
	check("an empty subsequent page completes the list", found[1] == "@cf/test/only" and f.h.http.requestCount == 2)
	f.healthy(); f.close()
end)

case("a failed later page cannot publish a partial successful catalog", function()
	local f = fixture()
	f.h.http.handler = function(request)
		if request.url:find("page=1&", 1, true) then return response(f, { row("@cf/test/partial") }, { total_pages = 2 }) end
		return { StatusCode = 403, Body = '{"success":false,"errors":[{"message":"Not allowed"}]}' }
	end
	local found, note = f.fetch()
	check("failure leaves discovery uncached", #found == 0 and f.models.cached(f.record) == nil and note:find("Workers AI model page", 1, true))
	f.healthy(); f.close()
end)

case("an account changed during discovery invalidates every earlier page", function()
	local f = fixture()
	f.h.http.handler = function()
		f.record.baseUrl = base:gsub(account, "different-account")
		return response(f, { row("@cf/test/stale") }, { total_pages = 2 })
	end
	local found, note = f.fetch()
	check("stale discovery cannot advance or cache", #found == 0 and f.h.http.requestCount == 1 and f.models.cached(f.record) == nil
		and note:find("connection changed", 1, true))
	f.healthy(); f.close()
end)

case("a malformed later result cannot masquerade as a completed empty page", function()
	local f = fixture()
	f.h.http.handler = function(request)
		if request.url:find("page=1&", 1, true) then return response(f, { row("@cf/test/partial") }, { total_pages = 2 }) end
		return response(f, { unexpected = "shape" }, { total_pages = 2 })
	end
	local found, note = f.fetch()
	check("a malformed page discards the partial discovery", #found == 0 and f.models.cached(f.record) == nil
		and note:find("Workers AI model page", 1, true))
	f.healthy(); f.close()
end)

case("page bounds disclose additional manual choices", function()
	local f = fixture()
	f.h.http.handler = function(request)
		local page = tonumber(request.url:match("[?&]page=(%d+)"))
		return response(f, { row("@cf/test/page-" .. page) }, { total_pages = 11 })
	end
	local found, note = f.fetch()
	check("ten pages bound the catalog", #found == 10 and f.h.http.requestCount == 10)
	check("the picker explains the bounded partial catalog", note:find("page limit reached", 1, true) and note:find("entered manually", 1, true))
	f.healthy(); f.close()
end)

case("Cloudflare API failure envelopes do not become an empty success", function()
	local f = fixture()
	f.h.http.handler = function() return { StatusCode = 200, Body = '{"success":false,"errors":[{"code":7001}],"result":[]}' } end
	local found, note = f.fetch()
	check("failure envelopes remain retryable and uncached", #found == 0 and f.models.cached(f.record) == nil and note:find("Workers AI model catalog", 1, true))
	f.healthy(); f.close()
end)

suite.finish()
