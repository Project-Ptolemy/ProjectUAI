# Venice

Use **Providers > Add a provider > Venice**. Keep
`https://api.venice.ai/api/v1`, Chat Completions and Bearer authentication.

| Connection | Value |
| --- | --- |
| Model catalog | `GET https://api.venice.ai/api/v1/models` |
| Inference | `POST https://api.venice.ai/api/v1/chat/completions` |
| Authentication | Inference Only API key field; UAI sends `Authorization: Bearer <key>` |

1. Create an **Inference Only** API key in Venice settings. UAI needs inference
   access, not account-administration access.
2. Confirm that the account has usable DIEM, bundled credits or USD balance.
3. Paste the key into UAI, fetch models, choose an exact ID and save.
4. Check the model's capabilities for tool calling and, if needed, image input.

Venice returns text models by default from its public model catalog. UAI keeps
entries with the documented `type: text` and omits explicit non-text types.
The catalog's capability and offline fields provide further model-specific
information; listing an ID does not guarantee that it is currently serving.

A successful public catalog fetch does not authenticate the key. Inference can
return 402 when an individual key's spending limit is reached even if the account
still has a balance. Review both the account funding and the key's own limit.
For a model-unavailable response, refresh the list and check its current status.

Venice-specific generation options may differ by model. Start with the preset's
default parameters and add advanced options only when the documentation for your
chosen model requires them.

If discovery is unavailable, choose **Type model ID** with an exact text-model
ID from Venice's documentation. Keep `/api/v1` in the endpoint. If a desired ID
is missing from a successful list, check its type and offline status before using
manual entry; manually saving an ID does not make an offline model available.

For a 401, review the inference key and any custom Authorization header. For a
402, review both funding and that key's spending cap. With multiple keys, name
them in **Manage API keys** so a paused or limited entry is easy to identify.
Use Venice's account usage for charges; UAI's text-token estimates do not model
every credit arrangement. See [price coverage](../PROVIDER_COMPATIBILITY.md#model-prices-and-limits).

[Model discovery](model-discovery.md) · [Key management](key-management.md) ·
[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)

Official sources:

- [Quickstart](https://docs.venice.ai/getting-started/quick-start)
- [API key creation](https://docs.venice.ai/guides/getting-started/generating-api-key)
- [Model catalog](https://docs.venice.ai/api-reference/endpoint/models/list)
