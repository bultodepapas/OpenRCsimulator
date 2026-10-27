# GP-12: fixed-gear shared brake input

2026-10-26. `FlightSession`, `Main` and legacy `Trace` now distinguish brake
hardware from gear retraction. Applied wheel-profile availability, positive
torque and matching quantity provenance admit a shared fixed-gear command.
The input law is `fixed-gear-shared-wheel-brake-input-v1`, brake index 4, with
optional flaps at 5. No gear target, gear auxiliary state, hardware estimate or
second friction law is introduced. Existing unbraked/retractable layouts remain.

Main B, external controls, checkpoint/configuration/metadata and restore use the
same role. Positive commands require admitted hardware. Zero releases still
clear demand when hardware becomes unavailable; an invalid mixed input packet
applies nothing. Pause/focus release, reset/reload, actual grounded wheel torque,
failed-step rollback and finite-fuel continuous-state offsets are checked.

Legacy Trace adds `cmd_wheel_brake` under outer v17 and records
`fixed_brake_base_trace_format`. Named roles, exact law/index, bounded JSON,
optional flap placement and conflicting gear claims are validated. The focused
Python inspector explicitly reports `physics_validation_available=false`.
Existing physical validators retain their historical version/equation gates;
they do not ignore brake commands to manufacture validation. The consumer matrix
under `construction/` identifies their scope. Old unsupported Trace cases remain
refused without the new law.

## Installed verification

| Check | Result |
| --- | --- |
| Focused Session/Main/Trace/checkpoint/recording suite | 256 assertions, 0 failures |
| Existing flight-log suite, six aircraft and 260 ticks each | 3,247 assertions, 0 failures |
| Trace role inspector and hostile inputs | 13 Python tests, pass |
| Regular test-script registration | Bash syntax passes; 13 Python tests invoked directly |

Both installed Godot runs use warnings-as-errors and have no engine diagnostics.
Authored-aircraft data notices still describe existing experimental models.
The original focused prototype counts 140/237 and the repeated 256 projection are
historical executions, not extra unique coverage. The initial wrong wall-clock
hash fixture and its failed check remain retained; the permanent old-output
oracle normalizes only `created_utc` to a declared presentation sentinel.
Physical checkpoint and continuation outputs are not normalized.

The immutable oracle was captured from old Session `2bc02a0f...` and Trace
`1c529262...`, before production promotion. The installed test reads it rather
than comparing the current owner with itself. New synthetic authoring/profile
inputs go through existing Data/WheelProfiles validation at test time; their
provenance says software fixture. No stock aircraft or profile bytes changed.

Six earlier immutable ORFL baselines in the sibling `input-role-replay` cohort
were compared with the candidate: 30 assertions across 96 ticks, all unchanged
sample rows, and `solver_changed=true` on every tape. This is bounded candidate
compatibility, not exact-source replay. Two installed fixed-brake recordings,
four ticks each, are retained here with exact owner restore/replay checks. The
existing 260-tick recordings remain in ignored tmp; their report is retained.
The custom fixture owner is required to restore the synthetic brake hardware.
Root added `--retain-evidence` to the test after its default cleanup removed the
first successful run's outputs. The retained run again passes 256 assertions;
default cleanup remains unchanged. This test-only followup is separately pinned.

`app/test.sh` automatically discovers the GDScript suite; root also added the
Python inspector tests to its existing integration partition. No full-suite
pass, physical braking calibration, stock hardware qualification, airborne or
differential braking, Workshop UI or performance claim follows from this slice.

## Evidence

`source/` is the installed projection; `before/` preserves the three runtime
sources and test script before promotion. Construction pins, minimal review
diff, terminal checked reports, failed development reports and current ORFLs
are retained. Source snapshots are selected evidence, not a complete repository
closure; historical construction scripts contain their executed workspace paths.
The manifest binds raw payload bytes. Folder attributes and a disposable Git
autocrlf clone check verify transport without staging the shared working tree.

## Per-OS legacy outputs (2026-10-27)

The legacy output fixture was captured on Windows. The Linux build of the same
pinned engine (Ubuntu 24.04, glibc 2.39, WSL2) never reproduced it, even at the
promotion commit: p51d differs in all four digests, gp-extra in all except the
launch checkpoint. Separately, NITRO-06-R3 (`20662f264`, the documented
closed-form carburettor root) moved all four gp-extra digests on both OSes.
`outputs.gp-extra-300s-60` therefore holds the R3 values.

[`construction/reconstruct_legacy_reference.py`](construction/reconstruct_legacy_reference.py)
rebuilds the old owner from `552d683ea^`, plus `before/` and two retained
byte-exact copies. It verifies all 400 app inputs in `loaded-source-pins.json`
and optionally applies only the R3 carburettor.
[`construction/capture_legacy_outputs.gd`](construction/capture_legacy_outputs.gd)
runs the test's unchanged legacy body.
[`construction/merge_legacy_os_capture.py`](construction/merge_legacy_os_capture.py)
records an OS's differing digests in `outputs_by_os.<os>` and its provenance in
`os_captures`.

On Windows, the reference reproduced every original digest, and the reference
with R3 reproduced current HEAD. On WSL Linux, the reference matched Linux at
`552d683ea`, and the reference with R3 matched Linux HEAD on all four aircraft.
The test selects digests by `OS.get_name()`, compares them exactly and fails on
an OS without a capture. Identity is per pinned runtime and OS. The ubuntu-24.04
CI image is not separately captured. Its earlier jensen and sebart differences
did not reproduce under WSL and need a CI run to confirm. The sealed
`manifest.json` predates these files and is unchanged.
