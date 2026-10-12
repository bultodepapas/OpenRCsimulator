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

```text
blender --background --factory-startup --python tools/scenery/population/generate_people.py -- --pose standing --mpfb-user-data /your/isolated/mpfb-data --output-dir /your/temporary/output
python tools/scenery/population/package_population.py /your/temporary/output/person_standing.gltf /your/staged/assets/standing.glb
```

Repeat with `--pose seated` → `person_seated.gltf` → `sitting.glb`, and `--pose pilot` → `person_pilot.gltf` → `pilot.glb`. Default poses are the vendored CC0 BVHs. An optional `--pose-file` is an authoring override: review its license and update the source/hash manifest before distributing its output. The frozen meshes were imported/rendered and audited; the relocated parameterized recipe has static validation only.

The packager preserves exact PNG/JPEG bytes and writes shared `textures/<sha256>` files plus a `.source.json` record. It accepts the selected one-buffer Blender glTF/GLB exports, not arbitrary glTF extensions, remote images or data URIs. Preserve those output records in the source manifest; ship only referenced textures and import settings. Check a fresh Godot import, native 5/15/40 m views, fitted bounds, source licensing and scene budgets before replacing a frozen asset.

## Validation

```text
godot --headless --path app --script res://tests/test_landscape_population_assets.gd
godot --path app --script res://tests/test_landscape_population_assets.gd
godot --path app --script res://tests/capture_population_assets.gd -- --out=/your/capture/folder
```

The native test is required for real MultiMesh readback; the headless dummy renderer skips that subset explicitly. Captures check 5/15/40/120 m LOD and all three poses' motion/pause/reset/clock wrap. PNG-per-frame runs are visual evidence, not frame-time benchmarks. See [LU-21](../../../docs/research/landscape-upgrade/LU-21/README.md) for actual measurements and limits.
