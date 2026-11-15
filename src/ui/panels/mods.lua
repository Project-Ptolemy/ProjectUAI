-- Mod navigation and live readouts use the normal client presentation primitives.
-- Scripted extensions own their own full host changes through the mod runner.
return function(env)
	local mods = env.require("runtime/ui_mods")
	local runner = env.require("runtime/ui_mod_runner")
	local nativePanels = env.require("runtime/ui_mod_panels")
	local nativeView = env.require("ui/mod_panel")
	local clock = env.require("runtime/clock")
	local dispose = env.require("runtime/dispose")
	local sessions = env.require("agent/session")
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local preview = env.require("ui/mod_preview")
	local overlay = env.require("ui/overlay")
	local M = {}
	function M.new(parent, app)
		local panel, alive, visible, dirty = {}, true, true, true
		local metricsDirty, painting, disabling = true, false, false
		local queueRefresh, cancelRefresh
		local currentView, selectedPanel, liveRecord, metrics, tabs = nil, app.modPanelSelection, nil, {}, {}
		local scriptPanels = {}
		local scroll = P.scroll(parent, { name = "UiModsWorkspace", size = UDim2.fromScale(1, 1),
			padding = theme.space.lg, gap = theme.space.sm })
		P.text(scroll.instance, { name = "UiModsTitle", text = "Mod workspace", role = "heading", layoutOrder = 1 })
		P.text(scroll.instance, { text = "Make Project UAI your own. Create an appearance preset, add useful panels, or write a scripted extension.",
			role = "caption", color = theme.color.textSecondary, wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		local actions = P.row(scroll.instance, { name = "UiModsWorkspaceActions", auto = "Y", wrap = true,
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 3 })
		P.button(actions, { name = "ManageUiMods", text = "Manage UI mods", variant = "primary", size = "sm",
			onClick = function() if alive and visible then app.showUiMods() end end })
		P.button(actions, { name = "DisableWorkspaceMods", text = "Disable mods", variant = "secondary", size = "sm",
			onClick = function(button)
				if not alive or not visible or disabling then return end
				local found, session = pcall(sessions.current)
				if not found or type(session) ~= "table" or type(session.disableUiMods) ~= "function" then
					overlay.toast("The conversation is unavailable. Open a conversation before disabling mods.", "warn", 5); return
				end
				disabling = true; button.setBusy(true)
				clock.spawn(function()
					local ok, result = pcall(session.disableUiMods)
					disabling = false
					if not alive then return end
					button.setBusy(false)
					if not visible then return end
					if not ok or type(result) ~= "table" then
						overlay.toast("Disabling UI mods stopped unexpectedly. Review the active mod before trying again.", "warn", 5); return
					end
					local warning = result.ok ~= true or type(result.data) == "table" and result.data.persisted == false
					overlay.toast(type(result.text) == "string" and result.text or "The mod cleanup returned no status.", warning and "warn" or "info", 5)
				end)
			end })
		local status = P.text(scroll.instance, { name = "UiModsWorkspaceStatus", text = "", role = "small",
			color = theme.color.textSecondary, wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 4 })
		local navigation = P.row(scroll.instance, { name = "UiModPanelTabs", auto = "Y", wrap = true,
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.xs, layoutOrder = 5 })
		local content = P.column(scroll.instance, { name = "UiModsWorkspaceContent", auto = "Y",
			size = UDim2.new(1, 0, 0, 0), gap = theme.space.sm, layoutOrder = 6 })
		local function requestRefresh()
			if alive and visible and not painting and (dirty or metricsDirty) then queueRefresh() end
		end
		local function navigate(action)
			if not alive or not visible then return end
			if action == "micro_goals" then app.showGoals()
			elseif action == "commands" then app.showCommands()
			else app.show(action) end
		end
		local function refreshMetrics()
			if not alive or not visible or not currentView or liveRecord and liveRecord.spec.kind == "script" then return end
			local session = sessions.current()
			local snapshot = session.modMetrics()
			if not alive or not visible or session.id ~= sessions.activeId then metricsDirty = true; return end
			metrics = type(snapshot) == "table" and snapshot or {}
			currentView.refresh()
		end
		local function showPanel(id)
			if not alive or not visible or not liveRecord or not tabs[id] then return end
			local position = scroll.instance.CanvasPosition
			selectedPanel = id
			if currentView then currentView.destroy() end
			if liveRecord.spec.kind == "script" then
				app.modPanelSelection = id
				currentView = nativeView.new(content, id)
			else currentView = preview.renderVisual(content, liveRecord.spec, { panelId = id,
				metric = function(selector) return metrics[selector] end, navigate = navigate }) end
			for key, button in pairs(tabs) do button.setVariant(key == id and "primary" or "secondary") end
			scroll.instance.CanvasPosition = position
			metricsDirty = true; requestRefresh()
		end
		local function paint()
			local record, state = mods.getActive(), mods.state()
			if not alive or not visible then dirty = true; return end
			local position = scroll.instance.CanvasPosition
			if currentView then currentView.destroy(); currentView = nil end
			for _, holder in ipairs({ navigation, content }) do
				for _, child in ipairs(holder:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			end
			tabs, liveRecord = {}, record
			if env.context.safeMode then
				status.Text = "Safe mode: mods are disabled for this execution. Reload normally to review and apply a mod."
			elseif not liveRecord then
				status.Text = "No active mod. Open Manage UI mods to create, import or review a saved mod."
			elseif liveRecord.spec.kind == "script" then
				local run = runner.state()
				status.Text = liveRecord.spec.name .. " / version " .. tostring(liveRecord.version) .. " / " .. tostring(run.status)
				scriptPanels = nativePanels.list(liveRecord.spec.id)
				local found
				for _, item in ipairs(scriptPanels) do if item.key == selectedPanel then found = true end end
				selectedPanel = found and selectedPanel or (scriptPanels[1] and scriptPanels[1].key)
				for _, item in ipairs(scriptPanels) do
					local key = item.key
					tabs[key] = P.button(navigation, { name = "UiModNativeTab_" .. item.id, text = item.title, size = "sm",
						variant = selectedPanel == key and "primary" or "secondary", onClick = function() showPanel(key) end })
				end
				if selectedPanel then showPanel(selectedPanel)
				else P.text(content, { name = "UiModScriptWorkspace", text = "This scripted mod has no native workspace panels. Ask your agent to add a panel, or open Manage UI mods to inspect and edit its source.",
					role = "body", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) }) end
			else
				status.Text = liveRecord.spec.name .. " / version " .. tostring(liveRecord.version)
				local found
				for _, item in ipairs(liveRecord.spec.panels) do if item.id == selectedPanel then found = true end end
				selectedPanel = found and selectedPanel or (liveRecord.spec.panels[1] and liveRecord.spec.panels[1].id)
				for _, item in ipairs(liveRecord.spec.panels) do
					local id = item.id
					tabs[id] = P.button(navigation, { name = "UiModTab_" .. id, text = item.title, size = "sm",
						variant = selectedPanel == id and "primary" or "secondary", onClick = function() showPanel(id) end })
				end
				if selectedPanel then showPanel(selectedPanel)
				else P.text(content, { name = "UiModAppearanceOnly", text = "This mod changes the appearance without adding workspace panels.",
					role = "body", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0) }) end
			end
			if state.error then status.Text = status.Text .. " " .. tostring(state.error) end
			scroll.instance.CanvasPosition = position
		end
		-- Reads can emit a change signal while loading. One deferred refresh keeps
		-- those notifications and metric bursts from rebuilding this surface recursively.
		queueRefresh, cancelRefresh = clock.debounce(function()
			if not alive or not visible or painting then return end
			painting = true
			local ok = pcall(function()
				if dirty then dirty = false; paint() end
				if alive and visible and metricsDirty then metricsDirty = false; refreshMetrics() end
			end)
			painting = false
			if not ok then
				dirty, metricsDirty = false, false
				if alive and visible then status.Text = "The mod workspace could not refresh. Open Manage UI mods to review the saved definition." end
			end
			requestRefresh()
		end, 0)
		local function invalidate() if alive then dirty = true; requestRefresh() end end
		local function invalidateMetrics() if alive then metricsDirty = true; requestRefresh() end end
		local releaseMods, releaseRun = mods.changed:connect(invalidate), runner.changed:connect(invalidate)
		local releasePanels = nativePanels.changed:connect(function(_, kind) if kind == "structure" then invalidate() end end)
		local releaseSession = sessions.listChanged:connect(invalidateMetrics)
		local releaseEvent = sessions.anyEvent:connect(function(session, event)
			if session.id == sessions.activeId and event.kind == "goals:changed" then invalidateMetrics() end
		end)
		local releaseUsage = sessions.usageChanged:connect(invalidateMetrics)
		function panel.setVisible(value)
			if not alive then return end
			visible = value == true
			if currentView and currentView.setVisible then currentView.setVisible(visible) end
			if visible then metricsDirty = true; requestRefresh() end
		end
		function panel.select(key)
			if not alive or not nativePanels.snapshot(key) then return nil, "This native mod panel is unavailable" end
			selectedPanel, app.modPanelSelection = key, key; dirty = true; requestRefresh(); return true
		end
		local destroyedConnection
		local cleanup = dispose.add(function()
			if not alive then return end
			alive = false; cancelRefresh(); releaseMods(); releaseRun(); releasePanels(); releaseSession(); releaseEvent(); releaseUsage()
			if destroyedConnection then destroyedConnection:Disconnect() end
			if currentView then currentView.destroy() end
			scroll.instance:Destroy()
		end, "UI mods workspace")
		function panel.destroy() cleanup() end
		destroyedConnection = parent.Destroying:Connect(cleanup)
		requestRefresh()
		return panel
	end
	return M
end
