# Agent voice and Ponytail

Choose **Settings → Agent → Persona** in Roblox, or **Settings → Agent** in
Cowork. The picker includes a description and sample reply for each voice:

| Voice | Delivery |
| --- | --- |
| UAI | Clear, calm and direct; the default. |
| Femboy | Cheeky confidence, cute wording and an occasional uwu. |
| Catboy | Smug keyboard cat with an occasional nya. |
| Gremlin | Scrappy bug goblin who enjoys deleting bloat. |
| Tsundere | Mock grumpy rival who still gets the work done. |
| Goth | Deadpan midnight engineer with dry humor. |
| Drill Sergeant | Short, decisive target/action/result delivery. |
| Evil Genius | Cartoon mastermind with one dramatic flourish. |
| Brainrot | Terminally online slang kept short and readable. |

`agent.persona` stores the exact selected ID. It applies to the next model
request, including delegated agents. Changing it preserves conversation history,
drafts and permission rules. Custom instructions and reply language remain in
effect; persona wording changes neither model identity nor tool arguments.
Public `chat_agent` workers retain their separate operator instructions.
Actual wording depends on the selected model.

Ponytail's smallest-complete-change workflow is included in the main and delegated
system instructions. Agents inspect callers and affected configuration, fix the
shared cause, reuse UAI components, preserve validation and cleanup, and finish
every requested deliverable. They review source, build, inspect output and then
run focused verification. Brief replies include observed outcomes and material
unchecked limits.

This is a UAI adaptation of [Ponytail](https://github.com/DietrichGebert/ponytail),
based on [the base skill at revision
96608e0](https://github.com/DietrichGebert/ponytail/blob/96608e078b2d5ea607c5c3b8b5a54d1c1fba6846/skills/ponytail/SKILL.md),
reviewed November 15, 2026. UAI's tools, Luau conventions, lifecycle ownership,
UI LIB and build order take precedence. The adaptation ships as local prompt
text and performs no runtime download or hook installation. Its MIT copyright
and permission notice are retained in `src/agent/ponytail.lua` and therefore in
the generated client bundle.
