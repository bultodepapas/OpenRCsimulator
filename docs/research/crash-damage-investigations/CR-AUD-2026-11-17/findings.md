# Collision and damage findings

Audit date: **17 November 2026, America/Bogota**. Audited application source: [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61). This is an engineering assessment of that revision, not a judgment about individual contributors.

Read [verification](verification.md) for the exact execution record, fixture limitations, unsuccessful attempts, and commands. A deliberately failing assertion in an audit probe is evidence of a counterexample; it is not a passing regression test. Conversely, a characterization probe can pass while demonstrating undesirable current behavior.

The [18 November continuation](deep-dive-2026-11-18.md) adds records **CR-AUD-16 through CR-AUD-20** against the same application source. This page preserves the original fifteen-record register and its dated evidence.

## Classification

- **P1 — collision-world or response consistency:** a supported vehicle consumes materially different obstacle/terrain semantics, or silently drops a detected contact candidate. Address before claiming consistent collision behavior across the fleet.
- **P2 — bounded functional, presentation, or verification correctness:** reproducible wrong attribution, motion, geometry, timing, or aftermath behavior, with the affected layer identified.
- **Capability gap:** an explicitly incomplete model or unsupported domain. The improvement plan can prioritize it without rewriting history as a regression.
- **Source-confirmed:** the relevant call path establishes the behavior, but this audit does not claim an executed end-to-end flight demonstrating it.

Priorities are audit recommendations, not measurements of crash frequency. No P0 safety, security, or data-loss incident was established. Godot wreck bodies are visual aftermath; defects in them are not automatically defects in the authoritative float64 flight kernel.

## Register

| ID | Priority | Finding | Strongest evidence |
|---|---|---|---|
| CR-AUD-01 | P1 | Quad and blimp session ground queries omit the enabled lake | Stock-data session characterization with dry/lake controls |
| CR-AUD-02 | P1 | Helicopter scenery detection drops nonterminal fuselage contacts | Production detector plus shared-response control |
| CR-AUD-03 | P2 | A source-disabled but spinning fixed-wing propeller bypasses the ground-strike guard | Accepted coast tick, actual engine cut, source-on/stopped controls |
| CR-AUD-04 | P2 | Flattened impact event loses the identity of its crossing witness | Analytic two-probe crossing fixture |
| CR-AUD-05 | P2 | Effects and wreck ground assume a global flat datum | Elevated direct-input fixture and source trace |
| CR-AUD-06 | P2 | Wreck launch velocity uses a geometric center despite a custom mass center | Asymmetric inventory, nonzero angular velocity |
| CR-AUD-07 | P2 | C3 release changes represented first moment and linear momentum | Instantaneous split, no physics frame or scatter |
| CR-AUD-08 | P2 | Delayed breakup temporarily removes scheduled mass from active collision bodies | Before/after release accounting |
| CR-AUD-09 | P2 | Core collision bounds do not follow attached-component membership | Attached-wing and detached-prop point-coverage checks |
| CR-AUD-10 | P2 | Secondary-contact callback ignores valid scenery bodies | Direct callback signal with ground positive control |
| CR-AUD-11 | P2 | Wreck scenery is provisioned only for scenery-triggered crashes | Source-confirmed director branch |
| CR-AUD-12 | P2 | Aftermath clocks consume different amounts of the same supplied time | Direct update partition comparison |
| CR-AUD-13 | P2 | Kerosene flame duration retains declared fuel instead of the accepted fuel sample | Executed declared/live-fuel fixture and matching director source trace |
| CR-AUD-14 | Capability gap | Cars share scenery visuals without sharing general scenery collision | Both stock sessions: missing-overlap response versus injected-box controls |
| CR-AUD-15 | P2 | Parked-aircraft regression asserts an obsolete shelter-proxy count | Original-project failure, exact predicate diagnostic, and passing independent geometry controls |

## CR-AUD-01 — Quad and blimp omit the lake from their collision environment

**Observed result.** With the stock field's lake enabled, the sampled interior at north 110 m, east 125 m has water down-coordinate 0.45 m and lakebed down-coordinate 5.45 m. Both prepared vehicle sessions have an empty water provider. Their terrain queries return approximately **−0.00368975 m render height**, the dry-ground answer, rather than the lake-composed **−5.45 m** bed height. Their contact callbacks use the same dry environment. Ordinary dry starts still accept a tick and both sessions reset normally.

**Cause and scope.** The [quad session preparation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/multirotor/session.gd#L225-L249) and [airship preparation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/airship/session.gd#L105-L122) install surfaces and weather without composing the lake provider. Their scene paths build the field/lake independently. This is a shared-world inconsistency: the numerical contact world is dry where the field defines water and a depression.

**Evidence boundary.** `lake_session_probe.gd` characterizes actual prepared sessions and contact callbacks. It does not fly a vehicle through the water, measure buoyancy, or provide a rendered screenshot. Helicopters' explicit refusal of unsupported water is a separate, more honest capability boundary; cars already have wet-force work and must not be described as wholly lacking water interaction.

**Correction.** Resolve field composition once and pass the same immutable geometry identity to every vehicle's environment and scene. For each unsupported medium, choose and expose a deliberate refusal or restricted operating envelope. Do not silently substitute dry terrain. Lake geometry support and hydrodynamic force support need separate capability flags.

**Acceptance.** At interior, shore, bank, and outside samples, scene geometry, session terrain, and contact providers agree within a stated numerical tolerance. Cover lake disabled, non-default field, reset, and checkpoint restore. Add actual water-entry acceptance only after that family's water-response contract exists. Preserve dry-field behavior.

## CR-AUD-02 — Helicopters discard nonterminal scenery-contact candidates

**Observed result.** A controlled stock-helicopter fuselage sweep at **2 m/s** through a **3 mm** frangible box produces one nonterminal contact in the shared scenery sweep. An independently invoked shared-response control returns a finite changed state and reduces the fixture's kinetic energy from **16.4 J to 3.386286 J**. The helicopter detector returns success with an empty impact dictionary. Changing only the fixture to a hard box produces a terminal fuselage event; the open-air control is clear.

**Cause.** The [rotorcraft detector](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/rotorcraft/impact_detector.gd#L721-L730) filters away nonterminal scenery contacts. The session's consumption path handles the terminal result; the shared nonterminal response is not carried into an accepted helicopter state transition. The shared classification thresholds are estimates, not measured material failure strengths.

**Consequence.** A contact can be detected by the common geometry and then vanish at the family adapter. This undermines consistency between a hard obstacle, frangible scenery, and different vehicle families. The 13.013714 J reduction above is the shared response's estimate, not a measured real-helicopter energy loss.

**Evidence boundary.** `heli_soft_contact_probe.gd` isolates production detection and response functions with stopped rotors at altitude. It does not claim an integrated flown trajectory or certify every foliage/rotor interaction.

**Correction.** Return both terminal impact and bounded nonterminal contact observations. Apply accepted nonterminal responses through the shared kernel's transition contract, not an out-of-band scene mutation. Preserve deterministic ordering, rollback, and scenery damage ownership.

**Acceptance.** Add session-level accepted-tick cases for frangible body contact, foliage, hard contact, two simultaneous obstacles, and no contact. Verify momentum/energy bounds, one-time event publication, checkpoint/replay, and no response from rejected integration trials. Keep main- and tail-rotor contacts separately qualified.

## CR-AUD-03 — A coasting propeller bypasses the ground-strike guard after a source cut

**Observed result.** The controlled glow fixture calls the real `glow_cut()`, accepts an airborne coast tick, and then places only the propeller disc 1 mm below ground with the hull and gear clear. At **8,089.7107 rpm**, the source-disabled propeller records no strike. The source-enabled control at **8,113.9274 rpm** records a strike without a whole-aircraft crash. A source-disabled, stopped propeller correctly records no strike under the current stopped-blade policy.

The final intersecting boundary pose is injected after the genuine coast tick, and the production session process/guard is invoked. This is a controlled boundary reproduction, not a naturally flown approach.

**Cause.** The [guard in `FlightSession`](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/flight_session.gd#L3322-L3332) returns when `engine_running` is false, even though a coupled shaft can coast or windmill. The detector therefore uses source enablement as a proxy for mechanical rotation.

**Contract nuance.** [E3d2](../E3d2/README.md) describes a turning propeller reaching the field. The current [crash-damage plan](../../../CRASH-DAMAGE-PLAN.md) also contains a narrower powered-prop economics description. These are different questions: geometric/mechanical contact should be specified from actual motion; a chargeable repair observation may retain an explicitly narrower rule. Stopped blade phase is not implemented and is not established by this test.

**Correction.** Base the physical strike gate on validated shaft speed and actual disc/blade geometry. Keep propulsion enablement as event context, not a substitute for angular speed. Specify how positive rotation, reverse rotation, windmilling, and stopped blade phase are treated. Avoid coupling the fix to an unsupported structural-strength claim.

**Acceptance.** Source-on, source-cut coasting, windmilling, stopped, threshold-adjacent, and reset cases; gear/hull-clear positive control; no duplicate cost or strike event. An engine cut must not make an otherwise identical rotating disc immune. Record how damage changes subsequent propeller loads; that latter work remains a separate physical-model capability.

## CR-AUD-04 — Crossing time is serialized without its witness identity

**Observed result.** An analytic two-point fixture crosses the ground at fractions **0.2** and **0.8** of the step. The terminal policy selects the second point. The typed impact snapshot correctly retains selected point 1 and earliest-crossing point 0 separately. The flattened event then exports selected point 1 and its contact ID alongside `crossing_fraction = 0.2`, without the earliest witness's identity.

**Cause.** [Impact snapshot fields](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/impact_snapshot.gd#L65-L77) deliberately support two meanings. [Event construction](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/aircraft_contact_events.gd#L97-L105) and [crossing serialization](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/aircraft_contact_events.gd#L444-L449) flatten away that distinction. The [director](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/director.gd#L205-L246) also combines earliest-crossing location/surface with selected-component severity inputs.

**Consequence.** A downstream consumer cannot safely interpret the fraction as the named contact's time of impact. Telemetry, effects, and future failure-time transitions risk binding different witnesses into one apparent event. This is an attribution defect; the typed snapshot's explicit earliest-whole-hull diagnostic is intentional and is not itself wrong.

**Correction.** Version the event schema with named selected-contact and earliest-crossing records, each carrying point/component ID, frame, fraction, validity, and uncertainty. Alternatively omit a fraction that cannot be attached unambiguously. State which witness owns severity, surface, effects, and any later physical transition.

**Acceptance.** Reversed point order, unequal crossing times, equal-time tie, non-crossing selected point, and terrain/scenery candidates in one tick. Validate identity and time together. Preserve backward readers through an explicit compatibility policy rather than silently changing `crossing_fraction` semantics.

## CR-AUD-05 — Elevated impacts are flattened onto the field datum

**Observed result.** Supplying an impact at **y = 10 m** to the effects path places its origin and dust emitter at **y = 0.04 m**. Ninety-nine emitted chip positions lie approximately between **0.191 and 0.735 m**. The wreck's ground plane has up normal and distance zero. This fixture establishes the coordinate substitution directly; it is not a screenshot judgment.

**Cause.** [`Effects.start`](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/effects.gd#L299-L311) overwrites input height. Chip ground handling similarly assumes a flat floor. [`Wreck` ground construction](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L550-L563), later correction, and ground shadows retain a global plane assumption. Some director marks already query terrain; this is inconsistent composition, not proof that every crash visual ignores terrain.

**Consequence.** A building, tree, elevated surface, bank, or lake-adjacent collision can have one authoritative contact location and another effects/aftermath floor. Expanding scenery collisions without updating the ground assumptions exposes the mismatch.

**Correction.** Preserve the event's 3D contact point. Separate airborne debris origin, ground-attached marks, and water effects. Supply a bounded local terrain/scenery representation and normals to the wreck. Ground-dependent decals must query a valid supporting surface rather than project indiscriminately to zero.

**Acceptance.** Flat runway control, elevated wall, pitched roof, slope, bank, lake, airborne breakup, and below-datum terrain. Test coordinate frames and normals numerically, then review 1080p captures. The fixture only proves the supplied-altitude defect; rendered integration remains an acceptance gate.

## CR-AUD-06 — Launch velocity is evaluated at the wrong mass center

**Observed result.** An asymmetric 4 kg fixture has inventory center of mass at local x = **0.8125 m**, while its core box center is x = **1.25 m**. With incoming COM velocity `(1, 0, 0) m/s` and angular velocity `(0, 0, 2) rad/s`, the launched rigid body's linear velocity becomes **`(1, 0.875, 0) m/s`**.

**Cause.** The core receives a [custom center of mass](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L299-L307), while [launch velocity](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L891-L895) uses the geometric section center. Rigid-body point velocity is `v(point) = v(COM) + omega × (point − COM)`; assigning a geometric-point velocity as COM velocity introduces a spurious translation when the centers differ.

**Evidence boundary.** This is the visual flight-to-wreck handoff. It is not an error in the flight kernel's integrated COM velocity. Symmetric inventory or zero angular velocity can hide it. See [references](references.md) and the separate pinned-engine semantics probe status in [verification](verification.md).

**Correction.** Give each active body's mass, COM, inertia, and velocity one common inventory-derived reference. Convert incoming translational and angular motion once in the render boundary. Validate finite values and use the geometric box only for the explicitly approximate collision shape.

**Acceptance.** Asymmetric inventories, nonzero rotation about all axes, translated/rotated world poses, zero-omega controls, and bounded input clipping. Before any external impulse or scatter, whole-body linear momentum must match the incoming mass model within a declared tolerance.

## CR-AUD-07 — C3 component release changes first moment and momentum

**Observed result.** In a direct C3 release with no intervening physics frame and scatter disabled, active mass remains **4 kg**. Nevertheless, the represented x first moment changes from **3.25 to 5.4375 kg·m**. Linear momentum changes from **`(4, −6.5, 0)` to `(4, −0.5, 0) kg·m/s`**, a **6 kg·m/s** change without an external or declared separation impulse. Conditional on the already-launched core's pre-split COM velocity `(1, −1.625, 0) m/s`, the section's intended inventory-COM velocity is `(1, 3.25, 0) m/s`; the assigned velocity is `(1, 4.375, 0) m/s`. These are immediately inspected properties, not post-solver measurements.

**Cause.** [C3 release](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L1446-L1464) subtracts section mass without recomputing the remaining core's mass center/inertia consistently. The release velocity starts from the core's stored COM velocity but adds an angular offset measured from its geometric center (x = 0), not its custom COM (x = 0.8125 m). Separately, the fixture's section inventory center is x = 3.25 m, while its centered box's geometric center and automatic COM are both x = 3.00 m. The geometric offset error, inventory-to-shape COM difference, and stale remaining-core COM are distinct mismatches.

**Evidence boundary.** The trigger is an injected secondary-exposure transition, not a solver-generated impact. Linear momentum and first-moment checks need no angular-inertia assumption. This audit does not assert angular-momentum conservation from this fixture, because that requires a consistent inertia calculation too. It establishes a visual-physics transition defect, not physical flight breakup.

**Correction.** Treat release as a transaction over a mass inventory: partition members; recompute each COM and inertia with the parallel-axis theorem; transform velocities at the resulting centers; apply only declared paired impulses. Keep numerical clipping explicit. If a stylized impulse is desired, record its energy and momentum separately rather than hiding it in coordinate conversion.

**Acceptance.** Conservation of mass, first moment, linear momentum, and angular momentum before/after a zero-scatter split, plus a separate test for deliberately budgeted scatter. Cover repeated releases, simultaneous releases, already-detached pieces, reset/reuse, and minimum-mass floors.

## CR-AUD-08 — Delayed fragments temporarily stop contributing active mass

**Observed result.** In a 4 kg synthetic fixture with a 1 kg scheduled propeller fragment, the probe's sum of visible-body mass is initially **3 kg**. Source inspection confirms those released bodies are active while the pending body is frozen, hidden, and noncolliding; the visible-mass assertion itself does not independently inspect all three flags. The other 1 kg is already assigned to a frozen, hidden pool body with a **40 ms** release delay. After activation, active mass returns to 4 kg.

**Cause.** [Core mass accounting](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L1073-L1080) excludes groups scheduled for detachment before [delayed bodies](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L316-L348) become active. Total assigned inventory data is not erased, but the active collision system temporarily carries less mass.

**Consequence and qualification.** The core can receive a contact response during the delay with an incomplete active mass/inertia representation. The fixture's **25%** delayed fraction is deliberately extreme; it establishes no prevalence or typical percentage for the real fleet. This may be an intentional visual approximation, but its mechanical effect needs an explicit budget.

**Correction.** Keep the pending section's mass and geometry in the parent until the release transaction, or activate all physical masses immediately while delaying only presentation. Never count a fragment in both places. Choose one ownership model shared by mass, inertia, shape, and visibility.

**Acceptance.** Assert ownership and active mass every step of the delay, including impacts during the delay and reset before release. Combine with CR-AUD-07's conservation gate. Measure visual benefit before retaining propagation timing as a physics approximation.

## CR-AUD-09 — The core shape does not track which parts remain attached

**Observed result.** In a synthetic C3 fixture, the right wing remains attached and its center is `(3, 10, 0)`, but the core box does not cover that center. In a C2 fixture, the propeller is detached while its former center `(0, 10, −3)` remains covered by the whole-aircraft core box.

**Cause.** [Core bounds selection](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L299-L302) switches between whole-aircraft and core-only bounds. The [core-only bounds builder](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L637-L645) excludes named groups without matching their current attachment state.

**Consequence.** The approximation can omit an attached appendage or retain space vacated by a detached one. That creates a risk of visible penetration or invisible blocking. The probe establishes shape-point coverage only; it does not claim a solver-observed collision at those points or quantify how obvious the effect is in the stock fleet.

**Correction.** Build a bounded compound shape from the current attachment set, with a declared simplification policy. Update shape membership atomically with mass/COM ownership. Avoid repeated expensive mesh decomposition during a crash; prepare reusable per-component proxies.

**Acceptance.** For each breakup class and release sequence, verify that represented attached proxies are present and detached proxies are absent. Add actual solver contacts at formerly attached and still-attached locations, with 1080p visual review and body/shape budget measurements.

## CR-AUD-10 — Valid scenery contacts are rejected by the secondary-breakage callback

**Observed result.** Directly emitting the core's connected contact signal with its ground body increments the secondary-contact signal count. Emitting it with a valid static scenery body, with collision shape and the correct wreck layer/mask, does not increment the count.

**Cause.** The [callback filter](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L1388-L1403) recognizes its private ground and pooled wreck bodies, but excludes other static scenery colliders. Adding scenery to the collision mask alone therefore does not make it a secondary-breakage source.

**Consequence.** A wreck may physically collide with a provisioned obstacle while the cosmetic secondary-breakage exposure/audio path ignores it. Ground contact and wreck-to-wreck contact continue to work; this is not a claim that all secondary contact is absent.

**Evidence boundary.** Direct signal injection isolates callback admission. It does not prove the engine generated that signal in a live collision. The positive ground control and matching layer/mask rule out a disconnected signal or deliberately unrelated body in this fixture.

**Correction.** Give scenery bodies an explicit, bounded contact identity/type accepted by the callback. Validate obstacle ownership and lifetime; deduplicate contacts without globally suppressing unrelated simultaneous hits. Preserve separate physical response and cosmetic damage budgets.

**Acceptance.** Engine-generated core-to-wall, fragment-to-wall, ground, and wreck contacts; deleted obstacle; invalid body; repeat contact; and independent simultaneous contacts. Verify one accepted event with correct obstacle identity, normal, and bounded energy.

## CR-AUD-11 — A ground-triggered wreck is not given nearby scenery colliders

**Source-confirmed behavior.** The [director's provisioning branch](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/director.gd#L247-L260) creates the nearby wreck-scenery set only when the initial impact is a scenery impact. A ground-triggered crash can still send debris toward nearby buildings or track structures, but it does not enter that provisioning branch.

**Evidence boundary.** This audit traces the branch and the wreck's scenery ownership; it does not claim a rendered demonstration of a ground-launched fragment passing through a particular building. CR-AUD-10 is a separate defect: provisioning the colliders does not by itself make their secondary-contact callbacks eligible.

**Correction.** Provision a bounded local aftermath collision neighborhood based on wreck location and reachable motion, regardless of initial trigger. Define how the neighborhood updates as fragments travel. Keep count/radius caps observable and distinguish an intentional omission from an empty scene.

**Acceptance.** Identical wreck state and nearby obstacle after a ground trigger and a scenery trigger must receive equivalent collision coverage. Test the staged-build deadline with fast fragments; record omitted candidates and late colliders. Do not assume an existing count cap proves the relevant obstacle arrives in time.

## CR-AUD-12 — Effect and wreck clocks diverge under long update deltas

**Observed result.** Sixty direct `1/60 s` effects updates produce age **1.0 s**. Ten direct `0.1 s` updates, also totaling one supplied second, produce age **0.5 s**. The effects age uses a 0.05 s cap, while the wreck uses a different update policy and the scene/director have other clamps.

**Cause.** [`Effects.update`](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/effects.gd#L483-L515) uses clipped integration time for event age as well as numerical integration. The [wreck clock](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/wreck.gd#L529-L540) does not share that exact consumption rule. Scene caps add another distinction.

**Consequence.** Release, sparks, dust, fire, venting, sound, and expiration can drift relative to one another after hitches or low frame rates. This is presentation synchronization. It does not prove the fixed-step flight integrator advances at a wrong step size.

**Evidence boundary.** The probe compares direct update partitions; it is not a wall-clock benchmark of an actual 10 fps game. The application also deliberately limits physics catch-up, so wall time, accepted simulation time, and presentation time must be distinguished explicitly.

**Correction.** Choose a single aftermath clock with documented pause/time-scale behavior. Advance age from that clock; subdivide numerical motion with a bounded number of stable substeps instead of silently discarding age. Define the overload policy when the substep budget is exhausted.

**Acceptance.** Equal supplied time partitioned at 240, 60, 30, 20, and 10 Hz, plus isolated hitches, pause/resume, reset, and time scale. Scheduled-event times should agree within the declared clock tolerance. Separately bound motion error and CPU cost.

## CR-AUD-13 — Kerosene fire uses a stale fuel quantity

**Source-confirmed disagreement.** [Director configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/director.gd#L99-L110) caches the declared kerosene inventory. At impact, the director [selects a live/contact sample or accepted-endpoint fallback](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/director.gd#L295-L317) and computes an energy outcome from it, but [passes the cached scalar into `Effects.start`](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/director.gd#L340-L345). `start()` computes kerosene fire duration from that scalar; [`apply_energy`](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/render/crash/effects.gd#L573-L603) reconciles gasoline duration, not kerosene duration.

**Consequence.** The report can describe remaining fuel correctly while the flame lifetime still corresponds to the original declared tank quantity. This does not establish that an empty, cold engine always ignites: heat/source, severity, and estimated rupture conditions still matter. Fire duration is already a presentation estimate, but two consumers should use the same selected fuel sample.

**Observed result.** The completed scenario/fuel probe uses a hot, ruptured C4 case with 1.28 kg declared and 0.035 kg live kerosene. The typed outcome reports **1.000000 s**, while the effect's internal flame-duration field remains **36.571429 s** after `apply_energy`. The probe completes **61 checks with one expected desired-behavior failure and no engine errors**. Other checks cover the 11 registered fixed-wing configurations through synthetic severity inputs and cold-kerosene/glow/LiPo controls. This is an effects-state reproduction, not a filmed 36-second fire or a full-session fuel-burn flight. Earlier startup timeouts remain in [verification](verification.md).

**Correction.** Build one typed energy outcome from the selected crash fuel sample, preserving its live/contact or accepted-endpoint basis and apply it to all fuel kinds. Keep the legacy scalar only for backward-compatible reporting, explicitly marked as declared inventory. Do not let that compatibility field drive current effects.

**Acceptance.** Full, nearly empty, empty, hot, cold, ruptured, unruptured, glow, gasoline, and LiPo cases. Compare report and visible-effect timing fields, not only report contents. Preserve no-flash/no-fire controls and reset behavior. No material should receive a cinematic explosion solely because speed is high.

## CR-AUD-14 — Cars' general scenery collision coverage is narrower than the rendered field

**Source-confirmed capability gap.** Ground scenes build field scenery and RC-track dressing, while the [ground session](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/ground_vehicle/session.gd#L159-L177) obtains its collision walls through the road/course provider. The stock course supplies its defined walls rather than the complete shared scenery collision world. Tyre stacks and general field buildings are not thereby made car collision obstacles.

**Counterevidence.** The stock course has **five defined wall proxies**, and these are a real supported collision path. Historical track documentation explicitly treated some dressing as decorative. Calling every visible item a regression, or saying the cars have no collisions, would be incorrect. The user-facing gap is that visually substantial shared scenery does not have uniform collision semantics across vehicle families.

**Observed result.** The corrected probe completes **19 checks with zero failures or engine errors**, characterizing the coverage gap. It locates `rc_track:tyres:01` near the course (north 34.9 m, east 3.4 m) and a stock axis-aligned church building (north −164.75 m, east −2093.5 m) in the 6,156-proxy shared world. The distant church is reached only by pose injection in this fixture. Both cars' ordinary road providers omit these obstacles. At injected overlapping boundary poses, the actual solver reports **zero wall contacts**; the control with an equivalent injected box reports **10 contact witnesses for the electric car and 13 for the Nitro car**, with finite positive loads. Both ordinary dry starts accept a tick, the runway control is clear, and the stock slalom wall is provided. These are static-overlap/solver controls, not driven passages through scenery. An initial probe used an incorrect unprefixed fixture ID and was corrected; that mistake belongs to this audit. See [verification](verification.md) for the raw records.

**Correction.** Define a visible collision-coverage contract. Adapt the common scenery provider into bounded car contacts where supported, or clearly designate decorative/unsupported content. Avoid copying a large scenery world into a separate divergent car list. Car body, tyre, suspension, and wet-ground response remain distinct contracts.

**Acceptance.** Both stock cars against defined track walls, tyre stacks, buildings, foliage, lake banks, and open runway; oblique sliding, reversal, reset, and damaged driveline. Show that any new general scenery adapter does not bypass the car's existing wall-energy/contact limits. Test actual integrated motion in addition to provider membership.

## CR-AUD-15 — A parked-aircraft regression expects the old shelter geometry

**Observed result.** `test_parked_aircraft_collision.gd` completes 45 checks with one assertion failure, both in the exact-source mirror and in the original hydrated project. There are no engine errors. Its message alleges that shelter elevation adds a duplicate floor/support proxy, but the conjunction includes a hard-coded `shelter_parts == 19` requirement. An instrumented copy preserves every original assertion and prints the actual predicates: proxy present, **zero height error**, damage profile `none`, **zero `aircraft_support` pieces**, and **24 shelter pieces**. Only the obsolete count differs. See the [diagnostic script](evidence/diagnostics/parked_aircraft_diagnostic.gd), [log](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/runs/diagnostics/parked-aircraft/engine.log), and [checked report](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/runs/diagnostics/parked-aircraft/report.json).

**Cause and counterevidence.** The [parked-aircraft test](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/tests/test_parked_aircraft_collision.gd#L103-L137) retained the previous 18-post/one-roof count. The [current builder](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/scenery/collision_world.gd#L729-L757) deliberately uses 18 posts plus six roof strips. That sloped-roof change is documented under DR-19e in the [drone plan](../../../plans/drone-racing.md). In the same campaign, `test_landscape_collision.gd` passes 52 checks, including its 24-piece assertion and post, roof, and open-interior controls.

**Classification.** This is a verification-maintenance defect. It is not evidence of an added floor, an unwanted aircraft support, a mirror discrepancy, or a duplicate physical impulse. Roof/post proxies can intentionally intersect at structural joints; the failed count does not qualify their combined response or prove they are disjoint. The existing test failure must remain visible until its contract is repaired.

**Correction.** Change the regression's oracle rather than restoring obsolete production geometry to satisfy it. Build otherwise identical shelter worlds with and without the parked fleet; compare the shelter proxy dictionaries/IDs and support/floor inventory, and require that only the authored aircraft-part proxies are added. Keep explicit height, nondestructible-profile, and valid collision controls. Merely replacing 19 with 24 fixes today's number without fully testing the no-duplicate property named by the assertion.

**Acceptance.** The semantic invariance test passes with the current six-strip roof, detects an intentionally added duplicate support/floor, and detects incorrect aircraft elevation. The separate geometry suite continues to qualify roof/post contact and open clearance. Retain the original 45/1 baseline and diagnostic evidence; a later fix must have its own source revision and checked result.

## Investigated limits that are not promoted to new defects

The audit deliberately retains counterevidence and existing disclosures:

- Stock physical progressive airframe/gear fracture is incomplete. `AircraftGroundDamage` is experimental and not installed as a calibrated stock-flight module. Its tests do not prove damaged stock flight. See [fleet and scenarios](fleet-and-scenarios.md).
- After a recorded prop strike, blades can be hidden and the power source cut while the intact propeller model still supplies mechanical/aerodynamic terms. This is an existing simplification requiring a separate damage-transition design.
- Ordinary hull support and wheel microrelief are not fully unified; [GP-10](../../ground-physics/GP-10/README.md) already records that limitation. Sparse point hulls and conservative proxy geometry are not continuous surface fracture models.
- A high-speed glancing contact is not automatically a full-energy normal impact. Conversely, a low normal speed does not establish harmless abrasion, snagging, or fatigue. Current severity classes are estimates, not measured structural strengths.
- Native/reference parity, exact replay after new damage transitions, full-frame swept rotor coverage, and high-speed domains still need explicit qualification. A previous multirotor ramp strike issue has a shipped regression test and is not re-reported here as unfixed.
- The car's bounded kinetic-energy-residual damage observer is not a calibrated crush model. Braking, glancing contacts, and stored driveline energy deserve targeted qualification, but this audit has not produced a clean independent counterexample for each suspected attribution risk.
- Staged scenery collider construction may miss an arrival deadline; this is a testable risk, not an observed tunneling result in this audit. Count bounds and omission telemetry are useful existing safeguards.
- Some engine attempts stalled before script completion. They are recorded as inconclusive infrastructure/execution results, not evidence of a product collision defect.

These limits become work items in the [improvement plan](improvement-plan.md). They must not be counted again as newly reproduced failures merely to increase the issue total.
