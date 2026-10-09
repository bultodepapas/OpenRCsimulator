# UI-06a — persistent runway launch session

2026-10-08 · Software evidence · Godot 4.7.2.stable.official.ed1daf0bf. This step proves the selected-start session contract and regression behavior. It does not prove pilot handling, takeoff, landing, or physical model accuracy.

## Reproduce

From the repository root:

```sh
.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path app --script res://tests/test_start_choice.gd
```

Result: **34 checks, 0 failed.** The test selects runway before setup, verifies threshold state and launch metadata, distinguishes launch data from a later Recorder snapshot, and covers named pause holds, Restart, crash recovery, manual throttle input, hot reload, refusal paths and the legacy one-shot helper.

## Regression checks

All commands below ran with the same pinned executable and exited 0:

| Command | Result |
| --- | --- |
| `--script res://tests/test_runway_start.gd` | 19 checks, 0 failed; 10 s idle hold stayed below `1e-6 m/s` and `1e-6 rad/s`, with no measured movement. |
| `--script res://tests/test_trace_metadata.gd` | 171 checks, 0 failed. |
| `--script res://tests/test_checkpoint.gd` | 90 checks, 0 failed. |
| `--script res://tests/test_ground_start_integrity.gd` | 254 checks, 0 failed. |
| `--script res://tests/test_golden.gd` | 4 golden flights, 0 failed; airborne replay outputs match existing fixtures. |

The whole-app Godot script linter reported **0 errors and 0 parse errors**. Its 12 warnings are existing missing-path fixtures/references and one `get_node()` inference warning in `scenery/capture_views.gd`; none points to the session or the new test.

The focused test also verifies that an invalid data reload and a valid-but-unsupported runway aircraft reload preserve the active checkpoint and launch metadata. The latter is refused before the `resetting` signal, so an active Recorder remains open. A valid Stik reload resolves the threshold and wheel anchors again instead of reusing stale support data. A named pause hold keeps a successful reset paused until the hold is released.

## Limits

The supported explicit runway route is the `jensen-das-ugly-stik-60` on field `default`. Unsupported aircraft, fields, missing runway geometry and failed equilibrium return an explicit error and stay stopped. `reset_on_runway()` remains a one-shot compatibility helper and still restores the ordinary airborne start when its requested solve fails. Automated tests and golden replay are software evidence; owner flight, radio behavior, taxi/takeoff, circuit, approach, landing and physical validation remain pending.
