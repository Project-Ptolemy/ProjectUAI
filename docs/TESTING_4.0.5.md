# 4.0.5 verification

Release: **4.0.5**, November 15, 2026. Source, documentation, examples, tests and
build inputs were manually reviewed before building. Generated outputs were
inspected before verification; each fix received manual review before rebuilding
affected outputs or rerunning fixtures.

**Verification complete:** all 259 required native stages have passing command
receipts, retaining 253 passing stages from attempt 4 and completing its six
remaining checks after private Python reference setup. The original full command
retains exit 1 for its missing package import; no combined-command success is
claimed. Main coverage is 137 scenarios / 2,392 checks plus all 246 focused
suites. Desktop verification passed 154 checks and manual review of 11 previews.
Earlier receipts retain their actual tested builds.

## Reviewed artifacts

| Artifact | Identity | Size | SHA-256 |
| --- | --- | ---: | --- |
| Client, `dist/uai.lua` | `4.0.5-3c91fae36a064b18`, 338 modules | 4,666,694 bytes | `229617e9c3632a81f697665b592c6e11607ba81e752e96705d86bed1ab46c7f9` |
| Bridge package | 4.0.5, 24 files | 1,459,726 bytes | `6757e0401ff20a6a1ddb1b572d3368eeae4b9200f37b6dec379f6616aaee709e` |
| UI LIB, `dist/uai-ui.lua` | Unchanged 1.6.0 | 250,522 bytes | `cfa2d24c9e1e8bf66b27023350dd74f43b3a056a61047375b27c6e4364fddae5` |
| UI LIB manifest | Unchanged 1.6.0 | 4,629 bytes | `dc2e44a791c6d8263950a07aba5bcc4392432be21426f2b7e9d46cc10d29647c` |
| `desktop/release/UAI-Bridge-4.0.5-win-x64.exe` | 4.0.5; embeds current client | 67,640,195 bytes | `33df794d663174dd44cc19c608311f8016e1d26484731ab0c567edb61b7b563e` |
| Embedded desktop payload ZIP | 50 payload files, current client | 1,786,066 bytes | `04abc3ad45d7b74d8a15265e651957247504107075e15b95c993f1a90e95713e` |

The reviewed client header and `dist/uai.manifest.json` identify the new build;
the bridge identity agrees with `dist/bridge-release.json`. All 50 desktop payload
files (5,864,033 uncompressed bytes) match their reviewed inputs and inventory.
Inspection confirmed the exact ZIP embedded in the desktop assembly inside the
executable. Product/file versions are 4.0.5 / 4.0.5.0. The inspection receipt is
`desktop-after-keyboard/payload-inspection.json`. Previous desktop evidence in
`desktop-final-rebuilt/summary.json` tested client `4.0.5-328d5c58223e8c74`;
its earlier predecessor remains in `desktop-final/summary.json`. Both records
are preserved unchanged and retain their actual client identities.

The publication set follows the previous main release: client and UI LIB pairs,
bridge package/release-manifest pair, desktop executable/release manifest/sidecar,
and `SHA256SUMS`, which covers the nine packaged files. The checksum list was
generated from the inspected file bytes and manually reviewed. Bridge and desktop
updaters accept the unified `v4.0.5` tag; the actual shipped 4.0.0 bridge selector
was compared with current source. The bridge README was corrected to describe
that supported tag; it is excluded from all release builders and embedded guides,
so this documentation correction changes none of the verified artifact hashes.

## Verification outcomes

| Check | Recorded result | Local evidence under `refer/release-4.0.5/` |
| --- | --- | --- |
| `node tools/test_native.js --verify-only`, attempt 4 | 253 stages passed, including 137 main scenarios / 2,392 checks and all 246 focused suites; exit 1 at missing Python reference import before oracle execution | `native-final/attempt-4.command.json`, `attempt-4.results.json`, `attempt-4.workflow.log`, `attempt-4-stage-logs/` |
| Required native coverage after reference setup | Complete: 253 retained passing stages plus six exit-0 commands; 259 required stages, 246 focused suites; source/artifact identities unchanged | `native-final/verification-coverage.json`, `after-python-setup/results.json`, `command.json` |
| Independent credential crypto reference | Exit 0; 883 checks, including 219 authentication rejections | `native-final/after-python-setup/01-credential-crypto-interoperability.log` |
| Credential CPU benchmark | Exit 0; 100,000 iterations, 64-byte output, 29.286 seconds CPU; synthetic fixtures | `native-final/after-python-setup/02-credential-crypto-benchmark.log` |
| Official Luau compiler and three Node syntax checks | All exit 0; 379 exact compiler inputs, existing four exclusions | `native-final/after-python-setup/results.json`, `compiler-inputs.json` and respective logs |
| UI-library, bundle/catalog freshness and native static stages | All four exit 0 on current client; 335 parsed, 334 modules, 0 failures or warnings | First four receipts/logs in `native-final/attempt-4-stage-logs/` |
| `luajit test/provider_admission_ui.lua` after keyboard fix | Exit 0; 4 cases, 30 assertions, 0 failures | `native-final/admission-after-keyboard.log` |
| Supplementary official compiler, four source files | Exit 0; exact command and files retained | `native-final/official-native-exclusions.json` and matching `.log` |
| `node tools/build_bridge.js --check` | Exit 0; bridge 4.0.5 assets current, 24 files | `bridge-browser-final/bridge-freshness.output.log` |
| `node --test bridge/tests/streaming.test.js` | Exit 0; 30 passed, 0 failed | `bridge-browser-final/streaming.output.log` |
| `node bridge/tests/run.js` | Exit 0; 218 tests, 215 passed, 0 failed, 3 skipped | `bridge-browser-final/bridge-full.output.log` |
| Browser fixtures | All 15 have passing final fixture outcomes; both combined attempts remain exit 1 | `bridge-browser-final/SUMMARY.md` and final fixture logs |
| `python test/site_static.py` | Retained exit 0; 9,546 checks, v4.0.5, 209 tools / 28 groups, root/docs synchronized | `native-final/site-static.log` |
| `./desktop/build.ps1` with current client | Exit 0; script succeeded; outputs manually inspected before fixtures | `desktop-after-keyboard/build-command.json`, `build.log`, `payload-inspection.json` |
| `./desktop/verify.ps1` with current client | Exit 0 and script succeeded; five fixture processes, 154 checks, zero failures; 11 fresh WPF previews individually reviewed | `desktop-after-keyboard/summary.json`, `verify-command.json`, `verify.log`, five reports and 11 PNGs |
| Isolated native tail preflight | Exit 0; all 47 suites after shared UI layout passed, zero failures; current client identity checked | `native-final/tail-preflight/results.json`, `command.json`, `workflow.log` and per-suite logs |
| Independent offline performance benchmark | Exit 0; medians and bounds below | `performance/bench.log`, `results.json`, `summary.md` |

Current native coverage retains attempt 4's passing results and includes the six
remaining checks completed after reference setup. Failed full-command status is
preserved; no combined-command success is claimed. Earlier focused receipts remain
unchanged: Kilo and mods/mobile explicitly tested
`4.0.5-a9f9a56622961c6b`; `root-focused-final/results.json` records seven exit-0
commands without a build ID. Historical 4.0.0 regression labels are preserved.
Supplementary compiler files are `src/net/bridge.lua`, `src/net/bridge_commands.lua`,
`src/net/relay.lua` and `src/ui/panels/cowork.lua`; the retained command uses
`refer/native-tools/luau/luau-compile.exe --null` with those four paths.

The 30 streaming checks are included in the full bridge total. Its three skips
are optional standalone desktop MCP, optional official MCP SDK integration, and
the Unix-only symlink fixture. Overlapping focused/native evidence is not summed
into a single release assertion total.

## Kilo model discovery

New model-list defaults are `Accept: application/json` and
`Accept-Encoding: identity`, addressing wrappers that advertise Brotli without
decoding the returned body. A public read-only GET to
`https://api.kilo.ai/api/gateway/models` at **2026-11-15T12:28:24.732Z** returned
HTTP **200**, `application/json`, identity encoding, **621,550 bytes** and
**470 models** in valid JSON. An earlier Brotli comparison used approximately
69,816 wire bytes for the same catalog. The bounded receipt is `kilo/live-identity.log`.

The earlier six focused suites passed 134 cases / 2,142 assertions, zero failures,
on their explicitly recorded build above; details remain in `kilo/summary.md`.
They cover encoded/malformed JSON, HTML, route boundaries, custom header/auth
precedence, caching and picker ownership. No inference was submitted; no
credentials or raw response bodies were printed or retained by the public probe.
Real executor HTTP behavior and Roblox model-picker rendering remain unverified.

## Corrections and retained attempts

Initial native attempt 1 ended incomplete: 137 scenarios, 2,380 checks passed,
8 failed. Stale wording/whitespace/current-release expectations were corrected
while retaining independent permission/tool-contract assertions. The SCRIPT_UI
sentence `Read layout for GameName/ReducedMotion as needed.` was restored before
the preceding client rebuild; five prompt suites passed 497 checks. Receipts are
`native-final/attempt-1.results.json`, `attempt-1.main.log` and `prompt-fixes/`.

Attempt 2 passed 154 stages, including 137 main scenarios / 2,389 checks with
zero main failures, then stopped at stage 155: provider admission UI had one
genuine 4 px keyboard overflow. Its narrow-layout fixture uses a Windows touch
desktop profile with valid 44 px targets. `composer.lua` now budgets only optional
outer padding against available height, preserving the notice, typing field,
drafts, text and control targets. Reviewed release notes and runtime changelog
include the fix. The unchanged focused fixture now passes 4 cases / 30 assertions.
Archived evidence is `native-final/attempt-2.results.json`, `attempt-2.admission.log`
and `attempt-2.workflow.log`; the current native workflow was restarted afterward.

Attempt 3 passed 203 stages, including 137 main scenarios / 2,392 checks with
zero main failures, then stopped at stage 204 in `shared_ui_layout.lua`. Its
source-level phone fixture set touch capability without setting the new stable
`deviceMobile` identity, so it requested full desktop panel height. The reviewed
test-only correction explicitly sets handheld identity, rebuilds theme metrics,
and restores desktop identity afterward; all original assertions remain. The
focused fixture passes 210 checks, including both-axis dragging and resizing.
Client sources and generated artifacts are unchanged by this fixture correction.
Receipts are `native-final/attempt-3.results.json`, `attempt-3.main.log`,
`attempt-3.shared-ui-layout.log`, `attempt-3.workflow.log` and
`native-final/shared-ui-layout-after-identity.log`. All 204 stage logs from this
attempt are preserved together in `native-final/attempt-3-stage-logs/`.

Attempt 4 passed all 246 focused suites, the main suite (137 scenarios / 2,392
checks), the mock self-test and native performance contracts (9 cases / 30
assertions). Stage 254 stopped at Python's `cryptography` import, before any
reference oracle cases ran. The original full command and report remain exit 1
and `complete: false`. Private Python 3.13.15 with pinned `cryptography` 50.0.2,
`cffi` 2.1.1 and `pycparser` 3.12 supplied the independent reference. All six
remaining defined checks passed: interoperability, the CPU benchmark, official
compiler and three script syntax checks. The aggregate receipt records each
actual command and source log. Package pins, wheel hashes and interpreter identity
are retained in `native-final/after-python-setup/setup-results.json`,
`requirements.lock.txt`, `resolution.json` and `installation.json`. Retained passing
stages are unaffected by this test-only environment change. Exact failed-attempt
receipts and all 254 logs remain in `native-final/attempt-4-stage-logs/` and the
adjacent `attempt-4.*` records. No required stage is skipped.

The isolated tail preflight's initial helper stopped before running a suite:
its inventory guard compared the discovered native order with a manually listed
order. A reviewed helper correction derives exclusions and priority order from
`tools/test_native.js`; the actual 47 tail suites all passed. The initial refusal
remains in `native-final/tail-preflight/inventory-guard.command.json`,
`inventory-guard.workflow.log` and `run.inventory-guard.js`. This preflight is
separate from the full native workflow, and overlapping counts are not added.

The first Kilo run had a fixture setup failure: `timeout=0.1` normalized to the
supported one-second minimum while the fixture waited 0.2 seconds. A reviewed
test-only change supplies explicit `deadlineMs` 100 ms ahead of its clock; its
original log remains `kilo/kilo_models.initial-failure.log`.

Both combined browser commands exited 1. The first sampled sliced replay early
(198/320 entries after 180 ms); its fixture now waits for `aria-busy` completion
and 320 entries before unchanged anchor/count assertions. The second passed nine
fixtures then failed a recovery result missing the call's `name="inspect"`.
Reviewed payload corrections preserve the same name and exact IDs. The corrected
conversation fixture and remaining five fixtures subsequently exited 0; all 15
final fixture outcomes pass. Both failed command receipts remain preserved.

Browser recovery covers bounded slices, Stop, hidden overflow, durable ordering,
stale SSE callbacks, lazy reasoning and personas. Two actual loopback jobs have
full 4,096-frame rings plus a 400-event backlog; fresh recovery shares a
4,096-delta / 7 MiB budget across up to 32 running/recent uncommitted jobs,
prioritizes running jobs, reports gaps/terminal outcomes and retains exact
receipts using one fresh stream without resubmitting inference. Details and
screenshots are in `bridge-browser-final/`. External Playwright 1.64.1 and already
installed Chromium 1248 were reused; no repository tooling was installed.

The previous desktop report passed 154 checks across five exit-0 fixture
processes and reviewed 11 fresh WPF previews without unintended clipping/overlap.
Its verification script completed normally; the capture wrapper returned 1 after
comparing unset `$LASTEXITCODE` following `Start-Process`. That recording issue
remains separate from fixture success and belongs to the previous embedded
client. Final desktop build and verification captures now record immediate
PowerShell script success after direct invocation and both exited 0. The current
executable passed 88 self-test, 9 startup, 6 smoke, 12 window and 39 update checks,
154 total with zero failures. All 11 fresh previews were individually inspected
for readable controls, wrapping, scrolling and unintended clipping/overlap; all
also match the prior screenshots byte for byte. The executable and reviewed
client hashes stayed unchanged during verification. Evidence is in
`desktop-after-keyboard/summary.json` and its referenced files.

## Long-context measurements

Frozen actual context, UTF-8 repair and Markdown modules were compared with
baseline commit `a39bb80cd3a6a05594933a932bc7420b7eaf7efc`, using identical synthetic
data and unchanged mocks. Reviewed `performance/bench.lua` exited 0; snapshots,
hashes, output and measurements remain in `performance/snapshots.json`, `bench.log`
and `results.json`. Each timing is the median of three trials on Windows LuaJIT
with mock HttpService. Timing is separate from instrumentation; modules/fixtures
are loaded, context already calibrated, and immutable UTF-8 entries warmed.

| Workload | Work per timing | Baseline | Current | Baseline/current |
| --- | --- | ---: | ---: | ---: |
| 250,400-token prose context | 500 refreshes | 74 ms | 46 ms | 1.61x |
| 266,450-token immutable string-argument tool history | 80 refreshes | 109 ms | 63 ms | 1.73x |
| Same history with mutable argument tables | 3 refreshes | 2,866 ms | 1,233 ms | 2.32x |
| 1,053,694-byte Unicode JSON | 8 encodes | 1,201 ms | 626 ms | 1.92x |
| 100 ordinary 10,000-byte Markdown paragraphs | 1 full pass | 1,537 ms | 492 ms | 3.12x |

A refresh is breakdown + pressure + stats. Prose has 100 messages; tool corpora
have 625 messages, 500 calls and 500 paired results. Token totals/output lengths
match, and each implementation's output bytes remain stable across repetitions.
Mutable graphs still need re-estimation; `estimateText` already uses string length.
The shared text cache caps at 256 entries / 4 MiB, skips strings below 256 bytes
or entries accounting for over 2 MiB, and clears on unload. Observed retention was
256 strings / 507,648 source bytes for mutable tools and 100 strings / 1,155,590
accounted bytes for Unicode. Context metadata tracks current history, rebuilds
after removal/replacement and clears with `ctx.clear`. Cold UTF-8 validation,
table walks/full JSON writes, detached-history estimates and proportional metadata
refresh work remain. These are warmed local preprocessing measurements.

## Verification limits

Offline/Chromium fixtures exercise contracts and approximate layout. WPF fixtures
exercise native desktop rendering/processes with simulated bridge/game state.
Native Roblox rendering, executor input/HTTP, provider/persona quality, upload,
model prefill/generation and end-to-end inference performance remain unverified.
Studio MCP returned no connected instances at 2026-11-15T14:19:19Z, so a native
Roblox place/play check could not be performed; the read-only availability
receipt is `native-final/studio-availability.json`.
No live inference was submitted for catalog, loopback recovery or benchmarks.
The desktop executable is unsigned. This record covers the artifacts and checks
completed before publication.
