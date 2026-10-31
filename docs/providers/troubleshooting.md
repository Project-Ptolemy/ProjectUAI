# Provider troubleshooting

Start with the provider's saved endpoint, active model and access status. The
visible route summaries omit query credentials. Keep keys out of screenshots,
issue text and shared request examples.

| Symptom | Check |
| --- | --- |
| No provider selected | Add a provider from the library and save it |
| Project UAI Free is closed | Wait for 20:00 UTC+8 or choose another provider; its daily close is noon |
| HCNSEC asks for a key | This is the personal provider; community access is the separate Project UAI Free card |
| All keys paused | Resume an entry in Manage API keys |
| Selected key is paused | Resume it, select another active entry or enable rotation |
| API key rejected | Verify the account, key and auth header, including overriding custom headers |
| Header validation fails | Use each header name once without spaces; values must be one line |
| Catalog loads but inference fails | A public catalog does not prove funding or model access |
| Model not found | Use an exact model/deployment ID served by this endpoint |
| No model list route | Use manual model entry |
| Local server unreachable | Verify the active request machine, host, port and server bind address |
| Text works but tools fail | Check the model's tool support and server chat template/parser |
| Vault is locked | Unlock before discovery, inference or saved connection edits |

A failed request after partial output, cancellation or a timeout can have an
uncertain upstream outcome. UAI does not silently replay that request through
another endpoint. Inspect the existing conversation and provider status before
choosing your next action.

Socket setup, an allowed HTTP fallback and native retries share the original
request timeout. A slow socket connection cannot grant another full timeout.
Both numeric and GMT-date Retry-After headers use the existing bounded,
cancellable wait; invalid dates fall back to normal backoff.

For a slow model, try a small prompt and a supported lower reasoning effort,
then compare latency with the same route and model. Executor HTTP is buffered;
the text can arrive together even when the provider generated it incrementally.

[Diagnostics](../DIAGNOSTICS.md) · [All provider guides](README.md)
