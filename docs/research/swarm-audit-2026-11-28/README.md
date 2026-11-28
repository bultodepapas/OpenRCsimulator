# OpenRC Simulator: physics, correctness and FPS audit

**Audit date:** 28 November 2026

**Audited source:** [71306784a250d634854f0c8bab3a927cc46a61b8](https://github.com/bultodepapas/OpenRCsimulator/commit/71306784a250d634854f0c8bab3a927cc46a61b8)

**Branch:** [audit/swarm-physics-fps-2026-11-28](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/swarm-physics-fps-2026-11-28)

## Outcome

The audit confirmed **six software defects** and **six scoped performance opportunities**. Two native component experiments reduced operation or allocation counts while preserving the tested output bits. Game probes counted unnecessary hidden lighting updates and HUD construction. Two further opportunities have source-level support. No target-hardware FPS improvement has been measured or implemented.

Every accepted item received an independent review of its evidence and limits. A separate native preparation concern remains conditional because this workspace could not install the qualified native backend. Two propulsion issues were matched to earlier findings in draft PR 17 and are not counted as new.

The branch contains reports, diagnostic witnesses, component comparisons and compact receipts. Production code, aircraft data, the 240 Hz clock, float64 arithmetic and RK4 remain as at the audited source. A passing counterexample witness means that the documented defect or work count was reproduced. It does not mean that the defect has been repaired.

## Read the evidence

| Document | Purpose |
| --- | --- |
| [Independent verification](verification.md) | Acceptance decisions, rejected broader claims, duplicate checks and reproduction boundaries |
| [Aircraft physics](specialists/aircraft-physics.md) | Wake stability, dimensional propulsion checks and reference-path work |
| [Pure mathematics](specialists/mathematics.md) | Collision counterexamples, exact recurrence and rational table minima |
| [Application and replay](specialists/application-replay.md) | Storage recovery, solver identity and macOS activity entry |
| [Native engineering](specialists/native.md) | C++ comparisons, allocations and conditional admission concern |
| [Game performance](specialists/game-performance.md) | Actual Corsair scene, hidden lighting and instrument construction |
| [Baseline CI review](specialists/ci-baseline.md) | Six failed GitHub jobs, observed predicates and attribution limits |
| [Reproduction instructions](../../../research/swarm-audit-2026-11-28/README.md) | Runnable probes, controls, results and environment |

Source paths and line numbers in the specialist reports refer to the audited commit. The branch adds audit material only.

## Confirmed defects

P2 denotes a medium-priority correctness repair with a reproduced, bounded trigger. P3 denotes a lower-priority edge case whose wider gameplay consequence remains unmeasured. These are engineering priorities, not safety certifications.

| ID | Priority | Finding | Evidence and affected boundary |
| --- | --- | --- | --- |
| SW-01 | P2 | Rotational padding can hide a real box entry | Eleven collision-query cases include mirrored faces, a rotated shed and a continuous two-tick control. A physical crossing at 0.00845 of the second tick produces no contact. Synthetic valid query geometry; stock-flight incidence is unknown. |
| SW-02 | P2 | FPV replay omits result-storage recovery | A recording starts on an IDLE pad with eight pending results. Live save recovery drains the queue and admits a start; replay restores the full queue and refuses that same first tick. An empty-queue control replays exactly. |
| SW-03 | P2 | FPV and airship report unavailable solver identities as unchanged | Both adapters report `solver_changed=false` when both fingerprints are the official unavailable marker. Four real one-tick files exercise known and unavailable controls; the marker is injected into the process-local identity cache. |
| SW-04 | P2 | Raw custom aircraft can admit an unstable negative wake length | A one-field Stik edit loads and trims. Its wake-error multiplier is 2.27098 per tick, versus 0.92152 for stock. A normal elevator input leads to a large internal wake residual through 40 accepted reference ticks. |
| SW-05 | P2 | Corsair fold throttle hold arrives at presentation cadence | An actual O event in the stopped-runway Main scene is accepted before the hold exists. The observed run publishes full throttle for ticks 1–11, then idle after the first presentation update. |
| SW-06 | P3 | Capsule query accepts a hidden internal end-sphere contact | Both mirrored witnesses produce a hard-terminal event 0.197 m beneath the capsule surface. The path starts and stays inside the obstacle. Real exterior-entry and no-contact controls behave correctly. |

### SW-01: distinguish the physical box from its conservative padding

The body probe is on the yaw axis, so its true trajectory remains a straight translated line even while the body turns. At a 20 micrometre physical clearance, 1.5 degrees of yaw introduces roughly 85.67 micrometres of conservative padding. The padded-box routine calls the start “inside” and discards the segment, even though it crosses the physical face.

An independent two-tick witness addresses the objection that the prior tick would already have hit the padded object. Its shared join has 84.5 micrometres of real clearance, outside the first tick's padding and inside the second's. Neither query reports contact; only the second actually crosses the physical boundary. This is a geometric counterexample to the public contact function, not a measured rate of aircraft tunneling.

Repair the narrow-phase padded-box inside test and its first-entry semantics; the broad-phase query already admits this candidate. Preserve true initial-overlap handling and validate both directions, rotated boxes, physical face witnesses and adjacent-tick continuity. [Mathematical proof and source locations](specialists/mathematics.md)

### SW-02: replay must preserve the admission of a recorded tick

The live scene retries failed race-result persistence before accepting a start. The recorder's checkpoint can predate that successful retry. Replay restores the older full outbox without the storage drain, and its ordinary input admission then rejects a tick that was genuinely accepted and recorded.

The reproduction uses public session methods and real recorders with a deliberately obstructed scratch results path. It mirrors the scene's save-before-start operation. It does not drive keyboard events through the complete FPV scene. Eight ordinary completed races within one uninterrupted F10 recording is not the claimed trigger: the regular terminal retry path resets the activity and closes that recording.

A repair should make replay of accepted rows independent of later filesystem availability while preserving the live full-outbox limit, result ownership and failed-save behavior. Replay must not write user race records as a workaround. [Application evidence](specialists/application-replay.md)

### SW-03: numerical row equality cannot establish an unknown solver identity

Both adapters compare the fingerprint strings directly. Two `unavailable-export` values therefore look equal. The production helper can emit this marker when a release identity cannot be resolved. The source-process experiment injects exactly that marker and runs the unchanged capture and verify adapters. It is not a run of a damaged or receipt-less macOS executable.

The defect is false solver provenance. The airship's documented ability to compare identical rows across *known* different solvers is a separate policy and should be preserved. Centralize valid-identity comparison or make unknown identity explicit, covering either side unknown, both unknown, known equality and known inequality. [Application evidence](specialists/application-replay.md)

### SW-04: validate the distance used by the causal wake law

The derived distance is `L = horizontal_tail_x − wing_area / (4 × wing_span)`. The lag residual follows `e_next = e × exp(−dt × V / L)`. Positive speed and time require a positive distance for decay. The raw loader checks the position components but does not reject the demonstrated negative derived distance.

The unchanged Stik has L = 0.764700033 m. Moving only its horizontal pressure centre to x = 0 gives L = −0.076199967 m. From settled trim and a +0.25 elevator increment, the altered residual reaches approximately −1.249 × 10¹¹ m/s after 40 accepted ticks, while the stock residual is approximately −0.5993 m/s. These numbers describe an **internal equivalent-lift-velocity proxy**, not aircraft speed.

All 16 inspected direct gradient records have positive distances. Workshop package construction separately checks conventional tail arms. The confirmed exposure is directly loaded custom JSON on the reference backend. The native equation was read, but no custom native admission or trajectory is claimed. Reject nonpositive distance before publishing the applicable model, with zero, negative and positive-control cases. [Physics report](specialists/aircraft-physics.md)

### SW-05: apply the fold interlock when the action is accepted

The O handler changes the fold target. The presentation callback later advances the mechanism and writes the throttle hold. The fixed-step input path can run in between. A callback-order control and a second probe through the actual Main scene both reproduced the difference.

The full-scene test injects an O event after a physics-frame signal and listens to naturally scheduled accepted input publications. The eleven full-throttle ticks are specific to that headless schedule. They are not a maximum delay or a hardware input-latency measurement. Recording the already-conditioned throttle can still replay exactly; the problem occurs when generating the live command.

Assert the hold at accepted action time. Resolve the mechanism's physical timing and release on the accepted simulation clock, and derive presentation from it. Check pause, reverse, restart, airborne refusal, keyboard/radio input and multiple physics ticks before one rendered frame. [Game report](specialists/game-performance.md)

### SW-06: restrict capsule cap roots to their exposed hemispheres

The capsule routine considers both complete end spheres. A segment already inside the cylinder can enter the hidden half of one sphere and acquire an event despite never crossing the exterior. The returned point and nearest-axis normal pass the approach-speed check.

Filtering sphere roots by the exposed hemisphere is a narrow candidate repair. Include both tips, the cylinder join, genuine exterior entries and overlapping starts. A prior audit established that a synthetic integrated flight could end up inside a capsule after a separate missed exterior entry. That evidence supports the possibility of overlap; it does not establish this exact hidden-cap event in normal play. [Mathematical report](specialists/mathematics.md)

## Performance opportunities

The following are candidates for controlled patches. Operation counts, live node counts and shader setters are direct measurements at their stated boundary. They cannot be converted into a percentage FPS gain without measuring the complete frame.

| ID | Candidate | Verified observation | Qualification still needed |
| --- | --- | --- | --- |
| PERF-01 | Skip analytic CL/CD work overwritten by an enabled wing polar | Across 160 enabled synthetic six-strip calls, emitted `pow` calls fell 3,872→1,952 and `sin` calls 3,546→1,768. All 1,920 load words across 320 total enabled/disabled cases matched, as did sampled FP status. | Qualified native compiler, admitted stage, full replay and frame/tick measurements. Current test uses GCC 14.2. |
| PERF-02 | Move a disposable family-stage derivative vector | Eight accepted turbine cases save one allocation each. Three-wheel requested allocation bytes fall 120→72; ten refused cases retain their result and allocation counts. | Glow component control, qualified ABI, fault/restore parity and actual allocator/frame cost. |
| PERF-03 | Guard reference-only diagnostic strip norms | Six full 3-D norms per conventional six-strip local evaluation feed only optional debug rows. Production force callers pass no rows. The native code already avoids this work. | Implemented A/B, diagnostic equality and measured reference-path time. Source-only count. |
| PERF-04 | Skip the discarded macOS FPV startup identity prewarm | An eligible Mac release hashes its bundle on each new FPV activity even with recording off; actual F10 requests a fresh identity later. | Packaged macOS entry and first-F10 timing/I/O, cold and warm. Preserve every real identity check. |
| PERF-05 | Construct optional HUD widgets on first use | Pilot and Off each build 710 manager nodes, including 426 nodes in 19 hidden optional instruments. Existing lazy glass behavior works. | Startup plus first-reveal time, memory and visual/state parity. This refines earlier HUD work. |
| PERF-06 | Avoid updating uniforms for hidden aircraft lights | With Festival installed and mode Off, 60 advancing samples produce 660 shader-parameter setter calls across 11 hidden bindings. Paused Off and Disabled-profile controls produce zero. | Candidate behavior on reveal/rewind/VFX, rendered CPU/GPU attribution and frame distributions. |

### Recommended order for FPS work

Begin with **PERF-06** and **PERF-01**, because they remove concrete repeated work on active runtime paths. For lighting, reconcile visibility transitions and current clock phase before showing a binding; a blanket early return could replay expired effects or leave stale colors. For polar coefficients, retain the exact arithmetic and ordering of every value that survives the branch. The component comparison supports a small change; it does not qualify a released native kernel.

Consider **PERF-02** after measuring allocator cost in an applicable turbine or glow scenario. Its 960 avoided allocations per simulated second assumes exactly four affected evaluations at 240 Hz. Resource events and other paths can change the call count. The 46,080-byte arithmetic under that assumption describes allocation traffic, not retained memory.

Use **PERF-03** when reference fallback or reference development throughput matters. It is not a saving in the current native implementation. Treat **PERF-04** and **PERF-05** as activity-entry, loading and first-use work. Improvements there may reduce stalls or startup time without changing steady-flight FPS.

The source and count evidence are in the [native](specialists/native.md), [game](specialists/game-performance.md), [application](specialists/application-replay.md) and [physics](specialists/aircraft-physics.md) reports.

### Required performance experiment before adopting a patch

1. Use the exact pinned engine, a qualified native package where applicable, a complete checkout and an actual target GPU. Record CPU/GPU, display resolution, renderer, graphics settings, backend identity and power state. Keep source and package identities with the measurement.
2. Freeze aircraft, field, weather, inputs and camera. Include the Stik with Festival Off and All; polar-equipped Extra/Avanti with flaps, near-ground and high-angle conditions; and healthy ordinary-flight controls. Measure Pilot/Cockpit first reveal and Mac FPV entry separately from flight.
3. Alternate baseline and candidate runs after equal warmup, with at least five matched runs per scenario and a fixed measurement window. Collect CPU and GPU frame time, median/p95/p99 presentation time, simulation tick cost, accepted simulated time per wall second, draw calls and the candidate's operation counter. Report run-level variation, not only the best run.
4. Run the existing numerical oracle and deliberate negative control, same-backend replay, contact/resource boundaries and applicable UI visual checks. A change must keep the 240 Hz contract and required numerical evidence. Reduced simulation progress is not an FPS improvement.
5. Accept a change only when the target metric improves beyond run-to-run noise and the relevant correctness and visual gates pass. A 60 FPS budget is about 16.67 ms per frame; 120 FPS is about 8.33 ms. CPU and GPU can overlap, so adding isolated savings does not predict whole-frame throughput.

Use the project's existing checked runner and frame tools described in [tools/debug/README.md](../../../tools/debug/README.md) and [tools/godot/README.md](../../../tools/godot/README.md). The workspace had no hardware GPU or `/dev/dri`, so this rendered campaign remains unexecuted.

## Test and qualification results

| Layer | Result |
| --- | --- |
| Existing Python tooling tests | 221 GOD TEST tests and 186 debug tests passed; one additional debug test skipped. Total: **407 passed, 1 skipped**. |
| Selected unchanged engine tests | **23 checked invocations passed**, including numerical contracts, aerodynamic flow/continuity, wake transport, fuel events, presentation cadence and three replay families. |
| Assertion detail | Twenty-two scripts report **4,402 checks**. The aero-flow script separately reports **25,000 local-flow comparisons** and **25,001 local-load comparisons**; do not add these unlike units into a single test count. |
| Existing race replay | The ordinary baseline recording replayed **16,374 ticks** exactly. The new storage-recovery witness exercises a different boundary. |
| New Godot evidence | Nine successful defect/opportunity probes, including both Corsair controls. The additional native-refusal probe completed only its reference preconditions because the native library was absent. |
| C++ comparisons | Two baseline/candidate component experiments, independently rebuilt by the verifier. Exact tested outputs and counters are retained. |
| Table checks | Two independent reducers, including exact rational arithmetic. Ten direct files passed the axial-power condition on overlapping authored forward intervals: **six catalog base files and four fixtures, seven distinct table pairs**. |
| Full baseline GitHub CI | **Not green.** Six failed jobs were inspected; three other jobs remained in progress at the recorded snapshot. See the separate CI review. |

The exact table minimum is 9929811/2426000000, approximately 0.004093079555, on the F4U at J = 23643/24260. This is a necessary power-consistency check over the stated intervals, not a validation of all propeller regimes, extrapolation, stall behavior or real-aircraft handling.

Initial probe-development attempts included GDScript identifier/type errors and missing files excluded by the local sparse checkout. These were corrected before the successful receipts. They are recorded as harness/setup failures, not product defects. The checked runner rejected them rather than trusting process completion.

### Existing CI failures

The baseline [CI run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/46153937220) is tied to the same audited SHA. Its six inspected failures concern:

- A native admission preparation time of **44,016 ms**, against a strict less-than-10,000 ms bound on a shared-graph fixture.
- A scenery test assertion that treats a nonempty native-fallback reason as failure, despite the tested reference impact proceeding.
- An FPV race-integrity fixture that fails to create its prerequisite obstacle strike.
- A combined Resume focus-and-containment assertion after Pause resizes at 200% text scale.
- A debug bridge mock missing a property read by an observer, producing an engine error despite process exit zero.
- A weather fixture with **four mismatched source pins out of nineteen**, rejected before endpoint comparison.

These are existing qualification failures with different causes and evidence. They are not six additional newly confirmed aircraft bugs. The native job's intentional mutant failure is a valid negative control and was excluded from the failure list. [Full job links and triage](specialists/ci-baseline.md)

## Conditional finding and prior work

**U-01: late native refusal after freezing live configuration.** Source ordering freezes aircraft/model/hull before later guards can refuse. A deep-metadata fixture has identical numeric configuration and reaches the reference preparation boundary, but the real native control reports that the library is not installed. The outer mutation-on-refusal result is therefore unverified. Retain it as an admission test gap and run the provided diagnostic on a qualified package before counting it as an executed defect.

The host has GCC 14.2.0; the qualified Linux native path pins GCC 13.3.0. The component experiments deliberately do not substitute for that build or alter admission restrictions.

The Phoenix static figure-of-merit error (**A36 F6**) and permissive external electric CT/CP power admission (**A36 R6-G01**) already appear in [draft PR 17](https://github.com/bultodepapas/OpenRCsimulator/pull/17), which was unmerged at review. They were rechecked and cross-referenced. The HUD proposal extends HUD-13-R11/UI-34c; macOS FPV prewarm extends A24 to a new lifecycle caller. The polar overwrite work is distinct from A33's overwritten spatial-wind calculation. Existing ledgers were consulted before classifying novelty.

## Review team and verification method

Six roles were assigned: aircraft physicist, pure mathematician, senior application developer, senior native developer, game/performance developer and independent verifier. Every specialist invocation requested **GPT-6.2 Astra with ultra reasoning**. The available four-slot limit allowed the lead and three specialists at once; roles were rotated, and the mathematics role received a replacement pass. This records the requested model configuration, not an independent attestation of serving infrastructure.

The lead owned the checkout and all Godot processes. Specialists wrote separate staging material, reviewed callers and prior ledgers, and proposed falsifiable witnesses. The verifier could reject or narrow a finding. It authored the independent box control, independently calculated the capsule root and wake factors, reran both C++ experiments and the rational table screen, and rehashed all weather source pins. Broader race-trigger, native-execution and FPS claims were excluded where the evidence did not support them.

This audit provides actionable software evidence. Physical calibration, stock-flight incident frequency, full qualified native coverage and target-machine rendered performance remain separate validation tasks.
