# Experimental flight dynamic resolution

Apply [the completed-frame patch](completed_viewport_gpu.patch) to a fresh Godot
source tree at `cafc17a192acf67903910a68aeb3c076c0907a4b`. Verify the source
archive using the checksum in the [engine intake guide](../metalfx/README.md).
Build a separate editor on the target OS using the project's pinned SCons.
On Windows use `platform=windows arch=x86_64 target=editor`. On Apple Silicon
use `platform=macos arch=arm64 target=editor`. Build a matching custom export
template before testing a package. Keep Godot's license and third-party notices.
Use the [native kernel qualification procedure](../../../research/native-kernel/README.md#normal-flight-backend-selection)
with the experimental binary before collecting flight performance. Check which
physics backend the application actually selected.

The patch publishes a completed viewport draw with the configuration generation,
internal and target texture sizes, recording time and GPU duration. The duration
covers the viewport draw up to its render target. Screen presentation and other
viewports have their own costs. The patch exposes Vulkan and Metal 3 timestamps
only when the device supplies the required counters. OpenGL Compatibility and
legacy Metal keep fixed resolution. The macOS test requires the Metal 3 driver,
counter support and a verified GPU receipt for the actual driver.
The Linux adaptive candidate uses Mobile/Vulkan. Keep the product's
Compatibility row for fixed-scale measurements and the unavailable-option test.

Start the patched editor binary in game mode with the project and
`-- --experimental-dynamic-resolution`. Use a fresh test profile. From Home,
open Settings → Display, select a fixed ceiling above 75%, then choose Native
reconstruction and a Dynamic resolution target. Keep the settings and start a
flight. The 75% minimum is an experiment threshold. Measure pilot readability
before qualifying a floor for a device and display.

The reconstruction diagnostic reports the controller's state, reason, target
and configured scalar. A completed frame in a new generation confirms a step.
Check the recorded backend and pixel extents while testing. Follow the
[platform matrix](../../../docs/plans/dynamic-resolution.md#native-platform-trials)
for native, best fixed and adaptive runs, including pause, fullscreen, focus
loss, Keep/Revert and a switch back to Off.

Before running the flight, run the [rendered producer probe](../../../app/tests/probe_completed_gpu_frame.gd)
with the patched editor, a visible 1920×1080 window or the native Retina target,
and the experiment flag. It validates fresh completed frames across a full-size
draw, an 85% draw and restoration. Use the checked runner on an admitted target.

## Windows RTX 3090 experiment

For an experimental binary on the enrolled Windows host, [windows_probe.py](windows_probe.py)
uses the documented manual desktop reservation and tracks the owned process tree.
It reports the experimental binary and patch hashes, logs and teardown in the
selected output directory. Run with a fresh output path. The probe executes in
a visible window.

1. Run the producer probe at 1080p and then 4K. Require a new completed
   generation for each actual size and restoration.
2. Use `--stress --fps 120 --fixed 100` to set the workload at 1080p, 1440p and
   4K. Keep the same shader iteration count when measuring the pixel-cost
   difference across those outputs. Select a separate iteration count at a
   given output if needed to put the fixed GPU time just above 8.33 ms.
3. With resolution, workload and target held constant, compare `--fixed 100`,
   `--fixed 85` and `--fixed 0` (adaptive). Record median and tail frame times,
   late callbacks, time at each observed 3D size and the first frames after
   each transition. The high-load phase lasts 18 s. The light phase lasts 16 s
   so the controller can recover after its dwell. Repeat decisive cases in
   reverse order. Reject a case when another task uses the host or the probe
   window loses focus.
4. Use 60 FPS as a control on a workload with spare capacity. The fixed ceiling
   should hold. A useful 120 FPS result reduces missed frames during the
   heavy phase and returns to the ceiling during recovery. Compare the motion
   and legibility in the real flight before recommending a floor.

The stress probe measures a shader workload and shows the actual 3D size and
GPU time in its window. Use the same engine and flight configuration for each
flight comparison. Check the selected physics backend when collecting flight
evidence.
