-- The world around the character: geometry queries, lighting and the camera.
return function(env)
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")
	local scan = env.require("runtime/instance_scan")
	local clock = env.require("runtime/clock")
	local function aborted(ctx)
		if not ctx or not ctx.aborted then return false end
		local ok, value = pcall(ctx.aborted); return not ok or value == true
	end

	local LIGHTING_FIELDS = {
		"ClockTime", "TimeOfDay", "Brightness", "Ambient", "OutdoorAmbient",
		"FogColor", "FogStart", "FogEnd", "GlobalShadows", "ExposureCompensation",
		"EnvironmentDiffuseScale", "EnvironmentSpecularScale", "ShadowSoftness",
	}

	local function rootPosition()
		local character = env.plr and env.plr.Character
		local root = character and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
		return root and root.Position or nil
	end

	return {
		{
			name = "raycast",
			risk = "read",
			description = "Cast a ray and report the first thing it hits. Origin defaults to your character; direction is a vector, not a target point.",
			parameters = {
				type = "object",
				properties = {
					origin = { type = "string", description = "Start as 'x, y, z'. Defaults to your position." },
					direction = { type = "string", description = "Direction and length as 'x, y, z', e.g. '0, -50, 0' to look down 50 studs." },
					ignore_character = { type = "boolean", description = "Exclude your own character. Default true." },
				},
				required = { "direction" },
			},
			run = function(args)
				local origin = rootPosition() or Vector3.new(0, 10, 0)
				if args.origin and util.trim(args.origin) ~= "" then
					local parsed = H.coerce(args.origin, Vector3.new(0, 0, 0))
					if not parsed then return H.fail("origin must be three numbers") end
					origin = parsed
				end
				local direction = H.coerce(args.direction, Vector3.new(0, 0, 0))
				if not direction then return H.fail("direction must be three numbers") end
				if direction.Magnitude == 0 then return H.fail("direction cannot be zero") end

				local params = RaycastParams.new()
				if args.ignore_character ~= false and env.plr and env.plr.Character then
					params.FilterType = Enum.RaycastFilterType.Exclude
					params.FilterDescendantsInstances = { env.plr.Character }
				end

				local ok, result = pcall(function()
					return env.services.Workspace:Raycast(origin, direction, params)
				end)
				if not ok then return H.fail("the raycast was rejected: " .. tostring(result)) end
				if not result then
					return string.format("Nothing hit within %.1f studs from %s.", direction.Magnitude, H.show(origin))
				end

				return { text = H.keyValues({
					{ "Hit", H.pathOf(result.Instance) },
					{ "Class", tostring(result.Instance and result.Instance.ClassName) },
					{ "Position", H.show(result.Position) },
					{ "Normal", H.show(result.Normal) },
					{ "Distance", string.format("%.2f studs", result.Distance) },
					{ "Material", tostring(result.Material and result.Material.Name or "unknown") },
				}), data = { hit = true, instanceId = env.require("runtime/instance_refs").id(result.Instance), path = H.pathOf(result.Instance), distance = result.Distance } }
			end,
		},
		{
			name = "parts_near",
			examples = { { title = "Inspect nearby geometry", arguments = { radius = 30, limit = 12 },
				note = "Distances are local observations. Incomplete spatial queries do not prove that an object is absent." } },
			risk = "read",
			description = "Page nearby parts sorted by captured distance. Uses the spatial query with a 20,000-part cap, or a cooperative subtree scan on older hosts. Incomplete results do not prove absence; restart pagination if the scene moves.",
			parameters = {
				type = "object",
				properties = {
					position = { type = "string", description = "Centre as 'x, y, z'. Defaults to your position." },
					radius = { type = "number", description = "Studs, 1-500. Default 20.", minimum = 1, maximum = 500 },
					limit = { type = "integer", minimum = 1, maximum = 80 },
					offset = { type = "integer", minimum = 1 },
				},
				required = {},
			},
			run = function(args, ctx)
				if aborted(ctx) then return H.fail("nearby-part scan cancelled") end
				local centre = rootPosition() or Vector3.new(0, 0, 0)
				if args.position and util.trim(args.position) ~= "" then
					local parsed = H.coerce(args.position, Vector3.new(0, 0, 0))
					if not parsed then return H.fail("position must be three numbers") end
					centre = parsed
				end
				local radius = util.clamp(tonumber(args.radius) or 20, 1, 500)

				local found, scanStats
				local ok = pcall(function()
					local params = OverlapParams.new(); params.MaxParts = 20000
					found = env.services.Workspace:GetPartBoundsInRadius(centre, radius, params)
				end)
				if ok and type(found) == "table" and #found >= 20000 then scanStats = { complete = false, reason = "spatial result cap" } end
				if not ok or type(found) ~= "table" then
					-- Older hosts lack the spatial query. Walk incrementally and make
					-- incomplete results explicit; a capped scan cannot prove absence.
					found = {}
					local unreadableParts = 0
					scanStats = scan.descendants(env.services.Workspace, ctx, function(node)
						local readable, nearby = pcall(function()
							return node:IsA("BasePart") and (node.Position - centre).Magnitude <= radius
						end)
						if not readable then unreadableParts = unreadableParts + 1
						elseif nearby then
							found[#found + 1] = node
						end
					end, 20000)
					if unreadableParts > 0 then
						scanStats.complete, scanStats.reason = false, scanStats.reason or "unreadable parts"
					end
				end
				local sorted = {}
				for index = 1, math.min(#found, 20000) do
					if index % 128 == 0 then clock.wait() end
					if aborted(ctx) then return { ok = false, text = "Nearby-part scan cancelled.", data = { status = "aborted", complete = false } } end
					local part = found[index]
					local readable, distance = pcall(function() return (part.Position - centre).Magnitude end)
					if readable then sorted[#sorted + 1] = { part = part, distance = distance, order = index }
					else scanStats = scanStats or {}; scanStats.complete, scanStats.reason = false, scanStats.reason or "unreadable parts" end
				end
				local note = scanStats and not scanStats.complete and ("\nScan incomplete: " .. tostring(scanStats.reason or "unreadable objects") .. ". Unvisited or unreadable parts may also match.") or ""

				if scanStats and scanStats.reason == "aborted" then return { ok = false, text = "Nearby-part scan cancelled.", data = { status = "aborted", complete = false } } end
				if #found == 0 then
					return string.format("No parts found within %.0f studs of %s.", radius, H.show(centre)) .. note
				end
				table.sort(sorted, function(a, b)
					if a.distance == b.distance then return a.order < b.order end
					return a.distance < b.distance
				end)
				local result = H.page(sorted, args, string.format("%d readable part(s) within %.0f studs of %s.%s", #sorted, radius, H.show(centre), note), function(row)
						local part = row.part
						return string.format("%s [%s] %.1f studs, size %s",
							H.pathOf(part), part.ClassName, row.distance, H.show(part.Size))
					end, 25, 80)
				if result.data then result.data.complete = not scanStats or scanStats.complete == true end
				return result
			end,
		},
		{
			name = "lighting_get",
			risk = "read",
			description = "Read current lighting settings and up to 30 direct effects. Select properties to avoid unrelated reads.",
			parameters = { type = "object", properties = {
				properties = { type = "array", maxItems = 30, items = { type = "string", minLength = 1, maxLength = 64 } },
				effects = { type = "boolean", description = "Include direct lighting effects; default true." },
			}, required = {} },
			run = function(args)
				local lighting = env.services.Lighting
				local rows, unreadable, seen = {}, {}, {}
				for _, field in ipairs(args.properties or LIGHTING_FIELDS) do
					if not seen[field] then
						local ok, value = pcall(function() return lighting[field] end)
						if ok and value ~= nil and type(value) ~= "function" then rows[#rows + 1] = { field, util.ellipsis(H.show(value), 160) }
						else unreadable[#unreadable + 1] = field end
						seen[field] = true
					end
				end
				local effects, omitted = {}, 0
				if args.effects ~= false then
					local ok, children = pcall(function() return lighting:GetChildren() end)
					if ok then
						for index = 1, math.min(30, #children) do local child = children[index]; effects[#effects + 1] = util.ellipsis(child.Name, 80) .. " [" .. child.ClassName .. "]" end
						omitted = math.max(0, #children - #effects)
					else unreadable[#unreadable + 1] = "effects" end
				end
				local text = H.keyValues(rows)
				if #effects > 0 then text = text .. "\nEffects: " .. table.concat(effects, ", ") end
				return { text = text, data = { unreadable = unreadable, omittedEffects = omitted, complete = #unreadable == 0 and omitted == 0 } }
			end,
		},
		{
			name = "lighting_set",
			risk = "write",
			description = "Change a lighting property. Client-side, so a script that reasserts lighting will overwrite it.",
			parameters = {
				type = "object",
				properties = {
					property = { type = "string", description = "e.g. 'ClockTime', 'Brightness', 'FogEnd', 'Ambient'." },
					value = { type = "string", description = "Text form: numbers plain, colours as 'r, g, b'." },
				},
				required = { "property", "value" },
			},
			run = function(args, ctx)
				local lighting = env.services.Lighting
				local name = util.trim(args.property)
				local okRead, current = pcall(function() return lighting[name] end)
				if not okRead then return H.fail("Lighting has no property '" .. name .. "'") end
				local value, err = H.coerce(args.value, current)
				if value == nil then return H.fail(err or "could not convert that value") end
				return H.writeProperties(lighting, { { property = name, value = value } }, "Lighting", ctx)
			end,
		},
		{
			name = "camera_get",
			risk = "read",
			description = "Read the camera: position, field of view, type and subject.",
			parameters = { type = "object", properties = util.emptyObject(), required = {} },
			run = function()
				local camera = env.services.Workspace.CurrentCamera
				if not camera then return H.fail("there is no current camera") end
				return { text = H.keyValues({
					{ "Position", H.show(camera.CFrame.Position) },
					{ "FieldOfView", H.show(camera.FieldOfView) },
					{ "CameraType", H.show(camera.CameraType) },
					{ "CameraSubject", camera.CameraSubject and H.pathOf(camera.CameraSubject) or "none" },
					{ "ViewportSize", H.show(camera.ViewportSize) },
				}), data = { instanceId = env.require("runtime/instance_refs").id(camera), localObservation = true } }
			end,
		},
		{
			name = "camera_set",
			risk = "write",
			description = "Change the camera's field of view, type, or position. Setting a position needs CameraType 'Scriptable' to stick.",
			parameters = {
				type = "object",
				properties = {
					field_of_view = { type = "number", minimum = 1, maximum = 120 },
					camera_type = { type = "string", description = "e.g. 'Custom', 'Scriptable', 'Fixed'." },
					position = { type = "string", description = "'x, y, z'." },
				},
				required = {},
			},
			run = function(args, ctx)
				local camera = env.services.Workspace.CurrentCamera
				if not camera then return H.fail("there is no current camera") end
				local edits = {}

				local fov = tonumber(args.field_of_view)
				if fov then
					if fov ~= fov or fov < 1 or fov > 120 then return H.fail("field_of_view must be between 1 and 120") end
					edits[#edits + 1] = { property = "FieldOfView", value = fov }
				end
				if args.camera_type and util.trim(args.camera_type) ~= "" then
					local value, err = H.coerce(args.camera_type, camera.CameraType)
					if value == nil then return H.fail(err) end
					edits[#edits + 1] = { property = "CameraType", value = value }
				end
				if args.position and util.trim(args.position) ~= "" then
					local target = H.coerce(args.position, Vector3.new(0, 0, 0))
					if not target then return H.fail("position must be three numbers") end
					edits[#edits + 1] = { property = "CFrame", value = CFrame.new(target) }
				end

				local result = H.writeProperties(camera, edits, "Camera", ctx)
				if args.position and camera.CameraType ~= Enum.CameraType.Scriptable then result.text = result.text .. ". CameraType is not Scriptable; camera scripts may replace the position." end
				return result
			end,
		},
	}
end
