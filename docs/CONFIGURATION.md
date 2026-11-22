# Settings, passwords and transfers

Open Settings from the sidebar/profile menu or press **Ctrl+,** while not typing.
Use **Find a command** to locate a setting by its purpose, such as `text size`,
`reasoning effort`, `password` or `bridge`.

## Limit requests per minute

In **Behaviour > Model requests**, set **Requests per minute** to `1` or `2` to
pace all inference attempts in this UAI run. `0` removes the global cap. Each
provider's connection editor has its own **Requests per minute** setting; `0`
adds no provider cap, while `10` caps that provider's entire key pool at ten
attempts per rolling minute.

| Setting | Saved field | `0` means |
| --- | --- | --- |
| Shared requests per minute | `agent.requestsPerMinute` | Unlimited globally |
| Provider requests per minute | Provider record `requestsPerMinute` | No additional provider cap |

Both fields accept whole numbers from `0` through `1000000`. The caps apply
independently: a global cap of `2` still limits all providers combined to two
attempts, even when a provider allows `10`. Increasing either cap does not
override the other.

Inference transport attempts count, including retries, key switches and protocol
recovery. Conversations and subagents share the global cap. Model discovery and
relay polling do not consume it. UAI waits for capacity before dispatching another
attempt and shows **Waiting for request rate limit**, including during context
compaction. **Stop** cancels a pending conversation wait; earlier attempts stay
counted. The native setup test shows **Waiting for limit**; closing provider setup
cancels it. Browser provider cards show the waiting state and offer **Cancel test**
independently of the active conversation. Waiting remains subject to the caller's
existing deadline.

The caps count dispatches from this UAI runtime. Starting a fresh runtime resets
the history; reusing the same running build retains its current minute.
One accepted bridge or companion inference job counts once; same-ID receipt
recovery and result polling add no dispatch. Upstream recovery inside the local
app, including Kilo tunnel/circuit recovery and installed CLI retries, stays
within that job and is outside the client's counter. Provider and account quotas
remain with the upstream service.

## Read release notes

**What's new** opens once for each new client release after startup and the saved
credential-storage choice or password unlock completes. A hidden embedding defers
the notice until its normal window is explicitly shown. Closing the notice keeps
it closed on later executions of that version, including build replacements.

Open **What's new** from the profile menu to read the notes again. Revisions to
notes within the same version can restore the menu's unread indicator without
automatically opening another notice.

## Choose credential protection

Password protection encrypts provider keys and protected connection fields using
the bundled credential vault. It requires your password on every execution.
There is no password recovery; resetting a forgotten vault discards its saved keys.

**Continue without encryption** is an explicit saved choice. It stores keys with
reversible encoding, leaves them unprotected, and skips future password prompts.
Privacy can enable protection later. An existing encrypted vault must first be
unlocked or deliberately reset before switching storage modes.

Password encryption does not encrypt conversation files, exported Markdown or
workspace scripts. Executor scripts with equivalent access can observe live inputs
and credentials. See [API key security](API_KEY_SECURITY.md) for the exact boundary.

## Transfer settings

In **Import & export**, the ordinary copy excludes provider and connection credentials.
Use the separately labelled private copy only when transferring those fields.
Private copies retain vault encryption when enabled; unprotected copies remain
recoverable. Neither kind is a backup of conversations or workspace files.

On the receiving device, paste the JSON, select **Review**, enter the source vault
password when required, inspect the summary, and **Apply**. Import retains the
receiving device's storage choice and password. A copy without credentials requires
you to re-enter them. Memory and other personal settings may still need review
before sharing an otherwise credential-free copy.

Empty imports and resets leave the provider library ready for your choice.
Release 4.1.1 filters retired community access from older copies and preserves
personal connections through [provider migration](providers/migration.md).
See [provider setup](providers/README.md).

## Know what is saved

| Location under the executor's UAI folder | Contents |
| --- | --- |
| `config.json` | Settings, provider records, permissions and saved memory |
| `sessions/` | Saved conversations and folder catalogs |
| `stats.json` | Recorded usage statistics |
| `files/` | Scripts and other agent workspace files |
| `pastes/` | Large message attachments |
| `export/` | Explicit configuration and conversation exports |

The [bridge](../bridge/README.md) manages local desktop vault paths separately from
executor storage. A configuration transfer is not an Obsidian backup. Keep backups
of important files using your normal filesystem tools, especially before deleting
or moving an executor's workspace.
