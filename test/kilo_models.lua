-- Kilo catalog content negotiation and failures use synthetic responses only.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Kilo model discovery")
local case, check = suite.case, suite.check
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end
local function fixture(base)
	local f = F.new()
	f.models = f.env.require("provider/models")
	f.record = f.env.require("provider/registry").blank("kilo")
	f.record.id, f.record.model, f.record.models = "kilo-fixture", "saved-model", { "saved-model" }
	if base then f.record.baseUrl = base end
	f.getHeader = f.env.require("net/headers").get
	f.catalog = f.h.json.encode({ data = { { id = "kilo-auto/free" }, { id = "vendor/model" } } })
	function f.fetch(opts, seconds)
		return f.run(function() return f.models.discover(f.record, opts or { force = true }) end, seconds)
	end
	return f
end

case("Kilo fetches plain JSON from a catalog that otherwise negotiates Brotli", function()
	local f = fixture()
	f.h.http.handler = function(entry)
		check("public catalog requests are GET without credentials or a body", entry.method == "GET" and not entry.body
			and not f.getHeader(entry.headers, "Authorization"))
		check("the catalog asks for JSON", f.getHeader(entry.headers, "Accept") == "application/json")
		if f.getHeader(entry.headers, "Accept-Encoding") ~= "identity" then
			return { StatusCode = 200, Body = "\101\0\192\255\6\0\206\178", Headers = { ["Content-Encoding"] = "br" } }
		end
		return { StatusCode = 200, Body = f.catalog, Headers = { ["Content-Type"] = "application/json" } }
	end
	local found, note = f.fetch()
	check("the public live schema becomes a usable list", #found == 2 and found[1] == "kilo-auto/free" and has(note, "2 models"))
	check("fetch keeps saved selections and caches the discovered list", f.record.model == "saved-model"
		and f.record.models[1] == "saved-model" and f.models.cached(f.record)[2] == "vendor/model")
	local cached, cachedNote = f.fetch({})
	check("cached discovery does not issue another request", #cached == 2 and cachedNote == "cached" and f.h.http.requestCount == 1)
	f.healthy(); f.close()
end)

case("only exact documented HTTPS Kilo catalog routes receive defaults", function()
	for _, base in ipairs({ "https://api.kilo.ai/api/gateway", "https://api.kilo.ai/api/gateway/v1", "https://ai-gateway.kilo.ai/api/v1",
		"https://api.kilo.ai:443/api/gateway" }) do
		local f = fixture(base)
		f.h.http.handler = function(entry)
			check("the exact route requests uncompressed JSON", f.getHeader(entry.headers, "Accept-Encoding") == "identity")
			return { StatusCode = 200, Body = f.catalog }
		end
		check("the supported route returns its catalog", #f.fetch() == 2)
		f.healthy(); f.close()
	end
	for _, base in ipairs({ "http://api.kilo.ai/api/gateway", "https://api.kilo.ai:8443/api/gateway",
		"https://api.kilo.ai.example/api/gateway", "https://api.kilo.ai/unrelated", "https://other.example/api/gateway" }) do
		local f = fixture(base)
		f.h.http.handler = function(entry)
			check("custom or unrelated routes retain their existing negotiation", not f.getHeader(entry.headers, "Accept-Encoding")
				and not f.getHeader(entry.headers, "Accept"))
			return { StatusCode = 200, Body = f.catalog }
		end
		check("the unrelated route keeps ordinary discovery", #f.fetch() == 2)
		f.healthy(); f.close()
	end
end)

case("case-insensitive custom negotiation and authentication retain precedence", function()
	local f = fixture()
	f.record.authStyle, f.record.apiKey = "bearer", "fixture-account-key"
	f.record.headers = { ["accept"] = "application/vendor+json", ["accept-encoding"] = "gzip", ["X-Region"] = "one" }
	f.record.query = { region = "one" }
	f.h.http.handler = function(entry)
		check("explicit lowercase headers win without duplicates", f.getHeader(entry.headers, "Accept") == "application/vendor+json"
			and f.getHeader(entry.headers, "Accept-Encoding") == "gzip" and entry.headers.Accept == nil and entry.headers["Accept-Encoding"] == nil)
		check("credentials and custom route data are preserved", f.getHeader(entry.headers, "Authorization") == "Bearer fixture-account-key"
			and entry.headers["X-Region"] == "one" and has(entry.url, "?region=one"))
		return { StatusCode = 200, Body = f.catalog }
	end
	check("a wrapper that decodes gzip still returns its catalog", #f.fetch() == 2)
	f.healthy(); f.close()
end)

for _, fixtureReply in ipairs({
	{ name = "Brotli", body = "\101\0\192\255\6\0\206\178", headers = { ["Content-Encoding"] = "br" }, notice = "compressed model data" },
	{ name = "gzip", body = "\31\139\8\0encoded", headers = {}, notice = "compressed model data" },
	{ name = "HTML", body = "  <!DOCTYPE html><title>private-body-marker</title>", headers = { ["Content-Type"] = "text/html" }, notice = "web page instead" },
	{ name = "invalid JSON", body = "{private-body-marker", headers = { ["Content-Encoding"] = "private-header-marker" }, notice = "could not parse as JSON" },
}) do
	case(fixtureReply.name .. " failures use fixed notices without exposing the response", function()
		local f = fixture()
		f.h.http.handler = function() return { StatusCode = 200, Body = fixtureReply.body, Headers = fixtureReply.headers } end
		local found, note = f.fetch()
		check("the failure has a useful fixed category", #found == 0 and has(note, fixtureReply.notice))
		check("invalid catalogs are not cached or retried", f.models.cached(f.record) == nil and f.h.http.requestCount == 1)
		check("the notice never copies bodies or arbitrary headers", not has(note, "private-body-marker") and not has(note, "private-header-marker"))
		local logs = f.env.require("runtime/log").entries
		check("model diagnostics retain only the fixed notice", logs[#logs].source == "models" and logs[#logs].detail == nil)
		if fixtureReply.notice == "compressed model data" then check("compression failure explains the override", has(note, "Remove any custom Accept-Encoding header")) end
		f.healthy(); f.close()
	end)
end

case("a terminal executor JSON exception remains fixed and does not replay", function()
	local f = fixture()
	local calls = 0
	f.env.require("runtime/caps").fn.request = function()
		calls = calls + 1
		error("malformed: failed to parse json: private-native-marker", 0)
	end
	local found, note = f.fetch({ force = true, timeout = 0.1 })
	check("native parser failure is identified without its raw detail", #found == 0 and has(note, "host could not parse Kilo's response as JSON")
		and not has(note, "private-native-marker"))
	check("terminal native parse failure is not replayed or cached", calls == 1 and f.models.cached(f.record) == nil)
	f.healthy(); f.close()
end)

case("a timed-out catalog request retains native ownership until it completes", function()
	local f = fixture()
	f.env.uis.TouchEnabled, f.env.uis.MouseEnabled = true, false
	f.h.http.handler = function() return { StatusCode = 200, Body = f.catalog, delay = 1 } end
	local clock = f.env.require("runtime/clock")
	local found, note = f.fetch({ force = true, deadlineMs = clock.ms() + 100 })
	local http = f.env.require("net/http")
	check("the Lua deadline leaves one native worker owned", #found == 0 and has(note, "timed out") and http.workers() == 1)
	local blocked, blockedNote = f.fetch({ force = true, deadlineMs = clock.ms() + 100 })
	check("another fetch cannot overlap the unfinished native call", #blocked == 0 and has(blockedNote, "earlier native HTTP calls")
		and f.h.http.requestCount == 1 and http.workers() == 1)
	f.h.sched.advance(1)
	check("only native completion releases ownership and cannot cache a late result", http.workers() == 0 and f.models.cached(f.record) == nil)
	f.healthy(); f.close()
end)

suite.finish()
