-- Camera ray inspection. This tool returns world geometry, not screen pixels.
return function(env)
	local util = env.require("runtime/util")
	local H = env.require("tools/helpers")

	return {
		{
			name = "ray_target",
			examples = { { title = "Inspect the crosshair target", arguments = { x = 0.5, y = 0.5, distance = 1000 },
				note = "Returns a ray hit and instance identity, not a screenshot or server ownership proof." } },
			risk = "read",
			needs = { "gui" },
			description = "Raycast from a viewport fraction and return exact instance identity, hit position, normal, distance and material. Defaults to the crosshair, 10,000 studs, excluding your character and water. Does not capture pixels or infer ownership.",
			parameters = {
				type = "object",
				properties = {
					x = { type = "number", minimum = 0, maximum = 1, description = "Viewport X fraction. Default 0.5." },
					y = { type = "number", minimum = 0, maximum = 1, description = "Viewport Y fraction. Default 0.5." },
					distance = { type = "number", minimum = 1, maximum = 15000, description = "Maximum ray length in studs, default 10000." },
					ignore_water = { type = "boolean", description = "Default true." },
				},
				required = {},
			},
			run = function(args)
				local camera = env.services.Workspace.CurrentCamera
				if not camera then return H.fail("no current camera") end

				local fx = util.clamp(tonumber(args.x) or 0.5, 0, 1)
				local fy = util.clamp(tonumber(args.y) or 0.5, 0, 1)
				local viewport = camera.ViewportSize
				if viewport.X <= 0 or viewport.Y <= 0 then return H.fail("camera viewport has no usable size") end
				local point = Vector2.new(fx * viewport.X, fy * viewport.Y)

				local okRay, unit = pcall(function() return camera:ViewportPointToRay(point.X, point.Y) end)
				if not okRay or not unit then return H.fail("could not build a ray from the screen point") end

				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { env.plr and env.plr.Character }
				params.IgnoreWater = args.ignore_water ~= false
				local distance = tonumber(args.distance) or 10000

				local ws = env.services.Workspace
				local okCast, result = pcall(function()
					return ws:Raycast(unit.Origin, unit.Direction * distance, params)
				end)
				if not okCast then return H.fail(tostring(result)) end
				if not result or not result.Instance then
					return { text = string.format("Nothing within %.1f studs along the ray from %s.", distance, H.show(unit.Origin)), data = { hit = false, distance = distance } }
				end

				local rows = {
					{ "Part", H.show(result.Instance) },
					{ "Class", tostring(result.Instance.ClassName) },
					{ "Distance", string.format("%.1f studs", result.Distance) },
					{ "Position", H.show(result.Position) },
					{ "Normal", H.show(result.Normal) },
					{ "Material", tostring(result.Material and result.Material.Name or "?") },
				}
				local okParent, parent = pcall(function() return result.Instance.Parent end)
				if okParent and parent and parent ~= workspace then
					rows[#rows + 1] = { "Parent", H.pathOf(parent) }
				end
				return { text = H.keyValues(rows), data = { hit = true, instanceId = env.require("runtime/instance_refs").id(result.Instance), path = H.pathOf(result.Instance), distance = result.Distance } }
			end,
		},
	}
end
