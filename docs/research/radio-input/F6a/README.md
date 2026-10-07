# F6a — Live-flight latency marker

**Status:** implemented and verified, 2026-10-07. F6 physical measurements remain open.

## Use

```bash
$(app/get-godot.sh) --path app -- --latency-patch --latency-axis=0 --latency-threshold=0
```

This starts the normal airborne flight with an optional 192 px square beside the flight panel. Move the selected axis first. Black means raw input is below the threshold; white means at or above it. Gray means no usable live sample: disconnected, untouched axis after connection, paused/held/crashed/faulted flight, calibration, disabled input or non-finite sample. Normal restart retains the marker. It belongs to that flight and disappears when the flight ends.

The axis is the Godot raw index (0–9), not the calibrated channel assignment. Default axis 0 and threshold 0 represent the midpoint of a bipolar −1…+1 range; a 0…1 trigger needs an explicit threshold such as 0.5. Inversion, trims, expo, deadbands, servo lag and throttle arming do not affect this raw-input diagnostic. Use a slowly observed crossing to locate the corresponding physical stick position; do not assume a radio's trimmed/mixed output crosses zero at mechanical center.

Flags require a live-flight route. Trace, capture, scripted, frame-time and visual-pose modes are rejected before flight or output creation. Invalid axis/threshold or a parameter without `--latency-patch` exits nonzero. The marker is absent by default and saves no report or settings. It does not change VSync, the frame cap or the input accumulation setting.

## Observation point and implementation

`FlightSession` already polls `Input.get_joy_axis` through `RCInput` at physics priority −1. Simulation advances at priority 0; the marker reads the same raw-axis buffer at priority 1 and changes its color on that tick. Rendering subsequently presents the latest color. A read-only `has_axis_sample` query distinguishes an actual event since connection from a polled startup zero. All controls ignore mouse input, and the CanvasLayer stays below the pause menu.

This checks **input sampled by the live flight → displayed marker**, when externally filmed from the physical stick. It does not include downstream servo or aircraft response. Several physics ticks can share one engine-delivered sample or occur before one draw; the marker cannot prove a USB polling rate, physical 240 Hz input, display presentation time or end-to-end latency from an in-app timestamp. No simulation, physics, aircraft data or M2-owned files were changed.

## Owner camera protocol (F6, still pending)

1. Identify the exact build, OS, machine/GPU/driver, radio/firmware/USB mode, RF setting, raw axis and threshold. Record display refresh/resolution, actual VSync mode, frame cap and achieved frame rate. Use the same airborne scenario for each condition. Set the engine options before `--`, e.g. `--max-fps 60`, and `--disable-vsync` for the off condition.
2. Film the physical stick reference mark and the entire latency square together at a verified 240 frames/s (4.167 ms/frame). Keep the physical mark and sampled patch row at similar camera scanline heights. Record the camera mode and retain the original clip; slow-motion playback frame rate is not acquisition frame rate.
3. Establish black, then move across the physical position corresponding to the chosen raw threshold. Record at least 20 valid black-to-white crossings **per condition**. Vary the timing relative to refresh; keep trials separate. Discard and document gray, paused, crash/restart or obscured trials. Short movements returning between draws are not observable by this patch.
4. For each trial, record the first camera frame past the physical reference and the first frame where the same central patch region turns white. Store both frame indices and compute `(white_frame - stick_frame) * 1000 / acquisition_fps`. Report the spatial criterion if the panel scanout gives a partial transition. Timing quantization alone contributes up to roughly one acquisition frame to the difference; exposure, rolling shutter, display scanout and uncertainty in the physical mark add uncertainty.
5. Retain raw clips/frame annotations and a CSV with condition, trial, frame indices, camera fps, latency and exclusions. Report median (average the two central samples for even counts), nearest-rank p95 (`sorted[ceil(0.95*n)-1]`), sample count and uncertainty separately for VSync on/off and each cap. Twenty trials are a minimum screen, not a stable tail estimate; collect more near the proposed budget (50 ms median / 70 ms p95 at 60 Hz).

Do not tune `physics_jitter_fix` or add a threaded input reader based on the synthetic tests below. Those decisions require the physical F6 evidence.

## Verification

- `test_latency_patch.gd`: 533 checks, including 240 live tick updates and 240 byte-identical complete simulation checkpoints against a simultaneous flight without a marker. Backend values change before polling, without replacing the radio's cached axes. Guard, reconnect, option, square-size and mouse-pass-through checks also pass.
- `test_latency_patch_cli.gd`: 26 checks through the real executable: valid routes, invalid/conflicting flags and preservation of an existing trace file on rejection.
- `test_latency_patch_route.gd`: five checks of the real main scene: absent by default, attached on request, axis/threshold forwarded, actual flight session observed, restart retained.
- [Ordering mutations](mutations.py): a disposable-copy baseline passes; sampling before the flight poll or updating in `_process` each fails all 240 same-tick assertions, with no engine errors. [Results](mutations.json).
- [Capture harness](capture.gd): actual flight scene with synthetic radio samples, 1280×720 and 800×600. Four viewport/rectangle/pixel readbacks pass; gray/black/white are exact at the square center. [Inactive](inactive-1280.png), [below](below-1280.png), [above](above-1280.png), [smaller window](above-800.png). These are visual proofs, not latency trials.
- Skill linter: zero errors; the same 12 existing warnings before/after. Debugger-backed input-resource validation: seven scripts load, no configuration warnings or physics-layer findings; ten pre-existing compiler warnings are in unchanged physics dependencies, none in F6a files. Their files and messages are retained in `verification.json`.

Reproduce the rendered checks from the repository root (requires Xvfb):

```bash
xvfb-run -a env LIBGL_ALWAYS_SOFTWARE=1 LP_NUM_THREADS=2 "$(app/get-godot.sh)" \
  --path app --audio-driver Dummy --script "$PWD/docs/research/radio-input/F6a/capture.gd"
```

[Verification record](verification.json) identifies the isolated baseline and source hashes. All `app/test.sh` checks were covered in two segments: [90 test programs, H7 and field-route checks](suite-tests.log), followed by [model contracts, four trimmed aircraft traces and identical 30/60/144 FPS states](suite-contracts-traces.log). The first process ended with SIGTERM (143) during the Extra contract, without a logged engine error; the unchanged contracts-through-end section was rerun and exited 0. The additional main-route test also passed separately. This is complete check coverage, not a claim that one uninterrupted `app/test.sh` invocation exited 0. The initial shared baseline run failed while writing logs with `No space left on device`; it is not counted as a passing run. No unrelated temporary folders were removed.
