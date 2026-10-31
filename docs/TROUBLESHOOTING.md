# Troubleshooting

Start with the visible error and the last observed outcome. A timeout means a
response was not received in time; it does not prove that an external effect never
occurred. Check the result before repeating an action with side effects.

| Problem | Next step |
| --- | --- |
| No provider is configured | Open Providers and add a preset. Free is optional and HCNSEC requires your own key. |
| Free is outside its access hours | Return during 20:00–12:00 UTC+8 or choose another provider. Existing accepted replies are allowed to finish. |
| Model list is empty | Check URL/authentication, then fetch again or enter an exact supported model ID. |
| All API keys are paused | Open Manage API keys and activate an entry, or change the selected single key. |
| Unauthorized response | Check the account/key at its provider and confirm the preset and endpoint. |
| Quota/rate-limit response | Inspect the provider's allowance; a different personal key may have a different quota. |
| Request times out on a phone executor | Follow the current [relay guide](MOBILE_COMPANION.md); do not infer success or safely replay an unknown outcome. |
| Tool unavailable or denied | Check its capability requirements, group, session scope and effective permission rule in Tools. |
| A text field ignores a shortcut | Release focus first; global shortcuts deliberately preserve typing. |
| Search omits a known conversation | Search loads retained current conversations; older saved files can remain archived on disk. |
| Export cannot save | Check filesystem support and the returned verification error. Copy Markdown if clipboard access is available. |
| Vault password is rejected | Use the original password; reset discards saved credentials and cannot recover them. |
| Obsidian is unavailable | Connect the desktop bridge, configure a vault, and check the read/write policy. See [Obsidian](OBSIDIAN.md). |
| A note changed during editing | Read the latest note and merge your changes before retrying with its new revision. |
| The loader keeps the old client | Finish active/unsaved work that would be lost during replacement, then run the updated loader again. |

## Gather useful evidence

Open **Logs**, select the relevant request and note the provider, status, transport,
duration and bounded error. A provider response and a local transport failure need
different fixes. [Diagnostics](DIAGNOSTICS.md) explains searching and copying a
focused report. Include your client/build version and executor when asking for help.

Review copied material before sharing it. Do not post passwords, private API keys,
bridge tokens, private configuration exports or personal note contents.

## Recover the interface

Try **Refresh conversation** for a stale view. Reopen a panel or use **Find a command**
to navigate without deleting its data. For a clean shutdown, choose **Unload UAI**;
destroying the ScreenGui alone leaves runtime work alive.

Native Roblox rendering, IME, touch and executor continuations require checks on
the affected device. An offline mock passing does not rule out a host-specific issue.
[Discord support](https://discord.gg/9xYyyYuKap) can help narrow it down.
