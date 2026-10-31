# Connect a local model server

Start the model server, load a model that supports tool calling, then choose its
entry in **Providers > Add a provider > Local servers**. Leave **Gateway socket
URL** empty for an ordinary HTTP server.

| Preset | Default URL |
| --- | --- |
| Ollama | `http://127.0.0.1:11434/v1` |
| LM Studio | `http://127.0.0.1:1234/v1` |
| vLLM | `http://127.0.0.1:8000/v1` |
| llama.cpp | `http://127.0.0.1:8080/v1` |
| SGLang | `http://127.0.0.1:30000/v1` |

These presets start without an API key. If you enabled authentication on the
server, select its required auth style and add its key. Fetch models or enter
the exact loaded ID, save, and try a small request.

`127.0.0.1` refers to the machine making the request. An executor, desktop bridge
or server in a different VM or container can have a different loopback address.
Use the server's reachable LAN address when appropriate. A server bind address
such as `0.0.0.0` is not the usual client destination.

Use the compatible `/v1` API, rather than Ollama's native `/api/chat` or
`/api/generate` routes. Tool calling depends on the model and the server's chat
template/parser. A text reply alone does not verify a usable agent setup.

UAI checks local reachability from the actual URL, including custom presets.
Local/private addresses require an executor HTTP function that can reach the
server. See the [compatibility contract](../PROVIDER_COMPATIBILITY.md#local-servers)
for additional servers and tool-template requirements.

[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)
