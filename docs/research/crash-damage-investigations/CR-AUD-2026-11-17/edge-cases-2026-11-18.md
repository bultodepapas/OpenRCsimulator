# Third code investigation: energy, collision identity, and geometric boundaries

**Date:** 18 November 2026, America/Bogota.
**Application baseline:** [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61).
**Starting audit commit:** [`82e715cbe9c8254888c3bc1f7edad739ba4355c9`](https://github.com/bultodepapas/OpenRCsimulator/commit/82e715cbe9c8254888c3bc1f7edad739ba4355c9).
**Branch:** `audit/collision-damage-2026-11-17`.

This continuation adds **CR-AUD-21 through CR-AUD-24** to the [first investigation](findings.md) and [second investigation](deep-dive-2026-11-18.md). The application, assets, and tools trees remain identical to the application baseline. The changes are audit documentation and reproducible diagnostic evidence.

The four final probes contain **73 checks: 67 pass and six fail the proposed desired behavior**, with zero checked engine errors or warnings. These are four scoped counterexamples, not six independent bugs. Four earlier authoring or fixture revisions are retained separately and excluded from that total. See [verification](edge-case-verification-2026-11-18.md), [implementation plan](edge-case-plan-2026-11-18.md), and the [evidence manifest](evidence/round3/manifest.json).

## Findings and confidence

| ID | Finding | Evidence boundary | Recommended priority |
|---|---|---|---|
| CR-AUD-21 | A graded quad propeller contact adds coupled kinetic energy for one tangential velocity direction | Executed production contact function with validated prescribed frames; no accepted integration tick | P2: repair the energy invariant |
| CR-AUD-22 | A paused airship collision-world change leaves an active recording under its old world identity | Public session/recorder API, accepted ticks, three real recording files and production verifier | P2: repair the recording boundary |
| CR-AUD-23 | A submicron hard-capsule entry is skipped; later acceleration crosses the entire isolated trunk without response | Accepted 120-tick, single-point reference fixture with a production trunk proxy | P3: define and harden numerical tolerance policy |
| CR-AUD-24 | The fixed-wing propeller's selected lowest point misses an earlier dry-bank rim penetration | Stock disc and authored lake, prescribed pose, accepted ticks and normal owner guard | P3: extend terrain contact coverage |

Priority is an engineering scheduling recommendation. The two P3 records concern explicitly bounded, currently unqualified geometry domains. Neither establishes a frequent player-facing failure. P2 also does not imply physical severity has been measured.

## CR-AUD-21 — A glancing quad prop strike can add energy

### Cause and supported invariant

The graded contact path applies propeller wear, brakes the shaft, gives the airframe a reaction impulse, then performs obstacle pushout and bounce. `_prop_strike_kick` takes the impulse direction from **relative shaft rotation alone**. It omits the body's translation and rotation when deciding the blade contact's direction of motion. Its comment asserts that the rotor's lost kinetic energy exceeds the airframe kick, but that assertion is not valid for every pre-existing airframe velocity. Read the [kick implementation][quad-kick] and its [obstacle caller][quad-obstacle].

For the admitted electric quad, the inertia includes the locked mass inventory. The energy oracle therefore includes the rotational coupling between body and relative shaft speeds, rather than adding unrelated body and rotor energies. With rotor spin signs \(s_i\), relative speeds \(\Omega_i\), body rates \(\boldsymbol\omega\), and rotor inertias \(I_i\), it evaluates

\[
K = \tfrac12 m\lVert\mathbf v\rVert^2
  + \tfrac12\boldsymbol\omega^T I_L\boldsymbol\omega
  + \tfrac12\sum_i I_i\Omega_i^2
  - \omega_z\sum_i s_i I_i\Omega_i.
\]

This expression follows the [locked-inertia preparation][quad-data] and [coupled angular momentum and shaft equations][quad-coupled]. The sign is consistent with the admitted body-minus-Z rotor axis. The before/after calculation, including the cross term, was independently reviewed against those equations.

### Reproduction and controls

The [executed probe](evidence/round3/probes/probe_quad_prop_strike_energy.gd) prepares the stock electric quad in graded mode, disarmed and far above the ground. It validates each candidate body/continuous frame through the model and reset preparation. A stationary diagonal half-space intersects only the selected propeller disc: the prescribed bite is **20 mm**, while the frame box remains **44.77 mm clear**. Only rotor 0 spins, at **301 rad/s**, just above the configured contact threshold. Body approach normal to the wall is **0.1 m/s**.

The test directly calls the real `_graded_impacts` function. It does not advance the integrator, perform motor work, or commit the reset candidate. The same current body is supplied as the previous body, so this is an already-overlapping endpoint fixture. The half-space is synthetic; the prepared vehicle parameters and contact law are production code.

| Case | Tangential body speed relative to the kick | Coupled kinetic-energy change |
|---|---:|---:|
| Motion along the kick | +25 m/s | **+0.166277417 J** |
| Zero tangential motion | 0 m/s | −0.240353739 J |
| Motion against the kick | −25 m/s | −0.646984896 J |
| Stopped propeller | +25 m/s | 0 J |
| No wall | +25 m/s | 0 J |

In the positive case, total kinetic energy rises from **170.632328500 J to 170.798605917 J**, while shaft speed falls from **301 to 150.5 rad/s**. The final body–shaft cross term is **−0.000847177 J** and is included in the result. One nonterminal prop-damage event occurs. The source, charge, terminal-energy and pack-loss fields used by the check do not supply extra work; horizontal pushout does not change altitude. No elastic reservoir is modeled in this transition. The [measurements and assertions](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/quad-prop-strike-energy/observations.json) retain the component energies and all five cases.

The increase is about **0.097% of the fixture's initial total kinetic energy**. It violates the transition's stated passive-energy behavior, but it is not evidence of a large instability, repeated gain, or a common flown maneuver. The log also contains a contact-velocity/impulse dot product; that diagnostic is **not** used as exact collision work because it uses a net body impulse and does not include shaft torque work.

### Consequence, coverage gap, and correction

A blade moving through a stationary environment must be evaluated using the velocity of its actual contact point, including airframe translation, body rotation and shaft rotation. Braking a relative shaft by a fixed fraction and applying a separately computed hub impulse does not by itself enforce passivity of that coupled system. A restitution cap on the later body bounce cannot correct every earlier energy addition.

The existing [graded-crash energy check][quad-existing-test] exercises a near-stationary input; it does not exclude this fast tangential case. This audit's desired passivity assertion fails while its geometric, validity and negative controls pass: **16 checks, one failure**.

The proposed repair should derive a compatible body-and-shaft contact impulse or conservatively limit/refuse an unsupported contact. It must account for the same inertia and shaft convention used by the electric plant and evaluate the complete post-contact result. Accepted-tick, multi-rotor, small-bite, ground-contact and replay qualification remain necessary before changing the production law. This result is distinct from CR-AUD-20's terminal wall continuation: here the tested event is a nonterminal prop contact and the defect is the energy bookkeeping of its response.

## CR-AUD-22 — A paused world change invalidates an airship recording

### Boundary mismatch

`AirshipSession.set_collision_world` is documented as installing the inventory before reset and refusing a change while a flight is underway. Its guard rejects the operation only when the tick is positive **and the session is unpaused**. Consequently, a paused session can replace the collision world without emitting `resetting` or establishing a new recording boundary. See [the setter and accepted-tick crash observation][airship-session].

The [recorder header][airship-recorder] captures the collision identity once at recording start. Replay rebuilds the world from that header and compares the final crash outcome as well as body/continuous rows. The replacement world is not a replayable event in this format. See [reconstruction and terminal verification][airship-replay].

### Accepted sequence and real files

The probe uses the actual default field inventory, its flagpole capsule, the stock airship, the public release options already used by `test_airship_session.gd`, and the production recorder. The deliberate release is inside that pole's collision volume. The test begins without an installed scenery world so that the first accepted tick is clear; it does not fabricate a damaged checkpoint or edit a recording.

The changed-world sequence is:

1. Prepare the airship with an empty scenery world and start a recording whose collision identity is empty.
2. Accept tick 1, then pause through the session API.
3. Install the stock world through `set_collision_world`. The call succeeds, the identity changes, `resetting` is not emitted, and the original writer remains open.
4. Resume and accept tick 2. The real obstacle observation records `Obstacle strike: fixture (hard_terminal)` and pauses the session.
5. Stop the writer cleanly and inspect and verify the resulting complete `.orfl` file.

| Recording | World behavior | Production verification |
|---|---|---|
| [Unchanged-world control](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/recordings/unchanged-world.orfl) | Empty world remains empty across pause/resume | Complete; exact replay |
| [Pre-record-world control](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/recordings/pre-record-world.orfl) | Stock world installed before recording; real pole crash at tick 1 | Complete; exact replay |
| [Changed-world case](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/recordings/changed-world.orfl) | Empty header world; stock world installed while paused; real crash at tick 2 | Complete; terminal replay mismatch |

The failing file retains its two accepted rows and the crash event. Its verifier reports `identity_match=true` and `solver_changed=false`, then correctly returns `ok=false`, `exact=false`, and **“Replay terminal outcome differs from the recording.”** The recorded crash is nonempty; the replayed crash is empty. `first_mismatch_tick=-1` is not a successful replay: the discrepancy is in terminal outcome, outside the state-row mismatch locator. Full [observations](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/airship-collision-recording/observations.json) and [probe source](evidence/round3/probes/probe_airship_collision_recording.gd) are retained.

### Scope and repair

This is a reproducible **public API and recorder consistency defect**. The verifier detects the inconsistency; it does not silently certify the file. The [current airship activity][airship-startup] installs its world at startup, so this test does not establish a player-facing midflight world-switch flow. Nor does it establish corruption of physical state. The artificially placed initial pose is disclosed because it makes the identity transition observable in two ticks.

The recording invariant must refuse a changed world while a writer is active, regardless of tick, or make every allowed identity change close or rebind that recording atomically before a tick under the new identity. This includes a recording started at tick zero; refusing changes only after accepted ticks would leave that header-staleness path open. Freezing the world after accepted ticks can be an additional session policy. A more ambitious design could serialize and replay explicit world transitions, but it needs a versioned recording contract. An unchanged-world setter should remain an idempotent no-op where supported. Rejection must leave the world, recorder and simulation unchanged; an accepted change must make its recording boundary atomic.

The final probe has **29 checks, two desired failures**: boundary closure/refusal and exact replay of the resulting file. Its two successful controls show that neither the pole fixture nor the unchanged recorder path explains the failure. This differs from CR-AUD-17's checkpoint observer order and CR-AUD-19's incomplete crash-pause metadata.

## CR-AUD-23 — A tiny hard-capsule entry becomes an undetected through-passage

### Numerical mechanism

The [capsule segment solver][capsule-solver] computes `horizontal_a = dx*dx + dy*dy` and processes cylinder roots only when that value exceeds `GEOMETRY_EPSILON`, currently `1e-12`. Its sphere-cap helper likewise returns when squared segment length is at or below that threshold. In this straight horizontal fixture, a segment shorter than **1 micrometre** takes the degenerate branch even when its endpoints straddle the capsule boundary.

This happens before [response classification][scenery-response], where `hard_terminal` is specifically exempt from the `0.05 m/s` soft-response cutoff. It is therefore a different cause from the slow soft-box lead kept unpromoted in the second investigation. No arbitrary-speed or arbitrary-scale collision guarantee is inferred from that exemption.

The production [tree builder][tree-builder] supplies a hard-terminal trunk capsule with radius **0.18 m**. The test retains only that trunk, with proper collision bins and damage metadata. The [reference-session fixture](evidence/round3/probes/probe_slow_capsule_entry.gd) uses a single datum hull point, zero gravity and a body-only load callback. Foliage, gear, propeller and aerodynamic loads are deliberately omitted. This isolates the geometric entry query and its subsequent session behavior.

### Measured crossing and continuation

| Quantity | Observed value |
|---|---:|
| Integration rate | 240 Hz |
| First-tick approach speed | 0.0001 m/s = 0.1 mm/s |
| Initial actual capsule clearance | 0.000000100 m = 0.1 µm |
| First-tick displacement | approximately 0.416667 µm |
| Squared displacement | `1.73611111113e-13 m²` |
| Actual capsule gap after tick 1 | `−3.16666666667e-7 m` |
| Padded entry fraction | approximately 0.2376 |
| Later prescribed acceleration | 4 m/s², starting after tick 1 |
| First tick beyond the far face | 103, about 0.42917 s |
| Final speed at tick 120 | 1.983433333 m/s |

The first accepted candidate crosses both the actual capsule and its **1 nm** padded boundary. The trunk passes the swept-bin and padded-AABB gates, but the direct capsule test and final scenery query return no hit. On the next tick, the probe begins applying a finite constant body force; it never teleports the body after the initial reset.

The world and no-world runs then have **byte-identical 120-tick recorded histories**, including body state, modes, pause state, crash trigger and contact observations. Both cross the far face of the 0.36 m diameter trunk on tick 103. The speed increase does not recover the missed event: subsequent segments start inside the volume until the far-face exit, while the solver searches for inward entry roots. Source inspection finds no independent persistent scenery-overlap recovery in this [fixed-wing filter and owner path][fixedwing-filter].

A faster **0.01 m/s** outside entry hits the same trunk and terminates the accepted first tick, even though that speed is still below the soft-response cutoff. Outward and side-clear controls accept without a contact. These controls distinguish a real installed scenery path from a broken test world or a stale event field. The retained [measurements](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/slow-capsule-entry/observations.json) contain all six cases. Result: **12 checks, two desired failures**.

### Meaning and bounded recommendation

The observed passage is large compared with the missed initial penetration, but the trigger is intentionally extreme. The fixture starts 0.1 µm outside a synthetic isolated proxy and prescribes a later acceleration. It does not show a stock aircraft flying through a stock tree, establish frequency, qualify native-backend behavior, or prove that a catastrophic crash at vanishing speed is physically desirable.

The [player guide][collision-qualification] describes collision proxies as approximate and collision accuracy as open; the [landscape plan][scenery-qualification] calls static contacts gameplay estimates rather than physical calibration. The new evidence identifies a concrete threshold and accepted trajectory within that unqualified domain. Assign **low engineering priority** until the scale and slow-contact policy is decided. If tiny entries are intentionally tolerated, growing penetration still needs an explicit recovery, refusal or diagnostic rule before a fast through-passage. If every inward hard entry remains terminal, the numerical solver must honor that policy around its chosen bound. Simply removing the epsilon could expose other numerical failures and is not a supported repair.

## CR-AUD-24 — A powered propeller rim overlaps a dry bank while the selected point remains clear

### Geometric mismatch

`HullContact.prop_disc_depth` builds the disc from aircraft propulsion data, chooses its **globally lowest point in NED**, and then samples terrain or water only at that point. That is a valid flat-ground construction. On a sloped bank, the rim point with maximum penetration relative to terrain can be somewhere else. See [disc construction and depth][prop-depth]. The separate lake sweep [skips bank events for non-hull probes][lake-bank-filter], and its prop probe [uses the same lowest-point construction][lake-prop-point].

The surviving soft-hull session calls `_check_prop_strike`; that guard requires a running source, sufficient rpm and positive reported disc depth. See [guard order][fixedwing-owner] and [the strike decision][prop-strike]. This case keeps the engine running and is independent of CR-AUD-03's coasting, source-off exclusion.

### Accepted-tick witness

The probe uses the stock default fixed-wing geometry, **0.1524 m propeller radius**, authored lake bank near N=110 m, E=173 m, ordinary stage loads, and the existing soft-hull owner guard. The prescribed pose is **yaw 0°, pitch −80°, roll approximately +53.1267°**, with an initial downward speed of 0.1 m/s. This is a controlled steep nose-down, banked start, not a flown maneuver. The existing split shaft route is retained; the probe records that route and does not claim a coupled-shaft run.

The same disc-frame rim point, phase **5.105088062 rad**, moves from clear to penetrating over two accepted ticks:

| Measurement | Tick 0 | Tick 2, 8.333 ms |
|---|---:|---:|
| That rim point's signed depth relative to the bank | −1.034204 mm | **+0.242395 mm** |
| Production-selected point's reported depth | −2.098924 mm | **−0.822297 mm** |
| Maximum sampled crash-hull depth | −21.355250 mm | −20.078381 mm |
| Reported propeller speed | 5,159.107 rpm | 5,159.107 rpm |
| Engine running / prop-strike latch | true / false | **true / false** |

The tick-2 witness remains after the normal owner guard is called. There is no simulation fault, terminal crash or gear collapse. All sampled rim points lie on dry bank, so this is not a wave or water-surface inference. The witness's actual point and terrain height are retained in [the observations](https://github.com/bultodepapas/OpenRCsimulator/blob/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17/evidence/round3/runs/probes/prop-bank-rim/observations.json).

The probe samples **128 rim positions**. A positively penetrating point is sufficient to prove overlap of the model's disc with its modeled terrain. Those samples do **not** establish a global maximum or certify that every rim/interior point was initially clear. The stronger supported transition is that this particular, named disc-model witness changes from clear to penetrating. It is not a measured blade-phase or material-fracture event.

The flat-ground control strikes at accepted tick 10 and cuts the engine. A deeper bank control makes the production-selected point positive and also cuts the engine. The final [probe](evidence/round3/probes/probe_prop_bank_rim.gd) completes **16 checks with one desired failure**. Earlier versions used a legacy hard guard, an initially overlapping rim, or mislabeled roll as heading; those authoring limitations are retained and excluded from final counts.

### Scope and correction

This demonstrates a **narrow contact-coverage gap at the observed boundary**, with a 0.242 mm geometric witness at the tested boundary. The probe stops there. It does not establish permanent immunity, escape through the bank, a visibly incorrect rendered frame, or the time of any later strike. The [original prop-strike design](../E3d2/README.md) describes a turning disc reaching the field, while its algorithm description uses the flat lowest-point approximation. Existing [flat prop tests][prop-existing-test] and [wet lake check][lake-existing-test] do not qualify the dry-bank case.

The repair should first define the contact geometry and required tolerance for a disc against varying terrain. A local terrain-plane support calculation may address smooth slopes, but curvature, shore transitions and waves need a bounded extension or explicit refusal. Replacing one global direction with one local normal does not by itself prove complete curved-surface coverage. Share the resulting query between the strike guard and lake probe, preserve flat-ground behavior, and keep the geometry decision separate from fracture and impulse calibration.

## What this pass does not add to the defect count

The car simultaneous wall/ground damage lead remains unproven. The branch giving wall work priority is an intentional double-count safeguard, and the shared energy residual cannot assign separate causal work to simultaneous contacts without a discriminating fixture. No new car defect is claimed from that source pattern.

The earlier soft-box overlap question remains a policy/qualification lead. CR-AUD-23 adds different evidence about hard-capsule geometry; it does not retroactively turn the earlier hypothesis into a proven defect. Likewise, the quad energy result does not certify a flight trajectory, and the airship result does not invent a UI path absent from the current activity.

The retained probe-authoring failures are part of verification quality. They are not application failures. The branch now contains **24 scoped records across three investigations**, including earlier capability gaps and a stale test assertion; it should never be advertised as 24 independently demonstrated end-to-end flight bugs.

[quad-kick]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L1161-L1190
[quad-obstacle]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L1025-L1068
[quad-data]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor_data.gd#L100-L131
[quad-coupled]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L449-L460
[quad-existing-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/tests/test_mr_graded_crashes.gd#L155-L194
[airship-session]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/airship/session.gd#L281-L312
[airship-recorder]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/airship/flight_log.gd#L45-L89
[airship-replay]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/airship/flight_log.gd#L303-L351
[capsule-solver]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/scenery_collision.gd#L523-L580
[scenery-response]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/scenery_collision.gd#L228-L249
[tree-builder]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/scenery/collision_world.gd#L533-L538
[fixedwing-filter]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/flight_session.gd#L3477-L3532
[prop-depth]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/hull_contact.gd#L93-L131
[lake-bank-filter]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/lake_collision.gd#L184-L207
[lake-prop-point]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/lake_collision.gd#L486-L501
[fixedwing-owner]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/flight_session.gd#L3141-L3173
[prop-strike]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/flight_session.gd#L3320-L3336
[prop-existing-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/tests/test_prop_strike.gd#L35-L43
[lake-existing-test]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/tests/test_lake_collision.gd#L216-L224

[airship-startup]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/vehicles/airship/airship_scene.gd#L100-L112
[collision-qualification]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/docs/FIRST-LAUNCH.md#L290
[scenery-qualification]: https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/docs/LANDSCAPE-PLAN.md#L3-L7
