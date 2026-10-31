# Settings and native input

The Settings dialog and stacked Settings panel share **Find a setting**. Search
uses public labels, category names, config paths and keywords. It never indexes
saved values, passwords, provider keys or text currently entered in a field.
Each word must match. Results rank exact labels first and show at most 30 matches;
the count explains when additional matches exist. Enter opens the first result.

Choosing a result opens its category and scrolls to the setting. Clear returns to
the previous view. Searching and changing categories preserve existing text
fields and unfinished drafts. An external configuration change can still rebuild
a stale category under the established draft-validation rules.

Focused sliders accept Left/Right and controller D-pad Left/Right. Each press
advances one allowed step and commits it once. Home/End choose the endpoints;
Page Up/Page Down move ten steps. Up/Down remain available for navigation. These
shortcuts do not change sliders while a text field owns focus. Disabled controls
ignore activation. Hiding the main window releases its text and gamepad focus
while preserving the draft.

Quick Chat preserves its text selection through appearance rebuilds and keeps a
rejected message for correction. Password setup uses Enter to move from the first
password to confirmation. Show/Hide retains the caret and selection; leaving the
application masks a revealed password again.

**What's new** can search release notes and copy the latest release independently
of the active search. **Copy invite** selects the visible invite for manual copy
when the executor clipboard fails. A timeout notice links to the request-wait
setting and retains the Discord help action. Review completed actions before
retrying an uncertain request; changing a client timeout cannot remove host limits.

Focused offline checks are `test/settings_search.lua`, `test/native_controls.lua`,
`test/native_utility_ui.lua`, and the existing `test/deadline_help.lua`. Follow the
repository's review, build, output inspection and verification order. Native
Roblox keyboard, controller, IME and renderer behavior still needs device checks.
