# Build a form with an Apply action

Use `Input` validation for field rules and keep application rules in your model.
The [complete example](../ui-lib/examples/forms.lua) uses both a required name and
a whole-number limit. The [API guide](UI_LIBRARY.md#validated-forms) lists options.

1. Give every value a stable Id. Set `Required`, `Pattern`, or `Validate` for
   rules that one field can check independently. Validators return `true` or
   `false, message` and must be synchronous and free of side effects.
2. In Apply, call `window:CommitInputs({ Ids = { ... }, FocusInvalid = true })`.
   Failure shows field errors and leaves all committed values unchanged.
3. Read `GetValues` after success, check relationships between fields, then pass
   the complete value set to your model. A successful form commit does not imply
   that a server or application operation has succeeded.
4. Report the model's actual outcome. Keep fields editable after a rejection so
   the user can correct them.

`Get()` returns the committed value; `GetDraft()` returns unfinished text. A
non-live numeric field can therefore display `-` while keeping its previous
valid number. `CommitInputs` validates that draft before the Apply action reads
it. Hidden or disabled fields still participate when selected; restrict `Ids`
to the active part of a conditional form.

Bulk commits and `SetValues` are silent by default. Refresh derived labels or
conditional sections explicitly after reflecting a model snapshot. Opting into
`Silent = false` emits changed-value callbacks after the complete transaction;
it never presses a button or invokes Enter handlers.

`ResetValues` restores constructor defaults, including an intentionally blank
required field. Use `InspectValues` to show which fields changed without keeping
another copy of control state. If a dropdown's original default was removed,
reset fails before changing any selected control; supply a current model value
through `SetValues` instead.
