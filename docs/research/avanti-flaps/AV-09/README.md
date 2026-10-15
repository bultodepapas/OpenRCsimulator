# AV-09-F flap evidence

2026-10-15 · This report records the flap implementation’s software and model-sensitivity evidence. SebArt’s [Avanti S manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) lists 0°, 20° and 50° settings and elevator-down mixing for the two deployed positions. The simulator geometry and aerodynamic coefficients remain estimates; see the [AV-06 reference review](../../avanti-s-av06-aero-references.md).

## Paired replay

The reproducible run is in [evidence-2026-10-15](evidence-2026-10-15/evidence_manifest.json). Its gain-0 sensitivity control and gain-1 candidate are generated from the same AV-06 source and have identical aircraft data apart from `flaps.aerodynamic_gain`. Gain 0 suppresses flap aerodynamic loads while the actuator and accepted commands still operate; it is not a calibrated clean-aircraft model. The candidate data hash is `387047f77349b61fe0eb463a93794b50d31ec76c65087f0d3cb3f9fe402f7e75`.

Each pair uses a 23-second, time-indexed tape: 3 seconds clean, 3 seconds at 20°, 7 seconds at 50°, a 1.5-second pitch pulse, 2.5 seconds recovery, 4 seconds retraction and 2 seconds clean. Separate recordings at 240 and 480 Hz use the same physical-time command schedule. At each rate, the gain-0 log has a complete exact replay (`solver_changed: false`) and the candidate has a complete explicit open-loop replay (`solver_changed: false`). Accepted commands and actual flap AUX histories match within each pair. At common segment boundaries, 240/480 candidate position components differ by at most 0.0524 m, TAS by 0.0086 m/s and angle of attack by 1.84e-5 rad; actual flap fraction matches. These are integration-step comparisons, not separate pilot flights.

All four traces start 500 m above a flat sea-level runway datum. The runner enforces a 100 m minimum AGL; the observed minima were 179.05 m for gain 0 and 478.41 m for the candidate. This is a high-altitude actuator/load response tape, not a takeoff, approach or landing profile.

The older, pre-feature Avanti `.orfl`, source JSON, export and exact report are retained under `evidence-2026-10-15/historical_prechange/`. Its original exact replay was complete under the old solver. Replaying it with the preserved old raw aircraft data under the current solver is explicitly candidate mode with `solver_changed: true`; the current candidate’s CSV is byte-identical to the prechange exact CSV (261 rows). This preserves the historical exact claim without relabeling a changed-solver candidate as an exact replay.

## Model response

The [static model probe](evidence-2026-10-15/static_model_probe.json) solves 1-g lift and pitch-moment equilibrium at fixed speed and density, including the authored elevator mix; required thrust is the resulting aerodynamic drag, not a solved propulsion trim. At 24 m/s, clean trim is 5.99° angle of attack and 12.83 N required thrust. With gain 1, 20° flaps trim at 1.60° and 14.87 N; 50° trim at −0.006° and 22.96 N. At zero pilot pitch, the authored mixer commands 8% and 20% of full elevator travel downward at 20° and 50° respectively. At full upward pilot command, 92% and 80% of nominal upward travel remains. This is geometric throw remaining, not measured pilot authority.

At a fixed 27 m/s, 7° angle of attack and zero net elevator deflection, flap increments are +68.7 N lift / +4.50 N drag at 20°, and +124.0 N lift / +36.81 N drag at 50°. The isolated wing section-couple plus panel-drag-arm change is negative My (nose-down in FRD), while full-aircraft ΔMy is positive in this run because it also includes tail-wake redistribution. The probe keeps those quantities separate. Its broad 0–70° lift sweep and implied one-g speeds include post-stall model samples; they are not measured stall onset or landing-speed guidance.

## Verification

The retained [core results](evidence-2026-10-15/verification/core-results.json) show 15 simulation, checkpoint, golden-flight, surface, actuator, downwash, ground-effect, aero and turbine suites passing. Selected supporting logs are stored alongside it: the AV-09 aero test reports 28 checks, the session test 36, gear-trace test 21, metadata test 343, and legacy trace test 37, all with zero failures. Python atmosphere checks (7), column checks (4) and flap-trace acceptance (1) also pass. The UI capture is [full-flaps.png](ui/full-flaps.png).

Reproduce the paired run with:

```powershell
python research/avanti-s/av09-flaps/capture_pair.py --out docs/research/avanti-flaps/AV-09/evidence-reproduction
```

Choose a fresh output directory; the runner refuses to overwrite evidence. It uses the retained prechange artifacts and the pinned engine, or an explicit `--godot` path.

The evidence is a software/model sensitivity result. Independent aircraft measurements and pilot evaluation are still required before claiming Avanti-specific aerodynamic calibration or flight validation.
