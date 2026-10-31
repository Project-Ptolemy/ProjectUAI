# Project UAI UI LIB

An independent, responsive Roblox UI library with neutral defaults, semantic
palettes, adjustable density/shape/type, and reusable application controls.

```lua
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai-ui.lua"))()
```

- [API and agent guide](../docs/UI_LIBRARY.md)
- [Embedding, state binding, and application patterns](../docs/UI_LIBRARY.md#embedding)
- [Full UAI embedding reference](../docs/EMBEDDING.md)
- [Custom assistant workbench](../examples/embedding/README.md)
- [Starter script](examples/starter.lua)
- [All-controls showcase](examples/showcase.lua)
- [Forms, profiles, debouncing and activity examples](examples/README.md)
- [Validated forms](../docs/UI_LIBRARY_FORMS.md), [profile storage](../docs/UI_LIBRARY_PROFILES.md), and [owned work](../docs/UI_LIBRARY_LIFECYCLE.md)
- [Appearance preferences](../docs/UI_LIBRARY_APPEARANCE.md), [structured readouts](../docs/UI_LIBRARY_READOUTS.md), and [lists/actions](../docs/UI_LIBRARY_COLLECTIONS.md)
- [Built library](../dist/uai-ui.lua) and [SHA-256 manifest](../dist/uai-ui.manifest.json)

Manually review changes, build with `node tools/build_ui_lib.js`, and inspect the
outputs before checking with `luajit test/ui_library.lua`. Follow the full
verification sequence in the guide after client or documentation changes.
The library owns layout, input, state, cleanup, and the permanent
`Project UAI | UI LIB.` footer. Navigation and action labels use text; the library
draws its own brand mark and window-control glyphs. A pinned sidebar profile shows
the local player and game; Roblox supplies the headshot. Owned transitions support
reduced motion. Scripts own application logic.

Every window automatically includes an Appearance tab for palettes, contrast,
density, shape, typeface, tab headings, text size, and motion. Detailed color groups collapse
to keep common settings easy to reach. Existing setters stay reflected, and
configuration profiles retain the full appearance. `SetAppearance`,
`GetAppearance`, and `ResetAppearance` expose the same preferences to scripts.

Mobile windows leave space for the game by default and resize with a 44px touch
grip. `SetSize`, `GetSize`, and `ResetSize` expose sizing preferences while the
library handles safe insets, rotation, and keyboard obstruction.

The built-in Light/Dark action is a sun/moon header icon to the left of Minimize
and uses the existing token palettes, including open
pickers and dialogs. `GetTheme()` and `ToggleTheme()` complement `SetTheme()`;
`ThemeToggle = false` omits the built-in action. Explicit configuration profiles
also retain the chosen mode and custom accent, without a separate settings file.

The visual refresh preserves the v1 API and saved configuration format. Existing
scripts receive the updated window, navigation, controls, pickers and dialogs
without migration. Simple headings are the default; detailed headings and live
counts are optional and scroll with the content. The
window keeps its touch targets and keyboard-safe layout.

Use the library independently for a script UI, or pass it into a view factory
alongside a live UAI client. `Parent` chooses the owned ScreenGui's parent; it
does not dock a window into a Frame. Keep model state outside controls, use
silent setters for reflection, and register view resources with `window:Give`.
The guide covers local ModuleScript loading, configuration, asynchronous work,
responsive layouts, and adding reusable capabilities under `src/`.

UI LIB 1.5.0 adds required/pattern/custom input validation, explicit draft commits,
atomic form snapshots and updates, named profile listing/deletion, and owned
Delay/Debounce helpers. `Reveal` opens the destination field for error recovery.
Tabs, sections, action wording and badge tones update through public methods.
The v1 configuration format remains compatible; loading preferences is silent
unless the caller explicitly requests callbacks.

UI LIB 1.6.0 adds Neutral, Graphite, Ocean, Forest and Rose palettes, High contrast,
Compact/Comfortable/Spacious spacing, named corner shapes and built-in font
families. `NumberInput`, `TextView`, `ItemList`, `ActionGroup`, `Callout` and
`KeyValue` cover numeric drafts, selectable output, paged collections and
structured readouts. The [workspace example](examples/workspace.lua) combines them.
