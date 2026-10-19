# Club maple — L6c

Implemented 2026-10-18 beside the white club building near the pilot. This is LOLIPOP's downloaded `Acer_large_3_LOD1`, not generated geometry. [Source comparison](source-options.md) records the alternatives.

## Source and placement

[LOLIPOP's Maple Trees Pack](https://sketchfab.com/3d-models/maple-trees-pack-lowpoly-game-ready-lods-b5d2833c258f4054a01ee2b4ef85adf0), CC BY 4.0. The user supplied `maple-trees-pack-lowpoly-game-ready-lods.zip` (150,673,952 bytes), SHA-256 `338c3373fa656cfa83b4c3c847ad4996f7236b0236204bdabbe068240e10af9a`. Downloads were left intact. Selected source files are retained; runtime exports include `LICENSE_MAPLE.txt`.

The maple replaces the previous oak at N −32 m, E 10.5 m, heading 247.1° (`prop:shade-trees:06`, seed 793949324). The white pavilion is at N −22 m, E 0 m. Its 14 m uniform height gives a 9.63 × 13.24 m crown footprint. Native views show ground contact, clearance from the club roof, and branches above nearby cars. Other placements and seeds are unchanged.

The [manifest](../../../../../assets/landscape/vegetation/derived/lolipop_maple_2026/conversion_manifest.json) binds original inputs and eight derived outputs. Measured source: 18.3271 m tall, 4,729 vertices, 5,541 triangles, two surfaces (2,614 bark / 2,927 leaves). Supplied LOD1 uses 57% fewer triangles than the listed 12,987-triangle LOD0. No topology was created or decimated. The converter removes gallery placement and bakes the FBX axis conversion while preserving the stem origin, UVs and normals.

## Materials and runtime

Two authored PBR materials retain 2K color, normal, AO and roughness maps. Bark is opaque/back-face culled; foliage is double-sided alpha-scissor at 0.5. Leaf opacity is combined into albedo alpha. AO/roughness occupy ORM red/green; native Godot uses StandardMaterial3D with these textures assigned to their separate channels. Source 16-bit bark AO/roughness are normalized to 8-bit without clipping. Utility vertex colors are not treated as RGB; the maple instance uses white tint.

Six runtime maps explicitly use VRAM compression and full mip chains; both normals use normal-map import mode. Native captures confirmed less grain than the initial unmipped import. Godot generates additional mesh LODs. Mipmaps do not eliminate all thin-leaf shimmer. See Godot's [image import](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html) and [3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) guidance.

The maple remains static because the current wind adapter cannot preserve its PBR combination; its diagnostic warning is expected. Collision dimensions share the render scale and include the canopy's offset from the centered stem. The scenery collision identity consequently changes. Woodland receipts were regenerated without moving their plants.

## Native evidence

Godot 4.7.2, Compatibility/OpenGL 3.3, NVIDIA RTX 3090, 1280 × 720.

| View | Previous oak | Maple |
|---|---|---|
| Club overview | [Baseline](baseline-postcard_club.png) | [Candidate](candidate/postcard_club.png) |
| Pavilion / pilot line | [Baseline](baseline-postcard_pavilion.png) | [Candidate](candidate/postcard_pavilion.png) |
| Pilot south | [Baseline](baseline-pilot_south.png) | [Candidate](candidate/pilot_south.png) |
| Detail | — | [Close](candidate/maple_close.png), [front](candidate/maple_front.png), [side](candidate/maple_side.png) |

[Native counters](candidate/views.json), [engine log](candidate/capture.log). Capture exited 0 without script errors. The crown retains its authored irregular openings and dark green leaves; this is a game asset in the existing lighting, not a claim of photorealism.

Full scenery: **648,688 / 650,000 triangles**, versus 648,435 before (+238 tree, +15 round contact shadow). The cap is unchanged. Club overview: 165 draw calls. These counters do not measure alpha overdraw or isolate the maple's GPU cost.

The warm side-view sample measured 9.072 ms median / 19.421 ms p95 over 180 frames with VSync disabled. It includes CPU, rendering and presentation waits. There is no matched frame-time baseline, so it does not establish an FPS improvement or performance on other GPUs.

The cold scene-build gate remains **failing**: [before](baseline-test_scenery_build.gd.log) 1175.998 ms; [after](final-test_scenery_build.gd.log) 1097.608 ms, against 800 ms. Warm candidate builds were 345.7 / 320.9 ms. The gate was not weakened; all other assertions in that test pass. [Full-scene geometry](test_landscape_vegetation.gd.log): 36 checks, no failures.

Focused import, native/headless material, vegetation, collision, loader, habitat and destruction tests pass. Python library/woodland suites pass (7 + 6 tests). Independent conversion reproduced all eight output hashes and the manifest byte-for-byte. Full aircraft/physics validation and export packaging were not rerun for this asset change.

## Reproduce

From the repository root, with Blender 5.2.2 LTS and Python dependencies Pillow 12.3.0 / NumPy 2.4.6:

```powershell
python -m pip install Pillow==12.3.0 numpy==2.4.6
python tools/landscape/vegetation/convert_maple.py --blender 'C:/Program Files/Blender Foundation/Blender 5.2/blender.exe'
python tools/landscape/vegetation/convert_maple.py --check
python tools/landscape/vegetation/build_library.py --check
python tools/trees/place_woodland_edges.py --check
& ./.tools/Godot_v4.7.2-stable_win64.exe --headless --path app --editor --import
& ./.tools/Godot_v4.7.2-stable_win64.exe --path app --rendering-driver opengl3 --resolution 1280x720 --script "$PWD/docs/research/visual-quality-implementation/L6c/house-tree/capture_club.gd" -- "--out=$PWD/tmp/club-maple-capture"
```

The fixture uses production world construction and fixed shader time. Its optional Blender EEVEE preview failed with texture/GPU errors and is not acceptance evidence.

The earlier [Jacaranda inspection](jacaranda-inspection.json) and [script](inspect_jacaranda.py) retain rejection evidence: 3,863,832 triangles in full LOD0 and 1,845,603 in LOD1. Its [1K Blend source](https://dl.polyhaven.org/file/ph-assets/Models/blend/1k/jacaranda_tree/jacaranda_tree_1k.blend) was 180,228,496 bytes, MD5 `1b827c7c364c6ebb2cbbff0f02b52a15`.