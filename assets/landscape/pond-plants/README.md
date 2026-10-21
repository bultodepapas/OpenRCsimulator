# Pond plant source and conversion · LU-22-R2

All source geometry is downloaded CC0, retained without topology remodeling.

| Role | Author / source | Retained source SHA-256 | Runtime derivative SHA-256 |
| --- | --- | --- | --- |
| Notched Nymphaea leaf | [Starry Skydancer, Lily Pads](https://opengameart.org/content/lily-pads), CC0, `water_lilly.blend` | `dbc9c3ef1807a16f15fe3a4e002c9ff33a26a42e15de2bfeca53da62ae7f97ab` | `nymphaea_leaf.glb`: `4ba50be1ffe978a2f8dade820517bb2c16a7617d9a2a156ec10ce5f33321ba00` |
| Small waterlily blossom | [Aredon, LowPoly Waterlily](https://opengameart.org/content/lowpoly-waterlily), CC0, `waterlily.zip` | `375a3d54f74da67643f50a6b011f8efe05f88c4db5f2a861b4fd4224a68228c8` | `white_waterlily_flower.glb`: `e296033998999d246303360c20be116cea94f35aa6df2177e34ddf1e32c9e186` |

Run `blender -b --python tools/landscape/export_pond_lily.py` with Blender 5.2.2
from the repository root. The exporter selects the supplied `Nymph Original`
leaf, reverses its downward-facing top normals, applies its 20 mm Solidify
modifier, and preserves its radial UVs and leaf silhouette. It selects only
the small white blossom from Aredon's archive, rotates the source OBJ from
Y-up, and centers its existing mesh. Godot uses runtime shader materials and
uniform scale; no source polygons are sculpted. The reed clump is the already
retained Aredon CC0 asset documented in `app/assets/landscape/UPGRADE_CREDITS.md`.

The in-game plant layout and materials are authored estimates for this pond,
not claims of botanical species identification or a surveyed habitat.
