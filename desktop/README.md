# UAI Bridge desktop launcher

A Windows 10/11 x64 app that starts the local bridge and opens the Cowork browser
workspace. The Roblox client discovers the running desktop bridge automatically.
The desktop project uses the existing server in `--desktop` mode on
**127.0.0.1:28791**.
Manual terminal startup keeps port 8790 and its existing token workflow.

Download [UAI Bridge 3.8.0 for Windows x64](https://github.com/Project-Ptolemy/ProjectUAI/releases/download/v3.8.0/UAI-Bridge-3.8.0-win-x64.exe).
Checksums and release notes are on the [3.8.0 release page](https://github.com/Project-Ptolemy/ProjectUAI/releases/tag/v3.8.0).
Open the executable, then click
**Start Cowork** on **Workspace**. It detects Node.js 18+ on your computer. If
none is available, choose **Get Node.js** or **Manual setup** in the Workspace
runtime card, then **Check again**.

Desktop 3.8.0 uses native WPF with a responsive interface, its own
title bar with custom window controls, keyboard navigation, and accessible controls. The sidebar
becomes horizontal navigation on smaller windows, and page content scrolls so
actions remain reachable. Five pages organize the app:

| Page | What you can do |
| --- | --- |
| Workspace | Start or stop the bridge, open Cowork, copy the client script, and install or recheck Node.js. |
| Connections | Enable MCP and connect external coding agents to the workspace. |
| Updates | Check for desktop updates, see download and staging status, restart to apply an update, and inspect bridge update status. |
| Settings | Choose browser, launch, and automatic app update preferences. |
| Tunnels | Enable Cline, OpenCode and Kilo routes, inspect readiness, and follow setup instructions. |

Tunnels checks whether OpenCode and Cline are **Installed** or **Not found** as
soon as the app opens, before Cowork starts. Use **Refresh installed apps** after
installing or removing a CLI. This checks local files with the same detectors
the bridge uses; it does not launch either CLI or read their account settings.
Installation is separate from the connection's enabled, sign-in and ready state.
If Node.js is missing, the app shows **Not checked** with Workspace setup guidance.

Chat remains in the existing Cowork browser workspace; the desktop window
does not embed chat. A second launch brings the existing window forward,
including requests made during startup. The first launch also recovers an
unowned mutex left by a previous instance.

Use **Ctrl+1** through **Ctrl+5** to switch desktop pages from Workspace through
Tunnels. Page changes start at the heading; live refresh preserves your reading
position. See [keyboard controls](KEYBOARD.md).

OpenCode, Cline and Kilo status comes from the current bridge reply. Missing,
unsupported or malformed capabilities clear a previous Ready badge. A temporary
disconnect cannot retain an old OpenCode version or ready state.

The app downloads the current Windows x64 LTS executable from nodejs.org, checks
its official SHA-256, and installs it for your account without administrator
access.

The single executable includes .NET, the bridge, browser assets, the matching
client and license notices. It verifies and prepares its embedded files in a
private user cache automatically. There is no ZIP to extract or supporting
folder to keep beside the executable. Node.js is installed separately through
the app or detected on your computer. Roblox and the UAI script must remain running.

Obsidian vault support is part of the embedded bridge and Cowork assets. Configure
an explicit local vault in Cowork; note access uses that vault's configured root.
See [Obsidian setup](../docs/OBSIDIAN.md) for read-only access and reviewed edits.

## Optional OpenCode native workaround

Install [OpenCode Desktop](https://opencode.ai) separately, then restart the bridge.
The OpenCode card on **Tunnels** reports when its free models are ready. The
bridge detects the installed native CLI, starts its authenticated loopback server privately, and
routes models in its public catalog through the native connection. OpenCode is
**not bundled, downloaded or copied into the desktop distribution**. The app uses
its existing Windows Job Object to own the bridge and its CLI descendant; Stop
and closing the window shut them down. The bridge also supports an absolute
`UAI_OPENCODE_BINARY` override; see the [bridge guide](../bridge/README.md).

The existing direct desktop workaround still works without this app. This native
route provides an additional desktop option; on mobile, OpenCode requires the UAI
Relay app from Discord.
UAI tools are returned to Roblox for execution. The bundled bridge includes the private
execution guard and matching permission handling before returning
blocked-action feedback. The CLI never receives permission to run local
desktop tools. Provider keys and existing OpenCode credentials are not
copied into its isolated session. OpenCode's retired HTTPS proxy is not used.

OpenCode Go subscriptions use `https://opencode.ai/inference/go/v1` and your Go API
key directly. They do not use this native free-model route. That mobile relay
requirement applies to OpenCode free models, not Go subscriptions.

Add optional **Project UAI Free** from the Roblox client's Providers library and
save to use community access. A fresh client starts without a provider. Personal
HCNSEC keys use the separate HCNSEC preset. See the
[provider guides](../docs/providers/README.md).

The window reports bridge startup separately from Roblox connection. Minimize
keeps Cowork in the taskbar. Closing the window stops the owned bridge and its
OpenCode process, then exits; the app never hides in the notification area.
Repeated launches restore the existing window. Occupied ports produce an error;
the app never chooses an undiscoverable random port or kills another application.

## Cline free models

Install the official [Cline CLI](https://docs.cline.bot/cline-cli/overview), then
open **Tunnels > Cline tunnel**. Cline is enabled by default. Run the following
command in PowerShell, or use **Copy sign-in command** in the desktop app:

```powershell
cline auth cline
```

Restart the bridge after signing in. The card shows **Sign in needed** until the
profile is authenticated, and **Ready** only after the bridge validates the
current official free-model catalog. Each request must retain that exact model
in the native CLI. Cline is installed separately and is not bundled or
automatically downloaded. Its provider allowances still apply. Native Cline
owns authentication; UAI does not copy its tokens into provider settings.
The bridge prefers a dedicated UAI profile if one already exists; otherwise it
uses your standard Cline sign-in. See the [Cline guide](../docs/CLINE_TUNNEL.md)
for that optional profile setup.

## Desktop preferences

The app saves seven controls for this installation and retains them across
verified app updates:

| Control | Page | Default | Behavior |
| --- | --- | --- | --- |
| OpenCode tunnel | Tunnels | On | Uses the installed CLI for native free models. Turn off to avoid starting OpenCode. |
| Cline tunnel | Tunnels | On | Uses the installed CLI and your Cline sign-in for current free models; prefers the dedicated UAI profile when present. |
| Kilo tunnel | Tunnels | On | Starts quota recovery after an explicit anonymous Kilo free-model refusal. |
| MCP access | Connections | On | Allows external coding agents to connect to UAI's MCP endpoint. Turning it off rejects MCP sessions. |
| Open browser on start | Settings | On | Opens Cowork after successful bridge startup. **Open Cowork** always opens it manually. |
| Start bridge on launch | Settings | Off | Starts the bridge after Node.js detection; does not register Windows startup. |
| Automatic app updates | Settings | On | Checks and downloads desktop updates automatically. **Check for updates** on Updates remains available when off. |

Stop the bridge before changing any tunnel or MCP. The next start receives the
saved settings; existing tool calls are never silently interrupted by a switch.
The OpenCode card shows readiness, the detected CLI version, or a setup problem.
MCP access controls external agents; OpenCode's private tool relay remains
independent. App preferences contain no credentials, and malformed preference
files recover to defaults. Disabling automatic app downloads lets a download
already in progress finish. Closing always exits, including when an update is
staged; the new version starts the next time you open the desktop app. **Restart
to update app** on **Updates** applies a staged update after you stop the bridge
on **Workspace**.
Bridge worker updates continue automatically when work is idle. **Check for
bridge updates** on **Updates** asks a running bridge to look immediately; the
bridge and web UI version it reports ships as one package.

## Automatic connection

External AI harnesses can use the same desktop bridge as an MCP server. Click
**MCP setup** on **Connections** in the running desktop app to open its browser
setup panel, or open
**Settings → MCP** in Cowork to copy the configuration for your harness. The
single executable accepts `--mcp-stdio`, runs its verified embedded adapter with
the detected Node runtime, and discovers the already-running desktop bridge.
This command does not open a window or start another bridge. The HTTP endpoint
is `http://127.0.0.1:28791/mcp`. UAI retains control of tool permissions and uses
an isolated ephemeral conversation per MCP connection. See [MCP setup](../bridge/MCP.md).

`bridge.autoDiscover` defaults to true. Desktop clients probe the dedicated port
every four seconds, with a two-second request deadline. Touch-only mobile clients
skip this Windows discovery route. An enabled manual bridge takes
priority. Turn off **Manual bridge enabled** in Cowork to use the desktop app.
Disable **Find desktop app automatically** to opt out. `bridge.stop()` suspends
discovery until `bridge.sync()` or a connection-setting change. Unloading releases
the discovery worker and ignores pending results.

Authenticated bridge contact selects Web runtime automatically;
disconnecting restores Game for subsequent requests. Stopping or restarting the
launcher does not resend an inference request.

## Automatic updates

Bridge releases download automatically, are verified, and activate only when
active work and retained receipts/pictures are idle. An automatic worker restart
keeps the same pairing token. The browser reconnects to the updated bridge.
Refresh an open browser page to load changed web assets. **Copy client script**
on **Workspace** copies the client embedded in the desktop executable. Desktop
3.8.0 includes the reviewed client and bridge, including local Obsidian vault
support. The Android companion remains on its separate existing release.

**Tunnels > Kilo tunnel** enables anonymous Kilo quota recovery by default.
After an explicit quota refusal, the bridge starts a private Tor helper and
makes a bounded retry through another connection. The first use downloads a
verified 22 MB archive. Each exit still has an allowance; shared exits may
already be limited. Stop Cowork to change the switch. See
[Kilo setup and evidence](../docs/KILO_TUNNEL.md).

When automatic app updates are enabled, the desktop app separately checks stable
releases in `Project-Ptolemy/ProjectUAI` on startup and every 15 minutes. It
downloads and verifies a compatible desktop executable in the background.
**Updates** shows the check, download, and staged result.
A ready update applies on restart; **Restart to update app** is available once
the bridge is stopped. Updates never automatically stop an active conversation.
Malformed or unrelated entries in the GitHub release list are skipped without
preventing discovery of a valid desktop release.

Desktop versions are staged in a private per-install cache under LocalAppData.
Extracted payloads, staged versions and quarantine folders that are older than
an hour and no longer referenced are pruned automatically, so the caches stay
bounded across updates.
The original executable is retained. The launcher remembers a verified
new version only after the replacement app reports successful startup. For an
immediate restart, the current app waits for the update helper to acknowledge
ownership of the handoff before exiting. The helper then checks the replacement's
startup receipt and falls back to the retained executable if startup fails.
The original shortcut continues to work, and bridge cache identity stays stable
across desktop updates. A candidate that failed to start is not retried by
automatic checks; choose **Check for updates** manually to retry that candidate.
Failed network or integrity checks leave the current app usable.

Desktop 1.0 has no updater, so its users need one manual download of a current
desktop executable first.
For each future release, publish `desktop-release.json`,
`UAI-Bridge-<version>-win-x64.exe`, and its adjacent `.sha256` on the same official
`v<version>` or `desktop-v<version>` GitHub release. The manifest includes the
exact version, platform, executable name, byte size and SHA-256. Bridge updates independently need `bridge-release.json`
and `uai-bridge-package.json`; see the [bridge guide](../bridge/README.md).

Desktop credentials live only in memory and rotate at each app start. The app
and native executor discover through a desktop-only POST endpoint requiring the
exact loopback Host, a custom header and JSON. Browser Origin and Fetch Metadata
headers are rejected, with no CORS support. Native programs on this computer are
inside this trust boundary; this is not authentication against local malware.
All ordinary bridge routes still require the bearer token.

Discovery returns a fixed product marker, schema, port, instance and token. The
client validates these before attaching and uses one shared effective connection
for commands, web inference and pictures. Credentials never replace saved manual
settings. A changed connection terminates an outstanding relay request rather
than resending it to a new process.

## Build and verification

Install the .NET 10 SDK for Windows and Node.js 18+ for verification. The package
build does not download Node, OpenCode or Cline. There are no NuGet library dependencies.
`desktop/make-icon.ps1` draws the executable's native connection glyph, the
sidebar brand mark is typeset text, and the window draws its own title bar —
drag to move, with custom minimize, maximize and close buttons — while resizing,
snapping and taskbar behavior stay native. Manually audit all
changed source, documentation and tests first, then build:

```powershell
powershell -ExecutionPolicy Bypass -File desktop/build.ps1
# Optional local SDK: -Dotnet C:/path/to/dotnet.exe
```

The desktop build embeds the existing `dist/uai.lua` alongside the bridge and
browser assets. A desktop-only change does not require rebuilding the client.
Inspect the generated payload, executable, release manifest and SHA-256, then verify:

```powershell
powershell -ExecutionPolicy Bypass -File desktop/verify.ps1
```

Optional bridge compatibility checks use the existing offline Node harness:

```powershell
node --test bridge/tests/desktop.test.js bridge/tests/opencode-native.test.js bridge/tests/updater.test.js
```

The desktop verification checks the release executable and embedded file hashes,
single-file startup, and the absence of bundled Node/OpenCode runtimes. It exercises
detected Node, repeated startup, discovery, simulated game status, graceful stop
and restart with a new token. It checks persisted preferences, launch switches,
native minimize/restore, window-close shutdown, responsive page layout, and updater
validation and handoff fixtures. It also renders native WPF content previews in
`desktop/.build/verification/`: `launcher.png`, `launcher-connections.png`,
`launcher-updates.png`, `launcher-settings.png`, `launcher-tunnels.png`,
`launcher-tunnels-bottom.png`, `launcher-compact.png`, `launcher-narrow.png`,
`launcher-narrow-bottom.png`, `launcher-narrow-tunnels.png`, and
`launcher-narrow-tunnels-bottom.png`. Inspect each preview.
The previews capture WPF content; native title-bar behavior is checked separately.
These offline checks do not claim a live executor/Roblox connection.
Manually review each fix before rebuilding or retesting.

Build outputs, dependency caches and intermediate files are ignored by Git.
Publish the executable, release manifest and adjacent SHA-256 as release assets.
This local build is unsigned; signing and public release publication are separate
distribution steps.
