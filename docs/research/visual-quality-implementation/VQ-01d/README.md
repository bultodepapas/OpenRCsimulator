# VQ-01d / CAM-22 — moving visibility reference foundation

2026-10-14. Capture/validation/packaging tooling and four native reference clips
delivered. **Human orientation/readability acceptance remains pending.** No camera
law, material, aircraft model, simulation or production setting changed.

## Retained reference

[Open the numbered clips](clips/README.md) before inspecting the answer key.
Each lossless APNG contains **60 frames, 1280 × 720, 30 samples/s, 2 seconds**.
The packager decodes every frame and compares its RGBA pixels with the source PNG,
including individual durations. Source manifests, frame hashes, camera transforms,
process logs and package summaries are in [checks](checks/verification.json).

Two matched pairs use the Stik at 100 m from the pilot's eyes, traveling through a
3°–15° azimuth arc. Prescribed render attitudes are knife-left and inverted.
Each pair keeps the exact positions/orientations and toggles only the existing
pilot rig's autozoom. Manual zoom remains 1. The two requested elevation bands are
2.3° and 10°; these are synthetic design values, not observed flight trajectories.

| Existing pilot law | Vertical FOV | Face-on reference span |
| --- | ---: | ---: |
| Autozoom on | 20.7054° | 30.0000 px |
| Autozoom off | 50° | 11.7528 px |

The reference span uses the runtime model extent and existing PilotCamera formula.
It is **not visible aircraft pixel area**. Each frame also records the projected
model AABB envelope; the producer rejects out-of-frame geometry or CG tracking
error greater than 0.1 px. Foreground occlusion and pixel contrast are not qualified.
The old L6c background labels cannot establish current background coverage:
trees and distant terrain changed. Labels remain requested elevations only.

## Identity and capture conditions

Source is the same archived **5f7f4ad529940743bdc16e3d9691243a8a1c6cd8** used for
[VQ-02a](../VQ-02a/README.md), with its pinned Windows import normalization.
Every archived input was rechecked against the archive or its recorded imported
sidecar hash. The shared tree's later changes are outside this reference.
[Verification](checks/verification.json) pins the source archive, actual engine,
capture/runner/packager/test sources and clip hashes.

Godot **4.7.2 ed1daf0bf**, native Compatibility, NVIDIA RTX 3090 / 610.88, 4× MSAA,
Pillow **12.3.0** from the existing visual-tools dependency set. The app's
CameraRig/PilotCamera, model builder, CG conversion and default world are reused.
Capture uses an isolated SubViewport and explicit draws with the native window
minimized. Six matched frames before/after minimization are byte-identical.
Two separate six-frame captures also match both pixels and recorded metadata.

The world is fixed legacy daylight, scenery high/on and landscape upgrade on.
Shader time is held at zero; node processing, scenery audio and birds are disabled.
No simulation, flight input, aircraft shadow, propeller rotation/blur, HUD or night
kit is present. Camera motion reveals the retained scenery; this is not full-flight
or weather-motion evidence. Offline capture duration and APNG timing do not establish
display refresh, latency, frame pacing, native flight acceptance or a speedup.

## Checks and rejected collection

- **13 Python tests pass**, including path/hash failures, frame sequence/time,
  non-finite and invalid geometry metrics, image dimensions, absence of pixel
  motion, exact APNG reconstruction and preservation of identical adjacent frames.
- Four native guards reject existing output, headless rendering, invalid frame
  count and unknown pose with exit 2; rejected new destinations remain absent.
- Four final captures pass the completion marker, image/metadata validation and
  complete-process log checks, with no engine errors or warnings.
- One earlier sky collection ended with exit 0 after 35 frames, without a final
  manifest or completion marker. The runner rejected it. Its
  [log](checks/incomplete-process.log) and [process record](checks/incomplete-process.json)
  remain retained; the early-termination cause is unknown.

The Python fixture suite and native guards validate these tools; no full app suite,
hardware acceptance or human results are claimed. Raw per-frame PNGs stay in the
local capture folder; the retained lossless APNGs preserve every decoded frame.

## Next acceptance work

This is a small reference set, not the full CAM-22 experiment. Before material or
camera adoption: complete aircraft/distance/view/day-night coverage on the selected
integration snapshot; verify actual background composition and contrast; collect
owner orientation answers and controlled response times. The four-clip worksheet is
a qualitative review aid only, with no pass threshold or automatic latency claim.
Re-capture after relevant world/model/camera changes; do not compare different
source identities as if only the proposed material changed.

Commands and limits belong to the
[tool contract](../../../../research/performance/README.md#moving-visibility-reference-vq-01d--cam-22).
The capture follows Godot's
[Camera3D projection contract](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
and [explicit RenderingServer draw API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw);
the pinned native captures establish the exercised behavior.
