-- Compact, session-owned references. Only the bridge expands these to image
-- bytes, immediately before its provider request; transcripts stay text-only.
return function(env)
	local util = env.require("runtime/util")
	local M = {}
	local types = { ["image/png"] = true, ["image/jpeg"] = true, ["image/webp"] = true }
	function M.validate(images, sessionId)
		if images == nil then return {} end
		if type(images) ~= "table" or not util.isArray(images) or #images > 8 then return nil, "Invalid image attachment list" end
		local out, seen, bytes = {}, {}, 0
		for _, image in ipairs(images) do
			if type(image) ~= "table" or type(image.url) ~= "string" or #image.url > 200
				or not image.url:match("^uai%-image://pic_[%w_-]+/%x+$")
				or #(image.url:match("/(%x+)$") or "") ~= 64
				or image.sessionId ~= sessionId or not types[image.mediaType]
				or type(image.bytes) ~= "number" or image.bytes ~= image.bytes or image.bytes < 1 or image.bytes > 5 * 1024 * 1024 then
				return nil, "Invalid or cross-conversation image attachment; attach the picture again"
			end
			if seen[image.url] then return nil, "Duplicate image attachment" end
			seen[image.url], bytes = true, bytes + image.bytes
			out[#out + 1] = { url = image.url, sessionId = sessionId, mediaType = image.mediaType,
				bytes = image.bytes, name = util.truncate(tostring(image.name or "Image"), 160) }
		end
		if bytes > 20 * 1024 * 1024 then return nil, "Images exceed the 20 MiB message limit" end
		return out
	end
	function M.hasReferences(messages)
		for _, message in ipairs(messages or {}) do
			if type(message.images) == "table" and #message.images > 0 then return true end
		end
		return false
	end
	function M.openai(content, images)
		if not images or #images == 0 then return content end
		local blocks = type(content) == "table" and util.deepCopy(content) or {}
		if type(content) ~= "table" and tostring(content or "") ~= "" then blocks[1] = { type = "text", text = tostring(content) } end
		for _, image in ipairs(images) do blocks[#blocks + 1] = { type = "image_url", image_url = { url = image.url, detail = "auto" } } end
		return blocks
	end
	function M.anthropic(content, images)
		content = M.openai(content, images)
		if type(content) ~= "table" then return tostring(content or "") end
		local blocks = {}
		for _, block in ipairs(content) do
			if block.type == "text" then blocks[#blocks + 1] = { type = "text", text = tostring(block.text or "") }
			elseif block.type == "image_url" and type(block.image_url) == "table" then
				local url = tostring(block.image_url.url or "")
				local media, data = url:match("^data:(image/[%w+.-]+);base64,(.+)$")
				blocks[#blocks + 1] = { type = "image", source = media and { type = "base64", media_type = media, data = data } or { type = "url", url = url } }
			elseif block.type == "image" then blocks[#blocks + 1] = util.deepCopy(block)
			end
		end
		return blocks
	end
	return M
end
