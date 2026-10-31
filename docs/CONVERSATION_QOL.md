# Conversation recovery and navigation

Pin a conversation from its sidebar menu to keep it ahead of other conversations
in the same folder. Pinned histories are also preferred when loading the most
recent 64 conversations. Pinning changes navigation, not the conversation's game,
tools, permissions or execution.

Sidebar labels show new replies and failures received while no native transcript
view is visible. Opening a conversation or choosing **Mark read** clears those
counts. A hidden or minimized native window does not count a reply as read.
These badges count text events and errors, not provider tokens.

**Browse conversations** filters loaded conversations by pinned, unread, running
or draft state. Text search accepts words, quoted phrases and excluded terms.
It searches titles, folder labels, a bounded recent transcript and legacy saved
context. It does not search archived files outside the loaded conversations.

Use **Message options → Find in conversation** to search messages, replies or
errors and open the matching transcript event. **Search older** continues from
the previous page. Each pass inspects at most 1,000 events and 4 MiB, with the
first 16 KiB of each eligible event. Results disclose this clipping. Search uses
stable transcript IDs, so layout redraws do not change the destination.

## Draft recovery

Composer drafts save inside their existing conversation JSON after typing pauses
for 1.5 seconds. They follow the same history storage boundary and the conversation's
**Not saved** choice; no separate plaintext recovery file is created. This does
not add encryption to conversation history. Hosts without file storage retain
drafts only in memory.

Conversation checkpoints serialize overlapping saves. Deleting a conversation or
choosing **Not saved** also removes a checkpoint whose host write was already in
progress. Reusing a deleted conversation id waits for that write to finish.

Recovery supports up to 1 MiB of draft text and inline attachment content, and 16
attachments. Oversized drafts remain in the composer and show a copy-before-close
notice; they do not replace a previously complete recovery snapshot with truncated
text. **Draft details** shows word and byte counts and provides **Copy text**.
Restoring a draft never sends it.

New file attachments retain a SHA-256 fingerprint when cryptography is available.
Before sending or resuming restored follow-ups, UAI checks it against the current
file so a same-size edit cannot silently change the attachment. Legacy references
without a digest retain their size check. **Attachments** shows exact paths,
sizes and validation status; removing a reference keeps its file.
Large attachment hashes yield between bounded blocks and stop when their draft,
send preparation or upload is cancelled. Password hashing retains its existing
synchronous primitive interface.

Task plans and bounded notes save with the conversation. After restart, tasks
that were active are pending; completed and dropped tasks keep their state.
**Plan → Details** shows notes and lets you copy the full plan. Clearing the
conversation also clears its script workflow.
Editing Code invalidates prior workflow checks immediately. These automatic
updates save after a 0.5-second pause; explicit goal actions save immediately.

## Verification

After the required manual audit and native rebuild, focused checks are:

    luajit test/conversation_qol.lua
    luajit test/conversation_qol_ui.lua
    luajit test/conversation_checkpoint.lua
    luajit test/project_creation_lifecycle.lua
    luajit test/attachment_identity.lua
    luajit test/attachments.lua
    luajit test/conversation_folders.lua

Native Roblox rendering, touch selection and executor filesystem failures still
need host checks. Offline fixtures verify state and control behavior.
