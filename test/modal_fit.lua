-- Modal layout feedback, coalescing and cleanup; no application boot or images.
-- Run from the repository root: luajit test/modal_fit.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h = require("env").new()
local luau = require("luau")
local cache, warnings = {}, {}
local env = {
	services = h.services, uis = h.services.UserInputService, guisvc = h.services.GuiService,
	tween = h.services.TweenService,
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
cache["runtime/config"] = { get = function(_, fallback) return fallback end, changed = signal.new("config") }
cache["runtime/caps"] = { clipboard = false }
cache["runtime/log"] = { warn = function(_, _, detail) warnings[#warnings + 1] = detail end }
cache["ui/icons"] = { draw = function() end, close = function() end }
local responsive, theme = env.require("ui/responsive"), env.require("ui/theme")
local P, overlay, clock = env.require("ui/primitives"), env.require("ui/overlay"), env.require("runtime/clock")
local U, V = h.dt.UDim2, h.dt.Vector2
local root = h.Instance.new("Frame")
root.Size, root.Position = U.fromOffset(1000, 664), U.fromOffset(0, 36)
responsive.viewport, responsive.inset = V.new(1000, 700), V.new(0, 36)
responsive.mode, responsive.reduceMotion = "window", true
overlay.mount(root)

local passed = 0
local function check(label, condition)
	assert(condition, label)
	passed = passed + 1
	print("ok " .. label)
end
local runs, delays, measurements = 0, 0, 0
local delay, measure = clock.delay, P.measureText
clock.delay = function(seconds, callback, ...)
	delays = delays + 1
	return delay(seconds, function(...)
		runs = runs + 1
		callback(...)
	end, ...)
end
P.measureText = function(...)
	measurements = measurements + 1
	return measure(...)
end

local modal = overlay.modal({ title = "Live activity" })
local bodyLayout = modal.content:FindFirstChildOfClass("UIListLayout")
local footerLayout = modal.footer:FindFirstChildOfClass("UIListLayout")
local title = modal.card:FindFirstChild("Header"):FindFirstChildWhichIsA("TextLabel", true)
P.frame(modal.content, { size = U.fromOffset(300, 100) })
local action = P.frame(modal.footer, { size = U.fromOffset(80, 36) })
bodyLayout.AbsoluteContentSize = V.new(300, 100)
h.sched.advance(0.2)
check("populated modal settles without a resident layout task", h.sched.pending() == 0)

local sizeWrites = 0
local observeSize = modal.card:GetPropertyChangedSignal("Size"):Connect(function() sizeWrites = sizeWrites + 1 end)
local beforeMeasures, beforeDelays, beforeRuns = measurements, delays, runs
for _ = 1, 200 do bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Fire() end
check("layout bursts share one pending callback", delays == beforeDelays + 1 and h.sched.pending() == 1)
h.sched.step()
check("layout events wait for a frame instead of chaining deferred resumes", runs == beforeRuns)
h.sched.advance(1 / 60)
check("an unchanged burst needs only one fit", runs == beforeRuns + 1 and h.sched.pending() == 0)
for _ = 1, 20 do modal.relayout() end
check("unchanged relayout does not resize the card or remeasure its title", sizeWrites == 0 and measurements == beforeMeasures)

-- The general mock does not solve AutomaticSize. Model the dependency that
-- caused the native failure: fitting a card publishes new body bounds, which
-- request another fit. Equal writes also publish in this mock, exposing loops.
local feedback = modal.card:GetPropertyChangedSignal("Size"):Connect(function()
	bodyLayout.AbsoluteContentSize = V.new(300, 220)
end)
beforeRuns = runs
bodyLayout.AbsoluteContentSize = V.new(300, 180)
h.sched.advance(1 / 60)
check("feedback during a fit is retained for the next frame", runs == beforeRuns + 1 and h.sched.pending() == 1)
h.sched.advance(1 / 60)
check("feedback cannot exhaust one scheduler resume cycle", runs == beforeRuns + 2)
h.sched.advance(0.1)
check("native-like layout feedback reaches a fixed size and stops", h.sched.pending() == 0 and runs <= beforeRuns + 3)
check("the final body measurement is fitted", modal.card.Size.Y.Offset == modal.card:FindFirstChild("Header").Size.Y.Offset
	+ modal.footer.Size.Y.Offset + 220 + theme.space.sm + theme.space.xxs)
feedback:Disconnect()

beforeMeasures = measurements
title.Text = "Updated activity"
h.sched.advance(0.1)
check("title edits invalidate the cached text measurement once", measurements == beforeMeasures + 1)
beforeMeasures = measurements
root.Size = U.fromOffset(350, 664)
responsive.viewport = V.new(350, 700)
modal.relayout(); h.sched.advance(0.1)
check("width changes refresh cached title wrapping once", measurements == beforeMeasures + 1 and modal.card.Size.X.Offset < 350)

action.Size = U.fromOffset(80, 64)
h.sched.advance(0.1)
check("resized actions grow the footer", modal.footer.Size.Y.Offset == 64 + theme.space.sm * 2)
action.Visible = false
h.sched.advance(0.1)
check("hidden actions release the footer band", not modal.footer.Visible and modal.footer.Size.Y.Offset == 0)
action.Visible = true
h.sched.advance(0.1)
check("a collapsed footer still observes returning actions", modal.footer.Visible and modal.footer.Size.Y.Offset == 64 + theme.space.sm * 2)
root.Size = U.fromOffset(350, 120)
responsive.viewport = V.new(350, 156)
modal.relayout(); h.sched.advance(0.1)
check("constrained forms retain full-size actions in the body scroll", modal.footer.Parent == modal.scroll.instance
	and action.Size.Y.Offset == 64)
root.Size = U.fromOffset(350, 664)
responsive.viewport = V.new(350, 700)
modal.relayout(); h.sched.advance(0.1)
check("restoring space pins the same footer again", modal.footer.Parent == modal.card and action.Parent == modal.footer)

local actionSizeSignal = action:GetPropertyChangedSignal("Size")
action.Parent = root
check("detached actions release their layout subscription", actionSizeSignal:Count() == 0)
action.Parent = modal.footer
h.sched.advance(0.1)
check("returning actions receive exactly one layout subscription", actionSizeSignal:Count() == 1)
bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Fire()
beforeRuns = runs
modal.close()
check("closing cancels a pending fit immediately", h.sched.pending() == 0)
check("closing disconnects body, footer and child layout listeners", bodyLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Count() == 0
	and footerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Count() == 0 and actionSizeSignal:Count() == 0)
h.sched.advance(0.1)
check("closed modals never run delayed layout work", runs == beforeRuns and #overlay.open == 0)
observeSize:Disconnect()

local destroyed = overlay.modal({ title = "Destroyed before fitting" })
local destroyedLayout = destroyed.content:FindFirstChildOfClass("UIListLayout")
destroyedLayout.AbsoluteContentSize = V.new(100, 60)
destroyed.scrim:Destroy()
check("external destruction cancels both fitting and first reveal", destroyed.closed and h.sched.pending() == 0
	and destroyedLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Count() == 0)

local closing = overlay.modal({ title = "Close during layout" })
local closedInFit, writesAfterClose, cancelledActive = false, 0, false
local cancel = h.sandbox.task.cancel
h.sandbox.task.cancel = function(worker)
	if worker == coroutine.running() then cancelledActive = true end
	return cancel(worker)
end
for _, node in ipairs(closing.card:GetDescendants()) do
	node.Changed:Connect(function() if closedInFit then writesAfterClose = writesAfterClose + 1 end end)
end
closing.card:GetPropertyChangedSignal("Size"):Connect(function()
	if not closing.closed then closing.close(); closedInFit = true end
end)
closing.content:FindFirstChildOfClass("UIListLayout").AbsoluteContentSize = V.new(100, 120)
h.sched.advance(1 / 60)
h.sandbox.task.cancel = cancel
check("closing inside a fit never cancels the running producer", closedInFit and not cancelledActive)
check("an interrupted fit stops all later sizing and queued work", writesAfterClose == 0 and h.sched.pending() == 0 and #overlay.open == 0)
check("fitting reports no errors or invalid properties", #h.errors() == 0 and #warnings == 0 and #h.instanceState.typeErrors == 0)
print(string.format("%d modal fit checks passed", passed))
