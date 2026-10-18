# Source structure (inspected from the original glTF 2.0)

The scene has three root nodes named `pine_sapling_small_a`, `_b`, and `_c`. Each references its own mesh with two material primitives (bark and twig/foliage), so these are three complete sapling forms, not three parts of one tree. Nodes A/B/C are positioned at X = 0/1/2 m. The combined scene width is about 2.64 m, matching the asset page's reported width.

| Form | Bark triangles | Twig triangles | Local bounds (x,y,z), metres | Height |
|---|---:|---:|---|---:|
| A | 540 | 141,966 | x -0.3603..0.4274; y -0.0155..1.2835; z -0.3714..0.3560 | 1.299 m |
| B | 486 | 121,749 | x -0.2652..0.2635; y 0.0009..1.0465; z -0.3314..0.3990 | 1.046 m |
| C | 528 | 132,875 | x -0.2310..0.2818; y 0.0007..0.9620; z -0.3207..0.2593 | 0.961 m |

Total is 398,144 triangles. Each primitive uses POSITION, TEXCOORD_0, NORMAL only; there is no vertex color or wind channel. Both materials are double-sided. Twig is alpha MASK with cutoff 0.5; bark uses default opaque mode. The bark and twig use `diff`, `nor_gl`, and `arm` JPG maps. In glTF, each `arm` image is bound as metallic-roughness; there is no separate occlusion texture. `KHR_materials_specular` and `KHR_materials_ior` are optional extensions (`extensionsRequired` is empty). No LOD node or LOD extension is present.

At 121,749–141,966 triangles per form, this source is far heavier than the project's 3.5–6.3k-triangle imported near-tree band. It is retained for an offline source/bake/material/silhouette comparison only. No Godot import, render, conversion, bake, benchmark, or runtime approval is implied.
