# Gamepad readiness solver replay

2026-10-15. This evidence checks that the controller-readiness UI change leaves the fixed-wing solver unchanged. It follows the [flight logging and replay workflow](../../../FLIGHT-LOGGING.md).

The frozen recording is `baseline-stik-glow-61fx-2t.orfl`, generated with the existing `app/tests/test_flight_log.gd` harness. That fixture disables live input and directly supplies its deterministic post-conditioning command tape to `sim.inputs`; it does not exercise a physical gamepad, `RcInput`, or the readiness UI. The recording was captured during this change, so it is not evidence of the old input route. It is used only as the same-tape solver reference.

The recording contains 260 simulated ticks and 261 rows. Its SHA-256 is `c3ab2c5c85e0ed514ccd8a7c8da2e9c91058e3299d6d8d4ab18e4da1588b6df5` (266,584 bytes). Export and exact replay both report `status: ok`, `complete: true`, and `solver_changed: false`; recorded and current solver SHA-256 are both `ad3fdaa7049d0c3b7e88c5baa062f30c601650fdddf584c680cb75d32d5e09ca`. CSV comparison reports 261 matching rows, no first divergence, and zero maximum and RMS errors for position, velocity, angular rate, and quaternion angle.

Reproduce from the repository root:

```powershell
& '.\.tools\Godot_v4.7.2-stable_win64_console.exe' --headless --path app --audio-driver Dummy --script res://tests/test_flight_log.gd -- --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/gamepad-ready/baseline
python tools/flight_log/flight_log.py export tmp/gamepad-ready/baseline/stik_glow_61fx_2t.orfl --out tmp/gamepad-ready/export
python tools/flight_log/flight_log.py replay tmp/gamepad-ready/baseline/stik_glow_61fx_2t.orfl --out tmp/gamepad-ready/exact
python tools/flight_log/flight_log.py compare tmp/gamepad-ready/export/flight.csv tmp/gamepad-ready/exact/flight.csv --out tmp/gamepad-ready/exact-comparison.json
```

The full six-aircraft fixture run exited 1 with 2,987 checks and one failure: `self contained replay prepares` for `sebart_avanti_s_a200`. The Stik fixture completed successfully, and its separate export, exact replay, and CSV comparison all passed. This establishes software replay equivalence for this tape; it does not validate physical realism or controller hardware behavior.
