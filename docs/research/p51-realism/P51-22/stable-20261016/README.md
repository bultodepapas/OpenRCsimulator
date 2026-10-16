# P-51-22 stable baseline evidence — 2026-10-16

This evidence preserves the known P-51-22 takeoff and inside-loop results at source commit `8b8574da009e3e47860adb6d44871402a760a4b5`. The P-51 remains experimental in the stable game; these documented aircraft-specific physics limits are known limitations, not general release blockers.

## Strict physical checks

The tests were run without `--allow-known-p51-22`, and the physical gates remain strict:

- `test_p51_ground.gd`: 13 checks, 1 failure. The right-rudder takeoff lifts off at 26.7 m/s after a 57 m ground roll, outside the 1.05–1.5 Vs band.
- `test_p51_handling.gd`: 17 checks, 2 failures. The eight-second loop accumulates 320° pitch; peak pitch is 43.6° and maximum sideslip is 19.5°.

The complete logs are `test_p51_ground.gd.strict.log` and `test_p51_handling.gd.strict.log`. Every non-P51-22 check in these runs passed.

## Recorded baselines

| Case | Duration | Samples at 240 Hz | Exact replay |
| --- | ---: | ---: | --- |
| Powered runway takeoff with the state-dependent right-rudder pilot | 12 s | 2,881 | complete; `solver_changed=false`; zero-difference comparison |
| Inside-loop fixture from 27 m/s and 150 m | 8 s | 1,921 | complete; `solver_changed=false`; zero-difference comparison |

The takeoff recorder runs the base fixture's park/idle setup and three-second rudder-free takeoff, then records the full twelve-second takeoff while the existing pilot computes each command from the current state. The loop recorder reproduces the handling test's hands-off and roll prehistory, trim, altitude, loop stick function, and per-tick commands.

Each ORFL has an export CSV and JSON report, a replay JSON report, and a comparison JSON. The replay CSV was used for the exact comparisons and omitted from this retained set to avoid duplicating the export CSV. The `source` path in retained reports is normalized to the sibling ORFL filename; result fields, source hash, and solver identity are unchanged. `receipt.json` records all retained artifact hashes and the Git tree/source identity. The source clone and Godot import cache are not included.

These traces are numerical software baselines. They do not establish physical validation or change the strict acceptance thresholds.
