-- A view owns its subscription; the library owns the coalesced paint task.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({ Id = "uai-activity-example", Title = "Session activity" })
local section = window:Tab({ Id = "main", Title = "Activity" }):Section({ Title = "Elapsed time" })
local enabled = section:Toggle({ Id = "tracking", Text = "Track elapsed time", Default = true, Persist = false })
local elapsed = section:Badge({ Id = "elapsed", Text = "Tracked seconds", Default = "0", Persist = false })
local seconds, queued = 0, false
window:Give(game:GetService("RunService").Heartbeat:Connect(function(delta)
	if enabled:Get() then seconds = seconds + delta end
	if queued then return end
	queued = true
	window:Delay(0.2, function()
		queued = false
		elapsed:Set(tostring(math.floor(seconds)), true)
	end)
end))
section:Button({ Id = "reset", Text = "Start timing again", ActionText = "Reset", Callback = function()
	seconds = 0
	elapsed:Set("0", true)
end })
window:OnDestroy(function() seconds = 0 end)
return window
