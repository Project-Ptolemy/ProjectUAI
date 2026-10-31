-- Vault exchanges stay on the authenticated bridge and never replay writes.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Obsidian transport")
local check, case = suite.check, suite.case
local function fixture()
	local f = F.new(); local state = { enabled = true, port = 8790, token = "fixture-token", instance = "fixture" }
	f.loaded["runtime/config"] = { accessProblem = function() return nil end }
	f.loaded["net/bridge_connection"] = { get = function() local value = {}; for k, v in pairs(state) do value[k] = v end; return value end }
	f.loaded["net/bridge"] = { status = function() return { online = true } end }
	return f, state
end
case("credentials stay in headers and configuration options are not mutated", function()
	local f = fixture(); local captured
	f.loaded["net/http"] = { request = function(value) captured = value; return { ok = true, body = '{"vaults":[]}' } end }
	local transport, options = f.env.require("net/obsidian"), {}
	check("configuration accepted", transport.configure({ action = "remove", id = "id" }, options) ~= nil)
	check("configuration endpoint selected", captured.url == "http://127.0.0.1:8790/api/vaults/config")
	check("no credentials in URL", not captured.url:find("fixture-token", 1, true))
	check("headers authenticate", captured.headers.Authorization == "Bearer fixture-token" and captured.identity == "none")
	check("caller options retained", options.config == nil)
	f.close()
end)
case("lost save responses remain uncertain and never dispatch twice", function()
	local f = fixture(); local calls = 0
	f.loaded["net/http"] = { request = function() calls = calls + 1; return nil, "timeout" end }
	local value, why = f.env.require("net/obsidian").request({ action = "append", vault = "id", path = "Note.md", content = "draft" })
	check("save uncertainty is visible", value == nil and why:find("could not be confirmed", 1, true) ~= nil)
	check("one dispatch only", calls == 1); f.close()
end)
case("changed bridge identities suppress late results and pre-cancelled calls never dispatch", function()
	local f, state = fixture(); local calls = 0
	f.loaded["net/http"] = { request = function() calls = calls + 1; state.instance = "replacement"; return { ok = true, body = '{"vaults":[]}' } end }
	local transport = f.env.require("net/obsidian")
	check("late replacement rejected", transport.list() == nil)
	check("cancelled request rejected", transport.list({ aborted = function() return true end }) == nil)
	check("cancelled call never dispatches", calls == 1); f.close()
end)
suite.finish()
