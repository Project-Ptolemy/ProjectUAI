-- Semantic appearance preferences repaint live controls without replacing state.
local h, UI, window, section, check, done = dofile("test/ui_library_support.lua").new("semantic-appearance")
local field = section:Input({ Id = "draft", Text = "Your label", Default = "saved" })
local input = h.byName("Input", field.Frame)
input.Text = "unsaved draft"
local initial = window:GetAppearance()
check("neutral defaults use simple headings and a named shape", initial.Palette == "Neutral" and initial.TabHeader == "Simple" and initial.Shape == "Rounded")
local options = UI:GetAppearanceOptions()
options.Palette[1] = "changed"
check("preference options are isolated copies", UI:GetAppearanceOptions().Palette[1] == "Neutral")
local palette = UI:GetPalette("Ocean", "Light")
palette.Text = h.dt.Color3.new(1, 0, 0)
check("palette lookup returns a detached map", UI:GetPalette("Ocean", "Light").Text ~= palette.Text)
for _, mode in ipairs({ "Dark", "Light" }) do
	for _, name in ipairs(UI:GetAppearanceOptions().Palette) do
		window:SetAppearance({ Theme = mode, Palette = name, Accent = false, Colors = {} })
		check(name .. " " .. mode .. " colors update mounted inputs", input.BackgroundColor3 == window.Theme.Input and field._label.TextColor3 == window.Theme.Text)
	end
end
local function luminance(color)
	local function linear(n) return n <= 0.04045 and n / 12.92 or ((n + 0.055) / 1.055) ^ 2.4 end
	return 0.2126 * linear(color.R) + 0.7152 * linear(color.G) + 0.0722 * linear(color.B)
end
local function contrast(a, b)
	local x, y = luminance(a), luminance(b)
	return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
for _, mode in ipairs({ "Dark", "Light" }) do
	window:SetAppearance({ Theme = mode, Contrast = "High" })
	check(mode .. " high contrast keeps primary text above 7:1", contrast(window.Theme.Text, window.Theme.Surface) >= 7)
	check(mode .. " high contrast strengthens borders", contrast(window.Theme.Edge, window.Theme.Surface) >= 3)
end
window:SetAppearance({ Contrast = "Standard", Density = "Compact" })
local compact = field.Frame.Size.Y.Offset
window:SetAppearance({ Density = "Spacious" })
check("density changes row spacing", field.Frame.Size.Y.Offset > compact)
h.services.UserInputService.TouchEnabled = true
window:SetAppearance({ Density = "Compact" })
check("compact touch targets preserve their minimum", window.Target >= 44)
window:SetAppearance({ Shape = "Square", Typography = "Mono", TabHeader = "Hidden" })
check("shape changes live corners", window.Frame:FindFirstChildOfClass("UICorner").CornerRadius.Offset == 0)
check("typography reaches existing fields and labels", input.Font == h.sandbox.Enum.Font.Code and field._label.Font == h.sandbox.Enum.Font.Code)
check("hidden tab headings remain hidden after search", not window.Tabs[1]._intro.Visible)
window:SetSearch("Your label")
check("search does not restore hidden headings", not window.Tabs[1]._intro.Visible)
check("appearance changes preserve the input draft", input.Text == "unsaved draft" and field:Get() == "saved")
window:SetSearch("")
window:SetAppearance({ Palette = "Forest", Theme = "Dark", Shape = "Soft", Typography = "System", TabHeader = "Detailed" })
window:SetSearch("no matching label")
window:SetTextScale(1.1)
check("responsive reflow retains an empty search's hidden heading", not window.Tabs[1]._intro.Visible)
window:SetSearch("")
local saved = window:ExportConfig()
window:ResetAppearance()
check("reset restores the original semantic preferences", window:GetAppearance().Palette == initial.Palette and window:GetAppearance().Density == initial.Density)
check("profile restores semantic preferences", window:ImportConfig(saved) and window:GetAppearance().Palette == "Forest" and window:GetAppearance().Typography == "System" and window:GetAppearance().Shape == "Soft")
for _, invalid in ipairs({ { Palette = "missing" }, { Density = false }, { Shape = "Triangle" }, { Typography = "Uploaded" }, { TabHeader = "Unknown" }, { Contrast = "None" } }) do
	local before = window:GetAppearance()
	check("invalid preference is atomic", not pcall(function() window:SetAppearance(invalid) end) and window:GetAppearance().Palette == before.Palette)
end
check("attribution and local profile remain", h.byName("Attribution", window.Frame).Text == "Project UAI | UI LIB." and h.byName("Profile", window.Frame) ~= nil)
done()
