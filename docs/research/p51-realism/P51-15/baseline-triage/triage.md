# P51-15 baseline triage

Status: complete.

This is a bounded failure comparison, not a full baseline suite. The frozen candidate run recorded 226 results: 224 exited successfully and two failed (000 and 144). Only one result reports engine errors. Each baseline replay used the pinned Linux Godot 4.7.2 binary and unique XDG data, config, and cache directories.

The isolated baseline app was copied from the frozen Linux clone with its Linux `.godot` cache. I restored only `data/aircraft/p51d_mustang_120.json` and `tests/p51_envelope_base.gd` from `.tools/p51-realism-baseline/app`. The direct baseline runs used `--headless --path .tools/baseline-app --script res://tests/<test>.gd`.

| Candidate result | Failure and baseline comparison | Scope |
| --- | --- | --- |
| [`000.log`](../linux-suite/000.log), aggregate `app/test.sh` attempt, exit 1 with engine errors | `test_atmosphere_flight.gd` reports `FAIL reset recomputes a fresh trim for the extreme density` (137 checks, 1 failed), then `Invalid access to property or key 'format' on a base object of type 'Dictionary'` in `_failure_recovery` at line 184, called from `_initialize` at line 91. The direct baseline replay reproduces the same failed check and script error at the same lines. Baseline log: [`test_atmosphere_flight.log`](test_atmosphere_flight.log); it also reports 10 leaked ObjectDB instances and 4 resources still in use at exit. | Shared extreme-density/Stik reset and failure-reporting path. Reproduces with the P51 data and test-base files restored, so those P51-specific files do not account for this failure. |
| [`144.log`](../linux-suite/144.log), `test_time_of_day_render_update.gd`, exit 1 without engine errors | Reports `FAIL scenery hook follows its configured opt-in state`; summary: `TOD-09b render update: 94 checks, 1 failed; scenery=true`. The direct baseline replay reproduces the same failure and summary without engine errors. Baseline log: [`test_time_of_day_render_update.log`](test_time_of_day_render_update.log). | Frozen snapshot's time-of-day/scenery integration check. It reproduces with the P51 data and test-base files restored, so those P51-specific files do not account for this failure. |

The P51-specific `test_p51_envelope.gd`, `test_p51_ground.gd`, and `test_p51_handling.gd` results (088–090) all exited 0 without engine errors. Final downstream entries 199–225 are 27/27 successful, each with exit 0 and no engine errors.

The baseline copy retains the frozen candidate clone's other files; this comparison tests whether the failures depend on the two restored P51 files. I did not rerun the full baseline suite. Concurrent live landscape/document changes are outside the frozen suite snapshot.
