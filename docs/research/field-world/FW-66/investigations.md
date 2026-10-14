# FW-66: targeted Internet investigations for the night plan

2026-10-13 · Research round 2 requested by the owner · **26 distinct Internet investigations completed; implementation probes remain pending.**

This record strengthens the [night landscape plan](../../../plans/night-landscape-lighting.md). Each investigation answers a separate question, consults a primary Internet source, distinguishes source evidence from an implementation inference, and leads to a concrete decision and a test. Linked sources were opened or retrieved, not merely counted as search results. Completed desk research does not mean completed engine validation. This delivery updates research, source samples and the plan; runtime behavior is unchanged.

## Investigation design

| IDs | Questions assigned before searching | Required result |
| --- | --- | --- |
| A01–A08 | Shielding and light spill; real flood optics; coverage photometry; airport directional cues; night visual illusions; CCT versus color rendering; natural-night references; controlled preference/readability review | Evidence-based artistic constraints and layout/review experiments |
| B01–B08 | Better mast; low fixture; campfire base; flame atlas; smoke texture; embers; fireground materials; reusable Godot fire example | Free-source alternatives, actual download/license status and Compatibility intake tests |
| C01–C10 | Exact spotlight law; bloom in LDR; soft cone versus soft shadow; light masks/batching; transparency; atlas filtering; particle replay; night reflections; performance measurement; glTF validation/import | Engine-specific design corrections and executable acceptance gates |

Priority is correctness and impact: resolve light/exposure agreement and resource suitability first; then shape, softness and composition; then effect detail and optimization. Sources that contradict the initial plan must change it. Repeated queries and duplicate pages do not count as additional investigations.

The lead owns this document and the plan. Two Luna Max research tasks own A and B findings in scratch space; they do not edit shared runtime or documentation files. C findings and final integration remain with the lead.

## A. Optics, composition and review investigations

### A01 — Can these shallow flood cones be called shielded?

**Query:** `site:nps.gov dark sky outdoor lighting shielded direct light downward spill`.

**Evidence:** [NPS outdoor lighting principles](https://www.nps.gov/subjects/nightskies/outdoor-lighting-principles.htm) favor useful task lighting, restrained spill and downward shielding; they caution against lateral floodlighting.

**Decision / test:** The original west/east targets have only 12.68° downward depression at 9 m height, but proposed 28–34° angular radii. That would emit directly above horizontal. The center's 19.80° depression also conflicts with its original 34–40° radius. A decorative hood cannot mask an unshadowed Godot cone. Replace those starting angles with a horizon-constrained experiment; compare retargeting and a four-runway-head arrangement if three narrow heads leave gaps. Record any remaining spill honestly. NPS principles inspire the design; they do not certify this virtual installation.

### A02 — What do actual floodlight optics look like?

**Queries:** `site:signify.com floodlight asymmetric IES file luminaire photometry`; `LEDVANCE asymmetric floodlight IES photometric data`.

**Evidence:** The manufacturer [Philips GameVision page](https://www.signify.com/en-au/prof/outdoor-luminaires/sports-and-area-floodlighting/area-and-recreational-floodlighting/philips-gamevision/912300060968_EU/product) links an [IES photometric file](https://api.microservices.signify.com/api/configurator/v2/getPhotometricAssets/ies?id=912300060968&locale=en_AA), which was downloaded. Its distribution varies by horizontal plane; it is not a uniform circular beam. This 1,000 W sports fixture is a reference, not a suitable RC-field specification.

**Decision / test:** Give the four heads believable optics and aiming joints, but label circular Godot spots as approximations. Do not copy this product's wattage/lumens or promise direct IES rendering in Compatibility. Compare each isolated ground footprint before judging the combined scene. Manufacturer photometry strengthens the rationale for asymmetric distribution; implementing that distribution remains constrained by the renderer and light budget.

### A03 — Is geometric reach the same as usable runway illumination?

**Queries:** `site:ies.org "inverse square law" "cosine law" illuminance`; `site:docs.godotengine.org/en/4.7/classes/class_spotlight3d.html spot_angle degrees cone angle`.

**Evidence:** The [IES cosine law](https://ies.org/definitions/cosine-law/) includes incidence angle in point-source illuminance. With equal intensity toward two horizontal-ground samples, this gives `E = I h / d³`.

**Calculation:** For mast `(-8,0,9)`, runway near-center `(9,0,0)` has slant distance 19.235 m; far corner `(21,50,0)` is 58.498 m away. The equal-intensity geometric factor is **28.13 times weaker** at the far point. This excludes real beam distribution, range taper, occlusion and material response; it is not a scene lux measurement.

**Decision / test:** Add relative ground-brightness profiles and individual-head contributions to the 2 m sample grid. Tight cones must not merely “reach” the runway edge. Tune relative aims/intensities before global exposure; keep end markers responsible for distant boundary readability.

### A04 — Which airport cues are directional?

**Query:** `official runway threshold lighting approach direction green red aviation authority aerodrome lighting`.

**Evidence:** [EASA aerodrome rules, March 2026 edition](https://www.easa.europa.eu/en/document-library/easy-access-rules/online-publications/easy-access-rules-aerodromes-regulation-eu?erules-id=ERULES-1963177438-2481) describe threshold green toward approach and runway-end red toward the runway, alongside edge-row guidance and exceptions for real installations. This independently reinforces the existing FAA-based color choice.

**Decision / test:** Preserve direction, not just tint. Capture approaches from both ends, from inside the strip and from behind each threshold. Airfield mode must not show an omnidirectional green ring. Maintain an artistic RC scale; the profile does not reproduce all aerodrome requirements or imply certification.

### A05 — Could a beautiful black background remove orientation cues?

**Queries:** `site:faa.gov "Airplane Flying Handbook" "black-hole" night approach illusion`; `FAA Airplane Flying Handbook Chapter 11 night illusions black hole approach PDF`.

**Evidence:** [FAA Airplane Flying Handbook, chapter 11](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/12_afh_ch11.pdf) describes false horizons and approach illusions where peripheral references are missing. Its context is full-size cockpit flight, not this RC display.

**Decision / test:** Preserve subtle terrain/treeline separation and a readable actual horizon. Compare a runway-only dark control with the intended restrained context during a banked pass and both approaches. Record aircraft attitude and runway-orientation errors as well as appearance. Do not infer a measured RC human-factors benefit from the handbook or globally brighten the sky to avoid testing the problem.

### A06 — Does a Kelvin number guarantee good aircraft colors?

**Queries:** `site:cie.co.at correlated colour temperature colour rendering index different metrics definition CRI CCT`; `site:pubmed.ncbi.nlm.nih.gov mesopic color discrimination different correlated color temperatures LED cone sensitivity study`.

**Evidence:** [CIE's CCT definition](https://www.cie.co.at/eilvterm/17-23-068) describes chromaticity, while its [color-quality position statement](https://www.cie.co.at/files/CIE%20Position%20Statement%20on%20CRI%20and%20Colour%20Quality%20Metrics%20(V.2).pdf) distinguishes color fidelity from broader preference. A [mesopic discrimination study](https://www.jstage.jst.go.jp/article/jpnjvissci/38/2/38_22/_article/-char/en) concerns changing retinal illumination, not a warm-versus-neutral simulator comparison.

**Decision / test:** Include 3,000 K as a warmer candidate alongside 3,500/4,000/4,500 K. Match ground brightness and exposure, then separately score aircraft-color recognition, red/green recognition and atmosphere. Kelvin-derived RGB tint is not a spectral rendering or a CRI measurement. No temperature wins solely by sounding more realistic.

### A07 — How dark should the unlit surroundings remain?

**Queries:** `moonlight illuminance measured lux full moon natural night landscape research National Park Service`; `NPS natural light source moonless full moon ground illuminance night sky metrics`.

**Evidence:** NPS's [Power of Night handbook](https://www.nps.gov/subjects/nightskies/upload/FINAL_NPS_The_Power_of_Night_Handbook_lowres_508.pdf) and [night-sky metrics guide](https://www.nps.gov/subjects/nightskies/NSQmetrics.html) distinguish sky luminance from ground illuminance. Approximate references include 0.1–0.3 lux under a full moon and a 0.8 millilux moonless horizontal reference, with substantial natural variability. [Natural night sources](https://www.nps.gov/subjects/nightskies/natural-light-in-night-sky.htm) provide qualitative context.

**Decision / test:** Compare mast-off/on against a moonless baseline, with moonlit context only as a separate art comparison. Watch sky, trees and lake for unintended lifting. Do not copy these physical lux values into arbitrary Godot energy or infer absolute brightness from tone-mapped PNGs.

### A08 — How will preference be separated from flight readability?

**Query:** `controlled experiment lighting scene preference task performance counterbalanced randomized within subjects night visual lighting study`.

**Evidence:** The [VUB low-light scene-preference manuscript](https://cris.vub.be/ws/portalfiles/portal/123449253/manuscript.pdf) uses randomized pairs and reverses presentation sides. A [PLOS ONE light/performance study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0164945) counterbalances order and separates performance from ratings. Neither establishes an RC-specific sample size or expected benefit.

**Decision / test:** Use coded A/B comparisons with balanced order, fixed camera/aircraft/route and matched exposure. Hide descriptive labels and the proposed winner where practical; the visible treatment itself cannot be blinded. Record cue-recognition errors/time separately from softness, brightness and atmosphere ratings. One owner's review can accept the art direction, but cannot support population-level claims.

## B. Free-resource and effect investigations

### B01 — Is a better complete mast or modular head freely available?

**Queries:** `site:sketchfab.com/3d-models free download stadium light pole floodlight CC BY`; `site:sketchfab.com/3d-models "Flood light 02" Chamod1999`.

**Evidence:** Creator listings show [Flood light 02](https://sketchfab.com/3d-models/flood-light-02-95ad365a60434015a8700efbdaa90893), Chamod1999, CC BY, about 2.8k triangles; and [Stadium Light](https://sketchfab.com/3d-models/stadium-light-realitycapture-fe1d1254cbf449849b825e5553c06e17), JFN, CC BY, a 40 m scan with about 69.2k triangles. The download API returned 401; neither archive was obtained.

**Decision / test:** Keep the already-downloaded Innerscene modular heads as the concrete baseline. Retain the smaller head as a conditional alternative; the stadium scan exceeds scale/budget. If a new archive becomes accessible, validate actual geometry, scale, material dependencies and 4.7.2 Compatibility appearance. Catalog counts and “downloadable” labels do not establish import readiness.

### B02 — Should the low lamps become visibly solar fixtures?

**Queries:** `site:sketchfab.com/3d-models "solar street light" "Download 3D Model"`; `site:sketchfab.com/3d-models "Modern LED Solar Street Light FREE Low Poly" Lady Lion Studios`.

**Evidence:** [Solar Street Light](https://sketchfab.com/3d-models/solar-street-light-5e95339b0ea94fefbd7bd661b1877e60), MamickaBeeGames, is listed CC BY, 952 triangles, untextured. [Modern LED Solar Street Light](https://sketchfab.com/3d-models/modern-led-solar-street-light-free-low-poly-1a7b3b671f1149268af9aab207e3fbee), Lady Lion Studios / LordSamueliSolo, is listed CC BY, about 3.9k triangles with PBR maps. Archives were not obtained; authentication blocked download.

**Decision / test:** Neither justifies adding tall poles. Keep the downloaded low path fixture and the requested soft solar-lamp appearance; visible photovoltaic hardware is optional only if a suitable low fixture passes intake. Inspect dimensions/materials in a daylight/night turntable before any substitution. Do not claim charging behavior, power simulation or texture-license closure from catalog metadata.

### B03 — Are alternative logs materially better than the Kenney base?

**Queries:** `site:sketchfab.com/3d-models "firewood" "CC0" logs campfire download`; `site:opengameart.org "firewood" 3D model logs CC0`; `site:opengameart.org/content/low-poly-camping-assets`.

**Evidence:** A fresh check of [TinyWorlds branches](https://opengameart.org/content/campfire-branches) confirms the missing referenced MTL. The newly downloaded [Saraskau camping assets](https://opengameart.org/content/low-poly-camping-assets), CC0, include a campfire OBJ with flat brown material. [Aparicio Silva 3D's Firewood Pile](https://sketchfab.com/3d-models/firewood-pile-game-ready-asset-393e8b83dfdc455fa4f03dbd4f116e0c) is catalog-only, CC BY, about 13.2k triangles with 2K maps.

**Decision / test:** The new comparisons do not displace Kenney. TinyWorlds fails material completeness; Saraskau is a style alternative, not demonstrated quality gain; the realistic pile exceeds the proposed 10k base target before adaptation. Compare silhouette/material completeness against Kenney in an isolated scene if a replacement is pursued. Rechecking TinyWorlds alone is not counted as another investigation.

### B04 — Can another downloaded animation avoid fractional atlas cells?

**Queries:** `site:opengameart.org fire animation sprite sheet flame seamless CC0`; `site:opengameart.org/content/animated-fire`.

**Evidence:** [BenHickling's Animated Fire](https://opengameart.org/content/animated-fire), CC0, offers integer-cell sheets; the inspected 640×384 cyan-white variant is visibly pixel-styled. [Mikodrak's Fire FX](https://opengameart.org/content/fire-fx-burning-fire-animation), CC0, was downloaded as a ZIP containing two sets of 40 transparent PNGs and previews. Inspected sample frames are 81×123; this avoids extracting fractional cells from the original tauran sheet.

**Decision / test:** Retain Mikodrak as the new turntable candidate alongside tauran. It remains low-resolution art, not automatically a realistic 3D flame. Qualify frame order/pacing and alpha on a simple presentation-clock-driven SpriteFrames probe, then evaluate layered particles over the actual logs from all relevant angles. BenHickling's inspected variant is rejected for this scene's natural flame direction.

### B05 — Is there a suitable free smoke flipbook?

**Query:** `site:opengameart.org/content smoke sprite sheet ohyhei CC0`.

**Evidence:** [ohyhei's Smoke Sprite Sheet](https://opengameart.org/content/smoke-sprite-sheet) is CC0. The retrieved 1280×1280 RGBA sheet has a 5×5 grid of 256 px cells: 21 occupied, four blank at the end of the last row. The lead inspected its puff shapes. Row-major playback coherence has not been verified.

**Decision / test:** Retain as a candidate, not a replacement for proven smoke by default. Test a low-opacity, non-emissive result, crop bounds and a 21-frame selection; blindly playing all 25 cells could introduce a gap. Reject obvious white cutouts, silhouette repetition or dark fringes. Inspect sorting against flame, aircraft and trees in Compatibility before choosing its tint/material response.

### B06 — Which spark assets actually resemble small embers?

**Queries:** `site:opengameart.org/content ember sparks particle sprites fire CC0`; `site:github.com Godot GPUParticles3D campfire sparks embers`; `site:godotengine.org ember particle campfire effect`.

**Evidence:** The official [Kenney Particle Pack](https://kenney.nl/assets/particle-pack) is CC0. Its archive was inspected; the sampled `spark_01`–`spark_07` images resemble electrical streaks, an unsuitable campfire treatment. The [CPU particle API](https://docs.godotengine.org/en/4.7/classes/class_cpuparticles3d.html) supplies lifetime/randomness and pause controls, but does not prescribe a realistic ember pattern.

**Decision / test:** Do not ship the 15 MB pack for these rejected sprites. Reuse the existing tiny soft particle profile, or a minimal untextured particle if sufficient, with sparse seeded motion and the existing 8–16 budget. No custom modeled ember prop is needed. Test visual density, pause and distance fade; do not present the artistic pattern as a combustion simulation.

### B07 — Can the fire sit on a convincing prepared ground patch?

**Queries:** `site:polyhaven.com/a/burned_ground_01 Burned Ground 01 Rob Tuytel CC0`; `site:polyhaven.com burned ground ash charred soil PBR texture`.

**Evidence:** [Poly Haven Burned Ground 01](https://polyhaven.com/a/burned_ground_01), Rob Tuytel, uses [CC0](https://polyhaven.com/license). Three actual 1K JPG maps were downloaded: diffuse, OpenGL normal and roughness, totaling 1,718,912 bytes. The source gives a 1 m material scale; the lead inspected the charred soil/organic debris appearance.

**Decision / test:** Compare a small local hearth patch using this subset, not a replacement of world terrain. Keep it within the campfire texture/draw budgets and preserve source normal orientation. Check physical UV scale, seams, edge blending, z-fighting and warm-light response in Compatibility. The files are retained research inputs; smooth blending into the existing ground remains unproved.

### B08 — Would a reusable Godot raymarched fire improve the result?

**Queries:** `site:github.com Godot fire campfire demo "Compatibility" 4.3 CC0`; `site:godotshaders.com spatial fire Godot 4 shader smoke sparks license`; `site:github.com Godot 4 "fire effect" campfire shader MIT Godot demo`.

**Evidence:** [Dari0us's Spatial Fire Raymarched](https://godotshaders.com/shader/spatial-fire-raymarched/) labels shader code CC0 and warns of GPU cost/perspective issues. The linked [example repository](https://github.com/Dari0us/Godot-Spatial-Fire-Raymarched) was downloaded and inspected: MIT license, Godot 4.5 Forward Plus configuration, shader/noise resources and bundled campfire art without separately established art provenance. Nothing was executed.

**Decision / test:** Defer this alternative; the downloaded flipbook is simpler to qualify. If sprite turntables fail, test only appropriately licensed shader code/noise in an isolated 4.7.2 Compatibility scene, with camera orbits, ground intersections and GPU timing. Do not import the demo wholesale, infer backend support from a showcase, or switch renderers. A raymarched material is also not native volumetric fog.

## C. Engine and verification investigations

### C01 — Does the exposure estimate describe the rendered spotlight?

**Query:** `site:github.com/godotengine/godot "4.7" "spot_attenuation" "scene.glsl"`; followed the pinned 4.7.2 source rather than relying on a current tutorial.

**Evidence:** [GLES3 scene shader](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/shaders/scene.glsl) applies distance decay, a smooth finite-range window and a smooth angular term. [Renderer upload](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp) sends the reciprocal of the authored angular attenuation. [SpotLight3D](https://docs.godotengine.org/en/4.7/classes/class_spotlight3d.html) distinguishes the distance exponent from the angular control. A hard cone plus unbounded inverse-square estimate omits relevant terms.

**Decision / test:** FW-68 must specify the rendered and analytic laws together. Probe radius fractions 0.1/0.5/0.9/1.01 and angle fractions 0/0.5/0.9/1.01 on neutral surfaces. Keep the surface cosine separate from scalar light transport. Compare normalized profiles before applying artistic gain; this is not a lux calibration.

### C02 — Which glow controls actually work in Compatibility?

**Query:** `site:docs.godotengine.org/en/4.7 Compatibility glow LDR threshold`.

**Evidence:** The [Environment reference](https://docs.godotengine.org/en/4.7/classes/class_environment.html) documents a reduced Compatibility implementation: `glow_strength`, per-level settings, blend modes and several other controls have no effect. `glow_intensity` remains a relevant control. An HDR-looking control name does not establish HDR scene discrimination in this pipeline.

**Decision / test:** Replace the vague “low-strength glow” experiment with an explicit `glow_intensity`/threshold probe. Use adjacent lens, white fuselage, grass and sky patches; reject glow that halos the aircraft or lifts the whole field. Compare at fixed exposure first, then both adaptation routes. Local halos remain the default if optional glow fails.

### C03 — Can a soft cone be mistaken for a soft shadow?

**Query:** `site:docs.godotengine.org/en/4.7 "shadow_filter" Compatibility PCF`.

**Evidence:** The [renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) excludes positional PCSS on Compatibility. The [pinned GLES3 renderer](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/rasterizer_scene_gles3.cpp) selects five- or thirteen-tap PCF variants by quality. This is shadow-map filtering; angular falloff is a separate operation.

**Decision / test:** Tune cone overlap with shadows off. Then compare no shadow / one head with low PCF / one head with higher PCF, using a moving aircraft and fixed thin pole. Record crawling, detached contact shadows and cost. Do not promise area-light penumbrae from `light_size`, or assume every inspector shadow control changes this backend.

### C04 — Can batching accidentally consume the light budget?

**Query:** `site:docs.godotengine.org/en/4.7 "light_cull_mask" MultiMesh lights`.

**Evidence:** [MultiMesh guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/using_multimesh.html) treats an entire MultiMesh as one visibility object. [Light3D](https://docs.godotengine.org/en/4.7/classes/class_light3d.html) selects affected visual layers with `light_cull_mask`; the renderer's local-light limits apply per mesh, not per decorative bulb.

**Decision / test:** Batch the mast by compatible material, but avoid one enormous lit batch spanning unrelated field regions. Build an overlap inventory for terrain, aircraft, veranda and fireground. Test a banked aircraft crossing every pool with all allowed lights enabled; excluded layers must not accidentally remove aircraft illumination. Unshaded marker batches remain distinct from lit hardware.

### C05 — Which transparency modes suit fire, smoke and lamp halos?

**Query:** `site:docs.godotengine.org/en/4.7 particles transparency sorting premultiplied alpha blend_add`.

**Evidence:** [Spatial shader modes](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html) distinguish additive, alpha-mix and premultiplied blending, and distinguish depth testing from depth writing. Emitting sprites and occluding smoke have different compositing requirements.

**Decision / test:** Compare additive and alpha-mix flame tongues; use alpha-mix for smoke, not luminous additive gray. Keep opaque depth testing; transparent particles normally do not write depth. Premultiplied textures require matching material treatment. Inspect against bright sky, dark trees, grass and an opaque blocker from both sides; reject black fringes, sorted-layer popping and halos visible through scenery. A shader compiling is not visual acceptance.

### C06 — How should downloaded atlases survive filtering and distance?

**Query:** `site:docs.godotengine.org/en/4.7 "Fix Alpha Border" "Mipmaps"`.

**Evidence:** [Image import documentation](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) explains alpha-border repair, matching premultiplied materials, OpenGL normal-map orientation and mipmaps. It explicitly marks `Mipmaps > Limit` unimplemented; it cannot solve atlas bleeding.

**Decision / test:** Inventory real cell bounds; compare separate-frame input or a reproducibly padded atlas. Inspect every frame and loop seam, including distant mips. Do not disable mipmaps globally to disguise one bad sheet. Track actual imported memory, including mips, and test 720p/1080p plus zoom. Preserve source pixels; conversion recipes, not hand-edited outputs, own padding and frame extraction.

### C07 — Does a fixed seed make the campfire replayable?

**Query:** `site:docs.godotengine.org/en/4.7 GPUParticles3D use_fixed_seed request_particles_process restart`.

**Evidence:** [GPUParticles3D](https://docs.godotengine.org/en/4.7/classes/class_gpuparticles3d.html) exposes fixed seeds, `restart(keep_seed)` and requested processing time with `speed_scale = 0`. Its manual `emit_particle()` method is not supported on Compatibility. A seed alone does not preserve time-varying wind inputs; that is a project-level inference.

**Decision / test:** Prefer a normal bounded emitter driven by the presentation clock. Qualify explicit processing on the pinned binary; use the CPU fallback if necessary. Save/reconstruct the inputs needed over the longest particle lifetime, or define a consistent restart policy. Compare equal simulation timestamps at 30/60/144 render FPS, pause and checkpoint restore. Do not promise identical pixels across GPU vendors.

### C08 — Will night light changes leave stale reflections?

**Query:** `site:docs.godotengine.org/en/4.7 ReflectionProbe UPDATE_ALWAYS Compatibility`.

**Evidence:** The opened [ReflectionProbe reference](https://docs.godotengine.org/en/4.7/classes/class_reflectionprobe.html) describes two probes per mesh in Compatibility and says `UPDATE_ONCE` is not refreshed merely by nearby geometry changing. Continuous refresh is expensive; probes source their environment from `WorldEnvironment`.

**Decision / test:** Coordinate with the existing lake/reflection owner. Capture Club → Airfield → Off and day → night on reflective materials. Request bounded refresh after a settled profile/time change if existing behavior leaves stale light. Do not add a continuously updated probe for flame flicker. Keep dynamic particle exclusion and existing probe capacity explicit; no promise of exact flame reflections.

### C09 — How can the new lighting cost be measured honestly?

**Queries:** `site:docs.godotengine.org/en/4.7 "Visual profiler" "Compatibility"`; `site:docs.godotengine.org/en/4.7 "get_frame_setup_time_cpu" "gpu"`.

**Evidence:** [Debugger documentation](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html) supports the Visual Profiler on Compatibility, except macOS, and requires matching viewport sizes. [RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html) distinguishes CPU rendering setup, per-viewport rendering time and GPU time. These are not total simulation frame time.

**Decision / test:** Record full-frame intervals and rendering counters separately. Use three sequential ABBA blocks (baseline/candidate/candidate/baseline), each run with 60 warmup and at least 600 samples, identical source snapshots/settings and fixed effect seeds. Save a proving image per run, report each run's percentiles and variation, and record VSync/power conditions. Do not sum CPU and GPU times into an invented frame time.

### C10 — Is parsing a GLB enough to accept the downloaded prop?

**Queries:** `site:github.com/KhronosGroup/glTF-Validator "validateBytes" "externalResourceFunction"`; followed the official `node/` files after a stale `npm/` path failed.

**Evidence:** The [Khronos validator API](https://github.com/KhronosGroup/glTF-Validator/blob/main/node/module.mjs) says external resources are not validated when the resource callback is omitted; the [official usage example](https://github.com/KhronosGroup/glTF-Validator/blob/main/node/README.md) supplies one. The already-downloaded Kenney GLB actually references an external palette PNG.

**Decision / test:** FW-67 must validate both GLB structure and dependency closure with a pinned validator version and a callback confined to the intake directory. Save full reports, resolve errors and review unsupported-extension warnings individually. Then perform a fresh native import and exported-build load. Schema success does not establish material fidelity or Compatibility rendering quality.

## Pinned engine source checks

These upstream files were downloaded as data into ignored scratch space and inspected, not compiled or executed. Documentation was also queried through Context7's Godot 4.7 branch. Source hashes let a future implementation reproduce the specific code observation even if documentation changes.

| 4.7.2-stable upstream path | SHA-256 |
| --- | --- |
| `drivers/gles3/shaders/scene.glsl` | `2c77be0c85b7ab1a85ed8009c77cdb6216f1494d43083592213ad68f9e812977` |
| `drivers/gles3/storage/light_storage.cpp` | `2aaae89b4d75abb1c91d5de3a85f094cc2d06a5f23fdcd288c78e22f3a8a3d24` |
| `drivers/gles3/rasterizer_scene_gles3.cpp` | `6d0719c9cd2caf685a9825028183bdf058081d7bc92d4b27ed2587f39b081221` |

The Signify photometry file was retained only in scratch: 249,948 bytes, SHA-256 `03aabdd85a4a67accc13d5e1457a342c8415fce278408ed07868d7cce0fe9daa`, LM-63-2002 format, catalog ID `912300060968`, with 121 vertical and 181 horizontal samples. It is reference data, not an adopted luminaire or shipped asset.

## Asset evidence retained and rejected

The [source ledger](../../../../assets/landscape/night-lighting/PROVENANCE.json) and [licenses](../../../../assets/landscape/night-lighting/LICENSES.md) own hashes and download URLs for retained art. This round adds Mikodrak's original ZIP, ohyhei's PNG and three Poly Haven JPGs: **five unmodified files, 3,245,373 bytes**. All still require native import/playback/material qualification. Only sample flame frames, not a running effect, were visually inspected.

Rejected or deferred packages remain outside the product in ignored scratch. These hashes record what was actually inspected, rather than implying that a catalog page was downloaded:

| Package / file | Bytes | SHA-256 | Disposition |
| --- | --- | --- | --- |
| TinyWorlds branches ZIP | 370,169 | `dd447be84813ca2c370b1c6890aa145a5d178208efe74c1439c6ff479f135633` | Missing referenced material; same source rechecked |
| Saraskau camping ZIP | 1,369,776 | `34b4aa55868bceea366265bffc1f07baf2c503a2d7e27a1529ef9798ef712f12` | Flat-color alternative, no demonstrated improvement |
| BenHickling `fire2_64.png` | 25,950 | `79ee9fcb1594b29e6d2cb02f03fc28a808190a52b03f760bcfe8f8a7523ac011` | Inspected cyan-white pixel variant unsuitable |
| Kenney Particle Pack ZIP | 15,001,764 | `b631d4b07f7002549fdcf155f01141ad482f79f3440e4e301eed49ce5f1d8958` | Sampled electrical sparks rejected |
| Dari0us example ZIP | 9,820,526 | `a30a3ea5f8a1b6a2266dd4b8f9f3e3066493f0063bf78a529668fa5b3445a4f9` | Backend/cost/provenance questions; not executed |

## Integration and remaining proof

| Findings | Concrete plan revision | Closing step |
| --- | --- | --- |
| A01–A03 | Reject original above-horizon broad cones; compare two four-head arrangements and quantify distance/incidence falloff | FW-68/69 |
| A04–A08 | Preserve directional cues/dark context; match brightness in the CCT sweep; separate preference from identification tasks | FW-70/71/75 |
| B01–B03 | Keep actual downloaded hardware/base; catalog-only and incomplete alternatives cannot silently replace them | FW-67 |
| B04–B08 | Add verified-source fire/smoke/ground candidates; reject electrical sparks and defer unproven raymarching | FW-67/72 |
| C01–C04 | Match analytic light law; name working glow controls; qualify PCF; preserve masks and light overlap during batching | FW-68/70/73 |
| C05–C08 | Qualify blend/filtering, seed plus input-history replay and profile-driven reflection refresh | FW-67/72/73 |
| C09–C10 | Strengthen sequential performance comparisons and external-resource validation | FW-67/74 |

Count: **A = 8, B = 8, C = 10; total = 26 distinct questions**, exceeding the requested minimum of 20. Multiple searches within one question, repeated pages and unsuccessful downloads do not inflate that count. Source inspection and local geometry calculations are completed evidence. Native material/clock/coverage/performance probes and pilot acceptance remain explicit future gates; this round establishes none of those results.

Delivery audit: all 26 IDs are unique and contain query/evidence/decision/test fields. The five edited Markdown documents have 46 valid local links/anchors and 59 distinct external URLs across the combined material (the URL count is not the investigation count). All ten retained art-file sizes and SHA-256 values match the ledger; the Kenney external palette exists; all three pinned engine-source hashes were reproduced. All 80 new flame PNGs were decoded and have 81×123 RGBA format. Targeted `git diff --check` passes. No application suite or native performance test was run for this research-only revision.
