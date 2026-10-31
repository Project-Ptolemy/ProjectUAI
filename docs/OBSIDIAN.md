# Obsidian vaults

Connect a folder in **Settings → Obsidian** to let Project UAI work with your
Markdown notes. The folder lives on the computer running UAI Bridge. Obsidian
does not need to be open, and no Obsidian plugin is required.

1. Start the updated bridge and connect UAI to Cowork.
2. Open **Settings → Obsidian** in UAI or the Cowork browser.
3. Enter a name and the folder's absolute path, then choose **Connect vault**.
4. Keep **Read-only** enabled for research. Choose **Enable editing** when you
   want to create or change notes.

An ordinary Markdown folder also works. Use the full folder path, such as
`C:/Users/you/Documents/Notes`. You can connect up to 16 vaults. Disconnecting
removes the connection and keeps every file.

## Browse and edit

In the native client, choose **Browse notes** on a connected vault. Folder and
literal text filters, paged notes, outgoing links, backlinks, note metadata and a
Markdown editor are available without opening the browser. **New note** creates
a draft; only **Save** writes it. Read-only vaults keep their editor locked.

Native note reads assemble complete UTF-8 pages bound to one revision. A failed
or unconfirmed save locks further saves until **Read current file** loads a
revision for review. **Keep draft** preserves your text against that reviewed
revision for a later explicit Save; **Use file** replaces the local draft.
Neither review action writes the note.

Closing a native note editor retains up to eight unsaved notes in memory. Use
**Recover note drafts** in the vault browser to reopen them. Drafts are not
written to executor files and do not survive unloading; save or copy them first.
The recovery store refuses a ninth draft without evicting existing edits.

The browser includes a vault selector, literal text search, paged note list, and
Markdown editor. Search covers paths and content. **Copy note** and **Download
note** use the current editor text, including unsaved drafts. **New note** accepts
a path such as `Research/Ideas.md` and creates missing parent folders on save.

Saving requires the revision that was read. If another app changes a note, UAI
keeps your draft and refuses to overwrite the newer contents. Copy or download
the draft, then **Reload note** to inspect the current file. A lost save response
also requires checking the note; writes are never automatically retried. Avoid
editing the same note in two apps at once.

## Ask the agent

- “List my connected Obsidian vaults and find notes about the project.”
- “Read `Research/Ideas.md` and summarize it with related notes.”
- “Find backlinks to `Architecture.md`.”
- “Create `Research/Meeting summary.md` using the decisions in this chat.”

The `obsidian` tool group uses normal UAI permissions: reads have read risk;
create, update and append have write risk. The vault's read-only policy also
applies. Agents cannot connect arbitrary folders or enable editing. Notes read
by the agent become part of its conversation with the selected model.

## Supported files and limits

| Feature | Behavior |
| --- | --- |
| Notes | UTF-8 Markdown, at most 1 MiB each |
| Links | Wiki links, embeds and local Markdown links; ambiguity is explicit |
| Backlinks | Resolved links; fenced and inline code are excluded |
| Metadata | Title, headings, inline tags, raw frontmatter and simple scalar properties |
| Search | Literal, case-insensitive; up to 5,000 entries and 16 MiB per pass |
| Pages | Up to 100 listing entries or 12,000 text bytes; tool budgets may be smaller |
| Excluded | Hidden folders, symlinks/junctions, hard-linked notes and non-Markdown files |

Incomplete search and metadata coverage is reported. Frontmatter is not a full
YAML interpreter; complex YAML tag collections are not extracted. Embedded
attachments are not read. UAI does not run plugins, render executable note
content, rename/delete notes, or rewrite links across a vault. Existing tools
continue to manage backups and sync.

Connections are saved on the bridge computer in `~/.project-uai/vaults.json`.
Set `UAI_VAULT_CONFIG` before starting the bridge to use a different file. Note
contents are not copied into that configuration. Agent-facing vault listings
omit absolute folder paths.

See the [API reference](OBSIDIAN_API.md) and [verification scenarios](OBSIDIAN_TESTING.md).
