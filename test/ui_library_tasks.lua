package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h, UI, window, section, check, done = require("ui_library_support").new("tasks")
local calls = 0
local cancel = window:Delay(0.2, function() calls = calls + 1 end)
cancel(); cancel(); h.settle(0.3)
check("owned delays cancel idempotently", calls == 0)
window:Delay(0.1, function() calls = calls + 1 end)
h.settle(0.2)
check("owned delays execute once", calls == 1)
local observed, count
local schedule, stop = window:Debounce(0.1, function(...)
	count = select("#", ...); observed = { ... }
end)
schedule("old"); schedule("new", nil, false)
h.settle(0.2)
check("debounce keeps the latest arguments including nil positions", count == 3 and observed[1] == "new" and observed[2] == nil and observed[3] == false)
observed = nil; schedule("cancelled"); stop(); h.settle(0.2)
check("debounce cancellation clears pending arguments", observed == nil)
local reentrant, runs = nil, 0
reentrant = window:Debounce(0.05, function(value)
	runs = runs + 1
	if value == 1 then reentrant(2) end
end)
reentrant(1); h.settle(0.2)
check("a debounce callback can schedule its next update", runs == 2)
local resumed = false
window:Delay(0, function() h.sandbox.task.wait(0.3); resumed = true end)
h.settle(0.05)
window:Delay(0.2, function() calls = calls + 1 end); schedule("destroyed")
window:Destroy(); h.settle(0.5)
check("destroy cancels pending and yielded owned delays", calls == 1 and not resumed and observed == nil)
check("retained debounce functions stop admitting work after destroy", schedule("late") == false)
local replacement = UI:CreateWindow({ Id = "replacement" })
replacement:Delay(0.2, function() calls = calls + 1 end)
local current = UI:CreateWindow({ Id = "replacement" }); h.settle(0.3)
check("same-Id replacement releases old scheduled work", calls == 1)
check("invalid delays reject before scheduling", not pcall(function() current:Delay(-1, function() end) end))
done()
