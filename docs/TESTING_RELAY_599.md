# Companion 599 investigation and verification

Prepared November 5, 2026. The report described both "the companion could not
connect to the provider" and "the companion relay did not answer" across all
providers. Both are surfaced as terminal client status 599, but they originate
at different points in the shared relay transport.

## Provider connection failure

`companion/app/src/main/kotlin/dev/projectuai/relay/engine/JobEngine.kt` previously
disabled OkHttp connection recovery. When DNS supplied multiple addresses and
the first connection failed, OkHttp stopped without trying the next address.
This can affect unrelated providers on a network with an unusable address family
or route. The companion's `ConnectException` mapping produces the reported
"could not connect to the provider" message.

Companion 3.7.2/code 9 enables connection recovery and marks inference request
bodies one-shot. Connection failures before HTTP transmission can try another
address. A partially sent request, lost response or automatic HTTP status
follow-up cannot replay the POST. Redirects remain disabled. Certificate and
hostname validation remain enabled. The 15-second connection-attempt limit and
finite jobs' original deadlines remain in effect. Kilo's explicitly bounded
recovery after a complete quota refusal is unchanged.

The regression fixture uses real local sockets and an ordered DNS result with
one unavailable address followed by the listening mock provider. It compares the
previous disabled-recovery setting with the fixed setting, checks connection
attempts, and checks the provider's exact request count, body and authorization
header. Other cases exercise partial uploads, lost responses, redirects and
408/503 responses carrying `Retry-After: 0`.

## Local companion connection failure

`src/net/relay.lua` previously reduced every failed pre-submission hello to
"did not answer", including explicit HTTP refusals and unusable responses. One
transient failure stopped the request even when the companion had been discovered.
The client now permits at most three hello exchanges within 15 seconds and the
caller's earlier deadline. It keeps the same executor profile and native owner;
an unfinished native call retains its lane until completion. Cancellation and
credential access restrictions still stop submission. Invalid replies and
explicit non-transient HTTP refusals stop immediately with fixed, redacted
diagnostics. No provider request exists during this recovery.

`src/net/relay_link.lua` also had two discovery defects:

- It required a native `request` function even when the existing HttpGet/HttpPost
  adapter was available. Discovery now admits that adapter on its own, with the
  same companion capability and authenticated-pairing checks.
- A previously verified HttpGet/HttpPost profile sent hello through authenticated
  `/api/executor`. After a pairing token changed, an explicit 401 prevented the
  public hello and existing saved-pairing repair from running. That specific
  refusal now permits one public hello and the normal authenticated status check.
  Connection failures do not erase or reset pairing credentials.

The client regression fixtures check successful inference with only
HttpGet/HttpPost, token repair, bounded hello recovery, unchanged native ownership,
single submission, cancellation, unusable replies and diagnostic privacy.

## Verification

Source, documentation and test inputs were manually audited before builds.
Generated outputs were inspected before automated verification, and fixes were
reviewed before rebuilding or retesting, as required by `AGENTS.md`.

| Check | Result |
| --- | --- |
| Companion JVM suite | 92 tests across 12 suites; zero failures, errors or skips |
| Companion discovery and preflight | 68 cases / 307 assertions passed |
| Relay poll ownership | 8 cases / 35 assertions passed |
| Mobile relay | 38 checks passed |
| Mobile deadlines | 15 cases / 54 assertions passed |
| HTTP diagnostics | 10 cases / 50 assertions passed |
| Bridge lifecycle | 54 checks passed |
| Bridge previews | 7 cases / 25 assertions passed |
| Credential-vault admission | 11 cases / 40 assertions passed |
| Provider compatibility | 106 cases / 2,010 assertions passed |
| Provider transport | 22 cases / 560 assertions passed |
| Main native suite | 137 scenarios; 2,692 checks passed, 5 failed before the fixture correction described below |
| Native static checker | 311 files; zero failures or warnings |
| Official Luau compiler | Both changed source modules and the complete native bundle passed |
| Native bundle and manifest freshness | Passed |
| Android release build and package inspection | Production signer, package/version metadata and 16 KiB alignment verified |
| Android release packager | 10 tests and artifact consistency check passed |

Two inline companion fixtures in bridge lifecycle/preview tests were updated to
include the protocol's existing `uai-relay` marker. The broader native suite also
exposed a pre-existing filesystem fixture failure: it disabled all providers,
ignored the resulting rejected send, then expected a new turn's tool epoch.
The original `b5db6fc` bundle reproduced that same failure in an isolated checkout.
The fixture now configures a mock provider, queues a successful response and
asserts admission; its focused rerun passed all 12 checks. Product behavior was
unchanged by this fixture correction.

The remaining four failed checks span three unchanged scenarios: bullet layout,
reply model attribution and OpenCode gallery guidance. All four were reproduced
against the original `b5db6fc` bundle in an isolated checkout (49 passed / 4 failed
across those three scenarios). They remain existing broader-suite issues; the
relay changes do not alter their implementation. The full native suite was not
rerun after the isolated filesystem fixture correction.

The provider compatibility matrix also needed its existing Cloudflare fixture
updated from generic `/models` to the implemented Workers AI `/ai/models/search`
route and response shape. Its authentication and inference model-ID checks were
preserved; no provider implementation changed for that fixture correction.

## Local artifacts

The native client is build `3.8.0-368b772ac0a5c1ae`, with 315 modules. The
companion is 3.7.2/code 9, package `dev.projectuai.relay`, minimum API 26 and
target API 36. Its production certificate remains pinned to
`ad7d215b8ad67ce70ae2ce89ad3ea959b68202b5c38e72141a68f7d54331f4b5`.

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| `dist/uai.lua` | 4,269,712 | `64378bf4f12ad7fbf9e3869cc08df70a083365a732306f750a180a69e335c3b9` |
| `companion/release/UAI-Relay-3.7.2.apk` | 39,830,600 | `8abcf28ee18eddddc7da632a81c8c63c8d43e44c86db779c78158f36965c2a55` |

The adjacent `relay-release.json` and `.apk.sha256` match the signed APK.
Companion release artifacts are ignored by Git and must be regenerated or
published separately; the source changes and native client bundle are tracked.

## Applying the fix and limits

Install the production-signed `UAI-Relay-3.7.2.apk` over the existing production
companion and reload the updated `dist/uai.lua` client. Both components have
changes. The Android update uses the same package and signing identity, so a
normal upgrade does not require uninstalling or resetting pairing.

These regressions establish concrete transport defects; no trace from the
reporting phone was available to establish its exact failing network path.
No Android device was attached for native executor, installation or background
service checks. Release assets are published separately under `relay-v3.7.2`;
the main-branch client update supplies the corrected script to existing loaders.
