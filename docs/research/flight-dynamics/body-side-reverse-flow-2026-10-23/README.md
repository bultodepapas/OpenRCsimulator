# D10-R3-R1 — Bound the forward body-side derivative

2026-10-23. Implementation verification, not physical validation of reverse flight.

The local fuselage term extrapolated its forward-derived `CYbeta` as
`0.5 rho S CYbeta u v`. For negative `u`, its lateral force changes sign and can
overcome the declared crossflow drag. The source data do not establish that
continuation. `app/physics/aero.gd::_local_loads` now uses `max(u, 0)` in that
term only. Crossflow, its ARP moments, forward flight and the existing
reference-velocity convention remain. No aircraft coefficients, solver state
layouts, integrator or goldens were changed.

This is a conservative applicability limit, not a calibrated reverse-flow law.
The references below do not prescribe this exact gate for these aircraft.
For the configured signs, the combined body-side contribution (gated slope plus crossflow) satisfies
`Fy v = 0.5 rho [S CYbeta max(u,0) - A_cross sqrt(v²+w²)] v² <= 0`.
That bounds its translational work using the reference air velocity; it does
not establish generalized rigid-body passivity with rotation or total-airframe
passivity. The force is continuous at `u=0`, with a derivative kink.

## Measured results

Static public-`Aero.loads` probes: neutral surfaces, 20 m/s, alpha 179 degrees,
beta 5 degrees, zero rates, density 1.225 kg/m³. Body contributions are differences
against the same model with the two optional body terms removed.

| Aircraft | Body Fy before → after (N) | Body power before → after (W) | Total aero power before → after (W) |
| --- | --- | --- | --- |
| Extra 300S | +0.970398 → -0.297450 | +1.691515 → -0.518490 | -98.944847 → -101.154852 |
| F4U | +4.863702 → -1.055205 | +8.477991 → -1.839343 | -223.176987 → -233.494321 |

Total aero power was already negative in both baseline samples. These measurements
do not show an energy-producing whole aircraft.

Three actual `FlightSession` baseline tapes exact-replayed with `complete=true`
and `solver_changed=false`. Candidate replay used identical aircraft and input
tapes; all three were complete with `solver_changed=true`.

| Case | Duration / rows | Candidate comparison |
| --- | --- | --- |
| Extra forward pitch pulse | 2 s / 481 | Zero differences in compared position, velocity, angular-rate and attitude channels |
| Extra nose-up, tail-first | 0.5 s / 121 | First divergence at tick 99, the axial-flow reversal; max component velocity difference 0.000130 m/s, position 0.00000391 m |
| F4U reverse, alpha 179 / beta 5 | 2 s / 481 | First divergence tick 1; max component velocity difference 2.28504 m/s, position 0.640165 m; attitude angle difference 0.238671 rad |

These are open-loop comparisons, not evidence that the changed trajectory matches
a real aircraft. Candidate tail-first runs at 240/480/960 Hz all crossed `u=0`
and exact-replayed at their recorded timestep. Crossing times were
0.4125/0.4104167/0.4104167 s. The positive-side attached-force time slopes were
0.12077/0.12086/0.12098 N/s, versus zero on the reverse side; crossflow stayed
continuous near -0.0202 N. This demonstrates the intended kink, not smoothness
or fourth-order convergence through that event.

The expanded body-side regression has 25 checks, including 160 zero-rate reverse
states per aircraft, nonzero crossflow and all six ARP load components, continuity
and forward preservation. It fails six checks against the baseline and passes
against the candidate. Independent verification passed 16 checked engine runs:
body side, aero, aero flow, continuity, attached flow, envelope, Extra post-stall,
Extra handling, wing polar, polar session, wing-body roll, rigid body, stall solver,
goldens, checkpoint and checkpoint integrity. Four committed goldens remained
within their existing tolerances; they were not re-recorded. Controls separately
passed 135 checks across rates, servo, RC input and actuator suites.

## Performance and control response

On Windows / Ryzen 9 5900X, three alternating baseline/candidate pairs each used
720 warmup and 3,600 measured steps per fixed Extra fixture. Timings surround
`Simulation.step()` only; state is restored before every step. Values below are
medians of the three per-run percentiles, in milliseconds.

| Fixture | Baseline p50 → candidate p50 | Baseline p95 → candidate p95 |
| --- | --- | --- |
| Positive stall | 1.950 → 1.959 | 2.699 → 2.857 |
| Reverse, alpha 179 / beta 5 | 2.001 → 1.999 | 3.176 → 2.691 |

Pairwise differences change sign. Baseline positive-stall p50 alone ranged
1.929–3.031 ms; reverse p95 ranged 2.617–3.380 ms. These measurements do not
establish a speedup or a precise overhead bound. Raw samples, source hashes and
all runs are retained; two initial longer runs are explicitly exploratory.
This is a repeated-state microbenchmark, not real-time flight qualification.

The software servo seam passed six checks in each isolated variant: at 240 Hz,
the normalized roll servo reached `5/33.6` after five ticks and full throw at
tick 34 (141.67 ms). This unchanged simulated travel time excludes controller,
OS, radio and displayed-response latency.

A native fullscreen rendering pair confirmed an actual 1920×1080 window on the
existing 60 Hz display, VSync on, uncapped, Compatibility/Standard, MSAA 2,
render scale 1.0. After five seconds of warmup, twenty-second samples measured
p50 16.669 → 16.673 ms, p95 17.118 → 17.119 ms and p99 17.296 → 17.387 ms.
The scripted-fixed capture advanced **zero simulation ticks**: this measures
render pacing only and cannot qualify combined flight/render performance or the
aero branch. Baseline emitted one ObjectDB exit warning; candidate emitted none;
neither reported engine errors. A 1920×1061 windowed attempt was exploratory,
not accepted as 1080p evidence.

## Scientific basis and limits

- [Allen–Perkins, NACA 1048](https://ntrs.nasa.gov/citations/19930090962): potential
  plus viscous crossflow body-force construction; not RC full-angle calibration.
- [NASA NDARC theory, section 10-3.3](https://ntrs.nasa.gov/api/citations/20170011635/downloads/20170011635.pdf):
  an explicit remapped/tapered fuselage side-force policy is precedent for limiting
  a local derivative. Its rotorcraft law is not a drop-in replacement for these data.
- [Jorgensen, NASA R-474](https://ntrs.nasa.gov/citations/19770026166): geometry and
  Mach-dependent high-angle body results; the 0–180 degree coverage at Mach 2.9
  does not validate these RC aircraft near Mach 0.06.
- [Rigid-body power](https://mechanicsmap.psu.edu/websites/14_work_energy_rigid_body/14-3_power_rigid_body/power_rigid_body.html):
  include `M dot omega` when evaluating a force applied away from the reference.
- [FAI F3A 2026](https://www.fai.org/sites/default/files/document/file/SC4_volume_CIAM%20F3A%202026.pdf):
  tail-first motion is relevant to tailslides, but judging descriptions are not
  aerodynamic coefficient measurements.

The investigation also examined rigid-body frames/inertia/RK4, control conditioning
and servos, post-stall behavior, and propulsion interactions. No additional
production correction was justified by the completed evidence. Dynamic post-stall
and reverse-flow calibration, body rotational derivatives and real RC validation
remain outside this correction. Replacing `u` by `abs(u)` or adding rotational
damping would introduce unsupported new response.

## Failures and qualification boundaries

Extra's stopped glow installation rejects a 20 m/s reverse-flow reset. A clean
static probe confirms the explicit backward-shaft domain guard: required torque
-0.103330 Nm exceeds the 0.010339 Nm static holding magnitude. Supporting backward
rotation requires a signed-shaft model; bypassing the guard is not a correction.

Two longer Extra attempts are incomplete: an older baseline accepted 260 ticks,
and the candidate extension accepted 255 before a malformed joint-stage fault.
**Those counts are not a before/after comparison.** A full-checkpoint audit found
the same body state, continuous state, modes and common command tape, but different
initial downwash auxiliary state: approximately -1.8e-7 versus +5.6999 m/s.
Initial loads also differ. The earlier comparison based only on the body seed
was withdrawn. Candidate replay of the old tape only reaches its accepted
260-tick prefix; it never evaluates the following failed step.
The accepted short tape is explicitly only 0.5 s. Earlier recorder prose saying
all four cases lasted two seconds is stale; per-case durations and failure records
govern. The three accepted baseline/candidate replay comparisons preserve the
full initial checkpoint and remain valid.

A fresh instrumented pair then matched all initial body/auxiliary/continuous
state, modes, inputs and reset loads, plus all 255 accepted command/input rows.
Both variants refused tick 255→256 at the same midpoint stage, 1.064583333 s.
The stopped, cut engine demanded reverse shaft torque of -0.0103607840 Nm
(baseline) and -0.0103679683 Nm (candidate), exceeding the 0.0103390090 Nm static
hold. `GlowFlight._stage_coupling` explicitly returns `{ok=false}` for that
unsupported reversal; `evaluate` returns an empty stage, which the kernel rejects.
This identifies a model-domain refusal, not nonfinite arithmetic, in this matched
case. The probes deliberately exit 1 for the incomplete flight; both checked logs
have zero engine/parser/resource errors. Diagnostic instrumentation and all stage
values are retained. This correction neither introduces nor resolves that boundary
in this fixture; a supported reverse-shaft model requires separate work.

The canonical WSL `app/test.sh` could not start because WSL returned
`Wsl/Service/CreateInstance/E_FAIL` (code 6, step 2). Native Windows checked runs
above are the available verification, not a claim that the full suite ran.

## Reproduction and retained evidence

Base commit: `e76a72f5b25f1787564ec8c34056428fa2cafe5a`, with pre-existing dirty
changes preserved. The isolated flight/performance app copies differ only in
`physics/aero.gd`. Baseline solver SHA-256:
`13b8d848df6df2cab646374c03a93f9651e240dfa634209ff77c7b52ff95df10`;
candidate: `1d06d5160dd6b23ec619584cb9ea115eec30f4111ca23c74165eac1d9761e753`.
Engine: Godot 4.7.2 stable, Windows x64, official `ed1daf0bf`.

[evidence.zip](evidence.zip) retains exact solver source bytes, aircraft data, the pre-existing
patch, source identities, probe/recording scripts, ORFL tapes, CSVs, comparisons
and checked-run reports/logs. [manifest.json](manifest.json) records each member's SHA-256.
Absolute scratch paths in original reports are provenance, not portable paths.
Use the base checkout plus retained baseline source/data overlays for the baseline;
replace only `physics/aero.gd` from the candidate overlay for comparison. Use
`tools/godot/run_checked.py` and the recorded command arrays, replacing local paths.
The executed regression test differs from the current test only by its header comment.

Rejected harness attempts (missing script, malformed probe inputs and a leaking
diagnostic) are excluded from accepted checks. Expected baseline regression
failures and incomplete flight records are retained and labeled separately.

Final independent Evidence Auditor and Good Enemy reviews found no blocking issue.
Good Enemy independently passed the 25-check body-side suite and accepted the gate
only as a domain policy; real reverse-flight fidelity remains unvalidated. Its
assessment is retained under `adversarial/` in the archive. The assessment's archive
hash identifies the pre-review bundle; `reviewed-manifest.json` preserves that
identity. The final bundle adds review evidence and updates only the packaging
script among earlier members, leaving the experimental payload unchanged.
