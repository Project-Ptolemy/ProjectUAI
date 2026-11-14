-- Settings entry points: one sidebar row, one modal, no leftover Customize.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local checks = 0
local function check(label, condition)
	assert(condition, label)
	checks = checks + 1
	print("ok " .. label)
end

local h = envMock.new()
h.setViewport(1280, 820)
local app = assert(h.boot("dist/uai.lua"))
require("password_fixture")(h, app)
h.settle(1)

local sidebar = assert(h.byName("Sidebar"), "missing sidebar")
check("the old Customize row is gone", h.byName("Customize", sidebar) == nil)
local settings = assert(h.byName("Settings", sidebar), "missing Settings row")
check("Settings names the surface", h.byName("Label", settings).Text == "Settings")

h.click(settings)
h.settle(0.6)
local dialog = assert(h.byName("SettingsDialog"), "Settings did not open the modal")
check("the modal lists categories", h.byName("Categories", dialog) ~= nil)
check("the modal is not the stacked panel", h.byName("SettingsPanel") == nil)

h.press("Escape")
h.settle(0.5)
check("Escape closes it", h.byName("SettingsDialog") == nil)

-- The panel is still reachable from the app menu; the modal is the sidebar's path.
local more = h.byName("More", sidebar)
if more then
	h.click(more)
	h.settle(0.4)
	check("More no longer duplicates Settings", h.byName("NavRow_settings", sidebar) == nil)
end

check("no thread errors", #h.errors() == 0, h.errors()[1] and h.errors()[1].traceback or nil)
app.destroy()
h.settle(0.3)
print("settings entry: " .. checks .. " checks passed")
