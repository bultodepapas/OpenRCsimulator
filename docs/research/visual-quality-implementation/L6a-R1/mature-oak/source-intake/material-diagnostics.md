# Native material diagnostics

## Setup and limits

The retained fixture is a temporary Godot 4.7.2-stable project using the Compatibility renderer (OpenGL 3.3) on an RTX 3090. Captures are 1280×1280, 4× MSAA, orthographic at a 14 m frame, and preserve source scale. The neutral dark background helps inspect the atlas silhouette and bright alpha-card patches. It does not test course lighting, ground contact, shadows, transparent-depth sorting in the full scene, wind, or forest density.

The source GLTF used for the baseline/diagnostic material comparisons had roughness 0.5 and no explicit specular extension; Godot imported its default `metallic_specular` value of 0.5. Both controlled diagnostic runs kept BLEND alpha and changed the temporary imported material to roughness 1.0, once requesting specular 0.5 and once requesting 0.0. Both back and underside images no longer show the conspicuous bright leaf-card patches. The diagnostic manifests mark the material as temporarily mutated. They do not serialize the specular override value, so the retained Python runner and its `--specular=0.5` / `--specular=0.0` arguments are the record of those settings.

The final production GLTF now carries roughness factor 1.0, metallic 0, double-sided, and BLEND. The final unmutated Godot import reports roughness 1.0 and `metallic_specular` 0.5. Its back and underside image hashes exactly match the controlled roughness-1/specular-0.5 diagnostic images. Therefore the adopted output uses the supported Godot default specular path; the specular-0 view is diagnostic only and is not the production material.

The source `.blend` has legacy specular intensity 0.0 and no authored roughness map. The scalar roughness-1 export is a reviewed material adaptation, not a texture-derived value. A separate glTF carrying `KHR_materials_specular.specularFactor: 0` was tested; the retained Godot metadata manifest still reports `metallic_specular: 0.5`. The extension test manifest is included, while its temporary GLTF is referenced by its SHA-256 (`5493a71700e8cc67e00dd10149ddd2db4181e7cbdd651fe41736ec1e5242c57e`) and not duplicated here.

## Evidence map

- `evidence/captures/rough05-default/`: original imported roughness-0.5/default-specular back and underside comparison plus the full native manifest.
- `evidence/material/rough1-spec05-diagnostic-source_gallery.json`: temporary roughness-1/specular-0.5 diagnostic manifest. Its two capture hashes match `evidence/captures/final/` exactly, so the final captures are the retained pixels for both records.
- `evidence/captures/rough1-spec0/`: temporary roughness-1/specular-0 diagnostic back and underside views with its manifest.
- `evidence/captures/final/`: actual unmodified import of the final GLTF, back/underside views, and manifest.
- `evidence/khronos-specular-test/source_gallery.json`: metadata-only Godot import check for the temporary `KHR_materials_specular` test.
- `fixture/scripts/oak_source_gallery_matdiag.gd` and `fixture/runners/run_oak_gallery_matdiag.py` contain the diagnostic implementation and requested parameter values; `fixture/scripts/oak_source_gallery_materialinspect.gd` and `fixture/runners/run_oak_gallery_final.py` reproduce the final unmutated import capture.
