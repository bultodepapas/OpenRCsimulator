# R13 · PresentMon: reuse presentation evidence without building another collector

Investigated 2026-11-15. Local research ID, not a new project track. Decision input to [M0 and M3](../05-integrated-implementation-plan.md).

## Question and decision

Can an existing free tool supply the Windows presentation observations missing from OpenRC's viewport timer? **Yes, as an external, versioned capture with explicitly checked fields.** Reuse PresentMon where it works for the exact Vulkan package. Do not integrate its service or build an overlay merely to collect a qualification receipt, and do not call its mouse/keyboard fields physical RC-radio latency.

## Sources inspected

| Source | Identity and evidence type |
| --- | --- |
| [PresentMon README](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/README.md) | Original Intel/GameTechDev repository, commit `f50c407ad9492051f4b834d77c31c49f38f0fef0`, committed 2026-11-13; architecture and known limitations. |
| [Console capture contract](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/README-ConsoleApplication.md) | Same commit; filtering, bounded capture, CSV schema and instrumentation prerequisites. |
| [Present-event representation](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/PresentData/PresentMonTraceConsumer.hpp) | Actual code inspected: process, swapchain, completion, input and frame-type identities. |
| [Output processing](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/PresentMon/OutputThread.cpp) and [metric structures](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/PresentMon/PresentMon.hpp) | Actual code inspected: per-process/per-swapchain association, failed/lost-event handling and distinct metric fields. |

The inspected development source is not a claim that an installed release contains every field. Freeze the actual executable version/hash and inspect its help/schema before using a command from current documentation.

## What the implementation teaches

PresentMon obtains Windows presentation evidence through ETW and separates its analysis library, console, service and graphical application. Its README explicitly limits some Vulkan/OpenGL CPU and latency interpretation and warns about GPU execution accuracy under Hardware-Accelerated GPU Scheduling. Record that setting; missing precision is not repaired by renaming the column. [Architecture and limitations](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/README.md).

The console supports process filtering, a finite capture duration and CSV output. It distinguishes GPU active duration, waits, displayed duration and presentation intervals. Frame-type and application-timing fields require cooperating instrumentation; requesting an option alone does not establish reliable real/generated-frame classification. The documented input fields concern mouse/keyboard interactions. [Console contract](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/README-ConsoleApplication.md).

The code reinforces those boundaries. `PresentEvent` retains separate input, GPU-ready and presentation identities; `FrameMetrics` does not collapse PC latency into GPU busy time. `OutputThread.cpp` associates a process and swapchain before producing metrics and excludes lost/failed presents from that processing path. Consequently, a CSV's row count is not automatically a complete inventory of every attempted frame; retain capture diagnostics and dropped/lost-event evidence. [Event representation](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/PresentData/PresentMonTraceConsumer.hpp), [processing](https://github.com/GameTechDev/PresentMon/blob/f50c407ad9492051f4b834d77c31c49f38f0fef0/PresentMon/OutputThread.cpp).

## Fit to OpenRC

The [owning VQ plan already permits PresentMon](../../../plans/advanced-graphics.md#numerical-and-human-acceptance). Keep [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd) for its declared application/render context and the existing [native frame reducer](../../../../research/performance/native_summary.py) for existing receipts. Attach an external CSV, executable identity and field-availability note to the same candidate evidence. A process interval, a GPU interval and an OS display event must remain separate columns with separate clocks and scopes.

For Reflex, compare Off/On/Boost within the same [native package](../../../../tools/graphics/native/README.md). Map the target process and active swapchain after each restart. Use the [existing optical patch](../../../../app/input/latency_patch.gd) and F6 method for RC response; a software event before the display is a different endpoint. For DRS, external presentation evidence judges the result; it is not a new runtime feedback dependency.

## Adopt and avoid

- **Adopt:** bounded console capture; exact process/swapchain and tool identities; explicit unavailable metrics; dropped-frame and capture-health evidence; separate uncaptured timing controls.
- **Avoid:** a compulsory service/overlay, a replacement CSV framework, treating `GPUBusy` as universal whole-frame wall time, silently excluding dropped frames, inferring Linux/macOS support from Windows ETW, or promising radio-to-photon accuracy from mouse counters.

## Bounded deliverable and exit

Within M0's existing budget, allow **half a day** to establish one usable capture schema on the first Windows reference package. Deliver one attached CSV and a short mapping of available/unavailable fields, or record why the external capture cannot answer the question. No OpenRC code change is necessary unless an existing reducer demonstrably mishandles a required field.

Stop expanding this work when the comparison can distinguish real application intervals from available presentation intervals. If Vulkan attribution or frame classification is unsupported, keep those claims open and proceed with unaffected static-provider work. Physical RC qualification remains a separate M3 gate, not a reason to build a new general profiler.
