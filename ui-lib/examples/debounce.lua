-- Search a small application-owned list after typing pauses.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({ Id = "uai-debounce-example", Title = "Player finder" })
local section = window:Tab({ Id = "main", Title = "Players" }):Section({ Title = "Find a player" })
local players = game:GetService("Players")
local matches = section:Dropdown({ Id = "player", Text = "Matching players", Options = {}, Persist = false })
local query = section:Input({ Id = "query", Text = "Name contains", Live = true, Persist = false })
local function update()
	local needle, options = string.lower(query:Get()), {}
	for _, player in ipairs(players:GetPlayers()) do
		if string.lower(player.DisplayName .. " " .. player.Name):find(needle, 1, true) then
			options[#options + 1] = { Label = player.DisplayName .. " (@" .. player.Name .. ")", Value = player.UserId,
				Image = string.format("rbxthumb://type=AvatarHeadShot&id=%.0f&w=150&h=150", player.UserId) }
		end
	end
	table.sort(options, function(a, b) return a.Label < b.Label end)
	matches:SetOptions(options, true)
end
local refresh = window:Debounce(0.15, update)
window:Give(query:OnChanged(refresh))
window:Give(players.PlayerAdded:Connect(refresh))
window:Give(players.PlayerRemoving:Connect(refresh))
update()
return window
