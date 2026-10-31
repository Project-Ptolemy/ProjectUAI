-- Core controls, using the exact loader agents put in standalone scripts.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({
	Id = "uai-library-showcase",
	Title = "Fieldwork",
	Subtitle = "A considered set of tools for your session",
	Search = true,
	Palette = "Graphite",
	TabHeader = "Detailed",
})

local overview = window:Tab({ Id = "overview", Title = "Overview" })
local controls = window:Tab({ Id = "controls", Title = "Controls" })
local preferences = window:Tab({ Id = "preferences", Title = "Preferences" })

local session = overview:Section({ Title = "Session", Description = "Small, purposeful controls. One consistent interface." })
session:Badge({ Text = "Workspace", Default = "Ready", Kind = "Success" })
local automatic = session:Toggle({ Id = "automatic", Text = "Automatic updates", Description = "Keep the workspace current as things change.", Default = true })
local radius = session:Slider({ Id = "radius", Text = "Selection radius", Description = "The reach of your next selection.", Min = 10, Max = 100, Step = 5, Default = 40, Suffix = " studs" })
local progress = session:Progress({ Id = "progress", Text = "Session progress", Default = 64, Persist = false })
session:Button({
	Text = "Refresh workspace", Description = "Run a sample action using the current values.", ActionText = "Refresh", Style = "Primary",
	Callback = function()
		progress:Set(math.min(100, progress:Get() + 12))
		window:Notify({ Title = "Workspace refreshed", Content = "Selection radius: " .. radius:Get() .. " studs.", Kind = "Success" })
	end,
})

local inputs = controls:Section({ Title = "Inputs", Description = "Values stay separate from your application logic." })
inputs:Input({ Id = "name", Text = "Workspace name", Default = "My workspace", Required = true, Placeholder = "Give this workspace a name" })
inputs:NumberInput({ Id = "limit", Text = "Item limit", Description = "A number between 1 and 100.", Min = 1, Max = 100, Step = 1, Default = 20 })
inputs:Dropdown({
	Id = "mode", Text = "Selection mode", Default = "nearest",
	Options = { { Label = "Nearest first", Value = "nearest" }, { Label = "In view", Value = "visible" }, { Label = "All available", Value = "all" } },
})
inputs:Dropdown({ Id = "filters", Text = "Include", Multi = true, Default = { "Players", "Objects" }, Options = { "Players", "Objects", "Markers", "Effects" } })
-- Player choices carry their headshot at the start of the row and in the
-- closed field. rbxthumb resolves inside the client; no upload is involved.
local function playerOptions()
	local options = {}
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		options[#options + 1] = {
			Label = player.DisplayName,
			Value = player.UserId,
			Image = string.format("rbxthumb://type=AvatarHeadShot&id=%.0f&w=150&h=150", player.UserId),
		}
	end
	return options
end
local target = inputs:Dropdown({ Id = "target", Text = "Target player", Placeholder = "No players yet", Options = playerOptions() })
inputs:Button({ Text = "Refresh players", ActionText = "Refresh", Callback = function()
	local options = playerOptions()
	target:SetOptions(options)
	window:Notify({ Title = "Player list refreshed", Content = tostring(#options) .. " player(s) available.", Kind = "Success" })
end })
local refreshPlayers = window:Debounce(0.1, function()
	if automatic:Get() then target:SetOptions(playerOptions(), true) end
end)
window:Give(game:GetService("Players").PlayerAdded:Connect(refreshPlayers))
window:Give(game:GetService("Players").PlayerRemoving:Connect(refreshPlayers))
window:Give(automatic:OnChanged(refreshPlayers))
inputs:Checkbox({ Id = "remember", Text = "Remember selection", Description = "Preserve your selection between refreshes.", Default = true })
inputs:Keybind({
	Id = "shortcut", Text = "Quick notification", Default = Enum.KeyCode.K,
	Callback = function() window:Notify({ Title = "Shortcut received", Content = "Your keybind is connected." }) end,
})

-- Appearance preferences are supplied automatically by the library.
local profiles = preferences:Section({ Title = "Preferences", Description = "Save a profile explicitly whenever you need it." })
profiles:Input({ Id = "notes", Text = "Session notes", MultiLine = true, Placeholder = "A few notes for this session…", Persist = false })
profiles:Button({ Text = "Save profile", ActionText = "Save", Callback = function()
	local ok, result = window:SaveConfig("default")
	window:Notify({ Title = ok and "Profile saved" or "Could not save", Content = tostring(result), Kind = ok and "Success" or "Warning" })
end })
profiles:Button({ Text = "Load profile", ActionText = "Load", Callback = function()
	local ok, result = window:LoadConfig("default")
	window:Notify({ Title = ok and "Profile loaded" or "Could not load", Content = ok and "Your controls have been restored." or tostring(result), Kind = ok and "Success" or "Warning" })
end })
local more = preferences:Section({ Title = "More", Collapsible = true })
more:Button({ Text = "About this workspace", ActionText = "About", Callback = function()
	window:Dialog({ Title = "Fieldwork", Content = "An example built entirely with Project UAI UI LIB. Each control is declared once; the library handles the interface." })
end })
more:Button({ Text = "Reset session", ActionText = "Reset", Style = "Danger", Callback = function()
	window:Confirm({ Title = "Reset this session?", Content = "Return the selection and progress to their defaults.", ConfirmText = "Reset", Danger = true, Callback = function()
		window:ResetValues({ Ids = { "automatic", "radius", "progress" } })
	end })
end })
return window
