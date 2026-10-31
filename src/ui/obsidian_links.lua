-- Outgoing links and backlinks expose exact resolved paths and ambiguity.
return function(env)
	local P = env.require("ui/primitives")
	local theme = env.require("ui/theme")
	local overlay = env.require("ui/overlay")
	local clock = env.require("runtime/clock")
	local transport = env.require("net/obsidian")
	local M = {}
	function M.open(vault, path)
		local modal = overlay.modal({ title = "Note links", description = path, width = theme.size.modalWide, scroll = true })
		if not modal then return nil end
		local action, offset, nextOffset, loading = "links", 1, nil, false
		local load, more
		local switch = P.row(modal.content, { auto = "Y", gap = theme.space.xs, layoutOrder = 1 })
		for _, option in ipairs({ { "Outgoing", "links" }, { "Backlinks", "backlinks" } }) do
			P.button(switch, { text = option[1], variant = "secondary", size = "sm", onClick = function()
				if loading then return end; action, offset = option[2], 1; load()
			end })
		end
		local status = P.text(modal.content, { name = "ObsidianLinkStatus", text = "Loading links...", role = "small",
			wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 2 })
		local rows = P.column(modal.content, { auto = "Y", gap = theme.space.xs, layoutOrder = 3 })
		load = function()
			if modal.closed or loading then return end
			loading = true; if more then more.setEnabled(false) end
			status.Text = "Loading " .. (action == "links" and "outgoing links" or "backlinks") .. "..."
			clock.spawn(function()
				local value, why = transport.request({ action = action, vault = vault.id, path = path, offset = offset, limit = 30 }, { aborted = function() return modal.closed end })
				if modal.closed then return end
				loading = false
				if not value or type(value.data) ~= "table" or #value.data > 100 then status.Text = tostring(why or "Invalid link listing."); return end
				for _, child in ipairs(rows:GetChildren()) do if child:IsA("GuiObject") then child:Destroy() end end
				status.Text = tostring(value.total or #value.data) .. (action == "links" and " outgoing links" or " backlinks")
					.. (value.incomplete and ". Coverage is incomplete." or ".")
				for index, link in ipairs(value.data) do
					if type(link) == "table" then
						local resolved = env.require("runtime/obsidian").path(link.path)
						local label = resolved or tostring(link.target or "Unresolved link")
						local row = P.rowButton(rows, { name = "ObsidianLink_" .. tostring(index), vertical = true, auto = "Y", size = UDim2.new(1, 0, 0, 0),
							padding = theme.space.sm, bg = theme.color.surfaceRaised, radius = theme.radius.md, gap = theme.space.xxs,
							layoutOrder = index, onClick = function()
								if loading or not resolved then return end
								loading = true; status.Text = "Reading linked note..."
								clock.spawn(function()
									local document, problem = transport.readNote(vault.id, resolved, { aborted = function() return modal.closed end })
									if modal.closed then return end; loading = false
									if document then env.require("ui/obsidian_editor").open(vault, document) else status.Text = tostring(problem) end
								end)
							end })
						P.text(row.row, { text = label, role = "label", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), layoutOrder = 1 })
						if not resolved then
							P.text(row.row, { text = link.ambiguous and "Multiple notes match. Use the exact path from the vault browser." or "No local note resolved.",
								role = "caption", wrap = true, auto = "Y", size = UDim2.new(1, 0, 0, 0), color = theme.color.textTertiary, layoutOrder = 2 })
						end
					end
				end
				nextOffset = type(value.nextOffset) == "number" and value.nextOffset == offset + #value.data and #value.data > 0 and value.nextOffset or nil
				more.setEnabled(nextOffset ~= nil)
			end)
		end
		P.button(modal.footer, { text = "Close", variant = "ghost", size = "sm", layoutOrder = 1, onClick = modal.close })
		more = P.button(modal.footer, { name = "ObsidianMoreLinks", text = "More", variant = "secondary", size = "sm", layoutOrder = 2,
			onClick = function() if not loading and nextOffset then offset = nextOffset; load() end end })
		load()
		return modal
	end
	return M
end
