# Nonfatal contact: near misses, brushing, scraping and brief water entry

**Review date:** 19 November 2026, America/Bogota. **Application source:** [`d736ee8a2eab0b59b0fa2c561a1eef07f5fae396`](https://github.com/bultodepapas/OpenRCsimulator/commit/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396). **Audit branch:** `audit/collision-damage-2026-11-17`.

This continuation prioritizes the owner's intermediate outcomes: a close pass that does not touch, a wingtip brush that releases, a sustained scrape, a small propeller contact and a brief water touch. It integrates source findings and executable probes into the existing [crash execution plan §9](../../../plans/crash-realism.md#9-recoverable-contact-and-near-misses--19-november-2026), [crash parent](../../../CRASH-DAMAGE-PLAN.md) and [ground physics plan](../../../plans/advanced-ground-flight-physics.md). It does not change production force laws, enable a new water response or claim calibrated damaged flight.

## Assessment

The simulator already has useful intermediate contact behavior. The main limitation is that its geometry, timing and response policies are not yet consistent across all surfaces and components. A supported interactive fixed-wing tip/belly scrape can continue and produce scuffs and repeated sound. A powered ground prop strike can stop the engine without terminating the whole flight. A selected fixed-wing water contact, including tangency, is terminal. Hard scenery and raised track dirt also follow policies different from the soft flat-field path. These differences explain why simply changing a crash threshold would not meet the requested realism goal. [S1–S6]

The recommended order is to establish **whether and where contact occurred**, preserve the correct elapsed time and local motion, then measure the accepted contact episode. Component damage and recovery follow from that evidence and the component's capabilities. A mark, a cost estimate, a low severity class and a nonterminal tick each describe different things.

This pass adds four separately scoped records, **CR-AUD-31 through CR-AUD-34**. Two are geometric/time counterexamples or approximations, one is an explicit water capability policy and one is a moving-interface diagnostic limitation. The earlier 30 records remain dated evidence; this focused pass does not revalidate their complete register at the new source revision. The current deterministic collision tie-order repair is preserved and its existing control passes.

## 1. What already works, and what it proves

| Foundation at the reviewed source | Evidence and limit |
| --- | --- |
| E3d1 spring/damper/friction hull contact | Supported interactive fixed-wing brushes and slides can continue. New normal-impact energy and excessive depth can still terminate. The coefficients and thresholds are estimates, not measured airframe strength. |
| GP-07 generated Stik hull and per-surface friction | Existing airframe checks cover generated contact geometry, local surface friction, tail scraping, inverted settling and exact replay. [GP-07b](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/research/ground-physics/GP-07/README.md) checked 6,000 sampled attitudes against limits of 12 mm drawn-airframe sink on flat ground with hull/wheels and 15 mm at a flat obstacle with hull alone, excluding propeller blades. These are sampled coverage checks, not continuous-orientation or 1 mm whole-mesh clearance guarantees. |
| GP-19 accepted hull-friction observations | Same force-owner diagnostics provide instantaneous tangent force, slip and power at accepted endpoints. They preserve physical state and feed bounded scrape grains. They do not integrate duration, friction work, heat or wear. |
| Live soft-contact marks/scuffs/audio | The current director preserves contact feedback while flight continues. Its legacy sliding audio is suppressed when accepted hull capture supplies grains, preventing duplicate cues. Post-terminal wreck continuity is separate work. |
| E3d2 ground prop strike | The existing source-on, RPM-gated positive-depth guard produces a nonterminal strike and engine stop. Partial nicks, strength, phase and general scenery coverage are not qualified by that guard. |
| GP-14 and CR-40 | Accepted survivable-incident/accounting boundaries exist separately from terminal pause. Financial rules do not certify physical failure. Intended support, unknown evidence and repeated incidents need their existing typed semantics preserved. |

The refreshed existing controls total **652 passing checks**. Four new probes contain **97 checks, 95 passes and two retained desired-behavior failures**, both concerning conservative scenery padding in two related component fixtures. There are **749 qualifying checks overall, with zero checked engine errors or warnings in those executions**. Three resource-incomplete script attempts are explicitly excluded; two of them print zero failed assertions despite engine errors. See the [verification record](nonfatal-contact-verification-2026-11-19.md), not just a process exit or summary line.

The existing audio record includes a later source-pinned native Stik scrape capture. This pass uses Dummy audio and does not refresh native output, listening, combined Master headroom or target-hardware frame budgets. [S6, S9]

## 2. How much can an aircraft graze?

There is no defensible universal limit in millimetres, metres of scraping or total airspeed. The useful question is: **which physical feature met which surface, with what relative motion, loading and duration, and what happened after release?**

For a rigid point, translational velocity and `omega × r` both contribute. A wingtip can descend while the CG rises, or catch the ground because of roll even during a level CG trajectory. The normal component describes approach into the surface; tangential motion describes sliding. A moving target has its own contact velocity. A spinning prop/rotor additionally has local blade motion. Contact impulse, lever arm, material, local structure and later contacts determine whether the result is a scuff, drag, yaw/roll, snag, fracture or a recoverable deflection. [S1–S4; equations below are mechanics, not fitted thresholds]

### 300 km/h and a 1 mm gap

At **300 km/h = 83.3333 m/s**, the reference point travels **0.347222 m in a 240 Hz tick**. A point moving parallel to an ideal static plane with a continuously positive 1 mm physical gap has no contact. Total forward speed alone must not create impact damage. A single clear endpoint or rendered frame cannot establish clearance of every point throughout the interval.

For constant translation and no body rotation, with angle `alpha` measured **to the surface**, `v_n = v sin(alpha)` and `E_n / m_eff = 0.5 v_n²`:

| Angle to the surface | Normal speed, m/s | Normal incident energy, J/kg of effective mass | Time to close a 1 mm normal gap |
| ---: | ---: | ---: | ---: |
| 0° | 0 | 0 | Does not close under these assumptions |
| 0.1° | 0.1454 | 0.0106 | 6.875 ms |
| 0.5° | 0.7272 | 0.2644 | 1.375 ms |
| 1° | 1.4544 | 1.0576 | 0.688 ms |
| 2° | 2.9083 | 4.2291 | 0.344 ms |
| 5° | 7.2630 | 26.3754 | 0.138 ms |
| 90° | 83.3333 | 3472.2222 | 0.012 ms |

These are reproducible [arithmetic illustrations](evidence/round6/contact-scales.json), with their [calculation](evidence/round6/calculate_contact_scales.py). Multiplying the energy column by `m_eff / aircraft_mass` gives the corresponding aircraft-mass-normalized term, before any separately defined transfer/durability policy. None of the rows is a safe touch limit or a qualified speed for a particular aircraft. High tangential speed can still drive severe local rubbing, snag torque or subsequent collision.

The flat-plane component probe confirms both the 300 km/h, 1 mm-clear case and zero-depth tangency produce no soft hull load or terminal decision. Its deliberately penetrating point, moving down at **0.264 m/s**, develops opposing friction and upward load and remains below the configured terminal threshold. This is an actual call to the production law with prescribed states, **not an accepted stock-aircraft approach or recovery**. [P1]

### Soil, grass and the drawn airplane are different geometries

Current wheel support has deterministic estimated load-bearing relief amplitudes of **1 mm on runway, 4 mm on mown and 7 mm on rough ground**. The source explicitly says this is soil relief, not grass-blade height. Ordinary dry soft-hull/ground-prop sampling uses the flat datum; lake-covered branches use their own surface/bed queries. Near grass is artistic geometry without simulation collision, including visual wind motion. [S1, S7, S8]

Consequently, “1 mm above the grass” needs a declared reference: above soil, above a modeled canopy, above the blade mesh, or above a conservative collision proxy. These are not interchangeable. If physical grass brushing is introduced, GP-10 should own an independent authored canopy/compliance/material envelope. A true near miss clears that represented physical envelope plus the admitted uncertainty; unresolved near-boundary geometry must not silently become either precise clearance or an impact. Blade density and graphics quality must not affect the force law. A sparse point cloud or a hull generated to a centimetre-scale tolerance cannot certify a millimetre of actual skin clearance simply because its probes are clear.

## 3. New bounded records

### CR-AUD-31 — Conservative rotational padding can become a false contact

**Type:** direct geometry/admission counterexample. **Priority:** first contact-truth work. **Source:** scenery subdivision/padding and `_event_at` in [S3]. **Evidence:** [P1] and the stronger outside-CG fixture [P2].

The scenery query subdivides rotation, expands the chord by a rotational bound, and can then construct an event at the padded entry fraction. It recomputes the actual point but does not require that point to contact the uninflated proxy. A bound intended to avoid missing candidates can therefore become an actual impact event.

The stronger witness uses one point `(0, 1, 0.1)` m, roll from **−0.9995° to +0.9995°**, a wide box with top `Down=0`, prescribed endpoint point clearances **0.300 mm → 0.050 mm**, and north speed 83.3333 m/s. The CG stays above the box. An analytic bound over the entire shortest-nlerp pose interval proves at least **0.0334576 mm positive point clearance**. Nonetheless, `first_hit` returns a nonterminal `impulse_pending` event at fraction **0.588350195403**, when its exported actual point is **0.1379451 mm above the uninflated top**. Reported normal approach is **0.0590291 m/s**, above the current soft-response floor. Farther-clear and unrotated-close controls return no event; an actually penetrating endpoint control returns an event. [P2]

For reproducibility, let `a=0.9995°`, `t=tan(a/2)`, `u=2f−1`, and `phi=2 atan(u t)`. For the vertical arm `sin(phi)+0.1 cos(phi)`, its deviation from the endpoint chord is

`2 t² (1−u²) (0.1+u t) / ((1+u²t²)(1+t²))`.

This is at most **0.000016542410 m**, less than the minimum endpoint gap of 0.000050 m. The proof is interval-wide; dense pose samples are not its sole oracle. The script separately checks the production velocity-interpolation convention without calling it the exact derivative of the interpolated pose.

The first witness [P1] deliberately has its synthetic CG inside the box and is weaker as a physical configuration. It remains retained and clearly labeled. Neither witness proves a stock aircraft has a false crash, that all nearby geometry is clear, or that an accepted response impulse was applied. They prove an erroneous contact candidate can leave this component with a fully clear modeled point.

**Correction/gate:** retain conservative broad-phase coverage, refine physical narrow-phase/time-of-contact before commit, preserve true-positive/tunneling controls and current tie ordering, and qualify an accepted whole-aircraft near-miss next. Removing padding globally is not a justified fix.

### CR-AUD-32 — A nonterminal scenery response can discard the remaining tick motion

**Type:** accepted-step characterization of an explicit integration approximation. **Priority:** time-consistent continuation. **Source:** contact-state return in the session and scenery response/separation [S2, S3]. **Evidence:** [P3].

A synthetic body has one point at its CG, no applied force, gravity or rotation, no wheel/prop contact coverage, north speed **83.3333 m/s** and down speed **0.24 m/s**. It starts 0.4 mm above a soft box top at `Down=−10 m`. Both the no-world control and world case execute the actual `Simulation.step()` and accept tick 1 at **0.004166666667 s**.

The no-world case advances **0.347222222222 m north**. The impact is nonterminal at fraction **0.399999000001**, applies the declared restitution and **0.01 m outward separation**, reverses down speed to −0.084 m/s and preserves north velocity. The accepted north position is **0.138888541667 m**, the contact-time position. Continuing that same instantaneous response through its remaining **0.002500004167 s** would instead reach **0.347222222222 m**: a **0.208333680555 m** difference in this force-free case. [P3]

This does not establish a universal 21 cm loss, a normal stock flight, or calibrated foliage response. The source already documents the approximation. It is newly quantified here because losing time/distance is especially visible in high-speed grazing and can vary with the contact fraction.

**Correction/gate:** bounded event-driven continuation or another explicitly time-consistent method; requery possible secondary contacts; preserve accepted resource/mass/shaft state, arbitration and replay identity. Include true no-contact, early/late contact and repeated-contact controls. Treat separation as numerical stabilization, not a physical deformation measurement.

### CR-AUD-33 — Brief fixed-wing water contact has no nonterminal response branch

**Type:** explicit capability/policy gap, not a newly introduced regression. **Priority:** staged transient-water model. **Source:** selected lake events and session terminal handling [S2, S4]. **Evidence:** accepted synthetic-point cases in [P4] and the existing lake control.

At both **10 m/s and 83.3333 m/s** tangential speed, a one-point synthetic aircraft with zero applied forces/gravity accepts a clear 1 mm-above-water tick without an event. Exact calm-water tangency and an initial **0.01 mm immersion**, with **zero point normal speed**, each produce a selected water event, terminal crash state, engine stop and pause. The initial immersion case is a controlled overlap, not a tiny-entry approach trajectory. [P4]

This behavior is deliberate in current tests and follows through the real accepted-step path. It establishes the requested intermediate water behavior is absent. It does **not** show all shallow real contacts should recover or that the same continuation rule should cover wingtip, prop, wheel and fuselage.

**Correction/gate:** define a versioned transient contact capability with wetted geometry, relative motion, duration, bounded hydrodynamic response and declared recovery conditions. Keep a severe-entry terminal control. Integrate the event schema, reset/replay, incident/cost evidence and local wet presentation; terminal aftermath currently hides/replaces the aircraft and cannot serve as a skim cue. Floats, boats and sustained buoyancy/planing require their separate support model.

### CR-AUD-34 — Reported water normal speed omits interface motion

**Type:** source-confirmed kinematic/diagnostic limitation, with a direct query witness. **Priority:** prerequisite for water severity/response. **Source:** [S4, S10]. **Evidence:** moving-wave portion of [P4].

The detector samples a time-varying wave, but event normal speed is computed from the aircraft point velocity projected onto the instantaneous normal. It does not include the interface's motion. A prescribed sine wave with **0.03 m amplitude, 12 m wavelength and 4 s period** rises across a stationary point that begins 0.1 mm above the surface. The direct query returns a terminal event at **0.0021240234375 s**, exporting **0 m/s normal speed**. The independently differentiated surface gives **0.0471178150 m/s normal closing of the interface gap**. Its calm-water control remains clear. [P4]

This is not a measured fluid impact or a fluid-particle velocity calculation. Surface-height motion does not uniquely define the fluid velocity field. Current policy is terminal independently of this reported speed, so the probe does not show a missed water event; it shows a quantity that cannot yet grade moving-water contact as a static-ground normal speed.

**Correction/gate:** define the derivative of the moving-interface gap, separately declare any current/fluid velocity assumption, and test rising, receding and translating cases. Include wave/boundary work in energy accounting; a moving surface can transfer energy to a stationary body.

## 4. Propeller brushing needs its own model

The direct prop-guard portion of [P4] isolates the disc from hull and gear and injects pose/RPM. At 1 mm penetration it distinguishes **299.999 rpm: no strike** from **300 rpm: strike**. At **5000 rpm**, a **1 micrometre positive depth** triggers the same engine-stop response at 10 and 83.3333 m/s forward speed. A 1 mm-clear control remains unstruck. A source-off, 5000-rpm injected control is also unstruck, consistent with the source guard behind earlier **CR-AUD-03**. These direct calls do not reproduce a coast trajectory or a blade at a known phase.

The guard's exported `velocity_ned` is reference translation. With the probe's deliberately injected body pitch rate, the independently calculated rigid point velocity differs by about **(+0.3052, 0, −0.8053) m/s**, before any blade-spin contribution. This does not claim the existing field was promised to mean blade velocity; it identifies why a future severity model cannot use it as one. [S2, P4]

For scale only, radius 0.15 m at 5000 rpm gives rotational tip-speed magnitude **78.54 m/s**; even 300 rpm gives **4.71 m/s**. Vector direction, translation and body rotation still matter. APC's manufacturer discussion distinguishes centrifugal, aerodynamic, torsional and vibration loads, and their uncertainties; it supplies no universal safe nick depth for these simulator models. [R1]

Preserve the current explicit conservative policy until a replacement is qualified. Resolve the source-off spin observation and the earlier variable-terrain rim gap **CR-AUD-24** first. Then distinguish vegetation flexure, hard ground, a fence/edge and water, actual shaft state and strike radius, and the limits of a disc envelope without blade phase. Cosmetic tip paint, chipped blade, imbalance, mount damage and thrust loss must not be guessed solely from penetration. Helicopter main/tail rotor and quad adapters require their own rotating-system work and continuation proofs.

## 5. Integrating the missing intermediate experience

The canonical plan now contains a six-outcome contract: **clear near miss → authored vegetation brush → brief solid touch → sustained scrape → qualified local damage with continuation → terminal escalation**. These are possible outcomes, not a required progression. An edge can snag immediately, and a brief brush can release without structural change.

For each contact episode, the physics owner should provide stable component/feature/surface identity, relative point motion, accepted entry/release timing and supported force/work information. Normal impact estimates remain distinct from tangential friction work. The useful solid-friction quantity is `integral(-F_t dot v_t_relative) dt`; today's endpoint power is a valuable existing observation, but is not that integral. Repeated accepted samples, rejected solver stages and additional hull points must not charge the same work multiple times. GP-16/17 and CR-07 own whether that work causes wear or failure. [S1, S5, S11]

The flight experience should follow those facts: a true near pass remains a flyby; a loaded brush gets a localized touch/scuff; a continuing scrape gets sustained local sound/marks; release stops that feedback; supported damage changes the affected systems; a later snag or slapdown can become the real crash. GP-14 handles the incident independently of whether the simulation pauses, and CR-40 uses only its admitted financial evidence. A soft visual mark must not silently reduce wing strength, and a financial replacement recommendation must not secretly change aerodynamics.

| Perspective | Specific integration requirement |
| --- | --- |
| Wingtip, leading/trailing edge and belly | Include roll rate, actual feature clearance, lever arm, normal loading, tangential drag and second-contact progression; do not assign all aircraft kinetic energy to each point. |
| Propellers, helicopter rotors and quad props | Include body and shaft motion, source-on/off state, actual geometry/phase scope and bounded work; engine-off does not establish a stationary blade. |
| Wheels, skids and retracts | Use actual configuration and intended support, not only the pilot's command. Keep contact, scraping, overload and detachment distinct. |
| Ground, grass, foliage and hard scenery | Separate load-bearing geometry from canopy/visuals and material from field usage. A runway may be turf; foliage response cannot stand in for a rigid fence post. |
| Water | Separate brief wet contact from sustained flotation, moving-interface closure from fluid velocity, and contact cue from terminal aftermath. |
| Other aircraft, cars and people | Use actual target/feature identity and supported relative motion. Do not infer a person hit from a nearby scenery box or use shrub breakage as person response. Static parked geometry does not validate a dynamic two-body exchange. |
| Performance and rendering | Keep physical results independent of FPS, camera distance and graphics presets. Adapt local collision refinement, reuse current bins/buffers and bound contacts, receipts, solver effort and effects. |

This adds focused acceptance to existing owners: E3d3 with GP-07/10 and CR-01 for geometry/time; GP-14/19 and CR-02/03/08 for accepted episode feedback; GP-16/17 with propulsion/lake owners for supported local failure and water; GP-18 plus CR-07/11–15 for actual damaged flight. It preserves the previous helicopter, lake-context, quad, car and deployed-wheel findings rather than pretending one fixed-wing change closes the fleet.

## 6. Efficiency and release boundaries

A global frequency increase is not the first response to a millimetre-clearance case. Use the existing float64 simulation and fixed tick, immutable prepared geometry, spatial bins and proven-clear early rejection. Refine only candidate intervals according to translation, rotation, curvature and timing error. Keep deterministic progress and explicit capacity/exhaustion behavior; do not trade a frame spike for silently dropped contact time. Point-count changes need shared contact-patch budgets so better geometry does not multiply friction or strength.

The existing GP-19 pool/queue and deferred render work are appropriate reuse points. New observations should be bounded and emitted after acceptance. Presentation can vary density or LOD; physical clearance, impulses, damage and replay cannot vary with graphics quality. Measure no-contact cost separately from first-contact and sustained/multiple-contact cost on target hardware. Report p95/p99 tick/frame time, allocations, candidate counts and any overflow. No such performance qualification was run in this pass.

The decisive acceptance is a matched matrix of **clear / actual touch / release / sustained contact / severe positive control**, with angle and local normal/tangential speed varied independently. Include whole-aircraft geometry within a declared error bound, source and spin states, live mass, moving targets/water, reset/replay, rejected candidates and a stated post-contact recovery maneuver ending in a supported flight/landing state within the model's airspeed, attitude, clearance and configuration domain. Finite motion and a responding control over a short horizon alone do not prove recovery. Current probes deliberately separate mathematical component calls from accepted synthetic steps and from existing stock-model controls. They establish the listed boundaries, not a fleet-wide 300 km/h recovery guarantee.

## Evidence and sources

### Executed probes

- **P1:** [flat clearance/brush plus original synthetic padding witness](evidence/round6/probes/probe_nonfatal_geometry.gd), [checked log](evidence/round6/runs/initial/geometry/engine.log).
- **P2:** [outside-CG interval-bounded padding witness](evidence/round6/probes/probe_nonfatal_geometry_outside.gd), [checked log](evidence/round6/runs/geometry-outside/geometry-outside/engine.log).
- **P3:** [accepted scenery remainder characterization](evidence/round6/probes/probe_nonfatal_remainder.gd), [checked log](evidence/round6/runs/remainder/remainder/engine.log).
- **P4:** [accepted synthetic water/direct prop/wave characterization](evidence/round6/probes/probe_nonfatal_water_prop.gd), [checked log](evidence/round6/runs/initial/water-prop/engine.log).
- Full run identities, exclusions, checksums and limits: [verification](nonfatal-contact-verification-2026-11-19.md), [manifest](evidence/round6/manifest.json).

### Pinned implementation sources

| Ref | Source at the reviewed application revision |
| --- | --- |
| S1 | [Hull contact law, prop disc, contact/terminal diagnostics](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/hull_contact.gd) |
| S2 | [Flight session: accepted observations, prop guard and contact arbitration/response](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/flight_session.gd) |
| S3 | [Scenery swept candidates, kinematics, response and ordering](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/scenery_collision.gd) |
| S4 | [Lake collision events, selected policy and normal speed](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/sim/lake_collision.gd) |
| S5 | [Accepted hull grain capture/playback](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/crash/crash_audio.gd) |
| S6 | [Live contact feedback and terminal water aftermath](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/crash/director.gd) |
| S7 | [Load-bearing terrain relief and support normals](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/ground_terrain.gd) |
| S8 | [Artistic near grass](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/render/near_grass.gd) |
| S9 | [Audio plan and later bounded native scrape evidence](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/AUDIO-PLAN.md) |
| S10 | [Deterministic wave/terrain surface and sweeps](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/app/physics/lake_surface.gd) |
| S11 | [Current advanced ground/contact/damage plan](https://github.com/bultodepapas/OpenRCsimulator/blob/d736ee8a2eab0b59b0fa2c561a1eef07f5fae396/docs/plans/advanced-ground-flight-physics.md) |

### Primary research context, not calibration

- **R1:** [APC Propellers — Safety Concerns, load-component discussion](https://www.apcprop.com/technical-information/safety-concerns/). Manufacturer context for rotational, aerodynamic, torsional and vibration loading; no simulator-specific nick/strength threshold is derived.
- **R2:** [von Kármán, NACA-TN-321, *The impact on seaplane floats during landing*](https://ntrs.nasa.gov/citations/19930081174), 1929. Water-impact pressure depends on the body and velocity; this motivates explicit geometry/entry response, not a universal terminal switch or an RC threshold borrowed from a full-scale float.
- **R3:** [MuJoCo official computation documentation, soft-contact discussion](https://mujoco.readthedocs.io/en/stable/computation/index.html). Useful comparison of contact approximations and deformation; this audit proposes no engine replacement and treats numerical compliance separately from structural validation.

Primary literature supports researching contact-specific mechanisms. It does not determine which of the current aircraft, props or materials survives an arbitrary millimetre-deep scrape. Those are still the explicit physical-evidence gates in the owning plans.
