# Project UAI 4.1.1 verification

November 22, 2026. Client, bridge package and Windows desktop target **4.1.1**;
UI LIB remains **1.6.0**, embedding SDK **1.1.0**, Android companion **3.7.2**.

Review order: manually audit source, documentation, examples, tests and build
inputs; build the standalone UI reference, native client, site and bridge;
inspect generated outputs; run focused regressions and the broader native,
bridge/browser and desktop checks. Each fix is reviewed before rebuilding and
retesting its affected paths.

Required behavior includes removal of the two retired provider presets and every
reversible community credential, idempotent load/save/replace/import migration,
preservation of personal keys and metadata, authenticated vault recovery,
valid provider selection after filtering, and retained drafts when no provider
remains. Remaining free routes and generic provider/key controls must continue
to work. OpenCode validation covers current upstream behavior, scoped direct
compatibility, native CLI URL semantics, tool/result replay, authentication,
refusals, deadlines and cancellation.

## Client verification

The final reviewed client is **4.1.1-9a812a3a479ea453**. Its 339 manifest source
ranges and bootstrap match the normalized authored inputs. The broad native plan
passed 110 stages before the final single-attempt companion-policy correction.
The complete 262-stage plan was not completed. After that correction, mobile
deadline and request-rate suites, the native checker and official Luau compiler
passed on the final build. Original checkpoints and per-stage logs are retained
under `refer/native-verification`.

| Check | Result |
| --- | --- |
| Broad native verification plan | 110 stages passed; complete 262-stage plan not completed |
| Main native suite | 137 scenarios, 2,402 checks; zero failures |
| Native static checker | 336 files parsed, 335 modules; zero failures or warnings |
| Final official Luau compiler | All 380 source, example and bundle files compiled |
| Final mobile companion deadlines | 15 cases, 54 assertions; zero failures |
| Request-rate core | 22 cases, 80 assertions; zero failures |
| Request-rate UI | 5 cases, 22 assertions; zero failures |
| Zen direct public dispatch | 22 cases, 312 assertions; zero failures |
| Once-per-release changelog | 7 cases, 37 assertions; zero failures |
| Provider test ownership and cancellation | 8 cases, 28 assertions; zero failures |
| Synthetic provider retirement | 10 cases, 51 assertions; zero failures |

The request tests cover global/provider caps, low integer values, concurrency,
FIFO admission, changing limits, cancellation, original deadlines, retries,
socket sends and uncounted discovery/polling. The changelog tests include hidden
startup, credential setup/unlock, manual viewing, cold restart, same-build reuse,
changed-build handoff and revision-only updates.

Historical verification reconstructed both retired credentials only in memory.
Four real historical migrations passed 76 assertions. The scan covered 1,162
files, 84 archive entries and 24 decoded entries, including the final desktop
payload, ZIP and executable: zero historical credentials or reversible key arrays.
The designated test-key scan covered 1,161 files and 75 decoded entries with zero
occurrences. The key is absent from the committed source and release assets.

## Bridge, browser and platform verification

| Check | Result |
| --- | --- |
| Bridge Node suites | 218 passed, zero failed, three initial skips |
| Final standalone desktop MCP test | 1 passed, zero failed or skipped |
| Official MCP SDK 1.32.2 integration | 3 passed, zero failed or skipped |
| Cowork Chromium suites | All 15 passed; changed screens and responsive screenshots reviewed |
| Public site static checks | 9,548 passed |
| Public site Chromium checks | Passed layout, focus, catalog, copy/fallback, animation and no-JavaScript checks |
| Windows `desktop/verify.ps1` | 154 checks passed on the preceding payload across self-test, startup, smoke, window and update modes |
| Final Windows payload checks | 88 self-test and 9 startup checks passed after the last client rebuild |
| Native WPF screenshots | All 11 reviewed; normal, compact, narrow and lower scroll content |
| Companion packaging and freshness | 10 packaging tests passed; package freshness passed |
| Android debug and signed release builds | Succeeded; production APK bytes and pinned signer verified |
| Android JVM verification task | Up-to-date; existing reports contain 92 passing tests in 12 suites |
| Android release lint | Executed: zero errors, 35 warnings |

The optional desktop and SDK checks resolve two initial bridge skips. The Unix
symlink case remains unexecuted on Windows. The Android JVM task did not freshly
rerun its 92 tests. No Android device or live Roblox executor was available.

## Reviewed artifacts and direct API observations

The UI LIB, native client, website, bridge package, Windows executable and Android
debug/release targets were built after input review. UI LIB remains 1.6.0; its
standalone bundle, manifest and embedded reference are unchanged. The website
contains 209 tools in 28 groups and its root/docs publishing copies match.
The bridge package contains 24 files and 1,468,306 bytes of decoded content.

The Windows payload contains 50 matching client, bridge, browser and license
files in 51 canonical ZIP entries. Every inventory and archive hash was checked;
the executable embeds the reviewed payload and runs without neighboring files.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `uai.lua` | 4,691,390 | `46e632fd08419960cd4ed88d18420ea1f489b367de5513a38a1ef8da4f0ea9ad` |
| `UAI-Bridge-4.1.1-win-x64.exe` | 67,647,875 | `ae20874631623f67cbee51d541857492ba6f72f0dc954b32868f5ad98ab3c1f3` |
| `UAI-Relay-3.7.2.apk` | 39,830,600 | `8abcf28ee18eddddc7da632a81c8c63c8d43e44c86db779c78158f36965c2a55` |

The independently versioned Android rebuild matches the existing production APK
byte for byte. Release assets retain those production bytes and include the
manifests, adjacent checksums and aggregate `SHA256SUMS.txt`.

Standalone direct HTTPS checks used both the designated key and public
authentication for all eleven current free Chat models. Text, tool calls and
synthetic result replay were checked per model without a bridge, relay or CLI.
The exact observations, Iceman batch behavior, Flint text mismatch and later
public quota refusal are retained in the [Zen model matrix](OPENCODE_4_1_1_VALIDATION.md).

Synthetic fixtures and Chromium previews do not establish native Roblox rendering
or host input. Live observations apply to their recorded route and date. Executor
HTTP and Android have their own TLS stacks; the direct HTTPS matrix does not
certify every model on every device or guarantee future free allowance.
