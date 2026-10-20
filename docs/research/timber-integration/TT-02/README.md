# TT-02 — datum, measurements and discrepancies of the imported r1 model

2026-10-12 · **Status: measurements complete; the owner's silhouette overlay is pending.** Owning plan: [Timber integration](../../../TIMBER-INTEGRATION-PLAN.md). Generated outputs: [mesh-measurements.json](../../../../assets/aircraft/turbo-lumber-evolution/mesh-measurements.json), [geometry.json](../../../../assets/aircraft/turbo-lumber-evolution/geometry.json); guide: [asset README](../../../../assets/aircraft/turbo-lumber-evolution/README.md).

## Method

`research/timber/tt02/measure_mesh.gd` instantiates the scene Godot imports from `app/assets/aircraft/turbo-lumber-evolution/timber.glb` (byte-identical to the r1 export, TT-01 hash) and measures it in the root frame: node tree and pivot rest transforms (parent and root frames, plus the glTF `extras` the importer stores on every pivot), per-surface vertex extremes, mesh extents, wheel and propeller radii about their own axles, and plane slices of the white/red/black skin and the control-surface meshes (wing: planes x = const every 10 mm; tail: x = const; fin: y = const; fuselage: z = const). Every slice records its extents and its fore/aft points (leading and trailing edges). Vertices come from `surface_get_arrays()`; see TT-03 for why `get_faces()` is not used for metrology. The script writes 6-decimal values and runs deterministically in 0.8 s; `--check` fails when the importer or the asset changes.

`build_geometry.py` then combines `r1/metadata.json` (by manifest hash), the measurements and the hand-edited manufacturer anchors `manual.json` into `geometry.json` with `{value, unit, kind, source}` on every headline quantity; `compile_geometry.py` emits the Godot constant.

```bash
"$(app/get-godot.sh)" --headless --path app --script "$PWD/research/timber/tt02/measure_mesh.gd" -- --out="$PWD/assets/aircraft/turbo-lumber-evolution/mesh-measurements.json"
python3 assets/aircraft/turbo-lumber-evolution/build_geometry.py
# wrote geometry.json (revision r1-fb7586f19029, span 1.5479 m, chord 0.2135 m, area 0.3282 m2, tail 0.0761 m2, fin 0.0250 m2)
```

## Results

| Measurement | Imported scene | Author (metadata.json) / manual | Verdict |
| --- | --- | --- | --- |
| Pivots (13) and thrust frame: root-frame origin and axis | agree within 1e-6 m / 1e-6 | author | consistent |
| Landmarks (wingtips by x, spinner tip, rudder TE, wheel centres, hub) | ≤ 0.003 mm from the author's values | author | consistent |
| Forward extent | z = −0.283461 m, spinner tip of `propeller_rotor` (surface 0, black) | author −0.283461; TT-00-R1 probe −0.291326 | the probe's −0.2913 m was the axis-aligned bounding box of the 2°/2° tilted rotor (`get_aabb()` corners), not a vertex; **no vertex reaches it** |
| Span | 1.5479 m (lenses), 1.5455 m (skin) | manual 1.555 m | −7.1 mm (−0.46 %) |
| Length, spinner tip to rudder TE | 1.1166 m | manual 1.040 m | +76.6 mm, unresolved (nose/cowl per the author); kept as delivered (D4) |
| Wing planform | rectangular, chord 0.2135 m constant from x = 0.06 to 0.69 m, rounded tips 0.70–0.77 m, LE at z = −0.0007 m, hinge z 0.1577 m (73.9 % chord), control chord aft of hinge 55.1 mm | CAD area 0.329 m², MAC 0.213 m | area 0.3282 m² (−0.24 %), MAC = chord |
| Dihedral / incidence | LE y slope 1.97°; LE-nose-to-TE line 2.44° (2.00° at the last panel station) | author 2° / 2° | consistent; the apparent incidence includes the nose radius above the chord line |
| Horizontal tail | span 0.596 m, chord 0.148 (centreline fit) / 0.108 m (tip), LE sweep 5.0°, TE sweep −2.7°, hinge z 0.704 | CAD Sh 0.0756 m², Lt 0.612 m | area 0.0761 m², arm 0.607 m |
| Fin/rudder | LE sweep 32.5°, root y 0.03, top 0.178, rudder chord aft of hinge 95.1 mm, rudder y −0.070…0.178 | — | area above the fuselage 0.0250 m², rudder 0.0236 m² |
| Fuselage | 46 skin slices every 20 mm from z −0.22 to 0.74 m (half-width, bottom, top) | — | for TT-07 |
| Thrust axis | 2.000° down, 2.000° right, hub (0, 0, −0.2515) | author 2°/2° estimated | consistent |
| Propeller | blade-tip radius 0.1403 m (diameter 11.05 in) | author 0.1381 m estimated; manual 11 in | +2.2 mm vs author, +0.6 mm vs manual |
| Wheels | radii 0.0580 / 0.0140 m, track 0.2640 m, contacts y −0.256 / −0.126, three-point attitude 9.82° | author 0.058 / 0.014, 0.264, 9.8° | consistent |
| Throws, manual mm → deg at the assumed stations | aileron 34.5° (33 mm, r 55.7 mm), elevator 17.8° at the root (23.0° at the tip), rudder 18.2°, flaps 20.7° / 36.6° | authored ranges ±22°, ±22°, ±30°, 0–40° | the aileron angle exceeds the authored range; elevator/rudder are below it; the manual's measurement station is an assumption (`manual.json`) |

Three facts of the plan's Revision 4 change: the forward-extent discrepancy is a probe artefact; glTF `extras` **do** arrive as a node `extras` Dictionary in the default 4.7.2 import (verify_timber.gd cross-checks them against the constants); the aileron pivots carry the dihedral in their rest basis (±2°), not ±1°.

## Silhouette overlay (owner)

The manual is not in the repository, so the overlay of the r1 previews (`assets/source-deliveries/turbo-timber-evolution-original/turbo_timber_evolution/r1/previews/side_right.png`, `top.png`) or the TT-03 captures (`inspection_side_left.png`, `inspection_top.png`, orthographic, 1.2 spans tall) on the manual three-view remains the owner's review. The metrology above is the second check, as the plan orders.

## Limits

Planform edges come from plane slices of a tessellated mesh (0.3 mm tolerance in the author's retessellation); chords are good to ~1 mm. Thickness is an upper bound (vertical extent of the tilted section). The throw conversion depends on the assumed station; the geometry reports the angle range over the span so TT-07 can carry it as a sensitivity. Nothing here validates the aircraft: the geometry is the author's estimate of the real airframe.
