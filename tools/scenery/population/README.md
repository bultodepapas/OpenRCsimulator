# Population authoring

Status: adopted in **LU-21**, Godot 4.7.2 Compatibility. Runtime assets are in `app/assets/scenery/population/`; exact sources/licenses and manifests are in `assets/scenery/population/`. No authoring add-on is loaded by the app.

## Cars

Use **Blender 5.2.2 LTS**, build `d13f752e3b9c`:

```text
blender --background --factory-startup --python tools/scenery/population/preprocess_cars.py -- --source-dir assets/scenery/population/source/cars --output-dir /your/temporary/output --lod close
python tools/scenery/population/package_population.py /your/temporary/output/innerscene-sedan-selective.glb /your/staged/assets/sedan.glb
```

Repeat packaging for hatch and crossover. The conversion checks source/license hashes, exact geometry counts and protected glass before export. The portable close conversion was rerun and matched all three frozen output hashes. Far variants are research outputs only; the shipped close meshes use Godot's generated LODs. Keep `meshes/generate_lods=true`, `meshes/create_shadow_meshes=false` and `animation/import=false`.

## People

Use Blender **5.2.2**, **MPFB 2.0.18**, and the exact CC0 system archive pinned in `HUMAN_SOURCES.json`. Install it into an isolated MPFB data directory. Start Blender with a separate user configuration for asset authoring; do not reuse interactive preferences. The generator redirects MPFB's data preference for the process and does not save Blender preferences.

The shipped people are six club members ([SC-HUM-07](../../../docs/research/scenery-implementation/SC-HUM-07/README.md)), each defined by an outfit file in [outfits/](outfits/): MPFB macros (gender, age, weight, height, ethnicity), proxy, skin, clothing, accessories, decimation, texture sizes and, optionally, a CC0 pose per pose kind. Generate each outfit and pose, merge all of them into one shared atlas, then package each pose:

```text
blender --background --factory-startup --python tools/scenery/population/generate_people.py -- --pose standing --outfit tools/scenery/population/outfits/woman_tee.json --mpfb-user-data /your/isolated/mpfb-data --output-dir /your/out/woman_tee
blender --background --factory-startup --python tools/scenery/population/merge_people_atlas.py -- --shared /your/merged people /your/out/*/person_*.gltf
python tools/scenery/population/package_population.py /your/merged/person_woman_tee_standing.gltf /your/staged/assets/people/woman_tee_standing.glb
```

Poses are `standing`, `seated` (packaged as `<outfit>_sitting.glb`) and `pilot`. `Population.OUTFITS` lists which outfit appears in which pose and zone; every listed variant must ship. Set the two atlas textures' import to VRAM compressed with mipmaps (`compress/mode=2`, `mipmaps/generate=true`; `compress/normal_map=1` for the normal atlas) and update `RUNTIME_MANIFEST.json`. Each person must stay within 8,000 triangles and, at natural size, inside its prefab's collision envelope (`test_scenery_build.gd` enforces both the envelope and a cap of at most 8 % shrink). Check the materials of new assets: an `.mhclo` without a `material` line exports untextured, and the merge refuses it.

Without `--outfit` the generator reproduces the LU-21 person exactly; with `--outfit`, people keep MPFB's metric height instead of LU-21's 1.75 m normalization. An explicit `--pose-file` overrides the outfit's pose: review its license and record it in the source manifest before distributing its output. On 2026-10-24 the default recipe regenerated the LU-21 poses on Linux within float noise of the frozen meshes; only the primitive-built pilot transmitter changes vertex order between runs ([SC-HUM-00](../../../docs/research/scenery-implementation/SC-HUM-00/README.md), which also gives the Linux setup). Prefer the `files.makehumancommunity.org` mirror; `files2` was about 50× slower.

The packager preserves exact PNG/JPEG bytes and writes shared `textures/<sha256>` files plus a `.source.json` record. It accepts the selected one-buffer Blender glTF/GLB exports, not arbitrary glTF extensions, remote images or data URIs. Preserve those output records in the source manifest; ship only referenced textures and import settings. Check a fresh Godot import, native 5/15/40 m views, fitted bounds, source licensing and scene budgets before replacing a frozen asset.

## Validation

```text
godot --headless --path app --script res://tests/test_landscape_population_assets.gd
godot --path app --script res://tests/test_landscape_population_assets.gd
godot --path app --script res://tests/capture_population_assets.gd -- --out=/your/capture/folder
godot --headless --path app --script res://tests/test_field_people_gaze.gd
godot --headless --path app --script $PWD/tools/scenery/population/camera_census.gd -- --out=/your/census.json
```

`camera_census.gd` drives the production camera rig along a reference sortie and reports, per view and person, the share of the flight each person is in frame and their head size in 1080p pixels (geometry only, no occlusion; [SC-HUM-00](../../../docs/research/scenery-implementation/SC-HUM-00/README.md#camera-census-2026-10-24)).

`test_field_people_gaze.gd` checks the head weight derived from each regenerated pose ([SC-HUM-03](../../../docs/research/scenery-implementation/SC-HUM-03/README.md)). A new pose must keep an eye proxy named `low-poly` and its parts' rotations at identity, or the head rig falls back to an estimate.

The native test is required for real MultiMesh readback; the headless dummy renderer skips that subset explicitly. Captures check 5/15/40/120 m LOD and all three poses' motion/pause/reset/clock wrap. PNG-per-frame runs are visual evidence, not frame-time benchmarks. See [LU-21](../../../docs/research/landscape-upgrade/LU-21/README.md) for actual measurements and limits.
