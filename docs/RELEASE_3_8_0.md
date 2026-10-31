# Project UAI 3.8.0

Release dated October 31, 2026. The client, bridge, browser workspace and
Windows desktop app use **3.8.0**. UI LIB is independently versioned **1.6.0**;
the embedding SDK is **1.1.0**. Android companion remains **3.7.1**.

## Everyday improvements

- **Build scripts step by step.** Save a goal and acceptance criteria, inspect,
  plan, build, validate and review. Actual compiler/test receipts accompany the
  goal. Editing source requires fresh validation before completion.
- **Give the model fewer declarations.** Focused groups actions into at most nine
  families plus seven direct tools. Schemas and examples are available on demand;
  existing action permissions and request scope remain enforced.
- **Work faster in Code.** Review basic or UI LIB project starters, quick-open a
  script, search workspace source, jump to a Unicode column, transform selected
  lines, reopen closed views and clear finished output.
- **Keep conversations organized.** Pin threads, see unread background results,
  search retained dialogue, recover drafts and preview Markdown exports.
- **Use Obsidian notes.** Connect local vaults through the bridge, browse/search,
  inspect links and edit Markdown with revision checks. Connections default to
  read-only; unsaved recovery drafts stay in memory.
- **Choose a provider explicitly.** Project UAI Free is opt-in and separate from
  HCNSEC personal-key connections. Model favorites, recents and connection health
  reduce repeated setup work.
- **See startup progress.** The new card shows preparation, restore and interface
  stages, actual component counts, elapsed time and a readable failure state.
- **Adapt UI LIB to your script.** Neutral defaults, four palettes, light/dark
  themes, density, shape, typography and reusable readout/form controls make its
  appearance more general. Native reduced-motion settings remain retired.

## Release artifacts

Download the bundles, Windows app and update manifests from
[GitHub release v3.8.0](https://github.com/Project-Ptolemy/ProjectUAI/releases/tag/v3.8.0).
The release includes `SHA256SUMS` for all nine packaged assets. GitHub also
provides source archives containing the embedding SDK and examples.

| Artifact | Purpose |
| --- | --- |
| `dist/uai.lua` and `dist/uai.manifest.json` | Native client and deterministic build metadata. |
| `dist/uai-ui.lua` and `dist/uai-ui.manifest.json` | Standalone UI LIB and SHA-256 manifest. |
| `dist/uai-bridge-package.json` and `dist/bridge-release.json` | Bridge package and updater metadata. |
| `desktop/release/UAI-Bridge-3.8.0-win-x64.exe`, adjacent `.sha256` and `desktop-release.json` | Standalone 3.8.0 desktop app with embedded bridge/client assets. |
| Root website and `docs/` mirrors | Download/setup pages matching this release. |

Existing provider profiles and configured connections are retained. New installs
use Focused tools; saved tool profiles are preserved. Companion files are outside
this release change set. See the [verification record](POLISH_2026_10.md),
[desktop build instructions](../desktop/README.md), [startup guide](STARTUP.md)
and [changelog](../CHANGELOG.md).
