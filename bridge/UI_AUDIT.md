# Cowork UI audit — 1.9.0

September 26, 2026. Reviewed `web/style.css`, `web/index.html`, and the JavaScript
that creates or updates their controls. The baseline was commit `d79c7c7`.

## Findings and corrections

| Priority | Defect and reproduction | Correction |
| --- | --- | --- |
| High | Adding a pending question rebuilt every request card, erasing an unfinished answer, the Remember checkbox, text selection, and keyboard focus. | Keep cards by request ID and update their content without replacing active inputs. |
| High | An expired token during a dialog action showed the connection form behind the still-open modal. | Close the modal and focus the token field during authentication recovery. |
| High | A long task list or a draft with pictures, files, and multiple lines could push Send below the clipped workspace, particularly at 844×390 and 320×480. | Bound task and composer content, allow scrolling, and keep the composer toolbar separate from overflowing attachments. |
| Medium | Jump to latest used a fixed 175px offset, placing it over an expanded textarea or pending controls. | Position it within the transcript's own wrapper. |
| Medium | Long provider endpoints, model names, log URLs, and conversation titles produced horizontal overflow. Narrow model lists also compressed multiline button labels. | Wrap long content and dialog headings; prevent model rows from shrinking below their content height. |
| Medium | Every state update collapsed the expanded task list. | Retain its details element and open state while updating task contents. |
| Medium | Provider, runtime, and permission buttons stopped refreshing while focused. The open model picker kept its old selected model. | Refresh selected states while preserving control focus; defer panel replacement during editing, saving, selection, or an unfinished pointer action. |
| Medium | Save failures appeared in the page toast behind native dialogs. | Use a live status region inside the dialog and scroll its message into view without moving focus. |
| Medium | Free-form answers lacked a question-specific label and did not submit with Enter. Permission requests from other conversations looked local. | Associate answer inputs with their questions, submit through forms, and identify the request's conversation. |
| Medium | Navigation could leave focus on hidden or removed content. Selecting a conversation from another panel did not open Chat. | Focus the destination, open Chat after a successful conversation change, and focus replacement modal content. |
| Medium | Updating a picture or removing an attachment discarded focus from another removal/retry control. | Restore the same attachment control, the adjacent attachment, or the attachment button. |
| Medium | Muted light-theme text had only 3.96:1 contrast on the sidebar. Light code buttons hovered at 2.49:1 against a dark page. | Darken the light muted-text token and use a light-code-specific hover surface. |
| Medium | Forced-colors mode erased the Stop square and the textarea's focus treatment. | Add a system-color Stop border and explicit focus outlines. |
| Low | Failed setting saves retained green success text, and armed Clear retained its original accessible name. | Style status according to its state and expose the confirmation label. |
| Low | The model picker's checkbox stacked above its label; streaming paragraphs lost their normal spacing at the stable/tail boundary. | Set row direction explicitly and limit the last-paragraph rule to direct message children. |

## Coverage

- Source review of the full Bridge stylesheet, static HTML, dynamic markup,
  focus handling, themes, dialogs, pending requests, and attachment controls.
- Static ID, label/reference, local asset, and SVG symbol checks.
- Chromium layouts across all nine workspace views at 320, 390, 768, 1024,
  and 1440 CSS pixels, plus short portrait and landscape viewports.
- Full drafts, the supported 24-task limit, 60-character titles, long provider
  paths, long model lists, live state changes, rejected commands, and expired tokens.
- Light/dark themes, opposite code themes, reduced motion, forced colors,
  keyboard focus, and automated WCAG accessibility checks on representative views.
- Before/after screenshots and geometry checks, including individual controls
  inside panels whose document-level bounds would otherwise appear correct.

`tests/browser-ui-audit.js` retains the focused regressions. It is included in
`node bridge/tests/run.js --browser-only` and uses the same external Playwright
installation as the other browser suites. Screenshot output is optional through
`UAI_SCREENSHOTS`; audit tooling and screenshots are kept outside the repository.

Final verification passed:

| Check | Result |
| --- | --- |
| `node bridge/tests/run.js` | 55 tests passed |
| `node bridge/tests/run.js --browser-only` | All four browser suites passed |
| `luajit test/web_runtime.lua` | 22 checks passed |
| `luajit test/bridge_install.lua` | 70 checks passed |
| `luajit test/run.lua changelog "what's new" boot` | Four scenarios, 247 checks passed |
| `node tools/build_site.js --check` | Version 1.9.0 bundle and generated website synchronized |
| `python test/site_static.py` | 5,974 checks passed |
| Representative axe WCAG scans | No violations on the connection screen, welcome, pending questions, dark chat with light code, and dark settings |
| JavaScript syntax and `git diff --check` | Passed |

These checks use an isolated local bridge and synthetic game state. They do not
establish Safari/Firefox compatibility, native mobile safe-area or keyboard
behavior, or live Roblox executor behavior.

## Release numbering

The Cowork update had been committed under an unnumbered `Unreleased` heading
while the client and generated site still identified 1.8.0. It is now recorded
as **1.9.0 — September 26, 2026**, with matching bootstrap metadata, in-game release
notes, README, client bundle, and generated website. Historical 1.8.0 release
evidence retains its original version and date.

## Cowork UI rework — October 16, 2026

Appearance work follows `UI_REWORK_PLAN.md` and `bridgenewuirefer.png`. The chat
centers a rounded composer and compact suggestions on a white canvas. Workspace
navigation, panels, dialogs, and pairing share neutral ink and quiet hairlines.

| Finding | Correction |
| --- | --- |
| The empty screen separated the welcome and bottom composer with large suggestion cards. | Keep the heading, composer, and suggestion pills together; animate the composer into the conversation position. |
| Purple accents, dense frame lines, and boxed controls competed with the chat. | Introduce monochrome light/dark tokens, a paper sidebar, quieter topbar and rounded controls. |
| Live response tails displayed raw Markdown and rebuilt their content during growth. | Format live Markdown incrementally, preserve completed blocks and code controls, and animate arriving text only. |
| Thinking, writing, and completion had little visual distinction. | Add restrained activity dots, a thinking shimmer, a live caret, and explicit finished/error/stopped presentation. |
| History replay animated every restored message. | Suppress entrance animation on restored messages, reasoning and tool rows. |
| Response updates could disturb reading and selection. | Preserve stable blocks and defer updates to selected live text; reconcile the saved response after focus/selection leaves. |
| Pairing used a heavy split layout and dialogs had a large repeated support callout. | Center the pairing form on the canvas and make the dialog support link a quiet footer line. |

Source, CSS, HTML, documentation and test inputs are manually reviewed before
verification. Focused Chromium coverage includes the new composition, response
phases, real incremental text motion, stable reading/selection, replay suppression,
and reduced motion, alongside the existing browser regression suites.

Screenshots and local preview tooling are kept outside the repository. The
October 17 work below supersedes this presentation pass.

## Desktop workspace redesign — October 17, 2026

Reviewed all six images in `bridgerefer/`: the light centered composer, the dark
workspace and conversation navigation, the two-column settings dialog, and the
response-ordering problem. The dark palette now uses neutral charcoal; responses
have a clear assistant/model header, integrated thought disclosures, quieter tool
rows, readable code surfaces, and a compact Copy action.

Settings opens above the current conversation and retains the draft. General,
Appearance, Agent, MCP, Advanced, and Data sections keep their form elements while
changing sections; remote state updates do not replace an active edit or selection.
The dialog keeps Close and Done visible at short heights. Theme previews choose
Light, Dark, System, or Roblox. Browser reduced-motion preferences still apply.

MCP setup shows the local endpoint, tool availability, and connected harnesses.
Copy setup prompt gives an agent the exact detected command and arguments,
configuration-preserving setup instructions, and a read-only verification step.
Configuration formats cover Claude Desktop/Code, Cursor, VS Code/Copilot,
OpenCode, Codex, and Streamable HTTP. The displayed preview masks the bridge token;
manual connection copies deliberately include it; desktop stdio uses discovery
without embedding a token. The backend supplies the actual
stdio command and arguments, including the installed desktop executable when
available. Individual harnesses may impose their own tool deadlines.

Model rows, the selected composer model, and provider summaries use a rounded
green border and a textual Free label. The client's `freeModels` metadata is
authoritative; a personal paid model is not labelled free based on its provider
name. Release 4.1.1 removes community schedules and automatic free-routing probe
status from provider setup, model selection and Agent settings.

Model selection pairs searchable cards with a current-model detail panel showing
context/output limits and supported reasoning effort. Controls follow the native
client’s documented or manually configured effort metadata; unknown models do not
receive invented effort choices. Provider default leaves the preference unset.
The composer’s context ring opens a live breakdown for instructions/tools,
conversation, compacted history, remaining capacity, and the compaction threshold.
Calibrated, partial, and unknown-window estimates are presented explicitly.

The composer accepts queued follow-ups while an answer is running and keeps Stop
as a separate action. Pending messages are shown above the composer with Remove;
paused queues show the reason and Resume queue. Sending clears only the accepted
draft version, and queue changes preserve a newer draft. Queued text appears in
the transcript only when the client consumes it at a safe boundary.

The stylesheet has one definition per repeated selector within each conditional
block. Consolidation removed 142 overridden declarations, merged 100 duplicate
rules, and removed unused keyframes. Short declaration groups remain readable
without thousands of spacing-only lines. No CSS dependency is added to the app.

Focused browser verification uses `tests/browser-desktop-redesign.js`,
`tests/browser-visual-rework.js`, and the existing UI audit/revamp regressions.
These cover modal geometry at 320–1440 pixels, short screens, light/dark themes,
keyboard focus, retained edits, MCP configuration formats and token handling,
free-model metadata, live response phases, Markdown, selection, and replay order.
They exercise Chromium and synthetic loopback game state; native Roblox rendering
and installed third-party harness UIs require separate checks.

All secondary destinations now use a bounded workspace dialog: Connection,
Providers, Tools, Subagents, Chat loops, Memory & skills, and Activity. Chat stays
mounted underneath. The workspace has persistent navigation, a scrollable body,
connection status, and an explicit return to chat. Nested action/settings dialogs
retain their parent view and restore focus to the invoking control. The Connection
view gives current readiness a prominent summary and keeps token copy and setup
steps close together. The focused redesign suite checks every workspace at wide,
narrow, and short viewports, plus nested dismissal and draft retention.

Tool calls now start with a compact name, status, duration, and input preview.
Failures show a bounded, wrapped explanation in the summary. Opening a call
reveals separate Input and Result or Error details disclosures; source, full
errors, and structured result data keep their Copy actions. Successful text
results render Markdown with fenced-code Copy. Completion preserves an open
call, and restored calls with no saved outcome remain explicitly unknown.
`tests/browser-tool-cards.js` exercises these states, exact copied content,
replay, and narrow layouts; optional screenshots use `UAI_SCREENSHOTS`.
