# Micro-goals

Micro-goals keep a user objective and small, verifiable tasks with their conversation.
Open **Micro-goals** from the app menu or Find a command. Start an objective, add
tasks with completion criteria, and keep one task active while working. Each task
has a stable ID so dependencies survive reordering.

An agent can break substantial work into micro-goals within the user's requested
scope. Clear requests still proceed directly. Every genuine question or missing
user decision uses `ask_user`, including under **Allow everything**. That permission
mode authorizes permitted tools; it does not answer questions for the user.

## Working with a plan

1. Start an objective and add small tasks describing an observable result.
2. Add prerequisite task IDs when another result must be established first.
3. Start a ready task. Record a blocker when work cannot proceed.
4. Complete an active task with the evidence that satisfies its criterion.
5. Complete the objective after every task is done.

Task states are **pending**, **active**, **blocked** and **done**. Only one task can
be active. Pending or blocked tasks can become active after all prerequisites are
done; only an active task can first become done. Blocked tasks need a reason and
completed tasks need result evidence. These records describe observations; an
evidence note alone does not establish that a game or script was tested.

Reopening a completed task resets it and its dependent tasks to pending and removes
their outdated evidence. Changing a task's text, criterion or dependencies does the
same for affected tasks. Saving an unchanged task preserves its results. Changing
the objective resets all task completion. Task order is independent of dependency
order, and a task cannot be removed while another task references it.

**Pause** and **Resume** control the planning board. They do not start inference,
stop a tool, cancel a native operation, or roll back effects. Use the client's
normal Stop control for active work. Restoring a conversation never starts a job.

Micro-goals are separate from the existing task list and `script_workflow`.
The script workflow still owns script acceptance criteria and compiler/test
receipts. A routine task does not need several duplicate plans.

## Editing and recovery

Every edit checks the board ID and revision that was read. An agent or another
view changing the plan causes a conflict instead of overwriting the newer state.
The editor keeps your fields. **Review current** shows the current plan;
**Keep draft** keeps your text against that reviewed revision, while **Use current**
loads its fields. Neither action saves. A later explicit Save checks the revision again.

One unfinished form per conversation remains in memory while the client is loaded.
Closing the board or changing appearance preserves it. **Resume form** reopens it;
**Discard form** removes it. Finish or discard that form before opening another one.
Fields retain their previous valid text when an oversized or invalid paste exceeds
their bounds. A changed build keeps the current client open until unfinished forms
are saved or discarded. Unsaved forms do not survive explicit unload.

The saved board uses the existing conversation checkpoint and executor filesystem.
Storage is best effort: ephemeral conversations, child conversations and hosts
without filesystem storage keep it only in memory. Unsupported or invalid saved
board formats skip that conversation without deleting its history file.

## Agent tools

| Tool | Behavior |
| --- | --- |
| `micro_goals_read` | Read the conversation's complete JSON planning record in UTF-8 byte pages. |
| `micro_goals_update` | Start, edit and progress the conversation's board; ordinary write permission applies. |

Read accepts optional `offset`, `limit`, `expected_id` and `expected_revision`.
The first page returns `id`, `revision`, `offset`, `nextOffset`, `totalBytes` and
`eof`. Continue with the returned byte offset and both identity fields. A stale
continuation fails; restart from the beginning after the board changes.

Every mutation of an existing board requires its observed `expected_id` and
`expected_revision`. The first start omits them, or supplies revision zero.
Only fields relevant to the selected action are accepted.

| Action | Fields and result |
| --- | --- |
| `start` | `objective`; optional `tasks`. Replaces only a completed board, with that board's expected identity/revision. |
| `objective` | `objective`; changes the objective and reopens its tasks. |
| `add` | `task = {text, criterion, id?, depends_on?}`; returns the new task ID. |
| `edit` | `id` and one or more of `text`, `criterion`, `depends_on`. |
| `status` | `id`, `status`; `evidence` for done, `blocker` for blocked. |
| `reorder` | `order`: every task ID exactly once. |
| `remove` | `id`; refuses a task referenced by dependencies. |
| `pause` / `resume` | Change active/paused planning status. |
| `complete` | Complete an active objective whose tasks are all done. |
| `clear` | Explicitly remove the board without affecting execution or other planning stores. |

Initial task definitions accept optional stable IDs and `depends_on` arrays.
Tasks begin pending; they cannot claim completion in an initial plan. Updates
return the new board ID/revision, status, counts, and a changed task ID when applicable.
`persisted` reports whether that operation completed a conversation checkpoint;
false does not discard the live board.

## State API and limits

The `agent/session` facade exposes `session.goalsSnapshot()` and
`session.updateGoals(arguments)`. Snapshots are detached. Updates return a detached
board, or false for a successful clear, or `nil, reason` for rejection. A third
result carries operation details including `taskId` and `persisted`.

`runtime/micro_goals` supplies pure `restore`, `snapshot`, `change`, `counts` and
`describe` functions. `change` has the same action arguments and returns the next
record without changing its input; false means clear. It never persists or
executes anything. `describe` produces a bounded, quoted prompt view; the agent
reads the full criteria and evidence on demand.

`ui/goals.hasDrafts()` reports unfinished form edits across live conversations,
including forms whose board has been closed. Opening an unchanged form does not
set the guard. Save, discard, removal of the conversation or unload releases it.

The version-1 record has `id`, `objective`, `status`, `revision`, `updatedAt` and
`tasks`. Tasks have `id`, `text`, `criterion`, `status`, `dependsOn`, optional
completion `evidence` and optional `blocker`.

| Bound | Maximum |
| --- | --- |
| Tasks per objective | 24 |
| Prerequisites per task | 8 |
| Board/task IDs | 64 ASCII letters, digits, underscores or hyphens |
| Objective | 2,000 UTF-8 bytes |
| Task text / criterion | 240 / 600 UTF-8 bytes |
| Evidence / blocker | 1,600 / 800 UTF-8 bytes |
| Prompt state | 2,400 bytes with an omission notice |

Dependency graphs reject cycles, duplicate or unknown prerequisites and invalid
completion. Verification uses [the external suites](DEVELOPMENT.md):
`test/micro_goals.lua` and `test/major_release_prompt.lua`. Mock UI checks cover
forms and lifecycle; they do not verify native Roblox rendering or host input.
