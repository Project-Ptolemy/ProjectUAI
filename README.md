# Project UAI

**3.8.0** · [Release notes](docs/RELEASE_3_8_0.md)

An open-source AI workspace inside Roblox: chat with your chosen model, inspect
the game, build scripts, and run tools. Use it on its own or embed it in a host script.

[Get started](docs/GETTING_STARTED.md) · [Documentation](docs/README.md) ·
[Provider guides](docs/providers/README.md) · [Discord](https://discord.gg/9xYyyYuKap)

## Start

Run the published client in your executor:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/Project-Ptolemy/ProjectUAI/main/dist/uai.lua"))()
```

1. Set a master password, or explicitly choose **Continue without encryption**.
2. Open **Providers**, add a service from the library, and select a model.
3. Choose a tool permission mode under the composer and send your first message.

**No provider is added automatically.** Project UAI Free is an optional Providers
library preset with shared access during **20:00–12:00 UTC+8**. **HCNSEC is a
separate provider for your personal API key.** Shared availability and speed vary.
Existing configured providers are preserved.

New installations use **Allow everything**; choose **Ask first** to review tool
calls before they run. Stop cancels further work, but does not undo applied changes.

## What you can do

- **Chat and organize:** conversation folders, retained-history search, Markdown
  exports, command search, and background agent progress.
- **Build scripts:** a shared Code workspace with files, syntax checks, source
  history, saved step-by-step goals, project starters and managed execution.
- **Connect your tools:** the optional local bridge provides Cowork in a browser,
  MCP access, installed CLI routes, and [Obsidian vault support](docs/OBSIDIAN.md).
- **Build your own interface:** use [Project UAI UI LIB](docs/UI_LIBRARY.md), or
  connect the full client through the [embedding SDK](docs/EMBEDDING.md).

Open **Find a command** in the app menu, or press **Ctrl+K** when no text field is
focused. Search settings, actions and conversation titles without leaving a draft.

## Choose a guide

| Task | Guide |
| --- | --- |
| First message and provider setup | [Getting started](docs/GETTING_STARTED.md) |
| Search, organize and export chats | [Conversations](docs/CONVERSATIONS.md) |
| Keyboard navigation | [Shortcuts](docs/SHORTCUTS.md) |
| Connect a local Obsidian vault | [Obsidian](docs/OBSIDIAN.md) |
| Browser workspace and bridge | [Bridge setup](bridge/README.md) |
| Windows launcher | [Desktop app](desktop/README.md) |
| Write a script or a script-owned UI | [Script development](docs/SCRIPT_DEVELOPMENT.md) / [UI LIB](docs/UI_LIBRARY.md) |
| Keys, passwords and transferring settings | [Configuration](docs/CONFIGURATION.md) |
| Diagnose a problem | [Troubleshooting](docs/TROUBLESHOOTING.md) |
| Contribute or build from source | [Development](docs/DEVELOPMENT.md) |

See [release notes](CHANGELOG.md) for changes and [SPEC.md](SPEC.md) for the
engineering contract. Executor capabilities and provider limits vary; offline
checks do not establish native Roblox rendering or input behavior.

## Unload and support

Choose **Unload UAI** in the app/profile menu, or run:

```lua
getgenv().UAI.destroy()
```

[Join Discord](https://discord.gg/9xYyyYuKap) for help and project news.
[MIT licensed](LICENSE).
