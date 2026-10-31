# UI library examples

Run these scripts in a client that supports `loadstring` and HTTP, or replace the
single entry loader with your reviewed ModuleScript. Each example loads the
published `main` bundle; pin a reviewed commit for reproducible deployments.

| Example | Workflow |
| --- | --- |
| [starter.lua](starter.lua) | A small tool with a button and keyboard shortcut |
| [showcase.lua](showcase.lua) | Controls, appearance, player choices and profiles |
| [forms.lua](forms.lua) | Required fields and an atomic Apply action |
| [profiles.lua](profiles.lua) | List, save, restore and explicitly delete named preferences |
| [debounce.lua](debounce.lua) | Search a live player list with owned, delayed updates |
| [activity.lua](activity.lua) | Coalesce heartbeat updates and clean up subscriptions |
| [workspace.lua](workspace.lua) | A searchable checklist with numeric review counts, selectable output, grouped actions and structured status |

Rerunning an example replaces only its own window. Closing a window releases its
callbacks, subscriptions, and scheduled updates. The library supplies appearance,
layout, local player profile and attribution; the scripts contain domain logic.

Use the [API guide](../../docs/UI_LIBRARY.md) for exact return values and the
[embedding workbench](../../examples/embedding/README.md) to connect an AI client.
