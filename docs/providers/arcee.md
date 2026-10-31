# Arcee AI

Use **Providers > Add a provider > Arcee AI**. The preset uses
`https://api.arcee.ai/api/v1`, Chat Completions and Bearer authentication.

| Connection | Value |
| --- | --- |
| Model catalog | `GET https://api.arcee.ai/api/v1/models` |
| Inference | `POST https://api.arcee.ai/api/v1/chat/completions` |
| Authentication | API key field; UAI sends `Authorization: Bearer <key>` |

1. Create an API key in Arcee Platform and confirm your billing balance.
2. Paste that key into UAI and fetch the current catalog.
3. Select an exact ID from this provider's list and save.
4. Check the selected model's tool support and send a short request before
   attempting a long agent run.

Arcee's published pricing lists paid token rates. A model with a similar name
being free through another gateway does not make the Arcee route free. Do not
copy a promotion suffix from Kilo or OpenRouter into an Arcee model ID unless
Arcee's own current catalog includes it.

The model list requires an API key. If fetching returns 401, confirm the key and
Bearer authentication. If a listed model fails during inference, check current
capacity, your account balance and the exact model ID. Catalog availability is
not a reservation of inference capacity.

Hosted model capabilities can differ across routes. Use Arcee's description of
the served model when deciding whether to send images or use advanced reasoning
parameters. The preset leaves model selection to the current catalog rather than
embedding a model that could disappear before the next UAI release.

If model discovery is unavailable, choose **Type model ID** and copy an ID from
Arcee's current inference example for this endpoint. Keep the `/api/v1` path;
removing `/api` changes the route. A model-not-found response is a reason to check
the exact ID and endpoint together before changing authentication.

For cost comparisons, use Arcee's own rates and account usage. UAI does not apply
another gateway's price to this connection merely because the model name matches;
see [price coverage](../PROVIDER_COMPATIBILITY.md#model-prices-and-limits).

[Model discovery](model-discovery.md) · [Key management](key-management.md) ·
[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)

Official sources:

- [Platform quickstart](https://docs.arcee.ai/get-started/quick-start)
- [Pricing](https://docs.arcee.ai/get-started/pricing)
