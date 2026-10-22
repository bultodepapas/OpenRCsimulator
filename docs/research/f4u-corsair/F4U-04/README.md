# F4U-04: delivery preflight and the g1.2 and g1.3 reviews

Reviewed 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Dated evidence: what the author delivered, what the tools found and what went back to the author in [request revision 3](../../../F4U-BLENDER-HANDOFF.md#0-review-of-g12-and-what-g13-changes). Software preflight, not acceptance.

## Delivery

`f4u_corsair/g1_2/` ("tapas superiores"), received from the owner on 2026-10-22 outside the repository, 81 MB, read-only. g1.2 adds six upper wing-fold covers to g1.1 (door bevels, tail-door relief, paint finish) and g1. Blender 5.2.2 LTS `d13f752e3b9c`, derived from R59 SHA-256 `94edd59b…4dc3`. `aircraft.glb` SHA-256 `2ae83262d2b81bf2d8ad2b4538a3d42b7882d6e72f68d3cddb778e48733a0302`.

It is not taken into `assets/source-deliveries/`: the accepted revision will be, once (F4U-03), so the repository does not carry two 81 MB copies.

## Results

| Check | Result |
| --- | --- |
| Manifest | 79 of 79 SHA-256 values match; only the manifest itself is unlisted |
| Author's verifier (`verification.json`) | Passes: identity root, unit scales, names, sections, required nodes, one rigid `GearRetract` action reproducing 101 reference samples, budgets, span 2.499993 m, GLB hash |
| [preflight_glb.py](../../../../research/f4u-corsair/F4U-04/preflight_glb.py), revision 2 rules | Passes: 90,861 triangles, 44 mesh nodes, 54 surfaces, 11 materials, one 2048² image, all ten sections, every pivot pair, gear helper and paint material |
| Godot 4.7.2 import (disposable scratch project) | 81 uniquely named nodes, every required pivot and helper, `openrc_section` extras on all 44 meshes, no animation player |
| Gear pose | **Down**: the lowest vertex is `gear_wheel_left` at −0.478 m (GLB up), 0.267 m below the lowest wing vertex. Revision 2 asked for frame 100 (stowed); the importer binds carriers only at the stowed sample |
| Scale | 1:5, as requested by revision 2; the owner moved the model to 1:4.5 the same day |
| Previews | Clean F4U-1D silhouette, coherent gull wing, closed sections, three original liveries (midnight default, three-tone, scarlet 308) |

Neither the author's verifier nor this preflight checked the exported gear pose. The preflight now does: no gear vertex may lie more than 10 mm below the lowest airframe vertex, propeller excluded (the default in the strict profile, `--gear-stowed` in the generic one). On the repository's assets it passes the Avanti (exported stowed) and rejects the fixed-gear Timber. The mutation suite gained the Timber and Avanti cases and an Avanti main gear moved 0.1 m down: 12 of 12 pass. The span rule follows revision 3 (12.5 m / 4.5 = 2.778 m).

Under revision 3 the preflight rejects g1.2 for exactly the two requested changes: `gear reaches 0.267 m below the lowest airframe vertex` and `span 2.5000 m differs from 2.7778 m`.

## g1.3: accepted, 2026-10-22

`f4u_corsair/g1_3/`, the author's answer to revision 3: g1.2 scaled 10/9 (data and location keys, node scales one) and exported at `GearRetract` frame 100 with `export_current_frame=True`. 84 MB, 90 files. `aircraft.glb` SHA-256 `c69151b3c96c53ff957d046c53600204598be854c10850e4bdda22ab333f464e`.

| Check | Result |
| --- | --- |
| Manifest | 89 of 89 SHA-256 values match, before and after the intake copy |
| Author's verifier | Passes, including GLB node transforms rebuilt against the source at frame 100 and a vertex-derived span |
| Author's scale witness | 80 nodes × 101 samples against g1.2 × 10/9: 0.24 µm position, zero rotation difference; topology, UV and material fingerprints unchanged |
| preflight_glb.py, revision 3 rules | Passes: span 2.7778 m, length 2.3811 m; lowest gear vertex 2.6 mm below the wing knee (stowed) |
| Independent geometry comparison | All 25 non-gear meshes equal g1.2 × 10/9 within 0.0001 mm; all 19 gear meshes moved, symmetric left and right. `cockpit_interior` exports two more vertices than in g1.2 with the same 2,722 triangles (exporter normal split), matched by nearest vertex |
| Pose against the delivered source | Blender 5.2.2 on a copy of `aircraft_game.blend`: every GLB node equals `GearRetract` frame 100 within 6 × 10⁻⁷; frame 0 differs by up to 1.4 |
| Godot 4.7.2 import (scratch project) | 81 uniquely named nodes, every pivot and helper, extras on all 44 meshes, no animation player, no import errors; lowest vertex now the propeller |
| Previews | Runtime renders with the gear up and doors closed; three liveries byte-identical to g1.2 |

g1.3 is taken in by F4U-03: `assets/source-deliveries/f4u-corsair-g1-3/` holds the delivery unchanged, and [manifest.py](../../../../research/f4u-corsair/F4U-03/manifest.py) freezes it in [source-manifest.json](../../../../assets/aircraft/f4u-corsair-250/source-manifest.json) (visual revision `g1.3-c69151b3c96c`), proving the copy equals the author's manifest.

## Limits

The scratch Godot imports check structure and extras, not runtime binding, pose sampling or crash separation; those belong to F4U-05/08/11. Licence terms are not set in either delivery (F4U-13).
