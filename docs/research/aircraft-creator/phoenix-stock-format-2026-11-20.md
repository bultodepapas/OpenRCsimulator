# Phoenix RC stock-install formats: GEO, textures and encoded MOD

Dated evidence, 2026-11-20. Owner direction for this round: Phoenix RC is discontinued and the owner authorized decoding the stock formats so a player can import aircraft from **their own local installation**. This file records the measured formats and corpus results. Stock geometry, textures and decoded definitions are third-party content: none of them is committed, and the importer reads them only from the player's selected installation. The [AC-PX plan](../../plans/phoenix-aircraft-import.md) owns status and acceptance.

## 1. Sources

| Source | Identity | Use |
| --- | --- | --- |
| `Phoenix_RC_5.5.k.iso` (owner download) | 3,174,301,696 bytes; 2,762 files | Stock install tree `files/#INSTALL/resources/objects/aircraft/<class>/<subclass>/<model>/` |
| `PhoenixRC_5.5.l_to_6.0.i_update.pkg` | 61,308,403 bytes, package label `6.0.i` | 6.0 scripts (`airplane.sim`, `physics.sim`, …); no new aircraft |
| `PhoenixRC_5.5.k_to_5.5.l_update.pkg` | 2,443,282 bytes | Small update; same container |

Public research found no format documentation, converter or official licence statement for these files ([web survey](#5-public-sources-and-rights)). Everything below was derived from the bytes and checked against the whole stock corpus.

## 2. Stock model folder

Each model folder holds `<model>.geo` (geometry), `<model>.mod` (encoded definition), one or more textures named by the GEO materials, `<model>_preview.bmp` (64×64 thumbnail) and optional plain-text `<model>_<variant>.var` overrides. The stock tree contains 220 model definitions: 109 airplanes, 7 gliders, 96 helicopters and 8 multirotors. A metadata-only [census](phoenix-stock-census-2026-11-20.json) lists every model, its class, size, mass, surfaces, propulsion and decoder outcome.

## 3. Formats

### 3.1 GEO geometry (`openrc-phoenix-geo-observed-v1`)

Little-endian and **unaligned**. Strings are fixed 28-byte fields written from `c_str()`: bytes after the terminating NUL are writer heap residue; a name of 28 or more characters overflows into the following 28-byte field (observed: `__helper_hinge_leftWheelFlap1`).

| Part | Layout |
| --- | --- |
| Header | `u32 version=1`, `u32 node_count`, `u32 unresolved`, `u32 triangle_count`, `u8 flag`, `f32[6] bbox` |
| Materials | `u32 count`; each 716 bytes: name @0, `u32 has_texture` @128, texture name @132, `f32[3] diffuse` @680, `f32[3]` @692, `f32[3]` @704; the rest unresolved |
| Vertices | `u32 count = 3 × triangle_count`; 52 bytes each: `f32[3] position`, `f32[3] normal`, `f32[2] uv`, 8 unresolved bytes, 8 zero bytes, `u32 colour` (`0xFFFFFFFF`) |
| Nodes | `u32 count = node_count`; each: name @0 (+overflow), 2 unresolved floats @124, `f32[6] bbox` @132, `f32[16] matrix` @156, `u32 sub_count` @220, then `sub_count` × 74-byte sub-meshes, then `u32` |
| Sub-mesh | `f32[6] bbox`, `u32 material` (`0xFFFFFFFF` = none), `u32`, `u32`, `u16`, `u32` writer pointer, `f32[6] bbox`, `u32 first_vertex`, `u32 end_vertex` |

The geometry is one unindexed triangle list. Sub-mesh ranges are contiguous and end at the vertex count. Node matrices are identity in the corpus: vertices are already in model space. Node names carry roles: `__col*` collision proxies, other `__*` helpers (empty hinge/mass helpers included), the rest visual parts named after the aircraft parts (`left_aileron`, `elevator`, `rudder`, `propBlades`, …).

**Frame and units.** GEO space equals glTF: +X left, +Y up, +Z forward; triangles are counter-clockwise and agree with the stored normals in every checked triangle. Visual span is normalized to about 100 units. The definition's `Physical.Size` sets the metric scale: metres per unit = `Size / 100`. The Easystar check: GEO span 101.56 units × 1.507/100 = 1.531 m, equal to twice its main-wing `Length` (2 × 0.7656 m).

### 3.2 Textures

Magic `FF 80 40 20 10 08 04 02`, then an overwritten BMP header, then 24-bit **BGR** rows stored bottom-up. Pixel data starts one byte before `size − width × height × 3`; this phase was fixed on known liveries (the red Fokker Dr.I replica and the yellow J-3 Cub render red and yellow only with it). Width and height are not recoverable from the header: sides are powers of two, square is preferred, and non-square images (1024×512 observed) are resolved by adjacent-row similarity. The UVs then follow glTF convention unchanged once rows are written top-down. Four-channel files are **BGRA** starting two bytes before `size − width × height × 4`: shared glass (`glass_001`, white with alpha ≈ 0.1; `smokedGlass_001`, dark with alpha ≈ 0.76), rotor discs (mostly transparent) and the red Fokker thumbnail decode consistently. Their horizontal registration is verified only on these uniform or thumbnail cases, so the importer reduces small alpha textures (≤ 64 × 64) to their average colour. Shared textures live in `resources/textures/aircraft/` and `resources/textures/misc/`; stock folders also hold `<model>#<Scheme>.bmp` paint schemes.

### 3.3 Encoded scripts: `.mod` and `.sim`

Magic `00 01 02 04 08 10 20 40`, then pairs of bytes: logical byte *i* = `(p[2i] + p[2i+1]) mod 256`. The logical stream is a standard **Lua 5.0 binary chunk**: header `1B 4C 75 61 50 01 04 04 04 06 08 09 09 08` and the Lua 5.0 test number `3.14159265358979323846E7`. A stock `.mod` is a straight-line data chunk that assigns `modelTypes.<id> = { … }`; `physics.airplane` and similar values are global references.

The research reader parses the chunk and **abstractly evaluates** only `MOVE`, `LOADK`, `LOADBOOL`, `LOADNIL`, `GETGLOBAL`, `SETGLOBAL`, `GETTABLE`, `SETTABLE`, `NEWTABLE`, `SETLIST(O)`, `UNM`, arithmetic on constants, `CLOSURE` (opaque) and `RETURN`. Unknown globals become symbols; any other opcode stops evaluation with a diagnostic. No Lua runtime, library or model code is executed.

The decoded definition matches the readable community `.mod` grammar already studied ([package research](phoenix-2026-11-17.md)): `attributes.Physical` (`Size`, `Weight` kg, `Centre_of_gravity` in GEO units, Phoenix inertia/tuning factors, fuselage drag areas), `airfoils[]` (position in GEO units; `Length`, chords in metres; NACA label; incidence, dihedral and sweep in degrees; mirrored sides with geometry/collision names; `controlSurfaces[]` with `root_pivot`/`tip_pivot` hinge points in GEO units, input channel and travel in degrees), `propulsion[]` (type, pivot, diameter and pitch in metres, blade count, maximum RPM, spin and blur geometry names; `turbine` entries, used for jets and ducted fans, carry `Max_Thrust` in newtons, `Idle_Thrust`, `Spool_Time` and fan RPM instead), `gear`, `body` collision primitives, `streamers`, `pilots` and `cameras`.

### 3.4 Variants and update packages

`.var` files are plain text: `modelTypes.<id>.<path> = <value>` overrides (for example setup, size and rates for `3D`/`Sport` presets). Update packages reuse the community PKG framing with marker byte `1` and a free-form label (`6.0.i`): `u8 marker`, `u16`-length label, `u16` chunk count, then `(u32 compressed, u32 inflated)` zlib chunks of at most 1,024,000 bytes. The inflated tree uses `u16` child counts, `u8 kind`, `u16`-length names and source paths, `u32` sizes and a `u16` zero child count after each file. About 4.5 MB of the 6.0.i body was not walked by the research listing; that remainder is not needed for aircraft.

### 3.5 Flight-model data

The 6.0 scripts in `resources/` define how Phoenix flies these numbers. `physics.sim` sets `air_density = 1.225`, `airfoil_efficiency = 0.85` and `num_airfoil_sections = 20`; `functions.sim` (`calcAifoilForces`) applies strip theory over those sections with tabulated section polars. The polars are `resources/airfoils/*.sim`: each names one airfoil (matching the definition's `Airfoil` label) and holds flat `[alpha°, CL, CD]` triples from −90° to 90° in 0.5° steps. `Fuselage_drag_area.frontal` is a projected area in m² (multiplied by a drag coefficient), not a CD·S product. Engine `.pxe` files are sound definitions only. Creator turns these facts into its own packages (see [§4](#4-corpus-results)); it executes no Phoenix script.

### 3.6 Field meanings from Phoenix Builder

The owner's Phoenix Builder 1.0.p install (`D:\PhoenixBuilder`, user guide `resources/userGuide/UserGuide.rtf`, February 2014) documents what each definition field means. It was read locally; nothing from it is committed. Census values are from the owner's Phoenix 5.5.k install (`D:\PhoenixRC`, the same 220 stock definitions as the ISO corpus).

| Field | Builder meaning | Stock use |
| --- | --- | --- |
| `Physical.Size`, `Weight` | Geometry scale (wingspan, or rotor diameter for helicopters); total flying weight | 220 |
| `Physical.Fuselage_drag_area` | Frontal, lateral and vertical drag areas (the Builder's "Set" measures them from the mesh) | 220; only frontal is used by Creator |
| `Physical.Cockpit` | Cockpit shown in cockpit view (Helicopter, Jet_Fighter, Modern, WW2_Fighter, Glider, None) | 220 |
| `Fine_tuning` | Percent multipliers on thrust, lift, engine power and elevator/aileron/rudder power, plus stall, wash, torque and rudder-roll/rudder-elevator coupling | Non-default on 212 models: lift 49 (75–175 %), elevator/aileron 25 (75–130 %), engine 22, thrust 12, wash 15, couplings 125 |
| `Controls.*` | Low-rate %, expo (normal/low), servo speed, dead-zone, mixes | 212 |
| Airfoil `Wash` | Propeller-wash influence on the airfoil and its surfaces | 456 airfoils, 0–150 % |
| Airfoil `flaps[]` | Hinged flap: travel, lift and drag increase, leading-edge flag | 19 models |
| Airfoil `airbrakes[]` | Drag increase and lift reduction at full extension | 1 glider |
| Propeller | Idle/Max RPM, `Down_thrust`/`Right_thrust` angles (0–8° / −0.5–0°), torque %, spool `Response`, spin direction, pusher flag, engine sound | 110 propellers |
| Turbine | Idle/max RPM, idle/max thrust, spool time | 10 |
| Gear | Hinge axis, guide (steerable) wheel with direction and travel, breakable, retract time and idle/mid/full poses, wheels (centre, radius, thickness) | 97 fixed-wing |
| Main/tail rotor | Diameter, chord, blades, inertia, min/mid/max pitch, cyclic response, damping, flybar type and gains, governor, engine power and gear ratio, ground effect, vortex-ring loss; tail drive type, pitch range, gyro type/gain | 96 helicopters |
| Exhaust, widget, pilot, streamer | Smoke (engine/display, colour), animated covers driven by an input, pilot figure, streamer anchor | see the census in the [quality plan](../../plans/imported-aircraft-quality.md#81-what-the-stock-models-carry) |
| Scheme project | Replacement textures for a model (`<model>#<Scheme>.bmp`); `<model>_preview.bmp` is the menu preview | 36 schemes, 220 previews |

Engine sounds are plain-text `.pxe` definitions in `resources/engines/` mapping throttle percent to volume and pitch curves over WAV samples in `resources/soundEffects/` (100 WAV files).

## 4. Corpus results

| Check | Result |
| --- | --- |
| GEO parse with exact byte consumption | 220 of 221 files under `objects/`; the refusal is `helicopters/Electric/KDSAgile55/output.geo`, a stray file no definition references |
| Winding versus stored normals | Agreement in every non-degenerate triangle of every accepted file |
| Encoded `.mod` decode + data evaluation | 220 of 220, no diagnostics |
| Encoded 6.0 `.sim` scripts | 64 of 64 parse; 11 are straight-line, the others stop at function calls as intended |
| 3-channel textures | 208 of 220 base-name textures decoded; the remainder use other names declared by GEO materials or 4-channel layouts |
| `Size / 100` scale rule | GEO visual span × `Size`/100 versus 2 × main-wing `Length` on 116 airplanes/gliders: median ratio 1.046, 95 within ±10 %; outliers are deltas, jets, biplanes and rotor/tiltrotor oddities where the widest mirrored airfoil is not the visual span |
| GDScript runtime readers (`app/workshop/creator/phoenix/`) | 220/220 definitions and GEO files decoded; 220/220 models converted and admitted by `SourceImporter.inspect_bytes` |
| Derived flight packages (`phoenix/physics.gd`, local install, 2026-11-20) | 114/114 aeroplanes and gliders yield a physics block; 110 compile after "Set up for flight", 105 have an airborne start and 21 a hand launch |
| Visual spot checks (Blender 5.2 renders of converted GLBs) | Easystar, J-3 Cub and Fokker Dr.I: correct geometry, metric span, colour and decal orientation |

Open findings: one J-3 Cub wing half maps into a white texture region (the GLB data and Blender agree, so the conversion is faithful; whether Phoenix tints or substitutes it at runtime is unresolved). Hinge `root_pivot`/`tip_pivot` semantics are clear for elevators and rudders (GEO points on the hinge line). Easystar's zero-length aileron shows that a declared surface can be inactive. Phoenix inertia factors and tuning percentages remain observations and are not OpenRC physical data. Weight, centre of gravity, airfoil labels (which select the installation's polars), surface geometry, propellers and turbine thrust feed Creator's derived packages ([decision](../../DECISIONS.md#phoenix-aeroplanes-fly-on-packages-derived-from-their-own-data)).

## 5. Public sources and rights

The 2026-11-20 web survey found no public GEO/MOD documentation, converter or importer in other simulators. Phoenix RC (Runtime Games Ltd) is discontinued and community hosts distribute the installer and updates without a published licence grant. Stock content includes licensed manufacturer designs (Horizon Hobby brands among them). Therefore: import only from the player's own installation, keep converted output local to that player's profile, and never bundle or redistribute stock content.

## 6. Reproduce

```bash
python3 research/aircraft-creator/phoenix/inspect_geo.py --corpus "<install>/resources/objects"
python3 research/aircraft-creator/phoenix/inspect_luac.py --corpus "<install>/resources"
python3 research/aircraft-creator/phoenix/inspect_geo.py MODEL.geo --texture MODEL.bmp --glb new.glb --scale 0.01507
python3 research/aircraft-creator/phoenix/inspect_luac.py MODEL.mod
```
