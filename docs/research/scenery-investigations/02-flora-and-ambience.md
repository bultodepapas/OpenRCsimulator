# 02 · Flora, motion, ambient sound and birds (SC-16…SC-20)

Date: **2026-10-07**. Track: [SCENERY-PLAN](../../SCENERY-PLAN.md) (SC-). **Status: research only. Nothing was added to the repo or `app/`.**

**Question:** which free assets, tools and techniques fit wildflower meadows (SC-16), flower borders and bushes (SC-17), clock-driven motion (SC-18), ambient sound (SC-19) and a distant flock (SC-20)? Constraints: Godot 4.7.2 Compatibility; alpha-to-coverage and alpha hash do nothing, so foliage is opaque geometry or alpha scissor; no shader `TIME` (global `sim_clock`, `wind_vec`); captures repeat byte for byte ([LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md), [05](../landscape-investigations/05-grass-rendering.md), [11](../landscape-investigations/11-wind-animation-ambience.md)).

**Evidence tags:** **[V-page]** read on the live page on 2026-10-07 · **[V-archive]** read inside the downloaded archive (scratch only: `/tmp/claude-1000/scenery-research/`, not in the repo) · **[V-src]** read in the cloned source · **[U]** not verified (search summary or memory) · **[calc]** computed here · **[est]** estimate.

## Summary and recommendations

**Key numbers [calc]** (1280×720 capture, 50° vertical FOV, no auto-zoom): screen size ≈ **772 / d px per metre** at distance d.
- A 3 cm flower head is 2.3 px at 10 m, 0.8 px at 30 m and 0.1 px at 220 m.
- For an object to stay ≥ 2 px, its size must be ≥ **d / 386 m**: 0.08 m at 30 m, 0.26 m at 100 m, 0.57 m at 220 m.
- Sub-pixel opaque geometry sparkles under MSAA 2×.

| Step | Recommendation |
| --- | --- |
| **SC-16** meadows (30–220 m) | **Our own procedural meshes, no third-party flowers.** Single flowers are sub-pixel in this zone. Use "flower cushions": flat low clumps of 6–12 opaque triangles, sized ≥ d/386 m (0.1–0.6 m), with the coloured faces on top. **One mesh, one surface, one MultiMesh per chunk.** The species colour comes from `set_instance_color` (Compatibility packs it into 16-bit halves: fine for colour). Rank the instances by hash and use `visible_instance_count` for the SC-24 quality tiers. Density and size are fixed offline from the distance to the pilot. Strips go along field edges and fences (the CGS24 uncut margin). Colours are in the palette table below |
| **SC-17** borders and bushes (20–30 m behind the pilot) | **Kenney Nature Kit** (CC0 in the archive's `License.txt`): flowers have 76–154 triangles, bushes 16–104. They are opaque, with **no textures** (colours are material factors). Offline: bake each material colour into vertex colour, merge into one surface, rescale bushes ×3–5 for hedges, and remap the toy palette to the scenery atlas. KayKit Forest (CC0, one gradient atlas) is the second bush source; it has no flowers. Quaternius MegaKit flowers and bushes are **alpha-MASK cards** (900–1,690 triangles): don't use them for the opaque path |
| **SC-18** motion | A vertex shader only. Per-instance phase from a world-position hash (`MODEL_MATRIX[3].xz`) or `INSTANCE_CUSTOM.r` (16-bit is fine for a phase in [0,1)). Frequencies are multiples of 1/1024 Hz; amplitude ∝ \|`wind_vec`\| (zero until M5) plus a tiny idle term only if the owner wants it. Bending is length-preserving (GPU Gems 3 ch. 16 curve, as in [11]). **Copy no third-party shader:** every one checked uses `TIME` |
| **SC-19** ambient sound | **Hybrid, in two steps.** **SC-19a:** synthesize, in testable GDScript like `engine_sound.gd`, a seeded wind bed (filtered noise, level from V) and **pre-rendered** bird chirps (sine sweeps with AM envelopes) into an `AudioStreamWAV` once at load. This needs no download, and the unit test hashes the samples. **SC-19b (optional):** 2–4 CC0 Freesound recordings (bed, skylark, blackbird, distant crowd), converted to mono OGG ~22 kHz with offline loop crossfades and provenance per file. **No Sonniss audio:** its licence forbids redistributing the files |
| **SC-20** birds | **Our own 4–8-triangle "V" mesh** with wing flap in the vertex shader from `sim_clock`. No model is needed at these sizes. Flock motion is **analytic** (centre on a closed curve with 1/1024 Hz-multiple frequencies, plus per-bird hash offsets and small sinusoidal perturbations): same sim time, same pixels, no state. Real boids would need integrated state; use them only offline to design formations. Keep the flock ≥ 300 m away and low over the treeline: a 1 m bird at 150 m is 5 px, the same as a 1.5 m airplane at 225 m [calc] |

## 1 · Models (flowers, bushes, hedges, birds)

| Resource | URL | License (how verified) | Format / cost | Compatibility / `TIME` notes | Fit |
| --- | --- | --- | --- | --- | --- |
| **Kenney Nature Kit** 2.1 (archive dated 2020-04-29) | [kenney.nl/assets/nature-kit](https://kenney.nl/assets/nature-kit) | **CC0** [V-page] "Creative Commons CC0"; [V-archive] `License.txt`: "License: (Creative Commons Zero, CC0) … free to use in personal, educational and commercial projects … crediting … not mandatory". Zip SHA-256 `fa7974a0…c4d9d` | GLB/OBJ/FBX, 329 GLBs, 10.5 MB. Flowers ×9 (purple/red/yellow A–C): **76–154 tris**, 0.13–0.29 m tall; `plant_bush*` ×6: **16–104 tris**, 0.17–0.36 m; `grass*`, `lily*`, `plant_flat*`, crops (wheat, corn) [V-archive, own GLB parser] | **All materials `OPAQUE`, no textures**, 2–3 materials per flower (= 2–3 surfaces, so 2–3 draws per MultiMesh until merged) | **SC-17 first choice.** Bake to one surface; recolour (grass factor is teal `0.17, 0.85, 0.72`) |
| **KayKit Forest Nature Pack** | [kaylousberg.itch.io/kaykit-forest](https://kaylousberg.itch.io/kaykit-forest) | **CC0** [V-page] "Creative Commons Zero v1.0 Universal". Archive not downloaded [U for the file text] | FBX/GLTF/OBJ; FREE 100+ models; EXTRA $9.99+. One 1024² gradient atlas (downsamples to 128²) [V-page] | Trees, bushes, grass, rocks; **no flowers** listed [V-page]. Triangle counts and alpha mode [U] | SC-17 bushes/hedges if Kenney's look is too toy-like; check the archive's licence file at intake |
| **Quaternius Stylized Nature MegaKit, Standard** | [OGA](https://opengameart.org/content/stylized-nature-megakit), [quaternius.com](https://quaternius.com/packs/stylizednaturemegakit.html) | **CC0 for this exact archive** [V-archive] `License_Standard.txt`: "CC0 1.0 Universal (CC0 1.0) Public Domain Dedication". OGA field "License(s): CC0" [V-page]. Zip SHA-256 `298f6732…58c9`, **the same archive the landscape track already uses** (`assets/landscape/trees/source/upstream-provenance.json`). The site-wide QAL v1.0 (2026-08-28) forbids redistributing assets "as standalone products, asset packs" and "will not apply retroactively" [V-page] | glTF + PNG. 68/116 models. `Flower_3/4_Single` **285/642 tris**, `_Group` 755/1,690, `Clover_1/2` 379/615, `Bush_Common(_Flowers)` 900/1,368, `Petal_1…5` 13–30 [V-archive] | Flowers, clover and bushes are **`alphaMode: MASK`, cutoff 0.2, double-sided, textured**; only `Grass_*` is opaque. Scale is "Ghibli" (flowers ~2 m) [V-archive] | **Not for the opaque path.** At most a reference, or alpha-scissor clumps far away. Keep it out of hedges |
| Quaternius Ultimate Nature Pack | [quaternius.com](https://quaternius.com/packs/ultimatenature.html) | Page shows "CC0" [V-page]; no archive checked [U] | FBX/OBJ/Blend, 150 models | [U] | Only with exact-archive evidence (repo policy) |
| Poly Pizza flowers (Daisy, Bell Flower by Zsky; Flowers by Quaternius …) | [poly.pizza/search/flower](https://poly.pizza/search/flower) | Licence not shown in the listing [V-page: absent]; per-model CC0 or CC-BY [U] | GLB | [U] | Low priority; per-model check at intake |
| **Quaternius Animal Pack Vol.2** (eagle) | [OGA](https://opengameart.org/content/animated-animales-low-poly) | OGA "License(s): CC0" [V-page]; archive not read [U] | zip | Rigged/animated: skinning is too much for 1–5 px birds | Not needed for SC-20 |
| PantherOne "bird animated" | [OGA](https://opengameart.org/content/bird-animated) | **CC-BY 3.0** [V-page] | .blend | — | ❌ attribution; not needed |

## 2 · Godot tools and techniques

| Resource | URL | License (how) | Version / activity | Compatibility / `TIME` / alpha | Fit |
| --- | --- | --- | --- | --- | --- |
| **ProtonScatter** | [HungryProton/scatter](https://github.com/HungryProton/scatter) | MIT [V-src, GitHub API] | Release tag 4.0 (2023-10-23); main pushed 2026-09-27; `plugin.cfg` 4.2.0; demo project features "4.7, Forward Plus" [V-src @7198cc0] | Core `src/` has no `TIME`; `TIME` only in demo materials and `example_random_motion.gdshader`. Seeded: "Using the same seed with the same settings will produce identical results" [V-src]. Compatibility not tested [U] | Editor tool: **ideas only** (modifier stack). The plan wants offline hash placement, not a plugin |
| **Spatial Gardener** | [dreadpon/godot_spatial_gardener](https://github.com/dreadpon/godot_spatial_gardener) | MIT [V-src] | v1.4.1 (2025-03-05); "requires at least Godot v4.2" [V-src README] | No shader `TIME` in the repo [V-src grep]; octree + LOD MultiMesh painting. Compatibility [U] | ❌ painting workflow, not data-driven |
| **SimpleGrassTextured** | [IcterusGames/SimpleGrassTextured](https://github.com/IcterusGames/SimpleGrassTextured) | MIT [V-src] | v2.1.0 (2026-04-03) | Detects `gl_compatibility` [V-src]; **`sin(TIME + rand)`** in `grass.gdshaderinc`; textured **alpha scissor**; SubViewports for interaction [V-src] | ❌; copy only the global-uniform wind pattern |
| GodotGrass | [2Retr0/GodotGrass](https://github.com/2Retr0/GodotGrass) | MIT | last push 2024-08-16 | Forward+, `TIME` ([05]) | Bending reference only |
| **MultiMesh per-instance colour / custom** | [MultiMesh docs](https://docs.godotengine.org/en/stable/classes/class_multimesh.html) | — | 4.7 docs | [V-page] `set_instance_color` "multiplying the mesh's existing vertex colors"; colour and custom data are "packed into 16 bits in the Compatibility rendering method". `visible_instance_count`: "Limits the number of instances drawn" | Use colour for species, custom.r for phase. A half float has an 11-bit significand: phase step ≤ 4.9e-4, integers exact to 2048 [calc] |
| MultiMesh culling | [Using MultiMesh](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) | — | — | [V-page] "no screen or frustum culling possible for individual instances"; split into several MultiMeshes per area | Chunk as in L11a; ≤ 4 draws per the SC-16 budget |
| Distance density | Ghost of Tsushima (via [05]) | — | — | Larger far tiles with the same count [U here, from 05] | Density ∝ 1/r with size ∝ r (≥ d/386 m), fixed offline because the pilot doesn't move |

**Shader core (ours, proposal, MIT).** A one-surface flower cushion: vertex colour `a = 1` marks the head faces.
```glsl
shader_type spatial;
render_mode cull_disabled, specular_disabled;
global uniform float sim_clock;   // [0,1024) s, never TIME
global uniform vec3 wind_vec;     // m/s, zero until M5
uniform vec3 stem_color : source_color;
void vertex() {
	vec3 o = MODEL_MATRIX[3].xyz;                       // instance origin (GLES3 folds the instance into MODEL_MATRIX, [05])
	float ph = fract(sin(dot(o.xz, vec2(12.9898, 78.233))) * 43758.5453); // or INSTANCE_CUSTOM.r
	float h = clamp(VERTEX.y / 0.3, 0.0, 1.0);          // 0.3 m: cushion height (est)
	float a = length(wind_vec.xz) * 0.01;               // est; 0 at zero wind -> static bytes
	VERTEX.xz += wind_vec.xz * a * h * h * (0.8 + 0.2 * sin(6.2831853 * (0.5 * sim_clock + ph))); // 0.5 Hz = 512/1024
	NORMAL = vec3(0.0, 1.0, 0.0);
}
void fragment() { ALBEDO = mix(stem_color, COLOR.rgb, COLOR.a); } // COLOR = vertex colour × instance colour
```
Unverified: whether the vertex `COLOR.a` survives the instance multiply as intended (instance alpha = 1 keeps it). Test it in the SC-16 spike.

## 3 · Meadow references (short)

| Fact | Source |
| --- | --- |
| The 10 most common lawn flowers in No Mow May (2023): daisy, creeping buttercup, yellow rattle, bird's-foot trefoil, field forget-me-not, meadow buttercup, white clover, common mouse-ear, oxeye daisy, dandelion | [Gardens Illustrated](https://www.gardensillustrated.com/news/no-mow-may-survey-wild-lawns/) quoting Plantlife [V-page] |
| "Mowing once every 4-6 weeks will maintain a shorter, re-flowering lawn" (bugle, self-heal, red clover, lady's bedstraw) | same [V-page] |
| Hay: "must not cut hay before mid-July"; "leave an uncut margin around the edge of the field as a refuge … you can rotate this uncut area"; "turn or 'ted' the hay at least once"; "dry for at least 48 hours before baling" | [gov.uk CGS24](https://www.gov.uk/find-funding-for-land-or-farms/cgs24-haymaking-supplement-late-cut) [V-page] |
| "Leaving edges of your meadow uncut provides insects with food sources and shelter"; cut, dry, bale, then aftermath grazing | [Gwent Wildlife Trust PDF](https://www.gwentwildlife.org/sites/default/files/2024-01/Hay%20Meadow%20Management.pdf) [V-page, PDF text] |
| Common poppy: "big, saucer-shaped, scarlet blooms", June–August, up to 80 cm; verges, waste ground, "field margins" | [Wildlife Trusts](https://www.wildlifetrusts.org/node/343) [V-page] |
| Cornflower (blue), corn marigold, corn chamomile in arable margin mixes; margins 5–15 m wide | search summary [U] |
| Common knapweed (purple) is constant in lowland hay meadows; red clover common | search summary of BSBI/Wildlife Trust ID sheets [U] |
| Mediterranean spring (SC-23 theme): poppy, yellow crown daisy, chamomile | [U] (not researched) |

**Palette for SC-16/17** (sRGB, **[est]** from typical photos; replace with measured values in SC-01):

| Flower | Colour | Where |
| --- | --- | --- |
| Buttercup, dandelion, bird's-foot trefoil | `#F2D22E` (yellow) | everywhere; the most frequent |
| Daisy, oxeye daisy, white clover | `#F4F2EA` (white; yellow centre at ≤ 15 m only) | mown areas (daisy, clover), meadow (oxeye) |
| Red clover, knapweed | `#A8507E` / `#7E4A92` | meadow |
| Poppy | `#D3271C` | edges and margins only (sparse) |
| Cornflower, forget-me-not | `#4A6FD0` | rare accent |

**For an RC club [inference]:** the runway and pits are mown short (L9c stripes). The mown areas around them (every 4–6 weeks) carry daisy, clover and buttercup at low density. Long grass beyond, along fences and in an **uncut margin** around the hay meadow carries the richest strips. The hay meadow itself shows flowers until mid-July, then windrows and bales (SC-12). So the season sets which field look is consistent: flowers or bales, rarely both at full strength.

## 4 · Ambient sound

Freesound licences verified **per sound page** [V-page: the page's licence link is `creativecommons.org/publicdomain/zero/1.0`]. Downloads need a login ([11]).

| Resource | URL | License (how) | Format / length | Notes | Fit |
| --- | --- | --- | --- | --- | --- |
| Countryside Ambience Spring (Kinoton) | [514550](https://freesound.org/people/Kinoton/sounds/514550/) | CC0 [V-page] | WAV stereo 3:09 | listen first for traffic/speech | **Bed** candidate 1 |
| Summer meadow – Houghton Lodge (richwise) | [815552](https://freesound.org/people/richwise/sounds/815552/) | CC0 [V-page] | WAV stereo 1:54 | | Bed candidate 2 |
| Quiet Day at Countryside (joenmuri) | [586438](https://freesound.org/people/joenmuri/sounds/586438/) | CC0 [V-page] | WAV stereo 2:48 | | Bed candidate 3 |
| summer meadow with wind (Garuda1982) | [639459](https://freesound.org/people/Garuda1982/sounds/639459/) | CC0 [V-page] | MP3 2:13 | lossy source | backup |
| Tempelhof Skylark (Veridiansunrise) | [399221](https://freesound.org/people/Veridiansunrise/sounds/399221/) | CC0 [V-page] | WAV mono 0:50 | an airfield (Tempelhof): fitting | **Skylark** |
| Single Skylark (Kinoton) | [387426](https://freesound.org/people/Kinoton/sounds/387426/) | CC0 [V-page] | WAV stereo 1:15 | | Skylark alt |
| Windy hedgerow and skylarks (Greensand_Sound_Archive) | [569011](https://freesound.org/people/Greensand_Sound_Archive/sounds/569011/) | CC0 [V-page] | WAV stereo 9:27 | long: cut a section | Wind + lark bed |
| Zernikow Skylarks (no_use) | [194343](https://freesound.org/people/no_use/sounds/194343/) | CC0 [V-page] | AIFF stereo 1:07 | | alt |
| Blackbird song, solo (Sacha.Julien) | [725332](https://freesound.org/people/Sacha.Julien/sounds/725332/) | CC0 [V-page] | WAV stereo 1:23 | "good quality" per title | **Blackbird** (treeline, positional) |
| common blackbird_35_songs (tinga) | [195908](https://freesound.org/people/tinga/sounds/195908/) | CC0 [V-page] | WAV mono 3:36 | 35 songs: cut into one-shots | Blackbird one-shots |
| Blackbird 252 (nigelcoop), Blackbird_Sweden_long (calodas) | [116791](https://freesound.org/people/nigelcoop/sounds/116791/), [188371](https://freesound.org/people/calodas/sounds/188371/) | CC0 [V-page] | WAV 2:52 / 4:06 | | alt |
| Soft Wind in the Trees – Leaves rustle (Borgory) | [751473](https://freesound.org/people/Borgory/sounds/751473/) | CC0 [V-page] | WAV stereo 2:27 | | Wind in trees (or synth) |
| Poplar_Wind (itsnotfair); poplar + bird (felix.blume) | [521138](https://freesound.org/people/itsnotfair/sounds/521138/), [659883](https://freesound.org/people/felix.blume/sounds/659883/) | CC0 [V-page] | WAV 10:10 / 5:01 | | alt |
| Flag flapping (felix.blume ×2; RichieMcMullen) | [154794](https://freesound.org/people/felix.blume/sounds/154794/), [146272](https://freesound.org/people/felix.blume/sounds/146272/), [386796](https://freesound.org/people/RichieMcMullen/sounds/386796/) | CC0 [V-page] | WAV 1:00 / 2:01 / 0:07 | 146272 has a halyard knocking the mast: a classic club-field sound | **Flag** (positional, gain ∝ wind) |
| distant crowd noise (solarpsychedelic) | [745264](https://freesound.org/people/solarpsychedelic/sounds/745264/) | CC0 [V-page] | WAV stereo 0:25 | short loop | **Distant voices** candidate |
| crowd ext park (kyles) | [455694](https://freesound.org/people/kyles/sounds/455694/) | CC0 [V-page] | FLAC 2:04 | Quebecois voices, beer cans, city: probably too urban | backup |
| OGA "Forest bird sounds" (pauliuw) | [OGA](https://opengameart.org/content/forest-bird-sounds) | CC0 [V-page] | MP3 | lossy | backup |
| OGA "Birds and Wind – Ambient" (Spring Spring) | [OGA](https://opengameart.org/content/birds-and-wind-ambient-birds-wind-and-synth) | CC0 [V-page] | OGG loops | "drag and drop loop" | backup bed |
| **Sonniss #GameAudioGDC bundle** | [licence](https://sonniss.com/gdc-bundle-license/) | Royalty-free, **not CC0** [V-page]: may not "distribute, publish, sub-license or otherwise supply the sound effects as sound effects to any other person … on their own or as part of a … asset pack, project template, software development kit or anything similar"; also bans AI training | WAV | Raw files in a public repo = supplying them as sound effects | ❌ **reject** for this repo |
| Kenney audio | kenney.nl | CC0 (catalogue) [U for nature ambience] | OGG | No countryside or bird pack found [U] | — |

**Synthesis references (SC-19a):**
- Cornell ECE 4760 "Synthesizing Birdsong" ([page](https://people.ece.cornell.edu/land/courses/ece4760/labs/s2021/Birds-serial/Birdsong_serial.html), [V-page]): a northern cardinal song as **swoop + chirp + silence** primitives. The frequency path is a sine segment (`y = k·sin(m·x) + b`, swoop ≈ 1.74–2 kHz over 130 ms), with **1,000-sample linear attack/decay ramps** at 44 kHz to avoid clicks, using a DDS phase accumulator. This maps directly onto our phase-continuous `synthesize()` style.
- Farnell, *Designing Sound* (MIT Press 2010): procedural animal sounds in Pure Data [U: content per search summary].
- SynSing (MATLAB, open source): FM sweeps plus envelopes for animal calls [U].
- Proposal [inference]:
  - A skylark is a long, fast warble: random-walk pitch in 2–6 kHz [est, U], 50–150 ms notes from a seeded hash, rendered once to a 20–30 s `AudioStreamWAV`.
  - Wind is noise through a one-pole low-pass, gain ∝ V².
  - Filter inside the synth: bus effects fail with web sample playback ([11], #95991).
  - Avoid `AudioStreamRandomizer`: its own RNG is unseeded [U].

## 5 · Birds

| Resource | URL | License | Notes | Fit |
| --- | --- | --- | --- | --- |
| Boids (Reynolds 1987) | [red3d.com/cwr/boids](https://www.red3d.com/cwr/boids/) | — (algorithm) | [V-page] separation: "steer to avoid crowding local flockmates"; alignment: "steer towards the average heading"; cohesion: "steer to move toward the average position". Reynolds, *SIGGRAPH '87* | Offline formation design only; runtime stays analytic |
| Own "V" mesh (4–8 triangles), flap in vertex shader | — | ours | Wing beat 2–5 Hz rounded to k/1024 Hz [est, U]; dark albedo; MultiMesh, 1 draw | **SC-20** |
| Quaternius Animal Pack Vol.2 | see §1 | CC0 [V-page] | Rigged: overkill at ≤ 5 px | — |

## Risks

1. **Sub-pixel sparkle.** Flowers below ~2 px shimmer with MSAA 2× and in motion. Enforce the size ≥ d/386 m rule in a test on the placement data.
2. **Draw-call creep.** Multi-material imports (Kenney: 2–3 surfaces) multiply draws per MultiMesh. Merge into one surface offline and count draws in the capture test.
3. **Quaternius licence drift.** The QAL (2026-08-28) restricts redistributing assets as packs; the CC0 claim holds only for archive `298f6732…` with its `License_Standard.txt`. A committed source folder of many Quaternius files could look like a "pack": keep only what is used, as the landscape track does.
4. **Readability.** Saturated flowers in front of the pilot break rule 2 of the plan. Keep strong colours south (borders); meadow strips stay muted and sparse; rerun L6c.
5. **Bird confusion.** At 150 m a bird looks like a far airplane [calc]. The flock stays off in tests and captures, and the owner judges it at Gate SC.
6. **Audio content.** CC0 recordings can contain speech, traffic or aircraft. Listen to every clip and cut it, record its provenance (URL, ID, author, licence, date, SHA-256), and prefer synthesis where it is good enough.
7. **Download size.** Mono OGG at ~48 kb/s is ~0.36 MB per minute [calc]; 3–4 minutes in total is ≈ 1.5 MB.
8. **`INSTANCE_CUSTOM` and colour in Compatibility** were verified in the docs only, not measured in 4.7.2. Do a capture spike first.
9. **Not checked:** KayKit archive contents and triangle counts; Poly Pizza per-model licences; Compatibility support of ProtonScatter and Spatial Gardener.

## Sources

- Kenney Nature Kit: <https://kenney.nl/assets/nature-kit> (archive `kenney_nature-kit.zip`, SHA-256 `fa7974a0d342bfe63c38664ba9f8ec1a4aab8ea25f099bdc56870e33588c4d9d`)
- Quaternius MegaKit: <https://opengameart.org/content/stylized-nature-megakit>, <https://quaternius.com/packs/stylizednaturemegakit.html>, QAL <https://quaternius.com/license.html> (archive SHA-256 `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`)
- KayKit Forest: <https://kaylousberg.itch.io/kaykit-forest>
- Poly Pizza: <https://poly.pizza/search/flower>
- ProtonScatter <https://github.com/HungryProton/scatter> @7198cc0 · Spatial Gardener <https://github.com/dreadpon/godot_spatial_gardener> @77b822f · SimpleGrassTextured <https://github.com/IcterusGames/SimpleGrassTextured> @88ff153
- Godot: <https://docs.godotengine.org/en/stable/classes/class_multimesh.html>, <https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html>
- Meadows: <https://www.gardensillustrated.com/news/no-mow-may-survey-wild-lawns/>, <https://www.gov.uk/find-funding-for-land-or-farms/cgs24-haymaking-supplement-late-cut>, <https://www.gwentwildlife.org/sites/default/files/2024-01/Hay%20Meadow%20Management.pdf>, <https://www.wildlifetrusts.org/node/343>
- Audio: Freesound pages listed in §4; <https://sonniss.com/gdc-bundle-license/>; OGA pages in §4; <https://people.ece.cornell.edu/land/courses/ece4760/labs/s2021/Birds-serial/Birdsong_serial.html>
- Birds: <https://www.red3d.com/cwr/boids/>, <https://opengameart.org/content/animated-animales-low-poly>, <https://opengameart.org/content/bird-animated>

**Reproduce the triangle counts:** download an archive into a scratch folder and parse the glTF JSON (accessor `count / 3` per primitive, plus `alphaMode`) with `python3 -I`. The script used was 25 lines of stdlib and is not kept.
