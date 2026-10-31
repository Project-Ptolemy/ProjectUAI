# API key security

Project UAI 3.7.2 offers a password vault by default and a red **Continue without
encryption** option. A vault encrypts saved provider credentials with AES-256-SIV
and PBKDF2-HMAC-SHA256. Continuing without encryption saves keys using reversible
byte encoding, leaves them unprotected, and skips future password prompts on this
device. The vault password is never stored in the configuration or bundle. The
implementation runs in bundled Luau and needs no external cryptography app.

Someone who obtains only the encrypted file must recover or guess the password
to decrypt its protected fields. Use a long passphrase of several unrelated words.
Scripts sharing the executor can still inspect live credentials, intercept requests
or capture the password while you enter it. Encryption at rest does not isolate
UAI from a hostile executor or another script in the same process.

## Upgrading the version you already used

1. Load the updated client with your existing `UAI/config.json`. Both the older
   plaintext format and the recently introduced byte-encoded format still load.
   Your existing keys are retained while you choose how to store them.
2. Enter and confirm a new master password in that prompt, then choose **Set
   password**. Use at least 12 characters, preferably
   several unrelated words. Setup prominently warns **NO PASSWORD RECOVERY**:
   keep the password somewhere safe, such as a password manager. If you forget it,
   resetting removes the credentials saved in this vault, and you must add them again.
3. After submission, the password dialog hides while a small panel at the bottom
   right shows an operation title, the percentage, **Cancel** and **Exit**. Wait
   for the verified-save confirmation. UAI carries over key pools, names, pauses,
   selection, accounting IDs and custom authentication. No key re-entry is needed. Cancelling derivation
   leaves the existing configuration intact and keeps access blocked.
4. With encryption enabled, later executions require that password again.
   Cancelling a running operation returns to password entry; choose **Exit** to
   leave UAI. Re-execution and build updates preserve credentials without granting
   password-free access.

To save keys without a password, choose the red **Continue without encryption**
action instead. UAI verifies the byte-encoded save before remembering this choice
as `security.credentialProtection = "unprotected"`. Key pools and their metadata
are retained, but anyone who can read the file can recover those credentials.
This is **not encryption**. Later runs skip password entry until you enable a
vault from Privacy. An existing encrypted vault must first be unlocked for the
current execution, or explicitly reset to discard its keys, before opting out.
An old session-only preference alone does not make this choice for you.

Embedding with `{ ui = false }` follows the same storage choice. With a vault,
password entry still appears on each execution, including same-build reuse.
The normal app stays hidden after the choice or unlock until explicitly opened.
An unlocked client may retain its private key to protect pending saves, but a
fresh execution still verifies the password and retains the latest live edits.
Inference, free providers, tool calls and remote commands wait until setup/unlock
or the explicit unprotected-storage choice succeeds.

During password derivation for setup or unlock, the compact progress panel replaces
the centered dialog and its full-screen backdrop. It names the operation above
the percentage at the bottom right so the game remains visible and usable. UAI's
own access stays blocked throughout the wait. Failure or cancellation reopens
password entry with cleared password fields and an explanation; successful setup
or unlock releases the access gate. Cancel and Exit remain available in the progress row,
subject to the storage operation's existing cancellation and unload checks.

The encrypted configuration is first written to `UAI/config.vault.pending.json`
and read back before the main configuration is changed. The main save is also
verified. If it fails, UAI keeps live keys and the previous active setting and
attempts to restore the prior bytes from memory. Keep the current session open
when a storage error is reported. A retained encrypted pending file allows startup
recovery if an interrupted write left the primary configuration missing or unreadable,
or a failed removal left a session-only primary beside the remaining encrypted copy.
Cancelled setup removes or invalidates its staged vault. If that cleanup fails,
the storage warning remains visible so the recovery file is not silently ignored.
No extra plaintext backup is created. Existing exports and historical files are
not automatically removed.

## Vault lifecycle and format

**Lock now** saves current credentials before removing them from UAI's live
configuration. Unlock restores them with the same key-pool metadata. A wrong
password or changed ciphertext releases no credentials. Locked providers cannot
send anonymously or accept connection edits that would overwrite the saved pool.
Already accepted requests may hold their own snapshots until they finish.

Configuration loads and saves run one at a time. Credential edits wait for a save
to finish; ordinary preference changes during a save are retained for a following
save. UAI stays open if unload or a changed-build update is requested while password
derivation or storage is busy. Finish the operation, or cancel derivation, then
retry unloading or updating. Unloading after normal edits saves their latest
encrypted values even when the usual save delay has not elapsed.

**Change master password** requires an unlocked vault and verifies the new
encrypted save before accepting it. **Continue without encryption** in unlocked
vault management instead verifies byte-encoded storage before removing encryption;
current keys are preserved. When you forget the password, **Remove saved
credentials** explicitly discards the encrypted pool and returns to the storage
choice. Ordinary settings remain; whether you set a new password or continue
without encryption, you must supply provider credentials again. There is no password
recovery or reset that retains the vault's saved credentials. Forgetting the password
does not automatically delete anything. Resetting the vault does not revoke keys at their providers or
erase existing exports and backups; revoke or replace provider keys separately.

The version-1 envelope uses RFC 5297 AES-256-SIV, with two 256-bit AES keys derived
by PBKDF2-HMAC-SHA256. New vaults and explicit password changes use **100,000
iterations**. Existing vaults retain their recorded count, including **600,000**;
opening or saving them does not silently change it. To rewrite an older vault at
100,000 iterations, unlock it and use **Change master password**. You may enter
the same existing password. Fewer derivation rounds reduce waiting and also reduce
the work needed for offline password guesses, so use a strong passphrase. Actual
time depends on the host.

The public GUID-based salt distinguishes vaults; it is not a secret.
The format header and provider identities are bound to the authenticated data.
Authentication is checked before decoded credentials are released. Unlike modes
that require a unique random nonce for every save, SIV can
safely operate without one; unchanged protected contents under the same key can
produce identical ciphertext. This reveals equality, not the protected contents.

Password entry is masked by default, with an explicit Show action. Password fields
are cleared after submission and on close. Only the derived key is retained in the
vault module's private state for the unlocked run. Lock and unload release that
reference. Lua strings and garbage collection do not guarantee secure erasure of
all previous memory copies. Derivation yields and reports progress so cancellation
remains available; actual unlock time depends on the host.

## Legacy storage compatibility

Older configurations may contain plaintext keys, reversible `storedCredentials`
byte envelopes, or a session-only preference. These formats remain readable so
either verified storage choice can preserve existing keys. The deliberate
**Continue without encryption** choice uses that same byte encoding for future
saves. A byte-envelope checksum detects accidental corruption; it does not provide
confidentiality or authenticate the file.

Malformed or unsupported records are preserved and cannot become anonymous
requests. Invalid encoded imports are rejected before replacing the current
configuration. Encoding or encryption failures never fall back to plaintext.
If the selected storage format cannot be verified, access remains blocked and
the existing keys remain available for recovery in the current session. Both
saved-storage choices need working filesystem support.

Credentials omitted by an earlier session-only save must be entered again after
choosing storage. The temporary key-rotation map is never persisted because it can
contain duplicate raw keys. Bridge and companion implementations are unchanged;
their pairing-token persistence remains independent of the provider vault.

## Copies, diagnostics and old files

The normal configuration copy omits provider credentials, identity headers,
bridge/relay tokens and recognized secret fields. The separately labelled private
copy preserves vault encryption when enabled, or includes reversibly encoded
credentials when encryption is disabled. It also includes existing connection
tokens for a deliberate transfer. It remains a private document.
Imports replace the provider configuration and retain the receiving device's
storage choice and vault password, if any. An encrypted import asks for its source
password before review. The destination must complete setup/unlock or deliberately
choose unprotected storage before using imports or exports.
Older encoded copies remain importable after that choice. Copies without credentials
require re-entry, except included community access, which restores from a reference.

Diagnostics use the same connection sanitization. These are not universal secret
detectors: a key manually pasted into a provider label, memory, custom instructions,
arbitrary extension data or a URL path can still be present there. Review personal
content before sharing. Existing exports, clipboard history, backups and old files
are not automatically found or erased. Deleting a current copy cannot revoke a key
already stolen or guarantee erasure from filesystem history.

## Rotate keys at the provider

Project UAI recommends regularly replacing personal API keys, preferably daily
where practical. Create the replacement in the provider dashboard, update UAI,
then **revoke the old key**. If theft is suspected, revoke the exposed key promptly
and inspect usage/billing. Set separate project keys, least-privilege permissions,
spending limits and alerts where the provider supports them.

UAI's **Rotate keys** option distributes requests among keys already in a pool.
It does not issue new keys, expire them or revoke old keys. Pausing/removing a key
inside UAI also does not revoke it at the provider. Daily replacement reduces the
lifetime of a stolen credential; it cannot prevent immediate abuse, or theft of the
replacement by a script that remains active.

## Included community access

Community access is an explicit **Project UAI Free** choice in the Providers
library. It is not installed on an empty startup, import or reset. **HCNSEC** is
the separate personal-key provider. Switching a Free setup draft to another
preset removes community keys even if its endpoint was edited first; personal
keys retain their labels, pauses and accounting identities.

**Project UAI Free opens daily from 8 PM to 12 PM noon, GMT+8 / Beijing / Singapore.**
That is 20:00 inclusive through 12:00 exclusive the following midday, using a fixed
UTC+8 offset. New requests, discovery and background probes observe this window.
Replies already accepted can finish. Personal HCNSEC keys and other providers do
not inherit the schedule. Shared capacity and upstream limits still apply.

The included credential is distributed to every client. Its encoded bundle
representation deters simple literal searches; the client must reconstruct it to
authenticate, so the encoding is **reversible obfuscation, not encryption or strong
secrecy**. Configurations and exports keep a community reference instead of its raw
value. Exact retired included credentials migrate on the official endpoint;
unrelated personal keys are preserved. Local references retain the included key's
pause state, name and selection; its accounting ID changes when the credential is
replaced. References at other endpoints cannot silently send without a key.
Updating the client does not revoke credentials at the provider.

Enforcement of community hours and quotas belongs at the provider. Modified clients
can bypass local schedule checks. The client cannot establish whether the upstream
service enforces the announcement, and rotating a distributed shared key does not
make its new value private.
