# R14 · Tracy: borrow proven asynchronous timing patterns, profile only a named blocker

Investigated 2026-11-15. Local research ID. Decision input to [M0 and M1](../05-integrated-implementation-plan.md).

## Question and decision

Should OpenRC develop a new CPU/GPU profiler to understand scale-change hitches? **No.** The project already has frame collectors and reversible render ablations. Tracy is a mature optional attribution tool when those observations leave one concrete engine-level question unresolved. Its asynchronous query handling is useful design evidence; installing or embedding it everywhere is not a prerequisite for implementing graphics improvements.

## Sources inspected

| Source | Identity and evidence type |
| --- | --- |
| [Tracy project](https://github.com/wolfpld/tracy/blob/aa5240ca19dd4978784b76f769f067cdda647615/README.md) | Original repository, commit `aa5240ca19dd4978784b76f769f067cdda647615`, committed 2026-11-14; profiler capabilities and official manual link. |
| [Vulkan instrumentation implementation](https://github.com/wolfpld/tracy/blob/aa5240ca19dd4978784b76f769f067cdda647615/public/tracy/TracyVulkan.hpp) | Exact code inspected, especially `VkCtx::Collect`, query allocation, context initialization and timestamp calibration. |
| [Godot profiler guidance](https://docs.godotengine.org/en/latest/tutorials/scripting/debug/the_profiler.html) | Official documentation inspected 2026-11-15; profiling scope and overhead. `latest` is mutable, not the application's engine pin. |
| [Godot rendering timing discussion #97473](https://github.com/godotengine/godot/issues/97473) | Original reporter/maintainer discussion, opened 2024-09-26; version 4.3, still open when checked. A historical discrepancy report, not proof of the same defect in 4.8 beta 2. |
| [Godot optimization guidance](https://docs.godotengine.org/en/latest/tutorials/performance/general_optimization.html) | Official recommendation to identify a bottleneck and use appropriate existing CPU/GPU tools. |

## What the implementation teaches

Tracy supports CPU and multiple graphics APIs, including Vulkan and Metal, with existing viewers and trace formats. That removes the rationale for writing another general timeline viewer for this audit. Tool capability alone does not establish a ready-made integration in OpenRC's exact Godot build. [Project documentation](https://github.com/wolfpld/tracy/blob/aa5240ca19dd4978784b76f769f067cdda647615/README.md).

The inspected Vulkan collector reads timestamp results with availability bits, stops at unfinished queries and retains outstanding work for a later collection. It keeps query/context identities and optionally calibrates clock domains. Its initialization path also contains synchronization; it is incorrect to describe the entire library as having no waits. The transferable idea is to avoid forcing pending results to complete in the normal measurement loop. This is not permission to copy Tracy's internal query pool into Godot. [Exact implementation](https://github.com/wolfpld/tracy/blob/aa5240ca19dd4978784b76f769f067cdda647615/public/tracy/TracyVulkan.hpp).

In Godot issue #97473, the author placed Tracy zones alongside engine rendering timestamps and reported different CPU durations in a custom 4.3 build. The discussion offers a concrete comparison method, but no demonstrated reproduction on OpenRC's pin. Treat it as a reason to check scope/clock/placement when numbers disagree, not as a license to replace every engine metric. [Original discussion](https://github.com/godotengine/godot/issues/97473).

## Fit to OpenRC

Start with [`render_probe.gd`](../../../../app/debug/render_probe.gd), whose existing `@half_res`, `@subviewports`, shadows and other ablations can isolate a candidate cost. Use [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd) and [`frame_diagnose.py`](../../../../research/performance/frame_diagnose.py) to retain complete-run and scope context. These are the owned entrypoints; their current explicit uncertainty labels are valuable and must survive the repair.

If a repeatable scale transition remains unexplained, instrument only the existing reconstruction apply and engine buffer configuration path in an isolated diagnostic build. The question is whether the hitch comes from CPU resource creation, synchronization, first-use work or reconstruction history. That answer selects a specific change to [`reconstruction.gd`](../../../../app/render/reconstruction.gd) or the maintained native patch stack. A trace must name the source-identical control and changed build; an instrumented editor cannot qualify an uninstrumented export.

## Adopt and avoid

- **Adopt:** delayed, identity-bearing GPU observations; narrow named zones; a matched trace and an uncaptured control; existing free viewer/export facilities; deletion or disabling of diagnostic-only instrumentation after the question is answered.
- **Avoid:** a new profiling transport/viewer, allocating or formatting diagnostic payloads every simulation tick, `wait_for_gpu` to make counters look fresh, adding Tracy as a production dependency during M0, or treating a trace screenshot as a performance qualification.

No graphics diagnostic may mutate the 240 Hz float64 simulation or depend on slowing it down. CPU callback duration and GPU work can overlap, so adding their totals is not a valid universal frame-time formula.

## Bounded deliverable and exit

Tracy adoption is **conditional**, outside M0's mandatory repairs. If a named blocker needs it, allow at most **one engineering day of additional attribution work** within that feature's reviewed scope. Deliver one annotated existing-tool trace, a supported cause or an explicitly inconclusive result, and the next product change or defer decision. The budget is a review limit, not a promise that integration will be possible.

Stop when the proposed change has a discriminating test. If obtaining a trace requires maintaining a new engine subsystem, retain the current option and defer the candidate. Do not lower correctness gates or keep improving the profiler as a substitute for delivering the feature.
