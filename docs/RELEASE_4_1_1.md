# Project UAI 4.1.1

November 22, 2026. Client, bridge package and Windows desktop use **4.1.1**.
UI LIB remains **1.6.0**, embedding SDK **1.1.0**, and Android companion **3.7.2**.

Set **Requests per minute** under **Settings → Behaviour → Model requests** to limit inference attempts
across conversations. Each provider's connection settings can add its own cap.
Values such as **1**, **2** and **10** are supported; **0** leaves that cap off.
Both limits apply when configured. Waiting requests show their status and remain
cancellable, and explicit caller deadlines still apply. Model discovery and
bridge/relay polling do not consume this allowance. See
[configuration](CONFIGURATION.md) for examples and counting rules.

The caps pace dispatches from this UAI run. A bridge or companion job counts once;
its receipt recovery and polling are uncounted. Upstream recovery inside that
local app, including Kilo recovery or CLI retries, remains outside the client
counter. Provider and account quotas still apply.

**What's New** opens automatically once for a new client release, after startup
and any required credential unlock. The displayed version is remembered, so
later executions of the same release keep the modal closed. Release notes remain
available from the app menu.

Project UAI Free and the HCNSEC preset have been removed. The client no longer
ships their community credential, restores shared access, checks access hours or
runs automatic free-routing probes. Their settings, notices and setup actions
are removed from the native application and Cowork. Other available free routes,
paid services and local servers keep their normal provider behavior.

Older configurations and imports migrate automatically. Community-only records
and references are removed; mixed key pools lose recognized community credentials.
Personal HCNSEC connections become custom endpoints while retaining their keys,
custom names, models, IDs, enabled state and surviving key metadata. A default
preset name becomes Custom endpoint. If a pinned community key is removed,
review and save the connection before using its surviving personal keys. Active selection and
model shortcuts follow the remaining providers. Migration uses one-way key
fingerprints and performs no network requests.

Encrypted payloads retain their bound provider identities until authenticated
unlock, then apply the same migration before credential use. The existing
password/storage-choice workflow and recovery of unreadable envelopes remain
effective. Old exports and backups are not rewritten; importing them applies
the current migration. See [provider migration](providers/migration.md).

If the removed route was your only enabled provider, Chat and Quick Chat retain
their drafts and direct you to Providers. Add another service and select a model
before sending. No replacement provider or credential is installed automatically.
Conversations, workspace files, Vault notes, UI mods and tool permissions remain
available.

OpenCode Zen supports direct free Chat API authentication with OpenCode's public
token, independently of a connected bridge or installed CLI. Personal Zen keys
take precedence and keep their API route. Public model eligibility now comes
from fresh official catalog kind, protocol and price metadata, replacing the
hardcoded whitelist. Discovery uses the API catalog even when a CLI is installed;
the client verifies public eligibility before sending. Decision-only models and
unknown or priced rows cannot become public Chat access. The historical desktop identity,
truthful context and compatibility declarations remain scoped to Zen; its
standalone HTTPS cipher profile requires no Bun or CLI installation. Every
current free model is reviewed individually in the
[4.1.1 live matrix](OPENCODE_4_1_1_VALIDATION.md). Host transports can have different
eligibility; native executor and Android behavior require device verification.

Go, custom endpoints and explicit URL settings keep their own behavior. Current
free Chat models cannot inherit stale Responses routing, and real UAI tools that
share a compatibility declaration's name survive optional CLI handoff. Requests
preserve deadlines, cancellation, tool handoff to Roblox and the rule against
replaying uncertain inference. See [provider compatibility](PROVIDER_COMPATIBILITY.md).
Logs also redact Zen's `oc_sk_` credential format in ordinary diagnostic text.

The desktop app embeds the matching reviewed bridge, browser and client. Update
the executable to refresh its Copy client script payload. Updated browser assets
require refreshing an already open Cowork page.

Build and verification outcomes are recorded in [4.1.1 testing](TESTING_4.1.1.md).
Offline fixtures and browser previews approximate behavior and layout; native
Roblox rendering, host input and Android transport require device verification.
