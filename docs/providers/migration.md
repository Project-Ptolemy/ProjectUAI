# Provider upgrades and retired community access

Release **4.1.1** removes Project UAI Free and the HCNSEC preset from the provider
library. The client no longer contains a community credential, restores shared
access, checks community hours, or performs automatic free-routing probes.
Other hosted, free and local providers remain available.

Migration runs on configuration load, replacement and import. It performs no
model discovery or inference. Empty setups stay empty; the client never adds a
replacement service or supplies a new key.

| Saved connection | Result in 4.1.1 |
| --- | --- |
| Community-only Project UAI Free or legacy HCNSEC access | Removed |
| Saved community credential reference | Removed without restoring a key |
| Personal HCNSEC account | Becomes Custom endpoint with its personal configuration retained |
| Mixed community and personal key pool | Community credentials removed; surviving personal entries and metadata retained |
| Other provider or custom endpoint | Retained; recognized retired community credentials are stripped |

Personal connections keep their provider IDs, custom names, endpoint, protocol,
model, enabled state and order. A preset's default name becomes Custom endpoint.
Surviving keys keep their names, pause states and accounting IDs. When a pinned
community key is removed, the connection requires a reviewed Save before using
the remaining personal keys. Otherwise a surviving key remains selected, with
its pool index updated, and existing rotation remains in effect. Active selection,
fallback references and model shortcuts are reconciled after removed providers.

Edited legacy endpoints or nonstandard authentication maps remain as guarded
Custom connections when their intent is ambiguous. Their personal fields are
preserved; review the endpoint, authentication and key choice, then Save before
using them.

The old `agent.autoFreeRouting`, `communityCredential` and `communityKeyState`
settings are discarded. Migration recognizes distributed credentials using
one-way fingerprints; the client does not retain a reversible copy of those keys.
Repeated loads, saves and imports do not reintroduce retired access.

Encrypted configurations retain their existing password gate and encrypted
envelope until unlock. Migration filters protected keys after authentication;
it cannot rewrite encrypted provider identities before the payload is verified.
Undecided legacy storage follows the existing verified storage-choice workflow.
Unreadable credential envelopes remain recoverable instead of being replaced
with empty keys. Personal credentials keep the device's
[storage and export policy](../API_KEY_SECURITY.md).

If migration removes your last enabled provider, Chat and Quick Chat retain
their drafts and open provider setup. Choose another service and supply the
access it requires before sending. Existing conversations, workspace files,
notes, tool permissions and unrelated provider keys remain available.

Old exports and backups are not rewritten. Importing them applies the same
migration; running an old client still runs the old release. Updating UAI does
not revoke any credential at its upstream service.

[Custom endpoints](custom-endpoints.md) · [Key management](key-management.md) · [All provider guides](README.md)
