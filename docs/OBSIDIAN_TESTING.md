# Obsidian verification

Review all changed inputs before building, inspect generated artifacts, then
run focused checks. Review fixes before rebuilding or retesting.

```powershell
node --test (Get-ChildItem bridge/tests/vault-*.test.js).FullName
luajit test/obsidian_runtime.lua
luajit test/obsidian_transport.lua
luajit test/obsidian_tools.lua
luajit test/obsidian_ui.lua
luajit test/obsidian_documents.lua
luajit test/obsidian_editor.lua
node bridge/tests/browser-vaults.js
```

The browser check uses the external Playwright installation selected by
`PLAYWRIGHT_MODULE`. Tests use isolated temporary vaults and configuration files,
without personal notes, installed provider CLIs or model accounts.

Coverage includes path/link boundaries, replaced roots, UTF-8 pagination, stale
revisions, read-only policy, damaged configuration preservation, multiple bridge
instances, bounded search, wiki/Markdown backlinks, sanitized filesystem errors,
HTTP authentication, uncertain saves, tool budgets/permissions, native settings
cleanup and browser draft recovery.
Native editor checks cover revision-bound page assembly, line-ending preservation,
draft capacity, explicit conflict review, read-only controls and no save replay.

For a manual check, use a disposable vault:

1. Connect it read-only in native Settings. Copy its id and confirm agent reads
   work while writes are refused.
2. Enable editing, create a note in a new folder, and check it in Obsidian.
3. Open the note in Cowork, edit it externally, then save the old browser draft.
   Confirm the external edit survives and the draft can be downloaded.
4. Check relative links, duplicate note names, backlinks and frontmatter.
5. Disconnect and verify the files remain. Move a connected folder and confirm
   Settings reports it unavailable.
6. Cancel closing Settings with unsaved text; verify the draft remains. Resize
   to a narrow portrait window and check editor/button access.
7. Open the native note browser, edit a note, close the editor and recover its
   draft. Change the file externally and verify Save fails until current-file
   review. Inspect a linked note and return to the original draft.

Offline and Chromium checks do not verify native Roblox rendering, executor
transport compatibility or a particular Obsidian sync service.
