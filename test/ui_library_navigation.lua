package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h, UI, window, section, check, done = require("ui_library_support").new("navigation")
local first = window:GetActiveTab()
local tab = window:Tab({ Id = "advanced", Title = "Advanced" })
local details = tab:Section({ Title = "Details", Collapsible = true, Collapsed = true })
local input = details:Input({ Id = "target", Text = "Target", Required = true })
-- The base library mock has no OS focus methods; observe the native request.
local focusRequests = 0
h.byName("Input", input.Frame).CaptureFocus = function() focusRequests = focusRequests + 1 end
tab:SetTitle("Renamed workspace")
details:SetTitle("Renamed group"):SetDescription("A description that can change with the model.")
check("live labels preserve stable identities", tab.Id == "advanced" and tab._heading.Text == "Renamed workspace" and details._heading.Text == "Renamed group")
window:SetSearch("no matches")
check("public search reflects the entered filter", window:GetSearch() == "no matches" and not input.Frame.Visible)
input:SetVisible(false); details:SetVisible(false); tab:SetVisible(false); window:Hide()
check("reveal restores visibility and opens the destination", window:Reveal("target") == input and window.Visible and tab.Visible and details.Visible
	and input.Visible and not details.Collapsed and window:GetActiveTab() == tab and window:GetSearch() == "")
window:SelectTab(first)
local ok, errors = window:CommitInputs({ Ids = { "target" }, FocusInvalid = true })
check("invalid form navigation selects and focuses the field", not ok and errors.target and window:GetActiveTab() == tab and focusRequests == 1)
check("unknown reveal targets fail explicitly", not pcall(function() window:Reveal("missing") end))
local empty = UI:CreateWindow({ Id = "no-search", Search = false })
check("disabled search allows clearing but rejects hidden filters", empty:SetSearch("") == empty and empty:GetSearch() == "" and not pcall(function() empty:SetSearch("test") end))
tab:Destroy()
check("destroyed containers reject label edits", not pcall(function() tab:SetTitle("late") end) and not pcall(function() details:SetDescription("late") end))
done()
