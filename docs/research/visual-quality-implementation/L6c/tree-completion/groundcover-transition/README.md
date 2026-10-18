# L7-R1 / L6c: layered groundcover at woodland margins

2026-10-18. The four default-field margins now contain **220 plants in five render batches**, compared with 60 plants in six batches. Existing fern, tall-grass and flowering-shrub cards remain unchanged. A four-view bake of the already downloaded Quaternius CC0 `Grass_Common_Short` replaces twelve 155-triangle grass meshes and supplies 160 additional low tufts. No plant was modeled and no source mesh or texture was edited. [Bake and license provenance](bakes/README.md).

## Placement and appearance

Each margin has twelve existing mixed-species cards and 43 short-grass cards. Five irregular grass groups have unequal populations, seed-driven offsets, yaw and heights that taper toward their outer edges. New heights span 0.152–0.378 m; centers stay within 4.84 m of the original patch center. The twelve retained edge accents preserve their IDs and positions and shrink to 0.075–0.144 m so their complete square cards fit inside the former mesh envelopes. Balanced quality remains a deterministic strict subset; low quality omits the decoration.

The generator checks full billboard radii, the existing patch footprints and all runway, lake, tree and scenery exclusions. Soft grass and shrubs may overlap visually; the former decorative grass-versus-shrub separation is intentionally removed. No collision proxy, field definition or simulation code changes. The v3 runtime consumes explicit `grass_cards`; legacy grass arrays remain provenance for the old footprint calculation.

| Fixed camera | Before | Current |
| --- | --- | --- |
| East north, elevated | [60 plants](baseline-overview/woodland-edge-east-north_close.png) | [220 plants](final-overview/woodland-edge-east-north_close.png) |
| Southwest, eye height | [Before](baseline-eye/woodland-edge-southwest_close.png) | [Current](final-eye/woodland-edge-southwest_close.png) |
| Northwest, elevated | [Before](baseline-overview/woodland-edge-northwest_close.png) | [Current](final-overview/woodland-edge-northwest_close.png) |

All four patches and one field-wide view were captured at both camera heights on native Windows Godot 4.7.2 Compatibility / RTX 3090, 1280×720, 4× MSAA. Cameras use the same recipe centers and sampled ground in both versions. The new tufts extend the groups into the surrounding ground without changing the main forest. Close silhouettes remain stylized billboards: the source vertex colors produce conspicuously dark grass roots, and this iteration does not establish photorealism or independent pilot preference. The final terrain-cache change produces byte-identical PNGs to the uncached candidate in all ten views.

## Geometry and construction cost

Habitat geometry falls **1,988 → 472 triangles** (76.3% fewer), with **6 → 5 batches**. The complete lake-aware scenery test counts **648,435 / 650,000 triangles**, leaving 1,565. The added 1024×256 RGBA atlas uses 1 MiB of decoded base-level pixels; this is not a GPU-residency measurement. It uses the existing lossless, unmipped alpha-card import policy.

The first implementation repeated terrain queries for every new card and raised warm high-tier build cost to about 21.4 ms. The accepted runtime caches at most 220 scalar terrain heights for the exact default world. It caches no scene nodes, meshes or mutable plant metadata. Custom field/scenery/lake inputs still skip this feature.

Three native processes each run nine alternating reference/candidate pairs per quality, with first-side order reference/candidate/reference. Median-of-process warm medians:

| Quality | Reference v2 | Current v3 |
| --- | ---: | ---: |
| Low | 3 µs | 3 µs |
| Balanced | 6.826 ms | 7.020 ms |
| High | 9.274 ms | 8.966 ms |

These are CPU construction calls with uncontrolled desktop load and shared dependencies warmed within each process. They do not establish FPS, GPU cost or a statistically significant improvement. The original three uncached pairs and final three pairs are retained in [receipts](receipts/).

**The 800 ms cold scenery-build gate remains unresolved on this host.** The initial candidate measured 998.7 ms; a paired follow-up measured 935.6 ms reference and 865.2 ms candidate, both failures. The final candidate measured 814.2 ms and still failed that one assertion. The threshold is unchanged and this is not reported as a passing performance gate. This test's scenery-only fixture omits the lake and counts 624,091 triangles; the lake-aware complete-scene test above is the aggregate budget check.

## Verification

- Generator `--check`, five Python checks and Blender source/atlas `--check` pass.
- Woodland runtime: 29 checks; full landscape vegetation: 36; imported hedge: 31. Scenery-build geometry/behavior checks pass, with the cold timing failure recorded above.
- Native probe checks all 220 GPU instance selectors, terrain contacts and billboard bounds, plus 36 floor vertices and 32 triangle windings. Three final processes complete without engine errors.
- Three real Home → Fly → Home cycles complete with stable 610 Home / 1,089 flight nodes, zero orphans, released audio and removed private settings. Controller safety pauses first draws at tick zero; this is lifecycle evidence, not active flight.
- Windows release export succeeds. A standalone Godot engine beside the exported EXE/DLL opens its embedded pack, loads the new atlas/manifest and builds the 472-triangle, five-batch habitat without engine errors. Export identities are retained in [export-identity.json](receipts/export-identity.json).

Known static-oak material warnings persist. The first capture fixture attempts failed on a missing recipe center key; corrected baseline/final captures use `floor_center_ne_m` and complete. No full application suite, native frame-time campaign or Linux/macOS export was rerun. Measurements use the shared working tree, with unrelated grass work preserved, not a frozen release checkout.

## Reproduce

Regenerate with `python tools/trees/place_woodland_edges.py`, then run the same command with `--check` and `python tools/trees/test_place_woodland_edges.py`. Run the three focused GDScript tests above with native pinned Godot and `--headless --path app --script res://tests/<test>.gd`.

Use [capture.gd](capture.gd) with a real Compatibility renderer, `-- --out=<new-folder> --view=eye|overview --plants=220`. For the baseline, use the retained v2 builder/recipe/shader in [reference](reference/) and `--plants=60`. [probe.gd](probe.gd) takes `--reference=<script> --output=<new-json> --first=reference|candidate`: first copy the retained builder into scratch and bind its `DATA_PATH` and card shader path to absolute paths of the retained siblings. It compares both versions against current shared dependencies. [identity.json](identity.json) records the delivery sources, fixtures and receipts; raw failed and preliminary runs remain distinguishable by name.
