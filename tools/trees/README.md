# L6a tree authoring pipeline

The [vegetation-renewal evidence](../../docs/research/visual-quality-implementation/L6c/vegetation-renewal/README.md) records the realistic source recipe and its accepted atlas proof. This guide owns the bake procedure; the current source choices do not change the card runtime contract.

The explicit `--recipe realistic` source set keeps the existing catalog slot IDs stable and records a distinct `source_asset_id` for each asset:

| Stable tree slot | Source asset ID | Source |
| --- | --- | --- |
| `CommonTree_1` | `landscapelab:quercus` | LandscapeLab Quercus |
| `CommonTree_3` | `lolipop:acer_large_3_lod1` | LOLIPOP Acer maple |
| `Pine_1` | `landscapelab:pine` | LandscapeLab joined pine |

The adapter wraps each selected scene to normalize its height to 1 m and put its stem at the grounded origin. The wrapper preserves the supplied mesh geometry, node transforms and material identities; it does not generate new plant geometry. The field runtime still uses three crossed atlas quads per tree (six triangles, one lit alpha-scissor surface). Close scenery remains the separate [downloaded vegetation library](../landscape/vegetation/README.md), not a mesh/card LOD transition. L6b/L7 own distribution and L6c owns flight readability. The source GLBs are not approved as L8 close-range LODs.

`--recipe legacy` remains the default and reproduces the historical Quaternius card atlas. That legacy recipe is retained for comparison and reproducibility; its source and CC0 record are marked historic in [landscape provenance](../../assets/landscape/PROVENANCE.json).

```sh
npm ci --prefix tools/trees
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" -m unittest discover -s tools/trees -p 'test_*.py'
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" tools/trees/build.py --out /tmp/tree-realistic-A --recipe realistic --match-atlas app/assets/landscape/trees/atlas.png
PYTHONDONTWRITEBYTECODE=1 "$(app/tests/visual-env.sh)" tools/trees/build.py --out /tmp/tree-realistic-B --recipe realistic --match-atlas app/assets/landscape/trees/atlas.png
```

The legacy bake remains available with `--recipe legacy` (also the default). Use `--recipe realistic` for the pinned replacement inputs. `--match-atlas` still checks mask alignment against the selected runtime color atlas; it does not replace or recolor that atlas. For a full source-set change, review the source/derived comparisons and repeat-bake evidence before promotion.

Requires pinned Godot 4.7.2 (`app/get-godot.sh`), Node 24 and the existing pinned visual Python environment. Linux captures use Xvfb; Windows runs Godot natively. `--out` must be new/empty. The pipeline verifies all recipe source hashes and dependencies, validates glTF/GLB inputs, normalizes tree height to 1 m, decodes each selected scene with GLTFDocument in an isolated project, renders source/derived comparisons, assembles the atlas, repairs alpha borders and inspects all mip levels. Subprocesses have timeouts and engine-error gates. Nothing writes back to `app/` automatically.

Normalization preserves topology, UVs, normals, textures and alpha cutoff. The upstream glTF has COLOR_0 components up to 1.00016785; the adapter permits only that reviewed small excursion (<=1.0002) and clamps it to 1. Any other source validation error is refused. The remaining Khronos warning is generated tangent space on the normal-mapped bark; Godot's importer ensures tangents. This is irrelevant to the unshaded albedo bake, and retained in the lit diagnostic.

Source and derived decoders explicitly use lossless images, generated mipmaps, full geometry and uncompressed mesh attributes. An editor-import prototype gave external and embedded textures different mip defaults, and fresh imports changed pine pixels. The final offline loader uses `GLTFDocument` with embedded uncompressed images and explicit image mip generation, avoiding editor extraction/cache jobs. The runtime atlas still goes through the normal editor importer and clean-export tests. The bake is unshaded: it does not bake the diagnostic sun into the atlas. Original authored texture/vertex coloration is retained. The atlas has no baked geometric normals: close views of its crowns will look flatter than the source mesh.

Each 1024² binary-alpha raw image is resolved to a 512² tile with alpha-weighted RGB and coverage alpha. Margins must be >=16 px. Acceptance is silhouette IoU >=0.995, RGB MAE <=0.05/255 and <=0.1% common opaque pixels differing by >2 channel levels. High per-pixel errors at rare leaf occlusion boundaries are reported, not hidden; float32 normalization changes a few raster edge samples. A source or palette change still needs human review. Runtime import is lossless, straight alpha, fix-alpha-border and mipmaps, with 3D auto-compression disabled.

For a new source set, inspect the source/derived comparisons, mips and independent repeat hashes before promotion. After that source set becomes the runtime recipe, a reproducibility bake must reproduce its runtime color atlas byte-for-byte. For a mask-only palette change, use `--match-atlas app/assets/landscape/trees/atlas.png`; this checks the baked silhouette against the existing atlas and sets the mask's final alpha channel to the runtime alpha exactly. It fills the few runtime-only edge texels from the nearest material-ID label in the source-derived mask and rejects silhouette IoU below 0.995. Promote only the reviewed atlas, foliage mask, catalog, aggregate license and three per-slot notices in `app/assets/landscape/trees/`. Refresh `assets/landscape/PROVENANCE.json` and proof reports after the promoted runtime hashes are final. Do not overwrite imported assets during a running editor/test.

The generated `foliage_mask.png` shares the color atlas UVs. Its red channel encodes source glTF surface materials by exact material name, derived from the source assignments and alpha textures rather than painted or inferred from RGB. The realistic recipe preserves these names: `branches` / `leaves` for Quercus, `Maple_Bark_PBR` / `Maple_Leaves_PBR` for Maple, and `branches.001` / `leaves.001` for Pine. The legacy recipe retains its original `Bark_NormalTree`, `Leaves_NormalTree` and `Leaves_Pine` names. The bake rejects unknown identities and requires raw mask alpha to match the adapted albedo coverage byte-for-byte. The atlas processor alpha-weights the aligned mask downsample, leaving silhouette edges fractional. Runtime samples red as linear data and applies the forest palette variation to foliage only. The fourth tile remains transparent.

The [L6b-R2 mask verifier](../../docs/research/visual-quality-implementation/L6b-R2/foliage-mask/fixtures/verify_mask.py) remains tied to that report's retained Quaternius atlas, mask and build manifest. It is historical evidence, not a gate for the renewed runtime bundle; its fixture and hashes are preserved unchanged. Use the current-runtime hashes in [vegetation-renewal evidence](../../docs/research/visual-quality-implementation/L6c/vegetation-renewal/README.md) for the renewed atlas.

```sh
app/test.sh
mkdir -p /tmp/tree-card-review
LP_NUM_THREADS=1 xvfb-run -a "$(app/get-godot.sh)" --path app \
  --rendering-driver opengl3 --audio-driver Dummy --script "$PWD/tools/trees/inspect_cards.gd" \
  -- --out=/tmp/tree-card-review
```

The fixture shows the actual runtime factory at four rotations. A caller in L6b should build one mesh per species and reuse it in sector MultiMeshes; disable card shadow casting. The transparent card frame extends below zero, while the **visible trunk** is at zero; its center is `pivot_y_m`, not half the padded image height. The test checks the lowest visible texel rather than only the quad bounds.

Run `app/export.sh` in a fresh clone to verify every pack without loose-file fallback. `check_field_pack.gd` loads the catalog, license and imported atlas through the adapter in all three packs. No GLB, source texture, npm package or runtime generator belongs in the exported tree family. llvmpipe images do not establish RTX 3090 frame times.

## L6b/L7 placement and rendering

`python3 tools/trees/place.py` regenerates only `objects` in the default field. `--check` verifies the committed data without writing it. Positions are pilot-relative NED offsets on a 0.25 m grid, marked as derived estimates rather than surveyed geography. The L6b recipe remains frozen at 480 near trees, seed `610602`, radius 270–570 m; its position digest is `9b42b61ff36e5df25ef0245702e4d75965ea805f81de56a1c353fd1f0c722875`.

The historical `existing` control places 1,200 far trees from seed `610607`: twelve 100-tree clusters with 55 m patch radii, tree centers in the 600–1,500 m ring, 4.5 m minimum within-patch spacing and the same two crown-cleared gaps and runway/mown corridor. The canonical habitat recipe shares the existing eight azimuth-sector MultiMeshes, so the model keeps six triangles per tree and adds no draw calls. The field loader caps the combined set at 1,680 positions and 1,500 m.

**`groves-v2` (L7-R4) is the default.** It keeps the groves-v1 near ring and turns the twelve habitat-v1 far sites into single-species woods at 220 m² per tree (seed `620102`; 61 frozen trees in the skyline sectors). New far trees keep clear of the countryside roads, the asserted farm boxes, the woodland-edge floors and the farm habitats. Generation takes about 11 s. [Far-ring evidence](../../docs/research/visual-quality-implementation/L7-R4/README.md).

`groves-v1` (L7-R3) keeps the habitat-v1 far ring byte-for-byte and regroups the 480 near trees:
- 9 woods of 24–57 trees, each one dominant species (shares 0.78–0.94), at 160 m² per tree, lower at the margin;
- 4 hedgerow lines of 14 broadleaf trees;
- 24 solitary field trees;
- 44 frozen L6b trees in the 64–92° and 254–268° skyline sectors, where `tools/scenery/place.py` places the turbines, pylons and village.

Seed `620101`. Species and height stay the renderer's position hash; the generator accepts candidates by their hashed identity. New trees keep 22 m from committed scenery placements beyond 200 m. The script writes the field CRLF on every OS, matching `.gitattributes`, so raw-byte pins agree across platforms. After a run, check `tools/scenery/place.py --check` (landmarks must not move), then regenerate `bake_countryside.py` and `place_woodland_edges.py` and update the companions field pin. `woodland_edges.json` pins the text of `place.py`, so regenerate it after any edit to this script. [Evidence](../../docs/research/visual-quality-implementation/L7-R3/README.md).

`habitat-v1` (L7-R1, the previous default) keeps the frozen 480 near coordinates and 1,200 far-tree budget, but varies twelve far-patch counts (55, 64, 72, 82, 88, 92, 96, 102, 110, 124, 142 and 173), anisotropic axes (68–155 m by 43–92 m), orientation and irregular notched margins. Patch envelopes leave intervening gaps; every crown still clears the existing viewing gaps and runway/mown corridor, and all far trees retain at least 4.5 m spacing on the 0.25 m grid. Seed `610617` produces bounds N `-1326.50..1205.25` m and E `-1266.00..1176.25` m. The field provenance records the seed, counts, overall bounds and position hashes; generator JSON also lists each patch center, shape and bounds. These are estimated visual-composition data, not surveyed geography or an ecological simulation. The explicit `--recipe existing` option retains the previous circular-patch layout as a historical control.

Verify the canonical field and, when comparing the historical control, generate it in a copy of the production field:

```powershell
New-Item -ItemType Directory -Force tmp/tree-quality-implementation | Out-Null
python3 tools/trees/place.py --check
python3 tools/trees/place.py --recipe habitat-v1 --check
Copy-Item app/data/fields/default.json tmp/tree-quality-implementation/historical-field.json
python3 tools/trees/place.py --recipe existing --field tmp/tree-quality-implementation/historical-field.json
python3 tools/trees/place.py --recipe existing --field tmp/tree-quality-implementation/historical-field.json --check
```

The CPU and shader keep the original +2400 identity hash coordinates for every L6b position. They use +8192 only when a south/west coordinate falls below that original unsigned range. Packed transforms use four exact bytes with +8192, which covers the full L7 radius through Compatibility's float16 instance-data path. Near instances form a prefix in each sector; `near_instance_count` and `far_instance_count` metadata let captures show only the near ring through `MultiMesh.visible_instance_count`.

The tree shader scales alpha gently from the screen-space mip footprint for far instances only. This compensates for the atlas's averaged alpha mips in the Compatibility renderer, where alpha-to-coverage is unavailable. Near trees keep the L6b alpha path unchanged.

Run the recipe regression with `python3 tools/trees/test_place.py` and the app's generated-data check with `python3 tools/trees/place.py --check`. `python3 tools/trees/check_review.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l7-forest-review` uses Xvfb/OpenGL to measure draws and verify all 1,680 shader identities through the real MultiMesh custom-data path, then repeats thirteen PNGs byte-for-byte. It also runs `tests/test_treeline.gd` with the real renderer; the headless dummy renderer cannot prove GPU buffer readback. `app/capture.sh` runs the review as part of its visual checks.

## L15b tree wind

The render-only tree response consumes the session's shared `wind_vec` and simulation clock. The calm weather preset naturally supplies zero wind. Field cards lean rigidly (below). Close downloaded trees use the [L15b-R2](../../docs/research/visual-quality-implementation/L15b-R2/README.md) shader family `app/scenery/imported_tree_wind*`: the cards' speed/frequency law as a horizontal quadratic bend in metres, plus shading-only leaf flutter. A tree qualifies only with a measured `ImportedVegetation.TREE_WIND_LEAN_LIMITS_M` entry (Quercus 0.12 m, pine 0.22 m), the largest crown-top sway that keeps every vertex inside its unchanged collision proxy. Re-measure with that evidence's `proxy_slack_probe.gd` after changing a tree source, placement height or proxy rule. The maples (protected), the BLEND oak and the library-only Quaternius forms stay static. Run the focused card GPU evidence with:

```sh
"$(app/tests/visual-env.sh)" tools/trees/check_wind.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l15b-wind \
  --baseline-app /path/to/pre-L15b/app
```

Use a fresh output directory. The baseline is optional for later regression runs; initial acceptance includes baseline parity. The complete capture wrapper also runs this check. Its tree-only image mask permits at most 16 changed pixels in the first two columns at a frame edge already touched by a calm tree, plus one pixel within a 13 px tree-edge neighborhood per comparison. All other changes outside the original mask fail; copied-data self-tests reject larger edge, near-tree and unrelated background changes. The summary records these bounded exceptions. See [L15b evidence](../../docs/research/visual-quality-implementation/L15b/README.md) for the card-specific root rotation, parameter estimates, culling proof and limits.


## Native imported-tree comparisons

`quality_capture.gd` runs externally against an already imported, frozen `app` folder. `--mode=field` captures the production field; `--mode=gallery` captures retained source IDs at identical height with front/back/underside/overhead and deterministic wind controls. It requires native Compatibility, a new/empty `--out`, and writes PNGs plus hashes/renderer identities. `--wind=on|off`, `--cell=0|64|128|256` and `--tree_shadows=off` isolate tree treatments; `--engine_shadows=on|off` separately controls the directional light. The report records its actual shadow setting, since Compatibility's raw shadow counter may be zero while shadows are enabled. The shader clock and all other scene processing are frozen for images; timed runs update the shared clock with the same 5 m/s wind. These are static scenes, not flight simulation. The fixed `oak_close` field camera frames `shade-trees:06` identically before and after its source replacement.

Use `--ids=common_tree_1,common_tree_2,common_tree_3,common_tree_4,pine_1,pine_2,pine_3` to cover all seven mature forms. Native script example (substitute a matching Godot executable and an imported frozen project):

```powershell
& $GodotWindows --path C:/captures/tree-candidate/app --audio-driver Dummy --script "$PWD/tools/trees/quality_capture.gd" -- --mode=gallery --wind=on --ids=common_tree_1,common_tree_2,common_tree_3,common_tree_4,pine_1,pine_2,pine_3 --out=C:/captures/tree-gallery-wind
python tools/trees/check_quality_capture.py --source C:/captures/tree-gallery-static --wind C:/captures/tree-gallery-wind
python tools/trees/profile_compare.py --godot C:/Tools/Godot_v4.7.2-stable_win64.exe --baseline C:/captures/tree-baseline/app --candidate C:/captures/tree-candidate/app --out C:/captures/tree-paired --pairs 5 --warmup 10 --seconds 60 --view car_park
```

Produce the source gallery with the same command and IDs, `--wind=off` and a different output. Wind states animate only the first ID, so repeat with each qualified tree first (`landscapelab_quercus`, `landscapelab_pine`, `landscapelab_fagus`, `landscapelab_quercus2`). Exact calm parity is a native-GPU check: under Xvfb/llvmpipe even the accepted L15b-R1 shader differs by tens of pixels ([L15b-R2](../../docs/research/visual-quality-implementation/L15b-R2/README.md#native-captures-llvmpipe)). The checker verifies source/calm pixel equality, an unchanged wind-off clock control, movement/reversal, repeated time and the 1024-second wrap. The profile runner alternates AB/BA order, launches one native process at a time, rejects engine errors or changed identities, retains every sample/log and reports paired p95 differences. Keep GPU work and other benchmarks out of the measurement interval. CPU static-memory counters are not GPU residency; imported and OS file caches are not reset.

`inspect_scene.gd` prints normalized close-tree choices, source triangle totals and collision identity with lights deliberately omitted. A changed population or mesh envelope changes that world; it cannot be presented as exact replay of the previous world.

`source_gallery.gd` is the narrow Poly Haven Pine Sapling Small intake fixture. It loads the downloaded glTF outside `app/`, isolates each supplied A/B/C tree at original metre scale, preserves materials, verifies the download manifest and captures front/back/underside. Use `--source=<absolute glTF> --out=<new absolute folder> --capture=on --frame_height_m=1.65` with an isolated native Compatibility project; `--capture=off` allows metadata inspection headlessly. It does not create tree geometry or export a runtime derivative.

```powershell
npm ci --prefix tools/trees --ignore-scripts
node tools/trees/validate_sources.mjs --out tmp/tree-source-validation.json
```

The validator defaults to all seven runtime trees and the retained Poly Haven comparison; optional explicit glTF paths replace that selection. It resolves local external buffers/images, records hashes, preserves warnings, refuses missing resources and exits nonzero on validator errors. See the vegetation pipeline for the reviewed precision-only color repair.

After exporting a frozen project's Windows preset to a PCK, run `check_imported_pack.gd` with native Compatibility from an otherwise empty project root, using `--main-pack <absolute PCK> --script <absolute checker> -- <catalog SHA-256> <license SHA-256> --mip-policy=bark`. Run it against the source project with the same hashes to compare `TREE_TEXTURE_INVENTORY` records. For an oak PCK, also pass `--oak-base-image-sha256=<OAK_BASE_IMAGE_SHA256 from source run>`; the checker verifies the extra license, single 5,303-triangle mesh, static BLEND/depth-prepass material and lossless 1024² atlas. Full platform release checks remain in the repository export workflow.

## Imported bark filtering (L6b-R2)

The two shared bark maps use lossless mip chains; the normal map explicitly enables normal renormalization. The two alpha-card leaf maps remain lossless and un-mipped, and 3D auto-compression is disabled for all four. A native 720p/1080p comparison rejected ordinary leaf mips because they filled crown gaps at the preserved 0.2 alpha cutoff. Bark-only filtering preserved every silhouette mask and the shared flowering shrub's pixels. The additional decoded image data is 10.667 MiB; this is not a GPU-residency measurement. See the [raw comparisons, finite supersampled reference and exported-payload proof](../../docs/research/visual-quality-implementation/L6b-R2/README.md).

`mip_compare.py --godot <exe> --baseline <frozen-app> --candidate <frozen-app> --mip-scope bark --out <new-folder>` runs the paired eight-asset, three-distance, two-resolution, eight-phase fixture. `--mip-scope all` retains the rejected experiment for reproduction. Keep these filtering controls separate from geometry and placement changes.

Actual flight throughput and pilot readability remain separate. Use the existing `--frametimes` and [flight logging](../../docs/FLIGHT-LOGGING.md) workflows; headless numerical replay does not replay a camera through a changed forest.

## Native flight and forest review

The [completion evidence](../../docs/research/visual-quality-implementation/L6c/tree-completion/README.md) separates active-flight timing, offline camera tracks, aircraft contrast measurements and exact numerical replay. Use the direct native Godot executable on Windows; its console wrapper may return before the child finishes.

`flight_quality.py --baseline <frozen-app> --candidate <frozen-app> --pairs 5 --warmup 10 --sample 60 --out <new-folder>` runs alternating AB/BA pairs through the normal flight scene and input callback. Both apps must share simulation and measurement code. The tree comparison explicitly uses imported-tree wind off/on and unchanged default grass. Environment selectors are recorded; changing field layout is a separately identified world. Run timing alone and retain raw clocks, input reads, viewport CPU/GPU metrics, memory counters and actual renderer settings. Monitor values are estimates reported by Godot, not a vendor memory-residency trace.

For a vegetation replacement comparison, explicitly select the same wind setting on both sides, for example `--baseline-env OPENRC_TREE_WIND=on --candidate-env OPENRC_TREE_WIND=on`. The probe isolates recorded input from desktop shortcuts and connected controllers, and verifies the actual borderless viewport size. Focus loss still pauses production simulation and invalidates that run. Resume an interrupted series by repeating its exact command with `--resume` and the same `--out`: source, engine, harness and settings identities must match. Complete pairs are preserved regardless of timing results; incomplete pair attempts remain in history and receive new attempt IDs on retry. Legacy series without embedded source identities additionally require their pre-run `--resume-source-receipt <json>`; a receipt created after modifying the source cannot establish continuity.

`temporal_quality.py --app <frozen-app> --out <new-folder>` records five native flight/control camera routes at 720p and 1080p. It uses fixed 24 fps movie capture and retains per-frame camera/aircraft poses; these videos do not measure live throughput. `quality_capture.gd --motion=oak-approach|card-orbit|forest-pan|car-park-wind --frames=192` adds prescribed camera tracks around production trees; `car-park-wind` holds the car-park postcard camera still so only the trees move, and `--wind_mps` (default 5) sets the route wind. Pass the normal `--out`, `--width` and `--height` options. Those tracks contain no aircraft simulation; a mesh approach is not a mesh-to-card transition because the current imported-tree and field-card populations are distinct.

`readability_compare.py --godot <native-exe> --app <frozen-app> --out <new-folder>` captures two aircraft at 20/50/100 m against tree/sky backgrounds, with normal/autozoom views and noon/low-sun/sunset/night lighting. It reuses the existing contrast metrics, verifies image hashes and exposes invisible targets or background mismatches. Synthetic poses and pixel contrast do not establish human attitude recognition. Night cases exclude the optional aircraft night kit.

`world_replay.gd --output=<new-absolute-json> --case=trim|runway --warmup-ticks=240 --sample-ticks=2160` reuses the detached production session fixture with the complete collision world and lake. Replay the adjacent `.orfl` with `app/tools/flight_log_cli.gd` and require complete exact replay with unchanged solver identity. Equal sampled state across different worlds only applies to the tested input tape.

`palette_probe.gd --out=<new-absolute-json>` uses native Compatibility readback to compare the production world-space patch function against the CPU reference at all field-tree positions, including a translated parent. See the [retained command and exact fixture](../../docs/research/visual-quality-implementation/L6c/tree-completion/palette/README.md) for its versioned arguments and tolerance.

## Decorative woodland margins

`python tools/trees/place_woodland_edges.py --check` validates the generated `app/data/woodland_edges.json`; omit `--check` to regenerate it. `python tools/trees/test_place_woodland_edges.py` checks determinism, source geometry bounds and field/scenery exclusions. The runtime builder in `app/scenery/woodland_edge_habitat.gd` reuses the existing downloaded shrub atlas and short-grass mesh. It adds four small default-field patches, with five high-quality batches and 1,956 triangles; balanced quality is a stable subset and low quality omits this decoration.

The original woodland-edge acceptance configuration contained 649,919 source triangles under its 650,000 cap. That dated count is not current free capacity: the shared world has since exceeded this cap; see [current vegetation evidence](../../docs/research/visual-quality-implementation/L6c/vegetation-renewal/README.md). [LU-34](../../docs/research/landscape-upgrade/LU-34/README.md) has since replaced the pooled cap with per-subsystem source allowances (close vegetation 150,000, botanical 90,000) and a drawn-cost budget per view. Margins do not enter field/scenery data or the collision world. Inputs that differ from the bundled default field, scenery groups or lake skip the recipe. Source hashes in the generated report describe provenance; runtime does not compare text hashes across platform line endings. Re-run the generator and `test_woodland_edge_habitat.gd` plus complete scenery-budget checks after changing the bundled sources or exclusions.
