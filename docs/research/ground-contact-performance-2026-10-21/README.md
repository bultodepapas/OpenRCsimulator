# Runway frame stalls, 2026-10-21

The interactive runway route enabled soft crash-hull contacts. Finite-fuel
aircraft sampled live mass at every RK4 stage, then computed contact stiffness
and damping from 26 effective-mass directions for **every hull point**, even
when no point touched the terrain. The work repeated four times per 240 Hz
tick. In a matched P-51 stage probe, enabling soft contacts changed the ground
stage from 546 to 4,409 µs; the same state in free flight took 379 µs.

`HullContact.loads_at_properties` now validates the mass sample and state,
screens individual points against flat ground or covered lake terrain, and
computes the unchanged coefficients only for potentially touching points.
`loads` retains its original contact and force calculations. The geometric
screen is conservative for covered lake terrain, so it can do extra work but
cannot omit a lake load.

## Native measurements

Godot 4.7.2, Windows, OpenGL compatibility, RTX 3090. Interactive `--quick-flight`
from the runway, default world and graphics, `--frame-diagnostics --warmup=0
--t=3`. These are short host-specific wall-clock samples, not physical
validation or a steady-state FPS guarantee. The paired JSON reports retain
render and simulation context. The same host ran each case serially.

| Aircraft | Before p50 frame | After p50 frame | Before physics/tick | After physics/tick |
| --- | ---: | ---: | ---: | ---: |
| Extra 300S | 177.8 ms | 57.0 ms | 14.15 ms | 3.85 ms |
| P-51D Mustang | 273.3 ms | 63.1 ms | 21.50 ms | 4.02 ms |
| Stik glow 61FX | 267.5 ms | 134.9 ms | 22.25 ms | 10.08 ms |

The Stik remains slow. Its optional fuel-feed closure evaluates engine
lifecycle, coupling and feed pressure four times per stage. A frozen 30 m
airborne probe measured 1.48 ms for its `GlowFlight.point` versus 0.137 ms
for the Extra. The candidate fuel factor changes torque and apparent gravity,
so reusing those sample results would alter the numerical law. This change
addresses the shared ground-contact overhead only.

## Numerical evidence

`*-baseline.orfl` used the committed pre-change `hull_contact.gd` with soft
contacts enabled; `*-candidate.orfl` used this optimization. Each run has 240
full-throttle runway ticks from the same field, aircraft and input tape. Each
baseline `*-baseline-replay.json` reports `status=ok`, `complete=true`,
`solver_changed=false` under its original source. Each pair's CSV exports
are byte-identical across all 241 rows, including body, force, auxiliary,
continuous and live-mass channels. `*-comparison.json` also reports no first
divergence and zero position, velocity, angular-rate and attitude error.
The changed solver fingerprint precludes calling the candidate an exact replay.

The focused mass-contact test covers a hull inside broad-phase reach with no
actual contact. Godot import parsed the project. The dynamic-mass contact,
dynamic-mass session, aircraft contact session, P-51 ground, and glow flight
physics tests passed. The P-51 takeoff gate still gives 4.0 s simulated
liftoff, 35 m ground run, and no crash. Software checks do not establish
aircraft-specific physical realism.
