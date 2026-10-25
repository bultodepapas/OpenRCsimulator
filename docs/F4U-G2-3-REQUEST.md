# F4U Corsair g2.3: request to the model author

2026-10-25 · OpenRC Simulator team · Base specification: [Blender delivery request](F4U-BLENDER-HANDOFF.md) and the [g2.1 request](F4U-G2-1-REQUEST.md). Review behind this request: [F4U-21](research/f4u-corsair/F4U-21/README.md).

## Summary

g2.2 is accepted and flies with all thirteen paint schemes. The simulator now moves the gear, flaps, control surfaces, wing fold, canopy and tailhook. The canopy and the hook came straight from R59's rig, because g2.2 already delivers them as separate nodes. The cowl flaps cannot move: g2.2 merges their sixteen sectors into `cowl`.

Deliver **g2.3: g2.2 plus the changes below, for all thirteen schemes, and nothing else.** C1 and C2 are required. W1 is wanted, but must not delay them.

## Keep unchanged

- Every node except `cowl` (C1) and `core_details` (W1): names, parents, `openrc_section` tags, rest transforms (within 1 × 10⁻⁵) and geometry.
- `GearRetract`: its carriers and 101 poses. Wheel radii, axles and ground contacts.
- Scale 1:4.5, the D0 model frame, every skin facing outward.
- The airframe UVs and the paint of all thirteen schemes.
- Limits per GLB: 300,000–350,000 triangles as target, 450,000 at most, 70 surfaces, 16 materials, 30 MB.

## Required

### C1 Separate the cowl flaps

**Problem.** R59 has sixteen hinged cowl-flap sectors (`R14 | bisagra sector 01…16`), all driven by `cowl_flaps_deg` from 0 to 28°. g2.2 merges their sixteen gates (`R14 | compuerta curva 01…16`) into `cowl` with the lip, so they cannot open.

**Do:**

1. Move each gate out of `cowl` into its own mesh node, `cowl_flap_01` … `cowl_flap_16`, numbered as R59's sectors (table below). Sector 01 is on the right, just above the thrust axis. The numbers run over the top to the left side and back along the bottom.
2. Each node is a direct child of the root `F4UCorsair`, with an identity transform and its vertices in the model frame, like every other g2 node. Tag it `openrc_section: "engine"` and list its R59 objects in `g2_sources`. Do not add pivots or turn the nodes: we take each hinge line from R59 and turn the node in place, as for the wing fold.
3. Keep each gate's geometry, UVs and paint as in g2.2. R59 hardware that shows with a flap open goes in the same node: hinge leaves `hoja bisagra NN ±1`, inner ribs `nervio interior NN ±1`, control arm `brazo de mando NN`. Add at most 300 triangles per sector for it.
4. Paint each flap's inner face as you painted the gear doors' inner skins (g1.9: a dedicated paint UV on inward faces).
5. `cowl` keeps the lip only (`Capot radial | boca abierta y labio redondeado`).
6. In a copy, open all sixteen to 28°. The gap behind a flap must not show the sky, back faces or a hole: the fuselage or firewall must close it; add a dark shroud only if they do not. No flap may touch its neighbours, the exhaust stacks or the fuselage. Export the flaps closed.

| Sector | R59 hinge | Hinge point, model frame (m) | Gate centre, model frame (m) |
| --- | --- | --- | --- |
| 01 | `R14 \| bisagra sector 01` | (0.1613, 0.0356, −0.1582) | (0.1631, 0.0341, −0.1229) |
| 02 | `R14 \| bisagra sector 02` | (0.1367, 0.0961, −0.1582) | (0.1382, 0.0944, −0.1229) |
| 03 | `R14 \| bisagra sector 03` | (0.0914, 0.1424, −0.1582) | (0.0924, 0.1405, −0.1229) |
| 04 | `R14 \| bisagra sector 04` | (0.0321, 0.1675, −0.1582) | (0.0325, 0.1655, −0.1229) |
| 05 | `R14 \| bisagra sector 05` | (−0.0321, 0.1675, −0.1582) | (−0.0325, 0.1655, −0.1229) |
| 06 | `R14 \| bisagra sector 06` | (−0.0914, 0.1424, −0.1582) | (−0.0924, 0.1405, −0.1229) |
| 07 | `R14 \| bisagra sector 07` | (−0.1367, 0.0961, −0.1582) | (−0.1382, 0.0944, −0.1229) |
| 08 | `R14 \| bisagra sector 08` | (−0.1613, 0.0356, −0.1582) | (−0.1631, 0.0341, −0.1229) |
| 09 | `R14 \| bisagra sector 09` | (−0.1613, −0.0299, −0.1582) | (−0.1632, −0.0313, −0.1229) |
| 10 | `R14 \| bisagra sector 10` | (−0.1367, −0.0903, −0.1582) | (−0.1383, −0.0918, −0.1229) |
| 11 | `R14 \| bisagra sector 11` | (−0.0914, −0.1367, −0.1582) | (−0.0924, −0.1381, −0.1229) |
| 12 | `R14 \| bisagra sector 12` | (−0.0321, −0.1617, −0.1582) | (−0.0325, −0.1632, −0.1229) |
| 13 | `R14 \| bisagra sector 13` | (0.0321, −0.1617, −0.1582) | (0.0325, −0.1632, −0.1229) |
| 14 | `R14 \| bisagra sector 14` | (0.0914, −0.1367, −0.1582) | (0.0924, −0.1381, −0.1229) |
| 15 | `R14 \| bisagra sector 15` | (0.1367, −0.0903, −0.1582) | (0.1383, −0.0918, −0.1229) |
| 16 | `R14 \| bisagra sector 16` | (0.1613, −0.0299, −0.1582) | (0.1632, −0.0313, −0.1229) |

Model frame: +X right, +Y up, −Z nose, origin D0; mapped from R59 by [extract_mechanisms.py](../research/f4u-corsair/F4U-21/extract_mechanisms.py) ([data](../assets/aircraft/f4u-corsair-250/mechanisms-r59.json)).

**Check:** each `cowl_flap_NN`'s gate, without hardware, has its bounds centre within 1 mm of the table. Render the nose from the front three-quarter and the side, flaps at 0° and 28°.

### C2 Blade normal map

Still open from [After g2.1](F4U-G2-1-REQUEST.md#after-g21), item 1, in all thirteen schemes. `naval_blade_paint` has no normal map, and its roughness fell from 0.72 to 0.37, so the blades show faceted diagonal streaks at 1.6 m. Add R59's normal map on UV0 at scale 0.65, keep the base colour on UV1, and compare the roughness with g2.0 in a close preview.

## Wanted

### W1 Name the hook

`core_details` holds only the tailhook (`R27 | asta gancho`, `R27 | punta curva gancho`). Rename it `tailhook`. Keep its geometry, stowed.

I1 (shading dents, [g2.1 request](F4U-G2-1-REQUEST.md#i1-shading-dents)) stays wanted and does not block g2.3.

## Before you deliver

Run these from the repository root (`C:\DEVELOPMENT\OpenRCsimulator`) for every scheme's GLB and put the outputs in `checks/`:

```sh
python research/f4u-corsair/F4U-04/preflight_glb.py <g2_3>/export/<scheme>.glb --profile f4u-g2
python research/f4u-corsair/F4U-18/glb_orientation.py <g2_3>/export/<scheme>.glb
```

- The preflight passes with no warnings.
- Every scheme has the same node set, positions, normals and UVs as the default.
- Your verifier, rig and clearance audit, and deviation report pass as they did for g2.2.

## Package

- Folder `f4u_corsair/g2_3/`, with the same layout as g2.2.
- `CHANGELOG.md` gets one entry listing exactly C1, C2 and W1 if done.
- `README.md` figures and `metadata.json` are current, including `nodes` and `liveries`; `SHA256SUMS.txt` covers every file.

## How we accept g2.3

1. The checks above.
2. Our compile maps R59's sixteen hinges onto the new nodes and checks each gate centre against R59 within 1 mm.
3. Integration: freeze, model compile, `verify_f4u.gd`, the liveries suite, the motion audit with the flaps at 0, 14 and 28°, and the canopy, tailhook, retract, flap and fold checks in the production scene.
