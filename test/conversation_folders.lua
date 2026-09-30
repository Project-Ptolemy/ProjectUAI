-- Folder storage, legacy history, and the native mobile organization flows.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local h = envMock.new({ context = { ui = false } })
local uai = assert(h.boot())
local sessions = uai.sessions
local folder = assert(sessions.createFolder("  Shared scripts  "))
check("folder names are trimmed and stable", folder.label == "Shared scripts" and folder.kind == "custom")
for _, name in ipairs({ "", "  ", "Universal", "SHARED SCRIPTS", "bad\nname", string.rep("a", 121), "bad\255" }) do
	local result, why = sessions.createFolder(name)
	check("invalid or duplicate folder name is rejected", result == nil and type(why) == "string")
end
local chat = assert(sessions.newThread({ id = "folder-test", title = "Reusable helper", folderId = folder.id, toolFilter = { file_read = true } }))
local placeId, placeName = chat.placeId, chat.placeName
chat.ctx.pushUser("Keep this conversation")
assert(sessions.persist(chat))
check("new conversations accept a custom destination", sessions.folderLabel(chat) == "Shared scripts")
assert(sessions.renameFolder(folder.id, "My tools"))
check("rename updates the folder without altering a chat", sessions.folderLabel(chat) == "My tools" and chat.title == "Reusable helper")
check("folder search finds its conversations", sessions.search("My tools")[1].session == chat)
check("folders never change game metadata or policy", chat.placeId == placeId and chat.placeName == placeName and chat.toolFilter.file_read)
check("invalid destination cannot create a conversation", sessions.newThread({ folderId = "missing-folder" }) == nil)
check("built-in folders cannot be renamed or removed", not sessions.renameFolder("universal", "Other") and not sessions.removeFolder("universal"))
local fsx = uai.env.require("runtime/fsx")
local write = fsx.write
fsx.write = function() return false, "disk unavailable" end
local result, reason = sessions.createFolder("Unsaved")
check("failed folder persistence does not publish a folder", result == nil and reason:find("disk unavailable", 1, true))
check("failed rename preserves the previous label", not sessions.renameFolder(folder.id, "Lost name") and sessions.folderLabel(chat) == "My tools")
check("failed move preserves the previous destination", not sessions.moveToFolder(chat, "universal") and chat.folderId == folder.id)
fsx.write = write
local snapshot = h.json.decode(h.files["UAI/sessions/folder-test.json"])
snapshot.id, snapshot.folderId = "legacy-folder-test", nil
h.files["UAI/sessions/legacy-folder-test.json"] = h.json.encode(snapshot)
snapshot.id, snapshot.folderId, snapshot.policy.version = "future-folder-test", folder.id, 99
local skipped = h.json.encode(snapshot)
h.files["UAI/sessions/future-folder-test.json"] = skipped
uai.unload(); h.settle(0.2)
uai = assert(h.boot()); sessions = uai.sessions; chat = assert(sessions.get("folder-test"))
check("custom folders and membership survive restart", sessions.folderLabel(chat) == "My tools")
check("restored chats retain history and restrictions", chat.ctx.last("user").content == "Keep this conversation" and chat.toolFilter.file_read)
local legacy = assert(sessions.get("legacy-folder-test"))
check("legacy conversations stay in their recorded game", legacy.folderId == "game:" .. tostring(legacy.placeId))
assert(sessions.removeFolder(folder.id))
check("removing a folder preserves and moves its chats", sessions.folderLabel(chat) == "Universal" and chat.ctx.last("user").content == "Keep this conversation")
check("removing a folder never touches unsupported saved history", h.files["UAI/sessions/future-folder-test.json"] == skipped)
-- Simulate an archived thread still carrying the removed ID: restore resolves
-- its membership without rewriting or deleting its original saved transcript.
snapshot.id, snapshot.policy.version = "archived-folder-test", 1
h.files["UAI/sessions/archived-folder-test.json"] = h.json.encode(snapshot)
local nextFolder = assert(sessions.createFolder("Next folder"))
check("deleted folder identities are not reused", nextFolder.id ~= folder.id)
uai.unload(); h.settle(0.2)
uai = assert(h.boot()); sessions = uai.sessions
check("archived deleted memberships resolve to Universal", sessions.folderLabel("archived-folder-test") == "Universal")
check("removed-folder chats remain available after reload", sessions.get("folder-test") ~= nil)
uai.unload(); h.settle(0.2)
local protectedPath = "UAI/sessions/.folders.1.json"
h.files[protectedPath] = h.json.encode({ version = 999 })
local protected = h.files[protectedPath]
uai = assert(h.boot())
check("future catalogs refuse mutations and retain their bytes", uai.sessions.createFolder("Cannot overwrite") == nil and h.files[protectedPath] == protected)
uai.unload(); h.settle(0.2)
check("runtime folder scenarios have no asynchronous errors", #h.errors() == 0)

for _, viewport in ipairs({ { 320, 568 }, { 390, 844 }, { 844, 390 }, { 1280, 800 } }) do
	local mobile = viewport[1] ~= 1280
	h = envMock.new()
	h.services.UserInputService.TouchEnabled, h.services.UserInputService.MouseEnabled = mobile, not mobile
	h.setViewport(viewport[1], viewport[2])
	uai = assert(h.boot()); h.settle(0.5)
	uai.app.show("chat")
	local original = uai.sessions.current()
	uai.app.chatPanel.composer.field.set("Keep my original draft")
	local modal = uai.app.newConversation()
	h.settle(0.2)
	local title = h.byName("ConversationName", modal.card):FindFirstChildOfClass("TextBox")
	title.Text = "Portable scripts"
	h.click(h.byName("ConversationFolder", modal.card))
	h.click(h.byName("Option___new")); h.settle(0.2)
	local name = h.byName("NewFolderName", modal.card):FindFirstChildOfClass("TextBox")
	name.Text = ""
	h.click(h.byName("ConfirmConversation", modal.card))
	check("invalid folder keeps the form and title at " .. viewport[1], not modal.closed and title.Text == "Portable scripts" and h.byName("FolderError", modal.card).Visible)
	name.Text = "Across games"
	h.click(h.byName("ConfirmConversation", modal.card)); h.settle(0.3)
	chat = uai.sessions.current()
	check("the native form creates a named chat in its folder", modal.closed and chat.title == "Portable scripts" and chat.named and uai.sessions.folderLabel(chat) == "Across games")
	uai.app.openSession(original.id)
	check("creating a folder chat preserves the previous draft", uai.app.chatPanel.composer.field.get() == "Keep my original draft")
	if mobile then
		local nav = uai.app.showAppMenu(h.byName("Nav_menu"))
		nav.filter.set("Across games")
		check("mobile history searches folder labels", h.byName("Open_" .. chat.id, nav.card) ~= nil and h.byName("Open_" .. original.id, nav.card) == nil)
		h.click(h.byName("HistoryFolder", nav.card)); h.click(h.byName("Option_" .. chat.folderId)); h.settle(0.2)
		check("mobile folder filter retains matching history", h.byName("Open_" .. chat.id, nav.card) ~= nil)
		nav.close(); h.settle(0.3)
	end
	modal = uai.app.moveConversation(chat)
	h.click(h.byName("ConversationFolder", modal.card)); h.click(h.byName("Option_universal"))
	h.click(h.byName("ConfirmConversation", modal.card)); h.settle(0.3)
	check("native move uses Universal without switching the active chat", chat.folderId == "universal" and uai.sessions.current() == original)
	check("native folder forms assign valid properties", #h.instanceState.typeErrors == 0)
	check("native folder flows have no asynchronous errors", #h.errors() == 0)
	uai.unload(); h.settle(0.2)
end
print("Conversation folders: " .. passed .. " checks passed")
