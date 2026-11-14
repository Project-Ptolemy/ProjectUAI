---
uai_vault: 1
title: "Build a small multi-file Luau project"
description: "Declare modules and tests explicitly, review patches, then generate a deterministic bundle."
kind: recipe
scope: global
tags: ["projects", "modules", "build"]
sources: [{"label":"Script project manifests and loader","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_PROJECTS.md"},{"label":"Script development guide","url":"https://github.com/Project-Ptolemy/ProjectUAI/blob/main/docs/SCRIPT_DEVELOPMENT.md"}]
status: verified
verification: "Manifest and loader workflow reviewed for Project UAI 4.0.0; compilation and behavior must be checked for the user's actual source."
---
# Build a small multi-file Luau project

Use `project_scaffold` for a staged starter, or declare a version-1 manifest with
explicit source paths. Paths are relative to the project directory and remain
inside the executor's files area.

```json
{
  "version": 1,
  "entry": "main",
  "modules": {
    "main": "main.lua",
    "settings": "settings.lua",
    "tests/settings": "tests/settings.lua"
  },
  "tests": ["tests/settings"]
}
```

`settings.lua`:

```lua
return { name = "My helper", enabled = false }
```

`main.lua`:

```lua
local settings = require("settings")
return { name = settings.name, enabled = settings.enabled }
```

Read staged source before applying a patch. `script_analyze` reports host compiler
diagnostics, lexical outlines and literal dependencies. It does not provide type
inference, an LSP or Roblox API validation. Dynamic requires remain dependent on
the explicitly declared runtime module map.

`project_build` checks and exports a deterministic bundle with source locations;
it does not execute the entry. Inspect that output before applicable behavioral
tests. The loader memoizes modules, preserves `false`, turns a nil return into
`true`, rejects active cycles and never falls back to Roblox's global `require`.

Project limits include 64 modules, 16 test modules, 256000 bytes per source,
1 MiB total source, and 256000 bytes per editable bundle. No package install,
implicit directory scan or network import is part of the project loader.

Modules receive `require` and `fixtures`. Keep initialization free of unwanted
effects because test discovery loads modules too. For interfaces, use UI LIB at
the entry point and keep runtime logic separate from declarative presentation.
