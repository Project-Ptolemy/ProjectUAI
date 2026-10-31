# AI/ML API

Use **Providers > Add a provider > AI/ML API**. Keep
`https://api.aimlapi.com/v1`, Chat Completions and Bearer authentication.

| Connection | Value |
| --- | --- |
| Model catalog | `GET https://api.aimlapi.com/v1/models` |
| Inference | `POST https://api.aimlapi.com/v1/chat/completions` |
| Authentication | API key field; UAI sends `Authorization: Bearer <key>` |

1. Create an AI/ML API key and choose a paid billing option.
2. Paste the key into UAI and fetch models.
3. Search the catalog for a model documented to use Chat Completions, choose its
   exact ID, then save. Check tool support for agent work.
4. Send a short request and confirm usage in the provider dashboard.

The preset is in the paid group because the free-tier documentation reviewed
for it said the free tier was paused. Check the provider's current billing terms
before buying access. An API key or access to the public model list does not
itself grant free inference.

The full catalog includes chat, Messages, Responses, embeddings, audio, image,
video and batch APIs. On this exact Chat Completions preset, UAI accepts rows
whose declared `type` is `openai/chat-completions` and hides explicit other types.
An ID intended for `anthropic/messages` or `openai/responses/submit` cannot be
made chat-compatible by selecting it from a list. Manual IDs remain possible
for provider changes, but their API compatibility is your responsibility.

If the catalog cannot be read, use **Type model ID** and copy one exact ID from
the model's Chat Completions example. If the catalog loads but your model is
missing, check its API type before entering it manually. Manual entry does not
convert a Responses or Messages model to Chat Completions.

Public catalog success does not confirm authentication or funds. For a failed
request, inspect your key, plan, remaining balance and the model's API type.
Search uses plain words and preserves the refresh/manual-entry actions even
when no model matches.

Use the provider dashboard for billable usage. UAI's token-cost estimates cannot
establish the price of an unknown route or account-specific plan; see
[price coverage](../PROVIDER_COMPATIBILITY.md#model-prices-and-limits).

[Model discovery](model-discovery.md) · [Key management](key-management.md) ·
[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)

Official sources:

- [Text model APIs](https://docs.aimlapi.com/api-references/text-models-llm)
- [Complete model list](https://docs.aimlapi.com/api-references/service-endpoints/complete-model-list)
- [Free-tier status](https://docs.aimlapi.com/faq/free-tier)
