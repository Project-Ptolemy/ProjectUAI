# Save named UI preferences

Use the [profile manager example](../ui-lib/examples/profiles.lua) for explicit
save, load and delete actions. File profiles store the controls and appearance of
one library window. They do not change the UAI client's providers or permissions.

| Action | Result |
| --- | --- |
| `SaveConfig(name)` | `true, path` or `false, error` |
| `LoadConfig(name, options?)` | `true, count` or `false, error` |
| `ListConfigs()` | `true, sortedNames` or `false, error` |
| `DeleteConfig(name)` | `true, existed` or `false, error` |

Names contain 1–48 letters, digits, underscores, or hyphens. The stable window Id
selects a window namespace under `ProjectUAI/UI/`; changing that Id creates a
different profile namespace. Deleting an absent profile succeeds with `existed`
false. Deletion leaves the current control values intact.

Mark profile picker controls and sensitive/transient fields `Persist = false`.
A profile picker should not change its own selected name while importing the
application preferences it manages. Require an explicit confirmation in the
consumer for profile deletion, as the example does.

Imports validate known controls and appearance before writing anything, ignore
removed controls, and reject incompatible control kinds. Restores are silent by
default. Call the model's Apply operation separately when restored controls
should take effect in your application.

If storage is unavailable, use `ExportConfig` and `ImportConfig` through the
host's own storage mechanism. The library does not auto-save or upload profiles.
An invalid required value blocks export; complete it or mark the field transient.
Configuration is limited to 256 KiB, so large notes and logs belong in domain
storage. A read-back mismatch means the host did not preserve the written bytes;
surface that error and keep the user's current state available for export.
