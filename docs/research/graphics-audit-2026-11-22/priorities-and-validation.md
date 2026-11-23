# FPS priorities, cost models and validation

This is an experiment order for source `7940a408`, not a measured speedup ranking. The [vehicle](vehicles-and-aircraft.md), [menu](menus-and-transitions.md) and [measurement](measurement-integrity.md) reports own the detailed paths and contract risks. The implementation remains unchanged.

## What to investigate first

| Order | Work | Reason | Decisive observation |
| --- | --- | --- | --- |
| Evidence gate | M01 focus eligibility and M02 phase attribution | A wrong workload or denominator can direct optimization toward the wrong operation | Correctly scoped selection intervals, initial-focus/override disposition, genuine draw/progress receipts |
| Frame work | T01 quad bus-only telemetry | Full plant forces/derivatives are computed for two electrical values | Component time removed, identical accepted-frame outputs, whole-frame/tick tails and selected backend |
| Frame work | T02 car surface-only presentation query | Normal center/wheel sampling requests unused physics walls | Calls and time by consumer, exact needed fields/refusals, unchanged physics and agreed diagnostics |
| Transition work | T03 Controls hidden-page construction and effect initialization | Large source-visible setup count on every open; new map points to the broader Controls transition | Separate constructor/configure/attach/open/first-draw and first-page-use times; node/material counts |
| Frame work | T04 flap-angle projection | Per-render advisory computation for a consumer that uses only angle | Getter/weather timings, visual angle and advisory parity for equipped aircraft |
| Smaller bounded experiments | T05 dry wet-pool fast path, T06 shared prepared quad index, T08 duplicate Theme build | Specific redundant work with a small proposed boundary | Zero-activity transitions; index identity/order; identical final theme/notifications and measured component savings |
| Conditional/lower priority | T07 ground signal payload, T09 profile-store snapshots, T10 hidden Settings report, T11 fly-by clearance | Public contracts, connected devices, small frequency or existing guards may outweigh benefit | Actual allocation/IO/callback cost and the relevant observer/device/visibility condition |

Earlier [native priorities](../graphics-audit-2026-11-21/native-priorities.md), [second-pass runtime work](../graphics-audit-2026-11-21/second-pass-runtime.md) and the [new-main disposition ledger](current-main-and-tests.md) remain relevant. In particular, the new aircraft tour did not exercise the Nitro car, its PCM synthesis, native artifact checking or companion workloads. The new small candidates must not displace a larger previously measured component solely because they are newer.

## Mathematics that constrain the upside

### Frame budget and CPU/GPU overlap

The frame budget at target rate F is `1000 / F` milliseconds:

| Target | Budget |
| --- | --- |
| 60 FPS | 16.667 ms |
| 120 FPS | 8.333 ms |
| 144 FPS | 6.944 ms |
| 240 FPS | 4.167 ms |

A first approximation for pipelined throughput is `T_frame ≈ max(T_CPU_critical, T_GPU, T_presentation_constraint)`, with synchronization and serial dependencies measured separately. Removing a CPU function can reduce power, headroom or a tail without improving GPU-limited steady FPS. A 94–96% device-utilization mean is not sufficient to select the limiting branch: it is not a per-operation trace, excludes neither background GPU work nor CPU synchronization, and is not presented-frame latency.

For a genuinely serial measured bottleneck, Amdahl's bound is `S = 1 / ((1 - p) + p/s)`, where p is the fraction affected and s is its acceleration. **Illustration, not a simulator result:** if a proposed native port covers 10% of that serial cost, even infinite acceleration caps total speedup at about 1.111×. Do not substitute a component microbenchmark's ratio for end-to-end FPS, or add CPU and GPU timings as though they were always serial.

### Work-count models from current source

| Candidate | Source-derived count | Bound and caveat |
| --- | --- | --- |
| Quad telemetry | Normally one extra full evaluation at the first read of each newly observed tick | Render cache coalesces unseen ticks; restart/invalidation can recompute at a held tick. This is not automatically another 240 evaluations/s |
| Car center + four effect wheels | Five full road queries per applicable render frame | 300 queries/s at 60 FPS or 720/s at 144 FPS are hypothetical cadence arithmetic; effects must be active, unpaused and inputs valid. Camera/shadow can add queries |
| Track wall portion of those queries | Each scans at most eight validated walls | At most 40 wall tests per five-query frame from that bounded portion; scenery bins and sorting are additional and workload-dependent. No unbounded all-scene scan is implied |
| Quad prepared obstacle index | Three P-proxy build passes and three independent cell-map/list structures | Sharing one removes two of three index-build invocations; time and memory savings remain unmeasured |
| Dry wet pools | Four wheels × eight slots, with separate water/mud ages | With all four wheel positions finite: 32 iterations / 64 age computations per applicable frame; not 64 draw calls. Existing dry branches already avoid instance transform/color uploads |
| Ground telemetry signal | Up to 240 deep-duplicate calls/s when advancing in real time | Calls do not establish how many packed buffers are physically copied. Necessary accepted-telemetry validation remains |
| Hidden Controls action rows | 37 actions × three Buttons = 111 Buttons | Their effects are pre-attached during construction and initialized on tree entry; open-time traversal is idempotent. No hidden-draw claim |
| Simulated flap visual | One full `flap_state` per executed pose-render call | Only equipped aircraft; hidden controls-guide requests are a separate conditional ~10 Hz opportunity |

The corresponding car CPU opportunity is approximately `5 × (C_full_road - C_surface_projection)` per applicable frame plus any eligible camera/shadow savings. No numerical value is assigned to either cost. Each query position and error/diagnostic behavior can differ; replacing all five with one accepted-state sample is not equivalent.

### Why the Linux slowdown matters

The [project](https://github.com/bultodepapas/OpenRCsimulator/blob/7940a4081e10994f34c858c4acac3d7a1a271464/app/project.godot#L49) uses a 240 Hz physics target and at most 12 physics steps per engine frame. If engine frame cadence F is the limiting scheduler rate, the catch-up ceiling is approximately `min(1, 12F/240)` simulated seconds per wall second. At F = 9 this is 0.45; at F = 13 it is 0.65. The new Linux screen reports roughly 0.43–0.44 and 0.63, respectively.

This is useful consistency evidence for the earlier N8 model, not proof that a particular shader, CPU function, compositor or GPU caused the low cadence. The run has incomplete drawable evidence, shared-host conditions and failed cases. Preserve the 240 Hz law and numerical contracts; improve the actual workload and measure local simulation pace alongside frames. Raising reported FPS by changing physics fidelity is not the proposed optimization.

## Native implementation choices

The preferred implementation is the smallest native or existing-engine path that removes measured cost while preserving the contract.

1. **Avoid unnecessary work before moving it.** A bus-only projection or validated flap-angle accessor can remove an entire unused calculation. Porting the complete discarded calculation to C++ would retain the unnecessary dependency.
2. **Use existing Godot facilities.** Theme, StyleBox, scene construction and MultiMesh operations already enter native engine code. Correct their ownership, count and timing first. Merely calling them from another language does not remove their engine work.
3. **Use a coarse native boundary for proven heavy math.** Existing native physics/electric-bus/render helpers are preferable to per-element cross-language calls or a new parallel framework. Batch contiguous inputs, preserve float64 arithmetic and error semantics, and measure conversion/allocation costs as part of the result.
4. **Prove the selected backend per vehicle and platform.** Aircraft-native receipts do not prove a native multirotor plant. The car body can be native on admitted Windows/Linux routes, while Nitro powertrain composition remains script; near-lake surface sampling can already use a native helper. A native request, source build or successful plugin load alone is insufficient.
5. **Preserve source identity.** Physics helper extraction can change the replay solver fingerprint; a course-source edit changes the course identity. Keep old baselines, same-source replay checks and candidate comparisons distinct. Do not hide changed identities to make an old receipt pass.

Godot's [CPU guidance](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) supports profiling the limiting work and notes that built-in engine functions share the underlying native implementation regardless of calling language; call/conversion overhead can still differ. Its [pipeline guidance](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html) distinguishes first-use Canvas/Mesh/Surface/Draw work and background specialization. Those documents are methodology, not measured evidence for this simulator's pinned `4.8.beta2.official.cafc17a19` build. Verify behavior against that engine before changing pipeline preparation or export settings.

## Platform and workload matrix

| Target | Main comparison | Extra requirement |
| --- | --- | --- |
| Windows / NVIDIA | 1080p, actual Forward+/Vulkan, fixed-wing plus electric/Nitro car and FPV drone routes | Verify each backend; compare cold/warm menu and loading; separate audible audio from muted tours and test relevant controllers |
| Windows / AMD and Intel | Same defined workloads on real adapters | The current passive utilization tool does not cover every vendor; use an admitted tracing method and mark unavailable channels rather than inferring GPU headroom |
| Linux / physical desktop GPU | 1080p, actual X11 or Wayland desktop, unlocked/focused | Distinguish a real desktop from headless Weston; no synthetic focus qualification; record driver/compositor, drawable gaps and background ownership |
| Linux / constrained integrated GPU | Same source/workload with Automatic's applied Low and a separately labelled fixed Medium experiment | The retained Medium LXC screen is not the Low default experience; keep failures and simulation-pace loss visible |
| Apple Silicon | Native Retina panel pixels as the primary gate; separately labelled external 1080p | Actual Mobile/Metal and backend identity; sustained repeats, power/thermal state, native drawable and internal rendering dimensions, actual presentation |

The fixed-wing V1 tour remains useful for its three aircraft, menus and lifecycle. It does not benchmark cars, drone racing, helicopter, airship or the planned scenic/crash V2. Use representative admitted routes for those families, retaining source/engine/native binary identities and all failures. Do not force a blanket native-only requirement on product paths that currently use reference physics.

For Mac attribution, Apple's [Game Performance / Metal trace guidance](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) provides CPU-thread, GPU-work and frame-time views. Use existing repository diagnostic/capture tools where they already expose the needed data; new instrumentation must have a measured observer cost and preserve the physical/rendering contracts.

## Paired experiment design and acceptance

Use the exact baseline and candidate with identical vehicle, route/input, seed, scenery, camera, weather, output/internal resolution, reconstruction provider, AA, VSync/cap and feature state. Record cold and warm cache policy rather than inferring it from a new process. Include first Controls subpage use so deferred work is not mistaken for a net removal. Record CPU/GPU clocks, power/thermal state and other workloads where the host supports them.

Run the owning tour's required roster and repeats without silently changing its order. For a separately declared candidate experiment, use matched within-aircraft or within-vehicle blocks and an order design that exposes warming; report the fixed roster's thermal/order confound. Three repeats are an initial screen, not a universal significance guarantee. Retain distributions, worst intervals, >16.667/33.333/50/100 ms counts, local tick-derived pace, CPU/GPU attribution and transition latency; means alone are insufficient.

Component probes answer whether the proposed path removes work. Rendered A/B runs answer whether the change improves the selected workload, tails and responsiveness. Physical presentation evidence answers what reaches the display. Keep those conclusions distinct, and require unchanged model/replay/failure semantics, visual/audio output, pause/resume and teardown. An optimization with no material whole-workload gain can still be a small cleanup, but must not be advertised as an FPS fix.

No new rendered campaign was run for this audit. Existing local source inspection and the offline reducer witness are sufficient to document these candidates; the platform checks above remain the concrete follow-up needed to qualify them.
