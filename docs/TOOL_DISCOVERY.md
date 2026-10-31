# Finding tools efficiently

To find the panel itself, use **Find a command** in the app menu and search
`tools` or `permissions`. This navigation does not change tool access.

Open **Tools** to search names, descriptions, groups and risk labels. Words can
match different fields: `file read` finds file-reading actions even when the
registered name uses underscores. The result count updates as you type.
**Parameters & permissions** builds details only for the tool you open, keeping
the full catalog cheaper to browse. Permission changes still apply immediately.

New installations use **Focused**: up to nine families (`uai_files`, `uai_code`,
`uai_instances`, `uai_game`, `uai_inspect`, `uai_connect`, `uai_automate`,
`uai_context`, `uai_other`) plus seven direct conversation/workflow tools.
Saved profiles remain selected. Each family advertises its exact available action
names. Use `action:list`, then `action:describe` for the needed schema and example,
then `action:call` with `name` and `arguments`. Reuse schemas already read.

For example, call `uai_files` with
`{"action":"describe","name":"file_read"}`, then
`{"action":"call","name":"file_read","arguments":{"path":"notes.md"}}`.
Every call re-enters the original action dispatcher. Families retain validation,
approvals, hooks, deadlines, disabled groups and conversation/request scope.

All, Lean and task-specific profiles remain available under Agent settings.
`tool_search` also lists, describes and invokes hidden available actions. The
following examples use that toolbox's pagination parameters:

```json
{"action":"list","query":"workspace source","limit":10}
```

Search supports words, "quoted phrases" and -excluded terms. It matches plain
text rather than Lua patterns, and
ranks exact tool names first. Queries are limited to 256 bytes and 16 distinct
words. A blank query retains catalog order. `group` selects one exact group.

```json
{"action":"describe","name":"file_read","limit":2000}
```

Describe returns the normalized schema used in provider declarations. Its
`limit` counts bytes; list limits count rows. List pages contain at most 100
rows, and schema pages request at most 20,000 bytes within the configured tool
result budget. Follow `nextOffset` to continue. This fixes the former shared
100-byte schema limit, which made explicit schema-page reads unnecessarily small.

Call the discovered tool through `action=call` with its exact arguments. UAI
checks its current permission and scope again at dispatch. Search/listing does
not clone all nested schemas, and only describe materializes the selected one.

## Obsidian example

Search `obsidian notes` and describe the operation you need. `obsidian_vaults`
lists configured vault IDs; use those exact IDs with `obsidian_list`,
`obsidian_search` and `obsidian_read`. A vault path is relative to the bridge
computer's configured folder, distinct from an executor `files/` path.

Before `obsidian_update` or `obsidian_append`, read the note and retain its
revision. A stale or uncertain write requires checking current state, not a blind
retry. Agents cannot connect arbitrary folders or enable editing themselves;
the user controls vault connections and their read-only policy in Settings.
See [Obsidian](OBSIDIAN.md) for the supported operations and limits.
