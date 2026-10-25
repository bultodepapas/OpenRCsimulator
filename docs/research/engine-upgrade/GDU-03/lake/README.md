# GDU-03 lake bake regeneration

2026-10-25. The existing packaged field check and `test_lake_geometry_bake.gd` correctly rejected a stale bake. The retained source hashes predated the October 24 `math3d.gd` changes, and the resource also recorded Godot 4.7.2. Regeneration used only the owning `tools/ground/bake_lake_geometry.gd` pipeline. No bake metadata, geometry, physics goldens or compatibility guards were hand-edited.

[Initial migration comparison](engine-migration-metadata.json) shows that only `engine_hex` and `sources` changed. [Final core comparison](final-core-metadata.json), after the owning core update, shows only `sources` changed. Both compare every complete serialized metadata payload using `var_to_bytes`: basin/water arrays, input keys, geometry digests, format and precision remain byte-exact. The owner hashes source text with CRLF normalized to LF; those metadata hashes differ from the raw file hashes in the [export source receipt](../exports/source-receipt.json).

| Unchanged geometry | SHA256 |
| --- | --- |
| Basin arrays | `5861457b0ccf5f88f425f7882ae5e018c1b4da940b85e33c427c8e912aaf5def` |
| Water arrays | `666a839db4292064c4bbc1042854f4f67f6adc1ccd65a531f0577d3d13587b55` |

The final generated pair is recorded in [generated outputs](generated-outputs.json):

- `app/assets/landscape/lake/default_geometry.res`: `4edcba6fc11f09c521af64b6e0fc5d0b8e56645d91da1bf0b3cfdf8fae994052`.
- `app/render/lake/generated_geometry_stamp.gd`: `0402278a05708d2b934d8a3c2ffc8d727bd7b8642283ca658241b815588de276`.

Root, frozen suite and export fixture received the final owner-generated pair. The [owner `--check`](owner-check.log) passes exact procedural buffer/source checks; the [existing lake test](existing-lake-test.log) passes all 18 checks, including stale/missing/corrupt metadata rejection and fresh procedural geometry equality. Final all-platform field-pack checks also pass with this pair. Native builder lake parity evidence remains in [native qualification](../native/README.md); no native numerical implementation changed for this regeneration.

The small retained [metadata comparator](compare_metadata.gd) is an evidence diagnostic, outside the production app. Original before/candidate resources and full invocations remain under `D:/OpenRCsimulator-experiments/gdu03-packages/tmp/exports/lake` and `lake-final`; the production owner command remains the authoritative regeneration path. This is software equivalence evidence, not physical validation.
