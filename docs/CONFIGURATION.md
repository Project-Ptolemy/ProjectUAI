# Settings, passwords and transfers

Open Settings from the sidebar/profile menu or press **Ctrl+,** while not typing.
Use **Find a command** to locate a setting by its purpose, such as `text size`,
`reasoning effort`, `password` or `bridge`.

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

Empty imports and resets leave the provider library ready for your choice; they
do not silently install Project UAI Free. Personal HCNSEC and optional Free records
remain separate. See [provider setup](providers/README.md).

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
