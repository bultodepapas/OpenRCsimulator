# Changelog

## r4 — 2026-10-25 · delivery-spec conformance for aircraft and skins

Pinned baseline: **r3** (`skywalker_x8_r3.zip`, delivered 2026-10-22; `source/aircraft_game.blend`
`ec5c99be…`, `export/aircraft.glb` `3e14a512…`, `export/aircraft_bolido.glb` `9cd46993…`). Master
v3.1 `6b70daf4…` unchanged. Both skins were re-exported from the same airframe and checked.

### Required changes
| # | Defect against the delivery brief | Affected | Correction | Measurable check |
| --- | --- | --- | --- | --- |
| 1 | Additional skin exported as `export/aircraft_bolido.glb`; the brief requires `export/<skin_id>.glb` | bolido | Path is now `export/bolido.glb`; `x8_game_spec.livery_glb()` | `export_all.py` writes it; K1 checks its hash |
| 2 | BÓLIDO baked always-on emissive navigation lenses although the simulator owns light state and the X8 UAV configuration has no lamp system | bolido: `x8_bolido_emission`, base colour, coat | Lenses repainted as unlit tinted glass; emission texture is black; lens positions recorded as decorative anchors; `lights.installed = false` | `checks/finish.json` (emissive faces = 0 for bolido) |
| 3 | Markings and insignia were flattened into the paint | both skins | Each painter runs twice (with and without markings); `paint_layers.py` stores `paint_base`, `markings` and `insignia` layers and recomposes the base colour | `checks/layers.json` (max difference ≤ 3/255) |
| 4 | Alternate-skin parity covered names, bounds and counts only | bolido | `skin_parity.py` and verifier check L1 compare positions, normals, UV0 and tangents per mesh in canonical order, plus hierarchy, rest transforms, extras and UV channels | `checks/parity_bolido.json`, `checks/structural_bolido.json` |
| 5 | Verifier lacked rejection cases for changed alternate-skin geometry and missing textures | verifier | New disposable-copy cases (2 mm vertex shift, normal texture removed from GLB, normal image removed from `.blend`) | `checks/negative_tests.json` |
| 6 | No `SHA256SUMS.txt`, no `checks/` evidence, no scope table, results not reported per skin | package | Added, with tool and input identity in `verification.json` | `make_sha256sums.py --check` |
| 7 | Demo animation GLB lived in `export/` next to the runtime skins | demo | Moved to `previews/demo/aircraft_demo.glb` | `export/` holds only runtime skins |

### Optional improvements
* One shared occlusion map (`textures/shared/x8_airframe_occlusion.png`) feeds the ORM red channel
  of every skin; the per-skin AO copies were removed (they were identical).
* `export_all.py`: one command exports every skin from the same `.blend`.
* New evidence: sampled rig comparison against r3 (`checks/motion_revision.json`), deviation
  against the master with maximum and 95th percentile (`checks/deviation.json`), finish per skin
  and part (`checks/finish.json`), closest views at 1920×1080 and 2560×1440 per skin
  (`checks/views/`), clean-package open/export/re-import (`checks/clean_package.json`).
* Previews reorganised per skin (`previews/abisal/`, `previews/bolido/`); silhouettes moved to
  `checks/silhouettes/`.

### Skin results
* `abisal` (default): unchanged; `export/aircraft.glb` sha256
  `3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac`, 8 547 120 bytes.
* `bolido`: changed only at the three lenses — the 4096 base colour differs from r3 in 1 363
  texels in exactly three regions, the emission map lost its three glowing spots, and roughness,
  metallic, coat and relief are identical; the ORM red channel now comes from the shared occlusion
  map (identical values):
  `export/bolido.glb` sha256 `9ecaf7b49aec555bbea178b3b582378bb362bec3f816448932438db2c8da8f93`,
  7 078 856 bytes.

### Preserved
Geometry, UVs, node names, hierarchy, pivots, rest transforms, ranges, sections, landmarks,
triangle and surface counts, materials, the ABISAL paint (all four runtime textures
byte-identical to r3, so `export/aircraft.glb` is byte-identical too: sha256 `3e14a512…`) and the BÓLIDO paint outside the three lens spots.

## r3 — 2026-10-22 · second livery BÓLIDO (skin)

Geometry, hierarchy, node names, pivots, rest matrices, ranges, sections, landmarks, triangle
count, materials and the UV atlas are identical to r2. ABISAL stays the default livery
(`export/aircraft.glb`, packed in the `.blend`).

### New livery BÓLIDO
* Original re-entry-demonstrator scheme inspired by the Space Shuttle thermal protection system:
  22 mm black ceramic tiles laid per zone (body axis, leading-edge sweep, hinge line), white
  44 mm tiles at the transition, quilted cream blankets, carbon-carbon nose cap and leading-edge
  panels with T-seals, felt on the elevons, temper-coloured motor heat shield; per-tile age,
  replaced tiles, part numbers, waterproofing holes, dings, a missing tile, gap fillers, plasma
  bleaching and streaks, heat stains, inspection rings, photogrammetry targets, rescue arrows,
  Spanish stencils, mission emblem and navigation lights.
* New scripts `livery_paint_bolido.py` (painter) and `render_bolido.py` (Cycles scenes:
  reentrada, estudio, planta, panza, nariz, pista; incandescence mask, volumetric plasma sheath
  and wake, temper thin film — all render-only).
* New files: `textures/bolido/` (4 runtime textures + 4096 sources and masks),
  `export/aircraft_bolido.glb`, `previews/bolido/`, `previews/renders/bolido/`.

### Package structure and scripts
* ABISAL moved to `textures/abisal/` and `previews/renders/abisal/` (file names unchanged).
* `x8_game_spec.py`: `LIVERIES`, `DEFAULT_LIVERY`, `LIVERY_SLOTS`, `livery_images()`,
  `livery_glb()`.
* `livery_bake_textures.py`: `--livery` and `--no-material` (skins write textures only).
* `export_glb.py` and `make_previews.py`: `--livery` swaps the four images of `x8_livery` in
  memory (the `.blend` is not saved).
* `verify_game.py`: `--livery`; J1 also checks the GLB image names of that livery; K1 checks the
  GLB hash of that livery and the texture hashes of every livery.
* `make_metadata.py`: `livery_common` (atlas, engine notes) and `liveries` (one block per skin
  with concept, textures, GLB hash, render-only features, pipeline).
* `release.py`: paints and bakes every livery, exports and verifies every GLB.
* GLB (ABISAL) sha256 `3e14a512fac3048e45cdeb46cbad7cc16f20fe41e5b6957b7df516c80a9b17ac`; GLB (BÓLIDO) sha256 `9cd46993ca116917e9062996c7ed9f4cd8b20933473732b5de1e373b658d8aba`.

## r2 — 2026-10-22 · livery ABISAL

Paint revision. Geometry, hierarchy, node names, pivots, rest matrices, ranges, sections,
landmarks and triangle count (38 504) are identical to r1; the changes are materials, UVs,
textures and the exporter options.

### Livery
* New original paint scheme **ABISAL** (deep-sea anglerfish): scales with iridescent rims,
  photophores, fin rays, bioluminescent lateral line, mouth with fangs and lure, false eyes on the
  winglets, gill slits, propeller warning chevrons, Spanish technical stencils, and realistic
  wear (chipped EPO, belly scrapes and grass, insects, grime, hand prints, tape repair, glued
  crack). No real brands, insignia or registrations.
* Procedural 3D painter (`livery_paint.py`): every texel is painted from its baked 3D position,
  normal, part and region, so there are no seams; relief is a height field.
* New scripts: `livery_uv.py`, `livery_bake_geom.py`, `livery_paint.py`,
  `livery_bake_textures.py`, `render_livery.py`; `release.py` runs the four livery steps after
  `build_game.py`.

### Materials and UVs
* `x8_epo_white` and `x8_servo_cover` are gone; the outer skin of the nine visible parts now
  uses one atlas material, `x8_livery` (base colour, ORM, normal, emission; 2048², packed in the
  `.blend`, embedded in the GLB). Hinge tape, servo covers, orange plastic and propeller blades
  are painted regions inside the atlas, kept as face attributes `x8_part` / `x8_region`.
* New UV map `UVMap` (Smart UV Project + Pack Islands): coverage 0.545,
  0.87 mm per texel at 2048.
* Materials 10 → 9, material surfaces 34 → 24, textures 0 → 4.

### Export and verification
* `export_glb.py`: `export_tangents=True` (the normal map was baked with Blender's MikkTSpace
  tangents). Images are embedded; still no extensions.
* GLB 977 764 → 8 547 132 bytes; new sha256 `724ed586c51376036f5e42675e15aad695b78ea8ecbcf4452142d57bc58daaa3`.
* `verify_game.py`: new check H4 (packed 2048 images, names, UVs inside [0, 1]); J1 also checks
  embedded images, the atlas slots, the shared ORM image, emissiveFactor 1 and UV/normal/tangent
  attributes on the atlas primitives; K1 also checks texture hashes against `metadata.json`.
* `make_previews.py` shows the atlas (Workbench texture colour); `make_metadata.py` writes the
  `livery` block and lists the real materials.

## r1 — 2026-10-22

First game version of the Skywalker X8. There is no earlier game revision, so the changes are
listed against the precise master.

### Source master v3 → v3.1 (corrections that also apply to the master)

* **Propeller position.** In v3 the blades, hub and spinner were parented to the rotor while its
  matrix was still stale, which moved them about 0.40 m aft of the motor. They now sit on the
  hub (x = 846 mm).
* **Propeller pitch sense.** In v3 the blade leading edge sat behind the trailing edge, so a
  leading-edge-first spin pushed aft. The blade pitch angle sign is corrected (correct pusher:
  leading edge and cambered face toward the nose) and the master's rotor now spins
  leading edge first.
* **Camera doors.** The inboard edge of each door half is trimmed by a cylinder of radius
  (half-width − 0.4 mm) around its hinge, so the two halves can open together without touching
  (v3 only checked each door against the fuselage). The piano-hinge pins are 0.4 mm in radius
  and sit on the hinge axis inside the 1 mm slot.
* **Motor.** The mount plate sits 0.3 mm behind the fuselage trailing edge and the motor base ends
  0.5 mm before the rotating bell. Fixed and rotating parts no longer share faces.
* Generator gains `RES`/`set_resolution()` (tessellation and the two optional corrections);
  default values reproduce the master exactly (triangle counts checked).

### Game version (this package)

* Retessellated from the same equations: 38 504 triangles instead of about 210 000. Hinge lines,
  hatch outline, door outlines and the root joint did not move.
* New frame: +X right, +Y nose, +Z up, origin D0 (wing leading edge at the root rib, thrust-axis
  height), metres; GLB Y-up. The master frame was X = left, Y aft, origin at the nominal CG.
* Crash sections as separate meshes with `openrc_section`: core, canopy (hatch), wing_left,
  wing_right, engine, propeller.
* New pivots with +X as the rotation axis: `elevon_*_hinge` (+ = trailing edge down; the master
  hinge rotated the other way), `camera_door_*_hinge` (+ = open), `thrust_frame` / `propeller_spin`
  (+X = thrust direction). Master rig, drivers, logic and helper empties are not exported.
* Merged per section: winglet into its wing; horn into its elevon; outrunner bell and shaft into
  the rotor; equipment into `bay_equipment`.
* Hinge tape and servo covers became material regions; a black 2 mm slot cover on each elevon
  replaces the tape that bridged the hinge slot.
* Closure faces: foam-coloured side caps on the centre body, root caps on the wings, 0.1 mm
  separations at the rib.
* 10 shared flat Principled materials (was 28 in the master), backface culling on.
* Excluded (see `export-map.json`): servo arms, pushrods, hidden servos, magnets, tabs, latch
  pin, spring, carbon tubes, rotary-lock parts (not installed with the parachute), logic
  indicators, studio content.
* Mesh cleanup: near-duplicate vertices (< 0.02 mm) merged, n-gons from booleans triangulated,
  no degenerate triangles.
