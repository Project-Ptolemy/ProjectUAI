# Obsidian bridge API

Routes use the existing bridge bearer authentication and same-origin checks.
The companion app does not implement them. Configuration is user-owned; agent
tools expose note operations only.

| Route | Method | Result |
| --- | --- | --- |
| `/api/vaults` | GET | Ids, names, read-only policy and availability; no absolute roots |
| `/api/vaults/config` | GET | User-facing connections, including absolute roots |
| `/api/vaults/config` | POST | Connect, change policy, or disconnect |
| `/api/vaults` | POST | Run a note operation |

`/api/hello` advertises `capabilities.obsidian` with `schema:1`, `available`,
`configured`, `readLimit` and `configError`. Damaged configuration blocks changes
instead of being overwritten.

## Connections

```json
{"action":"connect","name":"Notes","root":"C:/Users/you/Documents/Notes","readOnly":true}
```

The response includes `connectedId`. Include its `id` when renaming or changing
the root. Connect operations default to read-only.

```json
{"action":"policy","id":"vault_example","readOnly":false}
```

```json
{"action":"remove","id":"vault_example"}
```

Removing a connection keeps all files. Changes from another bridge instance
produce a 409; restart this bridge to reload its connection configuration.

## Note operations

Every action except `vaults` takes the stable `vault` id.

| Action | Additional fields |
| --- | --- |
| `vaults` | None |
| `list` | Optional `folder`, `offset`, `limit` |
| `search` | Literal `query`; optional `folder`, `offset`, `limit` |
| `read` | `path`; optional `offset`, `limit`, `revision`, `metadata` |
| `links`, `backlinks` | `path`; optional `offset`, `limit` |
| `create` | New `path`, `content` |
| `update`, `append` | Existing `path`, `content`, exact `revision` |

Paths are relative, use `/`, and end in `.md`. Offsets begin at 1. Listings return
`data`, `offset`, `nextOffset` and `total`; a null continuation ends the current
listing. Listings are fresh scans, so concurrent additions can change pages.
Narrow the folder/query when coverage is incomplete.

Reads return `content`, full-file SHA-256 `revision`, `bytes`, `modifiedAt`,
`offset`, `nextOffset` and `eof`. Pass that revision for later pages to reject
mixed file versions. Use returned byte offsets; splitting UTF-8 is rejected.
`metadata:false` omits metadata. Its `limited` object identifies truncated
headings, links, tags and raw frontmatter.

Link results include `candidateCount` and `candidatesLimited`. Ambiguous candidate
lists retain at most 25 paths within 8,000 UTF-8 bytes; the complete count stays
visible so a truncated list cannot imply an unambiguous target.

Writes require editing enabled and accept at most 1 MiB UTF-8. They verify saved
bytes. `append` adds no implicit newline. Creates never overwrite. Updates stage
a temporary file and recheck the revision before replacement. These checks catch
observed changes; independent sync programs do not participate in a filesystem
transaction.

A 409 requires rereading or reconnecting. Missing files return 404; read-only or
forbidden links return 403; oversized notes return 413; invalid UTF-8 returns 422.
Filesystem errors omit absolute paths. A connection failure has an uncertain
outcome: inspect the note before another write.
