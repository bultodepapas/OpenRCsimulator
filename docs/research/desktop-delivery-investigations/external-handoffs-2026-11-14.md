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


## Portable claim-to-source map

The following preserves the supplied reference IDs and exact targets. C references
name the external review's immutable OpenRC source/evidence snapshots; U references
name its pinned engine implementation; P references are its external bibliography.
They are retained citations, not a claim that every external page or historical
artifact was independently re-executed or requalified during this integration.
The dispositions above govern applicability to current work.

| External entry / evidence | Supplied source references |
| --- | --- |
| 10 | [C23], [C24], [P16] |
| 11 | [C29], [C30], [C31], [C32], [P20] |
| 12 | [C27] |
| 13 | [C35], [C36], [C41], [P19] |
| 14 | [C33], [C34], [U02], [P09], [P10], [P11], [P12], [P13] |
| 15 | [C38], [C39], [U01], [P21], [P15] |
| 16 | [C40], [C05], [C06], [P17], [P18] |
| 17 | [C19], [C20], [C15] |
| 18 | [C21], [C22], [C06] |
| 19 | [C35], [C36], [C37] |
| 20 | [C05], [C11], [C42], [U03], [U04], [U05], [U06], [P01], [P02], [P03], [P04], [P05], [P23], [P24], [P25], [P26], [P27], [P28] |
| 01 | [C12], [C13], [C14], [P32], [P33] |
| 02 | [C02], [C03], [C05], [C07], [C21], [C42], [C44], [C45], [C47] |
| 03 | [C02], [C23], [C24] |
| 04 | [C15], [C16], [C17], [C91] |
| 05 | [C15], [C18] |
| 06 | [C19], [C20], [C50] |
| 07 | [C23], [C24], [P30], [P31] |
| 08 | [C28], [C29], [C31] |
| 09 | [C26], [C22] |
| D01 | [C52], [C53], [C91] |
| D02 | [C52], [C54], [C56] |
| D03 | [C57], [C58], [C59], [C90] |
| D04 | [C74], [C75], [C76], [U07] |
| D05 | [C64], [C65], [C66], [C67] |
| D06 | [C59], [C61], [C62], [C63], [C92] |
| D07 | [C68], [C69], [C70], [C71], [C72], [C73], [U12], [U13] |
| D08 | [C53], [C54], [C55] |
| D09 | [C77], [C78], [C61], [U08], [U11] |
| D10 | [C79], [C80], [U07], [U08] |
| D11 | [C79], [C80], [C81], [C82], [C83], [C85], [U09], [U10] |
| D12 | [C59], [C60] |
| §16.8 drop cache | [C79], [C84] |
| Allocation/CPU attribution | [P34], [P35], [P36] |
| Review identities/fingerprints | [C01], [C08], [C09], [C43], [C51] |

### Preserved source catalog

| Ref | Kind | Exact supplied target |
| --- | --- | --- |
| C01 | OpenRC snapshot | [b80a4b214878e97313d2f93901b32174bb0713ea](https://github.com/bultodepapas/OpenRCsimulator/commit/b80a4b214878e97313d2f93901b32174bb0713ea) |
| C02 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/research/native-kernel/DT-MAC-04n4/README.md) |
| C03 | OpenRC snapshot | [apple-silicon-performance.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/plans/apple-silicon-performance.md) |
| C04 | OpenRC snapshot | [APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md) |
| C05 | OpenRC snapshot | [project.godot](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/project.godot) |
| C06 | OpenRC snapshot | [CONSOLIDATED-AUDITS.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/external%20Audits/CONSOLIDATED-AUDITS.md) |
| C07 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/README.md) |
| C08 | OpenRC snapshot | [build.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/build.py#L231-L239) |
| C09 | OpenRC snapshot | [flight_log.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/flight_log.gd#L409-L419) |
| C10 | OpenRC snapshot | [simulation.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/simulation.gd) |
| C11 | OpenRC snapshot | [build_macos.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/build_macos.py) |
| C12 | OpenRC snapshot | [resource_samples.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/godot/resource_samples.py#L360-L419) |
| C13 | OpenRC snapshot | [app_cpu_per_sim.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/app_cpu_per_sim.py#L86-L128) |
| C14 | OpenRC snapshot | [sustained_resources.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/sustained_resources.py) |
| C15 | OpenRC snapshot | [nk_stage.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_stage.hpp) |
| C16 | OpenRC snapshot | [nk_glow_stage.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_glow_stage.hpp#L318-L325) |
| C17 | OpenRC snapshot | [nk_liquid_stage.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_liquid_stage.hpp#L138-L147) |
| C18 | OpenRC snapshot | [nk_prop.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_prop.hpp#L105-L129) |
| C19 | OpenRC snapshot | [native_stage.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_stage.gd) |
| C20 | OpenRC snapshot | [native_macos_domain.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_macos_domain.gd) |
| C21 | OpenRC snapshot | [main.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/main.gd) |
| C22 | OpenRC snapshot | [flight_session.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/flight_session.gd) |
| C23 | OpenRC snapshot | [glow_audio_pump.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/glow_audio_pump.gd) |
| C24 | OpenRC snapshot | [soundscape.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/soundscape.gd) |
| C25 | OpenRC snapshot | [tests](https://github.com/bultodepapas/OpenRCsimulator/tree/b80a4b214878e97313d2f93901b32174bb0713ea/app/tests) |
| C26 | OpenRC snapshot | [flight_audio.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/flight_audio.gd) |
| C27 | OpenRC snapshot | [water.gdshader](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/lake/water.gdshader) |
| C28 | OpenRC snapshot | [cloud_shadow_map.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/cloud_shadow_map.gd) |
| C29 | OpenRC snapshot | [sky.gdshader](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/sky.gdshader) |
| C30 | OpenRC snapshot | [sky_appearance.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/weather/sky_appearance.gd) |
| C31 | OpenRC snapshot | [atmosphere.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/atmosphere.gd) |
| C32 | OpenRC snapshot | [sky_state.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/world/sky_state.gd) |
| C33 | OpenRC snapshot | [grass_surface.gdshaderinc](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/grass_surface.gdshaderinc) |
| C34 | OpenRC snapshot | [ground.gdshader](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/ground.gdshader) |
| C35 | OpenRC snapshot | [near_grass.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/near_grass.gd) |
| C36 | OpenRC snapshot | [runway_meadow.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/runway_meadow.gd) |
| C37 | OpenRC snapshot | [imported_vegetation_wind.gdshader](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/imported_vegetation_wind.gdshader) |
| C38 | OpenRC snapshot | [reconstruction.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/reconstruction.gd) |
| C39 | OpenRC snapshot | [metalfx_policy.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/metalfx_policy.gd) |
| C40 | OpenRC snapshot | [imported_vegetation.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/imported_vegetation.gd) |
| C41 | OpenRC snapshot | [field.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/field.gd) |
| C42 | OpenRC snapshot | [export.sh](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/export.sh) |
| C43 | OpenRC snapshot | [apple-silicon-m1-experiments-2026-11-12.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md) |
| C44 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/tools/README.md) |
| C45 | OpenRC snapshot | [macos-m1.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/tools/macos-m1.md) |
| C46 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/debug/README.md) |
| C47 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/godtest/README.md) |
| C48 | OpenRC snapshot | [ci_macos.py](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/ci_macos.py#L110-L128) |
| C49 | OpenRC snapshot | [COMPLETED-AUDIT-WORK.md](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/external%20Audits/COMPLETED-AUDIT-WORK.md) |
| C50 | OpenRC snapshot | [native_macos_admission.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_macos_admission.gd) |
| C51 | OpenRC snapshot | [bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c](https://github.com/bultodepapas/OpenRCsimulator/commit/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c) |
| C52 | OpenRC snapshot | [nk_stage.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_stage.hpp) |
| C53 | OpenRC snapshot | [nk_wheels.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_wheels.hpp) |
| C54 | OpenRC snapshot | [nk_retractable.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_retractable.hpp#L48-L105) |
| C55 | OpenRC snapshot | [nk_kernel.cpp](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_kernel.cpp#L1661-L1685) |
| C56 | OpenRC snapshot | [nk_gear_binding.hpp](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_gear_binding.hpp#L45-L72) |
| C57 | OpenRC snapshot | [scenery_collision.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/scenery_collision.gd) |
| C58 | OpenRC snapshot | [lake_collision.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/lake_collision.gd#L44-L110) |
| C59 | OpenRC snapshot | [flight_session.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/flight_session.gd) |
| C60 | OpenRC snapshot | [flight.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/glow/flight.gd#L230-L253) |
| C61 | OpenRC snapshot | [main.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/main.gd) |
| C62 | OpenRC snapshot | [ground_wheels.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/ground_wheels.gd#L216-L233) |
| C63 | OpenRC snapshot | [aircraft_contact_events.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/aircraft_contact_events.gd#L279-L294) |
| C64 | OpenRC snapshot | [pilot.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/pilot.gd) |
| C65 | OpenRC snapshot | [agent.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/agent.gd#L149-L189) |
| C66 | OpenRC snapshot | [manager.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/manager.gd#L167-L235) |
| C67 | OpenRC snapshot | [performance-report-2026-11-09.md](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/performance-report-2026-11-09.md#L104-L145) |
| C68 | OpenRC snapshot | [rc_input.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/rc_input.gd) |
| C69 | OpenRC snapshot | [controller_service.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/controller_service.gd#L174-L190) |
| C70 | OpenRC snapshot | [controller_registry.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/controller_registry.gd#L132-L151) |
| C71 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/controller-support-2026-10-14/cost/README.md) |
| C72 | OpenRC snapshot | [sustained_flight.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/performance/sustained_flight.gd) |
| C73 | OpenRC snapshot | [session_probe.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/performance/session_probe.gd#L126-L149) |
| C74 | OpenRC snapshot | [sun_glare.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/landscape_upgrade/sun_glare.gd#L129-L191) |
| C75 | OpenRC snapshot | [sky_mirror.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/sun/sky_mirror.gd#L19-L52) |
| C76 | OpenRC snapshot | [sun_optics.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/sun/sun_optics.gd#L172-L180) |
| C77 | OpenRC snapshot | [shader_clock.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/shader_clock.gd#L1-L37) |
| C78 | OpenRC snapshot | [world.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/world/world.gd) |
| C79 | OpenRC snapshot | [lens_stack.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/lens_stack.gd) |
| C80 | OpenRC snapshot | [lens_settings.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/lens_settings.gd#L14-L71) |
| C81 | OpenRC snapshot | [water_effects.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lake/water_effects.gd) |
| C82 | OpenRC snapshot | [director.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/crash/director.gd#L148-L182) |
| C83 | OpenRC snapshot | [lightning.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/weather/lightning.gd) |
| C84 | OpenRC snapshot | [drop_pool.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/drop_pool.gd#L133-L275) |
| C85 | OpenRC snapshot | [storm_bank.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/weather/storm_bank.gd#L175-L203) |
| C86 | OpenRC snapshot | [metalfx-frame-generation-2026-11-14.md](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/desktop-delivery-investigations/metalfx-frame-generation-2026-11-14.md) |
| C87 | OpenRC snapshot | [detector.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/statistics/detector.gd#L614-L719) |
| C88 | OpenRC snapshot | [service.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/statistics/service.gd#L655-L678) |
| C89 | OpenRC snapshot | [overlay_manager.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/overlays/overlay_manager.gd) |
| C90 | OpenRC snapshot | [stik_glow_61fx_2t.json](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/data/aircraft/stik_glow_61fx_2t.json) |
| C91 | OpenRC snapshot | [README.md](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/native-kernel/NK-3/README.md#L194-L200) |
| C92 | OpenRC snapshot | [ground_contact.gd](https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/ground_contact.gd#L429-L440) |
| P01 | External bibliography | [dev-snapshot-godot-4-8-beta-2](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) |
| P02 | External bibliography | [dev-snapshot-godot-4-8-beta-3](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/) |
| P03 | External bibliography | [building-a-universal-macos-binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary) |
| P04 | External bibliography | [about-the-rosetta-translation-environment](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment) |
| P05 | External bibliography | [tuning-your-code-s-performance-for-apple-silicon](https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon) |
| P06 | External bibliography | [analyzing-the-performance-of-your-metal-app](https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app) |
| P07 | External bibliography | [large_world_coordinates.html](https://docs.godotengine.org/en/4.6/tutorials/physics/large_world_coordinates.html) |
| P08 | External bibliography | [multiple_resolutions.html](https://docs.godotengine.org/en/4.6/tutorials/rendering/multiple_resolutions.html) |
| P09 | External bibliography | [tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering) |
| P10 | External bibliography | [setting-load-and-store-actions](https://developer.apple.com/documentation/metal/setting-load-and-store-actions) |
| P11 | External bibliography | [choosing-a-resource-storage-mode-for-apple-gpus](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus) |
| P12 | External bibliography | [analyzing-apple-gpu-performance-using-counter-statistics](https://developer.apple.com/documentation/xcode/analyzing-apple-gpu-performance-using-counter-statistics) |
| P13 | External bibliography | [optimizing-gpu-performance](https://developer.apple.com/documentation/xcode/optimizing-gpu-performance) |
| P14 | External bibliography | [monitoring-your-metal-apps-graphics-performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) |
| P15 | External bibliography | [understanding-metal-performance-hud-metrics](https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics) |
| P16 | External bibliography | [Timers.html](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) |
| P17 | External bibliography | [importing_images.html](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) |
| P18 | External bibliography | [optimizing-texture-data](https://developer.apple.com/documentation/metal/optimizing-texture-data) |
| P19 | External bibliography | [thread_safe_apis.html](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) |
| P20 | External bibliography | [sky_shader.html](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html) |
| P21 | External bibliography | [10103](https://developer.apple.com/videos/play/wwdc2022/10103/) |
| P22 | External bibliography | [pipeline_compilations.html](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html) |
| P23 | External bibliography | [UsersManual.html](https://clang.llvm.org/docs/UsersManual.html) |
| P24 | External bibliography | [ThinLTO.html](https://clang.llvm.org/docs/ThinLTO.html) |
| P25 | External bibliography | [improving-your-games-graphics-performance-and-settings](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings) |
| P26 | External bibliography | [105118](https://support.apple.com/en-la/105118) |
| P27 | External bibliography | [125124](https://github.com/godotengine/godot/issues/125124) |
| P28 | External bibliography | [compiling_for_macos.html](https://docs.godotengine.org/en/4.6/engine_details/development/compiling/compiling_for_macos.html) |
| P29 | External bibliography | [debugger_panel.html](https://docs.godotengine.org/en/4.6/tutorials/scripting/debug/debugger_panel.html) |
| P30 | External bibliography | [class_audiostreamgenerator.html](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html) |
| P31 | External bibliography | [class_audiostreamgeneratorplayback.html](https://docs.godotengine.org/en/stable/classes/class_audiostreamgeneratorplayback.html) |
| P32 | External bibliography | [__init__.py](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/__init__.py) |
| P33 | External bibliography | [_psosx.py](https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/_psosx.py) |
| P34 | External bibliography | [gathering-information-about-memory-use](https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use) |
| P35 | External bibliography | [addressing-cpu-bottlenecks](https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks) |
| P36 | External bibliography | [analyzing-cpu-usage-with-processor-trace](https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace) |
| U01 | Pinned engine | [renderer_viewport.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L145-L198) |
| U02 | Pinned engine | [render_forward_mobile.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp) |
| U03 | Pinned engine | [detect.py](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/macos/detect.py) |
| U04 | Pinned engine | [SConstruct](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/SConstruct) |
| U05 | Pinned engine | [texture_streaming.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/texture_streaming/texture_streaming.cpp#L224-L227) |
| U06 | Pinned engine | [ProjectSettings.xml](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ProjectSettings.xml#L3541) |
| U07 | Pinned engine | [material.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/material.cpp#L422-L461) |
| U08 | Pinned engine | [material_storage.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/material_storage.cpp) |
| U09 | Pinned engine | [mesh_storage.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L1815-L2013) |
| U10 | Pinned engine | [multimesh.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/multimesh.cpp#L258-L286) |
| U11 | Pinned engine | [material_storage.h](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/material_storage.h#L202-L223) |
| U12 | Pinned engine | [input.cpp](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input.cpp) |
| U13 | Pinned engine | [thread_safe.h](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/os/thread_safe.h#L30-L39) |

### Preserved synthetic witness source

This is the supplied source text whose hash was verified above. It is retained
for reproducibility, without running it or adopting its replacement allocator.
It is not a new benchmark, production test, native artifact or command to execute.
Any later target reproduction uses a disposable, source-bound fixture and the
existing tool/host ownership rules; production parity requires separate evidence.

```cpp
// Linux x86-64 allocation-count witness; calls OpenRC headers directly.
// No Godot, app, native extension, target-device timing, or production changes.
#include <cstdio>
#include <cstdlib>
#include <new>
#include <vector>
#include "nk_retractable.hpp"

static bool counting = false;
static unsigned long long allocations = 0;
static unsigned long long requested_bytes = 0;

void* operator new(std::size_t n) {
    if (counting) { ++allocations; requested_bytes += n; }
    if (void* p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc();
}
void* operator new[](std::size_t n) { return ::operator new(n); }
void operator delete(void* p) noexcept { std::free(p); }
void operator delete[](void* p) noexcept { std::free(p); }
void operator delete(void* p, std::size_t) noexcept { std::free(p); }
void operator delete[](void* p, std::size_t) noexcept { std::free(p); }

static void start_count() { allocations = 0; requested_bytes = 0; counting = true; }
static void stop_count(const char* label) {
    counting = false;
    std::printf("%s: allocations=%llu requested_bytes=%llu\n", label, allocations, requested_bytes);
}
int main() {
    nk::GroundContext original;
    original.gear.empty = false;
    original.gear.contacts.resize(3);
    original.gear.reach = 1.0;
    original.surfaces.values.resize(24);
    original.lake.present = true;
    original.lake.shoreline.resize(40);
    original.lake.bank.resize(40);
    original.lake.profile_inset.resize(3);
    original.lake.profile_depth.resize(3);
    nk::RetractableModel model;
    model.enabled = true;
    model.drag_area = 0.1;
    model.paths.resize(3);
    for (auto &p : model.paths) p = {0.0, 0.0, 0.0, 0.1, 0.2, 0.3};
    nk::GroundContext posed;
    start_count();
    posed = original;
    bool ok = nk::retractable_pose(original.gear, model, 1.0, posed.gear);
    stop_count("cold_ground_copy_and_down_pose");
    if (!ok || posed.gear.contacts.size() != 3) return 1;
    start_count();
    for (int i=0; i<1000; ++i) {
        posed = original;
        if (!nk::retractable_pose(original.gear, model, (i&1) ? 0.5 : 1.0, posed.gear)) return 2;
    }
    stop_count("warm_ground_copy_and_pose_1000");
    nk::R state[13] = {};
    state[2] = -30.0;
    state[6] = 1.0;
    double speeds[3] = {0.0, 0.0, 0.0};
    std::vector<nk::R> loads;
    volatile double sink = 0.0;
    start_count();
    for (int i=0; i<1000; ++i) {
        std::vector<nk::R> rates;
        if (!nk::wheels_evaluate(state, original, 0.0, nullptr, 0, speeds, 3, 0.0, loads, rates)
            || rates.size() != 3 || !loads.empty()) return 3;
        sink += rates[0].v;
    }
    stop_count("fresh_airborne_wheel_rates_1000");
    std::vector<nk::R> reusable_rates;
    reusable_rates.reserve(3);
    start_count();
    for (int i=0; i<1000; ++i) {
        if (!nk::wheels_evaluate(state, original, 0.0, nullptr, 0, speeds, 3, 0.0, loads, reusable_rates)
            || reusable_rates.size() != 3 || !loads.empty()) return 4;
        sink += reusable_rates[0].v;
    }
    stop_count("reused_airborne_wheel_rates_1000");
    nk::R air[3] = {20.0, 0.0, 0.0};
    start_count();
    for (int i=0; i<1000; ++i) {
        auto drag = nk::retractable_drag(state, air, model, 1.0, 1.225);
        if (drag.size() != 6) return 5;
        sink += drag[0].v;
    }
    stop_count("fully_down_drag_1000");
    start_count();
    for (int i=0; i<1000; ++i) {
        auto drag = nk::retractable_drag(state, air, model, 0.0, 1.225);
        if (!drag.empty()) return 6;
    }
    stop_count("fully_retracted_drag_1000");
    std::printf("sizeof_R=%zu sizeof_WheelContact=%zu sink=%.1f\n", sizeof(nk::R), sizeof(nk::WheelContact), static_cast<double>(sink));
}
```

[C01]: https://github.com/bultodepapas/OpenRCsimulator/commit/b80a4b214878e97313d2f93901b32174bb0713ea
[C02]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/research/native-kernel/DT-MAC-04n4/README.md
[C03]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/plans/apple-silicon-performance.md
[C04]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md
[C05]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/project.godot
[C06]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/external%20Audits/CONSOLIDATED-AUDITS.md
[C07]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/README.md
[C08]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/build.py#L231-L239
[C09]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/flight_log.gd#L409-L419
[C10]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/simulation.gd
[C11]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/build_macos.py
[C12]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/godot/resource_samples.py#L360-L419
[C13]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/app_cpu_per_sim.py#L86-L128
[C14]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/performance/sustained_resources.py
[C15]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_stage.hpp
[C16]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_glow_stage.hpp#L318-L325
[C17]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_liquid_stage.hpp#L138-L147
[C18]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/src/nk_prop.hpp#L105-L129
[C19]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_stage.gd
[C20]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_macos_domain.gd
[C21]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/main.gd
[C22]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/flight_session.gd
[C23]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/glow_audio_pump.gd
[C24]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/soundscape.gd
[C25]: https://github.com/bultodepapas/OpenRCsimulator/tree/b80a4b214878e97313d2f93901b32174bb0713ea/app/tests
[C26]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/audio/flight_audio.gd
[C27]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/lake/water.gdshader
[C28]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/cloud_shadow_map.gd
[C29]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/sky.gdshader
[C30]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/weather/sky_appearance.gd
[C31]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/atmosphere.gd
[C32]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/world/sky_state.gd
[C33]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/grass_surface.gdshaderinc
[C34]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/ground.gdshader
[C35]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/near_grass.gd
[C36]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/runway_meadow.gd
[C37]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/imported_vegetation_wind.gdshader
[C38]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/reconstruction.gd
[C39]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/metalfx_policy.gd
[C40]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/scenery/imported_vegetation.gd
[C41]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/render/field.gd
[C42]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/export.sh
[C43]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/research/native-kernel/apple-silicon-m1-experiments-2026-11-12.md
[C44]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/tools/README.md
[C45]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/docs/tools/macos-m1.md
[C46]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/debug/README.md
[C47]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/tools/godtest/README.md
[C48]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/research/native-kernel/ci_macos.py#L110-L128
[C49]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/external%20Audits/COMPLETED-AUDIT-WORK.md
[C50]: https://github.com/bultodepapas/OpenRCsimulator/blob/b80a4b214878e97313d2f93901b32174bb0713ea/app/sim/native_macos_admission.gd
[C51]: https://github.com/bultodepapas/OpenRCsimulator/commit/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c
[C52]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_stage.hpp
[C53]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_wheels.hpp
[C54]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_retractable.hpp#L48-L105
[C55]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_kernel.cpp#L1661-L1685
[C56]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/native-kernel/src/nk_gear_binding.hpp#L45-L72
[C57]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/scenery_collision.gd
[C58]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/lake_collision.gd#L44-L110
[C59]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/flight_session.gd
[C60]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/glow/flight.gd#L230-L253
[C61]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/main.gd
[C62]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/ground_wheels.gd#L216-L233
[C63]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/sim/aircraft_contact_events.gd#L279-L294
[C64]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/pilot.gd
[C65]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/agent.gd#L149-L189
[C66]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/ai/companions/manager.gd#L167-L235
[C67]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/performance-report-2026-11-09.md#L104-L145
[C68]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/rc_input.gd
[C69]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/controller_service.gd#L174-L190
[C70]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/input/controller_registry.gd#L132-L151
[C71]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/controller-support-2026-10-14/cost/README.md
[C72]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/performance/sustained_flight.gd
[C73]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/research/performance/session_probe.gd#L126-L149
[C74]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/landscape_upgrade/sun_glare.gd#L129-L191
[C75]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/sun/sky_mirror.gd#L19-L52
[C76]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/sun/sun_optics.gd#L172-L180
[C77]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/shader_clock.gd#L1-L37
[C78]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/world/world.gd
[C79]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/lens_stack.gd
[C80]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/lens_settings.gd#L14-L71
[C81]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lake/water_effects.gd
[C82]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/crash/director.gd#L148-L182
[C83]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/weather/lightning.gd
[C84]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/lens/drop_pool.gd#L133-L275
[C85]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/weather/storm_bank.gd#L175-L203
[C86]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/desktop-delivery-investigations/metalfx-frame-generation-2026-11-14.md
[C87]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/statistics/detector.gd#L614-L719
[C88]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/statistics/service.gd#L655-L678
[C89]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/render/overlays/overlay_manager.gd
[C90]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/data/aircraft/stik_glow_61fx_2t.json
[C91]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/docs/research/native-kernel/NK-3/README.md#L194-L200
[C92]: https://github.com/bultodepapas/OpenRCsimulator/blob/bdeb1a0a354207a18d2f0b6f11f17ca1fcf9953c/app/physics/ground_contact.gd#L429-L440
[P01]: https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/
[P02]: https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/
[P03]: https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary
[P04]: https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment
[P05]: https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon
[P06]: https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-metal-app
[P07]: https://docs.godotengine.org/en/4.6/tutorials/physics/large_world_coordinates.html
[P08]: https://docs.godotengine.org/en/4.6/tutorials/rendering/multiple_resolutions.html
[P09]: https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering
[P10]: https://developer.apple.com/documentation/metal/setting-load-and-store-actions
[P11]: https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus
[P12]: https://developer.apple.com/documentation/xcode/analyzing-apple-gpu-performance-using-counter-statistics
[P13]: https://developer.apple.com/documentation/xcode/optimizing-gpu-performance
[P14]: https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance
[P15]: https://developer.apple.com/documentation/xcode/understanding-metal-performance-hud-metrics
[P16]: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html
[P17]: https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html
[P18]: https://developer.apple.com/documentation/metal/optimizing-texture-data
[P19]: https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html
[P20]: https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/sky_shader.html
[P21]: https://developer.apple.com/videos/play/wwdc2022/10103/
[P22]: https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html
[P23]: https://clang.llvm.org/docs/UsersManual.html
[P24]: https://clang.llvm.org/docs/ThinLTO.html
[P25]: https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings
[P26]: https://support.apple.com/en-la/105118
[P27]: https://github.com/godotengine/godot/issues/125124
[P28]: https://docs.godotengine.org/en/4.6/engine_details/development/compiling/compiling_for_macos.html
[P29]: https://docs.godotengine.org/en/4.6/tutorials/scripting/debug/debugger_panel.html
[P30]: https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html
[P31]: https://docs.godotengine.org/en/stable/classes/class_audiostreamgeneratorplayback.html
[P32]: https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/__init__.py
[P33]: https://github.com/giampaolo/psutil/blob/release-7.2.2/psutil/_psosx.py
[P34]: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use
[P35]: https://developer.apple.com/documentation/xcode/addressing-cpu-bottlenecks
[P36]: https://developer.apple.com/documentation/xcode/analyzing-cpu-usage-with-processor-trace
[U01]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_viewport.cpp#L145-L198
[U02]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/forward_mobile/render_forward_mobile.cpp
[U03]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/platform/macos/detect.py
[U04]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/SConstruct
[U05]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/texture_streaming/texture_streaming.cpp#L224-L227
[U06]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ProjectSettings.xml#L3541
[U07]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/material.cpp#L422-L461
[U08]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/material_storage.cpp
[U09]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp#L1815-L2013
[U10]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/multimesh.cpp#L258-L286
[U11]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/storage_rd/material_storage.h#L202-L223
[U12]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/input/input.cpp
[U13]: https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/core/os/thread_safe.h#L30-L39

