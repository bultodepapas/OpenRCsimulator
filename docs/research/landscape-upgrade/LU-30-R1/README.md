# LU-30-R1 — Closer transmission corridor and efficient night markers

2026-10-20. Follow-up to [LU-30](../LU-30/README.md). Nine downloaded
30 m lattice towers replace the five-tower distant arrangement. Eight spans
carry six phase conductors and one shield wire each. Source assets and licenses
remain those recorded in LU-30; no replacement tower or cable is modeled.

The final corridor is at N=50 m, with E=650…1,610 m in 120 m increments.
All nine headings are 90°. The closest tower is 652 m from the field origin
(previously 1,250 m), and its center is 601 m from the runway edge. The line
extends into the distance rather than bringing every tower next to the runway.
The northeast candidate was rejected after native pilot views showed treeline
occlusion. The accepted east corridor has a clear skyline from the pilot.
The generator retains the loader's approach and flight-box rules; the group
uses the countryside zone instead of weakening the horizon zone's 1 km limit.
The highway crosses under the span between E=890 and E=1,010 m, with both
footings outside its road footprint.

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
`power_pilot,power_airfield,power_runway_east,power_corridor,power_detail`, 1280×720,
`--botanical_clock=0.25`, and 240 measured frames after warmup.
Headless checked scripts cover imported geometry, source winding, marker
attachment, scenery loading/build budgets, regional lighting and collisions.

Thin distant cables remain subpixel at 720p. The optimized insulator is still a
visual adaptation of the downloaded pin form. Conductors remain visual-only;
tower collision envelopes are unchanged.

## Verification and measurements

The final checked runs pass imported geometry/marker attachment, the complete
scenery loader, structural and landscape collisions, and native regional
lighting (287 checks). There are 174 regional optical instances in 40 batches,
including the 17 new markers. Source regeneration and both focused Python
scenery suites pass. The complete scenery has **717,027 triangles in 60 cells**;
the same two baseline daylight views retain their 162 and 294 draw calls.

The scenery-build test initially exceeded its 800 ms cold-build ceiling
(1,265 ms). An immediate unchanged repeat passed at 768 ms, including all
geometry, determinism, winding, tiers and theme checks. Both logs are retained.
The ceiling was not raised; this cold-load measurement remains sensitive to
shared machine load. The existing unsupported maple wind-material warning
also remains.

Native captures: Godot 4.7.2, RTX 3090, Compatibility/OpenGL, 1280×720,
4× MSAA, 240 frame intervals per case after warmup:

| View | Day p95 | Dusk p95 | Night p95 |
| --- | --- | --- | --- |
| Pilot looking east | 1.534 ms | 2.037 ms | 2.600 ms |
| Complete corridor | 1.293 ms | 1.056 ms | 1.103 ms |
| Insulator/cable detail | 1.145 ms | 1.031 ms | 0.926 ms |

These are unpaired samples under shared desktop load and concurrent workspace
activity, not isolated GPU costs or a speedup claim. Lower-end hardware is
unmeasured. Distant wires remain thin; lights are deliberately small, with no
large decorative halos.

Evidence: [pilot daylight](noon/power_runway_east.png),
[complete corridor](noon/power_corridor.png),
[downloaded details](noon/power_detail.png),
[dusk](dusk/power_corridor.png), [night](night/power_corridor.png),
[baseline](before/power_pilot.png), [measurements](performance.json),
[raw native report](noon/report.json), [checked runs](checks/),
[source identities](source-identity.json).
