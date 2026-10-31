-- Grouped actions retain independent busy states and owned cancellation.
local h, UI, window, section, check, done = dofile("test/ui_library_support.lua").new("action-controls")
local calls, completed = 0, 0
local group = section:ActionGroup({ Id = "actions", Actions = {
	{ Id = "run", Text = "Run work", Callback = function() calls = calls + 1; h.sandbox.task.wait(0.5); completed = completed + 1 end },
	{ Id = "reset", Text = "Reset state", Disabled = true, Callback = function() calls = calls + 10 end },
} })
check("disabled action refuses activation", group:Press("reset") == false and calls == 0)
check("action starts once while busy", group:Press("run") and group:Press("run") == false and calls == 1)
h.settle(0.6)
check("completed action releases busy state", completed == 1 and group:Press("run"))
group:SetActionEnabled("reset", true)
group:Press("reset")
check("independent action can run during work", calls == 12)
group:SetActionText("reset", "Clear state")
check("action labels update without rebuilding the group", h.textOf(h.byName("Action_reset", group.Frame)):find("Clear state", 1, true))
local callout = section:Callout({ Id = "message", Text = "Connection", Content = "Ready for work", Kind = "Success", ActionText = "Retry", Callback = function() calls = calls + 100 end })
callout:SetKind("Warning"):SetContent("Waiting for a connection")
check("callout content and semantic tone update", callout.StatusKind == "Warning" and callout.Description == "Waiting for a connection")
check("callout action invokes domain callback", callout:Press() and calls == 112)
local snapshot = h.json.decode(window:ExportConfig())
check("actions and messages never enter value profiles", snapshot.values.actions == nil and snapshot.values.message == nil)
group:Destroy(); h.settle(0.7)
check("destroy cancels owned work before completion", completed == 1)
done()
