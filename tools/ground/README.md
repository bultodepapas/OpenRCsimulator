# Ground surface capture

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
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bake_lake_geometry.gd"
# Check without writing either generated output:
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
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
`turf_requirements.txt`. The native engine must be Godot 4.7.2 Compatibility.

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

It subtracts `stripe_amp=0` images, compares native output with an independent raw-wave reference rendered at 16× resolution, and subtracts the reference's expected half-pixel motion. The improvement at 100/300 m must exceed twice the measured 8×/16× reference disagreement. A nearby threshold view must retain its stripe detail. Independent native repeats must match exactly; both a raw-wave control and a no-stripes control must fail acceptance.

Only a 640×64 sub-frustum of each original camera is rendered (up to 10240×1024 at 16×). The camera translation remains measured in base-resolution pixels; projected geometry is checked across resolutions. The measurement mask is a fixed one-metre runway inset, independent of image colour. The high-resolution PNGs are decoded to linear RGB before box averaging. This is a bounded engineering regression check, not proof of reference convergence or perceptual shimmer closure. See [method and evidence](../../docs/research/visual-quality-implementation/L9c-R1/README.md). Both ground checks run from `app/capture.sh` and appear in its final manifest.

L10a flight-cue captures use the same pinned rendering environment:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l10a-windsock
```

The L10a–d harness uses `--field-shadows=off` to isolate each cue mesh ablation; production projected shadows are checked by `app/tests/test_field_projected_shadows.gd`. Three production-field views isolate the calm windsock with visibility on/off at shader time zero. Default captures repeat exactly; a third run exercises the scenery-enabled field. Pixel changes must stay within current deformed cue bounds, whites must not clip, and the cue must add three draws and fewer than 6,000 triangles. The checker rejects an invisible-feature control. [Original L10a evidence](../../docs/research/visual-quality-implementation/L10a/README.md), [current motion evidence](../../docs/research/wind-implementation/M5-W04b-R1/README.md).

## Windsock motion (M5-W04b-R1)

Run `res://tests/test_windsock.gd` and `res://tests/test_windsock_motion.gd` with the pinned headless engine. Both are discovered by `app/test.sh`. Native captures need a display and a new output directory:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --resolution 960x540 `
  --rendering-driver opengl3 --audio-driver Dummy `
  --script "$PWD/tools/ground/capture_windsock_motion.gd" -- --out=C:/absolute/new-folder --sequence
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/bench_windsock.gd" -- --out=C:/absolute/cost.json
```

The capture uses the production sleeve/material and a fixed 240 Hz wind tape. It records two views of calm, light/full/strong flow, reversal, vertical gust and recovery; `--sequence` adds a 61-frame gust/turn/calm tape at 12 FPS. `capture.json` includes source/image hashes, wind vectors, state, renderer and mesh cost. Check engine errors as well as exit status. The CPU probe reports 30 batch means for tick advances and 60 Hz uploads after warmup; run it alone. These component checks do not qualify full-flight frame time or physical fabric dynamics.

### Windsock CPU comparison (VQ-04a-F3)

Before editing the renderer, copy `app/render/windsock.gd` to an absolute path outside `app/`. Keep its dependencies identical to the candidate; the tool loads both scripts in the same project. Then run alone with the pinned engine:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script "$PWD/tools/ground/compare_windsock_optimization.gd" -- `
  --baseline=C:/absolute/baseline/windsock.gd --out=C:/absolute/comparison.json
```

The harness compares 2,400 motion states, 600 render states and six bounds cases exactly, then measures 30 paired batches in alternating order. Active batches contain 240 advances and 60 updates with changing wind; paused batches contain 60 updates at the model's current timestamp. JSON retains raw batch microseconds, means, medians and source hashes. An equivalence mismatch exits nonzero. Check logs for engine errors too. This measures one cue's headless CPU work, with no GPU or whole-flight FPS claim. [Accepted measurements and native visual parity](../../docs/research/visual-quality-implementation/VQ-04a/windsock/README.md#vq-04a-f3-windsock-upload-cpu-optimization) own the evidence.

L10b reuses the flight-cue harness for the pilot station:

```bash
"$(app/tests/visual-env.sh)" tools/ground/check_windsock.py --cue pilot_station --app app --godot "$(app/get-godot.sh)" --out /tmp/l10b-station
```

Front, rear and raised views require a visible one-draw cue below 400 triangles. Both runway-threshold views use the field's actual pilot eye and require identical on/off pixels. A modified-pixel control tests that equality guard; it does not render an occluder. Default repeat and scenery-on runs produce 30 images. Both cue modes run in `app/capture.sh`. [L10b evidence and limits](../../docs/research/visual-quality-implementation/L10b/README.md).
