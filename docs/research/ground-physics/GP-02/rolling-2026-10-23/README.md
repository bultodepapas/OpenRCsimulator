# GP-02-R1 — Passive rolling resistance on smooth surfaces

2026-10-23. Confirmed defect repaired and numerically verified on native Windows, Godot 4.7.2, 240 Hz. No aircraft data, fitted coefficients or golden flights changed. Physical tire/terrain calibration remains open.

## Cause and repair

The wheel-radius correction multiplied both positive and negative surface excess by `sqrt(R_reference / R_wheel)`. For a smooth-surface multiplier below 1, a sufficiently small wheel therefore acquired negative rolling resistance. Its force pointed along travel and supplied mechanical energy. This was not restricted to malformed data: surface factor 0.5 is admitted and used by the field rotorpad, and the authored Timber has 58.002 mm main-wheel radius and 14 mm tail-wheel radius, enough to cross the negative-coefficient threshold.

Only positive vegetation excess now receives the radius correction. Below factor 1, the effective coefficient is the aircraft coefficient times the surface multiplier. Factors at or above 1 retain their previous arithmetic. This implements the existing surface-factor contract without a fitted constant or a zero-force clamp. The factor 0.5 remains an estimated surface parameter, not a measured tire coefficient.

The regression isolates rolling power with zero longitudinal tire slip. A synthetic 10 mm wheel, 90 mm reference radius, base coefficient 0.04, 100 N normal load and speed ±2 m/s previously produced coefficient −0.02 and **+4 W**. It now produces +0.02 and **−4 W**. Smooth-factor 0.75, reference-factor 1, and rough-factor 2.5/7.5 controls are also checked. The authored Timber regression failed only for its tailwheel before repair; all three wheels now obey the smooth-pad multiplier. See [pre-fix regression](rolling-before-fixed-fixture.log) and [repaired regression](rolling-after.log).

`wheel-positive-terrain-excess-v2` is recorded in trace metadata and included in profiled-wheel configuration hashes. Old native checkpoints cannot silently resume under the changed law. The state layout, shared simulation kernel, generated aircraft data and non-profiled contact law are unchanged.

## Same-tape experiment

The [baseline recording](baseline.orfl) preserves 600 ticks plus its initial sample. The [recording script](record-baseline.gd) loads the unmodified Timber, selects a uniformly level smooth pad with factor 0.5, solves the runway pose, then explicitly sets body-forward velocity to 2 m/s with zero throttle. This is a synthetic taxi perturbation: at the taildragger's rest pitch, body-forward velocity also has a vertical world component. The launch metadata describes the original stationary runway solve; the recorded initial checkpoint contains the velocity perturbation.

[Exact replay before the source edit](exact-before.json) passed all 601 rows with `complete: true` and `solver_changed: false`. [Baseline CSV](baseline.csv) retains that checked trajectory; the [original-log export](baseline-export.json) has [zero difference](exact-comparison.json) from it. Baseline solver SHA-256: `3f148883498130f2235f9834800830f030fa2510075866fb10530ae2857f7317`.

The [candidate report](candidate.json) has `complete: true`, `solver_changed: true`, and the same aircraft, initial state and command tape. [Candidate CSV](candidate.csv) and [comparison](comparison.json) show first divergence at tick 1. Over 2.5 seconds, maximum component differences are 0.0663 m position, 0.0534 m/s body velocity and 0.00165 rad/s body angular rate; maximum attitude difference is 0.00168 rad. These are measured consequences of this correction, not realism or acceptance thresholds.

An [airborne baseline](airborne-baseline.orfl) from the six-aircraft FL-04 fixture produces a byte-identical candidate CSV over 260 ticks: [comparison](airborne-comparison.json), [candidate report](airborne-candidate.json). The solver fingerprint changed, so this is a candidate preserved-output control, not an exact-mode replay under the original solver.

Reproduce the candidate with a new output directory:

```powershell
python tools/flight_log/flight_log.py replay docs/research/ground-physics/GP-02/rolling-2026-10-23/baseline.orfl --candidate app/data/aircraft/turbo_lumber_evolution.json --out tmp/rolling-candidate
python tools/flight_log/flight_log.py compare docs/research/ground-physics/GP-02/rolling-2026-10-23/baseline.csv tmp/rolling-candidate/flight.csv --out tmp/rolling-comparison.json
```

## Verification and limits

[Checked-run records](checks.json) retain commands and log hashes; [regression summary](regressions.json) and [source identities](identity.json) identify the tested work. Passing suites: ground physics 48 checks, wheel/session 51, ground contact 22, friction 26, stiction 25, terrain 21, retractable gear 26, Timber ground 23, takeoff 8, checkpoints 92, trace metadata 411, and flight logging/replay 3,247. Lake contact checks also pass. The pre-fix and post-fix takeoff fixture outputs preserve the same lift-off result, 2.862 s at 24.05 m/s. Float64, transcendental, whitespace and large-file guards pass.

Two independent read-only reviews found no blocker in the correction. Review of low-speed propulsion did not confirm a new reachable turbine-map defect: the finite-fuel cutoff disables thrust before spool rundown leaves the running map. This is a bounded audit, not a proof of the entire simulator.

Airborne wheel braking remains the declared loaded-contact-only approximation. P-51/Avanti brake commands reach the wheel API, but a free airborne wheel retains its spin. Simply moving brake torque outside the contact branch would omit the matching body reaction; a general repair needs axle orientation and momentum coupling, including retract motion. The retraction contract currently supplies contact-point paths only. This limitation is retained in the [ground model guide](../../GP-05/README.md#remaining-limits), without inventing mechanical data.

These native tests do not claim full `app/test.sh`, visual, performance or physical qualification. The shared checkout's CRLF shell-script issue prevented the earlier WSL full-suite attempt; focused native runners were used here. Concurrent Corsair verification/research changes were preserved.

Baseline HEAD was `f929372c`. During verification, concurrent commit `e76a72f5` included this physics patch, tests and the GP-05 guide update alongside Corsair work. History was preserved. Final source hashes still match the tested identity; review the physics paths against the baseline rather than relying on that commit's title.
