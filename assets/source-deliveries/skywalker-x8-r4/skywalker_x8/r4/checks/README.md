# checks/ — evidence for revision r4

Every file here was produced on this revision by `source/scripts/release.py` (or, for
`full_rebuild.json`, by an independent run of it in an empty folder). Tool versions and input
hashes for the run are in `../verification.json → tool_identity, input_identity`.

| File | Produced by | What it shows |
| --- | --- | --- |
| `structural_abisal.json`, `structural_bolido.json` | `verify_game.py <blend> --glb <glb> [--livery bolido --parity-ref export/aircraft.glb] --metadata metadata.json --json …` | All verifier checks per skin GLB (hierarchy, tags, transforms, motion and clearance, mesh quality, materials, textures, GLB contract, re-import, skin parity, metadata) |
| `parity_bolido.json` | `skin_parity.py export/aircraft.glb export/bolido.glb --json …` | Per mesh: triangle counts and maximum differences of positions, normals, UV0 and tangents; node table; texture bindings and UV channels |
| `motion_revision.json` | `check_rig_revision.py <r3 blend> <r4 blend> --json …` | 201 sampled poses (elevons every degree and ±40, doors every 5°, propeller every 10°) compared vertex by vertex against the r3 baseline |
| `deviation.json` | `check_deviation.py <master> <blend> export-map.json --json …` | Game vs master distances per mesh, both directions: max, p95, p99, mean, location of the maximum; provisional thresholds |
| `silhouettes/` | `compare_silhouettes.py <master> <blend> checks/silhouettes --json …` | Front/side/top overlays (red = master only, blue = game only) and IoU |
| `finish.json` | `check_finish.py <blend> textures --json …` | Per skin and painted mesh: luminance, roughness, metallic, occlusion, normal-map tilt, emissive faces |
| `views/` | `check_views.py <blend> checks/views` | Closest provisional views at 1920×1080 and 2560×1440 for every skin, same lights; `views.json` records camera distance, FOV, pose, renderer, hardware and pixel/texel sizes |
| `layers.json` | `paint_layers.py compose textures/<skin>/source <skin>` | Recomposition of each skin's base colour from its editable layers |
| `negative_tests.json` | `test_verifier_rejects.py <blend> --json …` | Disposable-copy rejection cases and the verifier's exit codes |
| `clean_package.json` | `check_clean_package.py <package> --json …` | Clean copy: factory-settings open, missing-file scan, all-skin export hashes, clean re-import of each GLB |
| `full_rebuild.json` | `release.py --skip-views` in an empty folder | Byte comparison of 51 delivered files (GLBs, textures, sources, layers, masks) with an independent rebuild |
