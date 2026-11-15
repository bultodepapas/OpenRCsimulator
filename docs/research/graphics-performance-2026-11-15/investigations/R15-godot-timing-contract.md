# R15 · Godot timing: repair ownership and sample truth before adding counters

Investigated 2026-11-15. Local research ID. Direct evidence for [M0](../05-integrated-implementation-plan.md#m0--bounded-measurement-repair).

## Question and decision

Which measurement improvements are actually necessary for OpenRC, and which have already been implemented upstream? **Repair the shared measurement owner and preserve sample validity/scope in existing reports. Verify exact engine behavior before adding a platform workaround.** In particular, an old forum answer saying Metal has no GPU timestamps is not a valid blanket rule for the pinned Godot 4.8 beta 2 Metal 3 driver.

## Sources inspected

| Source | Identity and evidence type |
| --- | --- |
| [RenderingServer timing contract](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu) and [Visual Profiler scope](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html#visual-profiler) | Official documentation checked 2026-11-15; current scope, enablement and power-state qualifications. |
| [Metal timing issue #102968](https://github.com/godotengine/godot/issues/102968) | Original 2025-02-17 report for 4.4 beta on M1; maintainer discussion and 2026-10-22 comment identifying the 4.8 fix. |
| [Metal improvement PR #121392](https://github.com/godotengine/godot/pull/121392) | Merged 2026-08-31, commit `20a52a8988b1170a53e0e04a7d71a0cb26f71656`; timing support and synchronization design. |
| [Pinned Metal 3 driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal3.cpp), [declarations](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal3.h), [query implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/metal3_objects.cpp) | Actual source inspected at OpenRC's official engine pin, `cafc17a192acf67903910a68aeb3c076c0907a4b`. |
| [Base Metal driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal.cpp) | Same pin; fallback stubs must be read with concrete-driver overrides. |

## What the investigation resolved

Godot documents viewport render CPU time as rendering work, excluding scripts and other subsystems. GPU timings require measurement enablement and describe a viewport's last result; power management can change observed durations under a cap. The visual profiler's CPU categories are not the simulator's entire CPU workload. These contracts justify retaining separately scoped process, physics and render fields. [RenderingServer](https://docs.godotengine.org/en/latest/classes/class_renderingserver.html#class-renderingserver-method-viewport-get-measured-render-time-gpu), [Visual Profiler](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html#visual-profiler).

The historical Metal issue contains useful first-hand reports, an initial limitation explanation and a later maintainer correction. PR #121392 states that GPU timestamps work with barrier synchronization. Its unrelated benchmark figures describe the author's own fixtures and hardware; they establish no OpenRC speedup. [Discussion](https://github.com/godotengine/godot/issues/102968), [merged change](https://github.com/godotengine/godot/pull/121392).

The exact beta 2 Metal 3 source confirms a concrete implementation: `_resolve_sync_mode` checks stage-boundary counter sampling in barrier mode; timestamp methods create/query a pool when supported and fall back otherwise. `metal3_objects.cpp` resolves counter timestamps and converts their timebase. The base class still contains zero-producing stubs, so inspecting it alone gives the wrong conclusion about the concrete Metal 3 path. None of this exposes a fresh sample's frame identity to OpenRC automatically. [Driver](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/rendering_device_driver_metal3.cpp), [query implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/metal/metal3_objects.cpp).

## Fit to OpenRC

Two current consumers independently write the same rendering-server measurement flag: [`frame_diagnostics.gd`](../../../../app/render/frame_diagnostics.gd) and [`render_probe.gd`](../../../../app/debug/render_probe.gd). Add one viewport-lifetime-aware lease owner through those existing consumers. Repeated acquire/release and either stop order must leave the remaining consumer enabled; freeing a viewport must retire its entries without retaining the node or touching a recycled RID.

Extend the existing sample/report contract with explicit status, scope, polling sequence and configuration generation. A **polling sequence is not a GPU completion sequence**. Record a completed render/sample identifier and age only when the backend actually provides that association; otherwise retain `unverified_freshness`, make adaptive operation unavailable, and continue static comparisons. Do not detect duplicate GPU work by equal numeric milliseconds: real consecutive samples can legitimately match.

Update the existing [`test_frame_diagnostics.gd`](../../../../app/tests/test_frame_diagnostics.gd), [`test_render_probe.gd`](../../../../app/tests/test_render_probe.gd), [`frame_diagnose.py`](../../../../research/performance/frame_diagnose.py) and its [tests](../../../../research/performance/test_frame_diagnose.py) for this new behavior. Existing sanitized-zero/invalid-count behavior must remain backward-readable; a new status must not silently turn an older report into valid DRS input.

## Adopt and avoid

- **Adopt:** one lease owner, idempotent teardown, typed unavailable/invalid/unverified states, exact engine/driver/synchronization identity, and one native comparison against an existing external profiler when a disagreement matters.
- **Avoid:** one new profiler per operating system, assuming all Metal timings are absent, assuming positive timing is fresh, summing stale auxiliary viewport values, interpreting an application poll as a completed frame, or adding blocking readback to satisfy a counter.

## Bounded deliverable and exit

These repairs belong inside M0's **five-engineering-day ceiling**, with existing early triage/review limits preserved. Produce a reviewed ownership fix, compatible report fields, focused failure/overlap tests and one named-host baseline decision. If trustworthy feedback needs a larger engine change, finish the ownership repair, mark that backend static-only for DRS, and move to M1 or M3. A measurement gap blocks the claim that depends on it; it does not authorize an indefinite tools project.
