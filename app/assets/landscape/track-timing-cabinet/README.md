# Track timing cabinet

Original Poly Haven [Utility Box 01](https://polyhaven.com/a/utility_box_01) by James Ray Cock. Poly Haven distributes its assets under [CC0](https://polyhaven.com/license); see [`LICENSE.txt`](LICENSE.txt) and [`PROVENANCE.json`](PROVENANCE.json).

Load `utility_box_01_1k.gltf` with its adjacent `utility_box_01.bin` and `textures/` files. This is the untouched official glTF 2.0 asset; Godot can import glTF directly. It contains one 4,404-triangle mesh, one PBR material, and three 1024×1024 maps. Its local bounds are 0.520 × 1.120 × 0.432 m (+Y up, bottom at Y=0). A scene scale of 0.6 yields approximately 0.312 × 0.672 × 0.259 m for one timing-control cabinet instance.

The weathered blue-gray steel, rivets, ventilation, latch, and high-voltage labels make it a plausible outdoor electrical/timing cabinet. The upstream material binds the diffuse, OpenGL normal, and packed ARM maps; its red AO channel is present in ARM but is not separately bound as an occlusion texture by the source glTF.
