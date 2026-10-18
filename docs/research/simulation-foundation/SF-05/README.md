# SF-05 — Stiff-contact substepping

2026-10-15 · **Status: implemented. A 240 Hz tick with two substeps is byte-identical to two 480 Hz ticks; substeps refine a stiff touchdown three times better than one stiff step; no tick gains energy; the current fleet derives one substep and every fleet fingerprint stays identical to HEAD.** Step SF-05 of the [simulation foundation plan](../README.md). This removes a numerical ceiling; it does not calibrate any gear.

## Change

| File | Change |
| --- | --- |
| [`app/physics/aircraft_data.gd`](../../../../app/physics/aircraft_data.gd) | The gear rule ω·dt < 0.1 now holds per integration substep: the loader derives `landing_gear.substeps = floor(ω·dt / 0.1) + 1` and refuses a gear needing more than `Ground.MAX_SUBSTEPS` (8) with the count in the message. The side-force damping rule uses dt/substeps. The current fleet derives one substep. |
| [`app/physics/ground_contact.gd`](../../../../app/physics/ground_contact.gd) | `substeps(state, gear, dt, surfaces)`: the derived count while the CG is within the gear's reach plus the distance covered in one tick plus 5 cm, otherwise 1. A deterministic function of state and data, so replay and refinement see the same plan. |
| [`app/sim/vehicle_model.gd`](../../../../app/sim/vehicle_model.gd), [`app/sim/simulation.gd`](../../../../app/sim/simulation.gd) | A model may declare `substeps(body, continuous, t) -> int` (1…16), evaluated once per tick. The kernel integrates its own RK4 and the declared-event locator in n pieces of dt/n with the same inputs, reusing the tick's k1 for the first piece and re-evaluating it for the rest. A step policy owns its whole tick and receives no substeps. |
| [`app/sim/flight_session.gd`](../../../../app/sim/flight_session.gd) | The fixed-wing model declares the gear rule (`Ground.substeps` with the current gear and field surfaces). |
| [`app/tests/test_sf_contact_substeps.gd`](../../../../app/tests/test_sf_contact_substeps.gd) (new) | 13 checks. |
| [`app/tests/test_aircraft_data.gd`](../../../../app/tests/test_aircraft_data.gd) | The "gear too stiff" expectation follows the new rule: a gear 50× stiffer loads with its derived substeps, and a gear 200× stiffer is refused with the substep count. |

Why full-load substeps rather than a split of slow and fast loads: a full RK4 piece of dt/n with the same inputs is exactly what a finer tick would do, so the scheme is proven bitwise against the finer tick instead of argued; the cost is paid only while a stiff gear is within reach of the ground, and a gear that is not stiff never pays it.

## Proof

| Check | Result | Record |
| --- | --- | --- |
| Loader | Ugly Stik derives 1 substep; the gear four times stiffer (ω·dt 0.194) derives 2; a hundred times stiffer (ω·dt 0.969, 10 substeps) is refused with the count in the message | [log](results/substep-test.log) |
| Reach rule | 1 substep 5 m above the ground, 2 within reach, and a 5 m/s sink engages them a tick's travel earlier | same |
| Exactness | A 1.5 m/s touchdown of the stiffened Stik gear, 0.4 s at 240 Hz with two substeps, equals the 480 Hz run with one piece byte for byte at every 240 Hz sample and at the end | same |
| Refinement | Against a 960 Hz reference the substepped run errs 3.1e-5 (m + m/s) against 9.2e-5 for one stiff 240 Hz step | same |
| Energy | Largest energy gain in a tick 1.8e-15 J; the rebound stays below the release height | same |
| Session | The catalog Stik's model declares the rule and plans one piece airborne; a tick steps | same |
| Fleet fingerprints, baseline commit `e5f93a4e` (SF-06, after the upstream merge) versus this tree | **24/24 identical**: the current fleet derives one substep and integrates exactly as before | [comparison](results/fingerprint-comparison.txt), [baseline](results/fingerprints-head.json), [SF-05](results/fingerprints-sf05.json) |
| Ground, landing, loader, kernel and glow suites on this tree | 20 programs pass, including touchdown, ground start integrity (254 checks), landing maneuver, electric runway (177), runway transaction, goldens, checkpoints and the glow session; `test_p51_ground` fails its pre-existing lift-off check as at HEAD | [log](results/focused-tests.log) |

## Limits

- Only the kernel's own integration and the declared-event locator substep. The finite-battery, glow, rotorcraft and truck policies own their ticks; the truck already substeps inside its policy for walls and wet zones.
- The reach margin and the per-substep ω·dt rule are numerical choices, not tyre or gear data.
- No physical gear is stiff enough today to exercise this in the catalog; the proof uses a stiffened copy of the Stik gear.

Commit message: `SF-05: stiff-contact substepping; loader derives the substep count, kernel integrates n pieces of dt/n within reach of the ground; 240 Hz × 2 substeps equals 480 Hz byte for byte`
