# Configure a custom endpoint

Choose **Custom endpoint** in any provider-library tier. Enter the server's
documented base URL, protocol and authentication header before choosing a model.
The form shows the normalized URL that will be saved.

UAI supports Chat Completions, Anthropic Messages and Google's native Gemini
API. Its Responses support is scoped to supported AgentRouter and OpenCode
routes. A URL ending in a different native API is not made compatible by
selecting the Chat Completions preset.

Base URLs preserve explicit schemes, path prefixes and query strings. Public
bare hosts default to HTTPS; local and private hosts default to HTTP. Avoid
copying the same path segment into both the base URL and a proxy configuration.

Select the auth header expected by that endpoint. **None** is appropriate only
when the server accepts anonymous requests. Extra headers override generated
headers, so a stale Authorization override can defeat a newly entered key.
Check query parameters and custom body fields when switching between servers.

A gateway socket must implement UAI's envelope protocol. A normal HTTP server,
generic WebSocket or OpenAI Realtime socket is not such a gateway. Leave the
field empty unless the gateway's operator documents that protocol.

Save after fetching models or entering a documented ID. Browsing presets and
editing a connection remain local until Save. Switching presets resets the
fields that belong to the preset and clears a different preset's socket route;
custom names and ordinary personal key pools remain in the draft. Community
keys are removed when switching away from Project UAI Free.

**Duplicate setup** opens another unsaved connection with the same endpoint,
model and protocol. It clears keys, URL query fields and custom header/body/query
maps, so review authentication and overrides before saving. Community access is
added through its library card instead of duplicated.

**Reset learned compatibility** clears locally learned parameter repairs and
token/tool limits. Future requests may relearn them. This keeps key cooldowns,
provider health and accepted request ownership; it does not replenish credits or
resend a request. Use it after a provider fixes behavior that UAI had learned to
work around.

[Model discovery](model-discovery.md) · [All provider guides](README.md)
