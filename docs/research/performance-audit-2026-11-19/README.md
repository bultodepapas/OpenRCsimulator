# OpenRC Simulator CPU/GPU optimization audit

Date: **2026-11-19**. Audited source: [`894357de83762ff6e0fdc47b0024e60f3d8286b7`](https://github.com/bultodepapas/OpenRCsimulator/commit/894357de83762ff6e0fdc47b0024e60f3d8286b7).
Report branch: `audit/cpu-gpu-optimization-2026-11-19`. This is a dated evidence snapshot; implementation ownership stays with the existing tracks.

## Executive assessment

The most useful next work is to **repair event/calibration correctness, then measure complete accepted-tick observers and render transitions**. OpenRC already has extensive optimized GDScript, native C++ stage evaluation, bounded history/cache designs and explicit fallback contracts. A wholesale language rewrite is not the evidence-supported starting point.

This report contains **35 findings and review items**: **4 reproduced defects**, **2 source-supported defects**, **3 measurement gaps**, **22 optimization candidates**, **3 intentional policy tradeoffs**, and **1 renderer constraint**. These are not 35 proven gameplay bugs or measured speedups. All candidate gains remain unmeasured in this audit.

| First action | Why it precedes broad optimization |
| --- | --- |
| F01–F02: event ordering and lost transitions | The actual solver can accept synthetic valid calls while omitting transitions; optimization must preserve correct chronology. |
| F04–F05: calibration pixel identity and stale High rejection | Automatic graphics decisions can reuse or discard measurements against inconsistent resolution identities. |
| F03/F06: validate restore publication and effective Retina scale | Source identifies narrower lifecycle/policy defects; establish their exact runtime coverage before promoting a repair. |
| F11–F16/F20/F27: complete CPU callback attribution | Contacts, audio, logs and event surfaces can remain expensive after the native force evaluator finishes. |
| F28–F31: cloud transitions and conditional GPU work | Cache reconciliation, readback and work for invisible layers are concrete targets for native-hardware profiling. |

P1 means correctness/decision repair first, **not** a measured frequency or catastrophic-risk rating. P2 means the next targeted investigation; P3 means a conditional/lower-priority candidate or a policy decision. Audit-local F01–F35 identifiers do not create a new project step namespace.

## Resolution status (2026-11-19)

Repairs landed in [`d736ee8a2`](https://github.com/bultodepapas/OpenRCsimulator/commit/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396). Each was reproduced before the change and has a regression test that fails on the pre-fix source (mutation check). Every check below is headless, on Godot 4.8-beta2 Windows x86_64, except F31. None of them measures a speedup.

| ID | Status | Change and evidence |
| --- | --- | --- |
| F01 | Fixed | `resource_event_step.gd`: an internal crossing seen only in the stage samples halves the step before any endpoint root is located. Before the boundary is committed, any surface that was enabled at the start of the segment and is already past zero beyond its tolerance causes a retry up to the earliest root, so a crossing between samples is not dropped. Several roots of one surface between samples remain undetectable by design. `test_resource_event_step`: 90 checks, 0 failed; 12 fail on the old solver. All 30 `test_glow_*` suites pass. |
| F02 | Fixed (+ lake) | The solver sorts by exact time, takes the tie set relative to the earliest root, and keeps the existing priority-first boundary inside it. Coincident rotor stop and fuel exhaustion still fire in priority order (`test_glow_counter_edges`). Scenery and lake collision (the same pattern) select through an anchored window. The six probe permutations all give A, B, C. `test_collision_tie_order`: 17 checks. The 339-check landscape collision oracle and 16 collision suites pass. |
| F03 | Fixed | `AirshipSession.restore_checkpoint` validates with the kernel's side-effect-free `prepare_reset()` before `resetting`, live arrays, fault or pause change. In `test_airship_flight_log`, a refused restore leaves the recorder, state, clock, tape and pause untouched, and 5 checks fail on the old code. |
| F04 | Fixed | Verdicts store output (window) pixels. Format 4 discards format 3 logical-canvas records once. The 1080p, 1440p and 4K UI-scale cases are in `test_auto_calibration`. |
| F05 | Fixed | `AutoCalibration.rejects_high()` is one-sided. A High miss measured at more than 1.5× the screen's pixels is ignored, while a miss in a 1080p window still holds on a 4K screen. |
| F06 | Fixed in source | The Retina estimate uses the root viewport's applied 3D scale; `auto_mode` is used only before reconstruction is applied. This still needs native Mac Retina evidence. |
| F07 | Fixed (scale, MSAA) | Verdicts record internal 3D pixels and 3D MSAA. A change in either measures again. Other settings are not part of the identity, by design. |
| F08 | Fixed | SubViewport activity is checked every sampled frame. One tree scan at the start plus `node_added` keeps a cached list, so no frame pays a full scan. |
| F09 | Unchanged (policy) | No retry budget was added. |
| F10 | Documented | The quantile convention is documented at `AutoCalibration._p95`; the behaviour is unchanged. |
| F28 | Fixed | `apply_sky` retargets every slot before any admission or eviction. For [A,B,C,D] to [E,A,B,C], bakes and evictions drop from 4 and 4 to 1 and 1. `test_cloud_shadow_reorder`: 16 checks; 13 fail on the old cache. |
| F31 | Fixed | A layer with exactly zero opacity skips its density and relief work while keeping the composite's density rounding. Rendered 640×360 sky hashes were identical before and after on Compatibility and Forward+ (Windows, RTX 3090), for mixed, all-zero, zero-density and opaque decks. The GPU saving is not measured. |
| F11–F27, F29, F30, F32–F35 | Open | These are measurement-gated candidates, a measurement gap and a renderer constraint, as classified above. F25 and F26 change native-mirrored sources (`aero.gd`, wind), which requires native requalification. The rest need complete-workload profiling or hardware, audio or visual acceptance under their owning tracks. |

Solver identity: the edits to `app/physics` and `app/sim` renew the AI-companion qualification pin (AFC-02-R3 re-bind). None of the edited files is a native-kernel mirrored source, so native admission is unchanged. `test_scenery_destruction_runtime` (5 of 8 failing) fails identically on the pre-fix sources and is unrelated. The [reproduction runner](../../../research/performance/audit-2026-11-19/README.md) stays pinned to the audited baseline, and it refuses the repaired sources by design.

## Scope, source identity and limits

The baseline is main at `894357de8376` (2026-11-19), obtained from the public GitHub repository and checked out into an isolated source-only branch. The inventory has **52,035 tracked files**, **2,016 app GDScript files** (1,195 under `app/tests/`), **95 app shader/include files**, and **54 C++/header files** under the native-kernel core. These counts describe scope, not exhaustive review.

The review followed high-risk call chains through simulation, event integration, propulsion/fuel, contact observers, audio/statistics/recording, experimental vehicles, automatic graphics, cloud/grass/water/shadow rendering and resource lifecycle. Existing research, plans, tests and GitHub PR metadata were checked for duplicate or already-fixed leads. Current source takes precedence over stale planning text or PR status.

Three helpers researched independent CPU/native, GPU/render and runtime/memory questions. The lead checked material source and integrated findings; two helpers independently challenged the numerical/calibration evidence. Requested helper routing was GPT-6.1 Terra/max; model selection is not evidence of correctness. The counterexamples and caveats below are the evidence.

**Executed:** isolated headless checks with the official pinned **Godot 4.8-beta2 (`cafc17a19`) Linux x86_64** binary. Its SHA-512 matches `app/get-godot.sh`; fixture dependencies were copied byte-for-byte and hashed. The unrelated system Godot 4.6.3 was not used for evidence.

**Not executed:** a full asset import, rendered flight, native C++ build/oracle campaign, real GPU timing/capture, native Mac/Windows run, audio listening, long recording, memory soak, release packaging or full CI. The sparse checkout omits binary assets. No FPS, CPU saving, VRAM residency or target-hardware qualification is claimed. Runtime files remain unchanged by this audit.

**Publication-time drift check:** main advanced to [`b2f81d1771031964446a1cbddd83770d6d1c87ff`](https://github.com/bultodepapas/OpenRCsimulator/commit/b2f81d1771031964446a1cbddd83770d6d1c87ff) during the audit. The inspected eight-file delta adds the v0.2.9 version/release documentation and renews D11g inventory guards; no finding-related runtime implementation or fixture dependency changed. The report and probes remain pinned to the original baseline. The exact delta is recorded in evidence.json.

The [source manifest](source_identity.json) pins cited code and document hashes. The [machine-readable register](findings.json) contains all findings, proposed actions, evidence limits and source ranges. [Primary API references](sources.json) support engine context; exact application behavior comes from the pinned repository and probes.

## Reproduced evidence

| Check | Observed result | What it establishes |
| --- | --- | --- |
| Existing resource-event control | **54 checks, 0 failed** | Existing focused tests pass while the additional counterexamples expose uncovered behavior. |
| F01 mixed interior/endpoint crossings | At T=1/240 s, both event orders accept only A at 0.75T; B at 0.2T is absent | Generic solver correctness counterexample at the production timestep; no stock-aircraft occurrence claimed. |
| F02 tolerance ordering | B&lt;A, C&lt;B, A&lt;C; six permutations give three distinct accepted flag sets | Non-transitive ordering and accepted lost events on a tiny valid synthetic interval. |
| F04 UI/window pixels | 1440p and 4K windows expose a 1080p logical canvas; same-window matching fails | Actual headless UiScale/Window behavior plus the inconsistent calibration boundary. |
| F05 stored High rejection | Injected 4K-labeled rejection fails the 1080p size check but suppresses High in plan() | Missing consumer-side size validation, isolated from F04. |
| F06 Retina estimate | Policy calculation: 2/3-scale M1 example recommends Medium, Native recommends Low | Capability-table sensitivity to assumed scale; no Mac/GPU execution. |
| F09 incomplete calibration | 200 valid synthetic samples save complete=false; same-key needed() returns false | Intentional neutral/no-retry behavior, not a passed GPU measurement. |
| F10 quantile boundary | 285 fast + 15 slow values: nearest-rank p95=1 ms, calibration p95=20 ms | Different conventions; the stricter calibration behavior is explicitly tested already. |
| Rejected packed-array lead | Append through a dictionary-held PackedFloat64Array alias is visible through all aliases | This operation does not support the suspected copy-on-write/O(n²) claim. |

The two audit probes return success when they finish collecting observations; that exit status does **not** mean the solver has been repaired. The reproduction runner separately checks that the pinned baseline observations recur. A repaired candidate should change relevant observations and requires its own regression/qualification evidence.

Run the [reproduction recipe](../../../research/performance/audit-2026-11-19/README.md). [Evidence and provenance](evidence.json) records checked-run completion, source/engine hashes, raw observations and harness corrections. One exploratory control used an incorrect expected `36 checks` marker: the engine actually passed 54 checks and the wrapper correctly rejected the missing marker. The corrected 54-check run is the qualifying control. The exploratory 2 ms event probe is not used to claim a duplicate-event defect because its transitions re-arm their surfaces.

## Complete finding register

| ID | Priority | Classification | Finding | Owning tracks |
| --- | --- | --- | --- | --- |
| [F01](#f01) | P1 | Reproduced defect | A detected interior event can be lost behind a later endpoint crossing | SF, NITRO |
| [F02](#f02) | P1 | Reproduced defect | Tolerance-based ordering is non-transitive and can lose near-tie events | SF, NITRO, SC |
| [F03](#f03) | P2 | Source-supported defect | Airship restore publishes reset side effects before validating the replacement body | BL-07, BL-08, SF |
| [F04](#f04) | P1 | Reproduced defect | Calibration stores logical UI pixels but validates against window pixels | VQ-07h, DT-MAC, UI |
| [F05](#f05) | P1 | Reproduced defect | Automatic High reuses a rejection without checking its measurement size | VQ-07h, DT |
| [F06](#f06) | P2 | Source-supported defect | Retina scene-detail estimates use hypothetical Automatic scale rather than the selected viewport scale | VQ-07h, DT-MAC |
| [F07](#f07) | P2 | Measurement gap | Saved calibration does not identify several settings that determine its GPU workload | VQ-07h, DT-MAC |
| [F08](#f08) | P2 | Measurement gap | Calibration checks secondary-view activity only at the end of its sample interval | VQ-07h, DT-MAC, VQ |
| [F09](#f09) | P3 | Policy tradeoff | An incomplete calibration suppresses later retries by design | VQ-07h |
| [F10](#f10) | P3 | Policy tradeoff | HUD and calibration use different p95 conventions at the decision boundary | VQ-07h, PT |
| [F11](#f11) | P2 | Optimization candidate | Incident observations repeat wheel-compression work on every accepted tick | CR-40, CC-00–17, GP-14 |
| [F12](#f12) | P2 | Optimization candidate | Master mute leaves flight-audio computations running | AUD-12b, SF |
| [F13](#f13) | P2 | Optimization candidate | Opt-in flight logs serialize and flush packets on the simulation thread | FL-01, DT-MAC-04b |
| [F14](#f14) | P2 | Optimization candidate | Stopping a manual trace performs whole-history export inline | DT-MAC-04b, FL |
| [F15](#f15) | P2 | Optimization candidate | Ground audio can recompute accepted contact laws and support queries | GP-19, GP-19f, AUD |
| [F16](#f16) | P3 | Optimization candidate | Flight audio independently requests wind, air data and propulsion observations | AUD, SF, DT-MAC-04b |
| [F17](#f17) | P3 | Optimization candidate | Statistics continues substantial accepted-tick derivation with its widget closed | UI-FS-08-R1, UI-FS-08-R2 |
| [F18](#f18) | P3 | Optimization candidate | Helicopter and airship presentation still mix interpolation needs with display-only work | HELI-09, HELI-16-R1, BL-17 |
| [F19](#f19) | P3 | Policy tradeoff | Bounded input tapes create deliberate memory and duration limits | DR-16b, DR-17, BL-07, BL-08, BL-17 |
| [F20](#f20) | P2 | Optimization candidate | Glow event surfaces repeat full point evaluation outside the native stage | NITRO, SF, NK-3 |
| [F21](#f21) | P2 | Optimization candidate | Opt-in servo intervals repeatedly prepare trajectories and validate guarded context | AC-12, SF, NK |
| [F22](#f22) | P2 | Optimization candidate | Reference liquid-fuel stages repeat configuration validation and result construction | FUEL-12, NK-3 |
| [F23](#f23) | P2 | Optimization candidate | Multirotor contact substeps and framed transaction checks need whole-tick attribution | DR-16, DR-17, SF |
| [F24](#f24) | P2 | Optimization candidate | Airship terminal-contact observation can evaluate more ground forces than its consumer needs | BL-12, BL-17 |
| [F25](#f25) | P2 | Optimization candidate | Coupled flap loops recompute station-only clean terms inside the pair loop | NK-2a, NK-3, SF |
| [F26](#f26) | P3 | Optimization candidate | The existing temporal-wind candidate is blocked by native source identity, not missing implementation | NK-3, M5-W |
| [F27](#f27) | P2 | Measurement gap | Kernel timing and diagnostic instrumentation do not represent complete frame cost | PT, SF, DT-MAC-04b, VQ |
| [F28](#f28) | P2 | Optimization candidate | Cloud-cache slot updates can evict keys needed later in the same transition | DT-MAC, FW |
| [F29](#f29) | P2 | Optimization candidate | Cloud baking reads an HDR render target back to CPU and uploads a converted texture | DT-MAC, FW |
| [F30](#f30) | P2 | Optimization candidate | Procedural grass collapses distant vertices after instance submission | VQ, LU, DT-MAC |
| [F31](#f31) | P2 | Optimization candidate | Zero-opacity cloud layers still compute density before alpha evaluation | FW, DT-MAC |
| [F32](#f32) | P2 | Renderer constraint | Water refraction inherits opaque-screen-copy limitations and bandwidth cost | VQ-07, LU, DT-MAC |
| [F33](#f33) | P3 | Optimization candidate | Vegetation resources remain strongly cached for process lifetime | LU, SC, DT-MAC |
| [F34](#f34) | P3 | Optimization candidate | Visible lens film resubmits unchanged material parameters each frame | VQ, DT-MAC |
| [F35](#f35) | P3 | Optimization candidate | Field projected-shadow geometry is prepared before policy may hide it | VQ-04b, SA-11, SA-12, DT-MAC |

### F01

**A detected interior event can be lost behind a later endpoint crossing**

P1 · Reproduced defect · CPU / numerical correctness · Owners: SF, NITRO.

**Evidence.** ResourceStep records an internal crossing from RK stage samples, but processes endpoint-bracketed crossings before the subdivision path. In the retained exact-source probe, T = 1/240 s, A(t) = 0.75 - t/T and B(t) = (t/T - 0.2)(t/T - 0.8), both falling. B crosses at 0.2T and is negative at the sampled midpoint; A crosses at 0.75T. Both event-list orders return ok=true with only A and flags [1,0]. The expected enabled transitions are B then A. Committing A leaves the earlier falling crossing behind the accepted time.

**Impact.** The generic solver can accept a tick with a missing resource transition. Glow flight is a production caller with nontrivial pickup surfaces, so correctness must be established before batching or moving these event computations to native code.

**Recommended action.** Resolve an already-detected internal crossing before committing a later endpoint root. Preserve bounded subdivision/evaluation budgets, transition validation and transactional rollback. Do not claim that a finite set of stage samples can detect every arbitrarily short excursion.

**Verification.** Add the retained mixed-crossing fixture to the owning regression suite; test both event orders, rising/falling senses, reverse root order, transitions that change other surfaces, rejected transitions and exhausted budgets. Add a reachable glow pickup/fuel fixture and exact replay checks before assigning aircraft-level severity.

**Limits.** Reproduced at the production timestep using synthetic, valid event functions and the actual solver. No stock-aircraft trajectory demonstrating this failure was flown. No performance impact was measured.

**Prior tracking.** New counterexample to the shared resource-event API; the existing 54-check suite does not cover this mixed-crossing case.

**Pinned sources:** [app/physics/resource_event_step.gd:57–92](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L57-L92); [app/physics/resource_event_step.gd:118–158](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L118-L158); [app/physics/resource_event_step.gd:315–328](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L315-L328); [app/physics/glow/flight.gd:379–407](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/glow/flight.gd#L379-L407); [app/tests/test_resource_event_step.gd:1–35](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/tests/test_resource_event_step.gd#L1-L35).

### F02

**Tolerance-based ordering is non-transitive and can lose near-tie events**

P1 · Reproduced defect · CPU / numerical correctness · Owners: SF, NITRO, SC.

**Evidence.** ResourceStep sorts by priority when two offsets differ by at most 1e-12 s, otherwise by time. With A=0/priority20, B=0.75e-12/priority11 and C=1.5e-12/priority0, B<A, C<B and A<C. The public advance() probe uses distinct disabling flags and a valid 4e-12 s interval: six input permutations yield three different accepted flag sets, each twice, omitting one or two transitions. A later high-priority root can also precede an earlier near-tie root whose residual then fails revalidation. SceneryCollision uses the same non-transitive pattern with fractions and obstacle IDs.

**Impact.** The solver result can depend on event discovery order. In scenery, choosing the first contact using this comparator has a mathematical ordering risk; a changed physical collision result has not been reproduced.

**Recommended action.** Use a transitive finite-time order, then define a tie set relative to an explicit earliest anchor and apply the documented priority/ID policy within that set. Preserve root uncertainty, residual checks and transition-induced surface changes. A skipped near-tie surface must not silently disappear after advancing time. The race director has a useful separate earliest/group pattern to study, not a drop-in implementation.

**Verification.** Exercise all permutations, two-event near ties, chains straddling the tolerance, equal priorities, duplicate-ID rejection, uncertain brackets and state-changing transitions. Add real scenery geometry with competing hull probes and compare first-hit results. Preserve deterministic event records and exact replay.

**Limits.** The clean public-API witness is a tiny admitted synthetic interval, not a 240 Hz flight. The separate exploratory 2 ms probe re-arms its surfaces, so its repeated event is not evidence of an independent duplicate-event bug. Scenery FRACTION_TIE is dimensionless: 1e-12 of a 240 Hz tick is about 4.17e-15 s. Sorted world IDs do not prove every discovery order is reachable.

**Prior tracking.** New solver counterexample and a second, source-supported occurrence in scenery collision ordering; one root-cause family, not two independently reproduced gameplay failures.

**Pinned sources:** [app/physics/resource_event_step.gd:103–128](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L103-L128); [app/sim/scenery_collision.gd:15](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/scenery_collision.gd#L15); [app/sim/scenery_collision.gd:127–180](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/scenery_collision.gd#L127-L180); [app/sim/scenery_collision.gd:654–659](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/scenery_collision.gd#L654-L659); [app/sim/flight_session.gd:3640–3646](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L3640-L3646); [app/sim/race/race_director.gd:250–258](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/race/race_director.gd#L250-L258); [app/sim/race/race_director.gd:296–304](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/race/race_director.gd#L296-L304).

### F03

**Airship restore publishes reset side effects before validating the replacement body**

P2 · Source-supported defect · CPU / state lifecycle · Owners: BL-07, BL-08, SF.

**Evidence.** AirshipSession.restore_checkpoint() checks preparation and continuous-array size, emits resetting, changes inputs/continuous data and then calls sim.reset(). The latter can reject a malformed body. An active airship flight log listens to resetting and synchronously finalizes and closes; the kernel failure path restores its protected physical snapshot but faults and pauses. Thus rejection can publish externally visible reset effects before a replacement is accepted.

**Impact.** A direct restore call on a prepared session with active recording and an invalid quaternion/NaN body can terminate that recording and change lifecycle state despite rejected physical reset. The rows already written are finalized, not shown lost or overwritten.

**Recommended action.** Prepare and validate a detached replacement before publishing accepted-reset side effects. Keep physical state, clock, inputs, observers and recorder ownership coherent under rejection; do not merely suppress kernel validation or the fault signal.

**Verification.** Add an active-recording restore test with a correctly sized continuous array and malformed body, plus evaluator failure, invalid continuous data and a valid restore. Define the rejection contract and verify state/clock, pause/fault state, observer notifications and one accepted recorder closure. Include test_airship_session.gd and test_airship_flight_log.gd.

**Limits.** Source-supported API defect; not executed in this audit. Normal flight-log verification constructs a fresh session, so this is not evidence that ordinary replay interrupts a live player recording. Interactive reachability beyond the direct API remains to establish.

**Prior tracking.** New source-level restore transaction finding; the airship plan already requires rejected-reset safety.

**Pinned sources:** [app/sim/airship/session.gd:509–516](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L509-L516); [app/sim/airship/flight_log.gd:84–89](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L84-L89); [app/sim/airship/flight_log.gd:104–116](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L104-L116); [app/sim/airship/flight_log.gd:155–156](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L155-L156); [app/sim/airship/flight_log.gd:277–299](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L277-L299); [app/sim/simulation.gd:113–119](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L113-L119); [app/sim/simulation.gd:935–959](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L935-L959); [docs/plans/rc-airship.md:260](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/rc-airship.md#L260).

### F04

**Calibration stores logical UI pixels but validates against window pixels**

P1 · Reproduced defect · GPU / automatic graphics · Owners: VQ-07h, DT-MAC, UI.

**Evidence.** AutoCalibration stores get_visible_rect().size as the measured pixel count. AppRoot and SceneDetail compare that record with Window.size. With actual UiScale.apply() on the pinned headless engine, windows of 1920x1080, 2560x1440 and 3840x2160 all expose a 1920x1080 logical canvas. size_matches is true for the first and false for the other two, although each comparison refers to the same window before/after calibration.

**Impact.** A valid higher-resolution measurement can be labeled as 1080p, its scene offset ignored, and calibration requested again on the next flight. It also contaminates any later decision that trusts the stored pixel identity.

**Recommended action.** Define a consistent output-size identity for measurement, storage and consumers. Reconstruction.viewport_output_size() already estimates non-embedded output pixels; use or reconcile that boundary, while recording drawable and internal 3D pixels separately. Version/invalidate old logical-size records instead of relabeling unknown measurements.

**Verification.** Cover 1080p, 1440p, 4K, UI scale/stretch, resize and display changes. Verify one completed measurement is reused only for a comparable workload. Add native Windows/Linux and Mac Retina checks for actual output/drawable/internal pixels; preserve explicit settings.

**Limits.** The headless test establishes Godot Window/CanvasItem scaling behavior and pure matching logic. It does not measure GPU time or native high-DPI drawable dimensions.

**Prior tracking.** New isolated reproduction of a current calibration identity mismatch.

**Pinned sources:** [app/render/auto_calibration.gd:107–118](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L107-L118); [app/render/auto_calibration.gd:263–283](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L263-L283); [app/app_root.gd:1736–1744](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L1736-L1744); [app/render/scene_detail.gd:108–121](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/scene_detail.gd#L108-L121); [app/ui/ui_scale.gd:1–55](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/ui/ui_scale.gd#L1-L55); [app/render/reconstruction.gd:657–668](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/reconstruction.gd#L657-L668).

### F05

**Automatic High reuses a rejection without checking its measurement size**

P1 · Reproduced defect · GPU / automatic graphics · Owners: VQ-07h, DT.

**Evidence.** RendererPreference.facts() reads reject_high from the adapter/Forward+ record without size_matches(). The isolated probe saves a complete 4K-labeled rejection, verifies that it does not match 1080p, then calls the actual plan() with 1080p facts. Automatic remains Standard; identical facts without the stale rejection choose High. The consumer obtains pixels from the current screen, not necessarily the window.

**Impact.** A rejection from a materially different output workload can suppress Automatic High after a screen/resolution change, even when the current hardware policy would select it.

**Recommended action.** Validate the record against the same agreed measurement boundary and relevant workload identity before carrying its rejection into plan(). Preserve explicit user High selection and renderer startup/failure guards. Address F04 first so the size metadata itself is trustworthy.

**Verification.** Test changed/current 1080p screen facts after a 4K measurement, unchanged-size rejection, unknown sizes, multi-monitor changes, adapter/renderer changes and explicit modes. Extend test_auto_calibration.gd and renderer preference tests with the isolated stored-verdict case.

**Limits.** The 4K-labeled record is deliberately injected to isolate the missing check; it is not an observed real 4K calibration record. F04 may cause production measurements to be mislabeled. The plan test is headless policy execution, not measured evidence that High meets a frame budget.

**Prior tracking.** New isolated policy reproduction; related to F04 but a separate consumer-side check.

**Pinned sources:** [app/app_state/renderer_preference.gd:109–116](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_state/renderer_preference.gd#L109-L116); [app/app_state/renderer_preference.gd:137–153](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_state/renderer_preference.gd#L137-L153); [app/app_state/renderer_preference.gd:203–207](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_state/renderer_preference.gd#L203-L207); [app/render/auto_calibration.gd:263–270](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L263-L270).

### F06

**Retina scene-detail estimates use hypothetical Automatic scale rather than the selected viewport scale**

P2 · Source-supported defect · GPU / resolution policy · Owners: VQ-07h, DT-MAC.

**Evidence.** SceneDetail._native_render_pixels() uses Reconstruction.auto_mode(runtime_capabilities(), screen). This correctly considers runtime support/global blocks, but it does not read an explicit user Native/other selection or the viewport-specific reconstruction failure latch. AppRoot applies the saved reconstruction before scene detail. Pure policy math for a 2560x1600 M1 panel gives 1,818,596 estimated internal pixels at 2/3 scale versus 4,096,000 at Native; the current table chooses Medium versus Low respectively.

**Impact.** Automatic scene detail can be selected against a smaller hypothetical workload than the viewport actually renders, particularly after an explicit scale choice or local scaler fallback.

**Recommended action.** Base the recommendation on the selected/effective reconstruction and the target panel policy, with a documented fallback when internal-size evidence is unavailable. Reconcile screen, output, drawable and internal pixels; do not assume every supported Mac is currently using MetalFX.

**Verification.** On native Retina hardware, test Automatic, explicit Native, each supported scale, unsupported/global-blocked providers and viewport-specific failure. Compare policy identity with the active viewport, preserve saved settings and evaluate sustained motion/readability.

**Limits.** The numerical example injects scales into the capability functions; it is not a Mac execution or a GPU benchmark. Capability/global-failure checks already exist and must not be described as absent. Actual panel/backing-store behavior still needs host evidence.

**Prior tracking.** Scoped current-source mismatch; the automatic-graphics plan already owns resolution-aware policy work.

**Pinned sources:** [app/render/scene_detail.gd:129–138](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/scene_detail.gd#L129-L138); [app/render/reconstruction.gd:227–263](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/reconstruction.gd#L227-L263); [app/app_root.gd:2078–2081](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L2078-L2081); [app/render/gpu_capability.gd:1–40](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/gpu_capability.gd#L1-L40); [docs/plans/automatic-graphics.md:66](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/automatic-graphics.md#L66).

### F07

**Saved calibration does not identify several settings that determine its GPU workload**

P2 · Measurement gap · GPU / calibration identity · Owners: VQ-07h, DT-MAC.

**Evidence.** The saved key and reuse logic track adapter, renderer, pixel count and scene level. They do not identify the selected/effective reconstruction scale, MSAA or other major graphics-workload changes. A settings change can therefore retain a verdict from a substantially different render workload even after pixel-size matching is repaired.

**Impact.** An old up/down/High verdict may over- or under-estimate the current configuration. This weakens the value of a one-time measurement and makes optimization comparisons harder to interpret.

**Recommended action.** Add a versioned, minimal workload identity for the settings actually needed by the decision, including effective reconstruction/fallback. Invalidate or request bounded recalibration at explicit settings boundaries. Avoid hashing every runtime value or recalibrating for irrelevant presentation changes.

**Verification.** Change one workload setting at a time and verify the intended reuse/invalidation table; include saved overrides, restart, fallback, preset reset, imported old records and unchanged sessions. Measure calibration overhead and retry frequency.

**Limits.** Source-supported coverage gap; not proof that every setting deserves its own persistent key or that a user has experienced a bad recommendation. No GPU samples were collected.

**Prior tracking.** Current schema limitation; propose a narrow identity extension rather than a second calibration system.

**Pinned sources:** [app/render/auto_calibration.gd:220–260](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L220-L260); [app/render/auto_calibration.gd:273–283](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L273-L283); [app/render/reconstruction.gd:227–263](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/reconstruction.gd#L227-L263).

### F08

**Calibration checks secondary-view activity only at the end of its sample interval**

P2 · Measurement gap · GPU / timing attribution · Owners: VQ-07h, DT-MAC, VQ.

**Evidence.** The calibrator samples root-viewport GPU time throughout the interval, but _subviewports_active() is called only when producing the final verdict. Magnifier and optional planar-water views render outside that root timing. A view active earlier but closed at completion is not represented by the final flag; a view still active blocks raising detail but does not supply its GPU cost.

**Impact.** The interval can be labeled more completely than its evidence allows, and root timing cannot by itself explain total rendering cost or a complete frame budget.

**Recommended action.** Track whether extra views participated anywhere in the measured interval, record the timing scope and mark incomplete attribution explicitly. Define a conservative policy for such intervals. Do not simply add viewport timings without establishing overlap, freshness and backend semantics.

**Verification.** Toggle magnifier/reflections during warmup, mid-sample and immediately before completion; compare persistent and transient activity. Use native GPU/frame evidence per backend, including CPU-bound frames and unknown/zero timing samples.

**Limits.** Static source finding; no rendered interval or backend timing was measured. Optional views and their enablement matter; this is not a claim that the default scene always renders all of them.

**Prior tracking.** Current timing-boundary limitation; the root-viewport scope is already documented in source.

**Pinned sources:** [app/render/auto_calibration.gd:96–118](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L96-L118); [app/render/auto_calibration.gd:141–146](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L141-L146); [app/render/auto_calibration.gd:181–206](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L181-L206); [app/render/camera/magnifier.gd:61–69](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/camera/magnifier.gd#L61-L69); [app/render/camera/magnifier.gd:125–138](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/camera/magnifier.gd#L125-L138); [app/render/camera/magnifier.gd:211–215](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/camera/magnifier.gd#L211-L215); [app/render/lake/lake_planar_reflection.gd:29–30](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/lake_planar_reflection.gd#L29-L30).

### F09

**An incomplete calibration suppresses later retries by design**

P3 · Policy tradeoff · GPU / calibration recovery · Owners: VQ-07h.

**Evidence.** evaluate() returns complete=false for the retained 200-valid-sample input. Saving that neutral result and calling needed() for the same adapter/method/pixels/level returns false. The source explicitly states that an unmeasurable flight stores a neutral verdict instead of retrying forever.

**Impact.** A transient shortage/unavailability of timing samples can leave the user on the heuristic recommendation even when a later flight could provide useful measurements.

**Recommended action.** If coverage is worth the cost, consider a bounded retry budget/backoff or explicit recalibrate action, while preserving the original anti-loop goal. Keep incomplete measurements neutral and distinguish them from complete evidence.

**Verification.** Test too few/invalid samples, recovery of timings, repeated unavailable hosts, restart, settings changes and exhausted retry budgets. Measure added work; avoid retries that perturb every flight.

**Limits.** Observed policy behavior, not a correctness regression. Low frame rate alone is not enough to predict sample count because delta clamping and active-time accumulation can extend wall-clock collection.

**Prior tracking.** Intentional anti-retry-loop policy, not an accidental failed-measurement success or mandatory bug fix.

**Pinned sources:** [app/render/auto_calibration.gd:107–118](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L107-L118); [app/render/auto_calibration.gd:161–181](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L161-L181); [app/render/auto_calibration.gd:273–283](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L273-L283).

### F10

**HUD and calibration use different p95 conventions at the decision boundary**

P3 · Policy tradeoff · CPU / performance statistics · Owners: VQ-07h, PT.

**Evidence.** On the same synthetic 300 values (285 at 1 ms, 15 at 20 ms), HUD nearest-rank p95 is 1 ms while calibration p95 is 20 ms and rejects High. Calibration selects floor(0.95*N), whereas nearest rank uses ceil(0.95*N)-1. The existing calibration test explicitly expects rejection with exactly a 5% slow tail (570 fast and 30 slow samples).

**Impact.** The label p95 can conceal a materially different threshold decision. This matters when comparing tools and explaining automatic choices, especially with discrete small samples.

**Recommended action.** Document the chosen quantile definition and threshold semantics at each interface. If a shared convention is desired, obtain an owning-policy decision and update compatibility tests; do not present changing the index as a universally safe off-by-one fix.

**Verification.** Use boundary sample counts around multiples of 20 and 5% slow tails; compare documented order statistics and resulting decisions. Keep interval, render CPU and GPU metrics distinct.

**Limits.** Different quantile conventions can be valid. The live HUD and calibrator also normally observe different metrics, so the synthetic comparison is not evidence that their real displayed numbers should match.

**Prior tracking.** Established/tested calibration policy; document the convention before proposing a behavioral change.

**Pinned sources:** [app/render/auto_calibration.gd:161–206](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L161-L206); [app/render/auto_calibration.gd:169–173](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L169-L173); [app/render/hud.gd:44–53](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/hud.gd#L44-L53); [app/tests/test_auto_calibration.gd:90–92](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/tests/test_auto_calibration.gd#L90-L92).

### F11

**Incident observations repeat wheel-compression work on every accepted tick**

P2 · Optimization candidate · CPU / accepted-state observers · Owners: CR-40, CC-00–17, GP-14.

**Evidence.** Ordinary interactive fixed-wing flights enable cost observations. Their committed-tick handler calls gear_compressions() on every accepted tick. For equipped gear using terrain/lake/track surfaces, it transforms supports and samples terrain even far above ground; the flat-ground fallback is simpler and gearless queries return empty. The contact-event consumer emits nothing when both previous and current compression are nonpositive. Statistics independently derives compression near contact.

**Impact.** Avoidable accepted-tick CPU work can survive a fast native stage evaluator. Multiple consumers can repeat the same endpoint geometry/terrain derivation.

**Recommended action.** Share a detached accepted-endpoint support result or prove a conservative no-touch shortcut. Preserve previous-positive to ended events and invalidation on gear/configuration changes. Reuse the accepted endpoint, not the RK4 fourth-stage approximation.

**Verification.** Compare event sequences for touchdown, liftoff, retraction, reset/restore, circuit, lake and terrain cases. Run test_crash_cost_producers.gd, test_ground_accident_session.gd and test_flight_statistics_terrain.gd; profile matched incident-on/off complete flights.

**Limits.** Source confidence high; savings and dominant scenarios unknown. Do not disable incident accounting or infer that all support work is redundant.

**Prior tracking.** New reuse candidate; the accepted gear-contact producer itself is implemented.

**Pinned sources:** [app/main.gd:1320–1325](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/main.gd#L1320-L1325); [app/main.gd:3072–3075](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/main.gd#L3072-L3075); [app/sim/flight_session.gd:2580–2587](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L2580-L2587); [app/sim/flight_session.gd:2745–2761](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L2745-L2761); [app/physics/ground_wheels.gd:216–233](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/ground_wheels.gd#L216-L233); [app/sim/flight_session.gd:3344–3349](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L3344-L3349); [app/physics/ground_contact.gd:428–440](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/ground_contact.gd#L428-L440); [app/sim/aircraft_contact_events.gd:281–285](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/aircraft_contact_events.gd#L281-L285); [app/statistics/fixed_wing_adapter.gd:140–154](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/statistics/fixed_wing_adapter.gd#L140-L154); [docs/plans/crash-damage-economics.md:231](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/crash-damage-economics.md#L231).

### F12

**Master mute leaves flight-audio computations running**

P2 · Optimization candidate · CPU / disabled-feature work · Owners: AUD-12b, SF.

**Evidence.** Game volume zero mutes the Master bus but does not suppress FlightAudio construction. The adapter continues accepted-tick contacts and per-frame wind, air, torque and mix-state work. The existing --soundscape=off route avoids construction but is distinct from the player volume setting.

**Impact.** A player who silences audio still pays much of its source-side CPU cost. Removing this work could help CPU-bound sessions without changing the flight model.

**Recommended action.** After required fades/retirement, suspend unnecessary generation and observation while fully muted; re-prime from the current accepted state on unmute. Preserve necessary safety/event semantics, avoid stale impact replay and handle preview/revert.

**Verification.** Test zero/nonzero volume, settings preview/revert, pause, crash, rewind, reset and listener changes. Count callbacks and compare physics bytes; use test_flight_audio_accepted.gd, test_ground_audio.gd, test_mechanical_accepted_ticks.gd, test_soundscape.gd and settings integration. Listen on real audio hardware.

**Limits.** The source proves work remains, not its current cost. Event-history/fade requirements may justify a small residual observer while muted.

**Prior tracking.** Volume behavior is tracked; no exact mute-processing optimization was found locally.

**Pinned sources:** [app/app_root.gd:2055–2059](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L2055-L2059); [app/main.gd:1268–1272](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/main.gd#L1268-L1272); [app/audio/flight_audio.gd:146–158](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L146-L158); [app/audio/flight_audio.gd:187–198](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L187-L198); [app/audio/flight_audio.gd:234–250](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L234-L250); [app/audio/flight_audio.gd:440–466](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L440-L466); [docs/plans/audio-realism.md:87](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/audio-realism.md#L87).

### F13

**Opt-in flight logs serialize and flush packets on the simulation thread**

P2 · Optimization candidate · CPU / storage hitches · Owners: FL-01, DT-MAC-04b.

**Evidence.** Fixed-wing .orfl recording buffers up to 240 rows, then its accepted-tick callback serializes, hashes, writes and flushes synchronously. Fixed-wing pause/stop also flush. Multirotor and airship writers likewise flush packets on tick/stop paths; their pause-event buffering is not identical.

**Impact.** Slow storage can block an individual accepted-tick callback even though buffers/files are bounded. Average kernel timing can hide this intermittent tail.

**Recommended action.** Evaluate a bounded writer with immutable packets, sequence ordering, explicit backpressure/failure and accepted ownership. Preserve checksums, replay identity, complete/incomplete footers and crash recovery. Separate serialization cost from filesystem latency before choosing threading.

**Verification.** Measure recording-off/on frame and full callback distributions on normal and slow storage. Inject write failure/full disk and shutdown during backlog. Run test_flight_log.gd, test_flight_log_inputs.gd, test_mr_flight_log.gd and test_airship_flight_log.gd plus ordering/recovery cases.

**Limits.** A known synchronous path, not a measured stall in this audit and not an unbounded-memory leak. Asynchronous writes need a defined durability tradeoff.

**Prior tracking.** Already documented in the flight-log guide and Apple performance plan; retained here because it remains in current source.

**Pinned sources:** [app/sim/flight_log.gd:284–306](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_log.gd#L284-L306); [app/sim/flight_log.gd:350–379](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_log.gd#L350-L379); [app/sim/multirotor/flight_log.gd:138–155](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/flight_log.gd#L138-L155); [app/sim/multirotor/flight_log.gd:190–228](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/flight_log.gd#L190-L228); [app/sim/airship/flight_log.gd:124–136](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L124-L136); [app/sim/airship/flight_log.gd:168–203](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/flight_log.gd#L168-L203); [docs/FLIGHT-LOGGING.md:335–342](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/FLIGHT-LOGGING.md#L335-L342); [docs/plans/apple-silicon-performance.md:349–355](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/apple-silicon-performance.md#L349-L355).

### F14

**Stopping a manual trace performs whole-history export inline**

P2 · Optimization candidate · CPU / user-visible storage stalls · Owners: DT-MAC-04b, FL.

**Evidence.** The fixed-wing and helicopter T-key paths call recorder.stop() directly. Fixed-wing export joins the spool worker when one exists, then reads, formats, writes and flushes the full recording. Helicopter export has the analogous full-history path. The active raw pipeline is bounded, but export work and disk data grow with duration; the saved spool remains owned until cleared/released.

**Impact.** A long recording can create a stop-time input/render stall even if steady recording is inexpensive. Bounded RAM does not bound finalization time.

**Recommended action.** Move eligible export work to a bounded background job over frozen recording ownership, publish atomically and preserve recovery/retry. Keep explicit completion/failure state and safe exit behavior; avoid copying the whole trace into memory.

**Verification.** Compare 1-, 10- and 60-minute stop latency/input gaps. Exercise stop, exit, reset, retry, destination failure and cleanup using test_trace_chunks.gd, test_rotorcraft_trace_chunks.gd, test_trace_chunk_store.gd, test_exit_transaction.gd and test_manual_trace_integrity.gd.

**Limits.** No long recording or stop latency was measured here. Retained spool ownership is intentional and is not by itself a leak.

**Prior tracking.** Already called out for investigation; distinguish manual CSV traces from .orfl logs.

**Pinned sources:** [app/main.gd:2292–2296](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/main.gd#L2292-L2296); [app/helicopter_main.gd:606–608](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/helicopter_main.gd#L606-L608); [app/sim/recorder.gd:54–66](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/recorder.gd#L54-L66); [app/sim/trace.gd:1820–1869](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/trace.gd#L1820-L1869); [app/sim/trace.gd:159–170](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/trace.gd#L159-L170); [app/sim/trace.gd:274–277](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/trace.gd#L274-L277); [app/sim/rotorcraft_recorder.gd:127–166](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/rotorcraft_recorder.gd#L127-L166); [app/sim/rotorcraft_recorder.gd:224–253](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/rotorcraft_recorder.gd#L224-L253); [docs/plans/apple-silicon-performance.md:349–355](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/apple-silicon-performance.md#L349-L355).

### F15

**Ground audio can recompute accepted contact laws and support queries**

P2 · Optimization candidate · CPU / contact observation · Owners: GP-19, GP-19f, AUD.

**Evidence.** FlightAudio observes accepted ground endpoints and can force observation every tick near a possible touchdown. GroundAudioModel can reevaluate the ground law, wheel frames, support and material data. A far-ground unloaded-row shortcut and once-per-frame cadence already reduce some cases.

**Impact.** Near-ground audio may duplicate computations already needed by the physical/contact owner. This cost lies beyond the native evaluator boundary and can affect busy contact scenes.

**Recommended action.** Consume a detached, validated accepted-contact receipt with enough material/normal/slip information. Preserve intervening touchdown events and invalidation under terrain/configuration changes; do not replace accepted events with render-frame polling.

**Verification.** Compare exact contact rows and cue order across touchdown/liftoff, surfaces, composed terrain, lake, pause/reset and multiple ticks per frame. Run test_ground_audio.gd, test_ground_audio_materials.gd, test_flight_audio_accepted.gd and test_presentation_cadence.gd, then paired complete-flight profiles.

**Limits.** Conditional source-visible work; the previous unloaded-row optimization is already implemented. No incremental saving is claimed.

**Prior tracking.** Accepted-contact reuse is already tracked. Older plan prose about frame-only touchdown polling is stale.

**Pinned sources:** [app/audio/flight_audio.gd:146–158](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L146-L158); [app/audio/flight_audio.gd:187–198](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L187-L198); [app/audio/ground_audio_model.gd:59–73](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/ground_audio_model.gd#L59-L73); [app/audio/ground_audio_model.gd:90–104](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/ground_audio_model.gd#L90-L104); [docs/plans/advanced-ground-flight-physics.md:613–621](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/advanced-ground-flight-physics.md#L613-L621); [docs/plans/advanced-ground-flight-physics.md:921](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/advanced-ground-flight-physics.md#L921).

### F16

**Flight audio independently requests wind, air data and propulsion observations**

P3 · Optimization candidate · CPU / presentation sampling · Owners: AUD, SF, DT-MAC-04b.

**Evidence.** Every render frame the adapter calls wind_at() and air_data(); the base uniform-weather air_data() also samples wind, while spatial air has a different provider path. Non-turbine propellers above the RPM threshold also derive torque for sound.

**Impact.** Repeated derived-state queries can consume CPU after the solver is optimized, especially with spatial weather or multiple vehicles.

**Recommended action.** Reuse one correctly timed air/wind observation only where dispatch, provider and accepted-state identity match. Keep derived-session overrides, spatial semantics and torque-dependent sound. If native work is justified, batch a pure observation rather than many tiny crossings.

**Verification.** Compare detached snapshots and provider call order for base/custom sessions, uniform/spatial weather, pause and rewind. Start with test_flight_audio_accepted.gd and test_soundscape.gd; profile complete audio-on/off routes.

**Limits.** A direct duplicate wind lookup is established for the uniform base path. Spatial calls are not necessarily interchangeable, and savings were not measured.

**Prior tracking.** The compatibility-sensitive wind/air reuse candidate already appears in the November 14 handoff.

**Pinned sources:** [app/audio/flight_audio.gd:234–250](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L234-L250); [app/audio/flight_audio.gd:440–454](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/audio/flight_audio.gd#L440-L454); [app/sim/flight_session.gd:613–616](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L613-L616); [app/sim/flight_session.gd:677–686](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/flight_session.gd#L677-L686); [docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md:54](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md#L54).

### F17

**Statistics continues substantial accepted-tick derivation with its widget closed**

P3 · Optimization candidate · CPU / accepted-state observers · Owners: UI-FS-08-R1, UI-FS-08-R2.

**Evidence.** Eligible Home-started fixed-wing sessions attach the statistics service. Each accepted tick derives air data, terrain, attitude, contacts and detached classifier observations. Widget visibility does not disable accounting; Workshop and ineligible/suspended branches are excluded.

**Impact.** The service contributes to total callback cost even when its UI is hidden. Several derived quantities overlap other consumers.

**Recommended action.** Profile and share immutable values from the same accepted boundary. Preserve every required classifier sample, accounting and eligibility check; do not throttle statistics merely because the widget is closed.

**Verification.** Require identical samples/events for short contacts, composed terrain, start/reset/restore and session eligibility. Run the detector, lifecycle, eligibility and terrain statistics suites; measure the whole active observer after current shortcuts.

**Limits.** Intentional sample cadence. Earlier statistics improvements are already implemented, so historical observer-ablation savings are not an achievable forecast.

**Prior tracking.** Known remaining profiling area after existing shortcuts and a terrain correctness repair.

**Pinned sources:** [app/app_root.gd:3828–3846](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/app_root.gd#L3828-L3846); [app/statistics/service.gd:120–158](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/statistics/service.gd#L120-L158); [app/statistics/fixed_wing_adapter.gd:40–90](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/statistics/fixed_wing_adapter.gd#L40-L90); [app/statistics/fixed_wing_adapter.gd:140–154](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/statistics/fixed_wing_adapter.gd#L140-L154); [docs/plans/flight-statistics.md:322–324](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/flight-statistics.md#L322-L324); [docs/plans/optimization-priorities.md:59–65](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/optimization-priorities.md#L59-L65).

### F18

**Helicopter and airship presentation still mix interpolation needs with display-only work**

P3 · Optimization candidate · CPU / presentation cadence · Owners: HELI-09, HELI-16-R1, BL-17.

**Evidence.** Helicopter accepted ticks build electronics/envelope presentation samples; two adjacent samples support rotor interpolation. Its HUD also formats text every render frame while the layer is hidden. Airship presentation requests telemetry and rebuilds nine HUD lines each frame; the detailed force evaluation is already cached per newly consumed tick.

**Impact.** Display-only derivation/text churn may add work without improving visible cadence, particularly while hidden or paused.

**Recommended action.** Separate the minimum adjacent-tick interpolation state from display-only derivation. Update hidden/unchanged text only when needed or at an explicitly bounded display cadence. Preserve rotor interpolation and current control/envelope semantics.

**Verification.** Check adjacent-tick interpolation, hidden-to-visible, pause/resume, telemetry freshness and control changes with test_heli_render_audit.gd, test_airship_activity.gd and test_airship_presentation.gd; profile the actual vehicle routes.

**Limits.** Do not reduce helicopter physics/controller cadence or describe cached airship full-force evaluation as happening on every displayed frame. Gain unknown.

**Prior tracking.** Existing experimental-vehicle performance qualification remains open.

**Pinned sources:** [app/helicopter_main.gd:169–173](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/helicopter_main.gd#L169-L173); [app/helicopter_main.gd:310–372](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/helicopter_main.gd#L310-L372); [app/helicopter_main.gd:395–470](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/helicopter_main.gd#L395-L470); [app/helicopter_main.gd:512–513](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/helicopter_main.gd#L512-L513); [app/vehicles/airship/airship_scene.gd:641–658](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/vehicles/airship/airship_scene.gd#L641-L658); [app/vehicles/airship/airship_hud.gd:198–225](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/vehicles/airship/airship_hud.gd#L198-L225); [app/sim/airship/session.gd:444–453](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L444-L453); [docs/plans/helicopter.md:650](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/helicopter.md#L650); [docs/plans/rc-airship.md:310](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/rc-airship.md#L310).

### F19

**Bounded input tapes create deliberate memory and duration limits**

P3 · Policy tradeoff · RAM / long-session behavior · Owners: DR-16b, DR-17, BL-07, BL-08, BL-17.

**Evidence.** Airship retains up to 432,000 rows of four float64 inputs, about 13.2 MiB of raw values, then sets tape_overflow and continues. The quad retains nine or ten inputs per row, about 29.7 or 33.0 MiB, and deliberately pauses at 30 simulated minutes. These session tapes are separate from .orfl recording and its limits.

**Impact.** Long-session UX and RAM are constrained by an explicit history policy. Airship in-memory history can be a prefix even while the flight continues; quad duration is intentionally capped.

**Recommended action.** Expose the relevant limit/status if needed. Only if product requirements require longer exact history, evaluate segmented storage with bounded memory and explicit replay/completeness semantics. Do not silently replace exact history with a lossy ring.

**Verification.** Exercise just-before/at/after limits, reset, replay and simultaneous .orfl recording. Use test_mr_session.gd, test_mr_flight_log.gd, test_airship_session.gd and test_airship_flight_log.gd; measure allocator overhead and retained copies separately.

**Limits.** Byte counts are capacity arithmetic, not measured RSS. They exclude allocation overhead and copies. Old plan text saying these flight-log adapters do not exist is superseded by source and later evidence.

**Prior tracking.** Existing bounded design; quad pause is documented. This is not a demonstrated leak.

**Pinned sources:** [app/sim/airship/session.gd:21–22](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L21-L22); [app/sim/airship/session.gd:49–50](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L49-L50); [app/sim/airship/session.gd:266–275](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L266-L275); [app/sim/multirotor/session.gd:35–39](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/session.gd#L35-L39); [app/sim/multirotor/session.gd:448–450](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/session.gd#L448-L450); [app/sim/multirotor/session.gd:549–605](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/multirotor/session.gd#L549-L605); [app/sim/race/race_model.gd:29–34](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/race/race_model.gd#L29-L34); [docs/plans/drone-racing.md:651](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/drone-racing.md#L651).

### F20

**Glow event surfaces repeat full point evaluation outside the native stage**

P2 · Optimization candidate · CPU / native-boundary residue · Owners: NITRO, SF, NK-3.

**Evidence.** Glow pickup/event policy calls full point evaluation, including work beyond the scalar surface it needs. ResourceStep samples stages and also reevaluates an endpoint after its trial already collected endpoint surface values. The native stage replaces the stage evaluator, not the GDScript event policy, so that cost can remain under native physics.

**Impact.** Event-free and event-heavy ticks may repeat aerodynamic/propulsion/environment work despite a fast native RK stage. This is a better port/reuse target than assuming the whole physics stack remains interpreted.

**Recommended action.** First isolate pure surface prerequisites and reuse exact stage-local or endpoint receipts where state, time and context match. Consider a narrow native batch only after profiling. Fix F01/F02 independently before altering event execution. Never cache by time alone: RK midpoint states differ.

**Verification.** Profile complete glow ticks with pickup/feed events and without events, native/reference separately. Compare event records, exact states, context mutation/refusal, roots, pause/restore and transition-induced changes. Retain evaluation bounds and mirrored-source/native receipt checks.

**Limits.** Source-supported repeated work; no current cost or speedup measured. Main/line and pickup-lost/recovered modes are mutually exclusive in pairs, although three candidates can coexist in a mode. Do not assume every surface is active every tick.

**Prior tracking.** NITRO profiling is already planned; this audit identifies repeated event-policy evaluation as a concrete target.

**Pinned sources:** [app/physics/glow/flight.gd:295–307](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/glow/flight.gd#L295-L307); [app/physics/glow/flight.gd:338–407](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/glow/flight.gd#L338-L407); [app/physics/glow/flight.gd:417–545](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/glow/flight.gd#L417-L545); [app/physics/glow/flight.gd:733–750](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/glow/flight.gd#L733-L750); [app/physics/resource_event_step.gd:57–76](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L57-L76); [app/physics/resource_event_step.gd:182–211](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/resource_event_step.gd#L182-L211); [app/sim/native_stage.gd:356–395](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/native_stage.gd#L356-L395); [docs/plans/RC_NITRO_ENGINE_REALISM_PLAN.md:223](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/RC_NITRO_ENGINE_REALISM_PLAN.md#L223).

### F21

**Opt-in servo intervals repeatedly prepare trajectories and validate guarded context**

P2 · Optimization candidate · CPU / interval integration · Owners: AC-12, SF, NK.

**Evidence.** Servo interval sampling, stages and policy reconstruct/validate trajectory information, while kernel interval callbacks copy and compare protected context. Short arrival pieces can multiply this overhead beyond the ordinary four-stage picture.

**Impact.** A correct local-clock/arrival solver can spend substantial work on repeated preparation and guard transport. Broadly removing those guards would weaken the transaction contract.

**Recommended action.** Prepare one immutable tick trajectory/context with owner-controlled invalidation, retain local piece clocks and arrival cuts, and reduce redundant internal preparation only after proving equality. Keep adversarial mutation protection and do not reuse a result solely because its timestamp matches.

**Verification.** Compare exact endpoint/event trajectories for normal and tiny arrival intervals, long absolute clocks, reset/restore and malformed/mutating callbacks. Measure full ticks and worst-case pieces; use the existing servo interval suites and owning AC-12 campaign.

**Limits.** Opt-in/reference-domain path, not a claim that all stock flights incur this overhead or that the native backend can be enabled without qualification.

**Prior tracking.** Concrete opt-in candidate; current adapter domain explicitly uses the reference evaluator.

**Pinned sources:** [app/sim/servo_interval_flight.gd:43–50](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/servo_interval_flight.gd#L43-L50); [app/sim/servo_interval_flight.gd:83–90](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/servo_interval_flight.gd#L83-L90); [app/sim/servo_interval_flight.gd:109–169](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/servo_interval_flight.gd#L109-L169); [app/sim/simulation.gd:441–457](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L441-L457); [app/sim/simulation.gd:1159–1175](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L1159-L1175); [app/sim/simulation.gd:1211–1217](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L1211-L1217); [docs/research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md:1–30](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md#L1-L30).

### F22

**Reference liquid-fuel stages repeat configuration validation and result construction**

P2 · Optimization candidate · CPU / reference evaluator · Owners: FUEL-12, NK-3.

**Evidence.** LiquidFuelFlight invokes liquid-fuel evaluation from stage paths. The reference helper validates inventory/configuration maps and constructs reporting dictionaries repeatedly, despite much of that configuration being immutable during a prepared flight.

**Impact.** Reference fallback and research routes can pay preparation-like costs at stage cadence. Native implementations already exist, so this is not an unported whole subsystem.

**Recommended action.** Prepare immutable validated configuration once, while retaining amount/state-dependent checks, finite validation and bypassed-mutation detection at the correct boundary. Keep reporting optional only where the consumer contract permits.

**Verification.** Compare exact reference outputs for normal/empty/refill/invalid inventory, configuration replacement and event boundaries; run the owning fuel hardening and native oracle/lifecycle gates. Measure current complete reference ticks rather than historical helper-only numbers.

**Limits.** Applies primarily to reference/fallback work. Current native ownership and refusal reasons must be recorded before attributing costs.

**Prior tracking.** Already tracked in FUEL-12 hardening; old contaminated timings are not reused as current evidence.

**Pinned sources:** [app/sim/liquid_fuel_flight.gd:39–69](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/liquid_fuel_flight.gd#L39-L69); [app/physics/liquid_fuel.gd:16–128](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/liquid_fuel.gd#L16-L128); [docs/research/fuel-systems/FUEL-12/HARDENING-R2.md:27–39](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/fuel-systems/FUEL-12/HARDENING-R2.md#L27-L39).

### F23

**Multirotor contact substeps and framed transaction checks need whole-tick attribution**

P2 · Optimization candidate · CPU / multirotor · Owners: DR-16, DR-17, SF.

**Evidence.** The controlled plant selects two or four contact pieces in relevant cases, and framed callbacks preserve detached sampled/continuous/mode context. Protected-array comparisons remain around the model boundary. Current code already has guard reuse, scalar contact work, a two-piece path and terrain memoization.

**Impact.** Full contact/controller ticks may cost more than an isolated stage evaluation; profile both boundaries. Repeating old optimization claims or dropping substeps would misrepresent remaining work.

**Recommended action.** Profile the current complete framed tick and isolate remaining contact/guard allocations. Improve validated internal data flow only while preserving once-per-tick controller sampling, contact integration and mutation rejection. Consider native batching only for a measured pure kernel.

**Verification.** Cover airborne, pad, impact, race wrapping and controller-memory replay; include adversarial callback mutation, refusal and exact native/reference candidates. Follow current drone campaign gates rather than treating historical medians as current qualification.

**Limits.** No multirotor timing was measured in this audit. Guards and contact pieces are correctness features, not unconditional waste.

**Prior tracking.** Existing M1–M3 performance work; several guard/contact optimizations are already implemented.

**Pinned sources:** [app/physics/multirotor/controlled_plant.gd:288–307](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L288-L307); [app/physics/multirotor/controlled_plant.gd:690–712](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/multirotor/controlled_plant.gd#L690-L712); [app/sim/simulation.gd:453–467](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L453-L467); [app/sim/simulation.gd:580–585](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L580-L585); [app/sim/simulation.gd:642–647](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L642-L647); [app/sim/simulation.gd:1364–1400](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L1364-L1400); [docs/research/drone-racing/M1-M3-2026-11-11/README.md:1–25](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/drone-racing/M1-M3-2026-11-11/README.md#L1-L25).

### F24

**Airship terminal-contact observation can evaluate more ground forces than its consumer needs**

P2 · Optimization candidate · CPU / airship contact · Owners: BL-12, BL-17.

**Evidence.** After an accepted tick, the airship session observes contacts. Its dynamics contact observer can evaluate full gear/hull normal and friction work although the session consumes terminal hull/propeller contact outcomes. This is separate from reference stage force evaluation.

**Impact.** Accepted-endpoint safety observation can duplicate force-related work. A faster stage evaluator alone would leave the observation cost.

**Recommended action.** Provide a narrowly scoped terminal-contact query or reuse a suitable accepted-endpoint receipt, keeping the existing field-terrain and terminal-event semantics. Do not use the last RK stage as the accepted endpoint.

**Verification.** Compare terminal outcomes, contact locations and accepted states across airborne, gear/hull/prop strikes, field terrain and reset/restore. Run airship activity/session/contact suites and measure complete BL-17 workloads.

**Limits.** Static candidate with existing prefilters; no current airship benchmark or physical validation was performed. Lake/water entry is not an admitted airship contract and remains open.

**Prior tracking.** Existing BL performance gate; the BL-12 prefilter is already present.

**Pinned sources:** [app/sim/airship/session.gd:135–148](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L135-L148); [app/sim/airship/session.gd:281–285](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/airship/session.gd#L281-L285); [app/physics/airship/airship_dynamics.gd:403–420](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/airship/airship_dynamics.gd#L403-L420); [app/physics/airship/airship_dynamics.gd:464–510](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/airship/airship_dynamics.gd#L464-L510); [docs/plans/rc-airship.md:310](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/rc-airship.md#L310).

### F25

**Coupled flap loops recompute station-only clean terms inside the pair loop**

P2 · Optimization candidate · CPU / mathematical reuse · Owners: NK-2a, NK-3, SF.

**Evidence.** In Aero._local_loads(), the coupled station inner loop recomputes clean_angle_k, clean_weight_k and clean_source_k for the same source station. These terms are invariant for that invocation even though the receiving/source coupling remains pair-dependent.

**Impact.** Hoisting the station-only work can remove repeated arithmetic from an O(n^2) loop. It does not make the coupling computation itself O(n).

**Recommended action.** Precompute only the invariant terms once per invocation, preserving expression grouping, branch behavior and sum order. Measure scratch allocation overhead. Coordinate native mirrors and exact source receipts; never cache state-dependent aerodynamic results across RK stages.

**Verification.** Compare float64 bytes for zero/reverse flow, flap transitions, stall, coupled/uncoupled stations and native/reference paths; profile powered/flap complete sessions where this loop is material.

**Limits.** Already-known opportunity, not a new discovery or measured gain. Reassociation, fast-math or a different closed-form model would be a separate numerical change.

**Prior tracking.** Explicitly retained as an unmeasured candidate in optimization-priorities.md.

**Pinned sources:** [app/physics/aero.gd:408–420](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/aero.gd#L408-L420); [app/physics/aero.gd:543–574](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/physics/aero.gd#L543-L574); [docs/plans/optimization-priorities.md:67–73](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/optimization-priorities.md#L67-L73).

### F26

**The existing temporal-wind candidate is blocked by native source identity, not missing implementation**

P3 · Optimization candidate · CPU / native qualification · Owners: NK-3, M5-W.

**Evidence.** The November 9 report retains a patch that reuses temporal remainders inside one immutable stage query while preserving point-dependent phase/trigonometry/order. Four changed reference files belong to NK-3 mirrored-source identity. Applying the patch alone invalidates existing native admission across the fleet, including calm weather.

**Impact.** A local reference-path speed improvement can make normal sessions slower if it forces native fallback, or fail package admission. Optimization must include deployment identity and actual selected backend.

**Recommended action.** Re-evaluate the candidate on a pinned isolated source/binary pair and qualify matching native mirrors/receipts before promotion. Preserve fallback and exact replay. Treat the reported preliminary one-pair result as historical screening, not accepted savings.

**Verification.** Run the existing wind oracle/negative/lifecycle coverage, paired complete-session native/reference workloads and fleet/package gates. Verify actual backend/refusal reasons after the change, including calm flights.

**Limits.** No patch was applied and no historic timing was rerun. This is a qualification/reuse opportunity, not an instruction to bypass receipt checks.

**Prior tracking.** Known apply-ready research candidate retained outside production; not an active optimization.

**Pinned sources:** [docs/research/performance-report-2026-11-09.md:63–94](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/performance-report-2026-11-09.md#L63-L94); [research/native-kernel/README.md:455–482](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/research/native-kernel/README.md#L455-L482); [docs/STACK.md:54](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/STACK.md#L54).

### F27

**Kernel timing and diagnostic instrumentation do not represent complete frame cost**

P2 · Measurement gap · CPU/GPU / measurement validity · Owners: PT, SF, DT-MAC-04b, VQ.

**Evidence.** Simulation.step_usec is an exponentially smoothed value updated before stepped.emit(), so it excludes accepted-tick observers and is not a raw tail distribution. Frame diagnostics/debug render probes poll renderer timings; frame streaming synchronously serializes and flushes lines. The calibrator already throttles timing reads under the separate-render-thread model, acknowledging synchronization cost.

**Impact.** A faster kernel can coexist with slow full callbacks, recording hitches or GPU-bound frames. Instrumentation can perturb the workload being compared, especially on a slow user-data filesystem.

**Recommended action.** Measure raw full callback/tick boundaries and named observer phases alongside kernel time, with a bounded sampled/aggregate path. Compare diagnostics off/on and stream off/on, retain write-time metadata and record all timing scopes. Preserve unavailable/stale status rather than mapping missing GPU evidence to zero cost.

**Verification.** Use matched uninstrumented controls and existing performance/debug tools. Report p50/p95/p99/max, hitch counts and simulation/wall ratio separately; test same-thread and separate-render-thread modes and normal/slow storage. Do not infer scanout or input-to-photon latency from process timing.

**Limits.** No observer overhead was measured here. The current diagnostic schema already marks GPU coverage/freshness limits; this is not a newly discovered false-zero implementation bug.

**Prior tracking.** Boundary limitation already recognized in optimization priorities; current diagnostics also retain useful unknown/freshness metadata.

**Pinned sources:** [app/sim/simulation.gd:697–705](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/sim/simulation.gd#L697-L705); [app/render/frame_diagnostics.gd:7–22](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/frame_diagnostics.gd#L7-L22); [app/render/frame_diagnostics.gd:117–145](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/frame_diagnostics.gd#L117-L145); [app/debug/render_probe.gd:75–82](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/debug/render_probe.gd#L75-L82); [app/render/frame_samples.gd:307–323](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/frame_samples.gd#L307-L323); [app/render/auto_calibration.gd:127–139](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/auto_calibration.gd#L127-L139); [docs/plans/optimization-priorities.md:59–65](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/optimization-priorities.md#L59-L65).

### F28

**Cloud-cache slot updates can evict keys needed later in the same transition**

P2 · Optimization candidate · GPU/CPU / cache lifecycle · Owners: DT-MAC, FW.

**Evidence.** Cloud-shadow cache ownership is changed slot by slot while eviction considers current references. A full set [A,B,C,D] changing to [E,A,B,C] can make A transiently unreferenced and eligible for eviction before a later slot binds it, causing an avoidable eviction/rebake cascade.

**Impact.** Preset transitions can perform repeated GPU baking/readback and create transient CPU/GPU/memory spikes. The analytic fallback preserves an output path but does not remove the redundant work.

**Recommended action.** Reconcile the complete desired key/owner set before admitting or evicting entries. Account for ground, sky and prewarm ownership together, preserving cancellation/generation tokens, bounded capacity and fallback.

**Verification.** Add deterministic full-capacity reorder/overlap transitions, rapid preset changes, cancellation and owner release/reentry. Count admissions/evictions/bakes and compare output/fallback parity, then profile cold/warm transitions on each backend.

**Limits.** Source-derived transient ownership scenario; no live cloud transition or measured hitch was captured in this audit.

**Prior tracking.** Already tracked in the consolidated Mac/external audit queue; remains source-visible.

**Pinned sources:** [app/render/cloud_shadow_map.gd:91–118](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/cloud_shadow_map.gd#L91-L118); [app/render/cloud_shadow_map.gd:315–345](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/cloud_shadow_map.gd#L315-L345); [docs/plans/apple-silicon-performance.md:878–887](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/apple-silicon-performance.md#L878-L887).

### F29

**Cloud baking reads an HDR render target back to CPU and uploads a converted texture**

P2 · Optimization candidate · GPU/CPU / synchronization and memory · Owners: DT-MAC, FW.

**Evidence.** The non-headless cache path bakes 2048x2048 HDR SubViewports, calls get_image(), validates/converts to RGH and creates an ImageTexture. Four final two-channel half-float tiles contain 64 MiB of base-level texels in total; render targets, temporary Images, staging/copies and driver allocations are additional and backend-dependent.

**Impact.** Readback, validation/conversion and re-upload can synchronize CPU/GPU and amplify cold/preset-transition cost. Peak memory can exceed the final cache payload.

**Recommended action.** First measure bake/readback/convert/upload and cache churn separately. Compare offline/precomputed data or a GPU-resident publication path where compatible with the validated deterministic fallback. Retain content validation, lifecycle cancellation and bounded residency.

**Verification.** Measure cold load, warm reuse, rapid preset transitions and F28 stress on Compatibility, Forward+ and native Metal. Capture peak RAM/VRAM when available, bake counts and frame gaps; test bad tiles, reset/reentry and device/provider failure.

**Limits.** 64 MiB is logical texel arithmetic, not a measured VRAM footprint. No GPU execution occurred in this audit, and moving GPU calls to a worker is not automatically safe or faster.

**Prior tracking.** Known cloud-cache qualification target; not a new claim that the analytic fallback is missing.

**Pinned sources:** [app/render/cloud_shadow_map.gd:33–45](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/cloud_shadow_map.gd#L33-L45); [app/render/cloud_shadow_map.gd:402–435](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/cloud_shadow_map.gd#L402-L435); [app/render/cloud_shadow_map.gd:488–501](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/cloud_shadow_map.gd#L488-L501).

### F30

**Procedural grass collapses distant vertices after instance submission**

P2 · Optimization candidate · GPU / visibility and geometry · Owners: VQ, LU, DT-MAC.

**Evidence.** The procedural NearGrass path builds up to 6,000 clumps across four MultiMeshes. Its vertex shader collapses distant geometry, but when a whole MultiMesh batch remains visible, its instances are submitted and the distant ones reach the vertex shader. Godot MultiMesh visibility is coarse for the whole batch.

**Impact.** Distance collapse can save later raster work while leaving vertex/submission cost. Large batches also weaken spatial culling.

**Recommended action.** Compare conservative spatial chunks/visible instance ranges against extra draw calls, preserving all active views and the wind/time contract. Bulk instance-buffer preparation may help startup only if profiling shows setter overhead. Keep the imported vegetation route separate.

**Verification.** Measure vertex/draw cost and frame time with pilot, chase, magnifier and reflection views; test field boundaries and fast camera motion. Compare visual density/transition stability at 1080p and the Mac native-panel target.

**Limits.** No rendered benchmark. Chunks can worsen draw overhead; vertex collapse is not itself proof of the dominant bottleneck. The stock imported meadow can use a different path.

**Prior tracking.** Already identified in the external handoff; applies to the procedural fallback, not every default meadow path.

**Pinned sources:** [app/render/field.gd:321–335](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/field.gd#L321-L335); [app/render/near_grass.gd:10–17](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/near_grass.gd#L10-L17); [app/render/near_grass.gd:229–274](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/near_grass.gd#L229-L274); [app/render/near_grass.gdshader:39–51](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/near_grass.gdshader#L39-L51); [docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md:1–100](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md#L1-L100).

### F31

**Zero-opacity cloud layers still compute density before alpha evaluation**

P2 · Optimization candidate · GPU / shader work · Owners: FW, DT-MAC.

**Evidence.** Sky cloud evaluation computes density before alpha for a layer, with additional relief work later. An exactly zero-opacity layer can therefore pay work that may be removable under the intended compositing recurrence.

**Impact.** Preset transitions and disabled layers may retain unnecessary shader computation across many sky pixels or radiance updates.

**Recommended action.** Evaluate an exact-zero fast path before expensive density/relief work, preserving ordered compositing, zero-alpha state updates and floating-point behavior. Do not use a broad epsilon cutoff that changes fades.

**Verification.** Compare zero, tiny-positive and transitioning opacity for every layer; include sky/radiance, day/night and each renderer. Inspect shader instructions and rendered frame cost on native hardware, plus visual equivalence at the accepted threshold.

**Limits.** A static candidate, not a measured shader improvement. GPU branch/compile behavior can erase or reverse an expected saving.

**Prior tracking.** Already identified in the external cloud/shader handoff.

**Pinned sources:** [app/render/sky.gdshader:215–244](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/sky.gdshader#L215-L244); [app/render/sky.gdshader:266–275](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/sky.gdshader#L266-L275); [docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md:1–100](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md#L1-L100).

### F32

**Water refraction inherits opaque-screen-copy limitations and bandwidth cost**

P2 · Renderer constraint · GPU / transparency and bandwidth · Owners: VQ-07, LU, DT-MAC.

**Evidence.** The water shader reads screen/depth textures and writes alpha. Godot documents that the 3D screen copy is captured after opaque geometry and before transparent geometry. Transparent smoke/canopies/other screen-reading surfaces therefore cannot be assumed to appear in that source, and the copy plus full-area water shading carries bandwidth cost.

**Impact.** Water/transparent intersections need explicit visual acceptance, and the screen-copy design may be expensive on bandwidth-limited GPUs or high-resolution outputs.

**Recommended action.** Test the actual content combinations and compare a scalable cheaper water/refraction option when profiling justifies it. Preserve shoreline/depth conventions per renderer. Extra viewports are a separate cost/coverage decision, not a free correctness fix.

**Verification.** Capture smoke/canopy/water overlap, shoreline and near/far camera cases under Compatibility and supported native Metal/Forward+ routes. Compare bandwidth-sensitive settings, total frame cost and presentation quality; retain opaque/transparent limitations in the graphics contract.

**Limits.** No screenshot or GPU capture was made. This is a documented rendering limitation and optimization target, not a claim of an observed artifact in the current scene.

**Prior tracking.** Known advanced-graphics qualification area; distinguish an engine constraint from a reproduced visual bug.

**Pinned sources:** [app/render/lake/water.gdshader:10–35](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/water.gdshader#L10-L35); [app/render/lake/water.gdshader:137–147](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/water.gdshader#L137-L147); [app/render/lake/water.gdshader:169–201](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lake/water.gdshader#L169-L201); [docs/plans/advanced-graphics.md:207](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/advanced-graphics.md#L207).

### F33

**Vegetation resources remain strongly cached for process lifetime**

P3 · Optimization candidate · RAM/VRAM / resource lifecycle · Owners: LU, SC, DT-MAC.

**Evidence.** Imported vegetation keeps static caches of parts, materials and shadow resources. These survive scene teardown and can accumulate catalog/quality variants during a session. The catalog and available variants bound the set; no unbounded leak was established.

**Impact.** Repeated scene/quality visits may retain more meshes/textures than the current flight needs. Source image file sizes do not reveal imported runtime allocation.

**Recommended action.** Inventory imported formats, unique resource identities and owners after controlled scene cycles. If retained unused variants exceed a justified budget, evaluate reference-aware eviction or explicit retirement without causing reload hitches or dangling resource use.

**Verification.** Run repeated Home/flight/quality/reentry loops and a soak, observing steady-state RSS/resource counts and backend memory where supported. Verify active materials/shadows survive eviction and measure cold/warm reacquisition.

**Limits.** Source-supported retention, not proof of a leak or excessive VRAM. Exact resident/driver memory cannot be inferred from PNG/JPEG sizes.

**Prior tracking.** Already recorded as a retention/inventory task in the Apple plan.

**Pinned sources:** [app/scenery/imported_vegetation.gd:78–85](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L78-L85); [app/scenery/imported_vegetation.gd:115–123](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L115-L123); [app/scenery/imported_vegetation.gd:622–632](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L622-L632); [app/scenery/imported_vegetation.gd:769–773](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L769-L773); [app/scenery/imported_vegetation.gd:824–877](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L824-L877); [app/scenery/imported_vegetation.gd:914–951](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/scenery/imported_vegetation.gd#L914-L951); [docs/plans/apple-silicon-performance.md:908–910](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/apple-silicon-performance.md#L908-L910).

### F34

**Visible lens film resubmits unchanged material parameters each frame**

P3 · Optimization candidate · CPU / render-state submission · Owners: VQ, DT-MAC.

**Evidence.** LensStack sets configuration constants/colors and dynamic film parameters in the visible-frame path. Hidden film already returns early. Much of the static configuration changes only on a material/configuration generation boundary.

**Impact.** Unchanged script-to-renderer setter calls may contribute avoidable CPU work; the number of calls alone does not establish GPU uploads or stalls.

**Recommended action.** Separate configuration/material-generation writes from truly dynamic parameters, preserving wetness, camera/light, pause and resource-replacement updates. Avoid a broad cache with stale material ownership.

**Verification.** Count setters and measure full lens-enabled frames before/after; test visibility, material rebuild, weather transitions, pause/reset and camera/light changes. Use existing lens correctness and visual gates.

**Limits.** Optional candidate with unknown ROI. Hidden-film work is already avoided, and the rendering server may coalesce unchanged values.

**Prior tracking.** Existing low-priority delivery handoff candidate.

**Pinned sources:** [app/render/lens/lens_stack.gd:536–561](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lens/lens_stack.gd#L536-L561); [app/render/lens/lens_stack.gd:863–886](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/lens/lens_stack.gd#L863-L886); [docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md:1–100](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/research/desktop-delivery-investigations/external-handoffs-2026-11-14.md#L1-L100).

### F35

**Field projected-shadow geometry is prepared before policy may hide it**

P3 · Optimization candidate · CPU/RAM / scene construction · Owners: VQ-04b, SA-11, SA-12, DT-MAC.

**Evidence.** Field construction attaches projected shadows before applying policy. The helper gathers/merges up to 16 casters even when projected shadows will be disabled or replaced by native shadows. Hidden projected targets are already reduced to 2x2, so the retained cost is not a full-size render-target leak.

**Impact.** Cold load and retained geometry may include work for a currently inactive feature, balanced against immediate toggling and fallback readiness.

**Recommended action.** Measure construction/retention first. Defer or cache eligible immutable field caster preparation only if live-toggle and fallback behavior remain correct. Do not blindly apply this to aircraft bind geometry, whose pose capture can require early preparation.

**Verification.** Compare cold/warm loading and memory with shadows off/native/projected; exercise live toggles, fallback, reentry and immutable bind poses. Keep shader/time/physics separation and visual acceptance.

**Limits.** Source-visible design tradeoff, not an unconditional bug. Target resizing already addresses the obvious hidden-buffer concern.

**Prior tracking.** Intentional live-toggle preparation tradeoff already described in the shadow plan; low-priority measurement candidate.

**Pinned sources:** [app/render/field.gd:352–355](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/field.gd#L352-L355); [app/render/field_projected_shadows.gd:22–39](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/field_projected_shadows.gd#L22-L39); [app/render/field_projected_shadows.gd:51–72](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/field_projected_shadows.gd#L51-L72); [app/render/field_projected_shadows.gd:94–116](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/field_projected_shadows.gd#L94-L116); [app/render/shadow_field_policy.gd:52–72](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/shadow_field_policy.gd#L52-L72); [app/render/shadow_field_policy.gd:396–405](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/shadow_field_policy.gd#L396-L405); [app/render/projected_shadow.gd:426–438](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/projected_shadow.gd#L426-L438); [app/render/projected_shadow.gd:510–530](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/app/render/projected_shadow.gd#L510-L530); [docs/plans/shadows.md:22–26](https://github.com/bultodepapas/OpenRCsimulator/blob/894357de83762ff6e0fdc47b0024e60f3d8286b7/docs/plans/shadows.md#L22-L26).

## Mathematical optimization and native-code decisions

### Work and frame budgets

The application uses float64 simulation state and 240 Hz RK4. The nominal interval is:

$$
\Delta t = 1/240 = 4.1667\ \text{ms}.
$$

The repository's 500 µs physics gate is a target, not an observed maximum. At exactly 500 µs per tick, 240 ticks consume 120 ms of CPU time each second, about 12% of one continuously available core. A 60 fps frame normally contains four ticks (2 ms of that kernel work); a 30 fps frame contains eight (4 ms); the configured 12-tick catch-up ceiling permits 6 ms. Observers, rendering, I/O, scheduling and waiting remain additional work. Below approximately 20 rendered fps, twelve ticks per frame cannot maintain 240 simulated ticks per wall second. Raising catch-up limits or lowering physics frequency is not a free optimization. These are arithmetic consequences of the configured rate/cap, not measured timings. See [kernel/engine limits](../../../docs/STACK.md#limits-and-upgrades).

An ordinary four-stage RK4 tick entails 960 stage evaluations per second per vehicle. Located events, contact substeps and endpoint observers add evaluations. K2 and K3 share a time but use different states; a cache keyed only by timestamp is incorrect. Likewise, the last RK stage is not generally the final weighted RK4 state. Reuse must identify state, time, immutable configuration, provider/context generation and accepted versus trial ownership.

For the coupled flap candidate F25, hoisting station-only expressions reduces those expressions from repeated pair-loop work to one calculation per station. The coupling matrix and ordered reduction remain O(n²). Scratch construction can outweigh arithmetic removal for small station counts; measure the complete invocation and flight.

For native translation, Amdahl's law makes the limit explicit:

$$
S_{\rm total}=\frac{1}{(1-f)+f/s}.
$$

If a candidate accounts for 30% of the measured CPU work and its own cost becomes four times faster, total CPU speedup is about 1.29×. This is an illustration, not an OpenRC estimate. A GPU-bound frame may show no FPS gain from that CPU improvement. Remove repeated work before adding an interpreter/native boundary to each tiny operation.

### What is already native

The [current native guide](../../../research/native-kernel/README.md#what-is-ported) lists prepared float64 math, air/terrain/wheels/hull, aerodynamic and propulsion stages, electric/liquid/glow families, weather/spatial/wake and helicopter evaluation. Linux ABI 2 admission, Windows NK-4 packaging/identity, and the screened Mac source/package routes have different contracts and evidence. Current source and receipts supersede older documents that call native execution Linux-only or Mac reference-only. This audit did not build or requalify any of them.

A native evaluator replaces a declared model boundary. It does not automatically eliminate accepted observers, event policy, validation, GDScript orchestration or rendering work. Verify the **actual** backend and refusal reason, not merely the requested flag. Preserve the reference fallback, exact source/binary/toolchain receipts and replay identity.

| Candidate | Preferred first experiment | Native suitability and acceptance |
| --- | --- | --- |
| F11/F15/F16/F17: accepted contact/air observations | Derive once at the exact accepted boundary and share a detached result | A pure batch may be suitable after duplication is removed; preserve derived-session dispatch, terrain/provider identity and all intervening events. |
| F20: glow surface prerequisites | Narrow the scalar query and reuse exact stage/endpoint work | A measured pure surface batch can extend the current evaluator; fix chronology first and retain event/rollback semantics. |
| F21/F22/F25: immutable preparation and loop invariants | Prepare once at the valid ownership boundary; hoist only proven invariants | Mirror exact arithmetic in existing native code and renew receipts. Do not trade validation or numerical law for speed. |
| F13/F14: recording/export | Separate serialization, write latency and main-thread ownership | A bounded worker is often more relevant than rewriting formatting in C++; backpressure, durability and ordered completion dominate correctness. |
| Audio synthesis or mesh/instance preparation, if profiling still identifies them | Reuse existing optimized paths, then batch contiguous numeric/buffer work | Consider native block generation or bulk buffers only when call/allocation overhead is material; preserve audio phase and main-thread scene publication. |
| Full kernel rewrite, GPU flight solver, global fast-math, blanket threading | No evidence-supported first implementation | These expand parity, determinism and platform risk; require a measured bottleneck and the existing owner gate. |

Preserve float64, expression grouping, reduction order, signed-zero behavior and rejection semantics where the contract requires exact bytes. SIMD, FMA contraction, reassociation or closed-form approximations can change results; treat them as explicit numerical changes unless exact equivalence is proven. Moving scene-tree/resource/GPU operations to arbitrary workers is not automatically thread-safe; consult the official thread API reference and the pinned engine behavior.

### Pixel and memory arithmetic

| Output or scale | Logical pixel count / fraction | Interpretation |
| --- | --- | --- |
| 1920×1080 | 2,073,600 | Primary non-Retina qualification target. |
| 2560×1440 | 3,686,400; 1.778× 1080p | More pixel work, not a guaranteed proportional frame cost. |
| 3840×2160 | 8,294,400; 4× 1080p | Pixel-bound work can grow substantially. |
| 2560×1600 panel | 4,096,000; 1.975× 1080p | Example native Retina panel target, distinct from backing-store dimensions. |
| 2/3 scale on both axes | About 44.4% of base pixels | Actual truncation gives 1706×1066 in the retained panel calculation. This is not a 55.6% FPS gain. |
| 0.85 scale on both axes | 72.25% of base pixels | Upscaler cost, fixed passes, geometry and CPU work remain. |

For an uncompressed base texture, bytes = width × height × layers × bytes per texel; mip levels and intermediate targets are additional. Four 2048² RGH tiles at four bytes per texel contain **67,108,864 bytes = 64 MiB** before those additions. GPU compression, format selection, driver residency, alignment and shared-memory behavior require runtime evidence. Source asset size is not VRAM size.

Follow the repository's resolution order: 1080p first, then higher resolutions, then 720p. The explicit exception is Apple Silicon on Retina: qualify the native panel and separately record output, drawable and internal 3D dimensions. A 1080p M1 result does not qualify its native panel. F04–F08 show why those boundaries must be made consistent before trusting automatic policy.

## Leads excluded or already repaired

| Lead | Disposition at the audited commit |
| --- | --- |
| “Physics still needs a first C++ port” | Rejected. Extensive native stage evaluation and platform-specific admission already exist. Remaining work must be attributed. |
| Circuit patch cache is unbounded | Rejected for this snapshot: `ground_features.gd` has entry and 4 MiB bounds. |
| Parked aircraft decode the same packed ORM channels repeatedly | The shared-channel means path is already present. GitHub PR #11 still being open did not override current source. |
| PackedFloat64Array append through a dictionary copies the whole array each time | Not supported by the pinned-engine alias probe. Do not label it O(n²) without a different proven operation. |
| Wet-lens drop cache ignores relevant configuration | Current keys include rain/gravity and mesh/count generation; the inspected stale lead is already repaired. |
| Lower scenery detail removes required collision physics | Current scenery retention handles collider ownership independently; the old warning is not an established current bug. |
| Ground audio only observes at render cadence | Stale description: accepted-tick/near-touchdown observation exists. F15 preserves it. |
| Airship/drone flight logging is not implemented | Stale plan prose; both `.orfl` adapters exist. |
| All retained input tapes/caches are leaks | Not established. F19 and F33 identify explicit limits/retention and the measurements needed. |
| Kernel guards should simply be removed | Rejected as a default optimization: they protect detached transaction/model boundaries. Internal reuse needs equivalent rejection coverage. |
| Zero/unknown GPU timing proves a zero-cost frame | Rejected. Existing diagnostic metadata already distinguishes unavailable/freshness/coverage limits. |
| Incomplete no-retry and p95 selection are accidental regressions | Reclassified as intentional policy tradeoffs (F09/F10), including the existing 5% tail regression test. |
| Historical headless, 720p or one-pair gains qualify the present game | Rejected. Source, backend, build, workload, target pixels and hardware must match. |

Pinned evidence for this triage is included in [source_identity.json](source_identity.json): `ground_features.gd`, `parked_aircraft.gd`, `drop_pool.gd`, `scenery.gd`, current native guide and the cited findings. Existing downwash/battery-query, controller/voice, contact and loading optimizations should be treated as baseline behavior, not counted again as new wins. Old documented gains are neither additive nor transferable.

## Recommended execution sequence

1. **Repair and prove chronology.** Implement F01 and F02 as small changes under SF/NITRO/SC, retaining the new counterexamples and exact event/rollback tests. Establish real glow/scenery reachability separately from the generic proofs.
2. **Make calibration identity consistent.** Implement F04 and F05 together with a versioned record boundary; then address F06/F07/F08 and decide explicitly whether F09/F10 policy should change. Preserve user overrides and provider/failure fallback.
3. **Close the restore transaction gap.** Add the active-recording malformed-body fixture for F03 and ensure publication occurs only under the chosen accepted-reset contract.
4. **Measure one complete CPU workload.** Use F27 to attribute kernel, events, accepted observers and I/O. Choose one of incident/contact reuse, mute behavior, glow queries or recording stalls from the result. Keep these as separately measurable slices.
5. **Measure one GPU transition/workload.** Start with cloud cache reconciliation/readback and optional shader work. Compare actual default and maximum settings, including disabled-feature cost. Keep the procedural fallback separate from imported scenery.
6. **Qualify native/platform delivery after source changes.** Refresh matching receipts and exact oracles where mirrors change; verify selected backends and release paths. Run sustained hardware acceptance only on the stabilized candidate.

A source-supported correctness repair does not need a promised FPS gain to be worthwhile. A performance patch should exceed measurement variation and improve the affected complete workload or remove a named reproducible hitch/memory defect. Do not merge unrelated numerical, native, settings and shader changes into one experiment.

## Verification matrix for implementation work

Reuse the [performance tooling](../../../research/performance/README.md), [debug bridge](../../../tools/debug/README.md), [checked Godot runner](../../../tools/godot/README.md), [test queue](../../../tools/testqueue/README.md) and [native verification workflow](../../../research/native-kernel/README.md#verification-and-local-installation). This audit adds only a small isolated reproduction fixture, not another profiler framework.

| Dimension | Required record or comparison |
| --- | --- |
| Identity | Commit/dirty-source hashes, exact engine/build type, actual physics/render backend and refusal reason, native library/receipt, aircraft/configuration/data and scenario/input identity. |
| Output | Window/output, drawable and internal 3D pixels, UI scale, reconstruction/provider/fallback, MSAA, detail/effects, active secondary views and display/refresh/VSync/cap. |
| CPU | Raw full callback and kernel timings separately; observer/event/I/O phases; p50/p95/p99/max, hitches and simulation/wall ratio. EMA is not a tail sample. |
| GPU | Native host, supported timers/capture with freshness and viewport/pass scope; separate GPU busy cost from CPU wait and process frame intervals. Missing metrics remain missing. |
| Baseline/candidate | Existing default: 10 s warmup + 60 s sample and at least three alternating pairs on an otherwise comparable host. Owning tracks can require stricter durations/soaks. |
| Hitches/loading | At least five fresh-process and five warm repetitions; separately identify process cold, asset/import cache and driver/shader cache. Check first interaction and setting/preset transitions. |
| Observers | Match audio, incidents, statistics, logging and diagnostics settings; use off/on ablations for attribution, not as a substitute for production behavior. Include uninstrumented controls. |
| Memory | Repeated Home/flight/quality changes, long recordings and a soak; compare steady-state/peak RSS, resource ownership and GPU counters where available, with allocator/cache effects stated. |
| Correctness | Exact state/event/replay comparisons, malformed inputs, mutation/refusal and reset/restore; native admission requires the existing ≥10,000-state oracle and fleet/lifecycle/package gates. |
| Acceptance | Existing plan: exceed run-to-run noise and improve ≥5% of the affected complete workload, or remove a named reproducible hitch/memory defect. Keep worst cases and visual/audio/input acceptance. |

Do not average away long stalls, compare different selected backends, or interpret a headless/Dummy run as audio or rendered-flight acceptance. This report's successful focused checks do not replace required CI for future runtime changes.

## Primary sources and reproduction assets

Official Godot documentation was consulted on 2026-11-19 for comparator contracts, MultiMesh visibility, thread ownership, screen copies, texture readback and native/custom CPU work. The `latest` channel is unstable and the `stable` channel is not necessarily the pinned beta. These sources explain API constraints; they do not prove an OpenRC speedup.

- [Godot Array: sort_custom()](https://docs.godotengine.org/en/stable/classes/class_array.html) — A comparator must give a consistent ordering; unstable sorting does not repair a non-transitive predicate.
- [Optimization using MultiMeshes](https://docs.godotengine.org/en/latest/tutorials/performance/using_multimesh.html) — MultiMesh batching, coarse visibility and bulk buffer preparation; context for F30, not an OpenRC benchmark.
- [Thread-safe APIs](https://docs.godotengine.org/en/latest/tutorials/performance/thread_safe_apis.html) — Scene-tree/resource/thread ownership and GPU synchronization considerations for worker proposals.
- [Screen-reading shaders](https://docs.godotengine.org/en/latest/tutorials/shaders/screen-reading_shaders.html) — 3D screen-copy timing after opaque and before transparent rendering; F32.
- [Texture2D: get_image()](https://docs.godotengine.org/en/latest/classes/class_texture2d.html) — Texture readback context for F29; actual cost remains backend/workload dependent.
- [CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html) — Profile custom CPU work and distinguish language overhead from engine operations already implemented natively.

Files in this report:

- [findings.json](findings.json): complete structured register and per-finding source anchors.
- [source_identity.json](source_identity.json): pinned hashes and source inventory.
- [sources.json](sources.json): primary-source context and version limitations.
- [evidence.json](evidence.json): compact observed results, checked-run provenance and explicit exclusions.
- [Reproduction scripts and recipe](../../../research/performance/audit-2026-11-19/README.md): byte-checked fixture, event/calibration probes and existing 54-check control.

The branch is an audit/evidence deliverable. Proposed runtime changes and their performance benefits remain to be implemented and qualified under their owning tracks.
