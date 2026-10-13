# D6e-R1 — reported climb and pilot elevator trim

2026-10-13. **Status: manual trim implemented and verified; the reported hands-off Timber climb at 25% throttle is not reproduced and remains unresolved.** Main physics/input track; this report does not close a flight-validation gate.

The owner reports a common tendency to climb, especially Timber at low power with keyboard controls and no elevator input; the Stik feels incorrectly trimmed. The initial power-step hypothesis alone does **not** explain that report. Launch choice and the exact executable/source version of the observed flight remain unconfirmed.

## Evidence

Production `FlightSession`, real servos/propulsion/downwash and RK4 at 240 Hz, normal input rates. Five catalog aircraft, four conditions each, ten simulated seconds. Neutral keyboard samples are applied before each tick. [Reproducible probes](../../../../research/flight-dynamics/climb-trim/README.md), [numerical summaries](results.json).

All five maintain starting altitude within 2e-9 m in calm air at solved power. Their solved powers are different: Stik 28.44%, Extra 35.72%, P-51 14.05%, jet 8.60%, Timber 40.94%. A common throttle percentage is not a common equilibrium.

| Condition, 10 seconds | Stik altitude change | Timber altitude change |
| --- | ---: | ---: |
| Calm, starting power | 0.000 m | −0.000 m |
| Calm, 25% throttle | −4.574 m | −11.439 m |
| Gentle weather, 25% throttle | −4.678 m | −11.914 m |
| Calm, 50% throttle | +9.330 m | +10.273 m |

The complete `main.tscn` scene, field, soft contacts, gentle weather, **real keyboard polling and engine physics callbacks** reproduce the 25% descent values exactly. Recorded commands remain neutral plus the solved trim, with `cmd_throttle=0.25`. This rules out a startup climb in those tested current-source conditions; it does not invalidate the owner's observation of another flight.

`Trim._evaluate` and the runtime share `Dynamics`; pilot trailing-edge-up angles are converted once to the aerodynamic convention. No common elevator sign or gravity defect was found. A nose-up attitude is distinct from a rising flight path: the level starts have approximately 4.3° pitch/angle of attack. No camera-perception explanation has been established for the report.

## Options and chosen improvement

- Reducing lift, changing CG/incidence or adding a universal nose-down moment has no supporting reproduction and would disturb the verified equilibrium. Rejected.
- Automatic altitude hold or continuously adapting trim would change manual RC flight into an assisted mode. Rejected for this repair.
- A pilot-controlled fixed elevator trim addresses a confirmed usability gap: the old session solved trim at launch but offered no keyboard adjustment for another operating point. Implemented independently of the unresolved report.

Page Up trims nose down; Page Down trims nose up, 0.1° per fresh key press. The command offset is independent of rates/expo and bounded by the aircraft's physical throw. Existing servos apply it on the next sampled ticks. The operation changes no state, force, throttle or aerodynamic coefficient. Invalid, paused, held, crashed, calibration and recorded-input sessions refuse it. Reset restores solved trims and initial servo positions. Existing trace commands/servo columns and recorded-input checkpoints already capture its physical effect; no new replay format is introduced.

At a controlled 40 m/s jet initial condition, preserving its old 29 m/s elevator trim gains 46.519 m in five seconds; applying the solved faster-cruise correction through the new trim API holds height within 1 mm. This counterfactual verifies the new trim path, not a fix for the Timber report or real-aircraft fidelity.

Power, elevator and trim interact with speed and flight path; the chosen separation follows the [FAA Airplane Flying Handbook, chapter 4](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/05_afh_ch4.pdf). Actual RC coefficient and handling qualification remains separate.

## Verification and remaining diagnosis

Native Windows, pinned Godot 4.7.2: `test_pilot_trim.gd` (68 checks), trim (14), trim integrity (700), regime consistency (50), rates (21), session guards (32), runway start (19), controls-reference, Help EN/ES and real key-event tests pass. Help still fits the 600 px content region at 720p in both languages. Checkpoint (92), replay-integrity (153), density-trim (35) and electric-session (86) checks also pass. The full Bash/WSL suite and physical pilot validation were not run. Existing UI teardown ObjectDB warnings remain.

No aircraft data or golden-flight references were changed. Other tracks modified/committed the shared checkout during this work; test evidence is scoped to the listed runs, not to a clean-tree release.

To resolve the original symptom, identify the exact executable/build and retain a **T** recording of the actual climb with aircraft, launch choice and controls unchanged. Compare `cmd_pitch`, `srv_pitch`, throttle, RPM, airspeed, vertical velocity, weather and initial-state identity. A current-source low-power descent is insufficient evidence to declare the reported climb fixed.
