# EL1a — Electric source foundation

2026-10-10 · **Status: source software verified; existing app regression passes; aircraft integration and physical validation remain open.**

The first bounded electric step adds a pure source kernel in [electric_motor.gd](../../../../app/physics/electric_motor.gd), [its tests](../../../../app/tests/test_electric_motor.gd), [reproducible proof runner](../../../../research/propulsion/el1a/verify.py) and the [integration plan](../../../ELECTRIC-PROPULSION-PLAN.md). The loader/catalog still accepts no electric aircraft. Existing flight laws, state layouts, aircraft data, goldens, input and rendering are unchanged.

Research: [primary equations and scope](sources.md), [selected Timber B configuration and missing measurements](timber-reference.md), [runtime seams and hidden glow assumptions](code-audit.md). No third-party code or assets are copied. The implementation uses published equations; linked documents retain their publishers' terms. All numerical motor/propeller fixtures in the tests are synthetic, including the 800 Kv example. Matching a nameplate Kv does not calibrate the installed Timber system.

## Interface and limits

`Electric.evaluate(rpm, duty, bus_voltage_v, motor, enabled=true)` consumes normalized numeric `kv_rpm_per_volt`, `resistance_ohm` and `no_load_current_a`. It returns `ok`, mode, effective duty, command/terminal/back-EMF voltages, equivalent motor and battery currents, net shaft torque and the electrical/mechanical loss accounting. A failure returns only `ok=false` and a message; a caller must refuse that result. Parameters have no aircraft ID and calls carry no mutable state.

This is a direct-drive, positive-rotation, ideal motoring ESC approximation. It distinguishes battery current from equivalent motor current and preserves `Pbus = Pshaft + Pcopper + Protational`, including mechanical coast losses. Duty zero or disabled opens the electrical path. At exact rest friction cannot create negative rotation; rotating below the zero-torque current still produces loss drag. Invalid inputs and finite-input overflow are rejected. No electrical regeneration, switching/commutation, active braking, measured startup ramp, thermal model or current limiting is claimed. The ideal source can predict high startup current; a nameplate current rating cannot be silently used as a limiter.

The kernel does not solve a full aircraft, stop event, trim or shaft trajectory. Its no-load transient probe holds the carrier fixed and uses the smooth positive-speed branch. The endpoint-at-rest friction rule still needs event/regularization and timestep proof in EL1d before real-session use. Existing stopped-prop drag/table limitations remain G1d work. Battery capacity, sag and depletion are deferred; the bus voltage is prescribed explicitly.

## Focused proof

[proof.json](proof.json) records exact source hashes, pinned Godot identity, 1,057 checks with zero failures and four isolated mutations rejected at their intended physical assertions.

| Experiment | Result | What it establishes |
| --- | --- | --- |
| Hand fixture, 600 rpm/V, 0.2 ohm, I0=1 A, 1,800 rpm, 12 V, duty 0.5 | Equivalent motor 15 A; battery 7.5 A; source 0.222816920329 N·m; bus 90 W, shaft 42 W, copper 45 W, rotational 3 W | Unit conversion and current/power accounting against independently reduced numbers |
| Three synthetic motor sizes, four bus voltages, four duties, five RPM values | 240 operating points preserve energy and nonnegative electrical input/losses | Positive motoring, blocked rotor, overrun and coast branches |
| Existing static prop-load function vs independent quadratic equilibrium | At density 0.8/1.225/1.6 kg/m³: 6,246.823214 / 5,936.859471 / 5,705.821175 rpm | A generic source can balance the existing prop torque; density enters the propeller load |
| Fixed-carrier no-load transient, 0.1 s | RPM error at 120/240/480/960 Hz: 0.015830551 / 0.000910824 / 0.000054623 / 0.000003344 | Smooth RK4 source evaluation converges toward an independent exponential; no full-session convergence claim |
| Existing rotor-coupling probe, source startup from rest | Opposite carrier acceleration and zero total angular-momentum derivative | Electric source torque has the existing internal-torque convention |
| Invalid/missing types, nonfinite parameters, unsupported signs/duty and finite-input overflow | All rejected | Invalid source evaluations do not produce a valid-looking powerplant result |
| Mutations: omitted duty in battery current; wrong Kv conversion; removed negative coast torque; ignored disable | All four rejected in disposable minimal projects | Checks can detect physically meaningful mistakes; working tree never mutated |

Reproduce from the repository root:

```sh
"$(app/get-godot.sh)" --headless --path app --audio-driver Dummy --script res://tests/test_electric_motor.gd
python3 research/propulsion/el1a/verify.py --output /tmp/el1a-proof.json
app/test.sh
```

The proof runner requires a completed suite, nonzero check count, intended assertion failures for mutations and no engine errors; a process exit alone is insufficient. It copies only the six physics modules and focused test into a fresh temporary Godot project, preserving source hashes and avoiding import-cache dependencies. `app/test.sh` discovers the new `test_*.gd` automatically.

[verification.json](verification.json) and the [compressed full app log](app-regression.log.gz) retain the regression result: `app/test.sh` exits 0, including all 156 existing GDScript suites, old goldens, model contracts, four trimmed aircraft, trace/CLI checks and 30/60/144 FPS equivalence. That run enumerated its test list before the electric test was added; the additional 1,057-check suite passed separately in the real app and the fresh isolated project. No existing app files changed. A subsequent editor import passed and generated the new script UIDs. The static linter has zero errors and the same 12 pre-existing diagnostics before/after; no new warnings were introduced. Existing data-estimate and shutdown warnings remain in the app log.

## Remaining work

EL1b adds a strict electric loader/schema branch; EL1c–d connect operating-point trim, continuous shaft integration and versioned telemetry/replay. EL1e proves shared aircraft/session behavior, then Timber TT-07–10 provide model-specific data and flight. The stock prop's `Ct/Cp`, equivalent motor R/I0, inertia, loaded voltage and independent flight evidence are still missing. Software verification cannot close EL5/6 or TT-16 physical acceptance.
