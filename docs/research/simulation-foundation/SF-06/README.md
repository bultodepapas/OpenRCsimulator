# SF-06 — Law property harness

2026-10-15 · **Status: implemented. 203 checks over 26 registered laws pass with no exemptions.** Step SF-06 of the [simulation foundation plan](../README.md). The harness verifies mathematical properties of the current laws; it does not validate any of them physically.

## What it checks

[`app/tests/law_properties.gd`](../../../../app/tests/law_properties.gd) is a library of property checks over a law `law(v_body, rates_body) -> loads or derivative`, each returning `{ok, worst, detail}` with the worst value normalized by the law's own forward-flight magnitude:

| Property | Statement | Origin |
| --- | --- | --- |
| continuity | Two Cartesian approaches to one limit point converge to the same output: normalized difference ≤ 1e-6 at ε/V = 1e-9, finite throughout | The 2026-10-14 audit's F01 probe (a 164 N / 257 N jump at pure spanwise flow before R02) and F02 (turbine inlet switch at zero axial speed) |
| finite | Finite output over rest, vanishing speeds and 24 seeded random velocity/rate samples | Audit F11 class (coordinate singularities) |
| rest | Zero output at rest for laws that react only to relative motion | Zero-at-rest rule |
| galilean | `law(v, calm) == law(v + w, wind w)` with identity attitude, four winds, tolerance 1e-9 | M5 wind Galilean tests, generalized |
| mirror | Lateral symmetry: `v_y, p, r → −v_y, −p, −r` gives `[Fx, −Fy, Fz, −Mx, My, −Mz]`, tolerance 1e-9 | Symmetric aircraft with neutral controls |
| passive / passive_translational | Dissipative axes never do positive work in pure translation; aerodynamic loads never do positive translational work at zero rates (lift does no work, drag dissipates), tolerance 1e-7 | "Friction never adds energy" (E2), aerodynamic passivity |

[`app/tests/test_sf_law_properties.gd`](../../../../app/tests/test_sf_law_properties.gd) registers every law and runs the applicable properties. A failure must be explained by an open ID in its `EXEMPT` table or the run fails; the table is empty.

## Registered laws

| Law | Properties |
| --- | --- |
| Aerodynamics of each flyable airplane (Ugly Stik, three glow Stiks, Extra, P-51, Ventage Jet, Timber): `Aero.loads` with neutral controls | continuity at the spanwise, vertical, rest and forward limits (seven approach pairs), finite, rest, galilean, mirror, passive_translational |
| Propulsion of each airplane: `Propulsion.loads` at 70 % of `max_rpm` (propeller, glow hub inflow and turbine through the same dispatch) | continuity at forward, rest and crossflow limits including the ±x sign crossing, finite |
| Landing gear of each airplane with contacts: `Ground.loads` with every wheel touching and the deepest compressed 2 cm | continuity at rest and rolling limits, finite, mirror, passive on x and y in pure translation |
| RC ground vehicle: `VehicleDynamics.derivative` at the default spawn | continuity at rest and rolling, finite |
| Rotorcraft airframe: `Airframe.evaluate` of the research helicopter | continuity at the spanwise, rest and vertical limits, finite, rest, mirror, passive_translational |

Not registered yet: the rotorcraft main and tail rotor stages (their state includes rotor speed, flapping and inflow; a rotor-specific adapter is a follow-up), the crash hull and lake laws (prepared geometry and water state), and the finite-difference derivative check listed in the plan.

## Proof

[run log](results/law-properties.log): 203 checks, 0 failed, 0 exempt. The worst continuity at the pure spanwise limit is 2.3e-11 normalized for the Stik aerodynamics, against the pre-R02 order-one jump the audit measured; the gear's rest limit converges from 8e-2 at ε/V = 1e-2 to 8e-9 at 1e-9.

Two gear checks failed on the first run and were a wrong property, not a wrong law: with body rates, a wheel moves at `v + ω × r`, so a force that opposes the wheel's velocity can do positive work along a CG axis. Per-axis passivity at the CG is a pure-translation property; that is the LEARNINGS entry for this step.

## Limits

- Tolerances are mathematical consistency bounds, not physical uncertainties.
- Each law is probed through its public entry point with neutral controls and reference density; control-deflected and ground-effect paths are not swept.
- The whole harness runs in about two seconds headless, well inside the suite's default program timeout.

Commit message: `SF-06: law property harness; 26 laws × continuity/finite/rest/galilean/mirror/passive, 203 checks pass with no exemptions`
