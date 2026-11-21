# Hardware validation and experiment plan

This is the executable research plan for the open timing questions. No row is marked completed by this audit. The host had no display, no `/dev/dri` device and no enrolled OpenRC test-pool configuration. The lead used the pinned Linux engine only for isolated policy checks. Physical Windows, Linux and Mac runs remain required.

## Target matrix

The [repository resolution policy](../../../AGENTS.md#display-resolution-priorities) makes **1920×1080 the first desktop target**, except **Apple Silicon Retina, where the actual native panel/drawable is first**. Higher-resolution desktop tests follow; 720p is supplementary. Record the window, logical UI, acquired drawable and effective internal 3D dimensions separately.

| Target class | First renderer/workload comparisons | Required control | Questions it resolves |
| --- | --- | --- | --- |
| Windows x86_64, lower/midrange Intel or AMD integrated GPU | Actual Automatic; explicitly matched Compatibility/Mobile/Forward+ where supported; native AA vs supported reconstruction | Current release on physical display, same driver/power/scene | Whether heuristic choices and GPU timing classification are appropriate; water/sky/bandwidth limits |
| Windows x86_64, NVIDIA and AMD discrete GPU | 1080p first, then named high-resolution/high-refresh display; supported APIs; 0–3 companions | Actual player and each agent backend, current package hashes | CPU/observer ceiling versus fill/pass cost; presented-frame pacing; native opportunity |
| Linux x86_64, Intel/AMD Mesa and NVIDIA | 1080p on physical display; Compatibility and supported Vulkan methods; record X11/Wayland/compositor | Native driver, no llvmpipe/lavapipe; current source/release identity | Driver/renderer ordering, screen/depth costs, cold shader stalls and compositor effects |
| macOS Apple Silicon, fanless M1 baseline and a newer actively cooled machine | Native panel pixels first; Mobile/Metal and qualified alternatives; explicit actual reconstruction/fallback | Public reference package versus separately identified experimental native package/source; thermally stable and long-run samples | Tile timing bias, bandwidth, thermal drift, retained resource costs and current native admission |
| macOS Intel / x86_64 process | Supported public renderer/package, native output and 1080p secondary where applicable | Verify process architecture and reference physics; do not infer ARM native through Rosetta | Older-driver and fallback usability; architecture-specific packaging |

These are target classes, not a claim that every combination is already supported or that buying every device is necessary. Start with available representative hosts, retain the exact GPU/CPU/driver, then broaden only after a shared change passes. A single discrete GPU cannot validate all integrated GPUs, and two Apple devices cannot validate every Retina/thermal configuration. The archived three.js CI prototype is separate from current Godot desktop qualification.

## Prepare one trustworthy baseline per host

1. Freeze a clean current commit and the exact engine/native libraries/package. Resolve the source preflight before labeling a full app build qualified. Preserve the audit's original SHA separately from any later repaired baseline.
2. Follow [test admission](../../../tools/testqueue/README.md) and [shared tool rules](../../tools/shared.md); use the host's existing resource owner. Stop competing captures, engines and remote sessions for a timing comparison, without altering a shared machine's policy. Record power source, governor/mode, clocks, thermals, available memory and background load.
3. Use an isolated snapshot/profile as specified by the [graphics ladder](../../../research/performance/graphics_ladder/README.md). Retain saved and effective settings. On Windows verify source-byte/native-receipt consistency rather than assuming a newly checked-out tree still admits native. Do not rename the production project or erase the player's cache/profile for an experiment.
4. Run the owning checked import and targeted correctness gates. Verify the actual renderer/API, process architecture, output/drawable/internal sizes, AA/scaling provider and native admission/refusal reason. For a fleet, record every agent, not only `flight.physics_backend.kind` for the player.
5. Create fresh result paths and a manifest. Record cold process versus warm process, import cache, shader/driver cache and content cache as separate conditions. A fresh process with a warm driver cache is not a fully cold shader run.

## Minimum scene and transition set

| Scenario | Variants that matter | Findings exercised |
| --- | --- | --- |
| Home → Fly loading | 0, 2 and 5 s Home dwell; five fresh-process and five warm repetitions; first visible feedback and first controlled frame | R2–R5, N5; cold construction/readback versus later stalls |
| Ordinary flight | Actual Automatic and explicit matched settings; sky-heavy and ground-heavy pilot/chase views; stock Club and other selected landscapes | R6–R9, C1–C6; full application observers |
| Runway / taxi / departure / touchdown | Airborne, previous-contact-to-clear transition, raised circuit, lake/water boundary | N3; observer parity and same-tick caching eligibility |
| Companions | 0, 1, 2, 3; same initial conditions, all visible and offscreen; native/ref identity per session | N2; complete callback scaling and unsupported domains |
| Ground vehicles | Nitro MONSTER CAR 2 versus electric MT8 control; reference and optional native body; actual packaged scripts | N1; identity guard versus solver cost |
| Cloud edits and cache lifecycle | Cold default, repeated same seed, new seed, full cache, fast paused edits, cancellation/reentry | R5; correlate bake/readback/convert/upload completion with frame gaps |
| Disabled-resource lifecycle | Meadow Off at build; On → Off preview → cancel/keep → On; shadows Off/Native/Projected; retained Workshop world | R1/R4; node ownership versus shared cache and transient targets |
| First-use effects | First and repeated crash/wreck, fire/smoke, night, headlights/lens, MSAA/provider change | Pipeline compilation versus content creation versus sustained cost |
| Extra views | Magnifier hidden/visible; planar reflection **only when deliberately enabled** | R10/C4; root-only timings versus full frame |
| Sustained operation | Representative thermal soak, settings/reentry cycles and a bounded long stream | N7; memory growth, incomplete capture, thermal and pacing drift |

Do not call a command-line scripted route the Home → Fly settings route: the existing graphics ladder explicitly distinguishes them. Its current effective-setting check also does not prove every reconstruction provider's GPU execution; corroborate the selected scaling mode and fallback through the platform trace. Follow the owning scenario's longer protocol where present. In particular, fleet qualification retains three 120-second foreground runs after 30 seconds warmup and a 20-minute soak in the [AFC plan](../../plans/ai-flight-companions.md#phase-6--busy-skies-and-measured-scaling).

## Matched experiment design

Use at least three alternating paired steady runs for an initial comparison, with the same seed, inputs, route, observers, camera, scene, output and effective settings. A reasonable screening minimum is 10 s warmup plus 60 s sample; longer owning gates such as AFC override it. Alternate AB/BA or otherwise balance order, and retain a repeating reference to expose thermal/cache drift. For cold construction retain at least five process-cold and five warm samples and the maximum loading gap, not only mean launch duration.

Change one mechanism at a time, then test the combined candidate. A cumulative settings ladder measures each option's marginal effect after earlier options; it is not automatically its standalone cost. Keep both uncapped throughput and a named pacing target with VSync/VRR/cap recorded. Uncapped, VSync-enabled and platform-present traces answer different questions. Do not discard a failed, throttled or incomplete run; annotate it and decide explicitly whether it belongs in a different condition.

Report paired absolute milliseconds, percentage change, paired spread/interval, sample counts and all completeness reasons. Three pairs are an initial screen, not a guarantee of statistical precision; add runs only if variance prevents a decision. A candidate is useful when the repeated end-to-end or tail benefit exceeds variation without moving the stall to startup, first flight, a new effect, or another supported route. Set the product's absolute pacing target explicitly; C5 explains why current 60 Hz policy is not a 120 Hz promise.

## Three timing layers and their instruments

| Layer | Primary question | Instrument / limitation |
| --- | --- | --- |
| CPU / engine callback | Which complete tick, observer, allocation, file operation or scene phase blocks progress? | Existing debug bridge, session-watch/frame streams, native CPU profiler and targeted spans; `step_usec` is partial/smoothed and detached session probes omit product attachments |
| GPU work | Which pass, buffer transfer, shader, resolve, viewport or barrier consumes GPU time? | Supported native GPU profiler; root viewport polling alone has freshness/scope limitations and is not a full display frame |
| Presentation | When do completed images reach the presentation path/display, and what pacing is visible? | OS/API-supported presentation trace, monitor and compositor identity; process FPS and `get_frames_drawn` cannot substitute |

**Windows:** use [PresentMon's own definitions and API limitations](https://github.com/GameTechDev/PresentMon/blob/main/README.md) for supported display/CPU/GPU events. OpenGL/Vulkan frequently report a less-instrumented runtime; some CPU pacing and derived latency fields are limited. Record capture version, HWS state and unavailable fields. For NVIDIA GPU attribution, [Nsight Graphics](https://developer.nvidia.com/nsight-graphics) supports relevant Vulkan/OpenGL routes subject to the installed version and hardware. For supported AMD Vulkan devices use [RGP](https://gpuopen.com/manuals/rgp_manual/); it does not profile the Compatibility/OpenGL path. A GPU trace is not input-to-photon measurement.

**Linux:** pair native CPU and compositor-appropriate presentation evidence with a GPU profiler that supports the actual GPU/API. The [RGP manual](https://gpuopen.com/manuals/rgp_manual/) distinguishes its Linux Vulkan capture paths and driver requirements; newer RADV capture is not identical to the old Developer Panel route. Do not change a player's driver just to fit a profiler or extrapolate a Vulkan result to OpenGL. If presentation events cannot be obtained on the chosen compositor, mark them unavailable and keep CPU/GPU results separately scoped. The retained UHD 630 headless-Weston test supplies a renderer comparison for that setup, not panel/VSync qualification.

**macOS:** use [Metal HUD logging](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) and a targeted Xcode/Instruments capture. For an experiment process, Apple documents `MTL_HUD_ENABLED=1` plus `MTL_HUD_LOG_ENABLED=1`; shader logging is separately available. [HUD metric definitions](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) distinguish command-buffer GPU time, drawable frame interval, present delay, layer size, thermals and Rosetta. Encoder timing adds detail and overhead and may conflict with other counter-buffer use. Use an instrumented/uninstrumented control; do not turn on every probe for the headline measurement. Record native panel/layer/internal pixels and verify actual MetalFX fields when applicable.

Tools and versions must be checked on the target before use. None of these profilers ran in this audit. The sources establish a method, not an OpenRC result.

## Specific acceptance evidence

| Proposed change | Evidence required before keeping it |
| --- | --- |
| Calibration identity/restart | Same-workload reuse, AA/size/provider changes, fallback, pause-without-change, changed-then-reverted preview, guard/explicit mode, no restart loop; then actual UI/native run |
| Nitro guard redesign | Same-size/same-mtime edits, deletion/recreation, unreadable/remapped source, mid-session mutation/revert, package identity and checkpoint/replay refusal; current component and full-session cost |
| Native companion admission | Per-agent actual stage/context calls, refusal/domain coverage, identical ordered accepted states/events/fault behavior, player/fleet timing and presentation; ORFL alone is not complete fleet replay |
| Contact/audio reuse | Exact same accepted state/time, spatial versus datum semantics, liftoff/end contacts, failure/restore/reset and mutated configuration; matching event/statistics/audio records |
| Cloud publication or geometry staging | Cancellation, bounded ownership, stable published texture/geometry, wrong/late result refusal, first controlled frame, native visual parity and actual hitch reduction |
| Reduced sky/water/grass or independent effects | Corresponding area captures and motion inspection, silhouettes/horizon/shoreline/reflections, same physical trace/collision inventory, and pass plus full-frame timing |
| Asynchronous diagnostics | Bounded immutable handoff, ordered chunks, writer failure/backpressure, finish/cancellation, sequence/checksum completeness, on/off perturbation and end-to-end tail evidence |

## Required result manifest

Retain source and dirty state; engine/library/package digests; OS/CPU/GPU/driver; process architecture; renderer/API; panel/refresh/compositor/present mode; output/drawable/internal pixels and actual provider/AA; physics backend and refusal per vehicle; configuration/seed/input/camera; warmup/sample boundaries; power/thermal/competing activity; instrumentation and write costs; CPU/GPU/presentation scope; raw bounded samples; sim/wall and ticks; p50/p95/p99/max; stutter counts/episodes; memory ownership; crash/fault/completeness; and paired analysis. This is the minimum context needed to decide whether a claimed gain transfers to another machine.
