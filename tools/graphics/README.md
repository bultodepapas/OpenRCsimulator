# Graphics modes

VQ-07 uses the existing Godot renderer and accepted assets. Standard remains the
default in the official-engine build. The [Windows NVIDIA package](native/README.md)
defaults to High and exposes DLSS, DLAA and Reflex in Settings. High is not a
hardware performance guarantee. Current evidence and remaining gates: [VQ-07 trial](../../docs/research/visual-quality-implementation/VQ-07/high-trial-2026-10-21/README.md).
Follow-up: [field-cue colors and Windows menu restart](../../docs/research/visual-quality-implementation/VQ-07/high-followup-2026-10-21/README.md).

From Home, open **Settings → Graphics → Enable High (restart)**. Keep pending display
changes first. **Restart in Standard** returns to Compatibility. Closing the game
and launching normally returns to the package default; no renderer preference, retry
marker or automatic restart is saved. Restart is unavailable during a flight or
Workshop session. If the engine falls back, Settings reports Standard.

High enables short-range SSAO, four blended directional-shadow cascades in an
8192-pixel atlas, solar-angle PCSS, and sky reflections during flowing time of day.
The official beta1 engine additionally supports multi-bounce ambient occlusion;
the pinned NVIDIA fork does not implement that newer setting.
The existing exposure, haze, aircraft, scenery population and simulation are
retained. High defaults to native rendering; FSR2 is now an explicit optional
choice (below). It does not enable motion blur, SSR, full GI or volumetric fog.
Multi-bounce occlusion is a Forward+ startup setting in `project.godot`; Compatibility
and Mobile ignore it. Bare technical Forward+ launches also inherit it. Changing
the setting from an already-running script cannot activate its shader variant.
[Paired evidence and limits](../../docs/research/engine-upgrade/GDU-11/implementation.md#gdu-11h--forward-multi-bounce-occlusion).
The atlas and screen-space buffers cost additional GPU memory. Only the recorded
Windows/NVIDIA host has been exercised; macOS, Linux and other GPUs remain open.

Known pinned-engine issue: a captured stock `ReflectionProbe` still leaks seven
Texture RIDs per independent world in official Godot 4.8-beta1 Forward+.
[The existing native controls](../../docs/research/engine-upgrade/GDU-03/rendering/gpu-correctness/README.md)
reproduce seven for one world and 28 for four, including explicit `UPDATE_ONCE`;
the no-probe controls exit cleanly. The historical Godot 4.7.2
[attribution and upstream fix](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#engine-lifetime-attribution-and-session-context-2026-10-22)
are retained. A [controlled local 4.7.2 backport](../../docs/research/visual-quality-implementation/VQ-07/planar-lake-2026-10-22/README.md#controlled-engine-backport-2026-10-22)
removed the leak in matched custom Windows editor controls and preserved six High
1080p captures exactly; it is not the shipping replacement. Full lifecycle and
platform qualification remain open. Do not suppress the pinned engine's warning.

## NVIDIA DLSS, DLAA, Reflex and FSR 3.1

The [native integration guide](native/README.md) owns the separate Windows/Vulkan
engine build, SDK pins and runtime requirements. The menu discovers each provider
through engine capabilities; stock Godot keeps those entries unavailable and uses
Native for unsupported saved requests. This Windows package does not
replace the standard official Godot 4.8-beta1 pin.

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

## Isolated Mac renderer trials (DT-MAC)

The research launcher separates renderer selection from the High effects preset.
It is preparation for native Mac testing; Windows headless checks do not establish
Metal execution, image quality or performance. The
[Apple Silicon plan](../../docs/plans/apple-silicon-performance.md) owns acceptance.

Prepare one new copy per renderer from the same frozen checkout. Each copy has a
UUID project/user-data identity, its own import cache, Standard effects and startup
multi-bounce occlusion disabled. The helper verifies copied file hashes and writes
`research-preparation.json` only after successful validation. It never replaces an
existing destination. Failed preparations retain their partial files for inspection.
Sibling `assets/` is a link to the source, not an immutable copy: freeze that source
and retain its identity throughout the campaign. Windows requires permission to
create directory symlinks; Mac preparation remains to be exercised natively.

On a native ARM64 Mac, from the repository root:

```sh
godot_exe="$(app/get-godot.sh)"
python3 tools/graphics/prepare_research.py --dest tmp/mac-renderer-trials/compat
python3 tools/graphics/prepare_research.py --dest tmp/mac-renderer-trials/mobile
python3 tools/graphics/prepare_research.py --dest tmp/mac-renderer-trials/forward

# Repeat import for each prepared app before its first launch.
python3 tools/godot/run_checked.py --timeout 600 --label mac-mobile-import -- \
  "$godot_exe" --headless --path tmp/mac-renderer-trials/mobile/app \
  --audio-driver Dummy --import

python3 tools/graphics/launch.py --godot "$godot_exe" \
  --research-project tmp/mac-renderer-trials/mobile/app \
  --research-method mobile --research-driver metal --resolution 1920x1080 \
  -- --quick-flight --scene_detail=medium
```

Use `gl_compatibility` / `opengl3` with the `compat/app` copy, and
`forward_plus` / `metal` with `forward/app`. Mobile/Forward+ `vulkan` is an optional
separate MoltenVK control, not native Metal. The launcher rejects incompatible
pairs and duplicate/contradictory renderer or project switches. `--dry-run` prints
the arguments and overrides without launching. Research mode requires an editor
and prepared app copy; it does not modify the production renderer default or
provide packaged-release qualification.

`--research-reconstruction native` is the default and clears inherited MetalFX
trial selection. Ordinary research comparisons also explicitly disable contact
shadows and planar reflections. This is not a complete lighting/workload snapshot:
use the same declared `OPENRC_*` environment, landscape, aircraft, scenery tier,
wind, time and observer settings in every case. Bare Forward+ launches outside this
research route still select the existing High profile.
The example explicitly pins Medium scenery so adapter-name-based Auto selection
cannot change the workload between drivers; this is a comparison control, not a
qualified Mac preset.

Runtime graphics receipts distinguish requested and effective driver/method,
project identity, effects and multi-bounce setting. Verify those receipts and
actual rendering dimensions before comparison. A 1920×1080 window request or
viewport size alone does not prove the Retina drawable's pixel size. Test 1080p
first, higher resolutions next, and 720p only as the final compatibility case.
Use the [streaming collector](../../research/performance/README.md) for long runs;
headless or scripted motion cannot qualify active native flight.

### Explicit MetalFX experiment

Add one of these research switches to the command above:

| Switch value | Required method | Nominal 3D input scale |
| --- | --- | --- |
| `metalfx_spatial_85` | Mobile or Forward+ | 0.85 |
| `metalfx_spatial_quality` | Mobile or Forward+ | 2/3 |
| `metalfx_temporal_native` | Forward+ | 1.0 |
| `metalfx_temporal_85` | Forward+ | 0.85 |
| `metalfx_temporal_quality` | Forward+ | 2/3 |

For example, `--research-reconstruction metalfx_spatial_85` explicitly enables the
trial in that child process. Runtime admission additionally requires the Metal
driver, exposed engine enum, a RenderingDevice and the provider's support flag.
Temporal scales must be within the device-reported range. Names are application
trial choices, not Apple's quality presets. No GPU-name whitelist is used.

The existing Settings picker includes these choices when the explicitly enabled
trial supports them. Direct technical launches use the command selection;
Home uses that isolated project's saved preferences. Spatial preserves saved
MSAA; Temporal owns antialiasing, and Native restores MSAA. FSR sharpening is
inactive for either MetalFX provider and its saved value is preserved.

Godot viewport properties describe the requested inputs, not the executed scaler.
MetalFX receipts therefore mark execution unverified and effective reconstruction
unconfirmed until native evidence can establish it. The UI must not present a
successful MetalFX pass from property readback alone. Native GPU capture and moving
aircraft, foliage, propeller, smoke and disocclusion checks remain required.

The pinned stock engine does not expose an acknowledged MetalFX history-reset
contract. A temporal camera discontinuity therefore latches Native fallback,
including startup with a non-pilot view that requests a reset. Select Native before
retrying the experiment. Method presence or a reset submission alone is not proof
the SDK cleared its history. Spatial is a separate explicit choice, not an automatic
substitute. Camera/aircraft changes, resize, Retina/fullscreen transitions, lifecycle
leaks and normal-flight motion must pass native validation before adoption.

The pinned Godot source uses its MTL3 command backend. These options do not implement
Metal 4 command submission, frame interpolation, denoising or neural shaders; those
remain the separate, evidence-gated engine work packages in the plan.

## Focused verification

```powershell
python -m unittest tools.graphics.test_launch -v
python -m unittest tools.graphics.test_prepare_research -v
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_high_graphics_profile.gd
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --script res://tests/test_high_graphics_restart.gd
```

Run the profile test natively with Forward+ to exercise its active branch. The
restart test injects the restart callback; `restart_probe.gd` additionally invokes
the real production restart handler through three processes (Standard → High →
Standard) using isolated preferences. Append `-- --out=<new absolute directory>`.
Inspect all three `stage-N.json` receipts and child logs, not only the parent exit.
The probe appends its own script/log arguments after checking production arguments;
it verifies the editor-binary path, not packaged or macOS application relaunch.

`capture.gd` uses production builders in an exact-size SubViewport, defaulting to 4× MSAA. Run with a
native renderer and `-- --out=<new directory> --aircraft=p51d-mustang-120`.
`--width=1280|1920|2560`, `--hour=<0..24)` and `--view=all|aircraftground|pilot|pavilion|lake|flightline|windsock`
select static comparisons. The `pavilion` case includes the clubhouse and pit area.
`--aa=msaa4|none|taa|fsr2_native` isolates antialiasing without changing player
preferences. TAA and FSR2 require native High; unsupported requests fail instead
of silently capturing a fallback. FSR2 Native uses the production reconstruction
adapter at full resolution with sharpening off. Reports record the actual MSAA,
TAA, scaling, sharpness and mip-bias values. Stills allow 90 drawn settling frames;
this is not a convergence or motion-quality guarantee. Compare contact on/off
within each AA mode before attributing a change to either effect.

The same producer accepts `--shadow-technique=auto|native|projected|off`,
`--shadow-quality=current|low|medium|high|ultra`, `--shadow-distance=auto|near|field|far`,
`--shadow-softness=auto|hard|soft` and `--shadow-cue=auto|sun|vertical|off`.
It uses the production settings resolver and records requested/effective values and the bounded
native-field caster inventory in `report.json`. Unknown choices fail. These static fixture views do not
exercise the flight's V-key override or establish complete Native coverage. Default options preserve
the prior capture configuration; contact experiments remain independent.
`--seconds=<duration>` requires one view and measures after 10 s warmup without
image readback. These offscreen static timings do not qualify flight performance.
Use the existing native flight collector separately, without concurrent tests,
exports or captures. `restart_probe.gd` requires an editor binary; release templates
ignore its `--script` route. It is not a packaged-release probe. Packaged restart
must be exercised through the actual menu.

GDU-11 contact shadows are available only as an explicit High experiment with
`OPENRC_CONTACT_SHADOWS=on`. Unset/invalid values keep them off. Beta1 produces
visible wall artifacts with the current Native AA path; default adoption failed
the [paired visual gate](../../docs/research/engine-upgrade/GDU-11/implementation.md#gdu-11g--high-contact-shadow-experiment).

For GDU-11 contact-shadow comparisons, `capture.gd --contact-shadows=off|on`
overrides only that runtime setting after High configuration; the default `profile`
uses production behavior. Overrides require native High. Reports retain the actual
contact-shadow setting, sun permission and startup multi-bounce setting.
`contact_shadow_probe.gd --out=<new absolute directory>` requires native High and
checks actual 1080p contact contribution, preservation of an offscreen caster's
ordinary shadow, and unchanged unoccluded sunlight. Its PNGs and JSON verdict are
fixture evidence, not flight performance or broad screen-edge acceptance.

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

The dated [lake sky-edit and low Vantage Jet fixtures](../../docs/research/visual-quality-implementation/VQ-07/lake-refresh-2026-10-22/README.md)
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
