# CAM-02 — explicit pilot-camera singularities

2026-10-23. Follow-up to [CAM-02](../CAM-01-10/README.md), supporting
[AAA presentation work](../../../plans/advanced-graphics.md). Adopt this narrow
orientation correction; retain ordinary pilot framing and the zoom law.

## Defect and correction

`PilotCamera.aim` previously always supplied world-up to `look_at`. Directly
overhead, underfoot and near-vertical targets produced colinearity warnings.
The pinned engine still aimed at these targets; this was not a demonstrated
tracking failure. An eye-coincident target produced an engine error and left
the orientation unchanged.

For targets within 1 micrometre of the eye, explicitly keep the previous
orientation. Within the tiny pole cone (normalized direction × world-up squared
less than `1e-10`), derive up from the previous screen-right axis. If that axis
is itself parallel to the target direction, use north-up. Elsewhere execute
the original world-up `look_at` call. Position and FOV calculations are unchanged.
Pole roll is intentionally different from the engine's implicit fallback.

## Evidence

Windows, Godot **4.7.2-stable**, RTX 3090, NVIDIA **617.42**. The retained
[source identity](identity.json) identifies the shared tree. This camera task
did not edit the unrelated physics work present in the shared tree/commit.

| Check | Result |
| --- | --- |
| Initial negative control | All 47 then-current assertions passed, but the checked runner failed on three colinearity warnings and one coincident-target engine error. Retained in `checks/before/`. |
| Expanded camera views | **52 checks pass**: both poles, near-pole target, previous-right retention, parallel-right fallback, coincidence, exact ordinary basis parity, zoom transitions, chase and orbit. |
| Camera math | **21 checks pass**. |
| Application input route | **19 checks pass**; camera input leaves simulation state untouched. Existing aircraft-data advisory text remains in the log. |
| Native Compatibility studio | Three actual **1920×1080** PNGs; the production Stik and camera rig remain centered and finite at ordinary, overhead and underfoot poses. FOV 50°, aim dot 1.0 in all three. |

All final focused runs use the checked runner with warnings treated as errors;
no engine warnings/errors were emitted. Logs and verdicts are in `checks/`.
The baseline assertion suite predates the final screen-right/fallback assertions;
the retained baseline is diagnostic evidence, not a claim that the final suite
passed on the old implementation. Independent Luna Max review found no blocking
issue in the runtime and initial regression diff.

The [capture fixture](capture.gd) reuses the production aircraft builder and
camera rig in a static studio. [PNG metrics](standard/report.json),
[ordinary view](standard/ordinary.png), [overhead view](standard/overhead.png)
and [underfoot view](standard/underfoot.png) are retained and visually inspected.
The underfoot pose is a mathematical camera case, not an aircraft underground
in a gameplay scene.

## Reproduce

From the repository root:

```powershell
python tools/godot/run_checked.py --timeout 180 --warnings-as-errors -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script tests/test_camera_views.gd
# Repeat for tests/test_camera_math.gd and tests/test_camera_route.gd.
python tools/godot/run_checked.py --timeout 120 --warnings-as-errors --require-text 'camera pole native captures passed' -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --rendering-method gl_compatibility --audio-driver Dummy --resolution 1920x1080 --script C:/DEVELOPMENT/OpenRCsimulator/docs/research/camera-views/CAM-02-poles-2026-10-23/capture.gd -- --out=C:/captures/camera-poles-new
```

Adjust absolute paths; the capture destination must not already exist. To
reproduce the defect, restore only the unconditional world-up `look_at` in a
disposable checkout and run the expanded view tests. Do not modify the active
shared tree for the negative control.

## Limits

`wsl -d Ubuntu -- bash app/test.sh` and `app/capture.sh` stopped before executing
checks because this Windows checkout has CRLF shell scripts (`pipefail\r: invalid option name`).
The full Linux test/capture campaign is not claimed. Native whole-tree parse
results are retained separately in `parse.json`.

These stills do not prove continuous overflight comfort, motion readability,
performance, or High/platform qualification. Outside the tiny pole cone the
existing world-up orientation law still applies; this patch does not smooth its
roll transition on an overhead crossing. CAM-22 remains open. No flight-law,
control, physics-data or golden-flight change belongs to this patch.
