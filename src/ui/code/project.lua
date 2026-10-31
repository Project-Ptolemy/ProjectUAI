-- Review the entire starter before applying its new-file-only proposal.
return function(env)
	local forms = env.require("ui/code/forms")
	local compare = env.require("ui/code/compare")
	local common = env.require("ui/code/common")
	local scaffold = env.require("runtime/project_scaffold")
	local patch = env.require("runtime/project_patch")
	local guard = env.require("runtime/project_guard")
	local sessions = env.require("agent/session")
	local M = {}
	function M.create(navigate)
		local session = sessions.current(); if not session then common.message(nil, "Open a conversation first"); return end
		local context = session.toolContext()
		local baseAborted, review, form, handedOff, cancelled = context.aborted, nil, nil, false, false
		context.aborted = function()
			return cancelled or baseAborted() or (review and review.closed) or (form and form.modal.closed and not handedOff)
		end
		form = forms.form("Create script project", {
			{ key = "directory", label = "New folder under files/", required = true, default = "MyProject" },
			{ key = "kind", label = "Starter", type = "choice", choices = { "basic", "interface" }, default = "interface" },
		}, function(data)
			if context.aborted() then return nil, "This project draft belongs to an inactive operation; reopen Create project" end
			local files, manifest = scaffold.files(data.directory, data.kind); if not files then return nil, manifest end
			local plan, why = patch.stage(files, context); if not plan then return nil, why end
			local function discard()
				if plan.status == "proposed" and not plan.busy then patch.discard(plan.id, context) end
			end
			if context.aborted() then discard(); return nil, "Project preview cancelled" end
			local parts = {}
			for _, file in ipairs(files) do parts[#parts + 1] = "-- File: files/" .. file.path .. "\n" .. file.content end
			local opened, result = pcall(compare.open, "", table.concat(parts, "\n\n"), "Review new project", function()
				if context.aborted() then discard(); return nil, "Project preview is no longer active" end
				local current, err = patch.get(plan.id, context); if not current then return nil, err end
				local result, problem = patch.apply(current, context, guard.check)
				if current.status ~= "proposed" then env.require("runtime/script_workflow").invalidate(session) end
				if context.aborted() then discard(); return nil, "Project operation stopped; inspect checkpoint " .. plan.id end
				if not result then return nil, problem end
				if result.status ~= "applied" then return nil, "Project creation was incomplete. Retained checkpoint: " .. plan.id end
				forms.discardDraft("new-script-project")
				env.require("ui/overlay").toast("Project created. Analyze and test " .. manifest .. " before running.", "good")
				if navigate then navigate("Files") end
				return result
			end, function() cancelled = true; discard() end)
			if not opened or not result then discard(); return nil, opened and "Close an open dialog before reviewing this project" or tostring(result) end
			if context.aborted() then
				pcall(result.close); discard()
				return nil, "Project preview cancelled"
			end
			review, handedOff = result, true
			return true
		end, { key = "new-script-project", keepDraft = true, submit = "Review files", description = "The interface starter separates its UI LIB view, model, settings and tests. Existing files are never overwritten." })
		return form
	end
	return M
end
