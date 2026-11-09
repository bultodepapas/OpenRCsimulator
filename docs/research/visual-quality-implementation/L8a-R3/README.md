# L8a-R3 Field-tree source alignment

2026-11-09 · Landscape **L**, coordinated with SC/LU. Implements the source-identity repair identified in the supplied vegetation audit. Baseline: `979819ecceb9f14799c31ca81521034e8498940a`; unrelated Timber/Workshop edits were present and preserved. [Tree plan](../../../plans/tree-forest-quality.md), [pipeline and reproduction](../../../../tools/trees/README.md).

Other work advanced HEAD and updated scene-detail recommendations during this session. The validation receipt records the final observed HEAD and shared dependencies; the current scene-detail and collision-setup suites also passed. This delivery does not claim ownership or full verification of those other edits.

## Result

The `CommonTree_3` field-card tile now comes from the existing downloaded LandscapeLab **Fagus**, matching its detailed field-tree model. Oak and pine tiles, including their material masks, retain identical decoded pixels. The blank fourth tile stays blank. No model, texture painting, new species or runtime dependency was created. The four scenery maples retain their resources.

The new `--recipe field` pins the three downloaded sources, original material names and notices. The Fagus notice includes Krzysztof Golik's leaf-photograph attribution and the upstream license evidence. Historical `realistic` (oak/maple/pine) and `legacy` recipes remain available. New tests bind card source hashes/material identities to the actual detailed-model catalog.

All 1,680 tree positions and identities remain unchanged: High selects the same 127 detailed trees; Extreme selects 480. Cards still have six triangles and eight sector batches. Regenerating woodland-edge data changed only source hashes; its 220 plants, placements, 472 triangles and five High batches remain unchanged. Texture import settings, filtering, wind laws and detailed tree models remain unchanged.

## Collision decision

This is an explicit static-world revision. A visual preset or camera movement never changes collision. The existing proxy volume must remain covered because Extreme can display a detailed model where the permanent world uses the card-proxy path.

| Slot-1 fraction of tree height | Previous maple card/proxy | Measured beech card | Retained collision envelope |
| --- | ---: | ---: | ---: |
| Horizontal half-width before the 0.24 m wind allowance | 0.339478 | 0.324097 | 0.339478 |
| Lowest foliage / crown edge | 0.194877 | 0.136352 | 0.133 |
| Highest foliage / crown edge | 1.002877 | 0.982300 | 1.003 |

The shader uses the measured beech crown center/shape. Collision uses the union of the previous volume and the new lower foliage, rounded outward. Replacing the old alpha-width equality check with **containment**, plus independent regression checks for the previous horizontal and vertical volume, prevents a smaller baked silhouette from shrinking mesh coverage. Existing alpha-extrema contact sweeps remain enabled. The smaller visual width also stays within the placement generator's historical horizontal allowance; no relayout was required.

The complete fixture world retains 6,092 proxies, with identity changing from `4e28a8ab799eb75b921cb2ac70946548e812d0ce607d536b6b3c624887962e9f` to `8c49e45696cbd0c126060041800e5e42b8a671c085aa18175245616c0dabe53b`. These identities include this checkout's complete fixture scenery. Existing checkpoints from a different world remain subject to the normal compatibility checks.

## Verification

- Two independent final bakes produced identical bytes for all 30 derived artifacts and all 15 raw comparison/material-mask frames. All source/normalized silhouette and color gates passed. [Bake manifest](bake-manifest.json), [atlas analysis](atlas-analysis.json), [repeatability](repeatability.json).
- Native Windows, Godot `4.8.beta2.official.cafc17a19`, Compatibility/OpenGL, RTX 3090, NVIDIA driver `617.42`: matched **1920×1080** pilot, aerial and forest overview captures; a 48-frame forest pan with 5 m/s render wind. Static views and sampled motion frames were inspected. These contain no simulated aircraft and establish neither attitude readability nor frame pacing.
- Checked Godot passes: tree assets (68 checks), native treeline runtime (29,579), field-tree detail, collision coverage (75), checkpoint (18), collision session (25), companion airspace (48), woodland edges (29) and scene-detail selection. Parse/import checks also passed. The field-detail test intentionally exercises an invalid LOD option and emits its expected fallback warning.
- Python passes: pinned recipe/adapter (3), atlas processing (15), repeat-gate rejection (1), woodland placement (6); tree and woodland generators passed `--check`.
- Baseline and final candidate each recorded and exactly replayed **2,400 ticks / 2,401 rows**, `complete=true`, `solver_changed=false`. Solver fingerprint stayed `88d3533f90ca78c75f3435305b5ed3241d5794dd7f6ed0a11506ab0aab82fefb`. The two exported trim-flight CSVs are byte-identical. This tests that input tape away from the changed contacts; different collision worlds are not generally equivalent or physically validated.

[Validation receipt](validation.json) retains source/engine identities, successful checked-run references, native capture hashes/counters and replay results. Full local logs, PNGs, `.orfl` recordings and CSVs remain under ignored `tmp/vegetation-source-alignment-20261109/`; no capture images were added to Git. The exact-hashed tree text files use explicit LF checkout rules; raw JSON receipts preserve their native bytes. [Fresh-clone receipt](fresh-checkout.json): resource/receipt hashes matched with `core.autocrlf=true` and `false` in a disposable sparse Git fixture. This checks checkout byte stability, not a complete simulator build/export.

The existing world-recording tool also needed its duplicate inherited `FlightLog` declaration removed. The repeat-bake gate now checks material-mask frames, and generated recipe-input names are independent of the output folder. The rejection regression verifies changed/missing mask frames fail the gate.

## Remaining gates

Source identity is repaired. Mesh/card lighting still differs, and cards retain their close/overhead depth limitations and different pivot/wind behavior. This change preserves existing collision coverage; it does not qualify every mesh/card/wind combination across all presets. Richer woodland margins, additional tree forms and camera-aware representation remain separate deliveries. Full CI, packaged-resource checks, independent pilot acceptance and the five alternating whole-flight performance pairs were not run. Unchanged geometry counts do not establish unchanged alpha overdraw or frame cost.
