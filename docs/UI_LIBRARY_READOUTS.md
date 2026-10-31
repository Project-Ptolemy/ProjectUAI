# Numeric fields and structured output

Use `NumberInput` for exact quantities that benefit from both typing and small
steps. It shares Input validation, draft, focus, commit and form APIs.

```lua
local quantity = section:NumberInput({
	Id = "quantity", Text = "Quantity", Min = 1, Max = 100, Step = 1, Default = 5,
})
```

Values round relative to Min, or zero when Min is omitted. Max remains reachable
when it is not a step boundary. `StepBy(-1)` and `StepBy(1)` start from the valid
draft; an invalid draft keeps the previous value and shows its error. Typed
changes commit on focus loss. `window:CommitInputs` includes these fields in an
atomic form submission. `Numeric`, `Live` and `MultiLine` are owned by this control.

`TextView` displays a selectable, read-only snapshot. It is useful for output,
review previews and logs. `Set(text)` replaces the snapshot; `Append(text)` adds
exact bytes and does not add a newline. Oversized replacements/appends fail
without changing the previous text. The default limit is 65,536 bytes; the
supported maximum is 262,144. `ScrollToEnd()` reveals the final content.

```lua
local output = section:TextView({ Id = "output", Text = "Output", Code = true, Lines = 5 })
output:Set("The scan has finished.")
local ok, message = output:Copy()
```

Copy returns `true` only when the available clipboard function accepts the
text. A refusal or missing capability returns `false, message`; show that
message through an application callout or notification. The field remains
selectable for manual copying. It never becomes editable when re-enabled.

`KeyValue` displays ordered `{ Key, Value }` records. Keys are unique strings;
values accept text, finite numbers and booleans and normalize to display strings.
Rows wrap into a stack on narrow screens. `SetValue(key, value)` updates an
existing row without reordering it; unknown keys fail. Supply a new complete
array through `Set` to change the keys. Arrays are copied on input and output.

Both readout controls are transient by default. Set `Persist = true` only when
the snapshot belongs in a user profile. Keep private or large output transient.
See the [control table](UI_LIBRARY.md#controls) and [workspace example](../ui-lib/examples/workspace.lua).
