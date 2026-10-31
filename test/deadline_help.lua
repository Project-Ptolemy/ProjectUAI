-- Deadline guidance stays in native presentation, including narrow touch layouts.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local h = require("env").new()
h.services.UserInputService.TouchEnabled, h.services.UserInputService.MouseEnabled = true, false
h.setViewport(390, 720)
local app = assert(h.boot()); h.settle(0.5)
require("password_fixture")(h, app)
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1; print("ok " .. label) end
local helper = app.env.require("ui/deadline_help")
for _, text in ipairs({
	"deadline: nothing returned after 34.5s -- the transport gave up while the request was still running.",
	"The connection timed out", "connect ETIMEDOUT 127.0.0.1", "Relay result deadline reached; inference was cancelled rather than retried.",
	"HTTP 504 Gateway Timeout", "timeout",
}) do check("recognizes deadline evidence: " .. text, helper.matches(text)) end
for _, text in ipairs({
	"HTTP 403: free tier is only available within OpenCode", "HTTP 429: rate limit exceeded",
	"HTTP 400: invalid request timeout parameter", "Unsupported parameter: timeout", "Stopped.",
	"Your timeout is set to 30 seconds", "Invalid API key", "No provider is configured",
}) do check("ordinary errors receive no deadline advice: " .. text, not helper.matches(text)) end

app.app.show("chat"); h.settle(0.3)
local session = app.sessions.current()
local contextBefore = h.json.encode(session.ctx.messages)
local text = "deadline: nothing returned after 34.5s -- the transport gave up while the request was still running."
local payload = { message = text }
session.emit("error", payload); h.settle(0.3)
local view = app.app.chatPanel.view
local action = assert(h.byName("DeadlineHelp", view.scroll.instance))
local label = h.byName("DeadlineHelpTitle", action)
check("deadline transcript includes highlighted clickable tutorial guidance", action:IsA("TextButton") and action.Active and action.Selectable
	and action.BackgroundColor3 == app.env.require("ui/theme").color.warnSurface
	and label.Text == "Join our Discord for a tutorial on fixing this")
check("the complete guidance wraps on a narrow mobile row", label.TextWrapped and label.AutomaticSize == h.sandbox.Enum.AutomaticSize.Y
	and label.TextTruncate ~= h.sandbox.Enum.TextTruncate.AtEnd and label.Size.X.Scale == 1)
check("guidance does not alter the runtime error or model context", payload.message == text and h.json.encode(session.ctx.messages) == contextBefore
	and not h.json.encode(session.log):find("Join our Discord", 1, true))

app.config.set("ui.communityInvite.disabled", true)
h.click(action)
local community = app.env.require("ui/community").open()
local invite = h.byName("CommunityInvite", community.card):FindFirstChildOfClass("TextBox")
check("manual deadline help opens the existing official invite despite reminder opt-out", invite.Text == app.env.require("runtime/community").invite
	and invite.Text == "https://discord.gg/9xYyyYuKap" and invite.TextEditable == false)
local caps = app.env.require("runtime/caps")
local clipboard = caps.fn.clipboard
caps.fn.clipboard = function() return false end
h.click(h.byName("CommunityCopy", community.card))
check("clipboard rejection retains selectable invite access", not community.closed and invite.TextEditable == false)
caps.fn.clipboard = clipboard
community.close(); h.settle(0.2)

local frame = h.Instance.new("Frame", h.screen())
frame.Size = h.dt.UDim2.fromOffset(260, 500)
local ordinary = app.env.require("ui/chat/message").notice(frame, { tone = "bad", text = "HTTP 403: invalid API key" }, 1)
local informational = app.env.require("ui/chat/message").notice(frame, { tone = "info", text = "The previous request timed out" }, 2)
check("API refusals and informational notices do not gain a tutorial action", ordinary.help == nil and informational.help == nil)
ordinary.root:Destroy(); informational.root:Destroy()

local http = app.env.require("net/http")
http.history = { { stamp = "12:00:00", method = "POST", url = "https://provider.invalid/v1", status = 0,
	ms = 34500, bytes = 0, via = "executor", error = text } }
local panel = app.env.require("ui/panels/logs").new(frame)
h.click(h.byName("RequestEntry", frame))
local detail = assert(panel.detail)
check("request details highlight the same deadline guidance", h.byName("DeadlineHelp", detail.card) ~= nil)
h.click(h.byName("CopyDetail", detail.card))
check("copied diagnostics retain the actual error without tutorial copy", tostring(h.sandbox.__clipboard):find(text, 1, true)
	and not tostring(h.sandbox.__clipboard):find("Discord", 1, true) and http.history[1].error == text)
detail.close(); h.settle(0.2)

http.history[1].error, http.history[1].status = "HTTP 403: invalid request timeout parameter", 403
panel.refresh(); h.click(h.byName("RequestEntry", frame))
check("ordinary request refusals have no deadline help in diagnostics", h.byName("DeadlineHelp", panel.detail.card) == nil)
panel.detail.close(); h.settle(0.2)
local log = app.env.require("runtime/log")
log.clear(); log.warn("http", "POST failed after 34.5s", text)
h.click(h.byName("Segment_log", frame)); h.click(h.byName("LogEntry", frame))
check("transport deadline logs expose the same official help action", h.byName("DeadlineHelp", panel.detail.card) ~= nil)
frame:Destroy(); app.destroy(); h.settle(1)
check("deadline help releases UI without callback or property errors", #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print(string.format("Deadline help: %d checks passed", checks))
