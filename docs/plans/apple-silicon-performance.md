# Apple Silicon performance and qualification

DT/PT own Apple host measurement and package qualification. VQ/GDU own renderer and engine changes, SF/FL own flight and recording contracts, and UI/AUD and vehicle owners qualify their respective routes. The [roadmap](../../ROADMAP.md) owns project status and priorities. Use the [technical background](../APPLE-SILICON-TECHNICAL-BACKGROUND.md) for architecture and limitations, the [M1 operating guide](../tools/macos-m1.md) for access and the [desktop delivery plan](../DESKTOP-DELIVERY-PLAN.md) for release work.

**Display target.** On an Apple Silicon Mac with a built-in or external Retina (2×) display, target full-screen native display pixels at 60 Hz, including the internal 3D result after MetalFX where available. The reference M1 Air has a 2560×1600 panel. Logical points, render input, reconstructed 3D output, acquired drawable and physical panel pixels are distinct. Record each dimension and its source. Intel Macs and standard (1×) external displays follow 1920×1080 first, higher resolutions second and 1280×720 last. A requested window, display-server estimate or offscreen image covers only its observed boundary.

**Physics and graphics.** For a supported stock production flight, qualify the native backend actually selected. Verify the explicit reference and unsupported/failed-admission routes independently. The November R10 locally signed development bundle exercised native stage execution and replay. Its dated receipt records the aircraft, OS, engine and package tested. Public signed distribution, physical display/control evidence, and sustained complete-product performance have separate gates. [Owner decision](../DECISIONS.md#default-to-native-physics-on-supported-apple-silicon-flights) · [R10 receipt](../research/desktop-delivery-investigations/DT-MAC-11a/README.md#2026-11-16-owner-directed-native-default) · [ARM64 qualification contract](../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md)

## Campaign protocol and acceptance budgets

Use the [shared acceptance contract](global-performance-visual-quality.md#4-measurement-and-acceptance-contract) for pacing, Gate P, loading and visual cost. Freeze the following Apple-specific controls and stricter replication requirements before comparing a candidate.

| Metric | Required method and acceptance |
| --- | --- |
| Frame pacing | Declare display mode, cap/VSync, refresh and observed dimensions. Alongside the shared process-loop gates, report maxima, >33.3 ms and >50 ms events and consecutive bursts. Evaluate physical presentation separately. |
| Throughput | Separate uncapped experiment with the same visible workload; do not use VSync-clamped FPS to claim CPU/GPU savings. Never sum overlapping CPU/GPU timers as frame time. |
| Physics | Report individual complete-session tick p50/p95/p99, tail cases and unpaused simulation/wall beside the owning Gate P statistic. |
| Adoption | Improvement beyond run variation and observer uncertainty; predeclared practical screen is ≥5% in the affected complete workload or removal of a reproducible hitch/leak/gate failure. Reject unexplained >5% required-case regression. A smaller proven defect repair can be justified explicitly. |
| Loading | Record request, validated ready, first draw and interactive-ready events separately. A paused first draw cannot qualify interaction. |
| Memory | Before candidate tests, record a justified working ceiling on the actual floor host with OS headroom. No sustained candidate-attributable pressure/swap increase or unexplained retained growth through warm lifecycle cycles. No arbitrary “VRAM fraction” or additive RSS+GPU budget. |
| Correctness | Required local checks, same-host exact replay where promised, current H9 cross-platform policy, unchanged collision/physics identity. No golden rewriting or tolerance widening. |
| Visual/control | No repeatable loss of orientation, silhouette, landing cues, smoke cues, UI readability or control response; fixed-camera moving comparisons and owner pilot acceptance. |
| Diagnostic overhead | Proposed screen: ≤1% relative increase in combined app+helper CPU-seconds per active wall-second (not one percentage point of psutil CPU%) and ≤0.2 ms frame-p95 increase, without new repeatable >50 ms hitches; also report p99, helper CPU/RSS, disk cost and repeat variation. Use both uncapped cost and 60 Hz pacing so VSync cannot hide cost; for a near-zero CPU baseline report absolute CPU-ms/s and freeze an absolute ceiling before the trial. If noise prevents this bound, state unresolved, use a lower rate or external short traces, and do not subtract overhead to manufacture a pass. |

For short candidate decisions use at least **five independent alternating baseline/candidate pairs**, initially 30 s warmup + 120 s measured, with comparable initial thermal/power conditions. Report per-run distributions and paired differences; correlated frames are not independent trials. Use pilot, render-fixture and active-physics results as distinct groups. A one-off capture diagnoses; it does not establish a speedup.

For loading use at least five fresh-process and five warm in-process trials with cache state recorded. For an initial lifecycle screen use 10 warm transitions, then 20 for changes affecting resource ownership; the final DT campaign retains **50 Home/flight cycles**. For baseline/finalist sustained qualification use **three independent 30-minute active-flight runs**, with 30 s warmup excluded and explicit reducer minima of 30/1,800 s. Short rejected candidates do not need three soaks each. Repeat AC and battery as separate claims where applicable, after the core AC pass; unchanged binary/settings with multiple claimed power profiles still need profile-specific evidence.

Each receipt includes source commit/dirty patch and relevant input hashes; engine/templates/package/native/SDK identities; host model/RAM/GPU/OS; actual output and internal dimensions; renderer, driver, effects, AA, reconstruction, scenery and camera; aircraft/field/weather/seed/input identity; observers, power/cache/focus state; sample scope/unit/availability/completeness; failures/exclusions; per-run and paired results; visual/replay result; accept/reject decision and rollback. A timed-out, capped, paused, recovered-prefix or substituted-backend run cannot count as a complete intended workload.

### DT-MAC-03b — attribution and baseline soak

Use a bounded 30-second CPU profile and, on a Metal candidate only, appropriate GPU trace/capture. With Compatibility, report GPU timing unavailable and use supported external evidence rather than calling it CPU-bound by subtraction. Compare full live callback time with detached session/evaluator probes; include input, collision, publication, observer, audio, recording and scenery scopes. Do not reinterpret `step_usec` as complete frame or callback cost.

Minimum workload manifest:

| Case | Purpose and fixed controls |
| --- | --- |
| Stik normal circuit, approach, ground contact | Baseline flight/control, fixed pilot camera and input tape where applicable. |
| P-51 plus an electric aircraft | Different evaluator/visual/propulsion load; use current catalog/data identity, not historical X8 eligibility. |
| Club field and Green paradise | Vegetation/terrain/water differences; same weather/time/scenery tier per pair. |
| Lake/reflection view, smoke maneuver, dusk/night | Exercise actual expensive effects independently before a combined worst required scene. |
| Distant aircraft against sky/cloud/trees and close pass | Orientation/readability; fixed FOV, zoom/aid, trajectory and projected size. |
| Home/Fly/Workshop, aircraft/landscape change | Cold/warm loading and lifecycle/retention; paused periods are labeled. |
| Helicopter/ground activity if offered in the release | Independent route/software/performance gate; fixed-wing success does not qualify them. |

Run diagnostic-off, frame-only, frame+resource and helper-enabled controls. Choose the lightest collection satisfying required evidence. Execute the three baseline soaks once the short runs are valid; compare early/final five-minute windows, pacing, active sim/wall, memory/pressure, thermal/power and recorded pauses. Do not create a long soak out of restarted short processes.

For the half-second disturbance in the ANGEL product tour, isolate the between-iteration phase and capture several periods in a paused route. Repeat in the same flying route after a causal intervention. Average FPS cannot resolve the periodic source. [24 November phase attribution](../research/god-test/2026-11-24-flight-tick-cost.md#the-m1-half-second-disturbance)

<a id="10-first-test-session-on-the-available-m1"></a>
## First test session on the available M1

1. Freeze the commit plus dirty changes, attributes-correct checkout bytes, binary/templates/package hashes, private settings, host, power and observers. Verify ARM64 without translation, effective graphics route and selected flight backend. Keep a separately requested reference control.
2. Use an admitted Aqua session. Confirm the normal Home → Fly → pause → re-entry → Home/Workshop path with active audio and intended input. A direct-flight fixture and an editor-only run have narrower coverage. Check interruption, teardown and process identity across the entire interval.
3. At the applicable target, verify measured output, drawable and internal 3D dimensions, cap, VSync and refresh. Confirm moving aircraft, first input and interactive readiness. Preserve the matched display, FOV, weather, camera and settings for all pairs.
4. Compare A/A and observer-off/on first, then freeze the least intrusive valid collector. Run short paired candidates before baseline/finalist soaks. Retain aborted, unfocused, non-drawing or paused trials and their exclusion reasons. Measure physical scanout and control-to-photon latency on a synchronized physical input/display route.

### DT-MAC-02h — reference-release identity independent of NK-3

Bind the actual executable, PCK, loaded solver when present, engine, architecture, resources and final bundle receipt. Exercise explicit reference exact replay independently of automatic native selection. A missing or mismatched receipt must fail closed for that claim. DT-MAC-02c/d additionally require native launch/resource capture and contiguous stream coverage; 02e/f/g cover host clocks, normal app route and voluntary share-safe diagnostics. Record unavailable channels, counter freshness, discontinuities and distinct clock domains. Keep diagnostic attach entitlements out of the public product. [Release tooling](../../tools/release/README.md) · [Performance collectors](../../research/performance/README.md)

## Selecting a platform experiment

| Steps | Entry and proof |
| --- | --- |
| DT-MAC-04a/b · CPU, collision, audio and observers | Attribute the affected route with balanced observer controls. Preserve exact accepted states, ordered transactions, recording and audible events. Compare complete cost across airborne, rolling and contact regimes. |
| DT-MAC-04c/d · loading and memory | Separate first feedback, validated ready, first draw and interactive control. Measure cold/warm caches, paused frames, peak pressure, retained owners and reacquisition after eviction. Refactor one indivisible construction unit or retained resource with a bounded cancel/recovery path. |
| DT-MAC-05a/c · renderer | Compare identical content and supported common features with isolated configuration. Record effective backend, output, AA, shadows, lighting and reconstruction. Accept on moving silhouettes, full-frame cost, correct startup and safe fallback. |
| DT-MAC-06b/c/d · GPU/first use | Attribute pixel/pass, material residency/geometry and first specialization independently. Price dependencies such as copied depth/screen textures and first-use compilation. Native shader baking requires a supported native export and fresh/warm/baked/unbaked controls. |
| DT-MAC-05b/06a · settings | Validate persisted choices, restart/Keep/Revert, bad preferences, failed initialization, resize, fullscreen and known-good recovery with existing UI. Reachability and process responses do not demonstrate physical display confirmation. |
| DT-MAC-08/09 · finalists | Qualify the exact package in repeated sustained runs and 50 lifecycle cycles. Separate AC, battery/Low Power, display and refresh profiles. Retain audio/controller, visual acceptance, memory, thermal, early/final-five-minute windows and actual native stage execution. A second named machine extends coverage only for that device. |
| DT-MAC-08b · distribution | Verify slices, receipt, loaded dependencies, signing and replay on the exact delivered bytes. Public distribution additionally needs supported downloaded, moved, quarantined and offline Finder routes on claimed OS versions. Public Developer ID distribution remains separately deferred. |
| DT-MAC-10–13, 13i · engine or mobile | Require a measured retained limitation before new engine optimizations. iOS/iPadOS additionally needs a named physical device, export/signing, suspend/resume, touch/controller/audio lifecycle, memory/thermal limits and device-specific acceptance. Mac tests cannot qualify it. |

<a id="9-phase-7--qualify-existing-metalfx-trials-conditionally"></a>
## Qualifying MetalFX trials

The [four-feature MetalFX plan](apple-metalfx.md) owns Spatial, Temporal, Frame Interpolation and Temporal Denoised Upscaling, including the real RT producer. For every mode, distinguish requested provider, supported inputs, actual execution, fallback and failure. Compare Native with one provider at fixed output and disclose input scale. Require moving distant aircraft and landing cues, motion/history reset on camera or world discontinuities, safe resize, resource retirement and recovery. For interpolation, report real and generated frames separately and measure physical control response. An API allocation, injected capability or isolated GPU witness leaves whole-flight acceptance open. [Engine and native product evidence](../research/desktop-delivery-investigations/DT-MAC-11a/README.md)

### DT-MAC-04n-R1 — keep the Mac native default after world changes

The Mac stock-world guard can reject an otherwise supported native flight after a scenery or collision change. On the DR-19e update the Mac identity differed from Linux and Windows even with the same geometry. The [R1 evidence](../research/native-kernel/DT-MAC-04n-R1/README.md) records the guard and hosted Mac default-route checks, with their device limits.

1. Run the portable stock-world check for proxy count and quantized geometry fingerprint. Read the macOS-native `world_identity` and `proxies` from `MACOS_DOMAIN_STOCK_GUARD_DIAGNOSTIC` in the hosted Mac job's `domain-guard.log`.
2. Review and renew the Mac world/proxy pins and portable fixture together. Renew affected companion pins through the existing rebind procedure. Rebuild the platform receipts on the changed source.
3. Exercise the no-override default with actual native stage calls, then the explicit reference and out-of-domain cases. Verify the physical M1 and the intended package separately from CI. Report actual backend/refusal and current fleet/companion scope. Follow the [native operator guide](../../research/native-kernel/README.md#experimental-macos-arm64) for current admission.
4. For toolchain, solver, aircraft, identity schema, package or collector changes, apply the [ARM64 qualification matrix](../../APPLE_SILICON_NATIVE_KERNEL_IMPLEMENTATION_PLAN.md#evidence-to-renew-when-inputs-change). Preserve the earlier receipt's exact scope when renewing a gate.

<a id="next-campaign-dt-mac-00-r4"></a>
## November 2026 shader and display experiments

The [R4 campaign](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md) separates technical M1 runs, source identities, actual and estimated dimensions, rejected variants and short native checks. A historical three-run-per-role Metal soak on the named instrumented circuit measured 17.6–23.2% higher process-loop FPS. It missed the 60 Hz pacing target. The [six raw captures and reducer](../research/desktop-delivery-investigations/DT-MAC-02/README.md#repeated-30-minute-metal-comparison) preserve the evidence for that build.

The [two external shader studies](../research/desktop-delivery-investigations/DT-MAC-00-R4/shader-experiments-2026-11-05.md) retain the original numerical data, algorithm proposals, sources and experiment kit. The [November follow-up](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#optimization-help-follow-up-2026-11-05) records effective-state validation, analytic fallback, bounded cache publication and separate ground/sky controls. Both bounded-density variants failed the unchanged Metal numerical gate; a reference-fallback trial then regressed the layered-cloud screen. A two-octave atlas or half-resolution sky needs actual memory, transition, motion and complete-frame proof. A native aircraft crop additionally needs matched occluders, exposure, projection/rays and seamless motion. The packed relief cache's large error and the solar LUT's shared angle computation explain their lower value. [Native rejection controls](../research/desktop-delivery-investigations/DT-MAC-00-R4/README.md#dt-mac-06b-r2--dt-mac-02b-r2-native-verification-2026-11-06)

<a id="17-external-handoff-work-order-2026-11-14"></a>
## External proposals from 14 November 2026

The [dated intake](../research/desktop-delivery-investigations/external-handoffs-2026-11-14.md) maps the twenty initial proposals, twelve follow-ups, dependency-key correction and source hashes. Apply the following conditions when reopening one of those candidates.

- For process CPU/resources, retain stable original-process identity in both collectors, validate pre/post-poll identity, and reject replacement, denied or partial reads. Test owned and attached processes separately. Freeze collector versions before paired evidence.
- Record normal Home/flight route, exact native stage and effective renderer, active radio, audio, lens/weather, recording and companions. Include complete workload and A/A and observer controls. Hardware allocation counters and symbols are required for an allocation claim.
- For cache, audio and collision changes, test invalidation on source, weather, gravity, mesh, contact and scene changes as applicable. Preserve source order, partial/failed setup, live ownership, independent instances, rollback and reference-exact behavior. Compare one active consumer at a time.
- For memory/loading, inspect packaged texture formats, mips, aliases and transition peaks. Use staged publication for work that is safe to interrupt. For build changes, record actual compiler/linker flags, loaded slices and strict arithmetic; compare held-out aircraft, weather and contact cases.
- For a finalist, apply the campaign budgets above, including complete-route CPU/GPU attribution, moving readability, actual audio/input, sustained thermal behavior and exact package identity. The [original work packages and detailed test catalogue](https://github.com/bultodepapas/OpenRCsimulator/blob/8d4169f8febfd7d78a028eaa817414217a54f24b/docs/plans/apple-silicon-performance.md) retain the original candidate-specific test designs and chronology.
