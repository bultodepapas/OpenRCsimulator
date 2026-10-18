# Native gallery run record

The copied `source_gallery.json` files are the machine-readable result records. The original Python runners call Godot with `capture_output=True` and print stdout/stderr to the invoking console; no standalone raw Godot stdout log file was present in the temporary evidence tree. The exact runner scripts and fixture are retained under `fixture/`.

| Run | Input | Mutation | Result evidence |
|---|---|---|---|
| Roughness-0.5 baseline | Earlier GLTF SHA `65e324ba29547ffb92121ee653762d1f2e0c4385bbf438b63597cfb5f780b14d` | None; Godot default specular | `evidence/captures/rough05-default/source_gallery.json` (`complete: true`) and two captures |
| Roughness 1 / specular 0.5 diagnostic | Same earlier GLTF | Temporary imported-material mutation | `evidence/material/rough1-spec05-diagnostic-source_gallery.json` (`complete: true`); capture hashes equal final images |
| Roughness 1 / specular 0 diagnostic | Same earlier GLTF | Temporary imported-material mutation | `evidence/captures/rough1-spec0/source_gallery.json` (`complete: true`) and two captures |
| Final production material | Final GLTF SHA `03f2c728f1b21f52d3278ee7abf81b91cf135d4cc4e4bc819e1b5a26b41491d7` | None | `evidence/captures/final/source_gallery.json` (`complete: true`), roughness 1, imported specular 0.5, BLEND |
| KHR specular import probe | Temporary test GLTF SHA `5493a71700e8cc67e00dd10149ddd2db4181e7cbdd651fe41736ec1e5242c57e` | Metadata only | `evidence/khronos-specular-test/source_gallery.json` (`complete: true`), imported specular remains 0.5 |

All viewport runs used `--rendering-method gl_compatibility`, `--audio-driver Dummy`, 1280×1280 capture, a 14 m orthographic frame, and 4× MSAA. The final production view was captured at original source scale with no source material mutation.
