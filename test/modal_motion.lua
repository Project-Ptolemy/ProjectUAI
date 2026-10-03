-- Focused source-level overlay transitions with asynchronous, interruptible tweens.
-- Run from the repository root: luajit test/modal_motion.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h = require("env").new()
local luau = require("luau")
local signalMock = require("instance").newSignal
-- The general settle helper rounds every step up to a 30 Hz frame. Exact virtual
-- time is needed here to inspect the hidden first frame and stale focus deadlines.
local advance = h.sched.advance
local cache, captured = {}, {}
local E, U, V = h.sandbox.Enum, h.dt.UDim2, h.dt.Vector2
local env = {
	services = h.services, uis = h.services.UserInputService, guisvc = h.services.GuiService,
	tween = { Create = function(_, target, info, goals)
		local tween = { Completed = signalMock("motion"), cancelled = false }
		local entry = { target = target, goals = goals, info = info, tween = tween, starts = {} }
		captured[#captured + 1] = entry
		function tween:Play()
			if target:IsA("GuiObject") then entry.size, entry.position = target.Size, target.Position end
			for key in pairs(goals) do entry.starts[key] = target[key] end
			h.sched.delay(info.Time / 2, function()
				if self.cancelled then return end
				for key, value in pairs(goals) do
					if type(value) == "number" then target[key] = (entry.starts[key] + value) / 2 end
				end
			end)
			h.sched.delay(info.Time, function()
				if self.cancelled then return end
				for key, value in pairs(goals) do target[key] = value end
				self.Completed:Fire(E.PlaybackState.Completed)
			end)
		end
		function tween:Cancel()
			self.cancelled = true
			self.Completed:Fire(E.PlaybackState.Cancelled)
		end
		return tween
	end },
}
function env.require(id)
	if cache[id] then return cache[id] end
	local file = assert(io.open("src/" .. id .. ".lua", "rb"))
	local source = file:read("*a"); file:close()
	local chunk, problems = luau.load(source, id)
	assert(chunk, problems and problems[1] and problems[1].msg)
	setfenv(chunk, h.sandbox)
	cache[id] = chunk()(env)
	return cache[id]
end
local signal = env.require("runtime/signal")
cache["runtime/config"] = {
	get = function(_, fallback) return fallback end,
	changed = signal.new("config"),
}
cache["runtime/caps"] = { clipboard = false }
cache["ui/icons"] = { draw = function() end, check = function() end, close = function() end }
cache["ui/brand"] = { draw = function() end }
local sent = 0
cache["agent/session"] = { current = function() return { send = function() sent = sent + 1; return true end } end }
cache["provider/registry"] = { active = function() return { label = "Provider" } end }
local responsive, theme = env.require("ui/responsive"), env.require("ui/theme")
local P, overlay = env.require("ui/primitives"), env.require("ui/overlay")
local root = h.Instance.new("Frame")
root.Size, root.Position = U.fromOffset(1000, 664), U.fromOffset(0, 36)
responsive.viewport, responsive.inset = V.new(1000, 700), V.new(0, 36)
responsive.mode, responsive.reduceMotion = "window", false
overlay.mount(root)
local passed = 0
local function check(label, condition)
	assert(condition, label)
	passed = passed + 1
	print("ok " .. label)
end
local function latest(target, property, value)
	for index = #captured, 1, -1 do
		local entry = captured[index]
		if entry.target == target and entry.goals[property] == value then return entry end
	end
end

local closed = 0
local modal = overlay.modal({ title = "Edit provider", onClose = function() closed = closed + 1 end })
check("modal remains transparent while its caller fills the body", modal.card.GroupTransparency == 1 and modal.scrim.BackgroundTransparency == 1)
check("modal preserves native geometry without entrance scaling", modal.card:FindFirstChildOfClass("UIScale") == nil)
P.text(modal.content, { text = "A form body", auto = "Y" })
modal.content:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize = V.new(300, 120)
local action = P.button(modal.footer, { text = "Save", size = "sm" })
advance(0.01)
check("modal does not flash its empty construction layout", modal.card.GroupTransparency == 1 and latest(modal.card, "GroupTransparency", 0) == nil)
advance(0.02)
local opening = assert(latest(modal.card, "GroupTransparency", 0))
local headerHeight = modal.card:FindFirstChild("Header").Size.Y.Offset
check("first reveal includes populated body and footer", opening.size.Y.Offset >= headerHeight + 120 + action.instance.Size.Y.Offset)
check("modal header uses compact vertical padding", headerHeight == math.max(theme.size.control, theme.text.title.height) + theme.space.sm * 2)
advance(0.08)
check("modal fades its complete surface together", modal.card.GroupTransparency > 0 and modal.card.GroupTransparency < 1)
check("fade never changes the laid-out card bounds", modal.card.Size.X.Offset == opening.size.X.Offset and modal.card.Size.Y.Offset == opening.size.Y.Offset
	and modal.card.Position.X.Offset == opening.position.X.Offset and modal.card.Position.Y.Offset == opening.position.Y.Offset)
modal.close(); modal.close()
check("closing during entrance cancels it and disables the card", opening.tween.cancelled and not modal.card.Interactable and closed == 1)
check("retiring modal controls stop accepting input", not action.instance.Active and not action.instance.Selectable and not action.instance.Interactable)
opening.tween.Completed:Fire(E.PlaybackState.Completed)
advance(0.2)
check("stale entrance completion cannot retain a closed modal", modal.scrim.Parent == nil and #overlay.open == 0 and closed == 1)

local listeners = responsive.changed:count()
local abandoned = overlay.modal({ title = "Cancelled before reveal" })
abandoned.close()
advance(0.3)
check("close before reveal releases the scrim without playing an entrance", abandoned.scrim.Parent == nil and latest(abandoned.card, "GroupTransparency", 0) == nil)
check("early dismissal releases its responsive listener", responsive.changed:count() == listeners)

local predecessor = overlay.modal({ title = "First dialog" })
advance(0.2)
predecessor.close()
check("visible modal has a short exit", predecessor.scrim.Parent ~= nil)
local replacement = overlay.dialog({ name = "ReplacementDialog" })
check("replacement removes the outgoing card and scrim immediately", predecessor.scrim.Parent == nil and #overlay.open == 1)
advance(0.2)
check("settings-size dialogs settle fully opaque without scaling", replacement.card.GroupTransparency == 0 and replacement.card:FindFirstChildOfClass("UIScale") == nil)
replacement.close(); advance(0.2)

local empty = overlay.modal({ title = "Confirm change" })
advance(0.2)
check("description-only prompts reserve no empty body band", empty.card.Size.Y.Offset == empty.card:FindFirstChild("Header").Size.Y.Offset)
P.button(empty.footer, { text = "Confirm", size = "sm" })
advance(0.05)
check("a confirmation footer stays pinned without an empty body", empty.footer.Parent == empty.card
	and empty.card.Size.Y.Offset == empty.card:FindFirstChild("Header").Size.Y.Offset + empty.footer.Size.Y.Offset)
empty.close(); advance(0.2)

responsive.reduceMotion = true
local reduced = overlay.modal({ title = "Reduced motion" })
advance(0.04)
check("reduced motion reveals at final opacity without a tween", reduced.card.GroupTransparency == 0 and latest(reduced.card, "GroupTransparency", 0) == nil)
reduced.close()
check("reduced motion dismissal releases the scrim immediately", reduced.scrim.Parent == nil)
responsive.reduceMotion = false

local quick = env.require("ui/quickchat")
quick.mount(overlay.layer)
local focused = 0
quick.field.focus = function() focused = focused + 1 end
quick.field.set("Keep the draft")
quick.show(); advance(0.08)
check("quick chat fades at its final native size", quick.card.GroupTransparency > 0 and quick.card.GroupTransparency < 1
	and quick.card:FindFirstChildOfClass("UIScale") == nil)
quick.hide(); advance(0.02)
local outgoing = latest(quick.scrim, "BackgroundTransparency", 1)
local opacity = quick.card.GroupTransparency
quick.show()
check("quick chat reverses from its rendered opacity", latest(quick.card, "GroupTransparency", 0).starts.GroupTransparency == opacity)
outgoing.tween.Completed:Fire(E.PlaybackState.Completed)
advance(0.03)
check("old quick-chat focus request cannot steal focus after reopen", focused == 0)
advance(0.14)
check("quick chat keeps its draft and stays visible after interrupted exit", quick.visible and quick.root.Visible and quick.card.GroupTransparency == 0 and quick.field.get() == "Keep the draft")
check("only the current quick-chat opening receives focus", focused == 1)
quick.hide()
quick.submit("A queued hidden action")
check("a retiring quick-chat action cannot send or clear the draft", sent == 0 and quick.field.get() == "Keep the draft")
local retiring = latest(quick.card, "GroupTransparency", 1)
quick.root:Destroy(); advance(0.3)
check("external quick-chat destruction cancels the owned fade", retiring.tween.cancelled and not quick.mounted)

responsive.reduceMotion = true
quick.mount(overlay.layer); quick.show()
check("reduced-motion quick chat appears synchronously", quick.root.Visible and quick.card.GroupTransparency == 0 and quick.scrim.BackgroundTransparency == theme.opacity.scrim)
quick.hide()
check("reduced-motion quick chat hides synchronously", not quick.root.Visible and quick.card.GroupTransparency == 1)

local geometryTween = false
for _, entry in ipairs(captured) do
	if entry.goals.Scale ~= nil or entry.goals.Size ~= nil or entry.goals.Position ~= nil then geometryTween = true end
end
check("dialog and quick-chat transitions never tween geometry", not geometryTween)
root:Destroy()
env.require("runtime/dispose").drain()
advance(0.3)
check("modal motion scenarios leave no asynchronous errors", #h.errors() == 0)
check("modal motion assigns valid property types", #h.instanceState.typeErrors == 0)
print("modal motion: " .. passed .. " checks passed")
