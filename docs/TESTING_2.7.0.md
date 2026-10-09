# Project UAI 2.7.0 verification

Release date: October 9, 2026. These checks cover this release's changes. They do
not invoke the full native suite, a browser, image previews, live models or paid
inference. Offline fixtures cannot establish native Roblox rendering, executor
Unicode support or real provider latency.

## Review and build

Review changed source, documentation and tests first. Build with
`luajit tools/bundle.lua --native`, then `node tools/build_site.js`. Inspect
`dist/uai.lua`, its manifest, and the generated root/docs site changes before
verification. Review each fix before rebuilding and rerunning affected checks.

## Focused offline checks

Run sequentially and inspect each result:

```text
luajit test/workspace_paths.lua
luajit test/tool_workflows.lua
luajit test/code_workspace.lua
luajit test/agent_efficiency.lua
luajit test/provider_output_budget.lua
luajit test/provider_transport.lua
luajit test/reasoning_display.lua
luajit test/model_effort.lua
luajit test/access_defaults.lua
luajit test/chat_stability.lua
luajit test/mobile_reading.lua
luajit test/project_support.lua
luajit test/run.lua --native "the composer states what is actually in force"
luajit test/run.lua --native "effort reads as a scale rather than a number"
luajit test/check.lua --native
luajit tools/bundle.lua --native --check
node tools/build_site.js --check
```

Use the official Luau compiler on the changed Lua sources, `init.lua` and the
finished bundle with `--null`. Do not substitute the all-suite verification runner
for these focused checks. The two `test/run.lua` commands above each select exactly
one named scenario; neither invokes the full suite.

## Recorded offline results

Built artifact: [`dist/uai.lua`](../dist/uai.lua), build
`2.7.0-b205fea716f3a534`, 3,130,474 bytes.
SHA-256: `f0e2155e5f80aef1347cad201cc92594dcf24c2485df747b82194eeae9ae5219`.

Verified October 9, 2026: **12 focused suites and two individually selected
scenarios, 1,760 assertions/checks, zero failures**. Counts exclude superseded runs.
The follow-up pass ran 630 checks covering access, model controls, folder discovery,
reasoning previews and chat stability. Unaffected suites were not rerun.
A new transport fixture initially
supplied an incomplete health record; it was corrected and reviewed before the
transport suite was rerun. A new preview fixture was corrected to wait for its
virtual row to mount before reading its text. Each correction was reviewed before
the affected check was rerun.

| Suite | Assertions/checks |
| --- | ---: |
| Workspace paths | 211 |
| Tool workflows | 375 |
| Code workspace | 74 |
| Agent efficiency | 32 |
| Provider output budget | 43 |
| Provider transport | 554 |
| Reasoning display | 34 |
| Model effort | 35 |
| Access defaults | 16 |
| Chat stability | 313 |
| Mobile reading | 9 |
| Project support | 43 |
| Composer active-mode scenario only | 12 |
| Effort settings scenario only | 9 |

Native static verification passed for 193 files with zero warnings; the eight
modules touched in the follow-up passed again. The official Luau compiler accepted
the changed sources/tests and bundle, including all 14 follow-up compilation targets.
Bundle/manifest/icon freshness and root/docs website synchronization checks passed.
The reasoning fixture verifies zero Markdown calls during 20 folded updates,
one formatting pass on opening, reuse on reopening, literal-text fallback on
formatter failure, and recovery on later content.

## Features to test in Roblox

1. **Release and navigation.** Reload the built client while idle. Confirm 2.7.0
   in About and What's New. Open the sidebar profile menu: ProjectUAI should have
   the brand mark. Open its modal and confirm the same mark, repository action,
   copy action and close action. Reopen it on a narrow screen.
2. **One filesystem path.** Ask the agent to create `path-check.lua` in the current
   game folder containing `return 27`. Have it list, search, read, edit to `return
   28`, compile and run the file by the exact returned path. No new extra `files/`
   directory should appear. Remove only this disposable file afterward.
3. **Game-folder compatibility.** In a game with emoji in its name, new automatic
   folders should have ASCII names and the PlaceId. Verify existing accessible
   Unicode folders and real nested `files/files/...` paths still work. An
   inaccessible old folder must remain untouched; warnings must not claim its
   contents are empty or successfully migrated.
4. **Response effort.** On an existing install, choose Agent → Effort → Low and
   compare a routine request with your previous setting on the same model. Confirm
   the setting survives reload. Try Provider default, then return to Low. An
   unsupported model may ignore effort; buffered HTTP still waits for delivery.
   In Models, enable Options → Reasoning support for a non-Anthropic model.
   Confirm effort controls appear immediately, share Agent settings, survive reload,
   and include Provider default. Change models and verify the global preference stays.
5. **Thinking display.** Expand a short trace: its estimate says tokens shown.
   A long retained trace should say Excerpt. Collapse/reopen it, switch chats and
   refresh the conversation. The excerpt label and retained content should agree;
   the final answer and tool results must remain intact.
   A long answer preview must not label short reasoning as an excerpt, or vice versa.
6. **Responsiveness.** Leave thinking folded during several tool steps. Open it
   afterward and check the latest text. Repeat with thinking expanded, scroll back,
   minimize/restore, and open the mobile keyboard. New output must not steal your
   reading position or hide controls. The offline formatter-failure fixture also
   checks that raw reasoning stays readable and later updates can recover.
7. **Failure feedback.** When a test endpoint returns an explicit stream error,
   confirm the actual bounded reason appears rather than a generic empty response.
   A partial response followed by an error must not run tools or dispatch a second
   request. Use the offline fixture for this check if no test endpoint is available.
8. **Default access.** With a fresh configuration, confirm Allow everything in
   the composer and Permissions settings. An existing saved Ask first, Read only,
   or Auto choice must survive reload, along with any explicit per-tool rules.

UI LIB 1.3.0 and embedding SDK 1.0.0 remain unchanged in this release.
