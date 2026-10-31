-- Named provider credentials keep metadata separate from ordered request policy.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Provider key metadata")
local case, check = suite.case, suite.check

case("legacy pools default to rotation and unnamed entries", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local record = { apiKey = "alpha, beta\ngamma\nalpha" }
	local entries = keys.entries(record)
	check("legacy duplicate parsing and order stay compatible", #entries == 3 and entries[1].key == "alpha" and entries[3].key == "gamma")
	check("missing metadata defaults to rotation and numbered presentation", keys.mode(record) == "rotate" and keys.selected(record) == 1
		and entries[1].name == "" and entries[3].name == "" and keys.validate(record))
	check("rotation offers every stored key", table.concat(keys.requestKeys(record), ",") == "alpha,beta,gamma")
	f.healthy(); f.close()
end)

case("names survive replacement, removal and append without following old positions", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local record = { apiKey = "alpha\nbeta\ngamma" }
	assert(keys.rename(record, 1, "  Personal  "))
	assert(keys.rename(record, 2, "Backup"))
	assert(keys.rename(record, 3, "Shared"))
	assert(keys.replace(record, 2, "new-beta"))
	check("replacement keeps its existing name", keys.entries(record)[2].key == "new-beta" and record.keyNames[2] == "Backup")
	assert(keys.remove(record, 1))
	local ok, added = keys.add(record, "delta, epsilon\nnew-beta")
	check("append retains existing names and ignores duplicates", ok and added == 2 and #keys.keys(record) == 4
		and record.keyNames[1] == "Backup" and record.keyNames[2] == "Shared" and record.keyNames[3] == "" and record.keyNames[4] == "")
	assert(keys.rename(record, 1, ""))
	check("clearing a custom name restores the default without removing its key", record.keyNames[1] == "" and keys.keys(record)[1] == "new-beta")
	check("all mutations preserve valid transfer metadata", keys.validate(record))
	f.healthy(); f.close()
end)

case("removing another entry preserves the pinned credential and removing it enables rotation", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local record = { apiKey = "alpha\nbeta\ngamma\ndelta" }
	assert(keys.setMode(record, "single", 3))
	assert(keys.remove(record, 1))
	check("removing an earlier key retains the same selected credential", keys.mode(record) == "single" and keys.selected(record) == 2
		and keys.requestKeys(record)[1] == "gamma" and #keys.requestKeys(record) == 1)
	assert(keys.replace(record, 2, "new-gamma"))
	check("replacing the pinned entry selects its replacement", keys.requestKeys(record)[1] == "new-gamma")
	assert(keys.remove(record, 2))
	check("removing the selected entry explicitly returns to rotation", keys.mode(record) == "rotate" and keys.selected(record) == 1
		and table.concat(keys.requestKeys(record), ",") == "beta,delta")
	f.healthy(); f.close()
end)

case("renames leave live round robin and raw legacy credentials unchanged", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local registry = f.env.require("provider/registry")
	local record = { apiKey = "alpha, beta\ngamma" }
	check("legacy rotation begins at the first key", registry.nextKey(record) == "alpha")
	local state = record.keyRotation
	assert(keys.rename(record, 2, "Backup"))
	check("renames keep the cursor and original serialization", record.keyRotation == state and record.apiKey == "alpha, beta\ngamma"
		and registry.nextKey(record) == "beta")
	assert(keys.replace(record, 2, "replacement"))
	check("credential changes reset future rotation", record.keyRotation == nil and registry.nextKey(record) == "alpha")
	f.healthy(); f.close()
end)

case("invalid fixed selection never silently chooses a different credential", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local registry = f.env.require("provider/registry")
	for _, selected in ipairs({ 0, 4, 1.5, "2", false }) do
		local record = registry.blank("custom")
		record.baseUrl, record.apiKey, record.model = "https://keys.fixture/v1", "alpha\nbeta\ngamma", "fixture-model"
		record.keyMode, record.selectedKey = "single", selected
		check("invalid selection is rejected without selecting another key", not keys.validate(record) and #keys.requestKeys(record) == 0
			and registry.nextKey(record) == nil)
		local result = f.run(function() return f.env.require("provider/chat").complete(record, {
			messages = { { role = "user", content = "hello" } }, stream = false, attempts = 1 }) end)
		check("invalid fixed selection cannot dispatch an unauthenticated fallback", result == nil and f.h.http.requestCount == 0)
	end
	local empty = { apiKey = "", keyNames = {}, keyMode = "rotate", selectedKey = 1 }
	check("empty rotation is valid but cannot be pinned", keys.validate(empty) and not keys.setMode(empty, "single"))
	f.healthy(); f.close()
end)

case("aliases are trimmed single-line UTF-8 and never limit the number of credentials", function()
	local f = F.new(); local keys = f.env.require("runtime/provider_keys")
	local record = { apiKey = "alpha" }
	assert(keys.rename(record, 1, "  Personal  "))
	check("names are trimmed at entry", record.keyNames[1] == "Personal")
	for _, name in ipairs({ string.rep("x", 121), "bad\nname", "bad\tname", "bad\0name", "bad\255name", "bad\226\128\168name" }) do
		check("invalid name is rejected without changing the alias", not keys.rename(record, 1, name) and record.keyNames[1] == "Personal")
	end
	local multibyte = string.rep("\195\169", 60)
	assert(keys.rename(record, 1, multibyte))
	check("the label bound counts UTF-8 bytes", not keys.rename(record, 1, multibyte .. "\195\169") and record.keyNames[1] == multibyte)
	local incoming = {}
	for index = 1, 100 do incoming[index] = "fixture-key-" .. index end
	assert(keys.add(record, table.concat(incoming, "\n")))
	check("large pools retain every credential and matching name slot", #keys.keys(record) == 101 and #record.keyNames == 101 and keys.validate(record))
	f.healthy(); f.close()
end)

case("included access clears personal aliases and request policy", function()
	local f = F.new(); local registry = f.env.require("provider/registry")
	local record = registry.blank("projectuai-free")
	record.apiKey, record.keyNames, record.keyMode, record.selectedKey = "alpha\nbeta", { "Personal", "Backup" }, "single", 2
	assert(f.env.require("provider/community_key").apply(record))
	local keys = f.env.require("runtime/provider_keys")
	check("included access owns one unnamed key with default rotation", #keys.entries(record) == 1 and keys.entries(record)[1].name == ""
		and keys.mode(record) == "rotate" and keys.selected(record) == 1 and keys.validate(record))
	f.healthy(); f.close()
end)

suite.finish()
