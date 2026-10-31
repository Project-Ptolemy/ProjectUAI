-- Recognizable, bounded native scenes and responsive placement in the bundle.
-- Review source and generated artwork before running this verification.
package.path = "test/?.lua;test/mock/?.lua;" .. package.path
local envMock = require("env")
local h = envMock.new()
local UI = assert(h.boot("dist/uai-ui.lua"))
local passed = 0
local function check(label, value) assert(value, label); passed = passed + 1; print("ok " .. label) end
local window = UI:CreateWindow({ Id = "artwork-main", Palette = "Halloween", SeasonalTheme = false, ReducedMotion = true })
local other = UI:CreateWindow({ Id = "artwork-other", Palette = "Christmas", ReducedMotion = true })
local section = window:Tab("Main"):Section("State")
local changes = 0
local draft = section:Input({ Id = "draft", Default = "saved", Callback = function() changes = changes + 1 end })
local input = assert(h.byName("Input", draft.Frame))
input.Text = "unfinished draft"
local frame, controlFrame = window.Frame, draft.Frame
local art, root = window._seasonalArt, window._seasonalArt.Root
local function node(name, parent) return h.byName(name, parent or root) end
local function bottom(object) return object.AbsolutePosition.Y + object.AbsoluteSize.Y end
h.settle(0.3)
check("Halloween supplies a substantial pumpkin and ghost scene", art.SceneName == "Halloween" and root:GetAttribute("SeasonalTheme") == "Halloween"
	and node("Pumpkin") and node("Ghost") and node("Moon") and root.Visible and root.AbsoluteSize.Y == 72)
check("artwork has its own band between header and application content", window._seasonalBand.AbsolutePosition.Y >= bottom(window._header)
	and window._workspace.AbsolutePosition.Y >= bottom(window._seasonalBand) and window._seasonalBand.AbsoluteSize.Y >= 48)
local motifs = {
	Halloween = { "Pumpkin", "Ghost" }, Christmas = { "FirTree", "Gift", "Snowflake1" },
	NewYear = { "CelebrationStars", "Firework1", "Confetti1" }, Valentine = { "Heart1", "Heart2", "Heart3" },
	EarthDay = { "Globe", "EarthLeaves1" }, Pride = { "RainbowRibbon", "RainbowBand1", "RainbowBand6" }, Peace = { "Dove", "OliveBranch1" },
}
for _, name in ipairs({ "Halloween", "Christmas", "NewYear", "Valentine", "EarthDay", "Pride", "Peace" }) do
	window:SetAppearance({ Palette = name })
	local complete = true
	for _, motif in ipairs(motifs[name]) do if not node(motif) then complete = false end end
	check(name .. " has its distinct native artwork", art.SceneName == name and complete and root.Visible)
	local passive, nativeOnly = not root.Active and not root.Selectable and root.ClipsDescendants, true
	for _, item in ipairs(root:GetDescendants()) do
		if item:IsA("GuiObject") then passive = passive and not item.Active and not item.Selectable end
		if item.ClassName ~= "Frame" and item.ClassName ~= "UICorner" then nativeOnly = false end
	end
	check(name .. " artwork is noninteractive and uses no image or font assets", passive and nativeOnly)
	check(name .. " artwork stays within its finite node budget", art.NodeCount == #root:GetDescendants() + 1 and art.NodeCount <= 160)
end
check("changing one window cannot draw into another window's scene", other._seasonalArt.SceneName == "Christmas"
	and h.byName("FirTree", other._seasonalArt.Root) ~= nil and h.byName("Dove", other._seasonalArt.Root) == nil)
window:SetAppearance({ Palette = "Halloween" })
local originalScene = node("HalloweenScene")
local originalCount = #root:GetDescendants()
for _ = 1, 12 do window:SetAppearance({ Palette = "Halloween" }) end
check("same-season updates reuse the artwork and its mounted parent", node("HalloweenScene") == originalScene and window._seasonalArt == art
	and art.Root == root and #root:GetDescendants() == originalCount)
local pending = h.sched.pending()
for _ = 1, 12 do
	art:Update("Halloween", { Mode = "Dark", Canvas = window.Theme.Canvas, Accent = window.Theme.Accent })
	art:Layout(window._seasonalBand.AbsoluteSize.X, window._seasonalBand.AbsoluteSize.Y)
end
check("static artwork updates schedule no motion or effect tasks", h.sched.pending() == pending)
local darkGhost = node("Body", node("Ghost")).BackgroundColor3
window:SetAppearance({ Theme = "Light" })
check("light mode redraws pale motifs for a readable silhouette", node("Body", node("Ghost")).BackgroundColor3 ~= darkGhost
	and window._seasonalArt == art and root:GetAttribute("SeasonalTheme") == "Halloween")
window:SetAppearance({ Palette = "NewYear" })
local center = node("Center", node("Firework1"))
window:SetAppearance({ Colors = { Canvas = h.dt.Color3.fromRGB(245, 230, 243) } })
check("custom palette repaint updates scene cutouts without remounting controls", center == node("Center", node("Firework1"))
	and center.BackgroundColor3 == node("NewYearScene").BackgroundColor3)
window:SetAppearance({ Palette = "Halloween", Theme = "Dark", Colors = {} })
for _, viewport in ipairs({ { 1280, 720, false }, { 390, 844, true }, { 320, 568, true } }) do
	h.services.UserInputService.TouchEnabled = viewport[3]
	h.setViewport(viewport[1], viewport[2])
	local height = root.AbsoluteSize.Y
	check("artwork stays visible and fitted at " .. viewport[1] .. " pixels", root.Visible and height >= 28 and height <= 72
		and root.AbsoluteSize.X == window._seasonalBand.AbsoluteSize.X and bottom(window._seasonalBand) <= window._workspace.AbsolutePosition.Y)
	check("motifs remain recognizable at " .. viewport[1] .. " pixels", node("Pumpkin").AbsoluteSize.Y >= 27 and node("Ghost").AbsoluteSize.Y >= 26)
	check("artwork preserves footer space at " .. viewport[1] .. " pixels", bottom(window._seasonalBand) < h.byName("Attribution", window.Frame).AbsolutePosition.Y)
end
local uis = h.services.UserInputService
uis.OnScreenKeyboardVisible, uis.OnScreenKeyboardPosition, uis.OnScreenKeyboardSize = true, h.dt.Vector2.new(0, 120), h.dt.Vector2.new(320, 448)
window:_Layout()
check("very short keyboard space releases the artwork band for controls", not window._seasonalBand.Visible and not root.Visible)
uis.OnScreenKeyboardVisible = false
window:_Layout()
check("artwork returns when keyboard space recovers", root.Visible and node("Pumpkin") ~= nil)
window:Minimize(); window:SetAppearance({ Palette = "EarthDay" }); window:Show()
check("minimized updates retain the scene for restore", art.SceneName == "EarthDay" and root.Visible and node("Globe"))
check("artwork changes preserve controls and application drafts", window.Frame == frame and draft.Frame == controlFrame
	and draft:Get() == "saved" and input.Text == "unfinished draft" and changes == 0)
window:SetAppearance({ Palette = "Neutral", SeasonalTheme = false })
check("ordinary palettes clear artwork and return all band space", art.SceneName == nil and #root:GetDescendants() == 0
	and not root.Visible and not window._seasonalBand.Visible and window._seasonalBand.AbsoluteSize.Y == 0
	and window._workspace.AbsolutePosition.Y < bottom(window._header) + 90)
window:SetAppearance({ Palette = "Pride" })
check("reusing a cleared renderer restores the rainbow scene", art.SceneName == "Pride" and node("RainbowRibbon") and root.Visible)
local replaced = UI:CreateWindow({ Id = window.Id, Palette = "Peace", ReducedMotion = true })
check("replacement destroys only the previous window's artwork", not art.Alive and art.NodeCount == 0 and not window.Alive
	and other.Alive and other._seasonalArt.Alive and replaced._seasonalArt.SceneName == "Peace")
check("fixed attribution remains independent of the decorative artwork", h.byName("Attribution", replaced.Frame).Text == "Project UAI | UI LIB.")
local replacementArt = replaced._seasonalArt
UI:DestroyAll(); h.settle(0.3)
check("all artwork and owned resources clean up without native property errors", not replacementArt.Alive and not other._seasonalArt
	and replacementArt.NodeCount == 0 and #h.errors() == 0 and #h.instanceState.typeErrors == 0)
print("UI library artwork: " .. passed .. " checks passed")
