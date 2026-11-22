# Experimental flight dynamic resolution

Apply [the completed-frame patch](completed_viewport_gpu.patch) to a fresh Godot
source tree at `cafc17a192acf67903910a68aeb3c076c0907a4b`. Verify the source
archive using the checksum in the [engine intake guide](../metalfx/README.md).
Build a separate editor on the target OS using the project's pinned SCons.
On Windows use `platform=windows arch=x86_64 target=editor`. On Apple Silicon
use `platform=macos arch=arm64 target=editor`. Build a matching custom export
template before testing a package. Keep Godot's license and third-party notices.

The patch publishes a completed viewport draw with the configuration generation,
internal and target texture sizes, recording time and GPU duration. The duration
covers the viewport draw up to its render target. Screen presentation and other
viewports have their own costs. The patch exposes Vulkan and Metal 3 timestamps
only when the device supplies the required counters. OpenGL Compatibility and
legacy Metal keep fixed resolution. The macOS test requires the Metal 3 driver,
counter support and a verified GPU receipt for the actual driver.

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
