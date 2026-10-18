# L6c / L7-R1: mixed woodland understory

2026-10-18. The four default-field woodland margins now combine 24 fern cards, 16 tall-grass cards and eight flowering-shrub cards, plus the existing twelve short-grass meshes. This replaces the previous 48 identical flowering-shrub cards. All plant geometry comes from the retained downloaded Quaternius assets; the existing baker renders their original Base Color/Alpha into four-view atlases. No tree or plant was modeled. [Bake provenance](bakes/L6c-impostor-bakes.md).

The recipe uses deterministic, compact, asymmetric groups with coherent species clusters and mixed heights. Final fern heights span 0.255–0.452 m, tall grasses 0.502–1.092 m, flowering shrubs 0.527–0.945 m and short grasses 0.130–0.250 m. The fern is fitted using its measured height within the square source frame; its card stays inside the old flowering-card envelope. Stable IDs, quality subsets, ground contact and all existing runway/lake/scenery/tree exclusions remain checked. The default field, collision world and physics inputs are unchanged.

Four 4 × 4 m terrain-sampled litter patches use the unmodified **Forest Leaves 02** diffuse JPG by Rob Tuytel / Poly Haven, under CC0. [Source comparison and download](../resource-research.md). Godot imports a 512 px copy with opaque mipmaps, tiled at the supplier's approximately 3 m scale. A restrained irregular alpha blend joins it to the existing ground and fades between 45 and 80 m. Its immutable material/texture is shared across scene rebuilds; sampled meshes and scene nodes remain per-build.

## Visual review

The first candidate left ferns too small and the litter too prominent. The retained version restores the full qualified footprint allowance for low fern silhouettes, compacts shrub centers to 72% of the earlier spacing and softens litter opacity. The red `bush_common` source was rejected because it did not fit the green setting; no recolored replacement texture was invented.

| View | Before | Accepted |
| --- | --- | --- |
| East north | [Baseline](baseline-native/woodland-edge-east-north_close.png) | [Candidate](candidate-final/woodland-edge-east-north_close.png) |
| Southwest | [Baseline](baseline-native/woodland-edge-southwest_close.png) | [Candidate](candidate-final/woodland-edge-southwest_close.png) |
| Near eye height | — | [Southwest](candidate-eye/woodland-edge-southwest_close.png) |

Five full-field static views and four near-eye patch views use Windows Godot 4.7.2 Compatibility, RTX 3090, 1280×720 and 4× MSAA. The fixture recomputes its camera target from plant positions, so before/after camera centers differ slightly; these are composition comparisons, not pixel-parity images. Plant silhouettes remain stylized four-view billboards with source shading and visible limitations at very close or elevated viewpoints. This is a bounded understory improvement, not photorealistic forest or owner-readability acceptance.

## Cost and validation

The habitat changes from 1,956 triangles / five batches to **1,988 triangles / six batches**. The complete scenery check counts **649,951 / 650,000** source triangles, leaving 49. The two additional RGBA atlases contain 2 MiB of decoded base-level pixels; native readback measures 1,048,575 bytes for the litter texture with mips. Together this is about 3 MiB of decoded texture data, not a GPU-residency measurement.

Three native processes each run nine alternating reference/candidate build pairs per quality. Median-of-process warm medians are 5.738 → 8.071 ms for balanced and 6.551 → 9.387 ms for high; low remains 3 µs. These measure CPU construction only, with shared dependencies warmed inside each process and uncontrolled desktop load. No FPS improvement or frame-time qualification is claimed. The retained reference uses its own v1 recipe and the same current dependencies.

The initial 1K litter candidate exceeded the existing cold scenery-build test (958 and 1,002 ms against 800 ms). After retaining the immutable floor material and using a 512 px import, the final comparison passes at **732.3 ms reference / 761.8 ms candidate**; the threshold is unchanged. Earlier failed timings remain in the receipts. These are local observations, not a universal startup guarantee.

Accepted checks:

- Placement generator `--check` and all four Python tests; full card envelopes, floor squares plus 1 m clearance, fixed population, source identities and deterministic regeneration.
- Woodland runtime: 28 checks; imported hedges: 31; landscape vegetation: 36; final scenery-build regression passes.
- Native probe: all 48 card source selectors, ground contact and conservative culling bounds; all 36 floor vertices and 32 triangle windings; three processes complete without engine errors.
- Three real Home/Fly/Home cycles: stable 612 Home / 1,091 flight nodes, zero orphans, released audio and removed private settings. First draws remain paused at tick zero by controller safety; this is lifecycle evidence, not active flight.
- Windows release export succeeds. A standalone engine beside the exported EXE/DLL reads its embedded pack, loads the new shaders/textures/manifests/license and builds the 1,988-triangle habitat. The release executable also launches headlessly for ten frames. Its forced quit reports two ObjectDB instances; the normal lifecycle probe is the teardown evidence.

The raw `.pck` alone lacked the existing native ground-vehicle DLL, and the release executable does not run the external inspection script; those diagnostic attempts are not passes. The final embedded-pack check uses the complete EXE/DLL export. Linux/macOS filters include the same notices, but their packages and the full application suite were not rerun. Known static-oak material warnings remain.

## Reproduce and inspect

Runtime: `app/scenery/woodland_edge_habitat.gd`, `woodland_cards.gdshader`, `woodland_floor.gdshader`. Recipe source: `tools/trees/place_woodland_edges.py`; regenerate with Python, then run `--check` and `tools/trees/test_place_woodland_edges.py`. Use the bake commands in the linked source record and their `--check` option to verify original asset/atlas hashes.

Run the existing [woodland capture fixture](../woodland-edges/woodland_capture.gd) with native Godot, `--path app --script <fixture> -- --out=<new-folder>`. [eye_capture.gd](eye_capture.gd) changes only the close camera offset. Never overwrite retained evidence. The [native probe](refinement_probe.gd) takes `--reference=<script> --output=<new-json> --first=reference|candidate`; bind the retained `reference/woodland_edge_habitat.gd` DATA_PATH to an absolute scratch copy of its sibling `woodland_edges.json` before running. It does not alter production files.

[Receipts](receipts/) retain tests, loading, exports and raw timing reports. [identity.json](identity.json) pins sources, fixtures, images and logs. Checks were performed on the shared working tree, not a frozen release checkout. The four litter patches share one transparent mesh with broad bounds; their small geometry and 80 m fade limit cost, but general transparency sorting across arbitrary custom worlds is not qualified. Custom field/scenery/lake inputs skip this decoration.
