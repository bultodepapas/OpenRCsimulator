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
`loads` retains its original contact and force calculations. A covered lake
point is screened against its sampled bed height; the same sample is then
reused when `loads` runs, without moving the sample across RK stages.

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

These native frame reports were captured after the runway hull screen and
before the lake follow-up below; their source fingerprints remain in each JSON.

The Stik remains slow. Its optional fuel-feed closure evaluates engine
lifecycle, coupling and feed pressure four times per stage. A frozen 30 m
airborne probe measured 1.48 ms for its `GlowFlight.point` versus 0.137 ms
for the Extra. The candidate fuel factor changes torque and apparent gravity,
so reusing those sample results would alter the numerical law. This change
addresses the shared ground-contact overhead only.

## Fleet and lake follow-up

The [fleet probe](fleet_contact_probe.gd) ran 120 full-throttle ticks per case
from runway and airborne starts, with soft contacts on or off. It uses a
headless session and measures physics only; the 8-aircraft output is retained
with [no lake](fleet-no-lake.json) and [the default lake](fleet-with-lake.json).
Representative soft-contact, no-lake mean costs in ms/tick:

| Aircraft | Runway | Airborne |
| --- | ---: | ---: |
| Reference Ugly Stik | 1.26 | 0.67 |
| Stik MAX-61FX | 7.59 | 4.58 |
| Stik MAX-55AX | 7.28 | 4.75 |
| Stik FS-64V | 7.20 | 4.63 |
| Extra 300S | 3.02 | 2.22 |
| P-51D | 3.18 | 2.21 |
| Ventage Jet | 1.87 | 1.26 |
| Turbo Lumber | 1.42 | 0.95 |

All three glow Stik installations have a `fuel_feed` block; the Extra's glow
installation does not. Their airborne cost therefore persists without any
terrain contact. The default lake adds roughly 0.5–0.6 ms/tick to Extra, P-51,
jet and Turbo Lumber runway cases on this host. Other pairwise changes are
within the noise of these short sequential runs.

The [lake-center probe](lake_near_probe.gd) exposed a second avoidable contact
cost. At N110 E125, body down −0.4 m, the normalized bed is down 5.45 m and
none of the eight aircraft's hull points penetrates it. The covered bank path
still built dynamic coefficients for every hull point and sampled each point
again when evaluating loads. The stage cost before/after the lake-specific
filter and terrain reuse was approximately 8.52/3.15 ms for the P-51 and
6.21/2.28 ms for the Extra.

The deep basin has a constant bed beyond the final profile inset. The lake
sampler now uses the polygon boundary distance to prove all four finite
difference neighbors remain on that constant bed, returning the same zero
slopes without those four extra polygon walks. The final lake-center stage
cost was approximately 1.13 ms for the P-51, 1.04 ms for the Extra,
1.11 ms for the MAX-61FX and 0.98 ms for Turbo Lumber. A 1,581-point grid
comparison matched every terrain output field exactly against the previous
sampler; 24 lake hull states across six finite-fuel aircraft matched complete
load results exactly. The frozen lake oracle suite passed 761 checks.

The [low bank probe](lake_bank_probe.gd) still costs about 2.5–3.2 ms per
stage for Extra, P-51 and Turbo Lumber near the sloped shoreline. Its terrain
height and slope vary across the finite-difference stencil, so the deep-bed
shortcut cannot apply. This is a remaining low-altitude performance limit,
not evidence of changed forces or a physical handling defect.

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
