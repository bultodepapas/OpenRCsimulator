# Sixth graphics audit: follow the remaining work, quantify the opportunity

**Source pin:** main [`85a2475f60029a4b6b09f23f643119bceea84a45`](https://github.com/bultodepapas/OpenRCsimulator/commit/85a2475f60029a4b6b09f23f643119bceea84a45), reviewed in an isolated current-main snapshot after the [fifth pass](fifth-pass.md). **Publication base:** audit branch `ee46d96b7be4a77e040d814f6db71ab968751f01`, preserving its concurrent repairs; see the integration boundary below. **Date:** 22 November 2026. The current-main review covers the new fixed render-scale option, recent UHD 630 evidence, telemetry repairs, updated paints, and HUD/ground-session changes.

This pass finds two specific RC shader experiments and a residual star-construction batch, and follows the known statistics observer deeper into its spatial-weather/native boundary. It also rejects or deprioritizes several small native/disabled-feature leads. **Source behavior and arithmetic are established; no new application FPS gain or platform qualification is established.** Executed offline checks cover a source-pinned pixel-cost fit and the I01 solver-source identity witness. Production code, physics and graphics settings are not changed by the audit.

## Reports and evidence

| Report | What it adds |
| --- | --- |
| [Statistics and native boundaries](sixth-pass-observers-and-native.md) | F17 spatial-weather continuation, successful station counts, refusal/callback constraints, native batch design and small kernel watchlist |
| [RC shader details](sixth-pass-shaders.md) | Independent zero-weight texture paths, full-dirt color overwrite, actual scene guards and derivative hazards |
| [Scenery and disabled-feature lifetime](sixth-pass-scenery.md) | Residual star materialization, campfire/bird lifetime tradeoffs, existing guards and prior evidence |
| [Pixel-model receipt](sixth-pass-pixel-model.json) | Exact input rows, fit, range-endpoint sensitivity, withheld point, script/report hashes and limits |
| [Reproducer instructions](../../../research/performance/graphics-audit-2026-11-22/README.md#paused-view-pixel-cost-model) | Offline calculation without an engine or hardware measurement |
| [Solver-pin witness](sixth-pass-solver-pin.json) | Two accepted identity controls and the later source/pin mismatch; no engine or parity execution |
| [Source/CI/review receipt](sixth-pass-evidence.json) | Source hashes, current-main observations, independent corrections and verification scope |

## Priority and novelty

`W01–W04` are local report labels, not implementation-track IDs or a claim of four wholly new discoveries.

| Investigation | Current evidence | Useful next experiment | Priority limit |
| --- | --- | --- | --- |
| **W01 — F17 spatial statistics continuation** | An eligible accepted-tick airspeed/validity consumer enters full station-flow construction; conventional powered success uses ten wind-provider calls | Measure full observer, then a refusal-equivalent compact projection and one qualified native batch | Spatial weather selected; native solver selection does not automatically make this observer native; existing F17/F14/A6-O5 own prior work |
| **W02 — zero-weight RC detail samples** | Two coarse normal source samples can have zero normal-map contribution; one fine-color sample has a different zero predicate | Separate and combined shader guards retaining all other arithmetic | Track must exist/be visible; no measured instruction reduction, GPU time or pixel coverage |
| **W03 — full-dirt overwritten grass color** | Full coverage is reachable; finite base color is subsequently overwritten | Derivative-safe separation of color-only work, tested independently | More invasive than W02; preserve normals/shoulders/lighting; a naive varying early-out is rejected |
| **W04 — star construction after catalogue caching** | 5,080 placement records, 15,240 setters, 406,400-byte logical instance buffer per fresh eligible build | Attribute boundary, then compare exact native packed producer plus engine bulk assignment | Loading/first-frame tail, not steady FPS; historical builder timing is not current savings |

The ordering is a measurement order, not a numerical ranking of expected FPS. For example, a large-looking shader count may affect very few visible pixels, while a small accepted-tick cost repeats 240 times per simulated second. Reports retain exact trigger conditions and counterexamples.

## What the new low-end results support

### Separate the live tour from the paused model

The updated [UHD 630 report](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/docs/research/god-test/2026-11-22-linux-uhd630-comparison.md) records live automatic-graphics tours on PRIMIS and megatron: Compatibility, Low, X11, MSAA Off, projected Low shadow, Few birds, no runway meadow and 75% scale. Jet/Corsair circuits report 38.0–40.7 FPS, 1% lows 26.5–27.3 and simulation/wall 1.00; the two Stik circuits report 47.4/50.6 FPS but their cases remain **ineligible because of first Home**, despite circuit completion. These are retained author measurements, not executions by this audit or qualification of every source change at this pin.

The same report has a different experiment: a minimal Stik day/Club Field view frozen five seconds after an airborne start, 1920×1080, X11, **RC track Off**, birds/meadow/shadows/lens effects Off. These paused debug-bridge sessions are the only data used in the model below. They do not exercise live 240 Hz flight cost or W02/W03's track shader. Their summarized table does not itself provide full per-run source/engine/driver/raw-frame identities; this audit pins the report bytes, not an invented experiment receipt.

### A simple area model with a withheld observation

Let `s` be the nominal per-axis render scale. Fit frame time in milliseconds as:

`T(s) = A + B * s²`

Use the FPS-range midpoint at scale 1.0 and 0.75, convert each to milliseconds, and solve:

`B = (T(1) - T(0.75)) / (1 - 0.75²)`, `A = T(1) - B`.

| Paused minimal renderer | Native FPS input | 75% FPS input | A, ms | B, ms | Fitted area term at native |
| --- | ---: | ---: | ---: | ---: | ---: |
| Mobile | 24.3–24.8 | 38.5–39.1 | 6.539 | 34.194 | 83.95% |
| Compatibility | 26.2–26.5 | 40.0 | 8.349 | 29.602 | 78.00% |
| Forward+ | 19.0 | 29.7 | 9.291 | 43.341 | 82.35% |

For Mobile, the unused 67% observation is **45.6 FPS**. The fit predicts **45.686 FPS**, or 21.889 ms versus 21.930 ms from the reported observation. The agreement is useful as a consistency check, not evidence of sub-millisecond measurement precision. The inputs are rounded summary values from one experiment. Combining the reported endpoint ranges gives a Mobile prediction range of 44.947–46.445 FPS and an area-term fraction of 81.34–86.52%; these are sensitivity bounds, **not confidence intervals**. The 67% point is withheld from fitting, not an independent replication.

`A` is an empirical fixed term, not measured CPU time. `B` is area-correlated cost in this restricted view, not a direct GPU timer or terrain attribution. Do not extrapolate the intercept to zero pixels, another aircraft/camera, active physics, a different renderer or a promised 60 FPS. Actual internal dimensions can round. Godot documents per-axis scaling and recommends checking for other bottlenecks when reducing pixels has little effect. [Official resolution-scaling guidance](https://docs.godotengine.org/en/stable/tutorials/3d/resolution_scaling.html).

Nominal 75% scale retains 56.25% of the pixels; 67% retains 44.89%. This explains why fixed scaling is a strong practical first lever for a pixel-sensitive old iGPU. It does not remove the need to improve shader complexity, scene construction and serial CPU observers. The retained one-texture-ground experiment saves only 1.8–3.7 ms in this flight view, while the report attributes roughly 30 ms to ground in a Home view with more terrain coverage. Do not transfer Home's saving to every flight.

### Translate accepted-tick work into the frame budget

At real-time 240 Hz, a serial observer averaging `c` microseconds per accepted tick costs `0.24 c` milliseconds per simulated second. At an evenly distributed 60 Hz presentation cadence this averages four ticks/frame; at 30 Hz, eight. The arithmetic illustrates why complete accepted callbacks matter:

| Hypothetical observer cost | CPU ms/s at real time | Mean serial contribution at 60 Hz | At 30 Hz |
| --- | ---: | ---: | ---: |
| 50 microseconds/tick | 12 | 0.2 ms/frame | 0.4 ms/frame |
| 100 microseconds/tick | 24 | 0.4 ms/frame | 0.8 ms/frame |
| 500 microseconds/tick | 120 | 2.0 ms/frame | 4.0 ms/frame |

These are illustrative costs, **not measured statistics times**. GPU overlap, batching, catch-up, other callbacks and frame pacing determine how much wall-frame time actually changes. The nominal budgets are 33.33 ms at 30 FPS and 16.67 ms at 60 FPS. Keep the accepted 240 Hz physics and float64 transaction intact; lowering simulation fidelity would change the task rather than establish an optimization.

## Main refresh and existing caps

Main advanced by 33 commits and 113 changed paths from the fifth-pass pin `0f859b5`. The refresh includes:

- **Fixed render scale now implemented:** Native reconstruction offers 100/85/75/67/50%; recognized weak integrated/software GPUs can start at 75%, unidentified GPUs remain at full resolution. Other reconstruction providers keep their own scale policies. The old observation that the product lacks plain bilinear scaling is historical. [Preferences](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/app_state/display_preferences.gd), [reconstruction](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/reconstruction.gd), [policy](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/auto_graphics_policy.gd).
- **Graphics preparation explains first-use waits:** the new helper displays/records notices keyed by engine, renderer, adapter/driver and game version. It is not a repair that eliminates cold shader compilation. [Implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/app/render/graphics_preparation.gd).
- **Updated rendering/data correctness:** HUD AGL now includes the installed RC circuit; recording/export cleanup, telemetry lifecycle/consent/queue semantics, and companion solver binding changed. Preserve these fixes while measuring. New paint families and the added JETI roughness map mean the fifth pass's four-texture totals describe its old source pin, not this main's current complete paint set.
- **Adaptive resolution remains an evidence-gated plan:** fixed scale is shipped; reliable completed-render GPU feedback, resolution ownership, motion readability and repeated matched native/fixed/adaptive runs are still required. [Owning plan](https://github.com/bultodepapas/OpenRCsimulator/blob/85a2475f60029a4b6b09f23f643119bceea84a45/docs/plans/dynamic-resolution.md). Do not replace VSync/presentation caps or the existing 12-step catch-up model with a new unverified diagnosis.

The retained low-end report still records cold first-use freezes of 8.8–12.3 seconds at startup and 6.9–7.4 seconds during loading; later cases and warm-cache behavior differ. Shader preparation, CPU construction and first-presented frames need separate spans. Godot's official Compatibility guidance uses actual visible material/effect warm-up during loading, while renderer pipeline precompilation/baking has different coverage. Neither a file `load()` nor a notice proves that a GPU program is ready. [Official compilation guidance](https://docs.godotengine.org/en/stable/tutorials/performance/pipeline_compilations.html).

## Remote repairs and integration boundary

The pre-publication lease checks found ten concurrent commits ending at `f1d1151a`, then a further presentation refactor at `ee46d96b`. They implement earlier findings, so those items must not remain presented as wholly open on that branch:

| Earlier finding | Preserved branch change |
| --- | --- |
| T04 | Rendering reads the accepted flap angle without the full air-data advisory |
| T08 | Settings retains its already-created theme |
| U02 | Nitro transforms consume packed components directly; shared axis preparation remains separate |
| U03 | Nitro service queries use one state snapshot |
| U12 | Each live effect pool reuses the root inverse |
| M01 | Interactive tour comparison requires observed focus |
| M02 | Focus-wait frames have their own setup phase; phase-count mismatches withhold metrics |

The branch's [implementation follow-up](README.md#implementation-follow-up-from-dc59add8e) records component/behavior checks and their platform limits. This audit inspected the changes and retained evidence; it did not rerun those tests or establish a rendered FPS improvement. The [companion receipt](../ai-companions/AFC-02/rebinds/2026-11-22-339c29ec-to-43c52f4e.json) records nine 2,881-row baseline/candidate CSV matches. [Qualification CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45069083759) succeeded on its own recorded run head; it is not a qualification of a later combined source tree.

Main's recording-export repair and the `f1d1151a` U03/T04 changes modify the hashed simulation directories independently. Their then-accepted solver identities are respectively `7e404f01…` and `43c52f4e…`. Preserving both source changes would produce a third identity; neither existing receipt validates it. The two branches also update different companion behavior-manifest inputs (`app_root.gd` versus `main.gd`). The [AFC-02 rebind contract](../../../tools/companions/README.md) requires actual tape comparison before accepting a new solver pin; hand-selecting an old hash is invalid.

Accordingly, this publication adds reports and offline arithmetic on top of the preserved remote application tree through `ee46d96b`, including the subsequently observed I01 mismatch rather than silently changing its qualification. Main `85a2475f` remains the immutable analysis reference and the locally retained review snapshot. Combining the runtime branches is separate qualification work, not a documentation merge. Source links and the model explicitly identify main; the remote repair table identifies the audit branch. No combined-tree parity or latest-main feature availability in this branch is claimed.

### I01 — later presentation refactor leaves the older companion solver pin

The additional `ee46d96b` commit moves flap-angle projection from `FlightSession` into `main.gd`, validates the accepted AUX fraction there, and renews the caller's behavior manifest. Removing the seven-line session accessor changes the normalized simulation-source identity. The profile and `tools/companions/qualification.json` still contain the prior `43c52f4e…` solver pin. [Presentation change](https://github.com/bultodepapas/OpenRCsimulator/blob/ee46d96b7be4a77e040d814f6db71ab968751f01/app/main.gd#L3685-L3710), [identity algorithm](https://github.com/bultodepapas/OpenRCsimulator/blob/ee46d96b7be4a77e040d814f6db71ab968751f01/app/ai/companions/profile_loader.gd#L724-L784), [qualification](https://github.com/bultodepapas/OpenRCsimulator/blob/ee46d96b7be4a77e040d814f6db71ab968751f01/tools/companions/qualification.json).

The [retained offline witness](sixth-pass-solver-pin.json) reproduces the sorted-path/UTF-8/LF identity over **203 GDScript sources** for each pinned snapshot:

| Snapshot | Computed source identity | Stored profile/qualification | Match |
| --- | --- | --- | --- |
| Reviewed main `85a2475f` | `7e404f01…` | `7e404f01…` | Yes, control |
| Earlier audit `f1d1151a` | `43c52f4e…` | `43c52f4e…` | Yes, control |
| Later audit `ee46d96b` | `1bc57146…` | `43c52f4e…` | **No** |

This is a confirmed source-pin inconsistency at that commit, not evidence of changed flight dynamics or a measured FPS regression. The [runtime profile gate](https://github.com/bultodepapas/OpenRCsimulator/blob/ee46d96b7be4a77e040d814f6db71ab968751f01/app/ai/companions/profile_loader.gd#L332-L346) compares the profile solver pin with the readable current identity; qualification.json is the rebind record, not a file read by that runtime comparison. Under normal admission, a clean checkout enumerating these exact bytes is expected to refuse that companion profile. An explicitly invoked editor-only test override is separate, and missing packaged sources can produce a different refusal. This audit did not run the application to observe either outcome. The 203-source count belongs to these Git trees; extra on-disk sources or packaged enumeration may differ. The earlier nine-tape CSV receipt is not evidence for the removed-accessor source tree. Run the existing qualified rebind workflow against the actual desired source, compare the retained tapes, and update both pins only after that evidence. Do not merely paste the computed hash into configuration. Later branch commits may repair this issue; the witness deliberately keeps its immutable counterexample. [Reproduction instructions](../../../research/performance/graphics-audit-2026-11-22/README.md#solver-source-pin-witness).

## A practical plan for old hardware

On main `85a2475f` or a later qualified runtime containing the fixed-scale option, start from an explicitly recorded hardware/driver/power/memory configuration and native-reconstruction Low/75% at 1080p. The preserved audit runtime through `ee46d96b` lacks that new option; use an actually available, explicitly recorded comparison setup there rather than claiming it has main's baseline. Test a stable 30 FPS target first on weak devices, then a separate 60 FPS target with the required visual readability. Do not declare every ten-year-old machine supported: integrated GPU, memory channels, CPU power limits and driver support differ. Preserve user overrides and unknown-GPU behavior.

For each candidate, measure the complete affected boundary before implementation, then alternate baseline/candidate runs under the same accepted inputs, weather, camera and renderer. Keep physics pace, median/P95/P99 frame times and actual drawn/presented-frame identity. First-use construction needs cold and warm runs; steady work needs sustained flight. Record GPU time only where fresh and trustworthy. Report any moved cost at first enable/first draw.

| Platform/workload | What it must resolve |
| --- | --- |
| Windows and Linux old Intel/AMD iGPU, 1920×1080 | W02/W03 shader compilation, actual track coverage, motion/parity and complete frame tails; current W01 CPU attribution |
| Windows/Linux admitted native aircraft, spatial weather | Exact selected backend, full observer validity/failure/override behavior and actual accepted-tick cost |
| Ground vehicles and explicit flight/quad track | Chase/orbit, distant circuit, shoulders/banks/lighting; no inference from track-Off tours |
| Home and fresh night/flow world | W04 cold/warm construction and first presentation, cache invalidation and resource ownership |
| Apple Silicon at native Retina pixels | Separate Metal/Compatibility and native/reference admission; record output, drawable and internal pixels; no transplanted 1080p qualification |

Prefer a native batch when it removes a material interpreted loop or repeated boundary. For stars, that means one correctly packed instance buffer. For spatial observers, it means a qualified full-validity batch with current provider identity, not ten new scalar crossings or a cached stale RK stage. Use existing native GPU shaders for per-fragment work. Keep tiny key comparisons, 120 KiB/s of logical input slices and 39-bird scans on the watchlist until measured.

## Verification and independent challenge

Three helpers followed the repository's bounded source-research workflow; the lead integrated and checked their evidence. Independent reviews corrected the F17 novelty claim, shader thresholds and normal preservation, flight track-Off scope, product weather default, per-point turbulence callbacks, historical bird timing, star probe ownership and the pixel model's limits. Those corrections are incorporated in the linked reports.

The workspace temporarily disconnected after the initial offline calculation. GitHub read-only source/CI access remained available; local access recovered with the work intact. The final receipt also distinguishes the initial main-based checks from publication on the preserved remote branch, and records the completed offline arithmetic and documentation/source checks separately from application/native/rendered tests, which were not run for this documentation-only pass. Exact-main CI is linked in the receipt; a green job or release build does not establish these performance hypotheses. No production optimization is promoted by this audit branch.
