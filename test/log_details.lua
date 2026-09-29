-- Native diagnostics disclosures use actual row buttons and bounded snapshots.
-- Run after rebuilding the reviewed client inputs: luajit test/log_details.lua
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h = require("env").new()
local handle = assert(h.boot())
h.settle(1)
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end
local function has(root, value) return h.textOf(root):find(value, 1, true) ~= nil end
local http, log = handle.env.require("net/http"), handle.env.require("runtime/log")
local frame = h.Instance.new("Frame", h.screen())
frame.Size = h.dt.UDim2.fromOffset(560, 640)
http.history = {
	{ stamp = "12:01:00", method = "GET", tag = "models", url = "https://test.invalid/v1/models",
		status = 200, ms = 12, bytes = 20, via = "executor", identity = "none", uaSent = false },
	{ stamp = "12:02:00", method = "POST", tag = "inference", status = 403, ms = 1500, bytes = 0,
		url = "https://user:password@test.invalid/v1/chat?api_key=QUERY_SECRET&api-version=2026",
		via = "roblox", identity = "claude", uaSent = false, droppedHeaders = { "User-Agent", "X-Custom" },
		attempt = 2, server = "edge", trace = "TRACE_SELECTED", mitigated = "challenge",
		error = "sk-private-secret-TAIL", response = "PRIVATE_RESPONSE_BODY", headers = { Authorization = "PRIVATE_HEADER" } },
}
local selected = http.history[2]
local panel = handle.env.require("ui/panels/logs").new(frame)
local requestRow = h.byName("RequestEntry", frame)
check("the entire request row is the activation target", requestRow:IsA("TextButton") and requestRow.Active and requestRow.Selectable)
check("request contents belong to its button", h.byName("Content", requestRow).Parent == requestRow)
h.click(requestRow)
local dialog = assert(panel.detail)
check("requests open a native detail popup", dialog.card.Name == "RequestDetails" and h.byName("BodyScroll", dialog.card))
check("request popup contains status, timing and transport evidence", has(dialog.card, "403") and has(dialog.card, "1500 ms")
	and has(dialog.card, "roblox") and has(dialog.card, "TRACE_SELECTED") and has(dialog.card, "challenge") and has(dialog.card, "X-Custom"))
check("URL credentials and known tokens are redacted", not has(dialog.card, "QUERY_SECRET") and not has(dialog.card, "user:password") and has(dialog.card, "api-version=2026"))
check("the popup excludes request headers, response bodies and full keys", not has(dialog.card, "PRIVATE_RESPONSE_BODY")
	and not has(dialog.card, "PRIVATE_HEADER") and not has(dialog.card, "private-secret"))
local snapshot = h.textOf(dialog.card)
selected.trace, selected.url = "TRACE_CHANGED", "https://changed.invalid"
http.clearHistory()
h.settle(0.5)
check("live refresh and history clearing keep the selected snapshot", not dialog.closed and h.textOf(dialog.card) == snapshot)
h.click(h.byName("CopyDetail", dialog.card))
local copied = tostring(h.sandbox.__clipboard)
check("detail copy exports exactly the selected evidence", copied:find("TRACE_SELECTED", 1, true) and not copied:find("TRACE_CHANGED", 1, true)
	and not copied:find("PRIVATE_RESPONSE_BODY", 1, true) and not copied:find("QUERY_SECRET", 1, true))
h.click(h.byName("CloseDetails", dialog.card))
check("closing releases the active popup", dialog.closed and panel.detail == nil)

http.history = { { stamp = "12:03:00", method = "GET", tag = "models", url = "https://test.invalid", status = 200, ms = 10, bytes = 0 } }
panel.refresh()
h.click(h.byName("RequestEntry", frame))
dialog = assert(panel.detail)
check("successful responses do not invent an error", has(dialog.card, "No transport error recorded") and not has(dialog.card, "Native HTTP transport failed"))
check("missing metadata is stated honestly", has(dialog.card, "Not recorded"))
h.click(h.byName("CloseDetails", dialog.card))

log.clear()
local message = string.rep("A detailed application message.\n", 70) .. "MESSAGE_END"
local detail = string.rep("A diagnostic line.\n", 70) .. "DETAIL_END Bearer abcdefghijklmnop sk-private-log-TAIL"
log.error("provider", message, detail)
h.click(h.byName("Segment_log", frame))
local logRow = h.byName("LogEntry", frame)
check("application logs use the entire row too", logRow:IsA("TextButton") and h.byName("Content", logRow).Parent == logRow)
h.click(logRow)
dialog = assert(panel.detail)
check("application popup retains the full message and detail", dialog.card.Name == "LogDetails" and has(dialog.card, message)
	and has(dialog.card, "DETAIL_END") and has(dialog.card, "provider") and has(dialog.card, "error"))
check("application secrets remain redacted", not has(dialog.card, "abcdefghijklmnop") and not has(dialog.card, "private-log"))
local previous = h.textOf(dialog.card)
log.clear(); log.info("new", "NEW_LOG_ENTRY")
h.settle(0.4)
check("log snapshot survives replacement of its source history", h.textOf(dialog.card) == previous and not dialog.closed)
h.click(h.byName("CopyDetail", dialog.card))
check("application detail copy remains scoped to the selected log", tostring(h.sandbox.__clipboard):find("MESSAGE_END", 1, true)
	and tostring(h.sandbox.__clipboard):find("DETAIL_END", 1, true) and not tostring(h.sandbox.__clipboard):find("NEW_LOG_ENTRY", 1, true))
handle.env.require("runtime/caps").fn.clipboard = function() return false end
h.click(h.byName("CopyDetail", dialog.card))
check("clipboard rejection is visible", has(h.byName("CopyDetail", dialog.card), "Retry"))
h.setViewport(390, 720)
h.settle(0.3)
local room = handle.env.require("ui/responsive").usableRect(handle.env.require("ui/overlay").layer, 0)
check("long diagnostics remain inside the phone viewport", dialog.card.Size.X.Offset <= room.width and dialog.card.Size.Y.Offset <= room.height
	and h.byName("BodyScroll", dialog.card).ScrollingEnabled ~= false)
frame:Destroy()
h.settle(2.2)
check("panel destruction closes its popup", dialog.closed)
check("diagnostic UI has no asynchronous or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print(string.format("Log details: %d checks passed", checks))
