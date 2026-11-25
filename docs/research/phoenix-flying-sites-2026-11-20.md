# Phoenix RC flying sites examined on 2026-11-20

The installed file audit covers 29 stock panoramas, 350 positions and 805 object records. The per-site table gives expected counts for an importer regression run. Separate evidence covers the owner's downloads, an independent club site, one native Airfield camera view and controlled Builder exports. OpenRC flight and contact comparison remain open. [In-game import plan](../plans/phoenix-scenery-import.md) · [Installed file audit](#installed-stock-files) · [Native comparison](#installed-airfield-reference) · [Builder experiment](#controlled-builder-experiment)

## Reproducible source inventory

| Source | Bytes | SHA-256 of complete source | What was inspected |
| --- | ---: | --- | --- |
| `UltimatePhoenixMapPackIII.zip` | 9,573,083,711 | `c13d1de646a7ff2ff826d7f800257ea96c52c1b672f8b34e2a43075d4d3eeee5` | ZIP directory, all PXF descriptor bytes, image signatures, selected members and four embedded packages. The [collection host](https://www.flugsimulatoren.ch/Phoenix-RC.php) lists it as the “274 Map Pack”. |
| `Phoenix_RC_5.5.k.iso` | 3,174,301,696 | `62aeaff23618c7891a3bb96b197a032ab1f53144fd336fb8f3c8a8282b24fc0f` | ISO inventory, all stock PXF descriptors, selected image and InfinityScape entries and the bundled Builder guide. |
| `hmac6.zip` | 58,938,820 | `1a7c91b99cc45b6afdf9d5527a50c42b260f316fba44ba9b7382caeb3e1c0405` | Independent club distribution. Its PXF hash is absent from the map pack. The publisher describes loading its folder through Builder's test sites. [Holdfast Model Aero Club](https://holdfastmac.asn.au/simulators/) |

To reproduce, hash each outer file. Use Python's standard `zipfile.ZipFile.infolist()` for the ZIP directory, including directory records. Compare suffixes case-insensitively, hash the **uncompressed** bytes of each PXF, and read the first 128 bytes of each DDS-named member for the signature census. For the ISO use `7z l -slt` and `7z e -so` on named members. The two local update ZIPs each contain one update PKG (5.5.k → 5.5.l and 5.5.l → 6.0.i). Their presence establishes packaging only. [Earlier update inspection](aircraft-creator/phoenix-stock-format-2026-11-20.md)

### Installed and community content

- The map pack has 4,314 ZIP records and 15,842,971,616 declared uncompressed bytes. Some local headers sit beyond the 32-bit offset range. There are 286 PXF entries in 266 parent directories. Hashing their contents gives 246 distinct descriptors. The ISO has 29 distinct descriptors under `files/#INSTALL/resources/environments/`. It shares 23 of these hashes with the pack, giving **252 distinct PXF descriptors across those two sources**. Sites with identical descriptors can still carry different images, so this is only a descriptor count.
- All 315 PXF entries start with `PHOENIXCREATOR FLYING SITE`. The little-endian word at byte offset 32 takes four values. In order 1, 2, 3, 4, the pack counts are 66, 143, 68, 9 and the ISO counts are 13, 7, 7, 2. These are sampling strata. A version name, record layout and feature set still need independent evidence.
- Of 2,986 DDS-named pack entries, 2,443 begin with standard DDS magic, 433 begin with the four bytes `ff 80 40 20`, and 110 begin with JPEG signatures. Standard headers include DXT1, DXT3, DXT5 and RGB-format fields. The sampled ISO `airfield/medium/airfield1.dds` begins with `ff 80 40 20 10 08 04 02`. A BMP decoder developed for Phoenix aircraft has no demonstrated equivalence here. [Microsoft DDS layout](https://learn.microsoft.com/en-us/windows/win32/direct3ddds/dx-graphics-dds-pguide)
- The pack includes 19 PXQ entries with `PHOENIXCREATOR PROJECT` magic, 13 FLY and 13 MAP entries, seven PXW files, four PXI and four PKG entries. Executables and incidental files are present. The four PKGs all reach `zero padding limit exceeded` in the existing aircraft research reader when `inspect()` receives each uncompressed PKG member. This documents a profile mismatch. Their embedded sites still require an independent closure check. [Reader and research limits](../../research/aircraft-creator/phoenix/README.md)
- Four named PXI defaults are listed under `files/#INSTALL/resources/defaults/InfinityScape sites/`, with matching names in the settings tree. The ISO and pack copies examined of `Default_alps.pxi` are both 580 bytes and share SHA-256 `e2f9c64397b0cb4246a8260380f48cb79527e35d1e439ce553b6c3f27f0e7699`. Their magic is `PHOENIX_INFINITYSCAPE_SITE`. Phoenix describes InfinityScape as a 3D terrain generator. [Spektrum product description](https://my.spektrumrc.com/Products/Default.aspx?ProdID=RTM4000)

### Discriminating examples for implementation

| Case | Observation | What it tests |
| --- | --- | --- |
| Pack `Aero_Club_Dolores_Sub_Comisi_n_Aeromodelismo_Sunset` | PXF of 3,335 bytes, SHA-256 `2fe798b1bad62389ac367e9b98d1116ddb3994edc47b30767f5230e4a7a9da14`. Numbered face references, separate medium/high directories, cubemap and icon. | First community panorama candidate. Prove the roles and orientation of each image before display. |
| Stock and collection `airfield` | ISO PXF is 14,264 bytes, SHA-256 `c8729fe78e7c579321b6fb3ecd138bd7e8c0060799eaac9bc1a6661821e9a51f`. Pack PXF is 276,442 bytes, SHA-256 `63e430468d9e0b23a78d18bd8f8d937814f5822fc9443096b46579c0b8413938`, alongside MAP/FLY and root-level faces. | Same name, different source and dependencies. Import both without cross-wiring them. |
| `Airfield MSC Albatros Nalbach e.V` directory | Two distinct PXF names with their own image families share this directory. | Multiple selectable sites per folder, with correct face ownership. |
| `Aircraft Carrier X98` | 17,056,807-byte PXF with medium faces and an empty high directory. | Large descriptor, tier fallback and unknown records. A name cannot establish moving-deck physics. |
| Holdfast `hmac6` | 2,876-byte PXF, SHA-256 `78d93d07169b57fc301d8aae34cc405fabb8582a318dcdba30b685f828f8ccc5`. Six 2048² DXT1 medium faces. All six high faces measure 5232². Two use DXT5 and four use DXT1. A separate 512² cubemap header has all face flags. | Test a non-power-of-two tier, mixed encodings and independent club packaging. Preserve alpha until its role is established. |

The ISO's `files/#BUILDER/resources/userGuide/UserGuide.rtf` describes aligning a six-panel panorama to a ground plane, setting spawn class and heading, and assigning physical materials. Primitives have independent visibility/occlusion and collision flags. The guide also describes polygonal material areas and extrusions, skylines, height maps, water, lighting, and local weather. Its separate masking-mode tool is marked unimplemented in that guide. Test actual exported flags for each producer. These descriptions establish authoring intent. They do not specify byte offsets or guarantee a feature in any particular site. [Phoenix flying-site manual](https://www.horizonhobby.com/on/demandware.static/Sites-horizon-us-Site/Sites-horizon-master/default/Manuals/RTM3000-Manual_EN.pdf) · [Phoenix Builder site tutorial](https://www.youtube.com/watch?v=X5Ks6XObKao)

For independent visual references, a runway author documents building the cubemap and placing ground, collisions and lighting. Another author report describes releasing a site without collision models. Include both kinds of source expectation in visual and gameplay review. Use generated or explicitly redistributable files in CI. Keep original downloads, derivatives, screenshots and licensing notes with their respective source owners and private evidence as appropriate. [Lutong runway author](https://www.supermotoxl.com/projects-articles/tec-dec-site-models/lutong-abandoned-old-runway-phoenix-r-c-simulator.html) · [Miri high-rise author](https://www.davidxl.com/articles/blog/simple-project-town-high-rise-miri-flying-site-for-phoenix-r-c-simulator.html)

## Installed stock files

This pass read the installed files under `D:\PhoenixRC\resources` and the supporting files under `D:\PhoenixBuilder\resources`. It used the 29 stock PXF descriptors as the development corpus. The results below describe Phoenix RC 5.5.k. The sparse Builder export described later is a different layout. All offsets are zero-based **bytes**, including unaligned offsets. All multi-byte numbers below use little endian.

### Panoramas and position records

| Stock PXF offset | Observation across all 29 descriptors | Import consequence |
| --- | --- | --- |
| 32, 36, 292 | A 32-bit profile word followed by the title at 36 and description at 292. Counts for words 1–4 are 13, 7, 7, 2. | Validate the signature, profile and section boundaries together. The 856-byte word-4 Builder export is a counterexample to a universal stock layout. |
| `553 + 256 × i`, for `i = 0…5` | Six 256-byte slots each contain a NUL-terminated panel filename. All 174 resolve inside the site's `medium/` directory. In the 11 complete high tiers, all 66 files insert literal `#high` before the face digit, e.g. `carpark#high1.dds`. The other 18 sites have zero high panels. | Read through the first NUL within each slot. Resolve the six high candidates together and retain the declared medium set as fallback. `desertMesa.pxf` has a stale `arcticTundra4.dds` at byte 518 in padding. A printable-string search would bind the wrong site. |
| 2089, 2101, 2165 | Three float32 values followed by a 4×4 float32 matrix and a 256-byte cubemap name. All 29 cubemap names resolve locally. Eighteen matrices differ from identity. `quintaDoLargo` has first row approximately `[0.94986, 0, −0.31267, 0]`. | Carry the source matrix and triplet through conversion. Qualify matrix order, shift, heading and the transform to OpenRC using a known pose. |
| 2481, then 2485 | A u32 count and a consecutive array of 92-byte records. Each record has a 64-byte name slot, a u32 at +64 and six finite float32 values at +68. There are 350 records, 8–19 per site. | Store source ordinal, label, raw class and both float triplets. Independently identify pilot eye, vehicle class, units and rotation before using a record for flight. |

Raw position class frequencies are 0 → 115, 1 → 123, 2 → 12, 3 → 32, 5 → 19 and 6 → 49. Every field repeats a position label. Three even repeat a **class and label pair**: Copenhagen Quay repeats `(0, default 3)`, Quinta do Largo repeats `(3, default 1)` and Stockholm Bridge repeats `(1, default 1)`. In Copenhagen Quay, Kambah Field and WHAMS Field the first record has a label other than `default 1`. Boatclub spells one label `windosck`. A source ordinal within a descriptor revision survives all of these cases. An explicit station choice can then bind independently to a verified vehicle start.

### Object records and embedded images

Starting at `2485 + 92 × position_count`, read the u32 object count and advance through exactly that many objects. A private reader walked **805/805 records across all 29 files** using sizes and counts. It checked the type repeated inside every record and landed on the first trailing length word for each file, without searching for the next object name. The count ranges from one in Arctic Tundra and Desert Mesa to 114 in both Lagos Rocks and Stockholm Bridge. Those two 114-record files exercise different layouts.

| Raw tag | Records / sites containing tag | Sampled authoring names and measured payload |
| --- | ---: | --- |
| 0 | 572 / 27 | Primitive. The shape word has four observed values. Named examples associate 0 with plane (21 records with this value), 1 with sphere (165), 2 with cube (238) and 3 with cylinder (148). Dimensions, origin, contact and surface coefficients still require independent fixtures. |
| 1 | 16 / 12 | Grid. All 16 carry dimension 50 and 2,500 entries of 48 bytes. Some are literally named `New height-map`. Stonehenge has two consecutive grids and Eli Field has three grids in total. |
| 2 | 90 / 21 | Area. Each has a subtype, a point count with 12 bytes per point and a second count with 72 bytes per entry. Subtype 2 adds 16 bytes. Both `New wind-area` and `New material-area` occur. Physics and wind have different consumers. |
| 3 | 23 / 2 | Marker-like records in Lagos Rocks and Montebello Castle. Some names include `New marker`. Keep these distinct from the earlier array of 350 positions. |
| 4 | 104 / 26 | Skyline-like records. The variable block has a u32 count followed by entries of 24 bytes. A skyline's geometry alone does not determine whether the aircraft collides with it. |

**Reproducing the walk.** Let `a` be the start of the 64-byte name immediately after the outer u32 tag. Let `d = 1` for header words 1–2 and `0` for words 3–4, and `q = a + 0xf0 - d`. Check the same tag at `a + 0x44 - d`. The following formulas return the offset of the next outer tag or, after the declared count, the trailer. `u(offset)` reads one u32. A production reader must check bounds before every read, multiplication and advance.

| Tag | Next offset for the observed stock profile |
| --- | --- |
| 0 | `a + 0x104 - d`. The shape word is at `q`. |
| 1 | `a + 0x10c - d + 48 × n²`, where `n = u(a + 0x108 - d) = 50` in this corpus. |
| 2 | Set `s = q + 8 + 12 × u(q + 4)`. Advance to `s + 4 + 72 × u(s)`, adding 16 when `u(q) = 2`. The observed subtypes are 0, 1 and 2. |
| 3 | `q`. This tag was observed only under header word 2. |
| 4 | `q + 4 + 24 × u(q)`. |

Preserve arbitrary labels. Kambah contains nonzero bytes after a name's NUL. Car Park has leading spaces and Copenhagen Quay has an empty object name. The controlled word-4 box locates Visible at name +64 and Collidable at +67. With words 1–2, offset +67 starts the repeated u32 tag. Copying that flag offset into the older reader would silently change collision behavior. A successful walk establishes byte boundaries on this corpus. Each tag still needs separate evidence for its physical meaning, transform and flags.

At the calculated end, six files have a zero length and 23 have a length-prefixed **256² BMP**. Eight of the 23 also contain a **2048² BMP**. For those eight, the second length word is 13 bytes past the end of the first declared BMP. All 31 length prefixes agree with the corresponding BMP file sizes. Each has a 40-byte DIB, 54-byte pixel offset, 32 bits/pixel, BI_RGB compression and two extra bytes after the pixel array inside its declared size. All 31 decoded with Pillow. The 2048² RGB image is solid black in Lagos Rocks and solid white in Lakeside. Decode and retain raw channels on demand, charge the declared bytes to the site's resource budget and preserve unclassified tails. The image's role, channel meaning and mapping to world coordinates require an authored differential export.

<details>
<summary>Per-site stock regression counts</summary>

The object column lists raw tags in order 0 / 1 / 2 / 3 / 4. High is the number of matching high-resolution panels. Embedded gives the widths of square BMPs in the descriptor, with zero for none. Each site also has six medium panels.

| PXF stem | Header word | Positions | Objects by tag | High | Embedded |
| --- | ---: | ---: | --- | ---: | --- |
| `airfield` | 3 | 11 | 17 / 0 / 1 / 0 / 3 | 0 | 0 |
| `arcticTundra` | 1 | 10 | 1 / 0 / 0 / 0 / 0 | 0 | 256 |
| `boatclub` | 1 | 14 | 1 / 1 / 9 / 0 / 2 | 0 | 256 + 2048 |
| `carpark` | 3 | 10 | 34 / 0 / 7 / 0 / 3 | 6 | 256 |
| `copenhagenQuay` | 1 | 19 | 34 / 0 / 7 / 0 / 12 | 6 | 256 + 2048 |
| `countrysideHill` | 4 | 14 | 18 / 1 / 1 / 0 / 1 | 6 | 0 |
| `desertMesa` | 1 | 10 | 1 / 0 / 0 / 0 / 0 | 0 | 256 |
| `eliField` | 3 | 12 | 55 / 3 / 6 / 0 / 10 | 6 | 256 |
| `farmland` | 1 | 10 | 1 / 0 / 0 / 0 / 1 | 0 | 256 |
| `flyingField` | 3 | 12 | 1 / 0 / 1 / 0 / 3 | 6 | 0 |
| `freedomPark-winter` | 1 | 11 | 3 / 0 / 1 / 0 / 3 | 0 | 256 |
| `kambahField` | 2 | 12 | 47 / 0 / 1 / 0 / 12 | 0 | 256 |
| `lagosRocks` | 2 | 8 | 94 / 1 / 9 / 9 / 1 | 6 | 256 + 2048 |
| `lakeside` | 1 | 18 | 7 / 1 / 2 / 0 / 4 | 0 | 256 + 2048 |
| `montebelloCastle` | 2 | 14 | 62 / 1 / 2 / 14 / 0 | 6 | 256 |
| `monteFarno` | 4 | 15 | 4 / 1 / 2 / 0 / 2 | 0 | 0 |
| `moscowRcClub_planes` | 1 | 10 | 29 / 0 / 1 / 0 / 12 | 6 | 256 |
| `nightflight` | 1 | 10 | 1 / 0 / 0 / 0 / 1 | 0 | 256 |
| `oldesloe` | 2 | 10 | 1 / 0 / 5 / 0 / 2 | 0 | 256 |
| `playingField` | 1 | 11 | 1 / 0 / 0 / 0 / 4 | 0 | 256 |
| `quintaDoLargo` | 3 | 14 | 33 / 2 / 7 / 0 / 5 | 0 | 256 + 2048 |
| `sandbar` | 1 | 17 | 0 / 1 / 1 / 0 / 1 | 0 | 256 + 2048 |
| `sandflats` | 2 | 14 | 0 / 1 / 4 / 0 / 4 | 0 | 256 + 2048 |
| `seaside` | 3 | 10 | 1 / 0 / 0 / 0 / 1 | 0 | 0 |
| `sportsHall` | 2 | 9 | 8 / 0 / 0 / 0 / 1 | 6 | 256 |
| `stockholmBridge` | 2 | 14 | 86 / 0 / 21 / 0 / 7 | 6 | 256 + 2048 |
| `stonehenge` | 1 | 10 | 3 / 2 / 0 / 0 / 3 | 0 | 256 |
| `stonehengeNear` | 1 | 11 | 21 / 1 / 1 / 0 / 3 | 0 | 256 |
| `whamsField` | 3 | 10 | 8 / 0 / 1 / 0 / 3 | 6 | 0 |

</details>

### Masking, water and 3D presets

- **Cubemap alpha.** For each PXF, decode all six faces of its named cubemap and histogram alpha over those faces. Eighteen sites have texels both below 230 and at or above 230 on an 8-bit scale. The other eleven are entirely 255. Airfield has 773,766 texels below that cutoff and 799,098 above or at it. The installed `effects/mask_area.fx` pixel shader thresholds the sampled cube alpha at 0.9. It also transforms and shifts its sampling direction. Preserve alpha and validate registration with an asymmetric mask. Pixel counts alone do not determine where Phoenix activates this shader or what geometry receives the mask.
- **Colour and orientation.** As a check on automatic calibration, downsample the six medium panels and six cube faces to 48² RGB, crop two pixels per edge, centre each channel and normalize. Compare all eight square symmetries and maximize the sum of correlations under a one-to-one assignment. Only 6/174 assignments reached both correlation ≥0.90 and margin ≥0.05 over the next orientation or panel. This test cannot supply a general face order. Use a labelled cube for axes and the earlier Airfield photograph for one real direction.
- **Panoramic water.** `effects/water_pano_high.fx` samples cube RGB for reflections, noise for the surface normal and a separate 2D map's red channel for opacity. Separate `water_3d_*.fx` files serve the 3D path. Builder's `shaders/mask_copy.fx` and `cubemap_combine.fx` also select individual texture channels. Preserve these image roles separately. Water height, a BMP-to-shader binding and buoyancy need independent evidence.
- **InfinityScape.** The four installed `defaults/InfinityScape sites/*.pxi` are each 580 bytes. They share the magic `PHOENIX_INFINITYSCAPE_SITE`, a title at 0x24 and a description at 0x124. A 32-byte tail at 0x224 can be read as three u32 and five float32 values. The second u32 is 0 in both Highlands presets, 1 in Alps and 2 in Desert. This correlation leaves generator and biome semantics unresolved. The word at 0x1c is 12 in `Highlands_with_lakes.pxi` despite the 20-byte title. Bound the title at its first NUL. None of the four contains a literal BMP, GEO or PXW reference.
- **Terrain dependencies.** The installed `effects/terrain_near.fx` takes current and next heights and interpolates them by LOD. `geometry/environment/` includes strips and foliage meshes. All 20 terrain, two foliage and 15 skybox BMP-named textures under `textures/` decoded as BMPs after the measured eight-byte-marker / 1,000-byte-tail reconstruction. Builder's 18 BMP textures start with ordinary BMP magic. Each of the three stock skybox sets has five numbered BMPs and a separate cubemap. These files establish texture availability and the renderer's height inputs. Reconstructing terrain needs an independently matched height generator, runway placement and ground queries.
- **Weather, sound and recordings.** All six `environments/weatherSetups/*.pxw` are text presets with the same 11 assignments, including distinct base and gust directions, speeds, randomness, gust frequency, turbulence, and thermal strength/duration. All six direction pairs are `{0,0,1}` and all thermal values are zero. Strong wind has base/gust values 14.910358 / 6.779774. Units, axes and gust law remain open. The only WAV within the installed environments tree, `flyingField/ambient_birds.wav`, is byte-identical to `soundEffects/ambient/ambient_birds.wav`. Its binding remains unverified. The shipped airplane tutorial recordings for taxi/takeoff and landing both contain `Flying Field` at byte 596. The Sports Hall and Countryside Hill demos likewise contain those site names. These give future reference cases for site behavior. Flight trajectories were outside this file audit.

The private receipts under `U:\openrc-tmp\phoenix-stock-audit-96cbba10\` include per-PXF SHA-256, all five tag counts, object-table end offsets, resolved panel names and embedded image widths in `stock-audit.json` (SHA-256 `a7a97950a1130ac95ad16d12f0ceafdec3441fbbe93fb64c512ed4ef93364a68`). `cubemaps.json` contains the per-site alpha and correlation results (SHA-256 `efb6024a5208eef20330069cfc82a0b9169a35841cffa7d81878c28131a8db08`). The table and formulas above allow the stock inventory to be repeated from the installation.

## Installed Airfield reference

On Windows, `D:\PhoenixRC\PhoenixRC.ver`, the launcher and the running simulator all reported **5.5.k**. The Builder version file and its window both reported **1.0.p**. Windows listed 5.5.g in the uninstall record, so discovery should prefer the selected installation's own version file and the actual asset signatures. The Windows Documents known folder was redirected on this machine. Resolve it via the OS for Builder test sites and user downloads.

**Native view.** Launch Phoenix, select Spanish, retain the initial graphics and metric defaults, skip transmitter calibration, and choose **Airfield** from the Start tiles. The title identified Airfield and the Pitts Special. Minimize the missing-USB panel. The view shows the paved strip curving away at left, trees behind it, and hangars at right. The interface reported no recognized USB, so this run supplies landscape imagery. Aircraft motion, eye height in metres, spawn heading, material changes and collision response remain unmeasured.

The private evidence directory on this host is `U:\openrc-tmp\phoenix-installed-airfield-mgVrk2\`. Its `airfield-pilot-window.jpg` is the 1514 × 1141 **window** capture including title bar and side tabs, SHA-256 `a640810cc2ae5c8fa2ee2ba932966a0750f0a6be39eb05e4dcdec8e6892b0779`. It is a camera reference at the observed framing. Capture FOV and drawable size separately for a future quantitative OpenRC comparison.

**Image correspondence.** Decode the six installed medium faces, convert them to grayscale and area-resize them to 1024². Compare each with the grayscale window image using OpenCV 5.0.0 SIFT (5,000-feature cap), restricting screenshot features to `x=[40,1470), y=[100,1040)`. Use L2 two-nearest-neighbour matching with a 0.72 ratio and a 3-pixel RANSAC homography. In filename order, with RNG seed 21, **face 4 gave 158 inliers from 184 matches**, spanning 1,351 × 511 window pixels, with 0.35 px median residual on the fitted inliers. The other faces had at most five inliers or too few pairs to fit. This identifies a source face for the native view. All-face orientation, absolute compass bearing and OpenRC rendering parity require separate checks.

**Source identity.** Airfield's nine installed files (PXF, cubemap, icon and six medium panels) match their ISO members by SHA-256. The high directory is empty. The six medium DXT1 payloads match the six collection Airfield panels byte for byte after wrapper removal. Five have differing DDS header bytes. The collection PXF and cubemap differ from the installation, and its icon has a different resolution. Deduplicate identical texture content while keeping each descriptor, its asset roles and the selected site revision together.

**Observed stock texture layout.** All 326 DDS-named files under the installed `resources/environments/` have the eight-byte marker `ff 80 40 20 10 08 04 02` and the DDS header 1,000 bytes before EOF. Admission checks the marker, header, dimensions, pixel format, surface count and total block length before allocation. The installed six Airfield panels use 2048² DXT1. The icon is 64² and the cubemap has six 512² faces. The corrected recipe below restores both the header and the displaced pixels. [Corrected panel decode](#corrected-panel-decode-during-l-px-implementation)

**Historical format inventory.** Pillow accepted **326/326 files and 506/506 image surfaces** using the initial header-only reconstruction. It counted 246 DXT1 files, three DXT5, one DXT3 and 76 uncompressed 32-bit files, including 290 single surfaces and 36 complete six-face cubemaps. The private `installed-textures.json` receipt, SHA-256 `11c49a67805e58a68cf41ac76a82c6e32f4f48daf46e9246f5940ac9f3f73236`, recorded structurally decodable but displaced pixels. Use the receipt for the file and format census. Use the corrected recipe for images and acceptance comparisons.

### Corrected panel decode during L-PX implementation

Moving the header to the front makes the DDS readable, but leaves a cyclic displacement in its pixel payload. The first seven checked 2048² DXT1 panels each had their largest column discontinuity at x = 1548, exactly 500 pixels or 1,000 BC1 bytes from the right edge. For a wrapped file `b` in this profile, take the 128-byte DDS header at `b[-1000:-872]`, the 1,000 bytes at `b[-2000:-1000]`, the final 872 bytes at `b[-872:]` and the middle at `b[8:-2000]`, in that order. Normal DDS keeps its declared layout.

**Open finding, 2026-11-25 (not applied).** The wrapper is format-independent: `signature + file[2000:] + file[1000:2000] + file[0:1000]`, as for stock aircraft BMPs ([aircraft texture layout](aircraft-creator/phoenix-stock-format-2026-11-20.md#32-textures)). The exact rebuild is therefore `b[-1000:] + b[-2000:-1000] + b[8:-2000]`. The recipe above places `b[-2000:-1000]` before `b[-872:]`, which misorders the first 1,872 pixel bytes: a strip of blocks along the top edge of each panel. On 60 installed environment DDS files, the mean absolute row difference in the first eight rows exceeded the interior's by a median of 0.68 with the current order (maximum 11.1), and by −0.03 with the exact rebuild (maximum 0.88). The x = 1548 seam evidence above is unaffected. Applying the fix changes the decoded faces. `calibrations.json` binds each calibration to the SHA-256 of those faces, and installed previews keep their stored faces under an unchanged preview id. The decoder change therefore needs recomputed calibration face hashes and a library migration in the same change. Otherwise calibrated sites lose their flight calibration. The earlier image hashes and cube-to-panel correlation scores were measured before this correction and should not be used for decoder acceptance or orientation. The decoded file and surface counts still describe the size and format inventory.

The corrected medium panels of all 29 installed sites match the lateral joins 1 right to 2 left, 2 right to 3 left, 3 right to 4 left, and 4 right to 1 left. The polar topology is consistent in the independently compared sites. Match the top edges of 1–4 with bottom, reversed right, reversed top and left of 5. Match the bottom edges of 1–4 with top, right, reversed bottom and reversed left of 6. The installed Builder guide lists editor directions +X, +Z, −X, −Z, +Y and −Y. The preview uses relative bearings. Physical pose, shift, yaw and source-to-NED coordinates still need independent calibration. [Preview projection](../../app/ui/phoenix_panorama.gdshader)

An offline Pillow preview of the 29 corrected medium sets sampled 128 texels along each join after reducing panels to 1024². The largest mean error among any pair of edges was 0.221 (normalized RGB absolute error), and the largest mean over any site's twelve edges was 0.075. These values guide the in-game seam check. A set outside the preview threshold remains available as six source panels. The check does not establish absolute orientation or flight geometry.

The corrected Airfield face 4 yielded 163 inliers from 184 feature matches against the earlier native window image, with at most five inliers on the other five faces. The ordinary DDS medium sets for the independently packaged Holdfast site and the Aero Club Dolores entry also follow the same panel topology without the stock file transformation. At 600² their largest normalized join errors were 0.099 and 0.024 respectively.

### Importer checks

| Evidence | Scope | Result |
| --- | --- | --- |
| `px-home-integrated-20261120`, job `ed9e6da8970b46acb71dca1b4a12040f` | Full OpenRC checkout on Apple Silicon, before the ZIP64 integration | 21 checks passed including the Home button, selection, preview, install, deduplication and damaged-entry recovery. |
| `px-verified-final-20261120` | Isolated browser and production readers on Apple Silicon | 20 browser and library checks passed, along with generated DDS/JPEG fixtures and a sparse ZIP64 read at byte 4,294,967,553. |
| `px-final-candidate-20261120`, job `c9a1c2f0667445ff9d472391bacd38b2` | Intel UHD 630, Compatibility renderer on Linux | 26 checks passed, including the rendered centre of all six authored directions. This is a functional rendering check. |

The original 9.57 GB map archive has 4,314 directory entries and 2,273 local headers above the 32-bit offset limit. Independent Python checks verified the local headers and CRC of `mccool/mccool.pxf` at byte 4,702,137,464 and its six medium faces. The ZIP64 engine test used generated data. Opening this original collection in a Windows OpenRC session remains a separate qualification step.

### Live scenery acceptance

- **Airfield on Intel UHD 630.** The production browser rendered actual stock Airfield at 1920×1080 from a ZIP containing the installed PXF and six medium DDS faces. The first capture exposed a clipped modal footer during the first preview. Keeping the source actions in one row and limiting the status to two lines held the loaded dialog at 960×690, centered at (480, 195). The repeat rendered both directions, installed one revision, moved the input archive out of the test path, and reopened the panorama from the installed library. The reopened panorama pixels matched the source preview at the same bearing. Run `phoenix-stock-layout-20261120`, job `3a246d8468504723afb9f0858732daab`. Captures are retained outside the repository.
- **Actual ZIP64 directory and one selected site, Apple Silicon.** A sparse fixture kept the original 9,573,083,711-byte logical length, central directory and offsets. The original bytes of the McCool Memorial descriptor and its six medium members occupied their original offsets above 4 GiB. OpenRC indexed 290 descriptor rows and prepared that site's 360° preview. Other member payloads were omitted from the fixture. Run `phoenix-mccool-zip64-20261120`, job `656df1b7fbfe4ac0b770bf027546036f`.
- **Mouse and compact viewport.** The repeated Airfield graphics check changed the panorama bearing through drag input and kept the reopened dialog within a 1280×720 window. The three 1920×1080 captures use the production browser after the layout correction. Run `phoenix-stock-interaction-20261120`, job `1f56231559474cba8f2f0de7f4e32c37`.
- **Full app and stock flight, Apple M1.** The real Home screen opened the importer and installed Airfield. After closing the browser, the app started the Ugly Stick in the air at Club Field. The bridge applied 0.10 roll for 0.8 s. Between ticks 4100 and 5492 the model moved 109.6 m horizontally in 5.8 simulation seconds, ending at 27.9 m altitude, 19.6 m/s and 8.9° of bank. It was still airborne at tick 5520 and returned to Home normally. The fixture used the GDScript reference backend and Mobile/Metal. The window captures are 1920×1018. The app loaded the installed Airfield preview with its source ZIP outside the selected path after flight and again after process restart. Putting Import scenery on its own row resolved the split Home labels observed in the first capture. One direct shutdown with the modal open logged four leaked ObjectDB instances. A repeat that closed the dialog after opening the preview exited with zero.

### Downloads compatibility sample

The extracted `UltimatePhoenixMapPackIII` contains 286 PXF descriptors. The matching 9.57 GB ZIP64 directory exposes 290 rows, including four PXI descriptors. The selection below covers 14 distinct PXF files. The verified folder run used the original bytes extracted from selected ZIP members. The ZIP64 run used the original central directory, logical size and selected local records at their original offsets.

| Scenario | Case | Result |
| --- | --- | --- |
| Aero Club Dolores | Standard DXT1 | 360° preview from folder. Installed and reopened with identical pixels on all six faces. |
| Aircraft Carrier X98 | 17,056,807-byte descriptor, 3072² faces | 360° preview from folder. The rendered preview shows the sky and sea panorama. |
| Airfield MSC Albatros Nalbach and Litermonthalle HQ V2 | Two descriptors in one directory | Both opened in 360° with distinct preview IDs. |
| AKMG Gothenburg and Frönäs | Six JPEG faces with DDS filenames | Both opened in 360°. The Frönäs name displayed with its original characters. |
| Airfield and Sports Hall | Panels beside the descriptor, including Phoenix-wrapped DXT1 | Both opened in 360°. |
| Samu | Five 2048² DXT1 faces and one 2024² JPEG face | All six faces resized to 1024² and formed a 360° preview. |
| Farmland | Five wrapped DXT1 faces and one wrapped 2048² RGB24 face | 360° from folder and ZIP64 with the same preview ID. Installed and reopened with identical pixels on all six faces. |
| Pipis | 4096² faces in `high/`. Descriptor at byte 7,192,926,208 in ZIP64 | 360° from folder. The first compressed face exceeded the ZIP decompression work limit. |
| AppleValleyFlyers | 6048² faces | The first compressed face exceeded the ZIP decompression work limit. Its dimensions also exceed the decoder's current 33,554,432-pixel ceiling. |
| ASRCM-HD | 8192² faces, 33,554,560 bytes each | The ZIP index rejected the first face before reading its payload. Each face exceeds the 32 MiB member limit by 128 bytes. |
| Tansawan sibling `tansawan2.pxf` | Descriptor outside the directory containing its six references | The importer reported an incomplete face set from folder and ZIP64. |

Farmland's fifth face established the need for packed 24-bit BGR support. The decoder now checks its masks, row stride and exact payload size. Generated image checks passed alongside the real six-face test. The folder sample produced 11 panoramas from 12 selections on Apple Silicon. The targeted ZIP64 run indexed all 290 rows and reopened Farmland. It failed the expectation that Pipis would also open directly from the archive. A separate reader check confirmed the exact decompression and member-size limits above. The initial 14-site ZIP64 batch reached its 320-second test timeout without a complete result.

The folder run is `phoenix-downloads-folders-rerun-20261120`, job `3f405d27c2e94891972a3f8e1931b553`. The ZIP64 sample is `phoenix-downloads-fixed-rerun-20261120`, job `60bb704dfeaf4edcbb524753545ef172`. The reader diagnostics are `phoenix-downloads-diagnostics-20261120`, job `94a6d8fcdaf04058ab29954ba59425ab`. Aircraft Carrier X98, Frönäs and Farmland were rendered through the production browser on Apple M1 at 1920 × 1080. Captures are in `U:/openrc-tmp/phoenix-live-test-20261120/downloads/`. These tests cover imported previews. Flight geometry, collision and spawn validation for imported scenery remain open.

### Rendered taxi and takeoff with manually calibrated ground

An isolated OpenRC checkout on Apple M1 reopened the production import library's six-face assets for each source in the table. A test landscape adapter projected those same faces around the fixed pilot eye and supplied an estimated field definition. The production fixed-wing scene, Ugly Stick, wheel contacts, ground-start solver and GDScript reference flight backend ran at 240 ticks/s. The harness drove the normal stick input seam and captured the live viewport at 1920 × 1080. The simulated aircraft used its actual state for every frame.

| Imported site | Contact profile | Contact and flight evidence |
| --- | --- | --- |
| Airfield, collection variant | Estimated dry asphalt on the visible paved strip | Three wheels supported the aircraft at 9.21 m/s during the roll. The last supported track sample was tick 879, with one wheel and 18.76 m/s. Tick 885 had zero wheels and 18.98 m/s. At tick 975 the center of gravity was 0.854 m up after 30.03 m of net horizontal travel. At tick 1232 it reached 9.65 m up and 24.60° of left bank. |
| Frönäs | OpenRC maintained-turf coefficients in a manually placed grass lane | Three wheels at 2.23 m/s in taxi. Zero wheels at tick 1095 with 0.821 m clearance. The aircraft climbed to 9.65 m and banked 24.05° left. |
| Farmland | Same turf coefficients. The six installed faces include the restored RGB24 sky face. | Three wheels at 2.22 m/s in taxi. Zero wheels at tick 1095 with 0.825 m clearance. The aircraft climbed to 9.66 m and banked 24.12° left. |
| Aero Club Dolores | Same estimated grass contact patch as Farmland | The aircraft repeated the same contact and flight results with the Dolores panorama. The sunset photograph limits the visibility of the grass and shadow. |
| Aircraft Carrier X98 | Estimated paved contact along the runway seen on the imported deck | Three wheels at 9.21 m/s in the takeoff roll. The first sample after the final wheel contact was tick 885, after 22.39 m of displacement at 18.99 m/s. At tick 975 the center of gravity was 0.859 m above the runway datum. At tick 1232 it was 9.69 m above that datum with 24.70° of left bank. |

The first Airfield attempt placed the projected shadow on the photographed grass near the point of lift-off. The corrected run moved the test lane 7 m west and 2.5 m south in the fixture coordinates. Its takeoff-roll frame shows the wheels and shadow on the photographed pavement. The airborne frame shows a gap from the wheels to the shadow on that same surface. The first unsupported sample came after 22.38 m. The heading changed by about 5.6° before the airborne capture with neutral rudder. A 0.35-second left aileron input followed by neutral produced the measured left bank. The same turf contact model explains the nearly identical grass results.

For X98, the source faces show the deck in directions 1–3 and 6. The descriptor also has a `deck` area with a raw Y translation of −200. The fixture used a 2 m estimated eye height above the deck and fit its centerline to the pictured runway. A rudder controller held the aircraft within 0.119 m of its initial lateral position during sampled wheel contact. All sampled support lay inside the test corridor. The aircraft passed the photographed bow airborne. Hull and water contact remain outside that test.

Private captures and telemetry are retained at `U:/openrc-tmp/phoenix-flight-qa-20261120/`. The initial four-site run is `phoenix-final-flight-p_wbodrf`, with 16 captures and zero failed checks. The corrected Airfield run is `airfield-aligned-7u38po_5`. The X98 run is `carrier-final-8_2181qx`. Both repeats retained five captures and sampled contact telemetry with zero failed checks. Field settings and viewpoints are experimental calibration data. The tests cover taxi, rotation and initial climb. L-PX-03 still requires source-matched ground, obstacle contacts, photo occlusion, landing and a normal Home flight entry.

### Calibrated runway in the production importer

The normal Home importer now offers a runway start for five exact revisions: the map-pack Airfield, Aircraft Carrier X98, Frönäs, Farmland and Aero Club Dolores. Each profile binds the descriptor and source faces through the import revision hash and verifies the six installed PNG hashes before launch. It supplies the yaw, fixed pilot viewpoint, runway start and an estimated ground surface. Files without a recipe can still open in the 360° preview. The dry paved profiles use a 2.25 rolling-resistance multiplier calibrated to achieve stable Ugly Stick ground starts at idle. The contact parameters and dimensions are estimates. Dolores uses a grass lane without a painted centreline. The X98 test covers the deck lane. The estimated field continues as a flat ground plane beyond the visible deck, with water, the hull and photo occlusion unmodelled. [Calibration recipes](../../app/landscapes/phoenix/calibrations.json) · [Ground-start regression](../../app/tests/test_phoenix_flight_calibrations.gd)

The final ground-start regression settled the Ugly Stick on each of the five profiles and checked fixed-eye camera limits and refusal of damaged assets. A macOS headless run reopened installed Airfield through the production Home controls, started flight and reset to the same position and heading (90.017° in the local frame). The flight accumulated no solver faults or crashes before reset. The engine log showed no errors, and the session exited with zero leaked objects. The browser regression passed 24 checks. The earlier staged flight captures above document visual alignment and actual takeoff in all five panoramas. They used estimated test fields before this production integration and the revised pavement coefficients.

#### Windows 1080p sample

One managed Windows session used an RTX 3090, OpenGL Compatibility, the High preset, 120 Hz VSync, a 1920 × 1080 drawable, and 100% internal 3D resolution. Both comparisons used the same Ugly Stick, pilot camera, calm air and native physics. The aircraft sat on the runway with the simulation active. The follow-up sample used the real imported Farmland revision from Home and recorded the last 720 frames of the takeoff and climb run. The frame times are engine process intervals. Each row is a single short run.

| Scenario and phase | Mean FPS | 1% low FPS | p95 frame time | p99 frame time | Frames over 17.17 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Club Field, on runway | 96.0 | 45.2 | 16.20 ms | 20.78 ms | 31 |
| Farmland, on runway | 110.1 | 49.9 | 13.20 ms | 15.47 ms | 5 |
| Farmland, takeoff and climb | 119.7 | 76.1 | 9.02 ms | 9.65 ms | 1 |

On Farmland the aircraft moved 9.1 m along the grass lane by the rolling sample at 12.37 m/s. After elevator input, it climbed through 6.57 m above the field datum at 24.53 m/s. The capture shows the airplane separated from the grass in the climb. The follow-up frame window had no stalls of 50 ms or longer, and the final flight sample at 61.58 m reported no crash or solver fault. The test ended airborne. Windows artifacts for managed ticket `T-7e1efbb97b1f4d13827cce4c87613216` are retained under `U:/openrc-tmp/phoenix-flight-product-20261120/windows/`. The Windows snapshot preceded the Airfield asphalt adjustment and the deferred Home launch signal. Farmland's runway and renderer were identical to the final candidate. Source-matched terrain, landing and performance across the other imported fields remain open.

## Controlled Builder experiment

Builder 1.0.p saves a **SITX** project through **File → New → Site → Save As**. The baseline began with a length-prefixed `CAvSiteProject_header`, and measured 1,574,498 bytes before a box was added. The community PXQ files above begin with `PHOENIXCREATOR PROJECT`. Builder's installed guide describes **File → Import** for older 3.0/4.0 PXF sites, **Test** for a local site export and **Publish** for building a PKG. Only Save and Test were exercised here.

Create `OpenRCProbe.sitx`, add one collision box, keep its transform and Short grass material fixed, and toggle Visible or Collidable in its properties. Run **File → Test** on each variant. All three exports are 856 bytes with PXF header word 4 at offset 32. The name `New Box` begins at byte 565. Compare complete files, using zero-based offsets.

| Visible | Collidable | Export SHA-256 | Change relative to both enabled |
| --- | --- | --- | --- |
| Yes | Yes | `82b5a7200178c20149adb7c77d35a2104262bae0afabe11d3f2d4ec1a20ca89f` | Reference |
| Yes | No | `7067d7344a7a24654052a5b485e6cb24ec64e2820e713b4de966c79e6ca1bd0c` | Byte 632 changes from 1 to 0 |
| No | Yes | `b01f5cd9819995f4cdd21e87d627d97d47e309d4c06eafb0181b0b51101d5163` | Byte 629 changes from 1 to 0 |

The two equal-length SITX snapshots with Collidable enabled/disabled also differ in one byte, at 1,574,976. These absolute offsets identify the saved fixtures. For a parser, move the box by inserting an earlier object and predict both values from the object's record boundary in an unseen export. Repeat with another primitive before generalizing.

**Negative gameplay fixture.** These exports deliberately had no light or airplane start. Builder reported both conditions, including that an airplane start named `default 1` must be away from `(0,0,0)`. It subsequently reported export success and wrote a PXF and icon to its test-site folder. The test fixture therefore exercises discovery, flags and refusal of **Fly**. A separately authored complete site is needed for flight. Copies of the three exports and project snapshots are retained alongside the private Airfield capture, outside the repository.
