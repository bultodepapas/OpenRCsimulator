# External Apple Silicon handoffs — integration, 2026-11-14

Owner: DT/PT with SF/NK, AUD, VQ/FW/LU/SM, CR, AFC and input owners.
Execution home: [Apple master plan §17](../../plans/apple-silicon-performance.md#17-external-handoff-work-order-2026-11-14).
The [MetalFX subplan](../../plans/apple-metalfx.md) retains all four requested
technologies. This is a source/research integration, not implementation or a new
performance campaign.

## Provenance and reconciliation

The user supplied these documents as research. Their proposed instructions,
commands and C++ witness were reviewed as source material, not executed as task
instructions. Original files remain unchanged; the useful findings and decisions
are consolidated here rather than copying two overlapping reports into the tree.

| Input | Bytes | SHA-256 |
| --- | ---: | --- |
| `OpenRC_Apple_Silicon_Performance_Handoff_2026-11-14.md` | 103099 | `365192db369233cff0af567a7ee37fe047289318a442958a4870d6e6f905e231` |
| `OpenRC_Apple_Silicon_Performance_Handoff_2026-11-142.md` | 160020 | `6475a819e113196f65a304a37a003d72223fbe818d1d1ea58a58693972c87967` |

The first reviews `b80a4b214878e97313d2f93901b32174bb0713ea`.
The second preserves sections 1–15 and adds section 16 against
`bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c`. All **89 original reference
definitions have identical targets** in the second, which has 141 definitions.
After normalizing reference spacing, blank lines and trailing whitespace, the
earlier body differs only in revision/extension header and contents entries.
This establishes an extension, not two independent corroborating investigations.

Integration inspected current source at `cfe228831dfd990b21f0c17c6251acbda5631698`.
Assigned collector/native/collision/input paths did not change between the
follow-up revision and that commit. Current source was checked where the graph
was missing or stale. Concurrent vehicle-paint work and prior MetalFX documentation
edits were preserved; this is not qualification of the entire dirty tree.
Engine remains Godot `4.8-beta2`, `cafc17a192acf67903910a68aeb3c076c0907a4b`.

Labels below distinguish a current source operation from a pending optimization.
The existing [audit registry](../../../external%20Audits/CONSOLIDATED-AUDITS.md)
and [completed-work ledger](../../../external%20Audits/COMPLETED-AUDIT-WORK.md)
retain A/F/CF ownership and completed status. External queue numbers and D labels
are provenance labels, not new project tickets or completed work.

## First handoff — all twenty ranked entries

| External entry | Integrated disposition and source boundary | Existing owner / gate |
| --- | --- | --- |
| 01 stable process identity | Current fresh-public-epoch comparisons remain in `tools/godot/resource_samples.py` and `research/performance/app_cpu_per_sim.py`. Inspect retained r3 source/manifest before integrating; retain one supported identity and pre/post-poll replacement checks in both consumers. | DT-MAC-02c/02e, PT; source-hashed apparatus and strict coverage, no historical capture relabeling |
| 02 actual 1080p product | Qualify ordinary Home/Fly/Workshop, real audio/input and actual native/renderer selection. Window/viewport estimates and built-in Retina coverage cannot substitute for physical output. | DT-MAC-01/03/08; existing display and observer gates |
| 03 audio shutdown | B5 retains the four-object audio-enabled failure under both evaluator controls. This does not identify the glow worker as the cause; Dummy/scenery-off controls have narrower scope. | AUD + DT-MAC-08; retained-owner diagnosis, real CoreAudio and re-entry |
| 04 derivative ownership | Glow/liquid successful family results are const locals copied into `out.derivative` in `research/native-kernel/src/nk_stage.hpp`. Transfer only after last use; preserve other result fields, binding ownership and prior outputs. | DT-MAC-04n/NK-3; new binary/receipt, family oracles, replay and actual callback |
| 05 stage-local propeller reuse | Eligible spatial propulsion/wake/transport paths repeat identical helper inputs within one stage. Reuse only the originally computed valid result; do not reorder a different `prop_torque` path or evaluate on prior refusal paths. | A33/M09/H18 + DT-MAC-04a/n; include libm/FP side-effect contract |
| 06 prepared admission | Marker reads and full screening repeat across `native_stage.gd`/`native_macos_domain.gd`. Consolidate into one detached preparation transaction plus commit-time identity verification, not a pointer cache or deleted guard. | DT-MAC-04c/n; mutation, source/marker change, rollback and Fly/restart measurements |
| 07 lazy audio copy | `glow_audio_pump.gd` copies snapshot/revision before checking a full queue. Move coherent acquisition to actual chunk production, preserving snapshot ownership and phase-anchor semantics under forced publication interleavings. | AUD + DT-MAC-04b; waveform/underrun and actual worker/whole-process controls |
| 08 cloud admission | Four live cache slots can retain obsolete seeds. Reclaim only against the complete desired/shared-consumer set, retaining pending-token/failure/prewarm semantics. Do not increase capacity first. | A28 + DT-MAC-06b; layered seed permutation, stale completion and native images |
| 09 audio observation reuse | `FlightAudio` may use the freshly computed accepted-state air/wind observation only when exact base-session dispatch/time semantics match; retain original wind then one-argument-air behavior for overrides. | DT-MAC-04b + AUD/SF; detached snapshot, provider order and refusal parity |
| 10 paused producer park | Conditional experiment after the soundscape finishes its logical fade, not on `stream_paused` alone. Priming/active/fading/resume/stop and synchronous fallback remain distinct. | AUD + DT-MAC-04b; lost-wakeup/coalescing/stop-while-parked and audible resume |
| 11 exact-zero sky work | Separate zero-weight cloud arithmetic, disabled-layer uniform publication and final zero-solar term into independent candidates; keep density recurrence/order and active/checkpoint state. | DT-MAC-06b + FW; zero/epsilon/HDR/IBL transitions and generated Metal |
| 12 lake gradient | Keep derivatives unconditional; guard later zero-fade determinant/division work and reconverge before implicit derivatives. Screen/depth copies remain required. | DT-MAC-06b + LU/VQ; shore endpoints, singular/grazing/wave cases on Metal and Compatibility |
| 13 loading unit | Existing Field stages already yield, but a whole subsystem build may exceed its 16 ms budget. Split only a measured indivisible unit into deterministic resumable work with atomic publication/cancel. | DT-MAC-04c; displayed loading interval, interactive-ready, total action time and cleanup |
| 14 GPU dependencies/ground | Continue A7/A26 attribution with actual frame-graph consumers. Removing one material may not remove a shared copy. Preserve noise/hash/derivative behavior; do not replace GPU float math with presumed-equivalent CPU double math. | DT-MAC-06b + VQ/LU/FW; capture then one viable complete-workload candidate |
| 15 Spatial qualification | Existing Auto uses Native at actual 1080p; manual Spatial 0.85 is a separate comparison, with native UI and fixed AA. Temporal remains a separately priced Forward+ path. | DT-MAC-07b1/b2 in MetalFX plan; preserve its stronger native failure/history gates |
| 16 texture/cache inventory | Runtime formats, mips, alpha/normal/ORM and strong vegetation-cache ownership need observation. Logical payload, physical footprint, residency and transition peaks are different metrics. | A31/DT-MAC-04d; actual package/resources and reacquisition-hitch controls |
| 17 live guard cost | Attribute start-byte encoding, native retained-leaf comparison, binding and full callback separately. Existing B3 optimization is complete. Any comparator must retain byte/type/public-alias mutation semantics every tick. | DT-MAC-04a/n; no decimation, tolerance change or identity-only cache |
| 18 exact observation/flap | Frame-local datum reuse requires identical state/time/weather/owner. Continue CF-07 angle-only render access without suppressing the full flap advisory for HUD/controls. | CF-07 + DT-MAC-04b; original consumer behavior and no persistent cross-tick cache |
| 19 conditional vegetation | Only route-specific proven vertex work: custom procedural grass with all-view conservative visibility or exact-zero legacy wind. Default meadow cells and batching already exist. | DT-MAC-06c + LU/VQ; every camera/probe/world transform and zero/epsilon motion |
| 20 build/platform | Keep current compiler/FP/deployment baseline. LTO/PGO/CPU tuning, Game Mode, power policy and engine upgrades are separately identified artifacts/workloads; no automatic global flag or affinity change. | DT-MAC-10/08 + GDU; held-out training, exact replay, ABI/slices and actual energy evidence |

## Second pass — all twelve D entries and the correctness prerequisite

| External entry | Current operation, accepted implementation boundary and remaining evidence |
| --- | --- |
| D01 wheel scratch | `nk_stage.hpp` constructs rates and `nk_wheels.hpp` fills storage before airborne return. Reuse owned per-instance scratch only where the returned derivative remains separately owned. The simple branch moves rates into its return; never lend that result a reusable scratch alias. Inspect the actual arm64 allocator and retain previous/interleaved results. |
| D02 retractable drag | `nk_retractable.hpp` returns a temporary six-value vector; preserve explicit empty/invalid/six-value shape using fixed internal storage and translate at `nk_gear_binding.hpp`. Keep extension/spatial-delta validation, NaN/zero behavior and force accumulation order. |
| D03 sampled validation | Scenery/lake sampled wrappers validate and call validating cores again. Introduce private validated entry points within the same stable invocation; preserve every unique public check, error reason, miss/hit distinction and callback/event order. Unsampled existing probes cannot qualify sampled finite-fuel paths. |
| D04 daylight sample | `sun_glare.gd` obtains the background and calls `background_luminance`, which recomputes it through `sky_mirror.gd`. Reuse one local original background; calculate denominator luminance before halo/aureole additions. Material reads here are CPU cached values, not GPU readbacks. |
| D05 companion invariants | Preserve A33's completed root/rate reuse. Hoist threat half-turn/distance inside one valid prediction; separately cache first saturated arc/chord geometry. Keep two distinct sinc arguments, geometry-ready flag, vertical correction, comparisons/ties/hysteresis and pre-step roster ordering. Qualify real opt-in companion/reference sessions. |
| D06 accepted support | Ordinary enabled cost observation samples compressions; nonterminal damage settlement can query them again. Reuse a detached observation only with state/gear/terrain/lake/track/provider and intervening-mutation proof, not merely tick equality. Preserve actual negative airborne values, threshold, event order and belly/dwell behavior. |
| D07 controller | Eligible polls read ten axes/128 buttons; those calls read Godot state, not 128 HID transactions. Rerun F6 on the current Mac and actual configured input. A narrow detached managed-verifier record is separate from a conditional all-up shortcut; injected/bound readers, AUX, held button 127, reused device IDs and fresh identity checks retain the original path unless equivalence is proven. |
| D08 posed ground | `nk_kernel.cpp` copies prepared ground and `retractable_pose` copies gear again. Start by removing only the same-call redundant gear copy. Broader terrain reuse needs prepared-generation ownership, failed-prepare/reset/world-change and inter-instance controls. External warm-copy probe found zero new allocations; this is a copy candidate, not a leak claim. |
| D09 shader globals | `ShaderClock` repeatedly publishes globals. Track independent exact last-published values plus initialization/owner generation, preserving wrapped time, rewind, alternate writers and changed wind at the same time. Paused-frame API work is a candidate; another dirty global may leave GPU transfers unchanged. |
| D10 lens film | Split constants, event/config and dynamic uniforms per material generation. Wet clock/camera/lighting can still change while paused. First visible/recreated material and restore must be complete. Count actual CPU setter work and transfers separately. |
| D11 terminal/idle effects | Three independent candidates: final splash hide once while keeping sink/audio/checkpoint work; clear idle lightning once per generation while thunder/clock ownership continues; update settled crack stamps by derived visible output, not raw age. Dry-flight/screenshots with these paths off cannot measure them. |
| D12 mass receipt | Candidate glow contact context needs all validation/property checks, but its detached receipt is discarded. Share validation and materialize only the previous owned interpolation receipt where needed; retain exact refusal order and alias isolation. Measure separately from D03. |
| §16.8 drop cache | `DropPool.write` skips on dirty/height only, although gravity, rain state and destination mesh affect output. Current source supports a conditional staleness risk, not a demonstrated rendered defect. Before extending D09–D11 cache patterns, test dt=0 gravity rotation, aged-bead rain toggle and same-size mesh replacement. Then include all output dependencies in invalidation. |

Native/source checks supporting these dispositions use the actual current
[native stage](../../../research/native-kernel/src/nk_stage.hpp),
[retractable helpers](../../../research/native-kernel/src/nk_retractable.hpp),
[FlightSession](../../../app/sim/flight_session.gd),
[controller](../../../app/input/rc_input.gd),
[cloud cache](../../../app/render/cloud_shadow_map.gd),
[glow producer](../../../app/audio/glow_audio_pump.gd),
[glare](../../../app/render/landscape_upgrade/sun_glare.gd),
[lens](../../../app/render/lens/lens_stack.gd) and
[drop pool](../../../app/render/lens/drop_pool.gd).
Current-source operations still need generated-code, target allocation or runtime
evidence before any performance claim.

## Evidence that must not be enlarged

The existing [B5 ledger](../native-kernel/DT-MAC-04n4/README.md) remains the
authority for adoption, callback measurements, collector versions, failed controls
and sustained circuit. Its 36.04–51.45% callback reductions are not FPS or energy
gains; the r3 whole-process pairs show no general CPU saving. The 1,382 verified
stock rows coexist with 46 open rows and an aggregate fleet failure. Source/digest
continuity does not requalify installed artifacts, all hardware or a public package.

The external allocation witness reports Linux x86-64/GCC 14.2.0, `-O2` with strict
FP flags, `sizeof(R)=8`, `sizeof(WheelContact)=104`; it did not run Godot or
`stage_evaluate`. Its complete extracted code, normalized to LF with final newline,
matches its claimed SHA-256
`269b3423995a1e89b5bfe398eb0ae6ddc3c37faed778f1ba7b9d1a42e224895a`.
This intake verified text integrity only and did not compile or rerun it.

| Externally reported operation | Iterations | Allocation requests | Requested bytes |
| --- | ---: | ---: | ---: |
| Cold ground copy + down pose | 1 | 6 | 1192 |
| Warm ground copy + alternating pose | 1000 | 0 | 0 |
| Fresh airborne wheel rates | 1000 | 1000 | 24000 |
| Pre-reserved airborne wheel rates | 1000 | 0 | 0 |
| Fully-down drag | 1000 | 1000 | 48000 |
| Fully-retracted drag | 1000 | 0 | 0 |

These are synthetic allocation requests, not Apple production allocations, retained
RAM, bandwidth or a measured speedup. Likewise 960 stage operations/s, the eligible
controller's 30,720 button calls/s, nominal 500 full-queue retries/s and setter-call
counts are conditional arithmetic, not observed load or global rate bounds.

## Retained primary references and deliberate non-adoption

The [psutil process implementation](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/__init__.py)
and [macOS backend](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/_psosx.py)
separate original-object liveness from wall-clock-adjusted public epoch creation
time. Retrieve the exact retained r3 apparatus before proposing supported integration;
do not turn private psutil internals into an undocumented new dependency.

Use Apple's [Allocations workflow](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use)
and [CPU attribution guidance](https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks)
for diagnostic hypotheses, then separate clean timing. [Processor Trace](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace)
recording requires M4+ Macs, macOS 15.4+ and Instruments 16.3+; it is not an M1
prerequisite. Preserve dSYM/binary UUID identity and diagnostic-engine provenance.

No copied external command template replaces current tool READMEs or shared-host
admission. No engine update, blanket fast-math/half precision, lower physics rate,
guard decimation, arbitrary background SceneTree/GPU calls or global QoS/affinity
policy is adopted. Keep existing A7/A24/A26/A28/A31/A33/CF-07/F6/CR-22e homes;
completed fixes are not reopened by older prose.

The external advice to park advanced engine work is a prioritization suggestion.
It does not supersede the user's later explicit four-MetalFX implementation scope.
App-level preparation and feature research may progress independently; hardware
timing remains serial. Public signed distribution stays deferred. No runtime or
performance gate is closed by this document integration.
