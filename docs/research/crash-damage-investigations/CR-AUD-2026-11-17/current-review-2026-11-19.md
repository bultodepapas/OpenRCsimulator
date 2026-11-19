# Collision realism and fleet coverage: current-main review

**Date:** 19 November 2026, America/Bogota.

**Application revision:** [`372053ac9448942e154801e3299cf77669161d08`](https://github.com/bultodepapas/OpenRCsimulator/commit/372053ac9448942e154801e3299cf77669161d08).

**Existing audit branch:** `audit/collision-damage-2026-11-17`, continued from `6029eb63d021d70096c89b7a8adc2d4ef6d02efb`.

**Scope:** collision detection, impact severity, damage ownership, breakup, debris, terrain/scenery/vehicle/person coverage, consistency and bounded performance. This continuation changes audit documents and evidence, not application behavior.

## Assessment

**The reported inconsistency has concrete implementation causes.** Contact coverage differs between vehicle families. Some severity decisions lose the actual contact normal or the velocity before response. The wreck presentation also has independently reproduced errors in mass, center of mass, collision ownership and elapsed time. Those defects should be repaired before tuning friction, adding fragments or making impacts more dramatic.

The existing investigation already contains 27 scoped records. Comparing all of them with current main finds **one repaired item, CR-AUD-15**, and **26 whose relevant logic remains unresolved**. The repaired parked-aircraft test now passes all 45 checks. This continuation adds **CR-AUD-28, CR-AUD-29 and CR-AUD-30**, bringing the register to **30 records, 29 unresolved at this revision**. Records include capability gaps and presentation defects; this is not a count of 29 flown regressions. The [verification record](current-verification-2026-11-19.md) separates accepted ticks, direct fixtures, observation checks, source inspection and unsuccessful attempts.

The old audit branch and current main have diverged. This review therefore uses a separate checkout of the exact main revision and retains the older findings as dated evidence. It does not merge unrelated application changes into the audit branch. All source links below are pinned to the reviewed main revision.

## Why the crashes can look wrong

The user's exact play session has not been reproduced. The table connects the reported symptoms to demonstrated implementation defects and source-level risks; it does not claim that each mechanism caused that particular session.

| Reported symptom or related risk | Concrete mechanism or qualification | Consequence and corrective direction |
|---|---|---|
| A seemingly minor contact ends flight abruptly | Different terminal policies by vehicle; fixed-wing contact ordering/identity problems | Establish the correct earliest supported contact and preserve its normal, point and response before changing thresholds. A terminal policy is not a measured material-strength law. |
| A terminal contact receives an excessive aftermath grade | The fixed-wing director uses a flat normal for non-scenery severity | Correct the grade's kinematics. The director runs after termination and does not itself cause the flight to end. |
| A contact produces no appropriate response | General car scenery is omitted; helicopter nonterminal scenery candidates are discarded | Specify supported world coverage and preserve supported nonterminal response. |
| A severe impact looks weak | The quad crash presentation receives velocity after the plant has settled the normal motion; CR-AUD-29 | Preserve a pre-response contact receipt and grade from that receipt. A nearly stationary terminal state does not describe the impact that created it. |
| Pieces slide, float, fall too quickly or settle unnaturally | Fixed-wing wreck/effect ground is flat; collision boxes are coarse; custom COM launch is inconsistent; airborne damping is explicitly stronger than physical intent | Repair geometry, terrain ownership and COM kinematics together, then measure sliding/rolling/bounce and tune damping and friction. |
| Parts fail to break, detach late or collide as if still attached | Core collision shape does not follow actual attachment membership; scheduled parts temporarily leave active collision mass; secondary scenery contacts are rejected or never provisioned | Make a split one atomic ownership transaction: mass, first moment, inertia, shape, COM velocity and activation. Keep animation delay separate from physical ownership. |
| Effect lifetime can depend on update cadence | A direct-update fixture shows wreck and effects consume supplied elapsed time differently; CR-AUD-12 | Use a common pause-aware clock and a bounded substep/remainder policy. A rendered frame-rate comparison remains to be qualified. |
| A ground crash appears to hit a nearby person | Helicopter lens presentation infers contact from nearby scenery instead of the authoritative hit; CR-AUD-30 | Route actual obstacle identity and material into presentation. Proximity alone is insufficient evidence of a person contact. |

These are distinct layers. The authoritative flight simulation uses a custom float64 kernel; Godot rigid bodies are used for the wreck presentation. A visual breakup, a terminal flight condition, a persistent cost assessment and a physical change to a flying aircraft are different outcomes. Repairing one layer does not establish the others. See [the current stack][stack], [the crash plan][crash-plan] and [the wreck implementation][wreck].

## Fleet inventory and present coverage

The [Home catalog][catalog] and [vehicle roster][roster] expose **13 selectable IDs**: eight fixed-wing configurations, one helicopter, one quad, one blimp and two cars. Three additional technical Stik configurations bring the fixed-wing registry to 11 routes; they are not three more selectable aircraft. The current scenario/fuel probe loads all 11 registered fixed-wing configurations and evaluates controlled estimator inputs. It does not fly all 11 through every obstacle.

| Family / selectable entries | Implemented contact path | Principal boundaries in this audit |
|---|---|---|
| Ugly Stik glow and Ugly Stik 6S electric | Shared fixed-wing hull, prop-ground, gear and scenery paths, with powertrain-specific state | Source-off spinning prop miss; sampled hull and gear/scenery gaps; common wreck defects. Hidden Stik powertrains exercise different source/fuel arrangements. |
| Extra 300S; P-51D; F4U Corsair | Shared fixed-wing solver, model-specific geometry, mass and inventory | Shared code coverage is not calibrated structural equivalence. Thin parts, prop-only and gear-only contacts need model-specific cases. |
| Vantage/Avanti Jet; Turbo Lumber/Timber; Moon Runner/X8 | Shared fixed-wing path with different propulsion, gear and layouts | Kerosene live-fuel duration mismatch; retract/gear contact boundaries; a gearless layout must not inherit wheeled assumptions. |
| X-Cell / HX-700 helicopter | Skid, fuselage/boom/fin and main/tail-rotor witnesses; separate response and wreck path | HX visual/X-Cell physics are surrogates; nonterminal scenery candidate is dropped; delayed rotor frame is stale; water contact explicitly refuses as unsupported; person attribution can be false. |
| FPV quad | Strict/graded modes, frame response, friction, prop wear and health affecting thrust | Graded frame uses endpoint/midpoint tests and props use endpoint tests; this is not general swept CCD. Lake context, contact energy, finite-box overlap, terminal state and severity need separate repairs. |
| RC blimp 5 m | Envelope/gear ground forces and sampled obstacle envelope with travel padding | Every obstacle class is terminal. The declared method is bounded below 10 m/s and has appendage limitations; this is not a globally enforced speed guarantee or validated puncture model. Lake and recording identity remain unresolved. |
| Bisonte MT8 electric; MONSTER CAR 2 nitro | Dedicated wheels, suspension, body/course-wall response and lake-aware ground sampling | General world scenery is not forwarded to the car solver. Damage region can follow sideways velocity rather than the front-only contact. The damage observer can reduce drive; it is not a general deformable-body solver. |

Family-specific source: [fixed wing][flight], [helicopter detector][heli-detector], [quad plant][quad-plant], [airship session][airship], [car course][car-course]. The [original fleet matrix](fleet-and-scenarios.md) remains the detailed inventory; this section reconciles it with current main.

### What can actually be hit

| Target | Present representation | Audit conclusion |
|---|---|---|
| Flat field, runway and surfaces | Dedicated terrain/gear/hull laws; materials vary by family | Support is broader than one universal contact law. Wreck contact is not guaranteed to follow the same terrain. |
| Raised circuit, banks and water | Separate composed-ground and lake paths | Fixed-wing circuit snapshots can carry a slope normal, but the director ignores it for non-scenery grading. Quad/blimp preparation omits the lake. Helicopter water refusal is explicit and different from omission. |
| Buildings, tables, benches, walls and parked road cars | Authored static proxies in the shared collision world | A rendered mesh is not itself a guarantee of collision coverage. General car-scenery coverage is missing. |
| Parked aircraft | Authored part boxes with a light-airframe impulse response and no target damage profile | They can be hit by supported static-world callers. This does not implement a second moving aircraft, target breakup or bilateral momentum exchange. The shelter/clearance test is now repaired. |
| Trees, foliage, wires and thin poles | Typed boxes/capsules/wires and response policies | Preserve material distinctions. Slow capsule entry, prop-bank rim and quad finite-box witnesses demonstrate different geometric limits; do not solve them with a blanket collision padding increase. |
| Authored standing, seated, pilot or working people | Static capsules with a soft-foliage impulse policy | This is proxy contact, not human biomechanics or injury simulation. Presentation must use actual contact identity. |
| The player's camera-station pilot | Presentation-only pilot-strike detector | No physical pilot collision body exists in this path. Do not advertise it as physically blocking an aircraft. |
| Moving player/AI aircraft or AI/AI aircraft | Independent agents with traffic snapshots and avoidance guidance | Physical aircraft-to-aircraft collision is not implemented. AFC-23 remains a planned capability. A parked-aircraft test does not cover it. |
| Moving user-controlled cars against other vehicles | No general dynamic-body coupling established by the inspected family paths | This needs a separate two-body contact and ownership design, not reuse of a stationary scenery response. |

Sources: [collision world][world], [pilot strike][pilot], [companion manager][companions], [AFC plan][afc], [car course][car-course]. A missing feature is a capability gap unless the product already promises it; the table does not inflate the finding count with duplicate defects.

## Existing findings reconciled with main

The machine-readable [source comparison](evidence/round5/source-status.json) records all 27 historical IDs, 31 unique critical paths, Git blob IDs and relevant function comparisons. Thirteen records have byte-identical critical sources. Thirteen have changed files but unchanged defect-bearing logic. CR-AUD-15 changed substantively and is repaired. Identical source does not imply identical complete runtime context.

| Existing IDs | Current disposition | Fresh evidence or boundary |
|---|---|---|
| 01–02 | Unresolved: lake omission and helicopter nonterminal scenery filtering | Current observation probes pass because they assert that these omissions/filtering exist, with positive controls. Passing these probes does not mean the features work correctly. |
| 03–04 | Unresolved: coasting prop guard and mismatched contact/crossing identity | Current desired assertions fail; the coasting disc remains about 8,090 rpm. |
| 05–10, 12 | Unresolved: datum, COM, split momentum/mass, shape membership, scenery callback, clocks | Current adversarial fixture: 18 checks, 12 desired failures. Several checks characterize one related defect; do not count each assertion as a new bug. |
| 11 | Unresolved: scenery-body provisioning depends on initial crash trigger | Current source inspection; no new full ground-first trajectory through a secondary wall is claimed. |
| 13 | Unresolved: declared/live kerosene duration | All 11 fixed-wing routes admitted; live remaining mass 0.035 kg versus declared 1.28 kg produces report duration 1 s versus the effects object's internal duration field of about 36.57 s. This does not measure rendered flame lifetime. |
| 14 | Unresolved capability gap: cars omit general scenery | Both stock cars: actual road gives no load at tested tyre-stack/building overlap, while an injected box produces contact load. This is a static-overlap characterization, not a driven crash video. |
| **15** | **Repaired** | Main commit `35787fb583f3b654b28381c951783be7a85be0e0`; current parked-aircraft suite passes 45 checks, including 18 shelter posts, six roof strips, no unexpected support and clearance witnesses. |
| 16–20 | Unresolved: delayed rotor frame, quad checkpoint, mixed contact order, pause metadata, quad obstacle aftermath | Fresh retained probes reproduce the five different boundaries; 16 has a clean rerun after hydrating missing fixture textures. |
| 21–24 | Unresolved: quad contact passivity, airship recording identity, slow capsule entry, prop-bank rim | Fresh probes preserve accepted-tick versus direct-fixture distinctions and real recording evidence. |
| 25–27 | Unresolved: finite quad prop geometry, car region assignment, wheel/scenery capability | Fresh probes reproduce two prop-geometry assertions, four car-region assertions and the gear-only obstacle gap. |

Current main also contains fixes that must be preserved: repeated quad effects retain their earlier placement, wreck shadow/handoff behavior changed, and parked-aircraft proxy tests were corrected. These changes do not resolve the unrelated contact and mass-property defects. The original [findings](findings.md), [second](deep-dive-2026-11-18.md), [third](edge-cases-2026-11-18.md) and [fourth](contact-ownership-2026-11-18.md) investigations remain the full per-record descriptions.

### Economics is further along than the old handoff

The earlier external crash-cost handoff is historical context. Current CR-40 supports automatic local assessments for 11 fixed-wing routes, qualified contact observations, bounded summaries/deduplication, reimpact invalidation, package choices, financial groups, ordinary gear contacts and versioned checkpoints/archives. It would be inaccurate to repeat the older claim that only prop strikes are assessed. This does not establish calibrated structural strength, arbitrary damaged flight, internal damage, or supported X-Cell economics. Follow the existing [economics plan][economics] and CR-40 evidence; do not create another permanent roadmap.

## New scoped findings

### CR-AUD-28 — Fixed-wing non-scenery severity uses a flat normal

**Priority:** P1, contact/severity correctness. **Evidence:** executed prescribed-snapshot fixture plus current producer/director source inspection.

[Director `_start`][director] uses down velocity for the normal channel, horizontal velocity for tangential speed and a flat normal for effective mass. Only its scenery branch switches to the snapshot's actual normal. The RC-track producer in [FlightSession][flight] explicitly puts the composed terrain normal in a hull snapshot, so the presentation contract can carry information the director ignores.

The independent fixture uses mass 2 kg, diagonal inertia 1 kg·m², contact arm (1, 0, 0) m, identity attitude and point velocity (7, 0, 7.2) m/s in NED coordinates. Both cases call the real director; inert sinks capture its report without claiming rendered effects.

| Quantity | Flat control | Sloped normal `(1, 0, -1) / sqrt(2)` | Director's sloped report |
|---|---:|---:|---:|
| Closing speed | 7.2 m/s | 0.141421 m/s | Flat-normal channel retained |
| Normal effective mass | 0.666667 kg | 1 kg | 0.666667 kg |
| Normal kinetic term | 17.28 J | 0.01 J | 17.28 J |
| Provisional severity class | C2 | C0 using the same estimator with corrected inputs | C2 |

Eight assertions contain three desired failures and zero checked engine diagnostics. This proves inconsistent grading for the prescribed valid snapshot. It does not prove that an aircraft survives this geometry, that the exact pose exists on the stock circuit, or that C0 is a calibrated structural result. A separate five-site stock-circuit producer attempt was refused by the production query at every site and is retained as **inconclusive**, not as a second reproduction or a new bug.

**Repair gate:** preserve and validate the unit normal, contact point, relative velocity and live mass/inertia from the authoritative producer through severity. Test flat, uphill, downhill, oblique and rotating cases against independent projections. Cover circuit snapshots, swept lake-bank events and the soft-hull fallback separately. That fallback can rebuild a snapshot with a default flat normal; its nonempty `soft_rule` also intentionally floors presentation at C2. Reading `snapshot.normal_ned` alone is therefore insufficient to fix every path, and this finding does not authorize silently removing the policy floor.

### CR-AUD-29 — Quad crash severity reads velocity after settlement

**Priority:** P1, event/presentation correctness. **Evidence:** accepted stock-session ticks plus direct-transition controls.

In the [quad plant][quad-plant], the hard-impact transition settles inward normal velocity before the session emits the crash signal. The [activity][quad-scene] passes `_render_velocity()` from that resulting state to [QuadCrashFx][quad-fx], which derives `power = clamp(speed / 20, 0, 1)` and the C2/C3 presentation choice. The stated impact-speed input has become residual motion after response.

| Accepted case | Previous-boundary maximum candidate-point closing speed | Post-settlement CG speed | Emitted power | Emitted class |
|---|---:|---:|---:|---:|
| Prescribed 19 m/s downward start | 19.082837 m/s | 0.053627 m/s | 0.002681 | C2 |
| Prescribed 28 m/s downward start | 27.744861 m/s | 0.085216 m/s | 0.004261 | C2 |

Both runs prepare the stock graded quad, admit a near-ground frame, accept ticks to a hard-impact terminal and retain the drive cut. They route the real crash callback into the real FX method, with an inert audio receiver capturing the severity dictionary. There is no claim of rendered particles or audible strength, and the previous-boundary speeds are not exact time-of-contact measurements.

The accepted outputs are **different and nonzero**; the probe's loose accepted monotonicity assertion passes. Two additional direct, nonintegrated endpoint controls settle to zero and both emit zero power, causing the one desired failure among 16 assertions. The defect is the input's provenance and loss of incoming contact motion, not a claim that all accepted crashes emit identical severity. C2/C3 and power remain uncalibrated presentation estimates.

**Repair gate:** emit a versioned pre-response contact receipt with point, normal, relative approach and accepted tick identity. Feed that receipt to FX and audio while preserving settled state, drive cut, reset, replay and checkpoint consistency. Test vertical, oblique, rotating, prop and obstacle contacts with a documented response curve and explicit saturation. Do not recover impact energy by guessing from the already settled CG.

### CR-AUD-30 — Helicopter person effects infer a hit from proximity

**Priority:** P2, contact attribution. **Evidence:** executed presentation-path fixture with a prescribed terrain-crash payload.

[HelicopterMain `_lens_crash`][heli-main] passes the installed collision world to the lens for a crash regardless of its authoritative target. [LensStack `strike_from_crash`][lens] asks for nearby scenery within 1.2 m and treats a returned person proxy as the hit. The nearby query uses bounds; it is not a narrow-phase contact receipt.

The real detached presentation caller receives a supplied ground impact at the origin and a spectator capsule centered at north 1.3 m. An independent point-to-capsule calculation gives **1.015009 m clear separation**. The caller nevertheless emits one person event and activates the blood presentation. A farther person does not trigger it; a prescribed person-overlap payload does. The player's pilot station is placed far away to isolate the spectator route. Nine assertions contain one desired failure, with no checked engine errors or warnings.

This establishes false attribution in the presentation path. It does not establish a solver-accepted helicopter trajectory, actual injury, or any physical contact response. The authored person proxy and the separate player-pilot presentation detector must not be conflated.

**Repair gate:** consume the authoritative obstacle ID/type and exact witness from the helicopter event. Ground-only crashes must remain ground-only even beside a spectator. Test a true person hit, a clear near miss, multiple nearby targets, missing/deleted IDs, camera modes, visual effects settings and reset. Keep presentation choices separate from physical collision admission.

## Wreck realism: repair the representation before tuning it

The current [wreck implementation][wreck] explicitly calls its airborne damping physically too strong: linear 1.5 s⁻¹ and angular 2.0 s⁻¹ were retained because earlier lower settings let box colliders tunnel or fail to sleep promptly. At 15 m/s, the documented linear setting corresponds to about 22 m/s² of damping acceleration. CCD is already enabled, so “turn on CCD” is not a sufficient diagnosis. Engine CCD can improve detection for small fast bodies but does not establish that a chosen approximation or timestep is adequate; see the [official RigidBody3D reference](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html).

The current adversarial probe reproduces a 6 kg·m/s change in represented linear momentum during a deliberately asymmetric C3 split with no external step or scatter impulse. It directly measures pending detached mass absent from the visible-body mass sum; source inspection corroborates that those pending bodies are hidden, frozen and noncolliding, so the active collision representation also lacks that mass. The fixture also demonstrates a core box inconsistent with attached/detached membership and a launch reference inconsistent with custom COM. These are controlled property fixtures, not a measurement of real aircraft fracture or angular-momentum closure.

A split must transfer mass, first moment, inertia, collision membership and velocity at the COM together. A useful rigid-body relation is `v_point = v_COM + omega × r`; using a geometric center in one stage and a custom COM in another changes the physical meaning of the assigned velocity. Deferred visual reveal can be supported, but hidden parts must have explicit mass/contact ownership while pending. Minimum masses and count caps need a declared fallback when no feasible allocation exists.

Fixed-wing ground is a flat world boundary and several effects use a fixed field datum. A fragment passing over a slope, raised circuit, table, bank or changed material therefore cannot be assumed to receive the terrain/contact it visually appears to touch. Helicopter wreck uses an impact-local plane, which improves the origin but is still not a full changing-terrain representation. Secondary scenery has two separate failures: the director provisions it only for a scenery-initiated crash, and the wreck callback rejects other static scenery even when bodies exist. Fix both gates.

Clock consistency is another independent concern. Supplying one second as 60 updates of 1/60 s versus ten updates of 0.1 s advances fixed-wing effect age by 1.0 versus 0.5 s because each effects update clips delta to 0.05 s. Wreck elapsed time consumes the full positive delta. This is a direct-update result, not a rendered 10 fps benchmark. Use one pause-aware elapsed-time contract and bounded numerical work; unbounded catch-up would trade a visual discrepancy for a hitch.

After representation fixes, qualify solid grass/asphalt/soil/wood/metal behavior with measured travel, rebound, angular decay and sleep time. Water needs its separately specified entry and aftermath model, not the solid-ground drop/slide oracle. Godot's [PhysicsMaterial reference](https://docs.godotengine.org/en/stable/classes/class_physicsmaterial.html) also makes clear that friction combination and bounce/damping are separate choices. One material sampled at initial impact is not a complete fragment path. Do not treat current provisional coefficients as measured RC-airframe material data.

## Efficiency and optimization

Several existing choices are valuable: 240 Hz authoritative stepping, bounded catch-up, stable spatial bins, cached static geometry, a 24-body wreck pool, finite effect/scenery budgets, sleeping bodies and prepared assets. Preserve those mechanisms while fixing semantics. Increasing every sampling density or spawning a body for every mesh triangle would expand cost without resolving incorrect event ownership.

| Source-level opportunity | Why it matters | Required measurement before changing it |
|---|---|---|
| Helicopter wreck builds nearby scenery synchronously | A cold crash may pay preparation plus up to 160 static proxies in the event path | Cold/warm impact CPU and allocation trace, number prepared, worst frame and time until all required colliders exist. An old comment's timing is not a current measurement. |
| Fixed-wing scenery creation is staged, first 16 then 24 per update | The initial and continuation batches can occur in the same director update, allowing up to 40 creations then; a fast fragment can still arrive before a later collider exists | Earliest fragment arrival versus collider readiness; report cap/deadline omissions. “Eventually built” is insufficient coverage. |
| Car damage visuals rebuild mesh data when a rounded five-channel signature changes | Small ongoing changes can regenerate arrays, vertices and normals repeatedly | Changed-signature frequency, mesh update time/allocations, visual error if updates are coalesced; avoid coarsening physical damage state. |
| Static-world broad phase has bounded bins and a large-query full-scan fallback | Normal queries can be efficient while rare large sweeps become expensive | Candidate counts, fallback frequency, p95/p99 and worst cost in dense/high-speed/rotating cases. Keep deterministic ordering. |
| Secondary-hit observation shares limits and pacing | Four contacts per rigid body and global audio/release pacing can suppress information | Separate physical observation, release decisions and sound rate limits; measure rejected/merged contacts and retain bounded output. |

The current source uses 32 m spatial bins, an 8 MiB budget for one retained serialized cache key/world entry, a 160-body nearby-scenery cap and a 65 m per-axis selection range plus margin. The serialized cache budget does not bound total decoded or temporary world memory. Wreck launch/point/angular/scatter caps also exist. These are workload/stability limits, not realism certificates. A limit can clip, refuse, omit, delay or merely document a domain; telemetry should distinguish those outcomes. See the existing [caps and performance register](caps-and-performance.md) and current [collision world][world], [heli presentation][heli-presentation], [car scene][car-scene] and [damage view][car-damage-view].

**No hardware performance qualification is claimed here.** Headless duration includes loading, import and fixture work and is not frame time. Before performance claims, record actual hardware/OS/backend, build and graphics preset, and follow the repository's resolution policy: 1080p first, except Apple Silicon on Retina displays, which requires native panel pixels. Record output, drawable and internal 3D pixels separately on that Mac path; neither result substitutes for the other target. Measure cold/warm impact, steady debris, dense scenery, repeated crashes, pause/reset and teardown. Capture CPU/GPU p50/p95/p99/worst frame, allocations/peak memory, active contacts/bodies, cap hits and persistent growth. Low/medium/high graphics presets must not change authoritative collision outcomes. Establish baseline distributions first; set budgets from those measurements rather than inventing numerical targets in an audit.

## Implementation order and exit criteria

Use the existing [eight-slice improvement plan](improvement-plan.md), its dated continuations and the owning CR/DR/GP/LENS/AFC plans. The sequence below reconciles those owners with the new findings; it is not a replacement roadmap. Priorities are engineering recommendations, not a statement that every gap is a release blocker.

| Order | Work and existing owner | Minimum exit gate |
|---|---|---|
| 1 — contact/event integrity | CR contact contract; DR quad; helicopter; LENS. Include 03–04, 17–19 and 28–30 | Each accepted contact receipt retains the right tick, obstacle/probe and policy, plus witness, normal and pre-response velocity where available. Preserve timing uncertainty, compare supported intervals and define unresolved/tie behavior. Explicitly mark unknown fields and sampled-time basis; do not invent exact contact values or collapse multiple contacts into one. Preserve checkpoint/log observers, drive cut, reset and replay. Each new counterexample becomes a desired-behavior regression. |
| 2 — supported world and geometry | CR/GP/vehicle paths. Include 01–02, 14, 21, 23–25 and 27 | Explicit family × target capability matrix; accepted contact and clear controls; thin/high-speed/high-angular tests; bounded refusal/cap behavior. Cars need a general-scenery decision before promising parked aircraft/people contact. |
| 3 — coherent wreck split | CR-08/CR-09 and helicopter wreck. Include 05–11 and 16 | Mass, first moment, linear/angular momentum and shape ownership close within declared tolerances; terrain and secondary scenery are available when needed; delayed pieces and repeated releases remain coherent. |
| 4 — presentation time and energy sources | CR effects, DR aftermath and fuel handling. Include 12–13, 20 and 29 | Equal supplied elapsed time under multiple frame partitions; correct pause/reset; live fuel/source receipts; no lost emitter placement fix; consistent delayed releases. |
| 5 — region and structural damage | GP localization, CR physical damage research and CR-40 economics. Include 26 | Region follows the actual contact. Keep cost, appearance, state transition and physical control/mass/aerodynamic changes explicitly distinct. Validate any newly enabled damaged-flight claim. |
| 6 — moving-body collisions | AFC-23 and a shared dynamic-contact design | Relative velocity and two-body effective mass; one event owner; equal/opposite impulse bookkeeping; bounded penetration, no duplicate pair response, reset/replay and traffic-load gates. This is new capability work. |
| 7 — calibration and visual qualification | CR material/structure research and graphics owners | Controlled physical evidence or stated provisional assumptions; model-specific drop/slide/impact cases; multiple viewpoints and speeds; correct debris orientation/contact/shadows. |
| 8 — optimization and release qualification | Existing platform/performance owners | Real target-hardware measurements under the 1080p/native-Retina policy, cold/warm traces, preset-invariant physics, native/reference requirements, replay and lifecycle gates. Optimize the measured bottleneck without weakening coverage silently. |

For moving contacts the relevant velocity is the difference between the two contact-point velocities, including both angular terms. For a static target the single-body normal effective mass is `1 / (1/m + (r × n)^T I^-1 (r × n))`; a moving target adds its inverse-mass and rotational terms. These relations define kinematics and an energy index, not material strength. Strength/fracture calibration still needs construction-specific evidence and uncertainty.

## Delivery and limits

The continuation retains the original investigation, new executable probes, current source identities, exact checked logs/reports, the real recording outputs and unsuccessful attempts. It identifies one repaired historical test and three new scoped presentation/contact defects. It does not change production physics, re-record goldens, certify every vehicle/target pair, validate injury or material strength, prove native/reference parity, or claim a GPU/frame-time improvement. Those boundaries are necessary to make the next implementation work testable and reviewable.

[stack]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/docs/STACK.md
[crash-plan]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/docs/CRASH-DAMAGE-PLAN.md
[catalog]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/app_state/aircraft_catalog.gd
[roster]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/app_state/vehicle_roster.gd
[flight]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/sim/flight_session.gd
[director]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/render/crash/director.gd
[wreck]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/render/crash/wreck.gd
[world]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/scenery/collision_world.gd
[heli-detector]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/physics/rotorcraft/impact_detector.gd
[heli-main]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/helicopter_main.gd
[heli-presentation]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/render/rotor/heli_crash_presentation.gd
[lens]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/render/lens/lens_stack.gd
[pilot]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/render/lens/pilot_strike.gd
[quad-plant]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/physics/multirotor/controlled_plant.gd
[quad-scene]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/vehicles/multirotor/multirotor_scene.gd
[quad-fx]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/vehicles/multirotor/quad_crash_fx.gd
[airship]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/sim/airship/session.gd
[car-course]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/physics/ground_vehicle/airfield_course.gd
[car-scene]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/vehicles/ground/ground_scene.gd
[car-damage-view]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/vehicles/ground/ground_damage_view.gd
[companions]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/app/ai/companions/manager.gd
[afc]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/docs/plans/ai-flight-companions.md
[economics]: https://github.com/bultodepapas/OpenRCsimulator/blob/372053ac9448942e154801e3299cf77669161d08/docs/plans/crash-damage-economics.md
