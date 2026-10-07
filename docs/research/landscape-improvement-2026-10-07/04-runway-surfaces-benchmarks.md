# 04 · Runway and field surfaces, and how RC sims present fields

Date: 2026-10-07. Status: research only; no `app/` change. Input: [05 · landscape image review](../scenery-investigations/05-landscape-image-review.md) (finding 5: the runway is a flat lime band, hue 87°, saturation 0.57, value 0.63, hard edges), [03 · RC field layout](../scenery-investigations/03-rc-field-layout-references.md) (sizes, markings, pads), [SCENERY-PLAN](../../SCENERY-PLAN.md) O-6, [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (L9c, L9d, L10; no decals until 4.8), [06 · ground anti-tiling](../landscape-investigations/06-ground-anti-tiling.md) (the L9 spike), `app/render/field.gd`, `ground.gdshader`, `app/data/fields/default.json`, `app/data/ground/surface_friction.json`. Constraints: Godot 4.7.2 Compatibility only, no `TIME`, deterministic, markings as shader or geometry, CC0 first. Downloads went to scratch only (`/tmp/claude-1000/landscape-research/04/`).

Evidence tags: **[V]** read on the page or in the PDF on 2026-10-07 · **[V-fig]** read from a rendered figure · **[doc]** official documentation · **[sec]** secondary page (review site, magazine) · **[F]** forum post · **[measured]** measured here from downloaded files or the owner's photo · **[computed]** our arithmetic · **[est]** estimate · **[inference]** · **[iss]** engine issue tracker · **[U]** not verified.

## Summary: recommendations

1. **Draw every field surface in the one ground shader (L9c), from the field rectangles as signed distances.** Remove the lifted `PlaneMesh` per surface in `field.gd`. Lifted planes z-fight beyond ~150–300 m (24-bit depth step 6 mm at 100 m, 5 cm at 300 m [computed]; SC-01 measured the runway vanishing). They also give hard, unfiltered edges, because MSAA does not anti-alias anything inside a shader [doc].
2. **Make the grass runway read as mown turf, not as a lime band.** Use the same hue as the surrounding grass (±5°), a little less saturation and +10–25 % value. Add **mown stripes 1.5 m wide along the runway** (1.2–1.8 m: one ride-on deck). Their brightness depends on the view: `±(3–6 %)·dot(view_xz, bend_dir)`. Keep the stripe amplitude ≤ ½ of the runway edge step (the L9c rule). Break the mown→rough border with noise. Add worn touchdown zones.
3. **Filter every procedural pattern by its pixel footprint.** Use an exact 1-D box filter for lines and a square-wave integral for stripes and dashes (our own code, §6). From the pilot, a 1.5 m stripe across the line of sight is 9 px at 15 m but 0.6 px at 60 m. A 0.3 m centreline is ~2 px wide [computed]. Unfiltered, both shimmer.
4. **Paved option (O-6, `paved.json`):** use CC0 **Poly Haven `aerial_asphalt_01`** (30 × 30 m tile, worn road with cracks and tyre arcs) as a **detail-only** texture. Divide it by its mean, then multiply by an albedo from the field data. Draw the markings analytically: dashed white centreline, yellow X with a cross bar at each end, black pads. The owner's photo gives the colour targets (§7). The photo shows **fresh, near-black asphalt**, darker than the grass (luminance ratio 0.27) [measured].
5. **Calibrate photo textures, never trust their means.** Ten CC0 asphalt and road sets measured here range from linear luminance 0.046 to 0.341. Real asphalt is 0.04–0.05 new and 0.10–0.20 aged [V, EPA figure].
6. **Gravel, dirt and worn grass** become extra shader surface types later. For now the scenery track draws them as lifted meshes (`scenery/ground_features.gd`). Candidates: CC0 Gravel043, Ground048, Poly Haven `gravel_floor_02`, `dry_mud_field_001`.
7. **Benchmark lessons:** players praise RC photo fields for realism, and fault 3D fields for **repetitive texturing**, primitive trees and "flat" ground [sec]. In MSFS, players fault **lime-green, over-saturated grass**, "inorganic and unrandomized" textures, low white-on-grey marking contrast, and grass runways that look the same as the fields around them [F]. All of these are on our list (05 findings 1, 2, 5).

## 1. Grass runway: what makes it look real

| Technique / fact | How | Cost | Compatibility | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Why stripes show** | Blades bent **away** from the viewer show their long, wide side and look lighter. Blades bent **toward** the viewer show tips and shadow and look darker. Seen from the opposite direction, a stripe flips. Longer grass and rollers increase contrast; warm-season grasses (Bermuda, Bahia) stripe poorly | — | — | — | [Landscape Management](https://www.landscapemanagement.net/step-by-step-achieving-good-stripes/), [Grasshopper](https://www.grasshoppermower.com/blog/the-secret-to-perfect-stripes-lies-in-your-deck-height) | [V] (trade press) |
| **Stripe width** = mower deck width minus overlap | Commercial zero-turn decks 48–72 in (1.2–1.8 m), up to 96 in. Tractor gang mowers wider | — | — | — | [Bob Vila](https://www.bobvila.com/articles/best-commercial-zero-turn-mowers/), [Deere](https://www.deere.com/en/mowers/zero-turn-mowers/) | [U] (search summary); 1.5 m [est] |
| Mowing heights for striping | 2.5–4 in (6–10 cm) by species | — | — | — | Grasshopper (above) | [V] |
| Full-size turf runways have **no FAA paint standard** | AC 150/5340-1M: "surface markings for unpaved airfield runways will be addressed at a future date" | — | — | — | FAA AC 150/5340-1M §1 | [V] |
| The runway must differ from the fields around it | MSFS users: "no difference between run-/taxiway and surrounding fields"; "very difficult to identify the actual runway"; normal cut 5–10 cm | — | — | — | [MSFS forum 444720](https://forums.flightsimulator.com/t/need-mown-grass-runways/444720) | [F] |
| **View-dependent stripes in the shader** | `b` = mowing direction of the stripe (±runway axis, alternating), `v` = normalized (fragment − camera).xz: `k = 1 + s·(A·dot(v, b)·(1 − abs(view.y))^p + B·dot(sun.xz, b))`, A ≈ 0.04–0.06, B ≈ 0.02 | ~10 ALU, 0 fetches | ✅ `CAMERA_POSITION_WORLD` [doc, used in the 06 spike] | ours | [06](../landscape-investigations/06-ground-anti-tiling.md) spike (`1 ± (0.04 + 0.10·v.x)`) | spike measured; A, B, p [est] |
| **Mown → rough border** | `d = sdBox(p, rect) + amp·(vnoise(p/λ) − 0.5)`, amp 0.3–0.8 m, λ 2–6 m. Rough ×0.75–0.85 value, a little yellower. Blend over 0.2–0.5 m plus the pixel footprint | ~15 ALU | ✅ | ours (Hoskins hash, MIT) | 06 spike (amp 5 m, rough ×0.74) | spike measured; widths [est] |
| **Wear** | Touchdown zones 10–30 m in from each threshold, ±3 m about the centreline: −10 % saturation, hue −5°, +5 % value, noise-broken. Taxi paths 1–2 m wide from the pads and the pilot gate to the runway | ~10 ALU | ✅ | ours | — | [est]; no source measured RC wear |

**What the pilot sees [computed].** From an eye height of 1.7 m, the runway's near edge (9 m north) is 10.7° below the horizon and its far edge (21 m) is 4.6°: 6.1°, or 88 px at 720p (50° FOV). The stripes run E–W, across the pilot's line of sight, so each stripe is foreshortened in depth. A 1.5 m stripe covers 9.2 px at 15 m, 2.3 px at 30 m and 0.6 px at 60 m (720p). Seen this way, `dot(v, b) ≈ 0`, so view-dependent contrast is **weakest from the pilot box**, as in 06. The edges carry the cue, and the stripes add life in chase views and at the runway ends.

## 2. Paved runway (O-6)

### CC0 asphalt sources

Mean colour and linear luminance Y (Rec. 709) were measured on the 1K colour maps, downsampled to 256² [measured]. Tile size comes from the ambientCG API `dimensionX` or the Poly Haven API `dimensions` (mm).

| Resource (exact ID) | Tile | Maps | Mean sRGB · Y | Licence | Source | Verified? |
| --- | --- | --- | --- | --- | --- | --- |
| **Poly Haven `aerial_asphalt_01`** (Rob Tuytel, 2020): "flat, worn road with subtle cracks, faint tire marks" | **30 × 30 m** | Diffuse, nor_gl, rough, AO, arm, disp; 1K 0.64 MB, 2K 2.8 MB JPG | (103, 98, 104) · 0.126 | CC0 | [asset](https://polyhaven.com/a/aerial_asphalt_01), [API](https://api.polyhaven.com/info/aerial_asphalt_01) | [V] + [measured] |
| Poly Haven `asphalt_02` (cracked, weathered) | 3.0 m | same set | (91, 91, 85) · 0.103 | CC0 | [asset](https://polyhaven.com/a/asphalt_02) | [V] + [measured] |
| Poly Haven `asphalt_04` (weathered, cracked, discoloured; to 16K) | 4.04 m | same set | (134, 130, 126) · 0.225 | CC0 | [asset](https://polyhaven.com/a/asphalt_04) | [V] + [measured] |
| Poly Haven `clean_asphalt` (2026) | 2.1 m | same set | (69, 70, 70) · 0.061 | CC0 | [asset](https://polyhaven.com/a/clean_asphalt) | [V] + [measured] |
| Poly Haven `asphalt_07`, `road_damaged_clean`, `tarred_gravel` (chip seal) | 2.5 / 2.2 / 2.2 m | same set | Y 0.072 / 0.047 / 0.046; hue 27–36°, brownish | CC0 | polyhaven.com | [V] + [measured] |
| **ambientCG Asphalt033** (photogrammetry, 2026-07) | 2.5 m | Color, NormalGL/DX, Roughness, AO, Displacement (zip also has a Godot `.tres`) | (86, 82, 72) · 0.085 | CC0 | [ambientcg.com/a/Asphalt033](https://ambientcg.com/a/Asphalt033) | [V] + [measured] |
| ambientCG Asphalt023L / 023S | 2.5 / 1.25 m | + AO | (122, 121, 113) · 0.190 | CC0 | ambientCG | [V] + [measured] (L) |
| ambientCG Asphalt030 | 2.2 m | + AO | (165, 157, 140) · **0.341** (too bright as albedo) | CC0 | ambientCG | [V] + [measured] |
| ambientCG Asphalt020L/S, Asphalt021 (cracks) | 4.6 / 1.85 / 1.85 m | + AO | — | CC0 | ambientCG | [V] |
| ambientCG Road006, Road003 ("patches"), Road008B ("aged, cracked, worn") | 7.5 m (006/003); 008B no size | Color, Normal, Roughness, Disp | — | CC0 | ambientCG | [V]; Road00x include lane paint, so not usable as-is |

Licences: ambientCG "All ambientCG assets are provided under the Creative Commons CC0 1.0 Universal License" ([licence](https://docs.ambientcg.com/license/)) [V]. Poly Haven: CC0, "You do not need to give credit" ([licence](https://polyhaven.com/license)) [V]. Record per-file provenance (ID, URL, date, SHA-256) anyway, as the repo does for other assets.

**Pick:** `aerial_asphalt_01` colour at 1K (2.9 cm/texel) or 2K (1.5 cm/texel). A 30 m tile repeats only 3.3× along a 100 m runway, which makes it the macro layer. Its cracks and curved tyre marks are what an aged club strip shows. At 15 m the pixel footprint is 1.8 cm across and ~16 cm in depth (720p) [computed], so 1K is enough at native zoom. 2K pays off only under auto-zoom. A second, smaller detail tile (Asphalt033, 2.5 m) is optional and needs the L9b anti-tiling.

**Use the texture as detail only:** `albedo = target_albedo · tex / tex_mean`, with `tex_mean` computed offline and stored with the provenance. Without this, the choice of texture would set the runway brightness: the CC0 sets above span 0.046–0.341, a factor of 7.

### Markings, cracks and weathering in the shader

| Element | How (field-local coords `u` along, `v` across the runway, metres) | Cost | Compatibility | Source / basis | Verified? |
| --- | --- | --- | --- | --- | --- |
| Dashed centreline | Box-filtered pulse across `v` (width 0.3 m) × box-filtered pulse train along `u` (period P, dash D) | ~20 ALU | ✅ `fwidth` (used in the 06 spike) | FAA: width ≥ 12 in, dash 120 ft / gap 80 ft (3:2); photo ≈ 1:1, ~13 dashes per runway | [V] (03); photo [est] |
| Yellow X at each end | Two segment SDFs (`length(p − a − (b − a)·h)`), minus half the arm width; a transverse bar at the threshold (photo) | ~25 ALU | ✅ | FAA closed-runway X (03); photo shows X + bar | [V] (03) / photo |
| Start-up pads | Rounded-box SDFs, same asphalt as the runway (photo: black squares) | ~10 ALU each | ✅ | 03 (hypothesis: taxi or start-up pads) | photo [est] |
| Paint wear | Multiply the coverage by `0.6 + 0.4·vnoise(p/0.4 m)` and by a tyre-band term near `v = 0` | ~8 ALU | ✅ | — | [est] |
| Crack-seal "tar snakes" | Darker, 5–10 cm meandering lines: comes free with `aerial_asphalt_01`; procedural only if the texture is dropped | 0 extra | ✅ | texture content | [V] (thumbnail viewed) |
| Asphalt edge into grass | Edge noise 2–5 cm; grass creeping 0.1–0.3 m onto old asphalt (a 1-D blend band) | ~6 ALU | ✅ | — | [est] |
| Marking geometry (thin quads above the runway) | MSAA anti-aliases geometric edges [doc] | +draws | ✅ | — | **rejected:** depth step 6 mm at 100 m, 5 cm at 300 m [computed]; needs a 2–3 cm lift that fails in raised views (SC-01) |

## 3. Other surfaces: gravel car park, dirt tracks, worn grass

| Resource | Tile | Mean sRGB · Y [measured] | Use | Licence | Verified? |
| --- | --- | --- | --- | --- | --- |
| ambientCG **Gravel043** (fine grey gravel, 2026) | 1.6 m | (108, 109, 105) · 0.152 | car park | CC0 | [V] + [measured] |
| ambientCG Gravel022 / Gravel023 (pebbles; 023 light) | 1.5 m | — | lighter limestone car park | CC0 | [V] |
| Poly Haven `gravel_floor_02` (driveway gravel) | 2.0 m | (171, 167, 156) · 0.389 (normalize!) | car park | CC0 | [V] + [measured] |
| Poly Haven `gravel_road` | 2.0 m | (121, 88, 64) · 0.115, hue 25°, sat 0.47 (reddish) | dirt-gravel road | CC0 | [V] + [measured] |
| ambientCG **Ground048** (brown soil) | 1.4 m | (86, 63, 52) · 0.058 | dirt track ruts | CC0 | [V] + [measured] |
| Poly Haven `dry_mud_field_001` | 3.0 m | (102, 89, 70) · 0.103 | dry dirt track | CC0 | [V] + [measured] |
| Poly Haven `aerial_mud_1` (tyre tracks, ruts) | 8.0 m | — | access road (macro) | CC0 | [V] |
| Poly Haven `grass_path_2/3`, `sparse_grass`, `withered_grass`, `grass_ground` | 1.0 / 1.0 / 2.0 / 2.0 / 2.5 m | `grass_path_2` Y 0.232; `withered_grass` Y 0.316 | worn grass, dry patches | CC0 | [V] + [measured] (two) |

**Blending from field rectangles.** Each surface gets a priority and an SDF. The coverage `c = clamp(0.5 − d/fw, 0, 1)` blends its albedo over the layers below. For grass types, `d` gets noise (amp 0.3–1 m). For hard surfaces (asphalt, gravel edge) it gets 2–10 cm. Gravel and dirt add a 0.5–1.5 m **worn-grass halo**: a second, wider blend band at reduced saturation, the same idea as the scenery's "worn ring". The scenery palette now uses gravel `#a59b88` (Y ≈ 0.33 [computed]) and dirt `#86704f` (Y ≈ 0.17). The dirt is a good match for bare soil (0.17 [V, Wikipedia]). The gravel sits at the bright end of the CC0 gravels (0.12–0.39).

**Not ready for polygons:** the scenery's tracks are polylines. A segment-SDF loop costs O(segments) per pixel. Either cap the count (≤ 16 segments), or bake a small mask texture on the CPU at load time (§6).

## 4. Benchmarks: how RC sims (and MSFS) present fields

The [landscape-research](../landscape-research.md) §3 table already covers the techniques of RealFlight, Aerofly, PicaSim, SeligSIM, Phoenix, ClearView and CRRCSim. This table adds what reviewers say about the **ground and runway**. Screenshots were not inspected (the tools return text only), so nothing below describes images.

| Sim | Field presentation | Praised | Complained | Source | Tag |
| --- | --- | --- | --- | --- | --- |
| RealFlight Evolution (2023–) | 3D fields + PhotoFields; Triple Tree Aerodrome; > 40 sites | physics, library | "Environmental textures, lighting, and visual fidelity feel noticeably antiquated"; "Flat environmental textures and low-polygon ground assets" next to Aerofly RC 10 | [Aeronautics Magazine (Apr 2026)](https://aeronauticsmagazine.com/hobby/rc-planes/realflight-evolution-rc-flight-simulator-does-it-actually-make-you-a-better-pilot-or-just-a-better-simulator-pilot), [Steam](https://store.steampowered.com/app/2069310/) | [sec] (low-quality review site) |
| RealFlight 9/9.5 vs Reflex XTR2 | RF9: 3D-modelled fields; Reflex: panoramic photo | users preferred the photo look | photo fields are "severely limited by the 'image on a fishbowl' programming"; 3D allows other views | [Steam 1637549649109270914](https://steamcommunity.com/app/1070820/discussions/0/1637549649109270914) (2019–2020) | [F] |
| RealFlight custom PhotoField (HHAMS) | equirectangular photo + hand-placed invisible collision | real field reproduced | "too bright … that actually is how the field looks, but most of the times one flies with sunglasses on"; aligning collision proxies "a pain" | [xinhaidude 2016](https://xinhaidude.com/2016/04/14/custom-realflight-airfields-based-on-the-hhams-aerodrome) | [sec] |
| Aerofly RC 8 | 360° photo + invisible terrain mesh; 3D "game-style" scenes with chase cams and time of day | photo scenes "can be breathtaking" | 3D: "repetitive texturing and primitive tree and structure models … often look dated" | [Tally Ho Corner 2021](https://tallyhocorner.com/2021/02/aerofly-rc-8-review/) | [sec] |
| Aerofly RC 10 | photo + "4D" 3D scenes, 4K, dynamic light | visuals, time of day | RC 8 → 10 changes hard to see ("except for some night lighting options") | [FlyAway](https://flyawaysimulation.com/ask/answers/best-rc-flight-simulators-pc/), [IPACS forum](https://www.aerofly.com/community/forum/index.php?thread%2F23186-changes-from-8-9-10%2F=) | [sec] / [F] |
| AeroFly 5 (2011) | HD panoramas + 4D sites with leaves moving in the wind | "near-photo realism" + free movement | — | [Fly RC 2011](https://flyrc.com/?p=1992) | [sec] |
| neXt (CGM) | 3D, 26 sceneries, "smooth on older systems" | — | no field-specific review found | [App Store](https://apps.apple.com/us/app/id1177626394) | [U] |
| MSFS 2020/2024 (full size) | aerial photo + procedural grass | — | "LOTS of lime green grass … a real immersion killer" (2022); "inorganic and unrandomized"; markings "lack contrast between white and grey"; green terrain "almost cartoony"; grass runways look the same as the fields | [Bing colour thread](https://forums.flightsimulator.com/t/bing-map-color-correction/498589), [ground textures thread](https://forums.flightsimulator.com/t/improve-the-ground-surface-textures/523029), [mown runways](https://forums.flightsimulator.com/t/need-mown-grass-runways/444720) | [F] |

**Lessons [inference]:**
- Repetition and saturation are the two complaints common to every 3D ground. They are our findings 1–2, so L9b comes before any runway polish.
- Photo fields win for a fixed pilot because their colour, wear and scale are real. A procedural field therefore needs real colour ratios (§7) and wear, not more texture resolution.
- Contrast of the paint against the asphalt, and of the runway against the grass, is what players notice on runways.

## 5. Reference data

| Quantity | Value | Source | Verified? |
| --- | --- | --- | --- |
| Asphalt solar reflectance, new → 6 years | 5–10 % → ~11–19 % (band in figure); concrete 35–40 % → ~26–34 %. "Asphalt tends to lighten as the binder oxidizes and more aggregate is exposed" | [EPA, Reducing Urban Heat Islands, ch. "Cool Pavements"](https://www.epa.gov/sites/default/files/2017-05/documents/reducing_urban_heat_islands_ch_5.pdf), Fig. 4 | [V-fig] + [V] |
| Fresh / worn asphalt; green grass; bare soil; new concrete | 0.04 / 0.12; 0.25; 0.17; 0.55 | [Wikipedia, Albedo](https://en.wikipedia.org/wiki/Albedo) (table) | [V] |
| Dry asphalt / grass / fresh grass / concrete | 0.09–0.15 / 0.15–0.25 / 0.26 / 0.25–0.35 | [PVPMC (PVsyst guidance)](https://pvpmc.sandia.gov/?p=313) | [V] |
| LBNL Heat Island Group: new / aged asphalt | ~0.05 / 0.10–0.20 | search summary only | [U] |
| **Caveat:** solar albedo includes the near infrared. Asphalt is spectrally flat, so its value also holds for visible light. Grass reflects strongly in the NIR and weakly in the visible (chlorophyll), so **its visible albedo is well below 0.25** | — | [K-State turf radiometry](https://www.k-state.edu/turf/docs/bremer/remote-sensing/Multispectral_radiometry07.pdf) (qualitative) | [inference]; no visible-band number found |
| **Owner's photo** (aerial, local only), colour means by mask | asphalt (42, 52, 47) V 0.20, Y 0.034; white paint (218, 221, 219) Y 0.72; yellow (200, 167, 65) hue 45°, sat 0.68, Y 0.41; grass (84, 106, 48) hue 83°, sat 0.54, V 0.41, Y 0.125. **Asphalt/grass Y = 0.27; paint/asphalt = 21×** | `references/scenery/owner-inspiration-aerial-2026-10-07.png` | [measured] (camera exposure and haze unknown: use the ratios) |
| RC runway sizes, markings, pads | 107–183 × 9–18 m paved (Florida); ours 100 × 12 m; FAA centreline ≥ 0.3 m, 3:2 dashes; yellow X = closed runway | [03](../scenery-investigations/03-rc-field-layout-references.md) | [V] there |
| Pilot cue: the centreline at a known distance | "proficient pilots perceive how far the runway centerline is from where they are standing" (their example: 75 ft in front; ours 15 m) | [Model Aviation, Landing Approach](https://www.modelaviation.com/LandingApproach) | [sec] |

**Pixel sizes from the pilot's eye (1.7 m) [computed].** A feature 0.3 m wide, seen across the line of sight ("lat") or along it ("depth", foreshortened):

| Distance | 720p, 50° lat / depth | 1080p, 50° lat / depth | 720p, auto-zoom 10° lat / depth |
| --- | --- | --- | --- |
| 10 m | 24.8 / 4.1 px | 37.1 / 6.1 px | 124 / 20 px |
| 25 m | 9.9 / 0.67 px | 14.9 / 1.0 px | 50 / 3.4 px |
| 50 m | 5.0 / 0.17 px | 7.4 / 0.25 px | 25 / 0.8 px |
| 100 m | 2.5 / 0.04 px | 3.7 / 0.06 px | 12 / 0.2 px |

So the centreline, the stripes and the dashes fall below a pixel in depth within 25–50 m. Filtering is required, not optional. **Auto-zoom** (down to 6°) magnifies the distant runway 5–8×. That is when tiling and blur at 100–300 m become visible, so test L9c in zoomed views too.

## 6. Godot 4.7.2 Compatibility implementation notes

| Topic | Finding | Cost | Status | Source | Verified? |
| --- | --- | --- | --- | --- | --- |
| **One ground shader, analytic SDF surfaces (recommended)** | `uniform vec4 surf_rect[16]` (centre, half size, field-local) + `uniform vec4 surf_param[16]` (type, priority, edge noise). Early-out: one `sdBox` against the field's bounding box, so the other 99.9 % of the 40 km ground pays ~5 ALU | ~12 ALU per rectangle inside the field; markings ~50 ALU on the runway only; **0 fetches** | ✅ uniform arrays are in the shading language (no default value allowed) [doc]; `fwidth` and `textureGrad` ran in the 06 spike [measured] | [shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html) | [V] |
| Baked surface-ID / SDF mask texture | CPU-baked from the field JSON at load (deterministic): e.g. RGBA8 1024² at 0.25 m/texel over 256 m (4 MB). Handles any polygon. Blurry edges, no thin paint | 1 fetch | ✅ | — | [inference]; keep for when scenery patches move into the ground |
| Separate lifted meshes (today) | z-fighting; edges anti-aliased by MSAA only; one draw call per surface | +1 draw per surface | works, but fails in raised views | SC-01; sibling [03](03-terrain-sky-lighting.md) | measured (SC-01), [computed] |
| **Depth step of a 24-bit buffer** | `Δz ≈ z²/(near·2²⁴)`, near 0.1 m: 0.5 mm at 30 m, 6 mm at 100 m, 5.4 cm at 300 m | — | assumes non-reversed 24-bit depth in Compatibility | [computed] | [U] for the depth format |
| **MSAA does not touch shader patterns** | "increases the number of coverage samples, but not the number of color samples". Compatibility offers only MSAA and SSAA (no FXAA/TAA) | — | ✅ | [3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html) | [doc] |
| **Thin lines: exact 1-D box filter** | `cov = max(0, min(v + fw/2, w/2) − max(v − fw/2, −w/2)) / fw`, with `fw = fwidth(v)`. It is correct even when `w < fw` (it fades to `w/fw`). `clamp(0.5 − d/fw)` is not: it never drops below 0.5 at the line centre | ~6 ALU | ✅ | ours (pulse filtering as in Gritz's `filteredpulse`, [patterns.h](https://people.eecs.berkeley.edu/~jfc/cs184f98/labs/proj2/dj/patterns.h)) | [inference], standard |
| **Stripes / dashes: integral of the wave** | Square wave ±1 with period P has the integral `I(x) = P·(0.5 − abs(fract(x/P) − 0.5))`; filtered = `(I(x + fw/2) − I(x − fw/2))/fw` → 0 (the mean) when `fw ≫ P`. Dashes: integral of a pulse train, `J(u) = floor(u/P)·D + min(fract(u/P)·P, D)` | ~10 ALU | ✅ | ours. Same idea as Quilez's filtered checkerboard ([article](https://iquilezles.org/articles/checkerfiltering/), no code licence, so we don't copy it) | [V] (idea) |
| **Precision (float32)** | ulp 1.5e-5 m at 128 m, 2 mm at 20 km. Compute SDFs in **field-local** coordinates `world.xz − field_origin` (uniform), so the numbers stay small. Keep noise inputs < 1e4 and use the integer-style Hoskins hash. Large two-triangle meshes can jitter interpolated UVs; Godot's fix is subdivision (G-1) | 0 | ✅ | [PlaneMesh doc](https://docs.godotengine.org/en/stable/classes/class_planemesh.html); [Bugnet note](https://bugnet.io/blog/fix-godot-shader-fract-on-large-uvs-precision-banding) (its "fix" changes the maths unless the scale is an integer) | [doc] / [sec] |
| **Derivatives inside branches** | Implicit-LOD `texture()` and `fwidth` give undefined derivatives in non-uniform control flow. Compute `dFdx/dFdy` of `p` once, before any `if`, then sample with `textureGrad` | 0 | ✅ | GLSL ES 3.00 rule | [inference] (spec not re-read) |
| Anisotropic filtering at grazing angles | Reported ineffective in 4.7 (#123648, "needs testing"). Far asphalt blurs to its mean, which is acceptable once it is calibrated | — | ⚠ | [06](../landscape-investigations/06-ground-anti-tiling.md) | [iss] |
| Fog | The ground shader writes its own `FOG`. Moving the runway into it removes the second fog path (the runway's `StandardMaterial3D`). It may also explain the far-edge "6 %" mystery in 06 | 0 | ✅ | [inference] | — |
| Fetch budget | grass 2 (L9b) + asphalt 1 (only where the runway covers the pixel, via `textureGrad`) + optional detail 1 = **3–4** | — | ✅ | 06 table | [inference] |

## 7. Concrete targets

| Item | Target | Basis |
| --- | --- | --- |
| Mown grass runway (`default.json`) | Hue within ±5° of the mown grass; saturation −0.05 to −0.10; value +10–25 %. Today: hue 87°, sat 0.57, V 0.63 against grass 0.38: too far apart and too lime | 05 photo grass hue 73–80°, sat 0.43–0.53; owner photo grass hue 83°, sat 0.54 [measured] |
| Runway edge step | ≥ the L0c-derived L9c threshold at 100 m; stripe ripple < ½ step (L9c proof) | LANDSCAPE-PLAN L9c |
| Mown stripes | Along the runway, 1.5 m (1.2–1.8 m), view amplitude 3–6 %, filtered to the mean below ~2 px period | §1 |
| Mown → rough | Rough value ×0.75–0.85, hue −3 to −8°; noisy border amp 0.3–0.8 m, λ 2–6 m | 06 spike; [est] |
| Wear | Touchdown zones 10–30 m from each threshold; taxi paths 1–2 m wide | [est] |
| Paved runway (`paved.json`) | Photo match: asphalt at **0.27× the grass luminance** (fresh, sealcoated, sRGB ≈ (45, 50, 47) when the grass is ≈ (84, 106, 48)). Aged variant: linear albedo 0.10–0.15, neutral grey, so lighter than the grass | owner photo [measured]; EPA [V-fig] |
| White paint | Linear ≈ 0.7 fresh (photo Y 0.72), worn −20…−40 % in noise blotches | photo [measured]; wear [est] |
| Yellow X | sRGB ≈ (200, 167, 65), hue ≈ 45°, sat ≈ 0.68; arms across the full runway width, arm width 0.6–1.0 m; a cross bar at the threshold | photo [measured]; widths [est]; FAA X (03) |
| Centreline | 0.3 m wide; dash:gap 1:1 (photo), period ≈ 7.7 m (13 per 100 m) or the FAA 3:2 | 03 [V]; photo [est] |
| Pads | Six, same asphalt, about one runway width square, on the pit side | 03 (hypothesis) |
| Friction | `asphalt` type in `surface_friction.json`: factors 1.0 / 1.0 (FlightGear dry asphalt is the reference) | SCENERY-PLAN (physics row); E3a |
| Proofs | Byte-repeat captures; column profiles across both edges (low pass); a 2-frame diff under a 0.5 px camera move shows no shimmer on the dashes and stripes; zoomed (10°) captures at 100 and 300 m | LANDSCAPE-PLAN L9c; [inference] |

## Not verified

- Typical zero-turn deck widths (search summary only). Stripe width 1.5 m is an estimate.
- LBNL asphalt values (0.05 / 0.10–0.20): search summary only. The EPA figure covers the same range.
- The visible-band albedo of grass: no numeric source read (the USGS spectral library page returned 404).
- EN 1436 luminance-factor classes for road paint: the standard is paywalled; COPRO's PDF has no table. The paint targets come from the owner's photo.
- Whether Compatibility uses a 24-bit non-reversed depth buffer (the depth-step formula assumes it). Sibling report 03 gives the same numbers.
- The GLSL ES rule on derivatives in non-uniform control flow was not re-read in the spec.
- No RC-specific source on runway wear; the wear layout is estimated.
- RC sim reviews are thin. Steam reviews and RCGroups threads were not searched one by one, and no screenshots were inspected. The RealFlight Evolution criticism comes from a low-quality review site.
- The pad size, the X arm width and the dash geometry are photo estimates (tilt unknown).

## Sources

- Owner's aerial photo (local only, not committed): `references/scenery/owner-inspiration-aerial-2026-10-07.png` — colour masks measured 2026-10-07.
- ambientCG API ([full_json](https://ambientcg.com/api/v2/full_json?q=asphalt&include=dimensionsData,displayData)), asset pages (e.g. [Asphalt033](https://ambientcg.com/a/Asphalt033), [Gravel043](https://ambientcg.com/a/Gravel043), [Ground048](https://ambientcg.com/a/Ground048)), [licence](https://docs.ambientcg.com/license/) [V].
- Poly Haven API ([assets](https://api.polyhaven.com/assets?type=textures), [info/aerial_asphalt_01](https://api.polyhaven.com/info/aerial_asphalt_01), [files/aerial_asphalt_01](https://api.polyhaven.com/files/aerial_asphalt_01)), [licence](https://polyhaven.com/license) [V].
- EPA, *Reducing Urban Heat Islands: Compendium of Strategies*, "Cool Pavements", Fig. 4. [PDF](https://www.epa.gov/sites/default/files/2017-05/documents/reducing_urban_heat_islands_ch_5.pdf) [V-fig].
- [Wikipedia: Albedo](https://en.wikipedia.org/wiki/Albedo); [PVPMC albedo page](https://pvpmc.sandia.gov/?p=313) [V].
- FAA AC 150/5340-1M Change 1, *Standards for Airport Markings* (scratch copy from report 03) [V].
- Lawn stripes: [Landscape Management](https://www.landscapemanagement.net/step-by-step-achieving-good-stripes/), [Grasshopper Mower](https://www.grasshoppermower.com/blog/the-secret-to-perfect-stripes-lies-in-your-deck-height) [V].
- [Model Aviation: Landing Approach](https://www.modelaviation.com/LandingApproach) [sec].
- RC sims: [Aeronautics Magazine](https://aeronauticsmagazine.com/hobby/rc-planes/realflight-evolution-rc-flight-simulator-does-it-actually-make-you-a-better-pilot-or-just-a-better-simulator-pilot), [Tally Ho Corner](https://tallyhocorner.com/2021/02/aerofly-rc-8-review/), [Fly RC](https://flyrc.com/?p=1992), [FlyAway Simulation](https://flyawaysimulation.com/ask/answers/best-rc-flight-simulators-pc/), [xinhaidude HHAMS](https://xinhaidude.com/2016/04/14/custom-realflight-airfields-based-on-the-hhams-aerodrome) [sec]; [Steam RF 9.5 thread](https://steamcommunity.com/app/1070820/discussions/0/1637549649109270914), [IPACS forum](https://www.aerofly.com/community/forum/index.php?thread%2F23186-changes-from-8-9-10%2F=) [F].
- MSFS forums: [Bing colour correction](https://forums.flightsimulator.com/t/bing-map-color-correction/498589), [ground textures](https://forums.flightsimulator.com/t/improve-the-ground-surface-textures/523029), [mown grass runways](https://forums.flightsimulator.com/t/need-mown-grass-runways/444720) [F].
- Godot docs: [shading language](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html), [3D antialiasing](https://docs.godotengine.org/en/stable/tutorials/3d/3d_antialiasing.html), [PlaneMesh](https://docs.godotengine.org/en/stable/classes/class_planemesh.html) [doc].
- Filtering ideas: [Quilez, filtered checkerboard](https://iquilezles.org/articles/checkerfiltering/), [Quilez, 2D SDFs](https://iquilezles.org/articles/distfunctions2d/) (no code licence: ideas only), [Gritz patterns.h](https://people.eecs.berkeley.edu/~jfc/cs184f98/labs/proj2/dj/patterns.h).
