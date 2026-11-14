# Master Vault starter collection

These Markdown recipes ship as read-only references in Project UAI 4.0.0. They
document supported workflows and provide templates for real findings; they do
not contain invented game-specific remotes, arguments or anti-cheat guarantees.

Open **Master Vault** in UAI to read a recipe or copy it into a user note. User
notes live under `UAI/vault/notes/` in the executor workspace and survive client
updates. Scope them to a game or project when their evidence applies there.

`catalog.json` defines the stable starter order. Each listed file uses the
frontmatter described in [Master Vault](../docs/MASTER_VAULT.md), identifies its
sources, and attributes any verification claim. `tools/build_master_vault.lua`
validates and embeds the collection during the client build. Do not edit the
generated `src/runtime/master_vault_seed.lua` directly.

Contributions should include the concrete problem, required capabilities, a
small reusable approach, checks that would establish success, and the limits of
that evidence. Review source and examples before building; inspect the generated
collection before running its focused verification.
