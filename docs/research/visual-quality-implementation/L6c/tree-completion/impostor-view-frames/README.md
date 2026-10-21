# Four-view impostor frame order

2026-10-21 · L7-R1 woodland margins and hedge impostors · render-only, no placement or collision change.

From north and south, the woodland-edge cards and hedge cards showed the frame baked from the opposite side. Orbiting a card stepped through frames 0, 3, 2, 1. The shaders selected frames by `+atan(z, x)`. The bake places the Blender camera at azimuth *a* for frame *a*/90°, and Blender's glTF importer maps glTF −Z to Blender +Y. That direction therefore reaches Godot as the source-local vector (cos *a*, 0, −sin *a*), where `atan(z, x) = −a`. Both [`woodland_cards.gdshader`](../../../../../../app/scenery/woodland_cards.gdshader) and [`bush_common_4view.gdshader`](../../../../../../app/assets/landscape/vegetation/impostors/bush_common_4view.gdshader) now negate the angle. East and west views were already correct.

## Proof

The convention was checked against the source models, not only against the importer documentation. [`source_views.gd`](fixtures/source_views.gd) renders each source orthographically from (cos *a*, 0, −sin *a*). [`compare_frames.py`](fixtures/compare_frames.py) compares bounding-box-normalized alpha silhouettes with every atlas frame. Views from opposite sides are mirror silhouettes, so only the correctly ordered frame matches. [Raw IoU](silhouette-iou.json):

| Atlas | Correct frame at 90° / 270° | Frame the old shader showed |
| --- | --- | --- |
| `bush_common` | 0.954 / 0.961 | 0.798 / 0.796 |
| `bush_common_flowers` | 0.972 / 0.972 | 0.757 / 0.757 |
| `fern_1` | 0.923 / 0.920 | 0.623 / 0.624 |
| `grass_common_short` | 0.946 / 0.947 | 0.383 / 0.383 |
| `grass_common_tall` | 0.900 / 0.899 | 0.542 / 0.542 |

At 0° and 180°, every atlas matches its own frame (IoU 0.85–0.97).

`test_woodland_edge_habitat.gd` now renders a synthetic four-colour atlas through both shaders with a real renderer. It requires frames 0–3 from azimuths 0–270° for instance yaws of 0° and 90°. The pre-fix formula shows `[0, 3, 2, 1]` in the same fixture. The Dummy renderer skips this check, so run the test natively:

```sh
xvfb-run -a "$(app/get-godot.sh)" --path app --rendering-driver opengl3 --audio-driver Dummy --script res://tests/test_woodland_edge_habitat.gd
```

Captures used Godot 4.7.2 Compatibility on Mesa llvmpipe. Atlases, placements, budgets and the [woodland-edge recipe](../groundcover-transition/README.md) are unchanged. Only frames 1 and 3 swap, so a nearly symmetric plant looks the same. The visible change is on asymmetric short grass and ferns viewed while looking north or south.
