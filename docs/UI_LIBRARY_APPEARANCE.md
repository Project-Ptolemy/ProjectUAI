# Choose a library appearance

UI LIB 1.6.0 starts with Dark mode, a saved Neutral palette, simple tab titles, comfortable
spacing, rounded corners and Sans typography. Every window has the same built-in
Appearance tab, so a script does not need to declare a settings interface.

```lua
local window = UI:CreateWindow({
	Id = "session-dashboard", Title = "Session dashboard",
	Palette = "Forest", Density = "Compact", Shape = "Square",
	Typography = "System", TabHeader = "Simple",
})
```

Palette choices are Neutral, Graphite, Ocean, Forest, Rose, Halloween, Christmas,
NewYear (New Year), Valentine (Valentine's Day), EarthDay (Earth Day), Pride,
and Peace (Peace Day). All work with
`Theme = "Dark"` or `"Light"`. Graphite retains a warm accent for scripts that
prefer it. `Contrast = "High"` strengthens text, surface edges and status tones;
it is most predictable with a built-in palette and no conflicting surface
overrides. Custom colors remain an advanced preference and may affect contrast.

With `SeasonalTheme = true` (the default), ordinary palettes automatically use
Halloween on October 30–November 2, Christmas on December 20–26, and New Year
on December 31–January 2 each year. Dates use the player's local calendar and
include both endpoints. The saved palette returns when the season ends.
Halloween pairs plum with pumpkin orange; Christmas pairs evergreen with
cranberry red; New Year pairs midnight blue with gold. The Dark/Light setting
and custom colors remain in effect.
Other annual palettes celebrate Valentine's Day on February 14, Earth Day on
April 22, Pride throughout June, and International Peace Day on September 21.
They use berry/rose, blue-green/leaf green, violet/magenta/cyan, and slate
teal/sky blue respectively.

`GetAppearance().Palette` keeps your saved choice, while `GetActivePalette()`
reports the currently displayed palette. Explicit seasonal choices take
precedence over the calendar and remain available year-round. Scripts control
automatic selection through `SeasonalTheme`; the full Project UAI client's
enable switch is in Settings → General → Appearance:

```lua
window:SetAppearance({ Palette = "Halloween" })
window:SetAppearance({ Palette = "Ocean", SeasonalTheme = false })
```

Windows check their local date at creation and at most every 60 seconds while
automatic changes are needed. Hidden and minimized windows still update;
destroying a window releases its watcher. If the host cannot read the local date,
the saved palette stays active. Profiles save the preference rather than a
temporary calendar choice.

Compact reduces row padding and desktop target height. Comfortable is the
default. Spacious adds room around controls. All densities retain at least
44-pixel touch targets and increase targets for larger text. Density is not a
scale transform: text stays at the requested size.

Rounded uses an 8-pixel window radius, Soft uses 14, and Square uses zero.
`CornerRadius` is an explicit 0–16 override and scales related section/field
corners. When it does not match a preset, `GetAppearance().Shape` is `"Custom"`.
Avatars, switch tracks and slider thumbs preserve their functional shapes.

Sans uses BuilderSans with a Gotham fallback. System uses SourceSans; Mono uses
Code. No fonts are downloaded. A `TextView` with `Code = true` remains monospace
independently of the rest of the window. `TextScale` remains available from
0.85 to 1.5. Simple tab headers contain a title, Detailed adds an introduction and
live counts, and Hidden leaves the tab body to its sections.

`SetAppearance` changes any subset atomically. It preserves values, input drafts,
selection, scroll position and control handles. It also updates open pickers,
dialogs and the restore launcher. `ResetAppearance` restores constructor choices.
The fixed attribution and automatic local profile remain library responsibilities.

`UI:GetAppearanceOptions()` returns copied option arrays for discovery.
`UI:GetPalette("Ocean", "Light")` returns a copied token map for inspection;
applications usually need only semantic option names. Choosing a palette in the
built-in UI resets color overrides. A programmatic palette change keeps them;
pass `Accent = false, Colors = {}` to clear them explicitly.

Named [configuration profiles](UI_LIBRARY_PROFILES.md) save the complete
appearance using the compatible v1 format. Older files retain current choices
for fields they omit. See the [full API](UI_LIBRARY.md#automatic-appearance-settings).
