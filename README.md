# Project UAI

**4.1.1 — provider retirement, Zen fixes and request limits** · [Release notes](docs/RELEASE_4_1_1.md)

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

**No provider is added automatically.** Choose a hosted service, an available free
route, or a local server from Providers. Release 4.1.1 retires Project UAI Free
and the HCNSEC preset: community connections are removed, while personal HCNSEC
connections become custom endpoints with their settings preserved.
See [provider migration](docs/providers/migration.md).

Set **Requests per minute** under **Settings → Behaviour → Model requests** to match your service's
quota, such as 1, 2 or 10. Each provider can also have its own limit. `0` leaves
that limit off; queued requests remain cancellable.
After startup, **What's New** opens once for each new client release; later
executions of that version keep it closed.

New installations use **Allow everything**; choose **Ask first** to review tool
calls before they run. Stop cancels further work, but does not undo applied changes.

## What you can do

- **Keep technical knowledge:** [Master Vault](docs/MASTER_VAULT.md) stores
  searchable Markdown recipes, bug fixes, remote contracts and project notes,
  with bundled starters, sources and game/project scopes. It works locally.
- **Work toward an objective:** [Micro-goals](docs/MICRO_GOALS.md) keep dependent
  tasks, completion criteria, results and blockers with each conversation.
- **Customize UAI:** [UI mods](docs/UI_MODS.md) support appearance presets,
  workspace panels and unrestricted native scripts, with source review,
  version history, portable exports and safe-mode recovery.
- **Delegate work:** choose **Read only** or **Full access** for subagents.
  Each worker retains the parent conversation's tool scope and explicit denials.
- **Chat and organize:** conversation folders, retained-history search, Markdown
  exports, command search, and background agent progress.
- **Build scripts:** a shared Code workspace with files, syntax checks, source
  history, saved step-by-step goals, project starters and managed execution.
- **Connect your tools:** the optional local bridge provides Cowork in a browser,
  MCP access, installed CLI routes, and [Obsidian vault support](docs/OBSIDIAN.md).
  Roblox discovers the Windows desktop app automatically; manual native bridging
  has been removed.
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
| Build a reusable technical knowledge base | [Master Vault](docs/MASTER_VAULT.md) |
| Plan, pause and resume focused tasks | [Micro-goals](docs/MICRO_GOALS.md) |
| Customize and share the native application | [UI mods](docs/UI_MODS.md) |
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
