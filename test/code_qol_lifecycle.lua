-- Editor conveniences retain drafts and ownership across synchronous callbacks.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Code quality of life lifecycle")
local case, check = suite.case, suite.check
local function fixture()
	local f = F.new()
	f.store, f.files, f.fs = f.env.require("runtime/code_store"), f.env.require("runtime/code_files"), f.env.require("runtime/fsx")
	f.store.init(); f.doc = f.store.active()
	assert(f.store.update(f.doc.id, "return 'original'"))
	assert(f.files.save(f.doc.id, "Source.lua"))
	return f
end

case("reentrant reopen consumes each closed view exactly once", function()
	local f = F.new(); local store = f.env.require("runtime/code_store"); store.init()
	local first = store.active(); local second = assert(store.create("Second.lua", "return 2", { select = true }))
	assert(store.close(first.id)); assert(store.close(second.id))
	local nested, called
	local off = store.changed:connect(function(event)
		if event.kind == "selection" and event.documentId == second.id and not called then
			called = true; nested = assert(store.reopen()); store.workspace.sourceId = "selected-by-callback"
		end
	end)
	local reopened = assert(store.reopen()); off()
	check("nested reopen selects the next distinct closed view", reopened == second and nested == first and store.activeId() == first.id)
	check("outer completion preserves callback-selected source", store.workspace.sourceId == "selected-by-callback")
	check("both views were consumed from recent history", store.reopen() == nil and #store.openIds() == 2)
	f.healthy(); f.close()
end)

case("a newly closed view survives another reopen's callback", function()
	local f = F.new(); local store = f.env.require("runtime/code_store"); store.init()
	local first = store.active(); local second = assert(store.create("Second.lua", "return 2", { select = true }))
	local third = assert(store.create("Third.lua", "return 3", { select = true }))
	assert(store.close(first.id)); assert(store.close(second.id))
	local off = store.changed:connect(function(event)
		if event.kind == "selection" and event.documentId == second.id then assert(store.close(third.id)) end
	end)
	assert(store.reopen()); off()
	check("callback-added history is retained in newest-first order", store.reopen() == third and store.reopen() == first)
	f.healthy(); f.close()
end)

case("a file binding changed during disk read cannot be overwritten by reload", function()
	local f = fixture(); assert(f.fs.write("Source.lua", "return 'disk'"))
	local read, changed = f.fs.read, false
	f.fs.read = function(path, options)
		local value, why = read(path, options)
		if path == "Source.lua" and not changed then changed = true; assert(f.files.save(f.doc.id, "Alternate.lua")) end
		return value, why
	end
	local result, why = f.files.reload(f.doc.id); f.fs.read = read
	check("reload rejects a stale file binding", result == nil and tostring(why):find("binding changed", 1, true))
	check("the new binding and original draft survive", f.files.binding(f.doc.id).path == "Alternate.lua" and f.doc.source == "return 'original'"
		and read("Alternate.lua") == "return 'original'" and read("Source.lua") == "return 'disk'")
	f.healthy(); f.close()
end)

case("reload publication cannot overwrite a save made by its observer", function()
	local f = fixture(); assert(f.fs.write("Source.lua", "return 'disk'"))
	local off = f.store.changed:connect(function(event)
		if event.kind == "source" and event.origin == "disk_reload" then assert(f.files.save(f.doc.id, "Observer.lua")) end
	end)
	assert(f.files.reload(f.doc.id)); off()
	check("an observer's saved binding remains authoritative", f.files.binding(f.doc.id).path == "Observer.lua"
		and f.doc.source == "return 'disk'" and f.fs.read("Observer.lua") == "return 'disk'")
	check("the observer's saved source is not marked dirty", not f.files.dirty(f.doc.id))
	f.healthy(); f.close()
end)

case("typing during disk read preserves the new unsaved draft", function()
	local f = fixture(); assert(f.fs.write("Source.lua", "return 'disk'"))
	local read, changed = f.fs.read, false
	f.fs.read = function(path, options)
		local value, why = read(path, options)
		if path == "Source.lua" and not changed then changed = true; assert(f.store.update(f.doc.id, "return 'new draft'", { origin = "typing" })) end
		return value, why
	end
	local result = f.files.reload(f.doc.id); f.fs.read = read
	check("reload cannot replace source edited during the read", result == nil and f.doc.source == "return 'new draft'" and f.files.dirty(f.doc.id))
	check("the previously observed disk base remains unchanged", f.files.binding(f.doc.id).base == "return 'original'")
	f.healthy(); f.close()
end)

suite.finish()
