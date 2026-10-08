# CR-01c — Render the reconstructed crash pose

2026-10-08 · **Status: focused checks and captures verified; full-suite/integration validation in progress.** Continuation of [CR-01b](../CR-01b/README.md) under [CR-01](../../../CRASH-DAMAGE-PLAN.md). [Reproduction tools](../../../../research/crash-damage/cr-01c/).

## Change and boundary

The real flight scene now draws `impact.crossing.position_ned` and `attitude` while a crash record exists and the reconstruction is available. The position is the airplane's **CG**, not the ground-contact point. The existing model-origin offset, shadow projection and pilot/inspection camera all receive that same pose through `_render_pose()`.

An unavailable or absent crossing draws the snapshot's detected state. A legacy crash without a snapshot draws the current simulation state. No interpolation fraction is consulted in either crash fallback. Synthetic review poses and the scripted circle retain their existing priority; ordinary flight retains its original interpolation. No simulation state, detector, force, aircraft data, pause/countdown/reset policy, UI wording or trace/checkpoint schema changes.

This changes only rigid-body presentation. The reconstructed pose remains an estimate along the CR-01b interpolation path, not the physical instant of impact. Controls, gear and propeller retain existing render behavior; no sub-tick actuator state or crossing velocity is inferred. Hull points approximate the airframe: putting the selected hull point on the flat plane does not guarantee every triangle of the mesh is clear. Component labels and crossing-time kinematics remain open in CR-01.

## Verification

The isolated candidate starts at `959eb8a8dea280a382be372265648bc2b5a1de73` and changes only `app/main.gd` plus a new test and UID. Independent Luna Max review checked the pose seam and lifecycle boundary.

- [84 real-scene checks](focused-tests.log) across all four aircraft: actual session detector, crossing CG/attitude, model CG offset, selected hull point within 2 µm of the rendered plane, shadow transform, both camera modes, simulation/aux preservation, menu hold, refused Continue, exact 360-tick automatic restart, active-crash manual reset, checkpoint restore, unavailable/missing snapshots, and ordinary/scripted/synthetic routes. This is render float32 tolerance near the runway, not physical accuracy.
- [Three deliberate rendering defects](mutations.json) fail on disposable copies; the control passes. Defects ignore the crossing, use the contact position as CG, or use previous/current interpolation for an unavailable crossing.
- [All four numeric three-second traces](comparison.json) match the baseline byte-for-byte (721 samples each). The reused CR-01a comparison tool also records unchanged physics/session benchmark paths; its snapshot timings omit crossing construction and are not rendering costs.
- [Pose-selector timing batches](pose-timings.json), five × 1,000 calls per aircraft/regime: candidate ordinary-flight medians 28.6–48.6 µs, crash 24.3–38.9 µs; baseline 27.9–28.6 and 28.1–31.6 µs respectively. These are selector-only headless batch means under concurrent host load, not frame-time percentiles or an attributable speedup/regression. Rendering adds no work to physics ticks. Target-GPU acceptance remains open.
- [Lint counts](lint-counts.json): zero errors and the same 12 pre-existing warnings. Full-suite and shared integration results pending.

## Rendered evidence

Five production-scene captures were repeated in separate software-rendered processes; PNG bytes and [transform/image manifest](captures/captures.json) match exactly. The fixtures manufacture previous/current states to isolate the presentation contract; their displacement and stored velocity are not a dynamically consistent flight. They do not establish physical crash realism.

| Fixture | Reconstructed pose | Detected-state reference, same camera |
| --- | --- | --- |
| Banked | [Crossing](captures/banked-crossing.png) | [Detected](captures/banked-detected-reference.png) |
| Level | [Crossing](captures/level-crossing.png) | [Detected](captures/level-detected-reference.png) |

[Banked pilot view](captures/banked-pilot-crossing.png) checks the other production camera route. HUD/panel are hidden only in this research harness to isolate the images. The detected-state references explicitly draw the saved tick pose; they are controlled comparisons, not claims about an old build's frame interpolation.

The selected point's rendered heights are −2.98e−8 m (banked) and 0 m (level), versus −0.546 m and −0.203 m in the detected references. The verifier checks nonblank images, file hashes, dimensions, plane residuals and equal camera/state data in each pair. The first capture run emitted the known intermittent ObjectDB exit warning; the [verbose repeat](capture-repeat.log) was clean. No engine errors occurred. Software captures do not close the owner's readability or GPU gates.

## Reproduction

Run from the repository root; choose separate output directories for concurrent runs:

```sh
$(app/get-godot.sh) --headless --path app --script res://tests/test_crash_pose.gd
python3 research/crash-damage/cr-01c/mutations.py --godot "$(app/get-godot.sh)" \
  --candidate /path/to/imported-candidate --output /tmp/cr01c-mutations.json
timeout 180 xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --rendering-driver opengl3 --script "$PWD/research/crash-damage/cr-01c/capture.gd" \
  -- --cr01c-out=/tmp/cr01c-captures
"$(app/tests/visual-env.sh)" research/crash-damage/cr-01c/verify_captures.py /tmp/cr01c-captures
$(app/get-godot.sh) --headless --path app --script "$PWD/research/crash-damage/cr-01c/benchmark.gd"
```

The suite uses the same validation-only 180 s process deadline as CR-01b: its unchanged baseline landing test took 75.51 s and exceeded the normal 60 s deadline. The repository runner and all assertions remain unchanged.

```sh
mkdir -p /tmp/cr01c-deadline-bin
install -m 755 docs/research/crash-damage-investigations/CR-01b/timeout-wrapper.sh /tmp/cr01c-deadline-bin/timeout
PATH="/tmp/cr01c-deadline-bin:$PATH" XDG_DATA_HOME=/tmp/cr01c-suite-user app/test.sh
python3 research/crash-damage/cr-01a/compare.py --godot "$(app/get-godot.sh)" \
  --baseline /path/to/baseline-clone --candidate /path/to/candidate-clone \
  --output /tmp/cr01c-comparison.json
```

The image verifier uses the repository's pinned visual Python environment (Pillow 12.3.0); both capture sets pass there. The mutation tool copies an imported candidate including its small import cache; it requires semantic assertion failures and refuses parse/runtime errors as proof. The ordinary `--capture` route advances and draws simulation state directly, bypassing crash detection; it is deliberately not used to claim crash-pose acceptance.
