-- Shared native artwork. The library build also generates the client's copy.
-- This factory has no application, calendar, input, asset, or task dependencies.
return function(env)
	local M = { MaxNodes = 160 }
	local rgb = Color3.fromRGB
	local white, ink = rgb(255, 249, 237), rgb(43, 27, 52)
	local orange, gold, green = rgb(246, 138, 43), rgb(255, 211, 105), rgb(69, 159, 104)
	function M.new(parent)
		local scenes = {}
		local motifGold = gold
		local self = { Alive = true, NodeCount = 0, _groups = {}, _cutouts = {}, _width = 0, _height = 0 }
		local function node(class, owner, name)
			self.NodeCount = self.NodeCount + 1
			assert(self.NodeCount <= M.MaxNodes, "Seasonal artwork exceeded its node budget")
			local object = Instance.new(class)
			object.Name = name
			if class == "Frame" then
				object.BorderSizePixel, object.Active, object.Selectable = 0, false, false
				object.BackgroundTransparency, object.ZIndex = 1, 1
			end
			object.Parent = owner
			return object
		end
		local function piece(owner, name, x, y, width, height, color, rotation, rounded)
			local object = node("Frame", owner, name)
			object.Position, object.Size = UDim2.fromScale(x / 100, y / 100), UDim2.fromScale(width / 100, height / 100)
			object.BackgroundColor3, object.BackgroundTransparency = color, 0
			object.Rotation = rotation or 0
			if rounded then
				local corner = node("UICorner", object, "Round")
				corner.CornerRadius = UDim.new(1, 0)
			end
			return object
		end
		local function group(name, x, y, scale)
			local frame = node("Frame", self._scene, name)
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			self._groups[#self._groups + 1] = { Frame = frame, X = x, Y = y, Scale = scale or 1 }
			return frame
		end
		local function triangle(owner, name, x, y, width, height, color, upsideDown)
			-- Eight shallow native rectangles describe the silhouette without an
			-- image or a font glyph. Coordinates scale with the motif's container.
			for row = 1, 8 do
				local span = width * (upsideDown and (9 - row) or row) / 8
				piece(owner, name .. row, x + (width - span) / 2, y + (row - 1) * height / 8, span, height / 8 + 0.15, color)
			end
		end
		local function star(owner, name, x, y, size, color)
			piece(owner, name .. "Vertical", x + size * 0.42, y, size * 0.16, size, color, 0, true)
			piece(owner, name .. "Horizontal", x, y + size * 0.42, size, size * 0.16, color, 0, true)
			piece(owner, name .. "DiagonalA", x + size * 0.45, y + size * 0.15, size * 0.1, size * 0.7, color, 45, true)
			piece(owner, name .. "DiagonalB", x + size * 0.45, y + size * 0.15, size * 0.1, size * 0.7, color, -45, true)
		end
		local function leaf(owner, name, x, y, color, rotation)
			piece(owner, name, x, y, 12, 25, color, rotation, true)
		end
		local function sprinkles(color)
			for index, point in ipairs({ { 0.08, 0.25 }, { 0.18, 0.72 }, { 0.43, 0.2 }, { 0.58, 0.8 }, { 0.84, 0.24 }, { 0.94, 0.65 } }) do
				star(group("Sparkle" .. index, point[1], point[2], 0.2), "Spark", 15, 15, 70, color)
			end
		end
		scenes.Halloween = function()
			local pumpkin = group("Pumpkin", 0.32, 0.55, 0.98)
			piece(pumpkin, "Stem", 44, 12, 12, 20, green, -12, true)
			piece(pumpkin, "Body", 16, 27, 68, 58, orange, 0, true)
			piece(pumpkin, "LeftRib", 24, 29, 18, 54, rgb(220, 106, 29), 0, true)
			piece(pumpkin, "RightRib", 59, 29, 18, 54, rgb(220, 106, 29), 0, true)
			piece(pumpkin, "MiddleRib", 38, 27, 26, 58, rgb(255, 164, 63), 0, true)
			triangle(pumpkin, "LeftEye", 29, 43, 13, 11, ink)
			triangle(pumpkin, "RightEye", 58, 43, 13, 11, ink)
			piece(pumpkin, "Grin", 31, 62, 39, 11, ink, 0, true)
			piece(pumpkin, "Tooth", 47, 62, 8, 5, orange)
			local ghost = group("Ghost", 0.69, 0.52, 0.96)
			local ghostFill = self._mode == "Light" and rgb(204, 191, 224) or white
			piece(ghost, "Body", 25, 16, 50, 66, ghostFill, 0, true)
			piece(ghost, "Skirt", 25, 55, 50, 23, ghostFill)
			for index = 0, 3 do piece(ghost, "Hem" .. index, 25 + index * 13, 69, 12, 18, ghostFill, 0, true) end
			piece(ghost, "LeftArm", 14, 44, 23, 13, ghostFill, -25, true)
			piece(ghost, "RightArm", 63, 44, 23, 13, ghostFill, 25, true)
			piece(ghost, "LeftEye", 37, 37, 7, 11, ink, 0, true)
			piece(ghost, "RightEye", 57, 37, 7, 11, ink, 0, true)
			piece(ghost, "Mouth", 46, 51, 9, 12, ink, 0, true)
			local moon = group("Moon", 0.09, 0.48, 0.52)
			piece(moon, "Disc", 15, 15, 70, 70, motifGold, 0, true)
			piece(moon, "Crater", 31, 32, 17, 17, rgb(234, 179, 71), 0, true)
			piece(moon, "SmallCrater", 62, 50, 10, 10, rgb(234, 179, 71), 0, true)
			star(group("HalloweenStar", 0.9, 0.35, 0.26), "Star", 10, 10, 80, motifGold)
		end
		scenes.Christmas = function()
			local tree = group("FirTree", 0.35, 0.55, 1.02)
			piece(tree, "Trunk", 44, 70, 12, 20, rgb(139, 83, 47))
			triangle(tree, "LowerBough", 15, 43, 70, 36, rgb(44, 124, 81))
			triangle(tree, "MiddleBough", 23, 28, 54, 32, rgb(56, 153, 98))
			triangle(tree, "TopBough", 31, 15, 38, 29, rgb(73, 176, 116))
			star(tree, "TreeStar", 40, 1, 20, motifGold)
			for index, point in ipairs({ { 38, 43 }, { 59, 54 }, { 28, 68 }, { 48, 70 } }) do
				piece(tree, "Ornament" .. index, point[1], point[2], 8, 8, index % 2 == 0 and motifGold or rgb(242, 105, 119), 0, true)
			end
			local gift = group("Gift", 0.7, 0.6, 0.79)
			piece(gift, "Box", 14, 30, 72, 56, rgb(204, 68, 87), 0, true)
			piece(gift, "RibbonVertical", 44, 30, 12, 56, motifGold)
			piece(gift, "RibbonHorizontal", 14, 43, 72, 11, motifGold)
			piece(gift, "BowLeft", 29, 15, 25, 17, motifGold, 30, true)
			piece(gift, "BowRight", 47, 15, 25, 17, motifGold, -30, true)
			for index, x in ipairs({ 0.08, 0.19, 0.54, 0.87, 0.96 }) do
				local snow = group("Snowflake" .. index, x, index % 2 == 0 and 0.28 or 0.65, 0.28)
				local snowColor = self._mode == "Light" and rgb(85, 149, 171) or rgb(160, 218, 233)
				for angle = 0, 2 do piece(snow, "SnowArm" .. angle, 46, 5, 8, 90, snowColor, angle * 60, true) end
			end
		end
		scenes.NewYear = function()
			local center = group("CelebrationStars", 0.5, 0.52, 1)
			star(center, "GoldStar", 14, 14, 60, motifGold)
			star(center, "SmallStar", 62, 58, 27, rgb(157, 204, 250))
			for index, x in ipairs({ 0.22, 0.78 }) do
				local burst = group("Firework" .. index, x, 0.49, 0.87)
				for ray = 0, 7 do
					local arm = piece(burst, "Ray" .. ray, 47, 7, 6, 86, ray % 2 == 0 and motifGold or rgb(153, 189, 245), ray * 22.5, true)
					arm.BackgroundTransparency = 0.12
				end
				self._cutouts[#self._cutouts + 1] = piece(burst, "Center", 36, 36, 28, 28, self._background, 0, true)
			end
			local colors = { motifGold, rgb(235, 143, 196), rgb(132, 221, 187), rgb(153, 189, 245) }
			for index = 1, 12 do
				local confetti = group("Confetti" .. index, (index - 0.5) / 12, index % 2 == 0 and 0.83 or 0.15, 0.18)
				piece(confetti, "Paper", 32, 13, 26, 66, colors[(index - 1) % #colors + 1], index % 2 == 0 and 25 or -30, true)
			end
		end
		scenes.Valentine = function()
			for index, entry in ipairs({ { 0.24, 0.59, 0.7 }, { 0.5, 0.5, 1.03 }, { 0.76, 0.59, 0.7 } }) do
				local heart = group("Heart" .. index, entry[1], entry[2], entry[3])
				local fill = index == 2 and rgb(233, 81, 127) or rgb(249, 156, 194)
				piece(heart, "Point", 32, 33, 40, 40, fill, 45)
				piece(heart, "LeftLobe", 19, 14, 40, 40, fill, 0, true)
				piece(heart, "RightLobe", 46, 14, 40, 40, fill, 0, true)
				piece(heart, "Highlight", 30, 23, 7, 16, rgb(255, 219, 231), 25, true)
			end
			sprinkles(rgb(232, 142, 178))
		end
		scenes.EarthDay = function()
			local globe = group("Globe", 0.5, 0.52, 1.03)
			piece(globe, "Ocean", 12, 12, 76, 76, rgb(76, 157, 214), 0, true)
			piece(globe, "NorthAmerica", 24, 24, 27, 17, rgb(106, 191, 117), -12, true)
			piece(globe, "CentralAmerica", 39, 37, 13, 17, rgb(106, 191, 117), -25, true)
			piece(globe, "SouthAmerica", 46, 50, 18, 27, rgb(106, 191, 117), -15, true)
			piece(globe, "Europe", 61, 24, 13, 13, rgb(137, 207, 130), -20, true)
			piece(globe, "Africa", 58, 35, 22, 25, rgb(137, 207, 130), 10, true)
			piece(globe, "PolarCap", 38, 14, 26, 7, white, 0, true)
			for index, x in ipairs({ 0.25, 0.75 }) do
				local leaves = group("EarthLeaves" .. index, x, 0.56, 0.81)
				piece(leaves, "Stem", 48, 20, 4, 65, rgb(54, 120, 77), index == 1 and -25 or 25, true)
				leaf(leaves, "LeafA", 30, 27, green, -38)
				leaf(leaves, "LeafB", 56, 37, rgb(114, 194, 114), 38)
				leaf(leaves, "LeafC", 30, 55, green, -38)
			end
			sprinkles(rgb(137, 195, 204))
		end
		scenes.Pride = function()
			local ribbon = node("Frame", self._scene, "RainbowRibbon")
			ribbon.Position, ribbon.Size = UDim2.fromScale(0.13, 0.23), UDim2.fromScale(0.74, 0.57)
			ribbon.Rotation = -2
			for index, color in ipairs({ rgb(240, 83, 97), rgb(247, 152, 65), rgb(251, 217, 92), rgb(83, 180, 121), rgb(80, 147, 224), rgb(160, 98, 211) }) do
				piece(ribbon, "RainbowBand" .. index, 0, (index - 1) * 100 / 6, 100, 100 / 6 + 0.1, color)
			end
			for index, x in ipairs({ 0.13, 0.87 }) do
				local cloud = group("RainbowCloud" .. index, x, 0.58, 0.61)
				local cloudFill = self._mode == "Light" and rgb(194, 209, 232) or white
				piece(cloud, "LeftPuff", 11, 41, 42, 42, cloudFill, 0, true)
				piece(cloud, "TopPuff", 31, 25, 44, 44, cloudFill, 0, true)
				piece(cloud, "RightPuff", 55, 41, 38, 38, cloudFill, 0, true)
				piece(cloud, "Base", 29, 61, 47, 22, cloudFill, 0, true)
			end
			star(group("PrideStar", 0.5, 0.14, 0.24), "Star", 10, 10, 80, motifGold)
		end
		scenes.Peace = function()
			local dove = group("Dove", 0.5, 0.48, 1.02)
			local doveFill = self._mode == "Light" and rgb(170, 202, 219) or white
			triangle(dove, "Tail", 12, 49, 30, 25, doveFill, true)
			piece(dove, "Body", 27, 44, 48, 24, doveFill, -12, true)
			piece(dove, "Wing", 37, 13, 26, 48, doveFill, -27, true)
			piece(dove, "WingFeather", 36, 25, 9, 33, rgb(211, 230, 237), -27, true)
			piece(dove, "Head", 66, 32, 19, 19, doveFill, 0, true)
			piece(dove, "Beak", 80, 40, 11, 5, motifGold, 10)
			piece(dove, "Eye", 77, 37, 3, 3, ink, 0, true)
			piece(dove, "OliveStem", 84, 46, 3, 26, green, -25, true)
			leaf(dove, "CarriedLeaf", 85, 49, green, 35)
			for index, x in ipairs({ 0.23, 0.77 }) do
				local branch = group("OliveBranch" .. index, x, 0.6, 0.84)
				piece(branch, "Stem", 48, 12, 4, 78, rgb(62, 133, 91), index == 1 and -18 or 18, true)
				for row = 1, 3 do
					leaf(branch, "LeftLeaf" .. row, 29, 12 + row * 18, green, -45)
					leaf(branch, "RightLeaf" .. row, 56, 3 + row * 18, rgb(114, 180, 126), 45)
				end
			end
		end
		self.Root = node("Frame", parent, "SeasonalArtwork")
		self.Root.ClipsDescendants, self.Root.Visible = true, false
		function self:Layout(width, height)
			if not self.Alive then return end
			self._width, self._height = math.max(0, width), math.max(0, height)
			self.Root.Size = UDim2.fromOffset(self._width, self._height)
			self.Root.Visible = self.SceneName ~= nil and self._width > 0 and self._height > 0
			for _, entry in ipairs(self._groups) do
				local size = self._height * entry.Scale
				entry.Frame.Position = UDim2.fromOffset(self._width * entry.X, self._height * entry.Y)
				entry.Frame.Size = UDim2.fromOffset(size, size)
			end
		end
		function self:Update(name, palette)
			if not self.Alive then return end
			assert(name == nil or scenes[name], "Unknown seasonal artwork")
			palette = palette or {}
			local canvas = palette.Canvas or rgb(25, 23, 31)
			local accent = palette.Accent or gold
			motifGold = palette.Mode == "Light" and rgb(190, 133, 27) or gold
			self._background = canvas:Lerp(accent, palette.Mode == "Light" and 0.06 or 0.11)
			if self.SceneName ~= name or self._mode ~= palette.Mode then
				if self._scene then self._scene:Destroy(); self._scene = nil end
				self.SceneName, self.NodeCount, self._groups, self._cutouts, self._mode = name, 1, {}, {}, palette.Mode
				if name then
					self._scene = node("Frame", self.Root, name .. "Scene")
					self._scene.Size = UDim2.fromScale(1, 1)
					scenes[name]()
				end
			end
			self.Root:SetAttribute("SeasonalTheme", name)
			if self._scene then self._scene.BackgroundColor3, self._scene.BackgroundTransparency = self._background, 0 end
			for _, cutout in ipairs(self._cutouts) do cutout.BackgroundColor3 = self._background end
			self:Layout(self._width, self._height)
		end
		function self:Destroy()
			if not self.Alive then return end
			self.Alive, self.SceneName = false, nil
			self.Root:Destroy()
			self._scene, self._groups, self._cutouts, self.NodeCount = nil, {}, {}, 0
		end
		return self
	end
	return M
end
