# UI-06a-R1 — checkpoint trace origin

2026-10-08 · **Status: complete; focused regression and full integration passed.** Software evidence only; no pilot or physical acceptance.

## Reproduction and repair

A runway checkpoint restored into a newly created airborne session retained that destination's launch header: altitude **0.23905038815208 m**, but `launch_choice=airborne` and a trimmed-flight scenario. The reverse direction falsely claimed a runway launch. Physics restoration was correct; `restore_checkpoint()` left `_launch_metadata` from the destination's previous flight intact.

Flight checkpoint v1 contains physics and its configuration fingerprint, not the source flight's launch provenance. Successful restoration now clears inherited launch snapshots and identifies `launch_kind=checkpoint_restore`; the selected/original launch and original engine state are `unknown`. The scenario explicitly says `checkpoint replay (original launch unknown)`. Existing recording-start metadata and samples still describe the restored boundary. Rejected restores retain metadata, and reset uses the destination's persistent start recipe and records a new known launch.

The checkpoint format, physics, input conditioning and trace columns are unchanged. This deliberately does not add live-session saving or infer launch history from current altitude.

## Proof

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_runway_checkpoint_metadata.gd
```

The same regression ran outside `app/` before the repair: **14 checks, 4 failures** ([before](before.log)). Afterward: **14 checks, 0 failures** ([after](after.log)). Both cross-start directions, exact physics-state retention, rejected restoration, Recorder's first row and restart choice are covered by [the regression](../../../../app/tests/test_runway_checkpoint_metadata.gd).

**Full integration:** `XDG_DATA_HOME=/dev/shm/openrc-runway-followup app/test.sh` exited 0: all scripts parsed, 125 GDScript test processes passed, model/trace checks passed, and 30/60/144 fps state comparisons matched. Retained [suite log](app-test.log.gz) and [verification manifest](verification.json) identify the tested files. The linter reports zero errors and the same 12 pre-existing warnings. Concurrent G2-R1 propulsion changes were present during this run and are hashed in the manifest; this repair does not edit them.

The UI-06c export evidence remains evidence for its recorded executable hash. Those original packages do not contain this repair. The subsequent [UI-06c-R1 refresh](../UI-06c-R1/README.md) now delivers verified packages with the correction.

## Separate observation

A read-only UI audit found no runway-launch blocker; `test_ui_runway.gd` passed. An existing low-severity preference notice remains: future-schema settings report their read-only status to the console on initial Home, but the visible save warning appears only after Fly attempts to save. Keep any correction with the menu/preferences track; this repair changes replay attribution only.
