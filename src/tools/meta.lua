-- Metadata about the place, the client build and Roblox users.
return function(env)
	local util = env.require("runtime/util")
	local http = env.require("net/http")
	local H = env.require("tools/helpers")
	local clock = env.require("runtime/clock")
	local cache, order = {}, {}
	local function stopped(ctx) return ctx and ctx.aborted and ctx.aborted() end
	local function productInfo(id, refresh, ctx)
		if stopped(ctx) then return nil end
		local hit = not refresh and cache[id]
		if hit and clock.since(hit.at) < 60000 then return hit.value, true end
		local ok, info = pcall(function() return env.services.MarketplaceService:GetProductInfo(id) end)
		if not ok or type(info) ~= "table" or type(info.Name) ~= "string" or stopped(ctx) then return nil end
		if not cache[id] then
			if #order >= 32 then cache[table.remove(order, 1)] = nil end
			order[#order + 1] = id
		end
		cache[id] = { value = info, at = clock.ms() }
		return info, false
	end
	local function json(spec, ctx)
		spec.aborted = ctx and ctx.aborted
		local value, err, response = http.json(spec)
		if stopped(ctx) then return nil, "metadata lookup was aborted" end
		if response and not response.ok then return nil, "metadata endpoint returned HTTP " .. tostring(response.status) end
		if type(value) ~= "table" or value.errors or value.error then return nil, err or "metadata endpoint returned no usable result" end
		return value
	end

	return {
		{
			name = "game_info",
			examples = { { title = "Identify the current place", arguments = {},
				note = "Use the current place identity when choosing an authoring folder or interpreting saved notes." } },
			risk = "read",
			description = "Identify the current place: name, IDs, creator, live player counts and uptime. Product metadata is cached for 60 seconds; refresh=true bypasses it.",
			parameters = { type = "object", properties = { refresh = { type = "boolean" } }, required = {} },
			run = function(args, ctx)
				local rows = {
					{ "PlaceId", tostring(game.PlaceId) },
					{ "GameId", tostring(game.GameId) },
					{ "JobId", tostring(game.JobId) },
					{ "PlaceVersion", tostring(game.PlaceVersion) },
				}

				local info, cached = productInfo(game.PlaceId, args.refresh, ctx)
				if stopped(ctx) then return H.fail("metadata lookup was aborted") end
				if info then
					rows[#rows + 1] = { "Name", tostring(info.Name) }
					if info.Creator and info.Creator.Name then
						rows[#rows + 1] = { "Creator", tostring(info.Creator.Name) }
					end
					if info.Description and util.trim(info.Description) ~= "" then
						rows[#rows + 1] = { "Description", util.ellipsis(info.Description, 200) }
					end
				end

				local okPlayers, players = pcall(function() return env.players:GetPlayers() end)
				if okPlayers then
					rows[#rows + 1] = { "Players", string.format("%d of %d", #players, env.players.MaxPlayers or 0) }
				end

				local okTime, gameTime = pcall(function() return env.services.Workspace.DistributedGameTime end)
				if okTime then rows[#rows + 1] = { "Server uptime", util.formatDuration(gameTime * 1000) } end

				return { text = H.keyValues(rows), data = { placeId = game.PlaceId, gameId = game.GameId,
					name = info and info.Name, cached = cached == true, players = okPlayers and #players or nil } }
			end,
		},
		{
			name = "place_info",
			risk = "read",
			description = "Look up a Roblox place or asset by positive id. Native product metadata is cached for 60 seconds; refresh=true bypasses it. HTTP is a fallback when native lookup fails.",
			parameters = {
				type = "object",
				properties = {
					id = { type = "integer", minimum = 1, maximum = 9007199254740991, description = "Place or asset id. Defaults to the current place." },
					refresh = { type = "boolean" },
				},
				required = {},
			},
			run = function(args, ctx)
				local id = tonumber(args.id) or game.PlaceId
				local info, cached = productInfo(id, args.refresh, ctx)
				if stopped(ctx) then return H.fail("metadata lookup was aborted") end
				if info then
					local rows = {
						{ "Name", tostring(info.Name) },
						{ "AssetId", tostring(id) },
						{ "Type", tostring(info.AssetTypeId or "unknown") },
						{ "Creator", info.Creator and tostring(info.Creator.Name) or "unknown" },
						{ "Created", tostring(info.Created or "unknown") },
						{ "Updated", tostring(info.Updated or "unknown") },
					}
					if info.Description and util.trim(info.Description) ~= "" then
						rows[#rows + 1] = { "Description", util.ellipsis(info.Description, 300) }
					end
					return { text = H.keyValues(rows), data = { id = id, name = info.Name, cached = cached == true } }
				end

				-- MarketplaceService fails for some asset types; the web API answers
				-- for more of them.
				local decoded, err = json({
					url = "https://economy.roblox.com/v2/assets/" .. tostring(id) .. "/details",
					method = "GET",
					attempts = 2,
					tag = "tool:place_info",
				}, ctx)
				if not decoded then return H.fail(err or "asset lookup failed") end
				if type(decoded.Name) ~= "string" then return H.fail("asset lookup returned no asset name") end
				return { text = H.keyValues({
					{ "Name", tostring(decoded.Name) },
					{ "AssetId", tostring(decoded.AssetId or id) },
					{ "Creator", decoded.Creator and tostring(decoded.Creator.Name) or "unknown" },
					{ "Description", util.ellipsis(tostring(decoded.Description or ""), 300) },
				}), data = { id = decoded.AssetId or id, name = decoded.Name, cached = false } }
			end,
		},
		{
			name = "user_lookup",
			risk = "read",
			needs = { "http" },
			description = "Look up a Roblox account by username or id.",
			parameters = {
				type = "object",
				properties = {
					username = { type = "string", minLength = 1, maxLength = 20 },
					user_id = { type = "integer", minimum = 1, maximum = 9007199254740991 },
				},
				required = {},
			},
			run = function(args, ctx)
				if args.user_id ~= nil and args.username ~= nil then return H.fail("use username or user_id, not both") end
				local userId = tonumber(args.user_id)

				if not userId then
					local username = util.trim(args.username)
					if username == "" then return H.fail("give a username or a user id") end
					local decoded, err = json({
						url = "https://users.roblox.com/v1/usernames/users",
						method = "POST",
						headers = { ["Content-Type"] = "application/json" },
						body = util.encode({ usernames = { username }, excludeBannedUsers = false }),
						attempts = 2,
						tag = "tool:user_lookup",
					}, ctx)
					if not decoded then return H.fail(err or "lookup failed") end
					local first = decoded.data and decoded.data[1]
					if type(first) ~= "table" or type(first.id) ~= "number" or first.id <= 0 then return H.fail("no account is named '" .. username .. "'") end
					userId = first.id
				end

				local decoded, err = json({
					url = "https://users.roblox.com/v1/users/" .. tostring(userId),
					method = "GET",
					attempts = 2,
					tag = "tool:user_lookup",
				}, ctx)
				if not decoded then return H.fail(err or "lookup failed") end
				if type(decoded.name) ~= "string" or type(decoded.id) ~= "number" then return H.fail("lookup returned no account identity") end
				return { text = H.keyValues({
					{ "Username", tostring(decoded.name) },
					{ "DisplayName", tostring(decoded.displayName) },
					{ "UserId", tostring(decoded.id) },
					{ "Created", tostring(decoded.created) },
					{ "Banned", tostring(decoded.isBanned) },
					{ "Description", util.ellipsis(tostring(decoded.description or ""), 240) },
				}), data = { id = decoded.id, username = decoded.name, displayName = decoded.displayName, banned = decoded.isBanned } }
			end,
		},
		{
			name = "roblox_version",
			risk = "read",
			needs = { "http" },
			description = "Report the current Roblox client release version.",
			parameters = { type = "object", properties = util.emptyObject(), required = {} },
			run = function(_, ctx)
				local decoded, err = json({
					url = "https://clientsettingscdn.roblox.com/v2/client-version/WindowsPlayer/channel/live",
					method = "GET",
					attempts = 2,
					tag = "tool:roblox_version",
				}, ctx)
				if not decoded then return H.fail(err or "version lookup failed") end
				if type(decoded.version) ~= "string" then return H.fail("version endpoint returned no release version") end
				return { text = H.keyValues({
					{ "Version", tostring(decoded.version) },
					{ "Upload", tostring(decoded.clientVersionUpload) },
					{ "Bootstrapper", tostring(decoded.bootstrapperVersion or "unknown") },
				}), data = { version = decoded.version, upload = decoded.clientVersionUpload, channel = "live", platform = "WindowsPlayer" } }
			end,
		},
	}
end
