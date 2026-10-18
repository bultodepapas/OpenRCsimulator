# Habitat composition and tree-completion evidence

2026-10-18 · deterministic CPU diagnostics for the current `habitat-v1` field layout. This compares the committed 1,680-tree recipe with the equal-count historical cluster recipe. It reports layout geometry and source inventories; it does not establish ecological validity, visible leaf coverage, human readability, physical flight quality, or performance acceptance.

The full machine-readable report is [habitat-diagnostics-2026-10-18.json](habitat-diagnostics-2026-10-18.json), SHA-256 `fefd1f30d3801560c1b366f40372e9e6f6e36764c311bc6a4076cf92eafdc5cb`. It includes source and tool identities, per-patch measurements, nearest-neighbor distributions, skyline proxies, exclusion checks, asset inventory, and conditional LOD dispositions.

| Recipe | Trees | Eligible patch area | Far stems/ha | Wind-swept card-disk occupancy | Far nearest-neighbor median / p95 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Historical clusters | 480 near + 1,200 far | 11.4024 ha | 105.24 | 98.66% | 6.116 / 10.078 m |
| `habitat-v1` | 480 near + 1,200 far | 24.8445 ha | 48.30 | 83.56% | 7.772 / 14.916 m |

`habitat-v1` has twelve irregular, anisotropic patches. Their tree counts range from **55 to 173** and sum to 1,200; the patches do not each contain 100 trees. Per-patch eligible densities range from 39.15 to 61.46 stems/ha. Both layouts keep the same 480 near and 1,200 far positions budget, with 9 m near and 4.5 m far minimum spacing checks passing.

The skyline calculation samples horizontal wind-swept card envelopes at 0.25° from the pilot. Combined angular coverage is 82.92% for `habitat-v1`, with open intervals of 20.5° at 210°, 16.25° at 30.125°, 13.25° at 86.875°, and 11.5° at 271.5°. These are geometric screening results: the calculation does not include camera FOV, elevation, terrain, card alpha, or lighting, and it does not designate a visual defect.

The maximum card-plus-wind horizontal radius is 14.351 m against the runtime 15 m clearance, leaving 0.649 m of derived margin. The full-envelope checks report zero collisions with the protected crown gaps, rough-surface containment failures, runway/mown strips, rotorpad, authoritative lake bank, and the three configured scenery tracks (`access-track`, `worn-parking-door`, and `worn-door-pits`). The lake mask is the 20-vertex bank polygon in `app/data/fields/lake.json`; it is separate from the scenery groups. The checked default scenery has no separate RC course geometry, so the three tracks are not treated as a complete course layout.

Eight mature tree forms are present in the imported vegetation catalog; their source heights range from 7.265 to 11.651 m. The far atlas has three named forms (`CommonTree_1`, `CommonTree_3`, `Pine_1`), leaving five imported forms without matching cards. There are seven named saplings, all in the club zone, and no tree-role source below 5 m. Shrub, herb, grass, flower, and reed resources exist, but no countryside/forest understory group is configured; an age-structured woodland margin still needs habitat review and a coordinated ground mask.

Oak source evidence distinguishes what is retained from what runs: the source archive includes supplier LOD1 (842 triangles) and LOD2 (14 triangles), while the runtime catalog imports supplier LOD0 and enables Godot-generated LODs. Supplier LOD1/LOD2 remain excluded because their alternate envelopes and prerendered branch/foliage representation have not been qualified. The current L8a/L8b disposition belongs to the [tree-completion record](../README.md); this habitat inventory does not decide which close-range representation to adopt.

The hypothetical +25% and +50% layouts would contain 2,100 and 2,520 trees, exceeding the current 1,680 field-loader limit by 420 and 840. They were not generated. Each increment would add 2,520 or 5,040 card triangles at six triangles per tree and has no same-target performance or flight-readability evidence; both remain deferred.

## Reproduction and limits

Run `python tools/trees/habitat_diagnostics.py --check --out <new-report.json>`. The checker confirms that the current field treeline exactly matches the generator output, the two recipes preserve the same loader budget, and all listed placement contracts pass. Inputs include the default field, lake, scenery tracks, card and vegetation catalogs, tree identity and wind contracts, and loader constants. Their SHA-256 identities are in the report.

Verified on this working tree with `python -m py_compile tools/trees/place.py tools/trees/habitat_diagnostics.py tools/trees/test_habitat_diagnostics.py`, `python -m unittest discover -s tools/trees -p 'test_place.py'` (10 passed), and `python -m unittest discover -s tools/trees -p 'test_habitat_diagnostics.py'` (5 passed). The diagnostics leave the default field untouched. The full forest plan still requires its independent native-view, temporal, performance, flight, owner-readability, lifecycle, and export evidence; these CPU measurements close none of those gates.
