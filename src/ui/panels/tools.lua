-- Tools panel: what the agent can do here, and what it is allowed to do.
--
-- Permission rules live next to the tool they govern rather than in a separate
-- list, because "can it delete files" is a question about file_delete, not about a
-- rules table.
return function(env)
	local util = env.require("runtime/util")
	local caps = env.require("runtime/caps")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local C = env.require("ui/controls")
	local registry = env.require("agent/registry")
	local permissions = env.require("agent/permissions")
	local schema = env.require("agent/schema")
	local search = env.require("runtime/search")

	local M = {}

	local RULE_OPTIONS = {
		{ value = "default", label = "Default" },
		{ value = "allow", label = "Allow" },
		{ value = "ask", label = "Ask" },
		{ value = "deny", label = "Deny" },
	}

	local GROUP_LABELS = registry.GROUP_LABELS

	function M.new(parent)
		local panel = {}
		local filter = ""
		local expanded = {}

		local column = P.column(parent, {
			name = "ToolsPanel",
			size = UDim2.new(1, 0, 1, 0),
			gap = 0,
		})

		local head = P.column(column, {
			size = UDim2.new(1, 0, 0, 0),
			auto = "Y",
			gap = theme.space.sm,
			padding = { x = theme.space.lg, top = theme.space.lg, bottom = theme.space.md },
			layoutOrder = 1,
		})

		local stats = registry.stats()
		P.text(head, {
			text = string.format("%d tools in %d groups", stats.total, util.count(stats.byGroup)),
			role = "heading",
			layoutOrder = 1,
		})
		local summary = P.text(head, {
			text = #stats.unavailable > 0
				and string.format("%d unavailable on this host. %s", #stats.unavailable, caps.summary())
				or "All tools are available on this host. Open a tool to review its parameters and permissions.",
			role = "caption",
			color = theme.color.textTertiary,
			wrap = true,
			auto = "Y",
			layoutOrder = 2,
		})
		summary.Size = UDim2.new(1, 0, 0, 0)

		local scroll, results

		local function rebuild()
			if not column.Parent or not scroll then return end
			local scrollPosition = scroll.instance.CanvasPosition
			scroll.clear()
			local match = search.compile(filter)
			local grouped = {}
			local matched = 0
			for _, tool in ipairs(registry.list()) do
				if match(tool.name, tool.description, tool.group, GROUP_LABELS[tool.group], tool.risk) then
					matched = matched + 1
					grouped[tool.group] = grouped[tool.group] or {}
					table.insert(grouped[tool.group], tool)
				end
			end
			if results then results.Text = util.pluralise(matched, "matching tool") end

			local order = util.keys(grouped, true)
			if #order == 0 then
				C.emptyState(scroll.instance, {
					icon = "search",
					title = "No matching tools",
					description = "Search by a tool name or what you want it to do.",
					layoutOrder = 1,
				})
				return
			end

			local position = 0
			for _, group in ipairs(order) do
				position = position + 1
				-- The group header carries its own switch: turning a family off removes it
				-- from the list the model is sent, which is a different thing from denying
				-- a call and belongs next to the family rather than in a settings pane.
				local header = P.row(scroll.instance, {
					name = "Group_" .. tostring(group),
					size = UDim2.new(1, 0, 0, 0),
					auto = "Y",
					gap = theme.space.sm,
					-- The same inset a card gives its own contents, so a group's name lines up
					-- with the tool names under it instead of sitting sixteen pixels to their
					-- left, and its switch lines up with theirs.
					padding = { x = theme.space.md, top = theme.space.sm, bottom = theme.space.xxs },
					layoutOrder = position,
				})
				local headText = P.column(header, {
					size = UDim2.new(0, 0, 0, 0),
					auto = "Y",
					flex = "Fill",
					gap = 0,
					layoutOrder = 1,
				})
				P.text(headText, {
					text = GROUP_LABELS[group] or group,
					role = "label",
					color = theme.color.text,
					auto = "Y",
					wrap = true,
				})
				local groupNote = P.text(headText, {
					text = "",
					role = "caption",
					color = theme.color.textTertiary,
					wrap = true,
					auto = "Y",
				})
				local function describeGroup()
					groupNote.Text = registry.groupEnabled(group)
						and util.pluralise(#grouped[group], "tool")
						or (util.pluralise(#grouped[group], "tool") .. ", not offered to the model")
				end
				describeGroup()
				local groupSwitch = C.switch(header, {
					value = registry.groupEnabled(group),
					onChange = function(value)
						registry.setGroupEnabled(group, value)
						describeGroup()
					end,
				})
				groupSwitch.instance.LayoutOrder = 2

				for _, tool in ipairs(grouped[group]) do
					position = position + 1
					local missing = registry.missingCapability(tool)
					local card = P.card(scroll.instance, {
						name = tool.name,
						layoutOrder = position,
						gap = theme.space.xs,
						padding = theme.space.md,
						bg = theme.color.surface,
						radius = theme.radius.md,
					})

					local top = P.column(card, {
						size = UDim2.new(1, 0, 0, 0),
						auto = "Y",
						gap = theme.space.xs,
						layoutOrder = 1,
					})
					local name = P.text(top, {
						text = tool.name,
						role = "monoSmall",
						color = missing and theme.color.textSecondary or theme.color.text,
						wrap = true,
						auto = "Y",
						layoutOrder = 1,
					})
					local badges = P.row(top, { size = UDim2.new(1, 0, 0, 0), auto = "Y",
						wrap = true, gap = theme.space.xs, layoutOrder = 2 })
					P.badge(badges, {
						text = tool.risk,
						tone = tool.risk == "read" and "info" or (tool.risk == "danger" and "bad" or "warn"),
						layoutOrder = 2,
					})
					if missing then
						P.badge(badges, { text = "unavailable", tone = "warn", layoutOrder = 3 })
					end

					local description = P.text(card, {
						text = tostring(tool.description),
						role = "caption",
						color = theme.color.textSecondary,
						wrap = true,
						auto = "Y",
						layoutOrder = 2,
					})
					description.Size = UDim2.new(1, 0, 0, 0)

					local details = P.column(card, { name = "ToolDetails", size = UDim2.new(1, 0, 0, 0),
						auto = "Y", gap = theme.space.sm, layoutOrder = 4, visible = expanded[tool.name] == true })
					local populateDetails, populated
					P.button(card, { name = "ToolDetailsToggle",
						text = expanded[tool.name] and "Hide details" or "Parameters & permissions", variant = "ghost",
						size = "sm", fill = true, align = "Left", tight = true, layoutOrder = 3, onClick = function(button)
							populateDetails()
							details.Visible = not details.Visible
							expanded[tool.name] = details.Visible
							button.setText(details.Visible and "Hide details" or "Parameters & permissions")
						end })
					populateDetails = function()
						if populated then return end
						populated = true
						P.divider(details, { layoutOrder = 1 })
						P.text(details, { name = "ParametersTitle", text = "Parameters", role = "label", layoutOrder = 2 })
						local parameters = P.column(details, { name = "Parameters", size = UDim2.new(1, 0, 0, 0),
							auto = "Y", bg = theme.color.canvas, radius = theme.radius.sm,
							padding = theme.space.sm, layoutOrder = 3 })
						local params = P.text(parameters, {
							text = schema.describe(tool.parameters),
							role = "caption",
							color = theme.color.textTertiary,
							wrap = true,
							auto = "Y",
							layoutOrder = 3,
						})
						params.Size = UDim2.new(1, 0, 0, 0)
						local examples = registry.examples(tool)
						if examples ~= "" then
							P.text(details, { name = "ToolExamples", text = "Examples\n" .. examples, role = "caption", auto = "Y", wrap = true, size = UDim2.new(1, 0, 0, 0), layoutOrder = 6 })
							P.button(details, { name = "CopyToolExample", text = "Copy examples", size = "sm", variant = "ghost", layoutOrder = 7, onClick = function()
								local ok, why = env.require("runtime/clipboard").write(examples)
								env.require("ui/overlay").toast(ok and "Examples copied" or why, ok and "good" or "warn")
							end })
						end

						if missing then
							local reason = P.text(details, {
								text = caps.reason(missing),
								role = "caption",
								color = theme.color.warn,
								wrap = true,
								auto = "Y",
								layoutOrder = 4,
							})
							reason.Size = UDim2.new(1, 0, 0, 0)
						else
							P.text(details, { name = "PermissionTitle", text = "Permission rule", role = "label", layoutOrder = 4 })
							C.segmented(details, {
								options = RULE_OPTIONS,
								value = permissions.ruleFor(tool.name) or "default",
								layoutOrder = 5,
								onChange = function(value)
									permissions.setRule(tool.name, value)
								end,
							})
						end
					end
					if expanded[tool.name] then populateDetails() end
				end
			end
			scroll.instance.CanvasPosition = scrollPosition
		end

		-- Third in the head block, stated rather than left to the tie-break: the two
		-- labels above it are constructed earlier but neither of them sets an order.
		P.field(head, {
			name = "ToolSearch",
			placeholder = 'Search words, "phrases", or -exclude',
			layoutOrder = 3,
			onChange = function(text)
				filter = util.trim(text)
				rebuild()
				if scroll then scroll.instance.CanvasPosition = Vector2.new(0, 0) end
			end,
		})
		results = P.text(head, { name = "ToolSearchCount", text = "", role = "caption",
			color = theme.color.textTertiary, layoutOrder = 4 })
		P.button(head, { name = "ManageChatLoops", text = "Chat loops & quiz scores", variant = "ghost", size = "sm", fill = true, align = "Left",
			layoutOrder = 5, onClick = function(button) env.require("ui/chat/loops").open(button.instance) end })

		-- Keep the flex item outside the clearable list contents.
		local listHolder = P.frame(column, { name = "ToolListHolder", size = UDim2.new(1, 0, 0, 0),
			flex = "Fill", layoutOrder = 2 })
		scroll = P.scroll(listHolder, {
			name = "ToolList",
			size = UDim2.new(1, 0, 1, 0),
			gap = theme.space.sm,
			-- Top padding as well. Without it the first group header butted against the
			-- head block above it while the bottom of the list had twelve pixels of air.
			padding = { x = theme.space.lg, top = theme.space.md, bottom = theme.space.xl },
			layoutOrder = 2,
		})

		rebuild()
		panel.refresh = rebuild
		panel.unsubscribe = permissions.changed:connect(rebuild)
		column.Destroying:Connect(function() pcall(panel.unsubscribe) end)
		return panel
	end

	return M
end
