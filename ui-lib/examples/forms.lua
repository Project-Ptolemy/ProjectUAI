-- An explicit Apply boundary: invalid drafts never partially update the model.
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
local window = UI:CreateWindow({ Id = "uai-form-example", Title = "Batch settings" })
local section = window:Tab({ Id = "main", Title = "Settings" }):Section({ Title = "Next batch" })
local model = { name = "My batch", limit = 20 }
section:Input({ Id = "batch-name", Text = "Batch name", Default = model.name, Required = true, MaxLength = 80 })
section:Input({ Id = "batch-limit", Text = "Item limit", Default = model.limit, Numeric = true, Min = 1, Max = 100,
	Validate = function(value) return value == math.floor(value), "Use a whole number." end })
local status = section:Badge({ Id = "batch-status", Text = "Changes", Default = "Ready", Persist = false })
section:Button({ Id = "batch-apply", Text = "Use these settings", ActionText = "Apply", Style = "Primary", Callback = function()
	if not window:CommitInputs({ Ids = { "batch-name", "batch-limit" }, FocusInvalid = true }) then
		status:Set("Check fields"):SetKind("Warning")
		return
	end
	local values = window:GetValues()
	model.name, model.limit = values["batch-name"], values["batch-limit"]
	status:Set("Applied"):SetKind("Success")
	-- Call your application's operation here with the validated model values.
	print("Batch settings", model.name, model.limit)
end })
section:Button({ Id = "batch-reset", Text = "Restore initial values", ActionText = "Reset", Callback = function()
	window:ResetValues({ Ids = { "batch-name", "batch-limit" } })
	status:Set("Defaults ready"):SetKind("Secondary")
end })
return window
