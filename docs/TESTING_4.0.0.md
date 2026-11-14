# 4.0.0 external verification

Release: **4.0.0 - a major release**, November 14, 2026.

All release verification passed after manual source, documentation, example,
test and build-input review, followed by builds and generated-output inspection.
The final native build is **`4.0.0-305e82b2b811c2f6`**, containing 333 modules.
The Windows executable reports ProductVersion **4.0.0** and embeds the identical
client. All 50 desktop payload files and archive entries match the reviewed inputs.

| Verification | Final result |
| --- | --- |
| Complete native pipeline | 254 stages passed, including 241 focused suites; no skipped stages |
| Native static checker | 330 files parsed, 329 modules checked; zero failures or warnings |
| Main offline harness | 137 scenarios, 2,440 checks; zero failures |
| Official Luau compiler | All 374 pipeline inputs accepted; four unchanged native-scope exclusions compiled separately |
| Credential cryptography | 883 interoperability checks passed, including 219 authentication rejections; CPU benchmark passed |
| Native performance contracts | Nine cases, 30 assertions passed |
| Bridge process coverage | 216 unique supported tests passed; one Unix permission fixture skipped on Windows |
| Cowork browser | All 14 suites passed, including direct mod Apply and response-rate display |
| Portable executable MCP | Wire test passed; official MCP SDK 1.32.2 interoperability passed with 15 assertions |
| Windows executable in an isolated directory | 154 checks passed: self-test 88, startup 9, smoke 6, window 12, update 39 |
| Public website | 9,546 static checks and Chromium behavior checks passed |
| Models and pricing | Normalization, official-source metadata and generated snapshot freshness passed |

Focused coverage includes Vault persistence and full-content conflicts, deterministic
neural training and saved weights, dependent goal transitions, Read only/Full access
delegation, questions under Allow everything, skill recovery after compaction,
exact-revision mod application, cleanup/remounts, safe recovery and changed-build
replacement. Automatic discovery, provider protocol/history handling, modal sizing,
response-rate provenance and browser form submission are also covered.
The native mod-through-bridge suite passed five cases and 37 assertions on the
final build.

The bridge count combines the full process suite with its separately executed
portable executable fixture. That focused run replaces the main suite's missing
executable skip; the additional official-SDK test is reported separately.

The final pipeline used `node tools/test_native.js --verify-only` after the inspected
build. It checks bundle/catalog/library freshness, runs the offline and focused
suites, verifies cryptography, and invokes the official compiler. LuaJIT, Node.js,
the official Luau compiler and Python with `cryptography` are required. The usual
build and verification entry points are documented in [Development](DEVELOPMENT.md).

Additional commands used for this release:

```powershell
node tools/build_bridge.js --check
node bridge/tests/run.js
node bridge/tests/run.js --browser-only
node test/model_pricing.js
node tools/sync_pricing.js --check
python test/site_static.py
node test/site_browser.js
```

The standalone executable was copied to an isolated directory and exercised in
`--self-test`, `--startup-test`, `--smoke-test`, `--window-test` and `--update-test`
modes. Portable MCP checks used those exact final executable bytes.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `dist/uai.lua` | 4,619,581 | `971c5ac6a8ee8639b3ef403b4272c4031e04755ab5bab9eb5b481d0a2dfc420a` |
| `UAI-Bridge-4.0.0-win-x64.exe` | 67,625,347 | `e63b9ed4134393237e74fda0604b7515399c202c7ad020f0941ec809854b3ea4` |
| `dist/uai-bridge-package.json` | 1,445,886 | `9a16f48cc2205c3db6b3a9369c69b62d13b0a2406a544f40076b2f3d5dbac7e1` |
| UI LIB 1.6.0 `dist/uai-ui.lua` | 250,522 | `cfa2d24c9e1e8bf66b27023350dd74f43b3a056a61047375b27c6e4364fddae5` |

Local raw receipts are retained under the ignored `refer/native-verification/`,
`refer/bridge-verification-4.0.0/` and `refer/release-4.0.0/` directories. The native
report records `complete: true` and zero nonzero exits; desktop receipts identify
the executable hash above. Release assets include manifests, the executable
checksum and `SHA256SUMS` for independent download verification.

No in-game tests, screenshot capture or image viewing were performed. Synthetic
image protocol tests remain included. Offline mocks and Chromium do not establish
native Roblox rendering or input, executor compatibility, live inference quality,
server effects, anti-cheat coverage or ban avoidance.
