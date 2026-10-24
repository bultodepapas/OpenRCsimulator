# F4U-15: the g1.13 model replaces g1.3

Integrated 2026-10-23 for the [F4U plan](../../../F4U-PLAN.md). The author's g1.13 delivery keeps the g1.3 airframe and rig. It rebuilds the wheels (grooved tyres, open rims, caps, valves; g1.8), details the six main gear-door interiors (g1.9) and adds five complete liveries. Presentation and contact geometry only; no aerodynamic data change.

## Freeze

[manifest.py](../../../../research/f4u-corsair/F4U-03/manifest.py) now freezes `assets/source-deliveries/f4u-corsair-g1-13/` (93 files, 72.8 MB). It checks them against the author's 246-entry manifest; 154 files are deliberately not copied, and their author hashes stay in [source-manifest.json](../../../../assets/aircraft/f4u-corsair-250/source-manifest.json):

| Omitted | Why |
| --- | --- |
| `textures/**` (editable layers, `.ora` sources, livery PNGs) | Every runtime image is embedded in the GLBs |
| `previews/*.png`, `previews/index.html` | Preview images are not needed in the repository |
| `source/aircraft_{blueangels,spectrum,splash,super57}.blend` | The four other livery sources; their GLBs are frozen |
| `source/scripts/uv-layout.json`, `reference-samples.json` | The author's 50 MB of UV and reference caches |

Visual revision `g1.13-03d66d8dc142`. The five GLBs are recorded by livery: `midnight` (Naval 308, `aircraft.glb`, the default), `blueangels`, `spectrum`, `splash`, `scarlet` (57/SOHIO).

## Checks

| Check | Result | Evidence |
| --- | --- | --- |
| [Preflight](../../../../research/f4u-corsair/F4U-04/preflight_glb.py) of all five GLBs | PASS: 99,729 triangles, 44 meshes, span 2.7778 m, ten crash sections, gear stowed | [checks/preflight-*.json](checks/) |
| `GearRetract` resampled from the g1.13 game source | Identical to g1.3 (largest numeric difference 0.0) | [gear-samples.json](../../../../assets/aircraft/f4u-corsair-250/gear-samples.json) |
| Model geometry | Only the wheels change: main tyre radius 0.09400 → 0.09415 m, so the main contacts drop 0.15 mm; tail unchanged within 1 µm | [model-geometry.json](../../../../assets/aircraft/f4u-corsair-250/model-geometry.json) |
| Physics | Regenerated; only the main contact heights and retraction paths move (≤ 0.15 mm). The wheel profile's main radius and inertia follow the new tyre | [wheel_profiles.json](../../../../app/data/ground/wheel_profiles.json) |
| `verify_f4u.gd` | 28/28 on g1.13 (44 meshes, 57 surfaces, 99,729 triangles) | [checks/verify_f4u.log](checks/verify_f4u.log) |
| Production flight scene: gear, flaps, smoke | 15/15 | [checks/systems.json](checks/systems.json) |
| Catalog and Corsair suites | 21 suites, 0 failures (catalog, render contract, customization, Workshop, UI, retracts, gear contacts and reserve energy, four crash suites, economy, night kit, trace metadata, audio, wheels, flaps) | — |

The g1.13 Naval 308 paint shows star-and-bar insignia, walkway stencils, the 308 numbers and black blades with yellow tips. The other four liveries are frozen and preflighted; selecting them is F4U-16.
