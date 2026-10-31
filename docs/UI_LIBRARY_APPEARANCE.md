# Choose a library appearance

UI LIB 1.6.0 starts with neutral Dark surfaces, simple tab titles, comfortable
spacing, rounded corners and Sans typography. Every window has the same built-in
Appearance tab, so a script does not need to declare a settings interface.

```lua
local window = UI:CreateWindow({
	Id = "session-dashboard", Title = "Session dashboard",
	Palette = "Forest", Density = "Compact", Shape = "Square",
	Typography = "System", TabHeader = "Simple",
})
```

Palette choices are Neutral, Graphite, Ocean, Forest and Rose. All work with
`Theme = "Dark"` or `"Light"`. Graphite retains a warm accent for scripts that
prefer it. `Contrast = "High"` strengthens text, surface edges and status tones;
it is most predictable with a built-in palette and no conflicting surface
overrides. Custom colors remain an advanced preference and may affect contrast.

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
