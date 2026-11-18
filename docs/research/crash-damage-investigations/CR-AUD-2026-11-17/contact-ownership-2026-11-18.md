# Contact geometry and damage localization: fourth investigation

**Date:** 18 November 2026, America/Bogota.

**Application baseline:** [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61).

**Branch:** `audit/collision-damage-2026-11-17`.

**Related records:** [audit index](README.md), [implementation plan](contact-ownership-plan-2026-11-18.md), [verification](contact-ownership-verification-2026-11-18.md).

## Assessment and evidence boundary

This pass adds **three scoped records, CR-AUD-25 through CR-AUD-27**. It examines whether a geometric contact belongs to the part that reacts: a prop disc against finite obstacles, a car's damaged body region, and deployed aircraft wheels against scenery. The three final probes contain **65 assertions: 58 pass and seven fail the proposed behavior assertions**, with zero checked engine errors or warnings. They expose two concrete behavior mismatches and one explicitly scoped capability gap. They do not establish three calibrated physical failures or three complete user-driven reproductions.

| Record | Priority | Observed behavior | Evidence level |
|---|---|---|---|
| CR-AUD-25 | P2 | A modeled prop disc reacts with 12 mm separation; a separate nearer box can suppress an actual modeled-disc overlap | Production pure transition, validated prescribed input/output frames and real collision-world callbacks; no accepted integration tick |
| CR-AUD-26 | P2 | A front-probe-only car impact damages the right or left body channel according to sideways velocity | Accepted session ticks on both stock cars, synthetic road/start, sampled RK-stage admission with byte-exact body endpoint cross-check |
| CR-AUD-27 | P3 | An Avanti's undeformed nose-wheel support-reference path overlaps a low scenery box without changing an 80-tick taxi history | Accepted stock-aircraft session, synthetic obstacle and starting velocity; nominal support point plus separately derived terrain projection |

Priorities are recommended engineering order. P3 for the gear record reflects an uncovered capability and deliberately limited geometry evidence, not an assertion that wheel impacts are unimportant. This brings the package to **27 scoped records**, including the earlier stale-test record and capability gaps. The first three campaigns retain their own counts.

The evidence is retained under [round4](evidence/round4/manifest.json). All final runs complete with exit status 1 because their desired assertions fail. One earlier car draft fails to parse and is excluded from the product totals. No application code, aircraft data, assets, physical coefficients or flight goldens were changed.

## CR-AUD-25 — Hub clearance is insufficient to decide finite prop-disc contact

### Production path

The quad's graded transition calls frame-obstacle handling before prop-obstacle handling. The prop path evaluates obstacle clearance at each spinning hub, estimates a normal by central differences, computes thin-disc support along that normal, and uses `support - clearance` as penetration. Positive penetration can wear the prop, brake its shaft, kick the body and trigger a positional correction. The body frame remains a separate collision shape. See [transition and support](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L940-L974), [prop response](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L1024-L1068), and [normal estimation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/multirotor/controlled_plant.gd#L1193-L1207).

The installed callback returns the minimum clearance among nearby proxies. Its separately evaluated class query also selects the nearest proxy at its query point. Neither scalar carries a stable contact feature through all the normal samples. The probe uses the real world builder, bins and session installation route; it does not replace these with a fabricated distance function. See [world queries](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/multirotor/session.gd#L669-L713).

### Reproduction and controls

The stock graded quad is prescribed a stationary, level airborne body. Only rotor index 1 spins, at 301 rad/s. Its represented disc has radius 64.77 mm and half-thickness 3 mm. The obstacles are bounded 10 mm cubes. The input and returned frames pass the stock validator and reset-frame preparation. No prepared reset is committed; `_graded_impacts` is called directly with the same previous/current body.

For the separated case, the primary cube center is 60 mm sideways and 20 mm above the hub. The cube's nearest vertical face is therefore **12 mm clear of the entire represented disc thickness**. Its frame-obstacle gate is separately clear. The measured hub clearance is 57.008771 mm, but the estimated normal gives a support extent of 63.288921 mm and a false penetration of 6.280149 mm. The transition emits `prop_damage`, reduces health from 1 to **0.9728772473**, reduces shaft speed from 301 to **237.9891679 rad/s**, and changes body position, velocity and angular velocity. This is a finite separated-shape counterexample, not a debate about a small contact tolerance.

For the overlap control, the cube is moved into the disc plane with its center still 60 mm sideways from the hub. The cube center itself is a witness inside the represented disc. That case responds. A second cube, called the decoy, is then added 5.1 mm sideways and 59 mm above the same hub. It is **51 mm vertically clear** of the disc and also clears the separately checked frame gate. However, its hub clearance is 54.000093 mm, slightly less than the contacting cube's 55 mm. Some central-difference samples select the decoy and others the contacting cube. The mixed estimated normal produces a support extent of 39.831562 mm and a negative calculated penetration of −14.168531 mm. The transition now leaves the body, shaft and health unchanged, although the original intersecting cube is still present.

| Case | Independent geometry | Health after | Shaft after, rad/s | Outcome |
|---|---|---:|---:|---|
| Separated, spinning | 12 mm vertical gap | 0.9728772473 | 237.9891679 | False prop response |
| Overlapping, spinning | Cube center inside modeled disc | 0.9578052563 | 202.9743333 | Contact control responds |
| Remote, spinning | Cube moved to 200 mm sideways | 1 | 301 | No response |
| Separated, stopped | Same 12 mm gap | 1 | 0 | No response |
| Decoy alone | 51 mm vertical gap | 1 | 301 | No response |
| Contact plus decoy | Original overlap remains | 1 | 301 | Contact is masked |

The [probe](evidence/round4/probes/probe_quad_disc_box_separation.gd), [observations](evidence/round4/runs/probes/quad-disc-box-separation/observations.json) and [checked report](evidence/round4/runs/probes/quad-disc-box-separation/report.json) retain all six cases and 29 assertions. The two failures are the separated-spinning invariant and the contact-preserved-with-decoy invariant. Both obstacles use the same hard response class; this experiment does not demonstrate mixed-material attribution.

### Cause, consequence and correction

Disc support along a normal is a useful building block. Subtracting one hub distance from that support tests penetration of the corresponding supporting half-space; it does not establish intersection with the finite obstacle itself. Separately, choosing the closest obstacle to a hub is not equivalent to choosing every obstacle intersecting a disc around that hub. Increasing distance-field sampling resolution alone cannot repair that second loss of candidate identity.

This can create or suppress prop wear and alter the returned airframe state before severity tuning becomes relevant. The result is distinct from **CR-AUD-21**, which audits energy once a contact response runs, and **CR-AUD-24**, which concerns the fixed-wing disc/terrain witness. The initial audit already identified curved-obstacle qualification as unfinished; this record adds concrete finite-box counterexamples to that broader limitation.

The proposed correction is a bounded per-proxy query that returns an admitted geometric witness, normal, separation/penetration and material identity together. Use the disc's extent to select candidates, then qualify finite-shape intersection. Preserve deterministic ordering and a defined capacity-exhaustion result. Keep the six present cases as regression controls and add accepted-tick, checkpoint and replay qualification before claiming user-flow coverage. Actual blade phase, swept rotation, arbitrary curved shapes and frequency in normal flight remain unmeasured here.

## CR-AUD-26 — Car body damage follows travel direction instead of contacting region

### Production path

The damage observer chooses a body region from the largest component of the average pre/post body velocity. Forward motion chooses front or rear; dominant sideways motion chooses right or left. That region is then used for a damaging hull-wall episode even though the dynamics exposes per-probe wall loads. See [accepted-tick damage observation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_vehicle/vehicle_damage.gd#L85-L136), [region selection and mutation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_vehicle/vehicle_damage.gd#L504-L517), and [hull-wall geometry and telemetry](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_vehicle/vehicle_dynamics.gd#L863-L902).

The channels have directional consumers: the damage view deforms different mesh regions and uses the front channel for the front bumper's transform. This makes localization observable beyond a single aggregate health number. See [channel consumption](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/vehicles/ground/ground_damage_view.gd#L109-L139) and [regional deformation](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/vehicles/ground/ground_damage_view.gd#L191-L217). This pass reads the output channels; it does not claim a captured rendered dent.

### Reproduction and controls

Both `mt8-bisonte` and `monster-car-2` use their stock loaded vehicle models, real session ticks and production damage observer. The fixture overrides the staged road with flat zero-grip support plus one narrow, frictionless elevated AABB. It seeds a level start 10 m above the datum, with 4 m/s forward velocity and either +8, −8 or 0 m/s sideways velocity. The initial frontmost probe starts 1 mm before the wall. No later state is teleported.

The wall is positioned to admit only probe 0. The probe independently checks that this sphere is uniquely frontmost. For Bisonte the stock inventory names it as the front bumper; the Nitro data does not independently name it that way. The general claim is therefore about the **frontmost hull probe**, not a named bumper on both cars.

Each damaging case must pass front-only telemetry, sphere/AABB geometry, face-normal and ground/wheel-clearance checks at accepted boundaries. A detached instrumented evaluation reconstructs the production RK body policy, including Nitro's midpoint powertrain setup, and requires its body endpoint to be byte-identical to the real accepted endpoint. The sampled RK stages also pass the front-only and ground/wheel-clearance gates. All six damaging cases satisfy admission and first change body damage at accepted tick 1; the active backend is `gdscript_reference`.

| Vehicle | Sideways start, m/s | Front channel | Left channel | Right channel |
|---|---:|---:|---:|---:|
| Bisonte | +8 | 0 | 0 | 0.0303536464 |
| Bisonte | −8 | 0 | 0.0303536464 | 0 |
| Bisonte | 0 | 0.0303536464 | 0 | 0 |
| Monster Car 2 | +8 | 0 | 0 | 0.0315949432 |
| Monster Car 2 | −8 | 0 | 0.0315939686 | 0 |
| Monster Car 2 | 0 | 0.0315944555 | 0 | 0 |

Rear and bottom channels remain zero in these cases. Both no-wall controls retain zero body damage through four accepted ticks. The straight controls select the front as expected. Changing only the sign of dominant lateral motion selects the opposite side channel while the admitted contact remains on the frontmost probe. The [probe](evidence/round4/probes/probe_car_damage_region.gd), [observations](evidence/round4/runs/probes/car-damage-region/observations.json) and [report](evidence/round4/runs/probes/car-damage-region/report.json) retain 22 assertions, including four failed directional-localization assertions.

### Interpretation and correction

This is a concrete mismatch with the proposed invariant that localized hull damage should follow the admitted contact feature. The implementation is an explicit velocity-based gameplay heuristic; the result is not labeled a regression against a previously promised structural solver. The energy magnitudes, material strength and amount of visible deformation are not physically calibrated by this experiment. RK evaluation states are not an independent proof of continuous clearance between those samples.

The fixture's road override leaves the ordinary stock course identity in in-memory recording metadata. That metadata alone cannot reproduce the synthetic road. The script, initial state and retained traces define this reproduction; no standalone `.orfl` replay is claimed. This caveat is part of the fixture provenance, not a newly asserted production recorder defect.

Carry contact ownership into the damage observer instead of inferring location from global travel. A first correction can use validated per-probe loads and an explicit probe-to-region mapping, provided it defines shared/multiple contacts and does not count one episode twice. For a stronger severity model, preserve contact work or impulse with the geometric witness; endpoint load weights alone are not a calibrated energy allocation. Keep the wall/hull duplicate guard and total damage budgets explicit. Qualify the rendered consumer separately after numerical ownership is fixed. This record is independent of **CR-AUD-14**, which concerns general scenery availability for cars; course-wall response is active here.

## CR-AUD-27 — Deployed wheel support does not participate in scenery response

### Production path and contract

Fixed-wing scenery queries pass `aircraft.model.crash_hull` into the shared sweep in both fixed-mass and sampled-mass paths. The deployed wheel force path samples terrain, including its relief and optional track overlay. The current aircraft contract intentionally excludes wheel-support points from duplicate crash-hull points. See [scenery selection](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/sim/flight_session.gd#L3640-L3646), [wheel terrain support](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/app/physics/ground_wheels.gd#L34-L60), and [aircraft contract](https://github.com/bultodepapas/OpenRCsimulator/blob/a7de9b35676d891bc2034cc344b910d9e1ef9c61/docs/AIRCRAFT_CONTRACT.md#L191).

The absence of a wheel-versus-scenery response is therefore recorded as a **capability gap**. Simply copying wheel points into the general crash hull would conflict with their existing support ownership and could turn ordinary landing compression into duplicate hull damage.

### Accepted taxi experiment

The probe prepares the stock Avanti on the default runway, retains ordinary force callbacks and gravity, stops its turbine and seeds 3 m/s taxi velocity with matching wheel rim speed. It clears the stored stiction-anchor flags for that prescribed rolling start. The downlock stays at extension 1. Three sessions differ only in their installed obstacle context: no obstacle, a bounded box in the nominal nose-wheel path, and an elevated box in a crash-hull path as a positive control.

The wheel-path box is 100 mm wide, 80 mm along the path and 100 mm tall in its local coordinates. Much of its height is buried: its top is **28.529266 mm above the datum**, not 100 mm above ground. The nominal nose point starts 260 mm before the near face. During the accepted trajectory it enters the unpadded finite box, reaches a minimum signed box gap of **−35.749410 mm**, and exits the far face. A separate call to production `Scenery.first_hit`, supplied only that nominal point, finds entry at tick 22 and normal speed **2.926463 m/s**. This manually supplied witness is not an event emitted by the session's real gear path.

Across 80 ticks, the box and no-box histories are byte-identical for the recorded body, auxiliary and continuous state, modes, gear extension/compression, contact events and scenery outcomes. Neither faults or crashes. The crash-hull points remain at least **110.293039 mm clear** at the five interpolated samples per interval used by the probe. The elevated positive-control box produces an accepted terminal scenery event at tick 22, using hull point 7. It establishes that the installed scenery hook works for its existing owner.

### Compression caveat and derived witness

The nose-wheel point is an **undeformed support reference**, not a complete finite wheel solid or its compressed physical bottom. At tick 24 its down coordinate is +28.191570 mm; model-reported normal compression is 28.779854 mm. The point law combines compliance and does not locate a physical compressed wheel. Treating the uncompressed point as a literal wheel surface would overstate the test.

To check whether the box is relevant above the actual support terrain, the retained tick-24 position was independently evaluated using the production runway microrelief formula. The height is +0.588559 mm. Its slopes reproduce the recorded compression to an absolute difference of **2.78 × 10⁻¹⁷ m**. The vertical projection of the nominal point onto that terrain lies inside the box, with a signed box gap of **−27.940707 mm**. The box top is 27.940707 mm above the local terrain at that location. The [derivation script](evidence/round4/derive_gear_support.py) and [derived output](evidence/round4/derived/gear-support-projection.json) retain inputs, equations, source hashes and classifications. This is postprocessing of the existing run, not an additional engine test or an exact wheel-volume/closest-surface calculation.

### Consequence and correction

The current owner separation can leave low obstacles without a wheel response while the aircraft hull stays clear. This fixture does not establish every curb height, all stock aircraft, a full tire solid, or a required damage severity. Its source and measured trajectory justify a dedicated wheel-obstacle capability decision.

Define compressed/deployed wheel geometry, contact normals, wheel spin and suspension coupling before enabling obstacle response. Decide how a low curb can roll, scrub, stop or damage a gear component. Use a separate contact owner with shared ordering and duplicate suppression when a body or strut also hits. Preserve ordinary terrain landing behavior and gear-up belly support. The [probe](evidence/round4/probes/probe_fixedwing_gear_scenery.gd), [observations](evidence/round4/runs/probes/fixedwing-gear-scenery/observations.json) and [report](evidence/round4/runs/probes/fixedwing-gear-scenery/report.json) contain 14 assertions and one failed proposed wheel-obstacle response assertion.

## Leads deliberately left unpromoted

The source review also considered the car's wheel-tangent singularity near a vertical attitude, moving-water impact telemetry, and wall/ground energy allocation. The vertical-pose lead lacks an admitted executed reproduction and ordinary-trajectory reachability evidence. The water-speed formula has existing explicit policy/test coverage; an alternative relative-surface interpretation requires a separate contract decision. The car wall-priority path intentionally avoids counting the same body hit twice, and this pass did not isolate a new energy-allocation error.

These remain qualified research questions. They are not additional findings, additional failed tests or proof that a large hidden defect count exists. The next work is the three reviewable implementation slices in the [plan](contact-ownership-plan-2026-11-18.md), with the [verification record](contact-ownership-verification-2026-11-18.md) defining what must be repeated against any changed candidate.
