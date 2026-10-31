# Development workflow

Read [AGENTS.md](../AGENTS.md) and [SPEC.md](../SPEC.md) before changing the client.
Source modules use a LuaJIT-compatible Luau dialect and one factory per module:
`return function(env) ... end`. Runtime modules do not depend on UI or transport.
The established client UI uses `src/ui`; new script interfaces use
[Project UAI UI LIB](UI_LIBRARY.md).

## Repository map

| Path | Responsibility |
| --- | --- |
| `init.lua` | Bootstrap and client lifetime |
| `src/runtime/` | State, storage and reusable runtime policies |
| `src/net/` | HTTP, relay, bridge and transport adapters |
| `src/provider/` | Provider catalog, credentials, models and protocol behavior |
| `src/agent/` | Conversations, prompts, permissions, tool dispatch and accounting |
| `src/tools/` | Model-facing tools |
| `src/ui/` | Existing Roblox application |
| `ui-lib/` | Standalone script UI library and examples |
| `bridge/`, `desktop/` | Browser/local bridge and Windows launcher |
| `test/` | Offline behavior and native syntax harnesses |
| `tools/` | Deterministic generators and verification commands |

## Review, build, inspect, verify

Manually review every changed source, test, guide, example and build input first.
Then build affected artifacts, inspect their outputs, and run checks that exercise
the change. Review each fix before rebuilding and rerunning affected checks.
Generated bundles, manifests and embedded references are never hand-edited.

For UI library or its guide changes, after input review:

```text
node tools/build_ui_lib.js
```

Inspect the generated bundle, manifest and embedded guide; then run:

```text
luajit test/ui_library.lua
node tools/build_ui_lib.js --check
```

For client changes, build after review:

```text
luajit tools/bundle.lua --native
```

Inspect `dist/uai.lua`, its manifest and any generated guide reference. Then run:

```text
luajit test/check.lua --native
luajit tools/bundle.lua --native --check
luajit test/run.lua --native
```

Add the relevant focused suites from `test/`. Use the official `luau-compile --null`
for actual Luau syntax where available. `LUAJIT` and `LUAU_COMPILE` override tool paths
in the native runner. The full `--verify-only` workflow is available for deliberate
whole-client verification after output review; it need not run after every small fix.

The root website sources are `index.html`, `style.css` and `script.js`.
After client/catalog and website input review, `node tools/build_site.js` generates
catalog regions and exact `docs/` publishing mirrors. Inspect them, then use
`node tools/build_site.js --check`, `python test/site_static.py`, and the browser
suite where Playwright is available.

See [bridge development](../bridge/README.md) for its package and test commands.
Keep Playwright/Chromium and downloaded tools outside tracked source. Preview
screenshots approximate layout; use [host scenarios](CODE_WORKSPACE_TESTING.md)
for native rendering, input, performance and executor behavior.
