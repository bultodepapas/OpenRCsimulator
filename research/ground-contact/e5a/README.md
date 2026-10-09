# E5a — taildragger contact verification

2026-10-09 · **Status: software verification; independent aircraft/pilot validation remains open.** Pinned Godot from `app/get-godot.sh`, Python 3 standard library and Git; no display required.

The Extra generator now supplies wheel contacts through the existing E1/E2 ground law, following the committed P-51 implementation. These checks verify both aircraft's geometry, static loads and force signs, then exercise Extra taxi behavior through the real flight session. [Evidence and limits](../../../docs/research/ground-contact/E5a/README.md).

`app/test.sh` runs the focused generator/contact/session checks automatically. The mutation option below adds the isolated fault-detection proof.

From the repository root, use a new output directory:

```sh
python3 research/ground-contact/e5a/verify.py --out /tmp/e5a-verification --mutations
```

The runner checks generated-data freshness, executes `checks.gd` and `session.gd`, and records input hashes and logs. With `--mutations`, it creates a temporary local clone, overlays the new Extra data and test scripts, verifies the unmodified control, then injects five faults: reversed tail steering, a displaced tail contact, missing source wheel diameter, a wheel reintroduced into the crash hull, and an inert throttle pulse. Deliberate faults never enter the working tree. A nonzero process exit, missing completion summary or Godot error fails the runner; mutation success requires an assertion failure, not an engine failure. `verification.json` is written only when all requested checks complete.

Direct runs with detailed numeric reports:

```sh
GODOT_E5A=$(app/get-godot.sh)
"$GODOT_E5A" --headless --path app --script "$PWD/research/ground-contact/e5a/checks.gd" -- --out=/tmp/e5a-contact.json
"$GODOT_E5A" --headless --path app --script "$PWD/research/ground-contact/e5a/session.gd" -- --out=/tmp/e5a-session.json
```

`checks.gd` reads the committed visual geometry and raw physics data, checks the loader's coordinate conversion, and integrates a bare rigid body on its gear. Hand-calculated vertical-force and moment balance provide the static oracle. Isolated main/tail contact tests distinguish destabilizing main-wheel and restoring tail-wheel side-force moments. These signs do not predict a complete ground loop.

`session.gd` uses the actual Extra engine, servos, aero, field surfaces, contact forces and crash checks. Four three-second cases run at 240/480/960 Hz: stopped-engine coasting from 3 m/s with ±0.3 yaw after 0.25 s, idle from rest, and a 0.25 throttle command from 0.5 to 1.5 s. Trims are explicitly zero; the test-only parked pose uses the generated three-point geometry and sag. The pulse must raise peak RPM by more than 100 rpm and move at least 10 mm farther than idle at each tick rate; these are response-detection floors, not physical performance bands. All controls and numeric tolerances are authored verification choices, not field measurements or pilot technique recommendations. This does not add an Extra runway-start menu option.

Refinement compares matched 20 Hz state boundaries. Bounds are 2 mm per position component, 0.01 m/s per velocity component, 0.001 per quaternion component and 0.005 rad/s per angular-rate component. Each difference must also shrink by at least 1.5× on the second refinement, except differences already below `1e-7` in their component units. These are numerical consistency checks, not accuracy bands against a real aircraft. Sampled engine/servo updates precede RK4; transient session tests need not show fourth-order convergence.

To regenerate the Extra after a deliberate data change:

```sh
python3 research/extra-300/ex05/derive_physics.py
python3 research/extra-300/ex05/derive_physics.py --check
```

Keep generator changes and generated JSON/report together. Stiffness, damping, tyre coefficients, steering ratio and collapse thresholds are provisional and source-labelled. No caster, brakes, stiction anchors, wheel-circle geometry, suspension rendering or independent physical acceptance is introduced by E5a.
