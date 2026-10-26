# Skywalker X8 — game asset r4 · skins `abisal` + `bolido`

2026-10-25 · Revision r4 · Production game version of the precise Skywalker X8 master (v3.1)
with two skins, brought into line with the *Senior Blender Developer — Aircraft and Skins
Delivery* brief. r4 changes packaging, editable paint sources, lights and verification; the
airframe, rig and ABISAL paint are those of r3. Previous deliveries (r1–r3) and the master are
untouched.

## 1 Delivery scope

| Item | Record |
| --- | --- |
| Aircraft | **Skywalker X8**, EPO-foam blended flying wing with winglets and a pusher propeller (visual family: flying-wing UAV). RC variant: 2120 mm-span X8 kit in the UAV mapping configuration — mapping camera behind two ventral doors, parachute pack, magnetic top hatch, 6S 5000 mAh battery, FPV camera, autopilot, telemetry. Scale 1:1 of the RC aircraft, metres. |
| Sources | Master v3.1 `Skywalker_X8/Skywalker_X8.blend`, sha256 `6b70daf46dc6414ad04b5e656ac96bb2916e463ff7e686accda4dcad41237156`, from the parametric generator `source/scripts/x8_skywalker_blender.py` built on the Skywalker three-view and spec sheet, kit photographs and Gryte et al. (ICUAS 2018). Baseline game revision **r3** (`skywalker_x8_r3.zip`, delivered 2026-10-22; `aircraft_game.blend` `ec5c99be…`, `aircraft.glb` `3e14a512…`, `aircraft_bolido.glb` `9cd46993…`). Integration acceptance of r3 is not recorded; r3 is the pinned baseline. |
| Delivery | Revision **r4**, package `skywalker_x8/skywalker_x8_r4.zip` (folder `r4/`). Scope: conform the existing aircraft and its two requested skins to the brief; no new skins, no geometry or rig changes. |
| Changes | Required: skin export path, unlit lenses (no fake lamps), layered paint sources, full skin parity, new rejection tests, SHA256SUMS, `checks/`, per-skin records, demo out of `export/`. Optional: shared occlusion map, `export_all.py`, deviation/finish/view/clean-package evidence. Preserved: everything else (see `CHANGELOG.md`). |
| Geometry | Span 2.1172 m (manual 2.120 m), nose to spinner tip 0.8752 m, height 0.2961 m; D0 and landmarks in §6 and `metadata.json`; tolerances in §6; measured from transformed vertices of the game scene; manual values are labelled as such. |
| Motion | Elevons (+ = trailing edge down, ±26.8° combined travel, clearance −40…+31°), camera doors 0–110° (unsupported mechanism role, §8), propeller continuous. No gear, folds, canopy mechanism, tailhook, cowl flaps or lamps. |
| Skins | 1. `abisal` — "ABISAL - deep-sea anglerfish" → `export/aircraft.glb` (**default**). 2. `bolido` — "BOLIDO - re-entry heat shield" → `export/bolido.glb`. |
| Views and budgets | No simulator views or per-aircraft budgets were supplied. Provisional closest views at 1920×1080 and 2560×1440 are recorded in §9; budgets are the working targets used since r1 for this same aircraft (30 000–50 000 triangles target, 100 000 ceiling, ≤ 10 materials, ≤ 40 mesh × material surfaces, 4 × 2048² textures per skin) and are **not** approved acceptance limits. |
| Reproduction | Blender 5.2.2 LTS (build d13f752e3b9c) as the `bpy` 5.2.2 module, glTF I/O 5.2.40, Python 3.13, numpy, SciPy, Pillow; commands in §4. |
| Open items | Godot 4.7.2 import and simulator checks pending integration; camera-door mechanism role; runtime texture resolution for the closest views (§9); no simulator display name; asset licence terms not yet set by the owner. |

## 2 Package layout and entry points

```
r4/
  README.md  CHANGELOG.md  LICENSE.txt  SHA256SUMS.txt
  source/aircraft_game.blend        editable game scene, default skin (abisal) packed
  source/scripts/                   derivation, painters, all-skin export, verification
  export/aircraft.glb               abisal (default), runtime rest pose
  export/bolido.glb                 bolido, same airframe
  metadata.json  export-map.json  verification.json
  textures/shared/                  x8_airframe_occlusion.png (ORM red channel of every skin)
  textures/<skin>/                  4 runtime textures (2048²) embedded in that skin's GLB
  textures/<skin>/source/           4096 paint maps, 16-bit height, baked normal, masks
  textures/<skin>/source/layers/    paint_base, markings, insignia (editable layers)
  checks/                           structural, parity, motion, deviation, finish, views, layers,
                                    negative tests, clean package, full rebuild, silhouettes
  previews/<skin>/                  Workbench views with backface culling (both skins)
  previews/renders/<skin>/          Cycles renders (7 abisal, 2 bolido)
  previews/demo/aircraft_demo.glb   animation demo (reference only, not a runtime asset)
```

Entry points: `source/aircraft_game.blend` (opens on the assembled neutral aircraft; one
collection `EXPORT_aircraft`; nine materials, the four ABISAL images packed; no libraries, caches
or add-ons) and `export/aircraft.glb` (default skin).

## 3 Skins

Both skins are original: no real brands, logos, insignia or registrations; every name is
invented. They share one airframe and one atlas: material `x8_livery`, UV map `UVMap`
(TEXCOORD_0 for every texture), nine painted meshes, UV coverage 0.545, **0.87 mm per texel** at
2048 (0.43 mm in the 4096 sources). Interior foam, metal, glass, motor bell, motor mount and bay
equipment keep flat materials, identical in both skins. Each separable part carries its own
pixels, so paint travels with the part that breaks off.

| Runtime texture (2048², per skin) | glTF slot | UV | Colour space | Content |
| --- | --- | --- | --- | --- |
| `x8_<skin>_base_color.jpg` | baseColorTexture | 0 | sRGB | albedo (composite of the layers) |
| `x8_<skin>_orm.png` | occlusionTexture (R) + metallicRoughnessTexture (G, B) | 0 | linear | R = shared occlusion, G roughness, B metallic |
| `x8_<skin>_normal.png` | normalTexture (scale 1) | 0 | linear | tangent space, MikkTSpace, +Y up; tangents exported |
| `x8_<skin>_emission.jpg` | emissiveTexture, emissiveFactor (1, 1, 1) | 0 | sRGB | abisal: decorative bioluminescence; bolido: black |

**Editable sources.** Each painter runs twice, with and without markings; `paint_layers.py`
stores `layers/x8_<skin>_paint_base.png`, `x8_<skin>_markings.png` (RGBA) and, for bolido, the
mission emblem as `x8_<skin>_insignia.png`. Base colour = base, then markings, then insignia
("over"); the recomposition matches the delivered base colour within 1/255. Text cannot be
mirrored: a decal is only applied to faces whose outward normal agrees with its text axes. Hand
edits: edit the layers or maps in `textures/<skin>/source/`, run
`paint_layers.py compose textures/<skin>/source <skin> --write`, then
`livery_bake_textures.py … textures/<skin> --livery <skin>` (add `--no-material` for bolido),
`export_all.py` and the verifier.

**Finish.** Intentional differences, measured per painted mesh in `checks/finish.json`: abisal
is a satin scaled skin (roughness 0.41–0.46 on the airframe, metallic 0.09–0.22 from the
silvery belly and fins) with fine relief (mean normal tilt 1.4°); bolido is matt ceramic, fabric
and felt (roughness 0.50–0.78, metallic near 0 except the temper-coloured motor shield and the
aluminium rib and horns) with deeper tile and quilt relief (mean tilt 3.3°). Both use the same
shared occlusion channel; only abisal emits light (decorative).

**Lights.** No lamps: the X8 UAV configuration has no lighting system, so no `navigation`,
`strobe`, `landing` or `orientation` groups are declared. ABISAL's always-on glow is decorative
paint, not a lamp. BÓLIDO's lens shapes are unlit; their anchors are recorded in
`metadata.json → skins[bolido].unlit_light_lenses` for a future lamp installation.

**Workshop.** Paint-region targets and five marking anchors (both wing tops, left wing underside,
both winglet outer faces) are recorded for the default skin only
(`default_skin_paint_targets`, `default_skin_marking_anchors`).

### 3.1 `abisal` — ABISAL (default, added in r2)

A flying wing painted as an anglerfish from the deep sea, worn like a working UAV.

**Animal.** Blue-black skin; hexagonal scales on the back drawn as overlapping arcs (cycloid
edges) with an iridescent rim; silver-violet belly with rows of photophores (glowing dots);
segmented fin rays radiating across the wings with a violet trailing edge; a cyan bioluminescent
lateral line along the body; an open mouth with fangs on the nose, a glowing lure above it and
small real eyes at the corners of the mouth; large false eyes with a slit pupil, a violet glowing
ring and a glossy cornea on both winglets; four coral gill slits behind the mouth, coral root
ribs and bone-coloured control horns; yellow/black warning chevrons around the pusher propeller
and cyan-tipped blades.

**Use.** Chipped edges that show the white EPO foam underneath, belly scrapes and grass stains
from belly landings, insects on the leading edges, dirt in seams and around the hatch, hand
prints where the aircraft is launched, a silver tape repair on the left leading edge, a glued
crack on the nose, faded technical stencils in Spanish (CG 430–440 marks, battery label, hatch
"LEVANTAR / IMANES", "PARACAIDAS / NO OBSTRUIR", "CAM / LIBRE" on the doors, "NO EMPUJAR" on the
elevons, "PELIGRO / HELICE", serial numbers inside the winglets, a calibration ruler under the
right wing), servo-cover screws, and the invented names `ABISAL`, `X8·08` and `ABISAL-08`.

Renders: `previews/renders/abisal/` (`render_livery.py`). Scale iridescence and clear coat
are render-only.

### 3.2 `bolido` — BÓLIDO (added in r3)

The X8 as a re-entry demonstrator. Inspiration: the thermal protection system of the Space
Shuttle (black HRSI tiles, white LRSI tiles, quilted FIB blankets, reinforced carbon-carbon, gap
fillers), studied from the Wikipedia article on the system and NASA photographs of Endeavour and
Columbia. No NASA markings or insignia are reproduced; the programme, the names `BÓLIDO`,
`VR-08` and `DEMOSTRADOR DE REENTRADA`, and the mission emblem are invented.

**Heat shield.** Underside in black reaction-cured-glass tiles of 22 mm (scaled from the 6-inch
originals), laid along the body axis, along the leading-edge sweep on each wing and along the
hinge line on each elevon, with 0.55 mm joints, rounded edges, small steps between tiles, a
tiny part number and one or two waterproofing holes on each tile. Every tile has its own age:
most are worn satin black, a few are old and bleached, and replaced ones are fresh gloss black,
often in clusters. White 44 mm tiles at the black/white transition, which steps along tile
edges as on the real vehicle; cream quilted insulation blankets (11 mm quilting, panels with
seams) on the top; grey carbon-carbon nose cap and leading-edge panels with dark T-seals and a
white gap filler where they meet the tiles; white felt on the elevon tops with a black-tile
strip at the trailing edge; black cloth hinge seals; a metal heat shield around the motor in
temper colours (straw, bronze, violet, blue).

**Flight history.** Plasma bleaching and streaks along the flow on the belly, strongest at the
nose and the leading edges; tobacco-brown heat stains where the hot gas leaked onto the blankets;
grey soot behind the elevon coves; chipped tiles showing the white silica inside; one missing
tile on the left wing underside with the felt pad, the green primer and red adhesive exposed;
white gap fillers sticking out between tiles (many around the camera doors); yellow and white
grease-pencil inspection rings around damaged tiles; technicians' smudges on the hatch.

**Markings.** `BÓLIDO` and `VR-08 · DEMOSTRADOR DE REENTRADA` across the wings, `BÓLIDO` on the
fuselage sides, `08` on the winglets, a round mission emblem on the hatch, yellow rescue arrows
"RESCATE · LEVANTAR", photogrammetry targets for flight-test cameras, CG marks, "NO PISAR",
"NO EMPUJAR", "PELIGRO HÉLICE" with a red/white band, "CAM" on the doors, serial numbers inside
the winglets, a carbon-fibre propeller with yellow tips, and unlit navigation-light lenses (red
left, green right, white tail). Since r4 the lenses carry no emission: the X8 UAV configuration
has no lamp system and the simulator, not the paint, owns light state.

Renders: `previews/renders/bolido/x8_bolido_reentrada.png` and `x8_bolido_estudio.png`
(`render_bolido.py`; the incandescence mask, plasma shells and wake are render-only).

## 4 Tools and reproduction

* Blender **5.2.2 LTS**, build `d13f752e3b9c` (2026-09-15), Khronos glTF Blender I/O **5.2.40**,
  as the Python `bpy` 5.2.2 module (Python 3.13, Linux x86_64); Cycles CPU with OpenImageDenoise;
  numpy, SciPy, Pillow. The `blender -b …` lines are the equivalent invocation with the same
  build; they were not run here. Exact versions per run: `verification.json → tool_identity`.
* Target: Godot 4.7.2, Compatibility renderer (not available in this environment).

All skins, one command (from the same `.blend`, geometry and rig; `GLTF_SETTINGS` in
`export_glb.py`: GLB, Y-up, `export_extras=True`, `export_apply=True`, only `EXPORT_aircraft`,
tangents, embedded images, no cameras, lights, animation, compression or extensions):

```
python source/scripts/export_all.py source/aircraft_game.blend export/
blender -b --factory-startup --python-exit-code 1 --python source/scripts/export_all.py -- source/aircraft_game.blend export/
```

Verify every GLB (exit code 1 on any mandatory failure), then the rejection tests:

```
python source/scripts/verify_game.py source/aircraft_game.blend --glb export/aircraft.glb --metadata metadata.json
python source/scripts/verify_game.py source/aircraft_game.blend --glb export/bolido.glb --livery bolido --metadata metadata.json
python source/scripts/skin_parity.py export/aircraft.glb export/bolido.glb
python source/scripts/test_verifier_rejects.py source/aircraft_game.blend
python source/scripts/make_sha256sums.py . --check
```

Full rebuild and all evidence (geometry, both skins with their layers, textures, GLBs, previews,
metadata, `checks/`, `verification.json`, `SHA256SUMS.txt`; about 20 min on 2 CPU threads,
plus about 6 min for the view renders):

```
python source/scripts/release.py --master ../../Skywalker_X8/Skywalker_X8.blend --baseline <r3 package>
```

## 5 Configuration

UAV configuration of the master: mapping camera behind two articulated ventral doors, parachute
pack inside the bay, magnetic top hatch (tagged `canopy` so it can fly off), battery centre at
228 mm from the nose (CG 435 mm in the master's estimate). Elevons, doors and propeller neutral,
hatch closed. The X8 has no landing gear, tail, flaps or rudder.

## 6 Frames, units, D0 and landmarks

| Frame | Right | Up | Nose |
| --- | --- | --- | --- |
| Blender game scene | +X | +Z | +Y |
| GLB / Godot | +X | +Y | −Z |

`godot = (blender.x, blender.z, -blender.y)`, applied once by the Y-up export. Metres
throughout. From the master's mm tables (x aft from the nose, s right, z up):
`blender = (s, x_D0 − x, z − z_D0) / 1000`, `godot = (s, z − z_D0, x − x_D0) / 1000`.

**D0** = symmetry plane, the wing leading edge at the orange root-rib station (s = 236 mm, the
wing/centre-body joint), and the thrust-axis height: x_D0 = 299.581 mm behind the nose,
z_D0 = 1.0 mm in master coordinates. The root `SkywalkerX8` has zero translation and rotation and
unit scale. D0 is not the CG. Dihedral (1.5°), washout (−2.5°) and the motor axis (no down/right
thrust) are kept; no ground attitude or floor offset is baked.

Main landmarks (Blender game frame, m; Godot values are in `metadata.json`):

| Landmark | x | y | z |
| --- | --- | --- | --- |
| Nose tip | 0.006 | 0.3007 | 0.0088 |
| Spinner tip (pusher, points aft) | 0 | −0.5744 | −0.0030 |
| Propeller hub | 0 | −0.5464 | 0 |
| Right wingtip (winglet) | 1.0586 | −0.6775 | 0.2064 |
| Right wing-root leading edge | 0.2376 | −0.0008 | 0.0070 |

Span 2.1172 m (manual 2.120 m), nose to spinner tip 0.8752 m, height 0.2961 m, propeller
0.3049 m (12 in nominal). Scale is the master's; nothing was rescaled to manual values.

Offset from D0 to the physical wing-leading-edge datum: the physical datum used here is the wing
leading edge at the root rib, (±0.2376, −0.0008, +0.0070) m in the Blender game frame (landmarks
`wing_root_leading_edge_left/right`); D0 lies on the symmetry plane at the same chordwise station
and at thrust-axis height. Manufacturer CG references (430–440 mm from the nose) are recorded in
`metadata.json` as manual values, not measurements.

Tolerances declared for this revision: export consistency 0.1 mm / 0.01° (pivots, axes, mesh
boxes, landmarks after re-import); revision parity against r3 1 µm (sampled rig) and exact
(skin parity, 1e-6 m positions, 1e-5 normals/tangents, 1e-6 UV); deviation against the master
p95 ≤ 1.0 mm and max ≤ 10 mm per mesh (provisional, see §9).

## 7 Hierarchy and crash sections

```
SkywalkerX8                     identity root at D0 (untagged)
  fuselage_core                 [core]      centre body, hollow bay, FPV window, door hinge pins
  bay_equipment                 [core]      battery, avionics, parachute pack, mapping camera
  canopy_hatch                  [canopy]    magnetic top hatch (detaches)
  wing_left_fixed               [wing_left] outer panel, winglet, orange root rib
  wing_right_fixed              [wing_right]
  motor_mount                   [engine]    mount plate + motor base (fixed)
  elevon_left_hinge             [wing_left]
    elevon_left                 [wing_left] elevon, control horn, hinge slot cover
  elevon_right_hinge            [wing_right]
    elevon_right                [wing_right]
  camera_door_left_hinge        [core]
    camera_door_left            [core]
  camera_door_right_hinge       [core]
    camera_door_right           [core]
  thrust_frame                  untagged, fixed shaft orientation
    propeller_spin              [propeller]
      propeller_rotor           [propeller] blades, hub, spinner, outrunner bell, shaft
```

`openrc_section` is a custom property on every exported mesh and moving pivot and reaches the
GLB as node `extras`. Different sections are sibling branches; the rotor is not under `engine`.
Closure faces: each side of the centre body ends in a foam-coloured cap hidden behind the orange
root rib; the rib closes the wing root. Pieces are separated by 0.1 mm at the joint (no coplanar
faces). When the hatch flies off it uncovers the hollow bay, its foam walls and the equipment.

## 8 Articulation and mechanisms

Every moving pivot rotates about its own local **+X**, angle 0 = saved rest:
`local = rest * rotation_about_local_X(angle)`.

| Pivot | Positive | Range (source) | Verified clearance |
| --- | --- | --- | --- |
| `elevon_left_hinge`, `elevon_right_hinge` | trailing edge down | ±19.5° pitch only, ±23.3° roll only, −26.76…+26.85° combined = full servo travel (master rig, default radio config) | free from −40° to +31° (1° steps) |
| `camera_door_left_hinge`, `camera_door_right_hinge` | door opens | 0–110° (keeps an 80° camera cone clear) | 0–110°, both doors together, no contact |
| `propeller_spin` | clockwise seen from behind (right-handed about +X = thrust) | continuous | full turn, no contact |

Elevon mixing (degrees of surface, + = trailing edge down): `left = roll − pitch`,
`right = −roll − pitch`, with pitch + = nose up and roll + = right wing down.

| Mechanism class | Status |
| --- | --- |
| Conventional control surfaces | `elevon_left_hinge`, `elevon_right_hinge` (two elevons; no ailerons, flaps, elevator or rudder) |
| Propeller | `propeller_spin` → `propeller_rotor`; fixed `motor_mount` in section `engine`; full revolution checked |
| Camera bay doors | `camera_door_left_hinge`, `camera_door_right_hinge`, hinge-style pivots about local +X, closed at rest. **Not one of the shared auxiliary mechanism roles** (canopy, tailhook, cowl flaps): reported for integration review before any runtime use |
| Canopy | `canopy_hatch` is a detachable section only (magnetic hatch); no opening mechanism |
| Landing gear, retracts, wing folds, tailhook, cowl flaps, lights | Not applicable: none on this aircraft/configuration |

The sampled rig of r4 was compared with r3 over 201 poses (every elevon degree across −26.76…+26.85
plus ±40, doors every 5° to 110, propeller every 10°): see §10.

## 9 Views, budgets and counts

**Closest views (provisional).** OpenRC camera distances and fields of view were not supplied, so
three views were defined and rendered for every skin with the runtime material (2048 textures, as
embedded), identical lights and exposure: Cycles CPU, 16 samples + OpenImageDenoise, AgX; Intel
Xeon @ 2.10 GHz, 2 threads (`checks/views/`).

| View | Resolution | Camera distance | Horizontal FOV | Pixel on aircraft | Atlas texel | Texels per pixel |
| --- | --- | --- | --- | --- | --- | --- |
| `workshop_3q` (whole aircraft, 3/4 front-left) | 1920×1080 | 2.8 m | 50° | 1.36 mm | 0.87 mm | 1.56 |
| `inspection_nose` (nose, hatch, markings) | 1920×1080 | 0.9 m | 40° | 0.34 mm | 0.87 mm | 0.39 |
| `inspection_nose` | 2560×1440 | 0.9 m | 40° | 0.26 mm | 0.87 mm | 0.29 |
| `chase` (behind, above) | 1920×1080 | 3.5 m | 70° | 2.55 mm | 0.87 mm | 2.93 |

At the closest inspection view the 2048 atlas is magnified about 2.5× (3.4× at 1440p): edges stay
clean but fine paint detail softens. The 4096 sources are in the package; choosing 4096 runtime
textures for Workshop close-ups is an integration decision (open item). The Workshop and chase
views are adequately sampled.

**Counts per skin** (identical airframe; measured on the `.blend` and on each GLB):

| Skin | GLB | sha256 | Triangles | Mesh nodes | Surfaces (mesh × material) | Materials | Textures | GLB bytes | Verification |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `abisal` (default) | `export/aircraft.glb` | `3e14a512fac3048e…` | 38 504 | 11 | 24 | 9 | 4 × 2048² | 8 547 120 | pass |
| `bolido` | `export/bolido.glb` | `9ecaf7b49aec555b…` | 38 504 | 11 | 24 | 9 | 4 × 2048² | 7 078 856 | pass |

Texture memory per skin (estimate): 85.3 MiB uncompressed RGBA8 with mipmaps, about 13.3 MiB with
GPU block compression (three 4-bit-per-pixel maps and one 8-bit-per-pixel normal map). Fleet:
15 625 976 bytes of GLB for the two skins; package 206 MB unzipped. The real import format
and memory must be measured in Godot (pending integration).

**Budgets.** No per-aircraft budget was supplied. Working targets used since r1 for this aircraft
(provisional, not approved): 30 000–50 000 triangles (ceiling 100 000), ≤ 10 materials,
≤ 40 surfaces, four 2048² textures per skin. Both skins meet them. Godot generates LODs on
import; no LOD copies are exported.

**Deviation from the master** (`checks/deviation.json`, game frame, rest pose; `checks/silhouettes/`):

| Mesh | Game → master p95 / max (mm) | Master → game p95 / max (mm) |
| --- | --- | --- |
| `camera_door_left` | 0.20 / 0.25 | 0.33 / 0.34 |
| `camera_door_right` | 0.17 / 0.23 | 0.33 / 0.34 |
| `canopy_hatch` | 0.49 / 1.00 | 0.50 / 0.85 |
| `elevon_left` | 0.01 / 0.84 | 0.03 / 0.11 |
| `elevon_right` | 0.01 / 0.84 | 0.03 / 0.11 |
| `fuselage_core` | 0.33 / 1.09 | 0.42 / 2.76 |
| `motor_mount` | 0.00 / 0.00 | 0.20 / 0.20 |
| `propeller_rotor` | 0.02 / 0.04 | 0.14 / 0.36 |
| `wing_left_fixed` | 0.02 / 0.27 | 0.12 / 11.18 |
| `wing_right_fixed` | 0.02 / 0.27 | 0.12 / 11.18 |

Silhouette IoU against the master: front 0.9965, side 0.9975, top 0.9994. Provisional thresholds
(declared before measuring): p95 ≤ 1.0 mm and max ≤ 10 mm. Both wings exceed the maximum from the
master side only (11.18 mm, 0.018 % of master vertices): the master's servo-bay cavity
(boolean, s ≈ ±502 mm, 558 mm from the nose) is not cut in the game wing, whose bay is closed by
the painted servo cover — a simplification documented since r1. Disposition: accepted as a
warning.

## 10 Verification

Every check below was run on this revision (`verification.json`, `checks/`):

| Check | Scope | Result |
| --- | --- | --- |
| Structural verifier (`verify_game.py`): hierarchy, names, tags, section subtrees, root identity, unit scales, positive directions, neutral interpenetration, clearance sweeps, return to rest, mesh quality, closed shells, exportable materials with backface culling, packed 2048 textures, UVs in [0, 1], GLB contract (no extensions, cameras, lights, animation; embedded images named for the skin; atlas slots; texCoord 0; tangents), clean re-import within 0.1 mm / 0.01°, metadata consistency | each GLB | abisal **pass**, bolido **pass** |
| Skin parity (`skin_parity.py`, verifier L1): nodes, parents, rest TRS, extras, and per mesh positions, normals, UV0 and tangents in canonical triangle order | bolido vs abisal | **pass**, maximum difference 0 |
| Sampled rig against r3 (`check_rig_revision.py`): 201 poses, all vertices of all meshes | airframe | **pass**, maximum difference 0 m |
| Layered paint recomposition (`paint_layers.py compose`) | each skin | **pass**, ≤ 1/255 |
| Finish (`check_finish.py`): normal maps present, shared occlusion channel identical, 2048 sizes, per-part roughness/metallic | each skin | **pass** |
| Rejection tests on disposable copies: removed `elevon_left_hinge`, invalid tag, missing tag, missing packed texture, changed alternate-skin geometry (2 mm vertex shift), alternate GLB missing its normal texture; unchanged copies accepted | verifier | **pass** (all 8 cases behave as expected) |
| Clean package: copy, open with factory settings (no missing files, libraries or caches), `export_all.py` in the copy reproduces both GLB hashes, clean re-import of each GLB (4 images, no actions, cameras or lights) | package | **pass** |
| Independent full rebuild from scripts in an empty folder (`release.py`, 20 min; `checks/full_rebuild.json`) | 51 delivered files | **pass**: both GLBs, all eight runtime textures and the shared occlusion are byte-identical to the delivered ones |
| `SHA256SUMS.txt --check` | every file | **pass** |
| Master and r3 baseline hashes unchanged | inputs | **pass** |
| Deviation from the master, provisional thresholds | airframe | warning, disposition in §9 |
| Closest views 1080p / 1440p | each skin | evidence, texture magnification noted in §9 |

**Warnings and dispositions:** the deviation exceedance (§9) and the texture magnification at the
closest provisional view (§9). No mandatory check failed.

**Pending integration** (not run here; no Godot environment available): import of every skin in
Godot 4.7.2 with the Compatibility renderer (rest and full-travel poses, materials, texture
format and memory), crash separation in the simulator, skin selection and independent instances,
Home / flight / Workshop views at 1080p with the simulator's cameras, import/load cost and frame
time, review of the camera-door pivots, and regeneration of runtime manifests and sidecar hashes
by the integration team.

**Integrity note.** The zip is the authoritative package. Some file hosts add content-credential
metadata to PNG/JPEG files after upload; that changes their bytes (not their pixels) and makes
`SHA256SUMS.txt` fail for those images. Verify against the files extracted from the zip.

## 11 Known limits and open items

* Pending integration checks: see §10.
* Camera-door pivots are not a supported auxiliary mechanism role; they need integration review.
* Runtime atlas 2048: magnified at the closest provisional inspection view (§9).
* No lamps: lens shapes on bolido are unlit paint; abisal's glow is decorative and always on.
* Render-only effects (abisal iridescence and coat; bolido incandescence, plasma, temper thin
  film) are not in the GLBs, which use core glTF only.
* Wear, dirt and markings are baked per skin: no clean variant or runtime decal layer.
* BÓLIDO tiles use planar projections per zone; they end at closeout lines where zones meet and
  are slightly stretched on the curved nose sides. It is a visual concept, not real thermal
  protection.
* ABISAL: the FPV window interrupts the row of teeth on the nose.
* Servo arms and pushrods are not exported (only the hinge is driven); hinge tape, servo covers
  and orange plastic are painted regions; hidden hardware is excluded (see `export-map.json`).
* `canopy` tags the detachable hatch; the X8 has no glazing.
* Mass and CG values in `metadata.json` are manual values or non-flight estimates.
* No simulator display name yet; asset licence terms not yet set by the owner (`LICENSE.txt`).

## Resumen en español

Revisión r4 del Skywalker X8 de juego con dos skins: `abisal` (por defecto, `export/aircraft.glb`)
y `bolido` (`export/bolido.glb`). La geometría, el rig, los nombres, las secciones, el atlas UV y
la pintura ABISAL son los de r3; el GLB de ABISAL salió idéntico byte a byte. Cambios: la skin
adicional se exporta como `export/<skin_id>.glb`; los lentes de luces de BÓLIDO ya no emiten luz
(el X8 UAV no tiene sistema de luces y el simulador controla ese estado); cada pintura trae capas
editables (base, rótulos, insignia); una sola oclusión compartida; verificación por skin con
paridad completa de posiciones, normales, UV y tangentes; nuevas pruebas de rechazo; comparación
del rig muestreado contra r3; desviación contra el maestro; vistas a 1080p y 1440p; prueba de
paquete limpio; `SHA256SUMS.txt`. Todo pasó; quedan como avisos la desviación de la bahía de servo
(simplificación documentada) y la textura ampliada en la vista de inspección más cercana. La
importación en Godot y las pruebas del simulador quedan pendientes de integración.
