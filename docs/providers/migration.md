# Provider upgrades and saved access

The client retains saved providers when upgrading. An empty setup remains empty:
startup, importing an empty provider list and resetting providers do not install
Project UAI Free. Add a provider explicitly from the library.

Older releases used the HCNSEC preset for both personal and community access.
On the official endpoint, records using the exact distributed community
credential move to `projectuai-free`. Saved community references are restored
and separated in the same migration. Personal HCNSEC keys stay `hcnsec`.

Migration preserves provider IDs, active selection, custom names, saved models,
enabled state and key preferences. A legacy default label is updated to describe
the actual access type. Paused community access remains paused. Replacing an
exact retired community credential resets its accounting ID because the key
itself changed; private keys and mixed pools are not guessed or replaced.

Custom endpoints and personal authentication overrides do not become community
access merely because their label says Free. Invalid or unrecognized saved
community references cannot dispatch anonymously. Review that connection in
setup and choose the appropriate separate preset.

Migration waits for the existing credential-storage access gate and does not
send discovery or inference requests. Configuration copies reference community
access instead of exporting the distributed key. Personal credentials follow
the chosen [storage and export policy](../API_KEY_SECURITY.md).

[Project UAI Free](projectuai-free.md) · [HCNSEC](hcnsec.md) · [All provider guides](README.md)
