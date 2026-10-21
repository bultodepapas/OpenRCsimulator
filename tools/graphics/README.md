# Experimental High graphics

VQ-07 uses the existing Godot renderer and accepted assets. Standard remains the
default. High is an opt-in, temporary Forward+ trial, not a qualified hardware
preset. Current evidence and remaining gates: [VQ-07 trial](../../docs/research/visual-quality-implementation/VQ-07/high-trial-2026-10-21/README.md).
Follow-up: [field-cue colors and Windows menu restart](../../docs/research/visual-quality-implementation/VQ-07/high-followup-2026-10-21/README.md).

From Home, open **Settings → Graphics → Try High (restart)**. Keep pending display
changes first. **Restart in Standard** returns to Compatibility. Closing the game
and launching normally also returns to Standard; no renderer preference, retry
marker or automatic restart is saved. Restart is unavailable during a flight or
Workshop session. If the engine falls back, Settings reports Standard.

High enables short-range SSAO, four blended directional-shadow cascades in an
8192-pixel atlas, solar-angle PCSS, and sky reflections during flowing time of day.
The existing exposure, haze, aircraft, scenery population and simulation are
retained. It does not enable temporal AA, motion blur, SSR, GI or volumetric fog.
The atlas and screen-space buffers cost additional GPU memory. Only the recorded
Windows/NVIDIA host has been exercised; macOS, Linux and other GPUs remain open.

## Explicit startup

The Python standard-library launcher chooses the renderer before initialization
and supplies the temporary `OPENRC_GRAPHICS_PROFILE` environment value:

```powershell
python tools/graphics/launch.py --profile high
python tools/graphics/launch.py --profile standard
python tools/graphics/launch.py --profile high --resolution 1920x1080 -- --quick-flight
python tools/graphics/launch.py --profile high --executable 'D:/path/OpenRC Simulator.exe'
python tools/graphics/launch.py --profile high --dry-run
```

Use `--godot <path>` or `GODOT` for an explicit engine. Engine arguments precede
`--`; OpenRC arguments follow it. Resolution is a request: window decorations and
desktop limits can reduce the actual drawable size. Read runtime metadata before
calling a measurement 1080p. The launcher does not force a platform rendering driver.

## Focused verification

```powershell
python -m unittest tools.graphics.test_launch -v
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_high_graphics_profile.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_high_graphics_restart.gd
```

Run the profile test natively with Forward+ to exercise its active branch. The
restart test injects the restart callback; `restart_probe.gd` additionally invokes
the real production restart handler through three processes (Standard → High →
Standard) using isolated preferences. Append `-- --out=<new absolute directory>`.
Inspect all three `stage-N.json` receipts and child logs, not only the parent exit.
The probe appends its own script/log arguments after checking production arguments;
it verifies the editor-binary path, not packaged or macOS application relaunch.

`capture.gd` uses production builders in a fixed 4× MSAA SubViewport. Run with a
native renderer and `-- --out=<new directory> --aircraft=p51d-mustang-120`.
`--width=1280|1920`, `--hour=<0..24)` and `--view=all|aircraftground|pilot|pavilion|lake|flightline|windsock`
select static comparisons. The `pavilion` case includes the clubhouse and pit area.
`--seconds=<duration>` requires one view and measures after 10 s warmup without
image readback. These offscreen static timings do not qualify flight performance.
Use the existing native flight collector separately, without concurrent tests,
exports or captures. `restart_probe.gd` requires an editor binary; release templates
ignore its `--script` route. It is not a packaged-release probe. Packaged restart
must be exercised through the actual menu.
