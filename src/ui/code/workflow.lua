-- Human-readable script goal and evidence, backed by the active conversation.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local sessions = env.require("agent/session")
	local workflow = env.require("runtime/script_workflow")
	local forms = env.require("ui/code/forms")
	local common = env.require("ui/code/common")
	local util = env.require("runtime/util")
	local M = {}
	function M.open()
		local session = sessions.current()
		if not session then common.message(nil, "Open a conversation first"); return end
		local modal = overlay.modal({ title = "Script-making goal", description = "A saved sequence from the requested outcome to reviewed evidence." })
		if not modal then return end
		local body = P.column(modal.content, { name = "ScriptGoal", auto = "Y", size = UDim2.new(1, 0, 0, 0), gap = theme.space.md })
		local render
		local function start()
			forms.form("New script goal", { { key = "goal", label = "What should the script do?", required = true, multiline = true },
				{ key = "criteria", label = "Acceptance criteria, one per line", required = true, multiline = true } }, function(data)
				local criteria = {}; for line in tostring(data.criteria):gmatch("[^\r\n]+") do if util.trim(line) ~= "" then criteria[#criteria + 1] = util.trim(line) end end
				local value, why = workflow.start(session, util.trim(data.goal), criteria)
				if not value then return nil, why end
				return true
			end, { submit = "Create goal", key = "script-goal:" .. session.id })
		end
		local startButton = P.button(modal.footer, { name = "NewScriptGoal", text = "New goal", size = "sm", onClick = start })
		P.button(modal.footer, { text = "Copy progress", size = "sm", variant = "ghost", onClick = function() common.copy(workflow.describe(session.workflow)) end })
		P.button(modal.footer, { text = "Close", size = "sm", variant = "ghost", onClick = modal.close })
		render = function()
			if modal.closed then return end
			for _, child in ipairs(body:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
			local value = workflow.restore(session.workflow)
			startButton.setEnabled(not value or value.status == "complete")
			if not value then P.text(body, { text = "Create a goal here or ask the agent to build a script. The agent can retain its stages, checks and acceptance criteria in this view.", auto = "Y", wrap = true }); return end
			P.text(body, { name = "ScriptGoalTitle", text = value.goal, role = "heading", auto = "Y", wrap = true, layoutOrder = 1 })
			P.text(body, { text = "Status: " .. value.status .. (value.blocker and (" · " .. value.blocker) or ""), role = "caption", auto = "Y", wrap = true, layoutOrder = 2 })
			for index, stage in ipairs(workflow.stages) do
				local card = P.card(body, { name = "Workflow_" .. stage.id, layoutOrder = 2 + index, padding = theme.space.sm, gap = theme.space.xs })
				P.text(card, { text = index .. ". " .. stage.label .. (index == value.stage and " · current" or value.notes[index] and " · reviewed" or ""), role = "label", auto = "Y", wrap = true, layoutOrder = 1 })
				P.text(card, { text = value.notes[index] or stage.hint, role = "caption", auto = "Y", wrap = true, layoutOrder = 2 })
			end
			for index, item in ipairs(value.criteria) do
				P.text(body, { text = (item.done and "Done: " or "Open: ") .. item.text .. (item.note and ("\n" .. item.note) or ""), role = "small", auto = "Y", wrap = true, layoutOrder = 20 + index })
			end
			for index, receipt in ipairs(value.receipts) do
				local current = receipt.revision == value.revision
				P.text(body, { text = receipt.tool .. ": " .. (receipt.ok and "passed" or "failed / unavailable") .. (not current and " · before the latest edit" or ""), role = "caption", color = receipt.ok and theme.color.textSecondary or theme.color.warn, auto = "Y", wrap = true, layoutOrder = 40 + index })
			end
		end
		local off = session.events:connect(function(event) if event.kind == "workflow:changed" or event.kind == "cleared" then render() end end)
		modal.scrim.Destroying:Connect(off)
		render(); return modal
	end
	return M
end
