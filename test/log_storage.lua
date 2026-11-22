package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Log storage")
local check = suite.check
suite.case("OpenCode credentials are redacted even without a secret field", function()
	local f = F.new(); local log = f.env.require("runtime/log")
	local key = "oc_sk_fixture-secret_0123456789ABCD"
	local other = "oc_sk_fixture-secret_0123456789WXYZ"
	log.clear()
	local entry = log.info("zen " .. key, "Upstream mentioned " .. key,
		'{"message":"Credential refused: ' .. key .. '","other":"' .. other .. '"}')
	check("source does not retain the credential", not entry.source:find(key, 1, true))
	check("message does not retain the credential", not entry.message:find(key, 1, true))
	check("arbitrary JSON text does not retain either credential",
		not entry.detail:find(key, 1, true) and not entry.detail:find(other, 1, true))
	check("exports retain only distinguishable tails",
		log.export():find("...ABCD", 1, true) and log.export():find("...WXYZ", 1, true))
	f.healthy(); f.close()
end)
suite.case("retained logs bound large values after redaction", function()
	local f = F.new(); local log = f.env.require("runtime/log")
	log.clear()
	local entry = log.info("fixture", string.rep("message ", 4000), string.rep("detail ", 9000) .. " token=fixture-secret-end")
	check("large messages are bounded", #entry.message < 8400)
	check("large details are bounded", #entry.detail < 16600)
	check("omission is visible", entry.message:find("omitted", 1, true) and entry.detail:find("omitted", 1, true))
	check("retained tail is redacted", not log.export():find("fixture-secret-end", 1, true))
	log.info("provider", "request refused", "fixture status 429")
	check("search can cross source and detail", #log.filter("info", "provider 429") == 1)
	check("all terms must match", #log.filter("info", "provider 404") == 0)
	for index = 1, 900 do log.debug("burst", "entry " .. index) end
	check("entry count stays bounded", #log.entries <= 400)
	check("the final burst entry is retained", log.tail(1)[1].message == "entry 900")
	f.healthy(); f.close()
end)
suite.finish()
