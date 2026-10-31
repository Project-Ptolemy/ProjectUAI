-- Connection settings for files owned by the local bridge computer.
return function(env)
	local clock = env.require("runtime/clock")
	local clipboard = env.require("runtime/clipboard")
	local bridge = env.require("net/bridge")
	local transport = env.require("net/obsidian")
	local theme = env.require("ui/theme")
	local P = env.require("ui/primitives")
	local R = env.require("ui/settingsrows")
	local M = {}
	function M.build(container)
		local alive, loading, epoch = true, false, 0
		container.Destroying:Connect(function() alive, epoch = false, epoch + 1 end)
		local card = R.section(container, { name = "ObsidianVaults", title = "Obsidian vaults",
			description = "Connect Markdown vault folders on the UAI Bridge computer. The agent can read notes, search text and follow wiki links.", layoutOrder = 1 })
		local status = R.paragraph(card, "Checking vault connections…", { name = "ObsidianStatus" })
		local connections = P.column(card, { name = "ObsidianConnections", auto = "Y", gap = theme.space.sm })
		local add = R.section(container, { title = "Connect a vault", description = "Use the full folder path from the computer running the bridge. New connections are read-only.", layoutOrder = 2 })
		local name = R.field(add, { name = "ObsidianVaultName", label = "Vault name", value = "", placeholder = "Personal notes" })
		local root = R.field(add, { name = "ObsidianVaultRoot", label = "Folder on bridge computer", value = "", placeholder = "C:/Users/you/Documents/Notes" })
		local readOnly = true
		R.toggle(add, { label = "Read-only", hint = "Disable this only when you want the agent to create or edit notes.", value = true, onChange = function(value) readOnly = value end })
		local connectButton, refreshButton
		local function busy(value)
			loading = value
			if connectButton then connectButton.setEnabled(not value) end
			if refreshButton then refreshButton.setEnabled(not value) end
		end
		local function paint(value)
			for _, child in ipairs(connections:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			status.Text = #value.vaults == 0 and "No vaults connected. Add one below." or tostring(#value.vaults) .. " vaults connected. Use obsidian_vaults to discover their ids."
			for _, entry in ipairs(value.vaults) do
				local row = P.column(connections, { auto = "Y", gap = theme.space.xxs })
				P.text(row, { text = entry.name .. " · " .. (entry.readOnly and "Read-only" or "Editing enabled"), role = "label", wrap = true, auto = "Y" })
				R.paragraph(row, entry.available and (entry.obsidian and "Obsidian vault" or "Markdown folder") or "Folder unavailable. Reconnect or remove it.")
				P.button(row, { name = "ObsidianBrowse_" .. entry.id, text = "Browse notes", variant = "primary", onClick = function()
					if loading or not entry.available then return end
					env.require("ui/obsidian_browser").open(entry)
				end })
				P.button(row, { name = "ObsidianCopy_" .. entry.id, text = "Copy vault ID", variant = "ghost", onClick = function()
					local ok, why = clipboard.write(entry.id)
					status.Text = ok and "Vault ID copied." or tostring(why)
				end })
				P.button(row, { name = "ObsidianPolicy_" .. entry.id, text = entry.readOnly and "Enable editing" or "Make read-only", variant = "secondary", onClick = function()
					if loading then return end
					busy(true); status.Text = "Saving vault permissions…"
					clock.spawn(function()
						local result, why = transport.configure({ action = "policy", id = entry.id, readOnly = not entry.readOnly }, { aborted = function() return not alive end })
						if not alive then return end; busy(false)
						if result then paint(result) else status.Text = tostring(why) end
					end)
				end })
				P.button(row, { name = "ObsidianDisconnect_" .. entry.id, text = "Disconnect vault", variant = "ghost", onClick = function()
					if loading then return end
					busy(true); status.Text = "Disconnecting vault…"
					clock.spawn(function()
						local result, why = transport.configure({ action = "remove", id = entry.id }, { aborted = function() return not alive end })
						if not alive then return end; busy(false)
						if result then paint(result) else status.Text = tostring(why) end
					end)
				end })
			end
		end
		local function refresh()
			if loading then return end
			busy(true); status.Text = "Checking vault connections…"; epoch = epoch + 1
			local mine = epoch
			clock.spawn(function()
				local result, why = transport.list({ aborted = function() return not alive or mine ~= epoch end })
				if not alive or mine ~= epoch then return end; busy(false)
				if result then paint(result) else status.Text = tostring(why) end
			end)
		end
		connectButton = P.button(add, { name = "ObsidianConnect", text = "Connect vault", variant = "primary", onClick = function()
			if loading then return end
			local input = { action = "connect", name = name.get(), root = root.get(), readOnly = readOnly }
			busy(true); status.Text = "Connecting vault…"
			clock.spawn(function()
				local result, why = transport.configure(input, { aborted = function() return not alive end })
				if not alive then return end; busy(false)
				if result then paint(result); name.set(""); root.set("") else status.Text = tostring(why) end
			end)
		end })
		refreshButton = P.button(card, { name = "ObsidianRefresh", text = "Refresh vaults", variant = "secondary", onClick = refresh })
		R.paragraph(add, "Browse notes to search, follow links and edit Markdown. Unsaved native note drafts stay in memory until saved or discarded; copy them before unloading. Disconnecting a vault keeps all its files. Agent edits follow the Obsidian tool group's normal permissions.")
		if bridge.status().online then refresh() else status.Text = "Connect UAI Bridge in Cowork, then refresh vaults." end
	end
	return M
end
