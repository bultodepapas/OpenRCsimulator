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

Magic `FF 80 40 20 10 08 04 02`, then an overwritten BMP header, then 24-bit **BGR** rows stored bottom-up. Pixel data starts one byte before `size − width × height × 3`; this phase was fixed on known liveries (the red Fokker Dr.I replica and the yellow J-3 Cub render red and yellow only with it). Width and height are not recoverable from the header: sides are powers of two, square is preferred, and non-square images (1024×512 observed) are resolved by adjacent-row similarity. The UVs then follow glTF convention unchanged once rows are written top-down. The 4-channel 64×64 thumbnails use a different, unresolved phase and are not converted.

### 3.3 Encoded scripts: `.mod` and `.sim`

Magic `00 01 02 04 08 10 20 40`, then pairs of bytes: logical byte *i* = `(p[2i] + p[2i+1]) mod 256`. The logical stream is a standard **Lua 5.0 binary chunk**: header `1B 4C 75 61 50 01 04 04 04 06 08 09 09 08` and the Lua 5.0 test number `3.14159265358979323846E7`. A stock `.mod` is a straight-line data chunk that assigns `modelTypes.<id> = { … }`; `physics.airplane` and similar values are global references.

The research reader parses the chunk and **abstractly evaluates** only `MOVE`, `LOADK`, `LOADBOOL`, `LOADNIL`, `GETGLOBAL`, `SETGLOBAL`, `GETTABLE`, `SETTABLE`, `NEWTABLE`, `SETLIST(O)`, `UNM`, arithmetic on constants, `CLOSURE` (opaque) and `RETURN`. Unknown globals become symbols; any other opcode stops evaluation with a diagnostic. No Lua runtime, library or model code is executed.

The decoded definition matches the readable community `.mod` grammar already studied ([package research](phoenix-2026-11-17.md)): `attributes.Physical` (`Size`, `Weight` kg, `Centre_of_gravity` in GEO units, Phoenix inertia/tuning factors, fuselage drag areas), `airfoils[]` (position in GEO units; `Length`, chords in metres; NACA label; incidence, dihedral and sweep in degrees; mirrored sides with geometry/collision names; `controlSurfaces[]` with `root_pivot`/`tip_pivot` hinge points in GEO units, input channel and travel in degrees), `propulsion[]` (type, pivot, diameter and pitch in metres, blade count, maximum RPM, spin and blur geometry names), `gear`, `body` collision primitives, `streamers`, `pilots` and `cameras`.

### 3.4 Variants and update packages

`.var` files are plain text: `modelTypes.<id>.<path> = <value>` overrides (for example setup, size and rates for `3D`/`Sport` presets). Update packages reuse the community PKG framing with marker byte `1` and a free-form label (`6.0.i`): `u8 marker`, `u16`-length label, `u16` chunk count, then `(u32 compressed, u32 inflated)` zlib chunks of at most 1,024,000 bytes. The inflated tree uses `u16` child counts, `u8 kind`, `u16`-length names and source paths, `u32` sizes and a `u16` zero child count after each file. About 4.5 MB of the 6.0.i body was not walked by the research listing; that remainder is not needed for aircraft.

## 4. Corpus results

| Check | Result |
| --- | --- |
| GEO parse with exact byte consumption | 220 of 221 files under `objects/`; the refusal is `helicopters/Electric/KDSAgile55/output.geo`, a stray file no definition references |
| Winding versus stored normals | Agreement in every non-degenerate triangle of every accepted file |
| Encoded `.mod` decode + data evaluation | 220 of 220, no diagnostics |
| Encoded 6.0 `.sim` scripts | 64 of 64 parse; 11 are straight-line, the others stop at function calls as intended |
| 3-channel textures | 208 of 220 base-name textures decoded; the remainder use other names declared by GEO materials or 4-channel layouts |
| Visual spot checks (Blender 5.2 renders of converted GLBs) | Easystar, J-3 Cub and Fokker Dr.I: correct geometry, metric span, colour and decal orientation |

Open findings: one J-3 Cub wing half maps into a white texture region (the GLB data and Blender agree, so the conversion is faithful; whether Phoenix tints or substitutes it at runtime is unresolved). Hinge `root_pivot`/`tip_pivot` semantics are clear for elevators and rudders (GEO points on the hinge line). Easystar's zero-length aileron shows that a declared surface can be inactive. Phoenix inertia factors, tuning percentages and NACA labels remain observations and are not OpenRC physical data.

## 5. Public sources and rights

The 2026-11-20 web survey found no public GEO/MOD documentation, converter or importer in other simulators. Phoenix RC (Runtime Games Ltd) is discontinued and community hosts distribute the installer and updates without a published licence grant. Stock content includes licensed manufacturer designs (Horizon Hobby brands among them). Therefore: import only from the player's own installation, keep converted output local to that player's profile, and never bundle or redistribute stock content.

## 6. Reproduce

```bash
python3 research/aircraft-creator/phoenix/inspect_geo.py --corpus "<install>/resources/objects"
python3 research/aircraft-creator/phoenix/inspect_luac.py --corpus "<install>/resources"
python3 research/aircraft-creator/phoenix/inspect_geo.py MODEL.geo --texture MODEL.bmp --glb new.glb --scale 0.01507
python3 research/aircraft-creator/phoenix/inspect_luac.py MODEL.mod
```
