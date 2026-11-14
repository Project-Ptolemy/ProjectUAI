# UI mod examples

These version-1 portable JSON definitions are reviewed examples for Project UAI
4.0.0. Importing them creates disabled records. Inspect the full definition/source,
then explicitly Apply its current revision under normal tool permissions.

- [Project workbench](project-workbench.json) is a visual appearance/panel example
  with aggregate metrics and fixed native navigation.
- [Native lifecycle marker](native-lifecycle-marker.json) is a scripted example
  with full native context. It sets an attribute on the actual root and returns
  guarded cleanup for remount/disable. It demonstrates the source/factory and
  owned-lifetime contracts, with no claimed native or in-game verification.

`catalog.json` lists these authored examples. They are not automatically
installed or activated. There is no source loader or network dependency in the
examples. Read [UI mods](../docs/UI_MODS.md) for schema, sharing, source access and
cleanup limits. Review example changes before building and running the focused
offline checks; do not claim their output verifies native rendering.
