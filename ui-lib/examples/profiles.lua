-- Explicit save/load/delete actions; profile controls themselves are transient.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({ Id = "uai-profile-example", Title = "Saved preferences" })
local tab = window:Tab({ Id = "main", Title = "Preferences" })
local settings = tab:Section({ Title = "Processing" })
settings:Toggle({ Id = "enabled", Text = "Enable processing", Default = true })
settings:Slider({ Id = "batch-size", Text = "Batch size", Min = 1, Max = 100, Default = 10 })
local profiles = tab:Section({ Title = "Profiles" })
local name = profiles:Input({ Id = "profile-name", Text = "Save as", Default = "default", Required = true,
	Pattern = "^[%w_-]+$", MaxLength = 48, Persist = false })
local selected = profiles:Dropdown({ Id = "profile-selected", Text = "Saved profile", Options = {}, Persist = false })
local function report(title, ok, detail)
	window:Notify({ Title = title, Content = tostring(detail), Kind = ok and "Success" or "Warning" })
end
local function refresh()
	local ok, names = window:ListConfigs()
	if ok then selected:SetOptions(names, true) else report("Profiles unavailable", false, names) end
	return ok
end
profiles:Button({ Id = "profile-refresh", Text = "Refresh profiles", ActionText = "Refresh", Callback = refresh })
profiles:Button({ Id = "profile-save", Text = "Save current preferences", ActionText = "Save", Callback = function()
	if not name:Commit(true) then window:Reveal(name.Id); name:Focus(); return end
	local ok, result = window:SaveConfig(name:Get())
	if ok and refresh() then selected:Set(name:Get(), true) end
	report(ok and "Profile saved" or "Save failed", ok, result)
end })
profiles:Button({ Id = "profile-load", Text = "Load selected profile", ActionText = "Load", Callback = function()
	if selected:Get() == nil then report("Choose a profile", false, "Select a saved profile first."); return end
	local ok, result = window:LoadConfig(selected:Get())
	report(ok and "Preferences restored" or "Load failed", ok, ok and "Controls restored. Apply them through your application when ready." or result)
end })
profiles:Button({ Id = "profile-delete", Text = "Delete selected profile", ActionText = "Delete", Style = "Danger", Callback = function()
	local target = selected:Get()
	if target == nil then report("Choose a profile", false, "Select a saved profile first."); return end
	window:Confirm({ Title = "Delete " .. target .. "?", Content = "This removes the saved profile. Current controls stay as they are.",
		ConfirmText = "Delete", Danger = true, Callback = function()
			local ok, result = window:DeleteConfig(target)
			if ok then refresh() end
			report(ok and "Profile removed" or "Delete failed", ok, ok and "The saved profile is no longer available." or result)
		end })
end })
refresh()
return window
