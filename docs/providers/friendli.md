# FriendliAI Model APIs

Use **Providers > Add a provider > FriendliAI Model APIs**. The preset uses
`https://api.friendli.ai/serverless/v1`, Chat Completions and Bearer auth.

| Connection | Value |
| --- | --- |
| Model catalog | `GET https://api.friendli.ai/serverless/v1/models` |
| Inference | `POST https://api.friendli.ai/serverless/v1/chat/completions` |
| Authentication | Personal API key field; UAI sends `Authorization: Bearer <key>` |

1. Open Friendli Suite and select the team that will own the usage.
2. Create a Personal API key and check the team's prepaid balance.
3. Paste the key into UAI, fetch models and select the exact served ID.
4. Save and send a short request using a model with tool calling enabled in its
   documented capabilities.

This is the shared Model APIs service. A Dedicated Endpoint has its own
deployment and billing configuration; its deployment ID and URL should not be
copied into the shared preset without following the Dedicated Endpoint docs.
Configure a separately documented compatible deployment through
[Custom endpoint](custom-endpoints.md), using that deployment's served ID.

The catalog marks chat entries with `mode: chat`. UAI excludes explicitly
different modes on this exact route. The provider also publishes input/output
modalities and `functionality.tool_call`; chat compatibility alone does not
guarantee images or tool calls. Parallel tool calls are model-dependent.

The catalog can be public, so a successful fetch does not verify your key or
balance. If an inference request fails, check your key's team, balance and selected
model. If a required feature is rejected, choose a model advertising that feature
rather than changing the protocol for the entire provider.

When the catalog is unavailable, choose **Type model ID** and copy an exact ID
from the shared Model APIs documentation. Retain `/serverless/v1` in the URL.
If the key was created for a different team, review the key's team before changing
models; fetching the public catalog cannot diagnose that account mismatch.

Check billed usage in Friendli Suite. A UAI token-cost estimate, when available,
does not cover a separate deployment's billing arrangement; see
[price coverage](../PROVIDER_COMPATIBILITY.md#model-prices-and-limits).

[Model discovery](model-discovery.md) · [Key management](key-management.md) ·
[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)

Official sources:

- [Model APIs quickstart](https://friendli.ai/docs/guides/model-apis/quickstart)
- [OpenAI compatibility](https://friendli.ai/docs/guides/openai-compatibility)
- [Tool calling](https://friendli.ai/docs/guides/tool-calling)
