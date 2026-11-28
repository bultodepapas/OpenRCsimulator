# Intel UHD 630 performance plan

VQ-07h-A2-R1 owns the UHD 630 investigation. PT1h-R15 and GOD own measurements, scenery/render owners own their materials, and UI-05/DT-11a own loading. Use the [roadmap](../../ROADMAP.md) for priority, the [Automatic graphics plan](automatic-graphics.md) for hardware recommendations, and the [dynamic-resolution plan](dynamic-resolution.md) for runtime scale policy.

## Lightweight first-start profile

Check actual adapter selection, the translated first-run notice, Simple/Full ground, Off/Simple/Full trees, saved overrides and restoration. Simple trees retain obstacle silhouettes and Off retains collision. Isolate a fixed scale before measuring adaptive flight. The [product-option observations](../research/god-test/2026-11-22-intel-green-club-screen.md#23-november--player-graphics-options-on-primis) cover virtual 1080p on the named device. Physical presentation, moving-aircraft readability and repeated release-route results need separate evidence.

## Starting point on main

In November 2026 PRIMIS Club Home at fixed 75% saved 9.21 ms at the median with a replacement rough-field material and 3.78 ms with trees hidden. On a separate Clear-sky circuit, 67% scale improved p95 by 10.0%. Opening draw took 6.69 s cold and 0.26 s with both shader caches reused. These measurements select view-, renderer- and cache-specific comparisons. Ground and tree ablations overlap and measure different workloads from flight. [Feature ablations and cache matrix](../research/god-test/2026-11-22-intel-green-club-screen.md)

The [historical tour](../research/god-test/2026-11-22-linux-uhd630-comparison.md) ran each aircraft once per host and lacked verified drawable/internal pixels. The [investigation](../research/god-test/2026-11-22-intel-gpu-investigation.md) and [audit](../research/god-test/2026-11-22-intel-plan-adversarial-audit.md) retain the original assumptions and sources. Freeze today's field, material and effective Home/flight scale before comparing Club and Green.

## Phase 1 · Establish the baseline (L0)

PRIMIS has since verified first-run selection in a small scene on a patched engine. Mobile/Vulkan selected 30 FPS and received a completed frame at its 85% ceiling on a 1366×768 virtual output. The Compatibility control held 75% fixed. Use the latter configuration for the Intel product comparison at 1920×1080. [First-run observations](../research/visual-quality-implementation/VQ-07/dynamic-resolution-flight-experiments-2026-11-22.md#rollout-decision)

1. **L0.1 · Select the workload.** Use the stock Ugly Stik, daylight, calm weather, the same camera, 1920×1080 output and a private profile. For the historical Automatic configuration select Compatibility/OpenGL and Low explicitly. The Linux GOD TEST renderer option `auto` resolves to Forward+. Verify the effective renderer, adapter, AA, reconstruction and scale after startup. [Tour guide](../../tools/godtest/PERFORMANCE_TOUR.md)
2. **L0.2 · Confirm what the run can measure.** Record source, engine, active native flight backend, Mesa version, cap/VSync, cache and host load. Record output, drawable and internal pixels separately, labelling unavailable dimensions. Use an admitted session for performance work. PRIMIS's normal rendered queue supports light and medium functional checks under a shared virtual display. [PRIMIS operating guide](../tools/primis-testlab.md)

**Exit.** Retain a reproducible baseline for each view. A saved scale or an unverified GPU poll can support a diagnostic note. Pixel or GPU-pass attribution needs the corresponding observation.

## Phase 2 · Locate the cost (L1)

1. **L1.1 · Compare landscapes.** Warm each Home separately before timing. Repeat the Green → Club → Green sequence airborne with the pilot camera and a matched flight window. The existing GOD TEST `green-paradise` scenario accepts either landscape for its `recover` phase. Use Home selection or the debug bridge for the parked view. Reverse the order if the difference follows the first visit. Record loading separately. [Experiment cases G0–G2](../research/god-test/2026-11-22-intel-gpu-experiments.md#green-paradise-and-club-field-isolation)
2. **L1.2 · Change one thing in the same world.** Hold Home's effective scale constant for a material test. Restore the initial state after each change and confirm that the target was active. Existing bridge masks can screen a layer. A hidden receiver may still schedule its shadow or reflection. Add a diagnostic hook only for the unresolved comparison. [Bridge GPU tools](../../tools/debug/README.md#gpu-cost-and-rewind-pt1h-r9)

| Observation | Next comparison |
| --- | --- |
| Club is consistently slower | Rank material and geometry work in the same Club scene. The default Home ablations prioritize terrain shading and trees. A lake-facing view raises the priority of cloud shading in that view. Keep water, its reflection, visible sky, the glare effect and directional light as distinct diagnostic states. |
| The affected view may be pixel-limited | Compare 75% and 67% at the same output. Keep Home and native flight results separate. Check p95/p99 and distant-aircraft readability before treating a median gain as a settings recommendation. |
| Slow frames appear only in motion or at first entry | Check live updates with advancing simulation time for motion. Use L3 for first entry. |

**Exit.** Retain the A/B/restored-A frame intervals and effective states. A landscape change also changes materials, geometry and physical layout. Select a product candidate only after a same-world comparison explains the difference. If the state failed to restore or the difference is within run variation, record the result as inconclusive.

## Phase 3 · Make one change (L2–L4)

| Subphase | Work | Exit |
| --- | --- | --- |
| **L2 · Ground** | **2.1** Compare the new Simple and Full options. Isolate base-grass anti-tiling and macro noise from parcel/photo work if the result is inconclusive. **2.2** Check turf and enabled worn-path consumers in Home, approach and night views. Preserve runway and shoreline cues, aircraft height, visible obstacles and physical contacts. | Qualify the new options against phase 4. Test saved ownership, Keep/Revert, restart and restoration of the previous material. |
| **L3 · Loading**, independently if first Home or Fly stalls | **3.1** Separate first-use and warmed runs with private Godot/Mesa caches. Time resource acquisition, model construction and first draw. **3.2** Trace the render or driver call in the cold draw near tick 391 before choosing a change. The cloud tile readback finished well before that draw. The first-use notice and Fly checkpoint receipt already ship. | Compare time to usable Home/Fly, worst blocked frame and peak memory. Check the first visible flight frame for a displaced stall. |
| **L4 · Other scene work**, if L1 points elsewhere | **4.1** Split the measured tree cost into field cards and imported tree batches. Test a reduction in render detail that preserves visible obstacles. **4.2** Use the sky-heavy view for a selective cloud or glare trial if that workload needs it. Use a two-feature interaction only when the individual tests leave a reproducible combined cost unexplained. | Keep the smallest candidate that passes phase 4. The [sixteen source investigations](../research/god-test/2026-11-22-intel-render-internals.md) provide hypotheses when a specific pass warrants inspection. |

## Phase 4 · Verify and decide (L6, then L5 if warranted)

1. **L6.1 · Measure the change.** Use the same admitted device, build inputs, renderer, route and observer settings. For steady rendering, use at least three alternating baseline/candidate pairs with 10 s warmup and 60 s sampling. Report per-run p50/p95/p99 process intervals, repeatable stalls over 50 ms, simulation/wall ratio and memory. Keep screenshot readback outside timing. Evaluate cold loading separately. [Global performance gates](global-performance-visual-quality.md#gates-to-freeze-in-vq-01c)
2. **L6.2 · Accept or stop.** Adopt a change when the gain exceeds paired variation and reaches 5% of the complete affected workload, or removes a named reproducible hitch or memory defect. Check moving aircraft, landing cues, settings restoration and 240 Hz simulation. Reject a repeatable regression. Expand to the three-aircraft tour only for a claim covering that scope. Preserve failed cases and report missing Intel utilization or physical-display evidence.
3. **L5 · Refine Automatic from measured results.** **5.1** Tie changes to the qualified device, renderer, workload and effective settings. **5.2** Apply at a safe boundary, validate the result and restore on failure. Preserve explicit choices, including a manual value equal to the default. End the slice with the manual improvement if the data supports only that scope. [Calibration and ownership](automatic-graphics.md#a5-measurement-loop-and-hardware-lab)

The external study proposes a **30 FPS usability checkpoint** for a declared steady flight window. Freeze it with the VQ/PT owners before use. Per run it calls for median ≥30 FPS, process p95 ≤40 ms, p99 ≤50 ms and simulation/wall 0.99–1.01. A gameplay stall above 50 ms recurring in two of three candidate runs fails the checkpoint. The existing 60 Hz product gate uses p95 ≤18 ms and p99 ≤25 ms. Physical presentation, pilot readability and release qualification require their own evidence.
