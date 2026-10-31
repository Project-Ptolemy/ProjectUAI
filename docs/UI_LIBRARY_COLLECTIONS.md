# Lists, action groups and callouts

`ItemList` is an inline, searchable list for a bounded collection. Each item has
a stable `Id`, a `Text` label, optional `Description`, and optional `Disabled`.
The library displays one page at a time and supplies Previous/Next controls.

```lua
local tasks = section:ItemList({
	Id = "tasks", Text = "Tasks", PageSize = 6,
	Items = {
		{ Id = "lighting", Text = "Review lighting", Description = "Check the interior lights." },
		{ Id = "paths", Text = "Review paths" },
	},
	Callback = function(id) selectedTask = id end,
})
```

Selection is an item Id; `""` means none. Construction and profile import do not
activate items. Disabled rows cannot be selected interactively. `SetItems`
validates a complete replacement before changing anything, keeps matching
selection, and clears a removed selection silently by default. Pass false as
its second argument to emit that clearing change. Removed defaults become empty.
`GetItems` returns a copy. `SetQuery` accepts at most 256 bytes and returns to
page one. `GetPage` returns current page, total pages, and matching item count.
Use up to 500 items and 1–20 rows per page; for larger remote data, supply your
own domain paging through list replacements and explicit actions.

`ActionGroup` groups 1–8 named actions. Each action declares `Id`, `Text`,
`Callback`, optional `Style = "Primary" / "Danger"`, and optional `Disabled`.
`Press(id)` ignores a disabled or already-running action. Different actions can
run independently; each callback belongs to the control's scope. Destroying the
control cancels owned scheduled work. Do not use separate actions concurrently
when your application cannot safely process them; disable them explicitly.
`SetActionEnabled` and `SetActionText` retain their stable identity and layout.

`Callout` presents a message with Info, Success, Warning or Danger tone. Use
`SetKind` and `SetContent` as state changes. Optional `ActionText` and `Callback`
add one owned action, such as Retry. Action labels are always text. Neither
callouts nor action groups add values to saved profiles.

The [workspace example](../ui-lib/examples/workspace.lua) combines these controls
with a read-only preview and numeric editor. All layout, focus treatment,
spacing, colors and cleanup remain inside the library.
