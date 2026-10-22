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
The capture windows differ: Extra before/after requested 3/3 s, P-51 2/3 s,
and MAX-61FX 1/3 s. The MAX-61FX baseline has only four frames and no frame
diagnostics. Its frame percentile is illustrative only; the physics/tick and
simulated-time figures carry stronger evidence for that case.

The Stik remains slow. Its optional fuel-feed closure evaluates engine
lifecycle, coupling and feed pressure four times per stage. A frozen 30 m
airborne probe measured 1.48 ms for its `GlowFlight.point` versus 0.137 ms
for the Extra. The candidate fuel factor changes torque and apparent gravity,
so reusing those sample results would alter the numerical law. The later scalar
feed-factor change below removes repeated telemetry construction while keeping
the same stage closure and solver callback count.

## Glow follow-up

`GlowFlight.point` now prepares candidate-independent fuel-feed terms once per
stage, evaluates only the scalar factor for each solver candidate, then builds
full feed telemetry for the accepted candidate. The endpoint-plus-seed solver
was retained. Against the original full-feed closure, the [short trimmed trace](glow-original.csv)
and [candidate trace](glow-scalar-only.csv) match exactly after excluding the
UTC creation line. The [original](glow-full-throttle-original.bin) and
[candidate](glow-full-throttle-candidate.bin) 240-tick, full-throttle airborne
binary state histories are both 94,080 bytes with SHA-256
`A51427333C5C2A854282B1559466DF553EE78B2EA77F1EC1CEAB12FF84DC0281`.
The original source was commit `32a7cff0`; the candidate appears in
`126fbc47`. `test_glow_fuel_feed.gd` passed 41 checks and
`test_glow_flight_physics.gd` passed 110.

On the same host, the MAX-55AX whole-tick bench changed from 4,213.6 to
4,113.0 µs/tick in its trimmed case and 4,302.4 to 4,014.0 µs/tick stalled.
These are modest improvements (2.4% and 6.7%) and remain near the 4,167 µs
240 Hz interval. The three glow Stik variants still need a larger, separately
validated performance improvement to guarantee real-time flight on this host.

## Fleet and lake follow-up

The [no-lake fleet probe](fleet_contact_probe.gd) and [default-lake variant](fleet_contact_lake_probe.gd)
ran 120 full-throttle ticks per case from runway and airborne starts, with
soft contacts on or off. They use headless sessions and measure physics only;
the 8-aircraft outputs are retained with [no lake](fleet-no-lake.json) and
[the default lake](fleet-with-lake.json). The lake variant explicitly calls
`set_lake_context` before the launch. The measured source is represented by
commit `32a7cff0`; timing distributions vary with host load.
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

The [low bank probe](lake_bank_probe.gd) found that many hull points remained
above the field datum while passing over the bank. Validated lake bed and bank
heights are below that datum, so `HullContact` now skips terrain sampling when
both the body contact depth and transformed point height are nonpositive. It
keeps a placeholder cache entry so the later load path reads the same point
order. In an isolated clean, paired 40-stage probe, Extra changed from
2,076 to 934 µs/stage and P-51 from 2,584 to 913; three glow Stiks changed
from 1,718–1,800 to 751–789. Ugly Stik and Turbo Lumber changed little.
Eighteen paired contact checks matched loads, status and reason byte-exactly;
the 761-check lake terrain oracle also passed. These are synthetic static
poses and do not measure frame rate or establish physical handling.

A later [native P-51 frame capture](p51d-mustang-120-followup-frames.json) on
the current contact/lake source remains slow at p50 62.8 ms over 44 frames.
During 3.06 s wall time, its simulation advanced 2.2 s (528 ticks), without
pausing or faulting. Every measured frame ended 12 ticks later, the configured
maximum steps per frame. Its smoothed physics cost was 4.24 ms/tick against a
4.17 ms budget at 240 Hz; this explains why runway motion appears delayed in
real time even after the contact fix. The frame report's physics cost is a
5%-weight moving average, not a per-tick median. The corrected
[fixed-state stage probe](p51_stage_profile.gd) installs the lake and soft
contacts, but it has no stable paired measurement on this busy host; no
component cost is inferred from it. The existing
`bench_regimes.gd` P-51 fixture fails its reset invariants on this source, so
its output was discarded rather than used as performance evidence.

A second [native P-51 capture](p51d-mustang-120-shore-followup-frames.json)
after the bank guard still has p50 62.9 ms across 43 frames. It advanced
2.15 s of simulation in 3.03 s wall time, with no fault; its smoothed physics
cost ended at 4.00 ms/tick. This run was not paired under controlled host
load, so its difference from the earlier 4.24 ms/tick is not attributed to
the bank change. Both captures show the remaining real-time backlog.

The P-51's off-source RPM preview in `FlightSession._substeps` cost about
0.88 ms/tick in one instrumented run. Skipping it for a full tank changed the
substep count from 2 to 1 near the stopped-RPM boundary and changed the next
state. A scalar `Propulsion.shaft_rate` replacement also differed because
rotor/body coupling uses aerodynamic and ground moments. Neither shortcut was
integrated; those measurements identify a residual cost, not a safe fix.
An apparent duplicate wing-lift calculation in the global ground-effect
branch cost about 22 µs per call, but that branch ran only once in 1,920
P-51 RK stage calls over a two-second runway probe. Its optimization was
reverted because it would not materially improve the flight loop.

## Runway acceleration in simulation time

The [fixed-tick probe](runway_acceleration_probe.gd) and its [Windows Godot
4.7.2 result](runway-acceleration-probe.json) compare immediate full throttle
with a 0-to-1 command ramp over two simulated seconds on the same flat runway.
The Extra is glow-started before each run. All four cases completed 480 ticks
without a crash or solver fault. At two seconds, the Extra reached 5.61 m/s
with immediate throttle and 3.46 m/s with the ramp; the P-51 reached 9.89 and
8.38 m/s. The Extra's three wheel anchors remained stuck at 0.5 s in both
cases, then slid by 1 s. P-51 wheel anchors slid by 0.5 s.

Keyboard and default gamepad stick-rate profiles both increase throttle at
0.5 per simulated second; the selectable absolute-trigger gamepad profile
applies its axis position directly. Thus the default command ramp, Extra glow
spool and estimated wheel breakaway all contribute to the perceived initial
delay. These probes do not establish an incorrect coefficient or a real-aircraft
acceleration target; no propulsion or friction data was retuned.

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
actual contact, a clear hull above the lake bed, and mixed penetrating lake,
clear lake and dry-ground points with aggregate force and torque checks (38
checks, zero failures). Godot import parsed the project. The dynamic-mass contact,
dynamic-mass session, aircraft contact session, P-51 ground, and glow flight
physics tests passed. The P-51 takeoff gate still gives 4.0 s simulated
liftoff, 35 m ground run, and no crash. Software checks do not establish
aircraft-specific physical realism.
