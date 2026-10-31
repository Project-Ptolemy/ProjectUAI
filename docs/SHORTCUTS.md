# Commands and keyboard navigation

Open **Find a command** from the app or profile menu. It searches application
destinations, settings descriptions and up to 64 loaded conversation titles.
Several words can match different fields; `vault notes` finds Obsidian settings.
Search results do not run model inference.

| Shortcut | Action |
| --- | --- |
| Ctrl+K | Find a command |
| Ctrl+Shift+P | Search conversation contents |
| Ctrl+, | Open Settings |
| Ctrl+L | Open Chat and focus the current message composer |
| Up / Down in command search | Select the previous / next result |
| Enter in command search | Open the selected result |
| Escape | Dismiss the current dialog or menu |

Global shortcuts apply while the UAI window is visible, access is unlocked, and no
text field or other dialog owns input. They ignore extra Alt/Shift modifiers and
input already handled by Roblox. Release text focus before using them; this avoids
stealing editor or game input. Ctrl is the supported modifier on every keyboard.

The menu and result rows provide touch and gamepad navigation alternatives.
Keyboard shortcuts do not change a conversation's provider, clear a composer
draft, or send a message. Results are capped at 40; refine the query when the
matching-destination count is larger.

Command search covers conversation titles. Use **Search conversations** to find
retained messages, replies and folders; **Show more** reveals further matches.
See [Conversations](CONVERSATIONS.md).
