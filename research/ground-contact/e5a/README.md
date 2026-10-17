# E5a — taildragger contact verification

2026-10-09 · **Status: software verification; independent aircraft/pilot validation remains open.** Pinned Godot from `app/get-godot.sh`, Python 3 standard library and Git; no display required.

The Extra generator now supplies wheel contacts through the existing E1/E2 ground law, following the committed P-51 implementation. These checks verify both aircraft's geometry, static loads and force signs, then exercise Extra taxi behavior through the real flight session. [Evidence and limits](../../../docs/research/ground-contact/E5a/README.md).

`app/test.sh` runs the focused generator/contact/session checks automatically. The mutation option below adds the isolated fault-detection proof.

From the repository root, use a new output directory:

```sh
python3 research/ground-contact/e5a/verify.py --out /tmp/e5a-verification --mutations
```

The runner checks generated-data freshness, executes `checks.gd` and `session.gd`, and records input hashes and logs. With `--mutations`, it creates a temporary local clone, overlays the new Extra data and test scripts, imports resource dependencies, verifies the unmodified control, then injects five faults: reversed tail steering, a displaced tail contact, missing source wheel diameter, a wheel reintroduced into the crash hull, and an inert throttle pulse. The v2 loader now rejects reversed steering before the force probe, and the contact-admission contract rejects a support contact duplicated as a hull probe before flight. Those mutations require their specific semantic diagnostics. The hull mutation preserves point-ID/component array cardinality, so malformed metadata cannot count as detection. Deliberate faults never enter the working tree. A nonzero process exit, missing completion summary or Godot error fails the runner; mutation success requires an assertion failure, not an engine failure. `verification.json` is written only when all requested checks complete.

Direct runs with detailed numeric reports:

```sh
GODOT_E5A=$(app/get-godot.sh)
"$GODOT_E5A" --headless --path app --script "$PWD/research/ground-contact/e5a/checks.gd" -- --out=/tmp/e5a-contact.json
"$GODOT_E5A" --headless --path app --script "$PWD/research/ground-contact/e5a/session.gd" -- --out=/tmp/e5a-session.json
```

`checks.gd` reads the committed visual geometry and raw physics data, checks the loader's coordinate conversion, and integrates a bare rigid body on its gear. Hand-calculated vertical-force and moment balance provide the static oracle. Isolated main/tail contact tests distinguish destabilizing main-wheel and restoring tail-wheel side-force moments. These signs do not predict a complete ground loop.

`session.gd` uses the actual Extra engine, servos, aero, field surfaces, contact forces and crash checks. Six three-second cases run at 240/480/960 Hz: stopped-engine coasting from 3 m/s with ±0.3 yaw after 0.25 s; idle and a throttle pulse from rest; and a matched rolling idle/pulse pair starting at 3 m/s. Both pulses command 0.25 throttle from 0.5 to 1.5 s. Trims are explicitly zero. Stationary starts retain the product runway solver's support pose and loaded stiction anchors; rolling starts use the generated three-point geometry and sag with sliding anchors. Each pulse must raise peak RPM by more than 100 rpm and move at least 10 mm farther than its matched idle control at each tick rate; these are response-detection floors, not physical performance bands. All controls and numeric tolerances are authored verification choices, not field measurements or pilot technique recommendations.

Refinement compares matched 20 Hz state boundaries. Every case retains bounds of 2 mm per position component, 0.01 m/s per velocity component, 0.001 per quaternion component and 0.005 rad/s per angular-rate component. Differences must also shrink by at least 1.5× on the second refinement, except differences already below `1e-7` in their component units, for all cases except the from-rest pulse. That pulse crosses once-per-tick stick/slip transitions, whose grid-dependent timing does not support this smooth-branch order assertion. It retains completion, three-contact, both absolute refinement bounds, RPM-response and displacement checks. Per-wheel anchor transition ticks/times are recorded; the rolling pair explicitly asserts sliding anchors and no transitions throughout the comparison. These are numerical consistency checks, not accuracy bands against a real aircraft. Sampled engine/servo updates precede RK4; transient session tests need not show fourth-order convergence.

The 2026-10-17 fixture correction follows the addition of Extra stiction and provisional runway starts. The former airborne-reset stationary fixture produced two order-check failures despite passing every absolute bound: position differences were 0.596/0.493 mm and angular-rate differences were 0.000248/0.000375 rad/s. This is a test-scope correction, with no physics or tolerance changes. The [Extra runway test](../../../app/tests/test_extra_runway.gd) additionally checks solved stuck support at idle and release of all three anchors during takeoff at 240/480 Hz. Physical aircraft and pilot qualification remain open.

The corrected Linux session run passes 98 assertions (99 with JSON report output). Its from-rest pulse records five wheel-mode changes at each rate, all during the powered pulse. After fixing the stationary equilibrium, its angular-rate differences decrease from 0.000233 to 0.000184 rad/s (1.27×), still below the former 1.5× requirement: fixing the start alone does not restore that unsupported event-crossing order gate. Both rolling cases record zero mode changes at all three rates. The rolling pulse's maximum position-component differences decrease from 1.319 mm to 0.660 mm; the stationary idle remains at its solved equilibrium. Observed transition times in seconds:

| Hz | Tail release | Tail re-stick | Left main release | Right main release | Final tail release |
| --- | --- | --- | --- | --- | --- |
| 240 | 0.687500 | 0.691667 | 0.695833 | 0.704167 | 0.775000 |
| 480 | 0.687500 | 0.689583 | 0.695833 | 0.702083 | 0.772917 |
| 960 | 0.688542 | 0.689583 | 0.695833 | 0.702083 | 0.772917 |

Reproduce the event lists and component errors with the detailed-report command above.

To regenerate the Extra after a deliberate data change:

```sh
python3 research/extra-300/ex05/derive_physics.py
python3 research/extra-300/ex05/derive_physics.py --check
```

Keep generator changes and generated JSON/report together. Stiffness, damping, tyre coefficients, steering ratio and collapse thresholds are provisional and source-labelled. The current generator supplies a borrowed engineering estimate for stiction; current wheel profiles and shared ground laws own wheel-radius behavior. E5a adds no caster, brakes, suspension rendering or independent physical acceptance.
