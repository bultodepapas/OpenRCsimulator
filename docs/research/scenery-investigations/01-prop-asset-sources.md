# 01 · Prop asset sources for the club field (SC-06…SC-15)

Date: **2026-10-07**. Track: [SCENERY-PLAN](../../SCENERY-PLAN.md) (SC-), step SC-01(b) input. **Status: research only. Nothing was added to the repo or `app/`.**

**Question:** which downloadable 3D assets fit a compact club field (shelters, pavilion, cars, pit props, people, fences) and its countryside (bales, farmstead, animals, turbines, pylons, church)? Which licenses are proven, and which art family fits next to the L6a Quaternius MegaKit trees?

**Evidence tags:** **[V-page]** read on the live page on 2026-10-07 · **[V-archive]** read inside the downloaded archive (scratch only: `/tmp/claude-1000/scenery-research/`, never in the repo) · **[V-drive]** read in the author's public Google Drive folder · **[meas]** measured here from the GLB/glTF/OBJ (indexed triangles, materials, bounding box) · **[U]** not verified · **[est]** estimate.

## Summary and recommendation

**Primary family: Quaternius "classic" flat-colour packs (2018–2020 CC0 releases), re-palettised into one scenery atlas, plus MegaKit textures for vegetation, plus our own simple meshes in the same palette for the gaps.** It is the same author as the L6a trees. Its cars have near-real metric proportions (4.22 × 1.81 m [meas]). Its models use a few named flat materials and no textures, so glTF Transform `palette()` (see [04](04-godot-techniques-and-prior-art.md)) collapses them to one material and they can be re-tinted to the moderate palette. It covers cars (SC-06), posed spectators (SC-10), fences and hedges (SC-11), the farmstead (SC-13) and farm animals (SC-14). **First fallback: Kenney.** CC0 is proven inside every archive checked, every model has one material, and it has the widest coverage, but the proportions are toy-like (sedan L/W 1.70 vs ≈ 2.5 real [meas]/[est]), so use it only for small pit props and far-away silhouettes. **Second fallback: KayKit City Builder Bits** (CC0 in the archive, one 1024² atlas, but few relevant items). Poly Haven is CC0 but photoreal: reference only. **Create ourselves:** pit shelters, the white pavilion, round and square bales, pit tables, folding chairs, coolers, stands, the flagpole, a post-and-wire fence, continuous hedgerows, wind turbines, pylons and a simple church. These are simple shapes whose real dimensions matter more than detail. **License caveat:** quaternius.com now publishes QAL v1.0 site-wide, so every Quaternius file needs CC0 evidence for that exact download (see Risks).

## License landscape (what was checked)

| Source | Finding | Tag |
| --- | --- | --- |
| Kenney | Every archive checked has `License.txt`: "License: (Creative Commons Zero, CC0)". The 16 kits checked are listed under Evidence | [V-archive] |
| KayKit | City Builder Bits `License.txt`: "License: (Creative Commons Zero, CC0)". Furniture Bits page: "Creative Commons Zero v1.0 Universal". EXTRA/SOURCE tiers are paid and not CC0-free content | [V-archive], [V-page] |
| Quaternius site | `license.html` = **Quaternius Asset License (QAL) v1.0**, effective 8/28/2026. §3: "You may not resell or redistribute the Assets themselves as standalone products." §7: changes "will not apply retroactively to Assets you've already obtained" | [V-page] |
| Quaternius pack pages | The old packs still show "License CC0" with a link to the CC0 deed: Farm Buildings, Farm Animal, Cars, Background Posed Humans, Ultimate Animated Animals, Ultimate Crops, Survival, Ultimate Modular Men/Women | [V-page] |
| Poly Pizza | The license is per model (the `Licence` field). Quaternius, Isa/Kay Lousberg and iPoly3D uploads say "CC0 1.0". All "Poly by Google" uploads say **"CC-BY 3.0"** | [V-page] |
| Poly Haven | "Our assets are all licensed as CC0" | [V-page] |

## SC-06 · Cars, van, pickup

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **Quaternius "Realistic Car Pack – Nov 2018"** (NormalCar1/2, SUV, SportsCar 1/2, Taxi, Cop) | https://quaternius.itch.io/lowpoly-cars (upload 1148381) | CC0: `License.txt` inside the archive ("CC0 1.0 Universal") [V-archive] | FBX, OBJ, Blend | 6–8 flat materials, no textures [meas] | **Best SC-06 fit.** NormalCar1 4.22 × 1.81 × 1.18 m, SUV 4.21 × 2.11 × 1.53 m [meas]; 2954–3294 tris [meas] | Muted colours in the preview. Car height runs about 20 % low against a typical sedan's ≈ 1.45 m [est]: check in SC-04. No van and no pickup |
| Quaternius Pickup Truck | https://poly.pizza/m/qn4grQgHm8 | Poly Pizza "CC0 1.0" [V-page] | GLB | 3 materials, `Zombie_Atlas.png` [meas] | SC-06 pickup | 6432 tris [meas] (the page says 4160). The atlas suggests the newer Zombie Apocalypse Kit: check that pack's license when downloading |
| Kenney Car Kit 3.1 (sedan, suv, van, truck-flat = pickup, hatchback-sports, tractor, delivery) | https://kenney.nl/assets/car-kit | CC0 in the archive [V-archive] | GLB, FBX, OBJ | 1 material, 512² `colormap.png` [meas] | Fallback, and the **only van** found in CC0 | Toy proportions: sedan 2.55 × 1.50 × 1.30 units [meas]. Wheels are separate nodes. About 2.0–2.6 k tris per vehicle [meas] |
| KayKit City Builder Bits (car_sedan, hatchback, stationwagon, taxi, police) | https://kaylousberg.itch.io/city-builder-bits (upload 8567487) | CC0 in the archive [V-archive] | glTF, FBX, OBJ | One 1024² `citybits_texture.png` shared by the whole pack [meas] | Second fallback | ≈ 1.2–1.3 k tris; sedan 0.94 × 0.42 × 0.34 units (toy) [meas] |
| Poly by Google vans (aT_24cDaW1a, akcsFuPMt3b) | https://poly.pizza/m/aT_24cDaW1a | **CC-BY 3.0** [V-page] | GLB | per model | Van, if attribution is accepted | 1946 / 5434 tris (page) |

## SC-07 · Pit shelters, pit furniture and small props

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Quaternius Gas Can (×2) | https://poly.pizza/m/eS1OXGo51c, https://poly.pizza/m/jRymgnHTTb | Poly Pizza "CC0 1.0" [V-page] | GLB | 3 flat materials (Red, DarkRed, Black) [meas] | SC-07 fuel cans | 632 / 788 tris |
| Kenney Survival Kit (barrel, box, bucket, signpost, workbench, structure-metal-roof) | https://kenney.nl/assets/survival-kit | CC0 in the archive [V-archive] | GLB, FBX, OBJ | 1 material, 512² colormap [meas] | Small props; the roof piece is too small and toy-like for a 30 m shelter | barrel 412, box 124, bucket 68, signpost 44, metal roof 456 tris [meas] |
| Kenney Car Kit `cone`, `box` | https://kenney.nl/assets/car-kit | CC0 in the archive [V-archive] | GLB | colormap | Cones, field boxes | 172 / 124 tris [meas] |
| Kenney Furniture Kit (bench, table, tableCross, chair) | https://kenney.nl/assets/furniture-kit | CC0 in the archive [V-archive] | GLB, FBX, OBJ, DAE | 1–3 flat materials, **no texture** [meas] | Fallback pit tables and benches | 120–178 tris. Indoor styling |
| Quaternius Bench | https://poly.pizza/m/jLxjFxFRpw | Poly Pizza "CC0 1.0" [V-page] | GLB | 1 flat material | Benches | 376 tris [meas]. Rustic style |
| KayKit Furniture Bits | https://kaylousberg.itch.io/furniture-bits | CC0 [V-page] | glTF, FBX, OBJ | One 1024² gradient atlas [V-page] | Weak: indoor only | Not downloaded |
| Coolers by S. Paul Michael; Folding Table | https://poly.pizza/m/2sX5RyEluoW, https://poly.pizza/m/96Vhd1riedz | **CC-BY 3.0** [V-page] | GLB | per model | Coolers, pit table | Coolers 3360 tris: too heavy. Creating them is simpler |
| Poly by Google Canopy | https://poly.pizza/m/40tUFNg2fu4 | **CC-BY 3.0** [V-page] | GLB | per model | Event-day 3 × 3 m canopy | 384 tris |
| Kenney Racing Kit (`grandStandCovered`, `pitsGarage`) | https://kenney.nl/assets/racing-kit | CC0 in the archive [V-archive] | GLB, FBX, OBJ | flat materials plus a banner texture | Not a fit (motorsport look) | 168 / 96 tris [meas] |

**No open-sided long pit shelter with a light metal roof exists in any of these sources: create it** (posts, a roof sheet and bench tables, at the 25–35 m measured from the photo).

## SC-08 · Pavilion, shed, flagpole, sign

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Quaternius Farm Buildings `SmallBarn`, `ChickenCoop` | see SC-13 | see SC-13 | FBX, OBJ, Blend | flat materials | Shed by the van, after re-tinting | 2176 / 948 tris [meas] |
| CreativeTrio Cabin Shed | https://poly.pizza/m/HTx7PZt6Zm | Poly Pizza "CC0 1.0" [V-page] | GLB | `Diffuse_palette_2.jpg` palette [meas, sibling models] | Shed (log cabin, weaker) | 2745 tris (page) |
| Quaternius Flag | https://poly.pizza/m/FuOkF3WBrx | Poly Pizza "CC0 1.0" [V-page] | GLB | 2 flat materials [meas] | Flag reference | 216 tris [meas]. Low pole; SC-18 needs our own flag mesh anyway |
| Quaternius Arrow Sign | https://poly.pizza/m/dwmvPHHCdq | Poly Pizza "CC0 1.0" [V-page] | GLB | 2 flat materials [meas] | Club sign stand-in | 120 tris [meas] |
| Quaternius Gazebo; Storage Sheds | https://poly.pizza/m/xYZB1TmGMv, https://poly.pizza/m/JrFL3mLOKg | Poly Pizza "CC0 1.0" [V-page] | GLB | flat | **Not a fit** (medieval wooden style) | — |
| Poly by Google Gazebos | https://poly.pizza/m/0cRW-BhHD16 | **CC-BY 3.0** [V-page] | GLB | per model | Not a fit (round garden gazebo) | — |

**No small white hipped-roof pavilion was found: create it** (a box, a hip roof and an open or half-open front; ≤ 8 k tris is easy).

## SC-10 · People (static)

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **Quaternius Background Posed Humans** (28 models) | https://quaternius.com/packs/backgroundposedhumans.html | Page: "License CC0" [V-page]. `License.txt` exists in the Drive folder (dated 7/23/18) but could not be read: Drive "Quota exceeded" [U] | FBX, OBJ, Blend [V-drive] | flat (assumed from the pack family) [U] | **Best SC-10 fit**: poses `LookingUp`, `Sitting`, `Sitting_Cheering`, `Standing`, `Standing_Hips`, `Standing_Waving`, `Walking`, male and female, plus 4 hairstyles each [V-drive] | Static poses, so there is nothing to rig. Tris not measured |
| Quaternius Man / Woman Casual | https://poly.pizza/m/HMnuH5geEG, https://poly.pizza/m/jpKRgGDxhk | Poly Pizza "CC0 1.0" [V-page] | GLB (skinned, 11 animations) | 6 flat materials [meas] | Fallback; bake a pose in Blender | 1852 tris [meas] |
| Kenney Mini Characters (12 characters) | https://kenney.nl/assets/mini-characters | CC0 in the archive [V-archive] | GLB, FBX, OBJ (skinned, 32 animations) | 1 material, colormap [meas] | **Style clash** (chibi, big heads) | 723–742 tris [meas] |
| Kenney Animated Characters (Protagonists) | https://kenney.nl/assets/animated-characters-protagonists | CC0 in the archive [V-archive] | FBX only, skin textures | per skin | Weak | 4 FBX files |
| Quaternius Universal Base Characters | https://quaternius.itch.io/universal-base-characters | itch: "(CC0 License)" and "Creative Commons Zero v1.0 Universal" [V-page]; the site says QAL | — | — | Later, for SC-21 animation | New pack: highest QAL risk |

## SC-11 · Fences and hedges

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Quaternius Farm Buildings `Fence`, `Fence2` (wood rail) | see SC-13; also https://poly.pizza/m/e02PFKKhbr | see SC-13; Poly Pizza "CC0 1.0" [V-page] | OBJ, FBX, Blend; GLB via Poly Pizza | 1 material (Brown) [meas] | Paddock and boundary rail fence | `Fence` 188 tris, 5.89 m × 1.10 m [meas] |
| **MegaKit `Bush_Common`** (+ `_Flowers`) | https://quaternius.itch.io/stylized-nature-megakit | CC0: `License_Standard.txt` in archive SHA `298f6732…` ([L6a provenance](../tree-resource-review-2026-10-06/README.md)) [V-archive] | glTF | Leaf texture + vertex colour [meas] | Hedge look that matches the trees | 900 / 1368 tris [meas]. Better: our own continuous hedgerow mesh using the MegaKit leaf texture |
| Quaternius Hedge | https://poly.pizza/m/df8uCl1YpK | Poly Pizza "CC0 1.0" [V-page] | GLB | `Leaf_Texture.png` [meas] | Hedge segment | 956 tris [meas] |
| Quaternius Metal Fence (chain-link) | https://poly.pizza/m/qWKhREFj7H | Poly Pizza "CC0 1.0" [V-page] | GLB | `Fence.png` texture, probably alpha [U] | Car-park fence | 218 tris [meas]. Alpha texture: check against the Compatibility alpha limits |
| Kenney Nature Kit `fence_simple`, `fence_gate`; Kenney City Kit Suburban `fence*` | https://kenney.nl/assets/nature-kit | CC0 in the archive [V-archive] | GLB, FBX, OBJ, DAE | Nature: flat materials, no texture; Suburban: colormap [meas] | Farm gate fallback | 64 / 88 tris [meas] |
| Isa Lousberg Hedge Straight (Long) | https://poly.pizza/m/0ffeaITgEG | Poly Pizza "CC0 1.0" [V-page] | GLB | — | Blobby, cartoon style | — |

**The post-and-wire boundary fence: create it.** At 1280 × 720 and a 50° vertical FOV a 4 mm wire is about 3.1/d px wide, so 0.3 px at 10 m: only the posts read. Make it posts plus at most one line.

## SC-12 · Hay meadow

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Quaternius Hay | https://poly.pizza/m/Yu8TOERkpw | Poly Pizza "CC0 1.0" [V-page] | GLB | flat | **Not a fit**: an upright sheaf, not a bale | 488 tris |
| Styloo "Cozy Farm" (`haystackround`, `haystackcube`) | https://styloo.itch.io/farm | itch "Asset license: Creative Commons Zero v1.0 Universal" [V-page] | glb, fbx [V-page] | textured (PSX/retro) | Style clash | Not downloaded |
| Mish7913 Hay Bale | https://opengameart.org/content/cc0-models-by-mish7913 | Page says CC0 [V-page] | — | — | Unknown shape | Not downloaded |
| Poly by Google Haystack | https://poly.pizza/m/6LeCqyw00RK | **CC-BY 3.0** [V-page] | GLB | — | No | 414 tris |

**Round bales (1.2 m) and square-bale stacks: create them.** A 16–24-sided cylinder with an end texture or vertex tint is under 100 tris and has an exact size.

## SC-13 · Farmstead

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **Quaternius Farm Buildings** (13: Barn, BigBarn, SmallBarn, OpenBarn, Silo, Silo_House, ChickenCoop, WaterTower, Windmill, TowerWindmill, Well, Fence, Fence2) | https://quaternius.itch.io/lowpoly-farm-buildings (upload 1125896); GLBs on Poly Pizza (e.g. https://poly.pizza/m/vSqQNA7ez6) | itch description: "CC0 License https://creativecommons.org/publicdomain/zero/1.0/" [V-page]; quaternius.com page "License CC0" [V-page]; Poly Pizza "CC0 1.0" [V-page]. **The itch archive has no license file** [V-archive]. A Drive `License.txt` (9/25/18) exists but was quota-blocked [U] | FBX, OBJ, Blend; GLB via Poly Pizza | 1–7 flat materials (DarkRed, LightRed, White, RoofBlack…) [meas] | **Best SC-13 fit** (classic red barn and silo) | Barn 2910, BigBarn 4224, Silo 1592, SmallBarn 2176 tris [meas]; Barn 8.2 × 7.7 × 6.0 units [meas]. Re-tint the reds to a muted barn red |
| CreativeTrio Barn / Cottage | https://poly.pizza/m/A6UkPq33aZ, https://poly.pizza/m/YDGLLT0emC | Poly Pizza "CC0 1.0" [V-page] | GLB | **one material plus a palette JPG**, `Diffuse_palette_2.jpg`, shared by Church, Cottage and Barn [meas] | Farmhouse (half-timbered cottage) | 3007 / 2094 tris [meas]. The source pack was not identified |
| Kenney City Kit Suburban (21 houses) | https://kenney.nl/assets/city-kit-suburban | CC0 in the archive [V-archive] | GLB, FBX, OBJ | colormap + `variation-a/b/c` textures [V-archive] | Farmhouse or village fallback | ≈ 1.1 k tris [meas]. Green roofs by default |
| Kenney Car Kit `tractor` | https://kenney.nl/assets/car-kit | CC0 in the archive [V-archive] | GLB | colormap | Tractor at 400–900 m, where its proportions do not show | 2044 tris [meas] |
| Poly by Google Tractor | https://poly.pizza/m/5TGoA5N14c5 | **CC-BY 3.0** [V-page] | GLB | — | Alternative | 2766 tris |
| Poly Pizza Silos (MaverickFX) | https://poly.pizza/m/Po3KCFJo6f | Poly Pizza "CC0 1.0" [V-page] | GLB | — | Alternative silo | 1242 tris (page) |

## SC-14 · Animals

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| **Quaternius Farm Animals Pack** (Cow, Sheep, Horse, Pig, Llama, Pug, Zebra) | https://quaternius.com/packs/farmanimal.html; the same models on https://quaternius.itch.io/lowpoly-animated-animals (upload 1126158) and Poly Pizza (https://poly.pizza/m/5XSc2Fka3F, https://poly.pizza/m/C39AUXUUes) | **CC0: the Drive `License.txt` was read** ("Farm Animals Pack by Quaternius … CC0 1.0 Universal") [V-drive], SHA `551ec32f…`; itch "Asset license: Creative Commons Zero v1.0 Universal" [V-page]; the itch archive has no license file [V-archive] | FBX, OBJ, Blend; GLB (skinned) via Poly Pizza | 2–3 flat materials [meas] | **Best SC-14 fit** | Cow 796, Sheep 612, Horse 690, Pig 562 tris [meas]. The OBJ scale is arbitrary (Cow 9.17 units long [meas]): normalize in SC-04. Static: bake one pose |
| Kenney Cube Pets (cow, pig, chick…) | https://kenney.nl/assets/cube-pets | CC0 in the archive [V-archive] | GLB, FBX, OBJ | colormap | Style clash (cubic) | — |
| Poly by Google Cows and Sheep | https://poly.pizza/m/0OToIgkcVM7 | **CC-BY 3.0** [V-page] | GLB | — | Alternative | — |

## SC-15 · Horizon landmarks

| Asset | URL | License (how verified) | Format | Palette / atlas | Fit / step | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Kenney City Kit Industrial `windmill` (a 3-blade wind turbine) | https://kenney.nl/assets/city-kit-industrial | CC0 in the archive [V-archive] | GLB, FBX, OBJ | colormap | Placeholder turbine; **a separate `blades` node** suits SC-18 | 456 tris; 0.60 × 2.31 × 1.13 units [meas]. The rotor is small for its height compared with real turbines (rotor Ø ≈ hub height) [est] |
| Poly by Google / Colin Hopkins wind turbines | https://poly.pizza/m/8Tke6WIyZtg, https://poly.pizza/m/3JKnKecvdMI | **CC-BY 3.0** [V-page] | GLB | — | Alternative | 342–584 tris |
| iPoly3D Transmission Tower (×3) | https://poly.pizza/m/Xfb0lAPvnh, https://poly.pizza/m/WZhSdczNJW, https://poly.pizza/m/TYK3rPu7E5 | Poly Pizza "CC0 1.0" [V-page] | GLB | 1 material [meas] | Pylon reference | 2504–5743 tris. Thin lattice members become sub-pixel and shimmer at kilometre range |
| CreativeTrio Church | https://poly.pizza/m/GHzPfvoyzX | Poly Pizza "CC0 1.0" [V-page] | GLB | palette JPG [meas] | Church steeple, white with a dark roof | 2265 tris [meas] |
| Poly by Google Churches | https://poly.pizza/m/0Oe72PEPCK6 | **CC-BY 3.0** [V-page] | GLB | — | Alternative | 760–4014 tris |
| Kenney City Kit Suburban | (above) | CC0 [V-archive] | GLB | colormap | Village houses at 2–3 km | — |

**Recommendation for SC-15: create.** A turbine with a real proportion (for example a hub height near 80 m and a rotor of about 90 m [est], one landmark ≤ 1.5° wide), a solid-silhouette pylon and a nave-plus-steeple church each take a few hundred tris and get exact sizes. Use the assets above only as shape references.

## Poly Haven (photoreal, CC0)

The model list (521 entries, `api.polyhaven.com/assets?t=models` [V-page]) has `painted_wooden_bench` (630 tris), `outdoor_table_chair_set_01` (9828), `metal_jerrycan` (20 022), `WoodenTable_01` (952) and `modular_electricity_poles` (200 610). Each model has its own PBR texture set: style clash, extra surfaces and draw calls. **Reference only.**

## Merging and atlas notes

- **Kenney:** one material per model, but **each kit has its own 512² colormap** (7 kits, 7 different SHA-256 [meas]). The swatches are vertical gradients, not flat cells [V-archive], so merging across kits means repacking the maps into one atlas and offsetting UVs, not baking vertex colours. Furniture and Nature kits use flat named materials and no texture.
- **Quaternius classic:** 1–8 flat named materials per model and no textures [meas]. `palette()` turns them into one palette texture, and re-tinting is a table edit.
- **MegaKit and Quaternius Hedge:** real leaf textures plus vertex colour. Keep them in the vegetation atlas, not in the prop palette.
- **KayKit:** one 1024² atlas per pack; packs do not share one.
- **Skinned GLBs** (Poly Pizza Cow, Sheep, Man; Kenney Mini Characters): bake a static pose before merging.

## Gaps: create ourselves

| Item | Step | Why |
| --- | --- | --- |
| Long open-sided pit shelter (25–35 m, metal roof, bench tables) | SC-07 | Nothing found |
| Pit tables, folding chairs, coolers, airplane stands, field boxes | SC-07 | Only CC-BY or heavy (coolers 3360 tris) or indoor-styled; boxes under 200 tris with exact sizes |
| Pop-up canopy 3 × 3 m | SC-07 extra | Only CC-BY |
| White hipped-roof pavilion; flagpole with a flag mesh | SC-08 | Nothing found; SC-18 needs our own flag topology |
| Post-and-wire fence; continuous hedgerow (MegaKit leaf texture) | SC-11 | Wire is sub-pixel; segments repeat visibly |
| Round bale 1.2 m and square-bale stacks | SC-12 | No CC0 round bale in a fitting style |
| Van (if not Kenney) | SC-06 | Only Kenney (toy) or CC-BY |
| Wind turbine, pylon, church silhouettes | SC-15 | Exact proportions; few tris; SC-18 rotor |

## Not verified / risks

1. **Quaternius QAL.** The site license is QAL v1.0 (effective 2026-08-28). §3 forbids redistributing "the Assets themselves", which a public repo committing source GLBs could arguably do. Use a Quaternius file only with CC0 evidence for that exact download, and record the SHA-256 of the archive and of the license text or page snapshot in `PROVENANCE.json`.
2. **Missing license files.** The Farm Buildings and Animated Animals itch archives contain no license file. The evidence is the itch page, the quaternius.com page and the Poly Pizza labels. The Drive `License.txt` files for Farm Buildings, Cars, Background Posed Humans and Ultimate Animated Animals were quota-blocked: **retry** them (Farm Animals was read).
3. **Background Posed Humans** was not downloaded: formats and poses come from the Drive listing, the license from the page only. Tris and materials are unknown.
4. **Pickup Truck** (Poly Pizza) uses `Zombie_Atlas.png`, probably from a newer Quaternius kit: check that kit's license. Its triangle count is 6432 measured, not the 4160 the page says.
5. **Poly Pizza labels are uploader claims.** Poly Pizza `Tris` fields can differ from the file.
6. **Not searched in depth:** Sketchfab CC0, OpenGameArt (one page read), and itch beyond the farm packs. Automata Workshop "Lowpoly Farm" has a contradictory license (description CC0, metadata CC-BY 4.0): avoid it. xra7en Farm Pack is CC-BY 4.0.
7. **Scale:** OBJ units vary between Quaternius packs (cars metric, animals not). SC-04 must normalize to catalog sizes.
8. Style judgements come from author previews and Poly Pizza thumbnails, not from Godot renders next to the L6a trees. The SC-01 bake-off decides.

## Evidence (scratch only, not committed)

| Archive | Upload / URL | SHA-256 | Bytes |
| --- | --- | --- | --- |
| Quaternius LowPoly Cars | itch 1148381 | `af8f45d6e2135cc53870e5d0882cc41ca329bd87b9923b4773d471f161d2bdc7` | 2 774 430 |
| Quaternius LowPoly Farm Buildings | itch 1125896 | `12b3a6ad979895585f6b576e5aa90310afdc4247c3ccf8d1836bcb3a59865e97` | 3 569 351 |
| Quaternius LowPoly Animated Animals | itch 1126158 | `b4bc5f209368cafc21962934e7d676cf1cfb1f746a363086cd9f45c4385db70e` | 6 963 285 |
| Quaternius Farm Animals `License.txt` | Drive file `1tOEbeiWqvuTIfFzyZTe92NUdGNAZSOHL` | `551ec32f604f57be7eca26fc6e6331b3c6d765804726ac259bc7891276634353` | — |
| KayKit City Builder Bits 1.0 | itch 8567487 | `aff444e1d083ddac331be94ea4a7590e5604ef49715ae23df71cd2e9659bd33f` | 4 881 740 |
| Kenney Car Kit 3.1 | kenney.nl | `fac7dacac5c7874348cf19729af3ef205f3d366493edaf0a827d93f4fdf3d0c4` | 4 814 237 |
| Kenney City Kit Suburban 2.0 | kenney.nl | `5869c35cf30b1c87bdb2d197b6d325eebadd2ef08ea27f04797e8e08d77a9a39` | 3 038 740 |
| Kenney City Kit Industrial 2.0 | kenney.nl | `5b381164e5760f3830a2dbee43b972deee38b2a695d091b56e238ab2910c96d2` | 5 045 077 |
| Kenney Survival Kit 2.0 | kenney.nl | `c3586341b5932c87eb43d75d915434f47daed168b17ed36a03e8ca9977c7443e` | 1 948 174 |
| Kenney Furniture Kit 1.0 | kenney.nl | `e67652d0932cee41683f74711c03d3e192a2af9979ef8e6b237711f5482d46b0` | 5 130 729 |
| Kenney Nature Kit | kenney.nl | `fa7974a0d342bfe63c38664ba9f8ec1a4aab8ea25f099bdc56870e33588c4d9d` | 10 537 521 |
| Kenney Mini Characters | kenney.nl | `9e1d48e6d7b8479ebbe84df71eb5bd8e1b3f0da546dea641890dccc8a02d0999` | 2 403 059 |
| Kenney Fantasy Town Kit 2.0 | kenney.nl | `1a7530c09f4d2fa2cdee259876f089334f8b1f27fa86a0c4f54ef86cdd8676ef` | 3 854 691 |
| Kenney Racing Kit | kenney.nl | `8a71ea16219315a01d00d5a90c4f6b5c090faddbc56d80ecf727e2b3b853c6c0` | 6 082 755 |
| Kenney Cube Pets 1.0 | kenney.nl | `b3bdc99a2ec92c687b875718c5d01e9231d2711ed0e2845f295b474bb42a1283` | 2 812 444 |

Also checked, all CC0 in the archive: Kenney City Kit Commercial 2.1, Holiday Kit, Retro Urban Kit, Building Kit, Tiny Farm (2D), Animated Characters Protagonists. Measurements come from small Python readers of glTF accessor counts and bounds and OBJ faces, written in the scratch folder.

## Sources

- Kenney: https://kenney.nl/assets/car-kit · https://kenney.nl/assets/city-kit-suburban · https://kenney.nl/assets/city-kit-industrial · https://kenney.nl/assets/survival-kit · https://kenney.nl/assets/furniture-kit · https://kenney.nl/assets/nature-kit · https://kenney.nl/assets/mini-characters · https://kenney.nl/assets/fantasy-town-kit · https://kenney.nl/assets/racing-kit · https://kenney.nl/assets/cube-pets
- KayKit: https://kaylousberg.itch.io/city-builder-bits · https://kaylousberg.itch.io/furniture-bits · https://kaylousberg.itch.io/
- Quaternius: https://quaternius.com/license.html · https://quaternius.com/packs/farmbuildings.html · https://quaternius.com/packs/farmanimal.html · https://quaternius.com/packs/cars.html · https://quaternius.com/packs/backgroundposedhumans.html · https://quaternius.itch.io/lowpoly-cars · https://quaternius.itch.io/lowpoly-farm-buildings · https://quaternius.itch.io/lowpoly-animated-animals · https://quaternius.itch.io/stylized-nature-megakit · https://quaternius.itch.io/universal-base-characters
- Poly Pizza: model pages cited in the tables (https://poly.pizza/m/<id>)
- Poly Haven: https://polyhaven.com/license · https://api.polyhaven.com/assets?t=models
- itch / OpenGameArt: https://styloo.itch.io/farm · https://automataworkshop.itch.io/lowpoly-farm · https://xra7en.itch.io/lowpoly-farm-pack · https://opengameart.org/content/cc0-models-by-mish7913
- Earlier license findings: [asset-sources-catalog-2026-10-06](../asset-sources-catalog-2026-10-06.md), [tree-resource-review-2026-10-06](../tree-resource-review-2026-10-06/README.md)
