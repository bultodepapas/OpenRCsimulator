# Ground surface capture

## L15c flag review

`capture_flag.gd` renders the production cloth and mast at 1920 × 1080 with a
matched calm/light/strong/reverse/crosswind tape and front/rear views. Pass
`--landscape` to include the production Club field and its wind cues. Optional
`--frames=180` captures a 30 Hz gust/reversal sequence; `--distance=30` reviews the
same cue at range. Use `--locale=fr` and `--flag_animation=static|basic|detailed`
for controlled variants. Output must be a fresh directory outside `app/`.

```powershell
python tools/godot/run_checked.py --timeout 180 --require-text 'FLAG CAPTURE COMPLETE' -- C:/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.8-beta2_win64_console.exe --path app --rendering-method gl_compatibility --audio-driver Dummy --script res://../tools/ground/capture_flag.gd -- --landscape --flag_animation=detailed --out=C:/new-empty-location/flag-review
```

`--legacy=<directory>` accepts preserved `prefabs.gd.txt` and
`motion.gdshader.txt` sources for the isolated baseline. Do not combine it with
`--landscape`. The manifest records source/image hashes, engine, renderer,
adapter, resolution and cloth diagnostics. PNG readback work makes this a
visual tool, not a frame-time benchmark. Use the existing
[frame diagnosis workflow](../../docs/tools/graphics.md#frame-diagnosis) for
native performance measurements.

## L10c-R5 fence planting review

`capture_barrier_detail.gd` uses the production field and defaults to a native
1920 × 1080, 4×MSAA SubViewport. It records close/front/rear, pilot, flightline,
gate, low-bank and overhead views, with engine, GPU, source and camera identities.
Run one rendered process at a time and choose a fresh output directory:

```powershell
python tools/godot/run_checked.py --timeout 240 --require-text 'FENCE CAPTURE COMPLETE' -- .tools/Godot_v4.8-beta2_win64_console.exe --path app --rendering-method gl_compatibility --audio-driver Dummy --script res://../tools/ground/capture_barrier_detail.gd -- --out=C:/new-empty-location/fence-review --width=1920 --height=1080 --motion-frames=12
```

`--motion-frames=2..120` adds an offline camera translation along the fence;
zero (the default) omits it. The simulation clock and field processing stay
frozen. Readback and PNG work exclude these runs from frame-time qualification.
`--planting-source=<path>` replaces only the captured planting with a preserved
GDScript source snapshot, using the same cue, posts and downloaded assets. The
manifest identifies that override; ordinary captures retain the production
builder. [L10c evidence](../../docs/research/visual-quality-implementation/L10c/README.md#2026-11-09--l10c-r5-varied-fence-growth-and-ground-contact)
records the comparison and its limits.

## L9b-R1 Club turf scale review

Use the production-world capture for matched 1080p ground views:

```powershell
python tools/godot/run_checked.py --label club-turf --out-dir tmp/club-turf/checks --timeout 300 -- .tools/Godot_v4.8-beta2_win64_console.exe --path app --rendering-method gl_compatibility --audio-driver Dummy --script res://tests/capture_landscape_upgrade.gd -- --out=C:/DEVELOPMENT/OpenRCsimulator/tmp/club-turf/views --width=1920 --height=1080 --cases=pilot_north,runway_west,runway_marker_close,entry_path,lake_shore,ground_200m,ground_raised --frames=30 --scene_detail=high --scenery_birds=off
```

Choose a new output directory for each run. `--grass_tile_m=6` restores the old
Club base-texture scale for a controlled comparison; the current Club uses 1.5 m.
The separate `--ground_diagnostic` controls are `normal`, `macro-off`, `dry-off`,
`detiling-off`, `photo-off`, `turf-off` and `clouds-off`. Detiling-off exposes the
repeated tile; photo-off exposes procedural turf and does not override the RC
soil route. These controls do not change production settings. Effective material
values appear in each case's `ground_materials` report and overrides are checked
after world updates. `ground_200m` is a narrow diagnostic aimed at a known ground
point, while `pilot_north` is the normal pilot view.

Add `--motion=camera --frames=48` for a slow camera translation with saved frames.
Motion-capture timings include readback/PNG work and cannot qualify performance.
The [L9b evidence](../../docs/research/visual-quality-implementation/L9b/README.md#l9b-r1-finer-club-turf)
records the comparison and remaining acceptance limits.

## L9b-R2 worn-path review

Use the same production capture at 1920 × 1080 with
`--cases=entry_path,pilot_south,gravel_close`. `--worn_photo=off` disables only the
sparse-grass scan; each case records the effective `worn_photo_enabled` binding.
`--gravel_detail=off` controls aggregate detail and does not isolate that scan.
Use a fresh output directory for every control. `--motion=camera --frames=32`
records a slow translation; compare the same source snapshot and import settings.
The source JPEG remains unchanged, while its checked-in import enables mipmaps.
Run the pinned editor's `--headless --editor --path app --import` after that import
setting changes, then check the actual texture via `test_landscape_gravel.gd`.
`test_landscape_ground_lu18.gd` owns route, mirrored/collapsed corner, material-tag,
batch and collision checks. [Dated evidence and limits](../../docs/research/visual-quality-implementation/L9b/README.md#l9b-r2-worn-path-color-and-filtering)
remain separate from whole-flight performance qualification.

## L9b-R3 field-textured path shoulders

Club's walking-path shoulders reuse that scene's field turf at High and Extreme.
Low and Medium skip the field-texture bindings and the uniform shader block.
This follows the saved Scene detail choice at the next world build; Automatic
uses the existing GPU-name heuristic, not measured performance.

The independent production override is `--worn_path_turf=auto|on|off` after `--`,
then `OPENRC_WORN_PATH_TURF`, then the preset policy. `off` disables this material
effect without changing the prop tier or collision inventory; `on` permits a
preview at any preset. This is a launch override, not a saved in-app control.
Custom fields, explicit scenery files and standalone scenery retain their prior
shoulder treatment. No asset regeneration is needed.

For a matched capture, use the R2 three views above. `--worn_shoulder=off` is a
capture-only ablation after binding; it does not test disabled resource lifetime.
The production `--worn_path_turf=off` skips the binding itself. Each report records
`worn_shoulder_enabled` and the enabled shoulder's effective ground parameters.

Optional `--measure_render_time=on` records raw CPU/GPU render times for the root
viewport. Verify GPU values are nonzero; defaults leave timing queries disabled.
These short static-view diagnostics exclude simulation and do not qualify the
whole-flight budget. Motion/readback timings are unsuitable for that purpose.
Run only one rendered process and preserve the exact source/import identities.
`test_field_surfaces.gd`, `test_landscape_gravel.gd`, `test_scene_detail.gd` and
`test_landscape_collision_setup.gd` cover bindings, isolation, presets, texture
release and the override's unchanged collision world at a fixed prop tier.
[Dated evidence and limits](../../docs/research/visual-quality-implementation/L9b/README.md#l9b-r3-field-textured-path-shoulders)
own the visual and cost results.

## DT-11a horizon construction

`Horizon.mesh()` reuses per-build float64 azimuth tables and preallocates triangle
indices. It still validates the profile on every call and creates a fresh mesh;
no generated asset or authoring pipeline changes are needed. Run the pinned
engine headless with `--script res://tests/test_horizon.gd` for topology, height,
seam and checksum checks. [Native parity, timings and the separate atmosphere
texture shutdown diagnostic](../../docs/research/visual-quality-implementation/VQ-01c/loading/horizon-build/README.md)
own the evidence and outstanding native-test limitation.

## DT-11a imported grass exclusion filtering

`ImportedNearGrass.layout()` discards masks strictly outside the validated 30 m
placement square, expanded by the existing clearance. It rebuilds this local list
for each call and preserves the original point/polygon predicate and selection
order. No generated asset changes are needed. Run
`res://tests/test_grass_mask_bounds.gd` with the pinned headless engine to check
inclusive boundaries, changed pilots and predicate parity; `app/test.sh` discovers
it automatically. [Measurements and rejected alternatives](../../docs/research/visual-quality-implementation/VQ-01c/loading/grass-masks/README.md)
own the evidence and loading limitations.

## DT-11a default grass image reuse

`Ground.grass_material()` caches one default procedural image's bytes, including
mips, while creating a fresh image, texture and material for every scene. Explicit
`grass_image(seed)` calls still run the original recipe. No generated asset or
regeneration command is needed; source changes take effect in a fresh process.

Run `res://tests/test_ground_image_cache.gd` with the pinned engine to check complete
byte equality, seeds and mutation isolation. It is also part of `app/test.sh`.
[Measurements, commands and limitations](../../docs/research/visual-quality-implementation/VQ-01c/loading/ground-image/README.md)
own the evidence; the first build still computes the tile.

## DT-11a default lake geometry

The default basin and water CPU arrays are generated from the production lake/ground
loaders and scalar samplers. With the exact engine pinned in `app/get-godot.sh`:

```powershell
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bake_lake_geometry.gd"
# Check without writing either generated output:
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bake_lake_geometry.gd" -- --check
```

Commit both generated outputs: `app/assets/landscape/lake/default_geometry.res` and
`app/render/lake/generated_geometry_stamp.gd`. Do not hand-edit them. Optional
`--out=<absolute.res>` writes an experimental resource without changing the production
stamp. `--check` compares the resource's full arrays, input keys and source hashes
against a fresh procedural generation; line endings are normalized in source hashes.
The source stamp excludes its own generated file to avoid a circular dependency.

Runtime accepts matching engine/precision, compiled stamp, content digests and full
normalized inputs. Custom inputs or missing/incompatible metadata use procedural
generation. The existing one-entry CPU caches remain bounded; every scene receives
new mesh/material/node resources. Physics samples are never read from this render asset.
When sampler code changes, regenerate both outputs: runtime checks the compiled stamp,
while the CI test checks that the stamp still matches current source and geometry.

`test_lake_geometry_bake.gd` runs automatically in `app/test.sh`; the existing lake-world
checks cover independent scenes and input invalidation. The empty-project field-pack
smoke explicitly requires a compatible bake so fallback cannot conceal export omission.
This binary resource has no external dependencies and is included by `all_resources`.
For a focused exported-lake check, append `--lake-only` after the pack path and field
SHA-256 arguments to `app/tests/check_field_pack.gd`, still running from an empty project.
That option does not qualify the remaining field/scenery assets or replace the full smoke.

## L9e turf material

`turf_generate.py --check` verifies the original packed data texture with Python
stdlib. For capture reduction, install the exact versions in
`turf_requirements.txt`. This section reproduces the historical L9e result with
Godot 4.7.2 Compatibility: `turf_verify.py` still requires `[4, 7, 2]` manifests.
That reducer's capture admission has not been migrated to the current official
4.8-beta1 pin.

Freeze a pre-change project as `BASELINE` and the candidate as `APP`. Run the same
`turf_capture.gd` script with `--path APP --script /absolute/tools/ground/turf_capture.gd`,
then pass user arguments after `--`:

| Output subfolder | Project | Arguments |
| --- | --- | --- |
| `day` | APP | `--mode=capture --out=.../day` |
| `legacy` | BASELINE | `--mode=capture --legacy --out=.../legacy` |
| `night` | APP | `--mode=capture --night --out=.../night` |
| `profile1` … `profile3` | APP | `--mode=profile --out=.../profileN` |

Every output folder must initially be empty. Check successful exit and absence
of engine errors before running `python tools/ground/turf_verify.py EVIDENCE`.
Profiles alternate off/on/off/on, warm for >=2 s/60 frames, and measure >=3 s/180
frames per state. Raw wall/CPU/GPU times are separate. Run profiles serially when
other GPU work is idle; shader compilation is excluded by warmup.

`--mode=motion` captures 12 threshold-camera steps of 20 mm. `--filter-reference`
selects a 640x96 exact crop of that camera; `--scale=4` supersamples it and uses
three steps. The L9e report documents the isolated no-filter mutation used to
compare the production filter with a supersampled reference. No mutation belongs
in `app/`. See [L9e evidence](../../docs/research/visual-quality-implementation/L9e/README.md).

## L9c surfaces

Run the L9c Compatibility-renderer review with:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_surfaces.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l9c-surfaces
```

The checker captures the production `FieldBuilder`, `Atmosphere`, and `ShaderClock` at fixed time zero. It covers 100 m and 300 m runway zooms (10° vertical FOV), 100 m and 300 m oblique runway views, the threshold, and a raised overview. Each pose has surface-on/off captures at zero and half-pixel camera-plane shifts. The raised planes must be consolidated into the rough ground material, whose surface arrays and bounds are checked against field data.

The 100 m runway edge score uses the camera-projected runway polygon, intersects its inside edge with pixels changed by the surface-on/off ablation, and compares median on-surface luma with the adjacent rough-ground band. It must exceed 5% Weber contrast. The shimmer score is RMS change in the surface-only residual divided by its RMS signal; it includes the expected response to camera translation. The checker records both oblique views against a scratch raw-square-wave mutation, but does not claim that the comparison proves shimmer closure. Stripe-filter acceptance remains open. A separate disabled-surface mutation must trigger the no-effect gate. Mutation copies are imported before capture and kept isolated from the live project.

Default and custom priority captures repeat in separate processes; every PNG hash and draw, primitive, and object counter must match. The custom fixture reverses runway/mown input order, draws both kinds, and compares runway pixels with the default field to check priority. `summary.json` records metrics, renderer and Godot versions, source hashes, exact capture arguments, and the deterministic render environment. Output directories must be new or empty.

The L9c-R1 stripe reference check separates expected camera motion from sampling error:

```bash
"$(app/tests/visual-env.sh)" tools/ground/test_stripes.py
"$(app/tests/visual-env.sh)" tools/ground/check_stripes.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l9c-stripes
```

It subtracts `stripe_amp=0` images, compares native output with an independent raw-wave reference rendered at 16× resolution, and subtracts the reference's expected half-pixel motion. The improvement at 100/300 m must exceed twice the measured 8×/16× reference disagreement. A nearby threshold view must retain its stripe detail. Independent native repeats must match exactly; both a raw-wave control and a no-stripes control must fail acceptance. A further control erases only the threshold residual while retaining the passing oblique views; it must fail specifically at the nearby-detail check and uses the existing captures.

The club field caps the normal stripe amplitude at `0.026` through `stripe_amp`; setting that uniform to zero still removes the stripes for this ablation.

Only a 640×64 sub-frustum of each original camera is rendered (up to 10240×1024 at 16×). The camera translation remains measured in base-resolution pixels; projected geometry is checked across resolutions. The measurement mask is a fixed one-metre runway inset, independent of image colour. The high-resolution PNGs are decoded to linear RGB before box averaging. This is a bounded engineering regression check, not proof of reference convergence or perceptual shimmer closure. See [method and evidence](../../docs/research/visual-quality-implementation/L9c-R1/README.md). Both ground checks run from `app/capture.sh` and appear in its final manifest.

L10a flight-cue captures use the same pinned rendering environment:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l10a-windsock
```

The L10a–d harness uses `--field-shadows=off` to isolate each cue mesh ablation; production projected shadows are checked by `app/tests/test_field_projected_shadows.gd`. Three production-field views isolate the calm windsock with visibility on/off at shader time zero. Default captures repeat exactly; a third run exercises the scenery-enabled field. Pixel changes must stay within current deformed cue bounds, whites must not clip, and the cue must add three draws and fewer than 6,000 triangles. The checker rejects an invisible-feature control. [Original L10a evidence](../../docs/research/visual-quality-implementation/L10a/README.md), [current motion evidence](../../docs/WIND-ATMOSPHERE-REFERENCE.md#evidence-wind-implementation-m5-w04b-r1).

## Windsock motion (M5-W04b-R1)

Run `res://tests/test_windsock.gd` and `res://tests/test_windsock_motion.gd` with the pinned headless engine. Both are discovered by `app/test.sh`. Native captures need a display and a new output directory:

```powershell
& .tools/Godot_v4.8-beta1_win64_console.exe --path app --resolution 960x540 `
  --rendering-driver opengl3 --audio-driver Dummy `
  --script "$PWD/tools/ground/capture_windsock_motion.gd" -- --out=C:/absolute/new-folder --sequence
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bench_windsock.gd" -- --out=C:/absolute/cost.json
```

The capture uses the production sleeve/material and a fixed 240 Hz wind tape. It records two views of calm, light/full/strong flow, reversal, vertical gust and recovery; `--sequence` adds a 61-frame gust/turn/calm tape at 12 FPS. `capture.json` includes source/image hashes, wind vectors, state, renderer and mesh cost. Check engine errors as well as exit status. The CPU probe reports 30 batch means for tick advances and 60 Hz uploads after warmup; run it alone. These component checks do not qualify full-flight frame time or physical fabric dynamics.

### Windsock CPU comparison (VQ-04a-F3)

Before editing the renderer, copy `app/render/windsock.gd` to an absolute path outside `app/`. Keep its dependencies identical to the candidate; the tool loads both scripts in the same project. Then run alone with the pinned engine:

```powershell
& .tools/Godot_v4.8-beta1_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/compare_windsock_optimization.gd" -- `
  --baseline=C:/absolute/baseline/windsock.gd --out=C:/absolute/comparison.json
```

The harness compares 2,400 motion states, 600 render states and six bounds cases exactly, then measures 30 paired batches in alternating order. Active batches contain 240 advances and 60 updates with changing wind; paused batches contain 60 updates at the model's current timestamp. It also compares all static mesh surface arrays byte-for-byte at four dimension fixtures and measures ten alternating construction pairs, keeping cue copies and disposal outside the build timer. JSON retains raw microseconds, means, medians and source hashes. An equivalence mismatch exits nonzero, with bounded mismatch details. Check logs for engine errors too. This measures one cue's headless CPU work, with no GPU or whole-flight FPS claim. [Upload evidence](../../docs/research/visual-quality-implementation/VQ-04a/windsock/README.md#vq-04a-f3-windsock-upload-cpu-optimization) and [construction evidence](../../docs/research/visual-quality-implementation/VQ-04a/windsock/README.md#vq-04a-f4-faster-cloth-construction) retain results and native visual parity.

L10b reuses the flight-cue harness for the pilot station:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --cue pilot_station --app app --godot "$(app/get-godot.sh)" --out /tmp/l10b-station
```

Front, rear and raised views require a visible one-draw cue below 400 triangles. Both runway-threshold views use the field's actual pilot eye and require identical on/off pixels. A modified-pixel control tests that equality guard; it does not render an occluder. Default repeat and scenery-on runs produce 30 images. Both cue modes run in `app/capture.sh`. [L10b evidence and limits](../../docs/research/visual-quality-implementation/L10b/README.md).
