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

Use [HCNSEC](hcnsec.md) for personal keys. [Project UAI Free](projectuai-free.md)
uses its own community credential; the two access types never share a new setup
pool. Reselecting the same Free preset preserves an existing pause.

[Credential storage and exports](../API_KEY_SECURITY.md) · [All provider guides](README.md)
