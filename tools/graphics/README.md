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
retained. High defaults to native rendering; FSR2 is now an explicit optional
choice (below). It does not enable motion blur, SSR, GI or volumetric fog.
The atlas and screen-space buffers cost additional GPU memory. Only the recorded
Windows/NVIDIA host has been exercised; macOS, Linux and other GPUs remain open.

Known pinned-engine issue: a captured stock `ReflectionProbe` leaks its atlas
color buffer and six texture views in Godot 4.7.2 Forward+. The native minimal
reproduction grows from seven leaked Texture RIDs for one independent world to
28 for four worlds. [Attribution and upstream fix](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#engine-lifetime-attribution-and-session-context-2026-10-22)
are retained. A [controlled local backport](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#controlled-engine-backport-2026-10-22)
removes the leak in matched custom Windows editor controls and preserves six High
1080p captures exactly. It is not a shipping replacement; the project's engine pin
is unchanged. Full-feature builds, matching templates and lifecycle/platform
qualification remain open. Do not suppress the pinned engine's warning.

## Explicit startup

### FSR2 reconstruction (VQ-07d)

In High, open **Settings → Graphics → 3D reconstruction**:

- **Native** keeps the saved MSAA choice and full resolution (default).
- **FSR2 · Native AA** reconstructs at full resolution for temporal antialiasing; it adds GPU work.
- **FSR2 · 85%** is our custom detail-preserving trial (1632×918 into 1080p), not an AMD preset name.
- **FSR2 · Quality** renders the main 3D view at two-thirds of each output dimension
  (1280×720 into a 1920×1080 output). UI and secondary viewports keep their resolution.
- **FSR2 · Balanced** uses 1/1.7 per axis (about 1129×635 into 1080p).
- **FSR2 · Performance** uses half resolution (960×540 into 1080p).

Start comparisons at 1080p with Native AA or 85%; the lower scales can lose small
aircraft detail. These are optional trials, not qualified performance presets.
**FSR2 sharpness** controls RCAS from off (0%) to maximum (100%), in 5% steps.
The initial 90% preserves Godot's existing default; it is not a tuned recommendation.
Lower it if edges show halos or scenery shimmers. The slider is inactive in Native
and Standard. Pointer dragging updates the displayed value and applies on release;
keyboard steps apply immediately. This avoids repeated render-buffer reconfiguration
during a drag in the pinned engine. Hover over reconstruction to see nominal input dimensions; engine
rounding can differ. No extra mip bias or second sharpening pass is added.

Use **Keep changes** within 15 seconds; Revert, expiry and closing an unsaved preview
restore the saved choice. FSR2 temporarily replaces MSAA; selecting Native restores
it. The choice is saved, but Standard always uses native rendering. Enter High again
to use the saved FSR2 choice. No GPU-brand whitelist is used.

Direct technical launches ignore player display preferences. Set
`OPENRC_RECONSTRUCTION=fsr2_85`, `fsr2_quality`, `fsr2_balanced`, `fsr2_performance`
or `fsr2_native` with the High launcher for a
reproducible candidate; `native` or an unknown value uses the native baseline.
`OPENRC_FSR2_SHARPNESS=0.35` selects user strength 0–1 (default 0.9; finite numbers
are clamped, malformed values use the default).
Home launches use saved preferences instead. Captures/frame reports record
`scaling_3d_mode`, scale and a `reconstruction` receipt (requested/effective mode,
nominal input size, sharpening strength/activation and additional texture mip bias).
`--frame-diagnostics` additionally retains this identity at start and report time.
Compare each mode separately;
the existing native campaign reducer does not automatically qualify mixed AA modes.

The existing main-flight `--capture` route allows temporal history after fixing the
pose: 16 drawn frames for Native AA, 36 for Quality, up to 64 for Performance.
Native retains its two-frame capture wait. `capture_settle_frames` records this
allowance; it does not qualify moving imagery or guarantee convergence. Use native
rendering for images; headless execution cannot complete a rendered capture.

The [RTX 3090 integration evidence](../../docs/research/visual-quality-implementation/VQ-07/fsr2-2026-10-24/README.md)
owns the tested scope and remaining motion/performance gates. FSR2 availability does
not establish a speedup, distant-aircraft readability or qualification on another GPU.

### Launcher

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

`flow_probe.gd` diagnoses moving moon/stars and twilight at a fixed 60 Hz clock,
20× world time, 1920×1080 and 4× MSAA. Run with an editor binary and a native
renderer, selecting either profile through `launch.py`:

```powershell
python tools/graphics/launch.py --profile high --script ../tools/graphics/flow_probe.gd -- --out=D:/captures/high-flow
```

Use a new absolute output directory. Each case warms for 10 seconds, records
481 draws and 120 draws at a paused clock, then replays selected times for PNGs
outside the timing sample. Check `complete`, actual profile/renderer, size and
sample counts before comparing reports. CPU/GPU queries can lag. This is an
offscreen production World diagnostic without aircraft or flight simulation;
it does not qualify flight pacing, pilot readability or reflection quality.
Flowing High uses Godot's realtime 256-pixel sky filtering to allow continuity;
frozen worlds retain quality filtering. [Evidence and tradeoffs](../../docs/research/visual-quality-implementation/VQ-07/sky-continuity-2026-10-21/README.md).

`test_ridge_color.gd` is a native GPU regression for the distant mountain
material. Run it with `launch.py --profile standard` and `--profile high`, adding
`--script ../tools/graphics/test_ridge_color.gd`. Eleven controlled palette cases
compare the production fragment path with StandardMaterial3D references, with
lighting/fog isolated. Headless execution fails rather than claiming GPU coverage.
[Mountain color evidence](../../docs/research/visual-quality-implementation/VQ-07/ridge-color-2026-10-21/README.md).

`test_shadow_energy.gd` checks that enabling shadow maps does not dim unoccluded
Forward+ panels through the production sun adapter. Run with
`launch.py --profile high --script ../tools/graphics/test_shadow_energy.gd -- --out=<new absolute directory>`.
It refuses headless rendering, retains on/off PNGs and a JSON verdict, and requires
agreement within 2/255 per sampled RGB channel. `--capture-only` records a failing
baseline without a nonzero exit; its report must not be presented as a pass.
[Sun-energy correction and evidence](../../docs/research/visual-quality-implementation/VQ-07/sun-energy-2026-10-22/README.md).

The dated [lake sky-edit and low Ventage Jet fixtures](../../docs/research/visual-quality-implementation/VQ-07/lake-refresh-2026-10-22/README.md)
retain production-reflection checks, prescribed aircraft motion, and rejected
fixture-only dynamic reflection screens. They do not qualify real-time flight
pacing or enable aircraft reflections in the game.

An experimental planar lake capture now supports the detailed jet in native High:

```powershell
$env:OPENRC_LAKE_REFLECTIONS = 'planar'
python tools/graphics/launch.py --profile high -- --quick-flight --aircraft=sebart-avanti-s-a200-p100rx
Remove-Item Env:OPENRC_LAKE_REFLECTIONS
```

This launch-only option is off by default and ignored in Standard/headless.
It renders a second camera at half resolution, capped at 1280×720, and falls back
to the existing probe below/near water or without a perspective camera. It adds
rendering cost; full flight/platform qualification remains open.
[Source, low jet clip, measured scope and reproducer](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md).

`test_pilot_station_color.gd` checks six production vertex material tags and three
fixed palettes against independent references at native 1920×1080. Run both
profiles with `--script ../tools/graphics/test_pilot_station_color.gd -- --out=<new absolute directory>`.
Headless execution fails. Reference anchors reject background-only comparisons;
palette agreement must be within 2/255 per channel.
[Pilot-station evidence and reproducer](../../docs/research/visual-quality-implementation/VQ-07/pilot-station-color-2026-10-22/README.md).

`test_material_tags.gd` verifies raw vertex metadata in the production barrier
and shelter shaders with 15 native GPU cases per renderer at 1080p. Run each
profile with `--script ../tools/graphics/test_material_tags.gd -- --out=<new absolute directory>`.
It checks variation, fitting tone, grain axes/seeds and roof/slab flags, with
reference anchors and a 2/255 per-channel tolerance.
[Metadata correction and evidence](../../docs/research/visual-quality-implementation/VQ-07/material-tags-2026-10-22/README.md).

`test_lily_color.gd` checks six leaf UV/tint combinations and two flower colors
against native StandardMaterial references. Run both profiles with
`--script ../tools/graphics/test_lily_color.gd -- --out=<new absolute directory>`.
[1080p evidence and integration captures](../../docs/research/visual-quality-implementation/VQ-07/lily-color-2026-10-22/README.md).
