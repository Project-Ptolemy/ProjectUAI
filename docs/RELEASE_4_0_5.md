# Project UAI 4.0.5

November 15, 2026. Client, bridge package and Windows desktop use **4.0.5**.
UI LIB remains **1.6.0**, embedding SDK **1.1.0**, and Android companion **3.7.2**.

Accepted bridge inference now keeps its verified connection identity through
failed background discovery probes. Previously, a two-second discovery failure
cleared the credentials and caused the running agent to show Stopped. Automatically
routed Free requests had a related health comparison that could cancel accepted
work. New work still follows current availability; accepted work polls its original
job. Stop, disconnect, opt-out, changed credentials and terminal provider failures
keep their cancellation behavior. Uncertain inference is never replayed.

Kilo model discovery requests plain JSON by default. The public catalog can return
Brotli when a host advertises compression without decoding it, causing a JSON
parse failure. Explicit custom headers remain effective; compressed or unexpected
responses now receive a useful fixed diagnostic and never enter the model cache.

Long conversations do less repeated token estimation and Markdown work. Cowork
defers closed reasoning content and replays transcript snapshots in bounded
batches, keeping input responsive while history appears. History and model context
retain their existing storage and compaction contracts. Provider upload, prefill
and generation time still depend on the chosen model and host.

Script mods gain a supported **`context:CreatePanel`** API for native workspace
sections, controls, values and callbacks. UAI supplies theme, sizing and rendering;
the mod supplies its domain behavior. Panels and callbacks belong to the mod's
lifetime and survive normal UI remounts. New script templates create a real panel;
the reviewed native workbench example includes editable notes and project actions.
See [UI mods](UI_MODS.md).

Handheld sizing now follows device identity independently of layout. A phone
reporting a synthetic mouse, changing orientation or using explicit Window layout
keeps the compact metrics. Previously it could switch from the 55% handheld scale
to full desktop dimensions, an approximately 82% increase. Native keyboard/pointer
touchscreen desktops preserve desktop sizing. Provider setup yields optional outer
spacing to keep its notice and typing row inside short keyboard bounds.

Agent settings add **UAI, Femboy, Catboy, Gremlin, Tsundere, Goth, Drill Sergeant,
Evil Genius and Brainrot** personas with example replies. These change speaking
style while retaining custom instructions, reply language and tool permissions.
Main and delegated system instructions include the UAI adaptation of
[Ponytail](https://github.com/DietrichGebert/ponytail): make the smallest complete
change, reuse shared components, inspect affected callers and verify the result.
See [agent voice](AGENT_VOICE.md) for choices and provenance.

Build and verification outcomes are recorded in [4.0.5 testing](TESTING_4.0.5.md).
Offline behavior and compiler checks do not establish native Roblox rendering,
executor input behavior or live model performance.
