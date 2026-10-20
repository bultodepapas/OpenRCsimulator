# LU-30-R1 — Closer transmission corridor and efficient night markers

2026-10-20. Follow-up to [LU-30](../LU-30/README.md). Nine downloaded
30 m lattice towers replace the five-tower distant arrangement. Eight spans
carry six phase conductors and one shield wire each. Source assets and licenses
remain those recorded in LU-30; no replacement tower or cable is modeled.

## Geometry and lighting

The original 5,743-triangle tower and 128-triangle conductor are retained.
The insulator baker uses the pinned Godot 4.7.2 meshoptimizer LOD generator:
1,488 → 372 triangles and 1,192 → 244 vertices per insulator. The derivative
keeps the ribbed silhouette and is refitted to the same 0.30 × 1.10 × 0.30 m
attachment envelope. Its normals are transformed and normalized; source hashes,
LOD candidates, retained shells and dimensions are recorded in the generated
JSON. The runtime does no mesh simplification.

Nine towers, 54 insulators and 56 conductors total **78,943 triangles** versus
76,939 previously: 80% more towers for 2.6% more transmission-line geometry.
The existing 725,000-triangle scenery ceiling is unchanged.

Nine dim steady red top markers and eight weaker wire markers share the
existing regional lighting shader and spatial MultiMesh batches. Wire marker
positions interpolate the downloaded conductor's actual sampled sag profile.
Emission fades in with dusk and is off during daylight. No dynamic lights,
shadow maps or per-tower frame callbacks are added.

Visual references: the [FAA AIM obstruction and catenary lighting section](https://www.faa.gov/Air_traffic/publications/atpubs/aim_html/chap2_section_2.html)
describes red nighttime obstruction lights and illuminated transmission-wire
markers. These inform the game's appearance, not a claim that this arrangement
is required or certified for real installations.

## Reproduce

```powershell
python tools/scenery/place.py --check
python tools/scenery/bake_countryside.py --check
python tools/scenery/bake_power_cable.py --check
python tools/scenery/bake_power_insulator.py --check --godot .tools/Godot_v4.7.2-stable_win64_console.exe
```

Native views use `res://tests/capture_landscape_upgrade.gd` with cases
`power_pilot,power_airfield,power_corridor,power_detail`, 1280×720,
`--botanical_clock=0.25`, and 240 measured frames after warmup.
Headless checked scripts cover imported geometry, source winding, marker
attachment, scenery loading/build budgets, regional lighting and collisions.

Thin distant cables remain subpixel at 720p. The optimized insulator is still a
visual adaptation of the downloaded pin form. Conductors remain visual-only;
tower collision envelopes are unchanged.
