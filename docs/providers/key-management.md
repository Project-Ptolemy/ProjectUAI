# Manage provider keys

Open **Manage API keys** from provider setup or a saved provider. Every entry
stays masked and can have a private name. Paste one key per line to add several
entries; duplicate keys are kept only once. Replacing or removing one entry
retains the others and their accounting history.

Search the manager by key name or `active` / `paused`. It accepts multiple words
and filters existing rows without replacing the focused field. Credential
contents are not searchable. Browser setup can replace a pasted key pool while
retaining the names, pause states and accounting identities of exact surviving
keys; removing a pinned key returns the connection to rotation.

**Rotate keys** shares future requests across active keys. **Use one key** pins
requests and model discovery to the selected entry. A quota refusal does not
switch another key into a pinned request. Provider fallback is a separate setting.

The connection editor's **Requests per minute** cap applies to the whole provider,
including every key in its pool. Rotation does not give each key a separate
allowance. `0` adds no provider cap; for example, `10` permits ten inference
attempts per rolling minute. Retries and key/protocol switches count. The shared
[global request cap](../CONFIGURATION.md#limit-requests-per-minute) applies too,
and Stop cancels while waiting for capacity.

Pause temporarily excludes a key without deleting it. A paused selected key, or
an entirely paused pool, prevents new requests and explains how to resume.
Pausing does not cancel a request already accepted. Removing the selected entry
returns to rotation; removing an earlier entry adjusts the selected position.

The manager has its own draft. **Apply** returns changes to the provider setup
draft, where **Save** persists them. When opened directly from a saved provider,
Apply saves to that connection. Cancel or Escape discards unapplied manager edits.

Names, pause flags and accounting IDs remain aligned after replacements and
removal. Replacing a credential creates a new accounting identity. Renaming it
retains both usage history and the current discovery cache.

OpenCode Zen can supply public authentication for an empty-key standard Chat
connection after fresh official metadata verifies zero prices in every tier.
UAI does not save that token as a personal key. Personal keys take precedence;
paused or pinned pools and imported credential guards cannot fall back to public
access. See [model discovery](model-discovery.md) for pending verification.

Release 4.1.1 removes retired community credentials during
[provider migration](migration.md). Surviving personal keys retain their labels,
pause states and accounting identities.

[Credential storage and exports](../API_KEY_SECURITY.md) · [All provider guides](README.md)
