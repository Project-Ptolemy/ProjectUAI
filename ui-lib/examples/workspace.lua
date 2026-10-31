-- A small task workspace: scripts supply records and behavior, not components.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({ Id = "uai-workspace-example", Title = "Session checklist", Palette = "Forest", Density = "Comfortable" })
local main = window:Tab({ Id = "main", Title = "Checklist" })
local tasks = {
	{ Id = "lighting", Text = "Review lighting", Description = "Check the interior and entrance lights." },
	{ Id = "paths", Text = "Review paths", Description = "Make the route to the entrance easy to follow." },
	{ Id = "signs", Text = "Review signs", Description = "Check wording and readability." },
}
local state = { completed = 0 }
local output, details
local selection = main:Section({ Title = "Tasks" }):ItemList({ Id = "tasks", Text = "Choose a task", Items = tasks, PageSize = 3,
	Callback = function(id)
		for _, task in ipairs(tasks) do if task.Id == id then output:Set(task.Text .. "\n\n" .. task.Description) end end
	end,
})
local review = main:Section({ Title = "Review" })
local status = review:Callout({ Id = "status", Text = "Choose a task", Content = "Select a task to review its details.", Kind = "Info" })
output = review:TextView({ Id = "preview", Text = "Task details", Value = "No task selected.", Lines = 3 })
local repeats = review:NumberInput({ Id = "repeats", Text = "Review passes", Default = 1, Min = 1, Max = 5, Step = 1 })
details = review:KeyValue({ Id = "details", Text = "Progress", Items = { { Key = "Available tasks", Value = #tasks }, { Key = "Completed reviews", Value = 0 } } })
review:ActionGroup({ Id = "actions", Text = "Review actions", Actions = {
	{ Id = "complete", Text = "Complete review", Style = "Primary", Callback = function()
		if selection:Get() == "" then status:SetKind("Warning"):SetContent("Select a task first."); return end
		local ok = window:CommitInputs({ Ids = { "repeats" }, FocusInvalid = true })
		if not ok then return end
		state.completed = state.completed + repeats:Get()
		details:SetValue("Completed reviews", state.completed)
		status:SetText("Review complete"):SetKind("Success"):SetContent("The completed count has been updated.")
	end },
	{ Id = "copy", Text = "Copy details", Callback = function()
		local ok, why = output:Copy()
		status:SetText(ok and "Copied" or "Copy unavailable"):SetKind(ok and "Success" or "Warning"):SetContent(ok and "Task details are on the clipboard." or why)
	end },
} })
return window
