-- Image references must survive the Lua pipeline without becoming text markers.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local F = require("workspace_fixture")
local suite = F.suite("Image input")
local check, case = suite.check, suite.case
local function image(sessionId)
	return { url = "uai-image://pic_fixture0001/" .. string.rep("a", 64), sessionId = sessionId,
		mediaType = "image/png", bytes = 120, name = "reference.png" }
end

case("attachment validation enforces scope, limits and uniqueness", function()
	local f = F.new(); local images = f.env.require("runtime/images")
	local valid = assert(images.validate({ image("s1") }, "s1"))
	check("valid references remain compact", #valid == 1 and #f.h.json.encode(valid) < 400)
	check("another conversation cannot reuse a reference", images.validate(valid, "s2") == nil)
	check("duplicates cannot inflate the image context", images.validate({ valid[1], valid[1] }, "s1") == nil)
	local bad = image("s1"); bad.url = "https://example.invalid/image.png"
	check("arbitrary URLs are not accepted as bridge references", images.validate({ bad }, "s1") == nil)
	bad = image("s1"); bad.bytes = 6 * 1024 * 1024
	check("oversize references are refused before dispatch", images.validate({ bad }, "s1") == nil)
	check("ordinary text needs no images", #assert(images.validate(nil, "s1")) == 0)
	f.healthy(); f.close()
end)

case("context persistence and both adapters preserve image content", function()
	local f = F.new(); local ctx = f.env.require("agent/context").new()
	ctx.pushUser("Describe these colors", { image("s1") })
	local restored = f.env.require("agent/context").new(); restored.restore(ctx.serialise())
	local user = restored.messages[1]
	check("saved context retains scoped image references", user.images[1].url == image("s1").url and user.content == "Describe these colors")
	local openai = f.env.require("provider/openai").wireMessages(restored.messages)
	check("Chat Completions receives text plus an image block", openai[1].content[1].text == user.content and openai[1].content[2].type == "image_url" and openai[1].content[2].image_url.url == user.images[1].url)
	local anthropic = f.env.require("provider/anthropic").wireMessages(restored.messages)
	check("Messages receives a real image source rather than a table string", anthropic[1].content[2].type == "image" and anthropic[1].content[2].source.url == user.images[1].url)
	local converted = f.env.require("runtime/images").anthropic({ { type = "image_url", image_url = { url = "data:image/png;base64,AA==" } } })
	check("direct multimodal content converts to Messages base64", converted[1].source.type == "base64" and converted[1].source.data == "AA==" and converted[1].source.media_type == "image/png")
	local usage = f.env.require("agent/usage")
	check("context estimates reserve image tokens in both shapes", usage.estimateMessages(restored.messages) == usage.estimateMessages(openai) and usage.estimateMessages(openai) >= 1600)
	f.healthy(); f.close()
end)

case("image-only sends retain readable history and pass attachments to the loop", function()
	local f = F.new(); local config = f.env.require("runtime/config")
	config.set("bridge.enabled", true, { quiet = true })
	local session = f.env.require("agent/session").newThread()
	local captured
	f.loaded["agent/loop"] = { run = function(target, text, images)
		captured = images; target.ctx.pushUser(text, images); return "Received"
	end }
	check("image-only send starts", session.send("", nil, nil, { image(session.id) }))
	f.h.settle(0.3)
	check("the loop receives the attachment", captured and captured[1].sessionId == session.id and session.ctx.messages[1].images[1].url == captured[1].url)
	check("transcript is readable and does not expose capabilities or bytes", session.log[1].text:find("attached image", 1, true) and not f.h.json.encode(session.log):find("uai-image", 1, true))
	f.healthy(); f.close()
end)

case("image requests always use the relay even with Game runtime selected", function()
	local f = F.new(); local config = f.env.require("runtime/config")
	config.set("bridge.enabled", true, { quiet = true }); config.set("bridge.runtime", "game")
	local http = f.env.require("net/http"); local captured = {}
	http.send = function(spec)
		captured[#captured + 1] = spec
		local body = spec.url:find("/messages", 1, true) and '{"content":[{"type":"text","text":"Visible"}],"stop_reason":"end_turn"}'
			or '{"choices":[{"message":{"role":"assistant","content":"Visible"},"finish_reason":"stop"}]}'
		return { ok = true, status = 200, body = body, headers = {}, via = "web", ms = 10 }
	end
	local registry = f.env.require("provider/registry")
	for _, api in ipairs({ "openai", "anthropic" }) do
		local record = registry.blank("custom"); record.api, record.model, record.baseUrl = api, "vision-fixture", "https://provider.invalid/v1"
		local adapter = f.env.require("provider/" .. api)
		local result, err = adapter.complete(record, { stream = false, sessionId = "s1", messages = { { role = "user", content = "Look", images = { image("s1") } } } })
		check(api .. " request succeeds through the fixture", result and result.content == "Visible" and not err)
		check(api .. " cannot send a reference directly to a provider", captured[#captured].relay == true and captured[#captured].sessionId == "s1")
	end
	f.healthy(); f.close()
end)

suite.finish()
