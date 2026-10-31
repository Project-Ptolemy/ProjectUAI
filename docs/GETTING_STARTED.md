# Your first Project UAI session

## Load and choose storage

Run the loader from the [README](../README.md). The client needs an executor with
the capabilities used by your task; unavailable capabilities are reported in UAI.

At startup, choose password protection or the explicit red **Continue without
encryption** action. Password protection requires at least 12 Unicode characters
and has no password recovery. Keep your password somewhere you can retrieve it.
The unprotected choice saves recoverable API keys and skips future password prompts.
See [credential storage](API_KEY_SECURITY.md).

## Add a provider

Open **Providers**, choose **Add provider**, and select a preset from the library.
The library separates free routes, paid services and local servers. Search by name
or use a custom endpoint. Choosing a card prepares a draft; **Save** applies it.

| Choice | What to supply |
| --- | --- |
| Project UAI Free | Select the optional preset; its shared credential is managed by UAI. Available daily 20:00–12:00 UTC+8. |
| HCNSEC | Your personal HCNSEC API key and a model available to that account. |
| Other hosted providers | The service's API key, compatible endpoint and model. |
| Local server | A reachable server URL and model; authentication depends on that server. |

Project UAI Free and HCNSEC are separate presets. New, reset and empty imported
configurations do not automatically add Free. Existing providers remain configured.
See [provider guides](providers/README.md) for service-specific steps.

Fetch models when supported, or enter an exact model ID. Select the provider and
model above the composer. A discovery failure does not prove that manual inference
is unavailable; check the endpoint, key and service documentation.

## Send a useful first message

New installations use **Allow everything**. Select **Ask first** under the composer
if you want to review tool calls. A useful first request is:

> Explain what is in this place before making any changes.

UAI sends your message and relevant conversation/tool content to your selected
provider. **Stop** cancels future work cooperatively; completed effects remain.
On touch devices, Return inserts a newline and **Send** submits.

## Find your way around

- **Chat:** conversations, attachments, model selection and permission mode.
- **Code:** shared documents, files, source history, Explorer and remotes.
- **Tools:** available tool names, parameters, capabilities and permissions.
- **Subagents:** delegated work, progress and reports.
- **Cowork:** connect the local bridge and use the browser workspace.
- **Logs:** application events and request diagnostics.

Use **Find a command** in the app menu, or **Ctrl+K** when you are not typing,
to find settings and actions. The profile menu's **Tutorial** reopens the introduction.
Read [Conversations](CONVERSATIONS.md) for organization, search and export.

## Return later

The same loader reuses a running copy when possible. Password-protected setups
require authentication again; an unprotected storage choice stays saved. An updated
bundle waits when replacement would lose active or unsaved work.

Use **Unload UAI** to save and release runtime resources. Deleting only the visible
ScreenGui does not unload the client. For problems, start with
[Troubleshooting](TROUBLESHOOTING.md).
