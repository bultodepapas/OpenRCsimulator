# Oak source intake evidence

This folder retains compact evidence for the free OpenGameArt Oak source and its native Godot check. The original ZIP, BLEND, converted glTF/BIN/atlas, license notice, and converter remain in their canonical locations under `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/` and `tools/landscape/vegetation/convert_oak.py`; they are referenced here rather than duplicated.

- [OpenGameArt listing and intake audit](oga-listing-audit.md) records the source page, selected license, original-download pins, published LOD facts, conversion, and final material mapping.
- [Material diagnostic record](material-diagnostics.md) explains the roughness/specular comparison and capture limits.
- `evidence/conversion/` contains the canonical conversion proof and a fresh repeat-export proof from the exact current converter.
- `evidence/captures/` contains the final production import views, roughness-0.5 baseline views, and the roughness-1/specular-0 diagnostic views. The roughness-1/specular-0.5 diagnostic screenshots have the same SHA-256 values as the final production views, so those pixels are retained once; its manifest is retained separately.
- `evidence/validation/khronos-final-report.json` is the final Khronos glTF Validator report.
- `evidence/khronos-specular-test/` retains the Godot metadata result for a temporary glTF extension test. The test glTF itself is not copied.
- `fixture/` retains the temporary Godot project scripts and Python command runners used for the captures. The fixture loads the canonical source path from this repository and is not self-contained without it.
- [Native run record](native-run-record.md) notes the exact capture configuration and the available machine-readable run results.

All viewport captures use a neutral dark background. They isolate silhouette and alpha-card/specular artifacts; they do not qualify course lighting, ground contact, shadowing, foliage depth sorting, wind, forest overlap, or performance.
