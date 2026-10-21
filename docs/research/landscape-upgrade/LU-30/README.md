# LU-30 — Downloaded transmission towers and conductors

2026-10-20. The five existing east-corridor pylons are replaced by downloaded
lattice geometry. The same placement identities connect four spans, each with
six phase conductors and an upper shield wire. No tower or cable curve is
modeled from scratch.

## Sources and adaptation

| Source | License | Use |
| --- | --- | --- |
| [Transmission Tower, iPoly3D](https://poly.pizza/m/TYK3rPu7E5) | CC0-1.0 | Original 5,743-triangle lattice and footings, uniformly fitted to 30 m. |
| [Rope bridge, Jeremy Eyring](https://poly.pizza/m/88e4zjTShuY) | CC BY 3.0 | One supplied 128-triangle curved handrail, extracted and fitted as a conductor. |
| [Power Pole, Grab3D](https://grab3d.com/models/city/power-pole/) | CC0-1.0 | Supplied insulator geometry, adapted beneath the crossarms. |

Original GLBs, license text, download URLs and SHA-256 identities live in
[`assets/landscape/power-lines`](../../../../assets/landscape/power-lines/).
Shipped attribution and modifications are listed in
[`UPGRADE_CREDITS.md`](../../../../app/assets/landscape/UPGRADE_CREDITS.md).

The cable extractor selects a connected component from the source rope
material. Nine existing cross-sections provide the sag profile. Their centers
are normalized separately from the 25 mm radial offsets; stretching a span
therefore does not create thick vertical ribbons. The source has approximately
5.72% sag; the scenery fits that profile to an estimated 2.3% sag/span ratio.
The original 81 vertices and 128 faces are retained. The Y/Z coordinate swap
already converts glTF winding to Godot winding; the extractor checks that every
face points outward.

The original roughly 96–99 m intervals and tower coordinates are retained.
`tools/scenery/place.py` computes headings from neighboring tower positions,
aligning local -Z with the route and local X crossarms across it. Generated
default scenery and its dependent countryside source identity are regenerated
through their existing pipelines.

Engineering context: [IUCN's *Wildlife and power lines*](https://portals.iucn.org/library/sites/library/files/documents/2022-043-En.pdf)
illustrates phase conductors, two circuit sides and upper ground wires.
[Powerlink's vegetation specification](https://www.powerlink.com.au/sites/default/files/2024-02/Vegetation%20Management%20-%20Specification%20.pdf)
illustrates changing conductor sag. These inform visual organization; the
scenery does not simulate conductor temperature, tension or electrical behavior.

## Runtime boundaries

`app/scenery/power_lines.gd` caches imported arrays and appends them to existing
scenery cells. There are no extra per-frame callbacks, lights or independent
nodes per cable. Full mesh bounds include the conductors for frustum culling.
Tower group/index identities and damage tags remain stable.

The imported tower measures approximately 8.652 × 30 × 8.450 m. The catalog
records those dimensions. CollisionWorld retains float64 state and uses
conservative stepped leg capsules and crossarm boxes fitted to the imported
dimensions. These are structural envelopes, not triangle-accurate lattice
collisions. Conductors and insulators are visual only.

The low-polygon source remains visible in close inspection. At long distances,
thin conductors become subpixel and may alias at 720p/4× MSAA; there is no
screen-space glow or artificial widening.

## Reproduce

```powershell
python tools/scenery/place.py --check
python tools/scenery/bake_countryside.py --check
python tools/scenery/bake_power_cable.py --check
python tools/scenery/bake_power_insulator.py --check
```

Native capture cases: `power_close`, `power_overview`. Use the checked Godot
runner with `res://tests/capture_landscape_upgrade.gd`, `--time_of_day=noon`,
`--botanical_clock=0.25`, 1280×720, and 240 measured frames.

## Verification and measurements

The 30 imported insulators retain 1,488 source triangles each and fit a
0.30 × 1.10 × 0.30 m envelope. The original pin form is inverted and stretched;
it is a visual adaptation, not a voltage-rated suspension-string design.
Five lattices, 30 insulators and 28 conductors total 76,939 triangles.
The isolated scenery-build test measures 715,023 triangles across the scene,
with the same 60 merged cells. Its former 650,000 ceiling is raised explicitly
to 725,000 for these downloaded assets; the build-time ceiling remains 800 ms
(675 ms measured in the final checked run).

The v0.1.7 release check uses this 725,000 ceiling for non-fleet field geometry,
the separately reviewed SC-09-R1 350,000 ceiling for parked aircraft, and a
30,000 ceiling for lake-context additions. Godot 4.7.2 measured 998,305 field
triangles, including 273,421 fleet triangles (724,884 non-fleet), and 26,340
additional lake-context triangles. The complete lake-context scene is 1,024,645
triangles. The former LU-21 650,000 assertion predates both the power-line and
parked-fleet additions; these three component limits preserve bounded checks.

Passed checks:

- 19 imported-geometry, route-orientation, topology and clearance assertions in
  `test_power_lines.gd`.
- 15 focused structural collision assertions and 51 existing landscape
  collision checks, including rotated hits and open-gap misses.
- Existing scenery loader and complete scenery-build tests: bounds, materials,
  winding, quality tiers, deterministic geometry and budgets.
- Both source extraction `--check` commands and the existing scenery and
  countryside regeneration checks. Source extraction checks now run in the
  integration partition of `app/test.sh`.
- Native Godot rendering on an RTX 3090, Compatibility/OpenGL, 1280×720,
  4× MSAA. The pre-existing maple wind-material warning remains unchanged.

| View | Before p95 / final p95 | Before / final draw calls |
| --- | --- | --- |
| Close | 1.348 / 1.329 ms | 18 / 18 |
| Overview | 2.694 / 1.227 ms | 23 / 24 |
| Insulator detail | — / 1.188 ms | — / 10 |

Each capture measures 240 frame intervals after warmup. These are unpaired
measurements under shared desktop load and concurrent workspace activity, not
isolated GPU costs. The wider mesh bounds can expose one additional existing
cell in the overview. Lower-end hardware and owner flight-readability review
remain open.

Evidence: [close view](noon/power_close.png),
[insulators and attachment points](noon/power_insulators.png),
[whole line](noon/power_overview.png), [previous geometry](before/power_close.png),
[raw native report](noon/report.json), [measurement summary](performance.json),
[checked runs](checks/), [source identities](source-identity.json).
