# Organize, find and export conversations

## Folders and navigation

Use **New conversation** to choose a title and destination. A conversation's menu
offers **Rename**, **Move to folder**, **Export Markdown** and **Delete**. The app
menu provides these actions when the sidebar is unavailable. **Conversation folders**
creates, renames and removes custom folders.

Moving a chat changes its organization, preserving its game context, provider
history and tool policy. Removing a custom folder preserves its conversations;
they resolve to Universal. Deleting a conversation removes its saved transcript
and is a separate explicit action.

## Search retained dialogue

Use **Search conversations**, or **Ctrl+Shift+P** while not typing. It matches a
case-insensitive literal in titles, folder names, retained messages and replies.
Results show where the match occurred and a short excerpt. **Show more** reveals
the next 12 results; a new query starts again at the first page.

Search covers currently loaded conversations, not every archived file. UAI restores
the newest 64 saved conversations; older files remain on disk. Model compaction
does not automatically remove retained transcript dialogue. History limits can
remove older content, and search cannot reconstruct bytes no longer retained.
System instructions and tool-result context are not presented as ordinary replies.

## Keep a Markdown copy

Choose **Export conversation** in the app menu, **Export Markdown** in a conversation
menu, or find the export command with **Ctrl+K**. The dialog freezes a snapshot of
retained dialogue when opened, so an incoming reply cannot change what you export.

Review the preview, then use **Copy Markdown** or **Save Markdown**. Saving creates
a unique file under `UAI/export/` and verifies its contents before reporting its
path. A failed save can be retried; repeated clicks after success reuse the receipt.
Clipboard and file actions appear only when the executor supports them.

The export includes user messages and completed assistant text. It excludes hidden
reasoning, tool arguments/results and request metadata. Personal text in messages
is still personal text: review it before sharing. Exports stop between whole
messages at 1 MiB and disclose omissions; the preview itself shows at most 12,000 bytes.
Exports are readable Markdown, independent of credential-vault encryption.

## Reading and follow-ups

Scrolling upward releases automatic following. The **Latest** control returns to
new replies; resizing and changing panels retain reading position where possible.
**Refresh conversation** redraws the view without changing the conversation or draft.

Follow-ups can queue while a response is running. Queue edits, reordering and removal
do not interrupt active inference. **Stop** remains the action for cancelling work.
See the [native client reference](NATIVE_CLIENT.md) for retention and lifecycle details.
