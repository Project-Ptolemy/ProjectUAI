# Script startup

The native script shows a compact loading card near the bottom of the screen.
It appears after the downloaded bundle begins executing; it cannot show progress
for the HTTP download or parsing that happens before execution.

The three markers are real startup boundaries:

| Stage | Work |
| --- | --- |
| Prepare | Read configuration, prepare tools and providers |
| Restore | Migrate older workspace files and restore saved conversations |
| Open | Build the interface and finish runtime initialization |

The component count reports completed module loads. It is separate from the stage
markers because some modules load only when their feature opens. There is no
estimated overall percentage. File migration reports the actual moved count.

Elapsed time updates while startup yields to the host. If no progress is reported
for eight seconds, the card explains that the step is taking longer. This does
not time out or replay startup. An unresponsive native host operation may also
prevent the screen from repainting until that operation returns.

Successful startup marks all stages complete and dismisses the card after a short
pause. Failure stops the activity animation and retains its stage with executor
console guidance until **Close notice** is selected. Raw host exceptions stay in
the console. Close only dismisses the notice; it does not rerun the script.

The card uses a frame-drawn mark and no external images. Its pulse, frame listener,
layout connections and delayed exit belong to its lifetime. Unload or explicit
destruction releases them. `context.ui = false` retains its existing hidden-boot
contract and does not create this card.

`test/boot_progress.lua` covers stage order, lazy module counts, elapsed time,
slow-state recovery, failure, narrow width and lifecycle. The main client harness
checks the bundled startup path. Browser previews approximate the layout;
native Roblox rendering and executor startup latency require a device check.
