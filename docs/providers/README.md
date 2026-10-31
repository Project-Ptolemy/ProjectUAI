# Provider setup guides

Open **Providers > Add a provider**, choose the named preset, provide its required
access, choose a model and save. The preset fills in the URL, protocol and
authentication style. New setups start without a provider; library browsing does
not install one or send inference. A preset does not buy credits or confirm access.

| Task | Guide |
| --- | --- |
| Add optional community access | [Project UAI Free](projectuai-free.md) |
| Use a personal HCNSEC key | [HCNSEC](hcnsec.md) |
| Find a model or use an exact ID | [Model discovery](model-discovery.md) |
| Rotate, name or pause keys | [Key management](key-management.md) |
| Run your own models | [Local servers](local-servers.md) |
| Connect another compatible API | [Custom endpoints](custom-endpoints.md) |
| Fix a setup or request error | [Troubleshooting](troubleshooting.md) |
| Understand an older saved setup | [Provider migration](migration.md) |

| Preset | Access and setup |
| --- | --- |
| [Vercel AI Gateway](vercel.md) | Monthly credits for eligible free-tier models; paid catalog is broader |
| [Perplexity Orchestrator](perplexity.md) | Funded API account, separate from other Perplexity APIs |
| [FriendliAI Model APIs](friendli.md) | Personal API key and team balance; shared serverless endpoint |
| [Venice](venice.md) | Inference Only key, funded credits and per-key spending limits |
| [Nscale](nscale.md) | API key and credits for serverless inference |
| [Arcee AI](arcee.md) | Platform key, current hosted IDs and published token rates |
| [AI/ML API](aimlapi.md) | Paid API access; documented free tier is paused |

For other connections, see [AgentRouter](../AGENTROUTER.md),
[Kilo quota recovery](../KILO_TUNNEL.md), [Cline desktop setup](../CLINE_TUNNEL.md)
and the [provider compatibility contract](../PROVIDER_COMPATIBILITY.md).

The external documentation and unauthenticated model catalogs for the seven
vendor guides above were checked on October 25, 2026. Paid inference was not exercised.
Successful model discovery proves only that the catalog could be read; it does
not prove a key is valid, funded, authorized for every model or below its limit.

Model menus support multiword search. Fetch and manual-entry actions remain
available when a search has no matches. UAI hides explicitly incompatible catalog
kinds on these providers' documented routes; manually entered IDs remain available.
Choose a model that supports tool calling for agent work. A chat-compatible entry
can still lack tools, image input or a particular reasoning setting.
