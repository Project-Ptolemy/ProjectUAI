-- Local identity belongs to the shared sidebar, not to consumer scripts.
return function(env)
	local C = env.require("core")
	local T = env.require("theme")
	local M = {}
	local placeName, loading, listeners = nil, false, {}
	local function resolvePlace()
		if loading or placeName then return end
		loading = true
		-- Native requests finish naturally; cleanup removes their recipients.
		task.defer(function()
			local ok, result = pcall(function() return env.services.MarketplaceService:GetProductInfo(game.PlaceId) end)
			if ok and type(result) == "table" and type(result.Name) == "string" and result.Name ~= "" then placeName = C.truncate(result.Name, 160) end
			loading = false
			for callback in pairs(listeners) do callback(placeName) end
		end)
	end
	function M.new(window, parent, gameName)
		local self = C.owner(window)
		local player = env.services.Players.LocalPlayer
		local username = player and player.Name or "Local player"
		local displayName = player and player.DisplayName or username
		self.Frame = C.node(self, "Frame", parent, { Name = "Profile", ClipsDescendants = true }, { BackgroundColor3 = "Sidebar" })
		C.node(self, "Frame", self.Frame, { Size = UDim2.new(1, 0, 0, 1) }, { BackgroundColor3 = "Subtle" })
		local avatar = C.node(self, "Frame", self.Frame, { Name = "Avatar", Size = UDim2.fromOffset(T.Size.Avatar, T.Size.Avatar) }, { BackgroundColor3 = "Raised" })
		C.corner(avatar, T.Size.Avatar / 2)
		local initial = C.text(self, avatar, displayName:match("^.[\128-\191]*") or "?", "Heading", "Text", { Name = "Initial", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center })
		local photo = C.node(self, "ImageLabel", avatar, { Name = "Headshot", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Crop })
		C.corner(photo, T.Size.Avatar / 2)
		local function loaded() if self._scope.alive then initial.Visible = photo.IsLoaded ~= true end end
		self._scope:Connect(photo:GetPropertyChangedSignal("IsLoaded"), loaded)
		if player and player.UserId > 0 then
			photo.Image = string.format("rbxthumb://type=AvatarHeadShot&id=%.0f&w=150&h=150", player.UserId)
			task.defer(function()
				if not self._scope.alive then return end
				local ok, image, ready = pcall(function() return env.services.Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150) end)
				if not self._scope.alive or not photo.Parent then return end
				if ok and ready and type(image) == "string" then photo.Image = image end
				pcall(function() env.services.ContentProvider:PreloadAsync({ photo }) end)
				loaded()
			end)
		end
		local name = C.text(self, self.Frame, displayName, "Heading", "Text", { Name = "DisplayName", TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local account = C.text(self, self.Frame, "@" .. username, "Caption", "Muted", { Name = "Username", TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local place = C.text(self, self.Frame, gameName or placeName or "Current experience", "Caption", "Secondary", { Name = "GameName", TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
		local function update(value) if self._scope.alive and value then place.Text = value end end
		if not gameName then listeners[update] = true; self._scope:Add(function() listeners[update] = nil end); resolvePlace() end
		function self.Layout(width)
			local line = math.ceil(18 * window.TextScale)
			local height = math.max(T.Size.Avatar, line * 3) + 28
			local left = 12 + T.Size.Avatar + 10
			avatar.Position = UDim2.fromOffset(12, 14)
			name.Position, name.Size = UDim2.fromOffset(left, 14), UDim2.fromOffset(math.max(1, width - left - 12), line)
			account.Position, account.Size = UDim2.fromOffset(left, 14 + line), UDim2.fromOffset(math.max(1, width - left - 12), line)
			place.Position, place.Size = UDim2.fromOffset(left, 14 + line * 2), UDim2.fromOffset(math.max(1, width - left - 12), line)
			self.Frame.Size = UDim2.fromOffset(width, height)
			return height
		end
		return self
	end
	return M
end
