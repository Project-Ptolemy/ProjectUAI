# Project UAI Free

Open **Providers > Add a provider**, find **Project UAI Free** in the library,
and choose **Save**. Its separate preset supplies community access and selects
`auto`; no personal API key or model setup is required. Browsing the library or
opening its setup form does not install it or send an inference request.

New installations, empty imports and provider resets start without a provider.
Existing saved connections remain available. Removing Project UAI Free keeps it
removed on later starts; add it again from the library when wanted.

Community access opens daily at **20:00 UTC+8** and closes at **12:00 UTC+8 the
following midday**. Singapore and Beijing use this fixed offset. The provider
picker shows time until opening or closing. An accepted reply can finish after
closing; new requests, model fetches and background probes wait for opening.
Shared capacity and response speed can vary during the available hours.

`auto` can route on the provider. UAI's optional **Settings > Agent > Automatic
free routing** also measures small synthetic tool exchanges and chooses a recent
compatible result when available. Disabling that setting stops new background
measurements. It does not cancel an accepted request or turn off the provider's
own `auto` routing.

For a personal account, choose the separate [HCNSEC provider](hcnsec.md). Its key,
pricing and account limits remain separate from community access. Configuration
exports reference the distributed community credential rather than copying it.
The normal [credential-storage choice](../API_KEY_SECURITY.md) still applies.

[Community notices and help](https://discord.gg/9xYyyYuKap) · [All provider guides](README.md)
