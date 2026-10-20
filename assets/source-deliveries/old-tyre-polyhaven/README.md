# Poly Haven Old Tyre source

[Old Tyre](https://polyhaven.com/a/old_tyre) is by MP, published by Poly Haven under [CC0 1.0](https://polyhaven.com/license). The source files were downloaded from Poly Haven's official API on 2026-10-20. [`source-manifest.json`](source-manifest.json) records the exact URLs, supplier MD5 checksums, downloaded SHA-256 checksums, and the runtime export hash.

The supplied low-poly glTF mesh has **2,880 triangles**, one UV set and one PBR material. Its 1K JPG diffuse, OpenGL normal and ARM maps are embedded byte-for-byte in the [runtime GLB](../../../app/assets/landscape/track-tyre/old-tyre-1k.glb). No geometry or material was remodelled or decimated. Rebuild with [`export_track_tyre.py`](../../../tools/landscape/export_track_tyre.py) in Blender 5.2.2 LTS.

The supplier tyre is **0.600 m in diameter and 0.165 m thick**. It arrives upright in Godot's Y-up frame: X/Y span the tyre face, and Z is its axle. The GLB node transform is identity; mesh-local AABB is `(-0.300000012, -0.300000012, -0.082763322)` to `(0.300000012, 0.300000012, 0.082236677)` metres. Rotate it **90° around X** to lie flat, then put the first instance origin **0.082236677 m** above local ground and add **0.165 m** for each layer. A three-tyre stack is about **0.495 m high** before any small compression/overlap. One tyre costs 2,880 triangles, so a three-tyre stack costs 8,640. These are visual props for off-course placement; collision must be authored separately before a stack can border a drivable surface.

`python tools/landscape/export_track_tyre.py --check` verifies the source and runtime hashes, GLB dimensions, identity transform, triangle count, mesh attribute counts and byte-exact embedded maps.
