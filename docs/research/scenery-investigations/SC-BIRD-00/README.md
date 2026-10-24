# SC-BIRD-00 · Bird resources: models, silhouettes, sounds, data and code

2026-10-24 · Source audit for the [birds plan](../../../plans/birds-sky-life.md), following the [web survey](../06-birds-sky-life-survey.md).

**Manifest:** [sources.json](sources.json) (`openrc-reference-manifest v1`, 298 files, 775 MB, all sha256 values re-verified 2026-10-24). Local copies are in the gitignored `references/birds/{models,silhouettes,audio,data,papers,code}/`. They are reference material until an asset is adopted through its pipeline with its licence and attribution. `not_downloaded` lists what sits behind logins or was too large.

**Verdicts:** *adopt* = permissive licence verified on the source page; *candidate* = usable after a review of quality, licence conflict or preview status; *restricted* = CC-BY-SA or Free Art Licence (share-alike); *reference* = study only. Spot checks: the PhyloPic API returned CC0 for a griffon silhouette; Freesound pages 830292 (CC0) and 865812 (CC BY 4.0) show the recorded licences.

## 1 · 3D models (40 files)

| Species | Source | Licence | Triangles / rig | Verdict |
| --- | --- | --- | --- | --- |
| Raven / crow | OpenGameArt, tehbucket "Raven" | CC0 | ≈ 1,190; rigged; `fly`, `stand` | adopt |
| Feral pigeon | OpenGameArt, mujtaba-io | CC0 | ≈ 1,010; rigged; flap, idle, legs-up; untextured | adopt |
| Eagle (proxy for golden/booted) | Quaternius Animal Pack Vol. 2 (OGA) | CC0 on the page; the archive ships no licence file and the Quaternius QAL (2026-08-28) claims all copies | 1,532; Flying, Idle | candidate (D10) |
| Hawk (buzzard/kestrel-like) | Poly Pizza, Sherkiz | CC-BY 3.0 | 9,956; 58 joints; Fly | candidate |
| Gulls, soaring corvid, gliding eagle, generic birds, bats (static flight poses) | Poly Pizza (Google, Mirabelle, madtrollstudio, others) | CC-BY 3.0 | 328–7,108; static | candidate |
| Generic birds, rigged | OGA pantherone (CC-BY 3.0); gonzalfj + noway basemesh (CC0) | — | 324–1,428 | candidate |
| Bats, animated | Poly Pizza Quaternius (QAL conflict); OGA rubberduck (CC0, 7,732) | — | — | candidate |
| Perched only (stork, golden eagle, heron, swallow, hawk, vulture, gull, raven) | Poly Pizza | CC-BY 3.0 | 370–1,606 | colour/head reference |

**Behind a Sketchfab login** (CC-BY, not downloaded): an animated low-poly white stork (608 faces), an animated stork (6,180), two animated low-poly gulls (580/1,078), a vulture with 3 animations (1,418), a static griffon vulture (5,621), and the OSU.Multimedia "in Flight" series of 13 animated birds (2.2–4.1k faces) including American kestrel, ring-billed gull, red-tailed hawk and osprey. The BlendSwap CC0 seagull is behind a JavaScript wall. **Correction to [survey L3](../06-birds-sky-life-survey.md#6--assets-and-audio-licences):** free animated stork, vulture, kestrel-like and gull models do exist, but only behind these walls.

**No free downloadable flying model** without a login: griffon vulture, kites, white stork, swift, swallow, grey heron, starling, jackdaw.

## 2 · Flight silhouettes (113 files)

- **PhyloPic:** 50 images as SVG + PNG (~1536 px, grey with alpha), soaring planforms from below, flapping, hovering and side views. **CC0** for griffon vulture, red and black kite, kestrel (plus a lesser-kestrel planform), white stork, golden and booted eagle, buzzard, barn swallow, common swift, herring gull, feral pigeon, raven and rook, grey heron, starling, noctule and pipistrelle. Some extra CC-BY images are attributed in the manifest. Jackdaw has perched images only.
- **Wikimedia Commons:** `RaptorialSilhouettes.svg` (Shyamal, CC BY 3.0), a single plate of below-view planforms for Gyps, Aquila, Buteo, Milvus, falcon, harrier and more. This is the best single reference for the T1 generator. Eight more plates are CC-BY-SA (restricted).

These are the generator's inputs and the owner's overlay references (SC-BIRD-03).

## 3 · Sounds (92 files, 152 MB)

Most files are Freesound HQ previews (lossy OGG, ~180 kbps); the lossless originals need a free Freesound login. **None has been auditioned:** noise, speech and aircraft are only what each page says.

| Needed sound | Adopt (Freesound ID unless noted; BY = CC BY, credit required) |
| --- | --- |
| Red kite whistle | 830292 (CC0, with a magpie); MichiJung 865812, 868531, 868738 (BY 4.0); 152301 kites mobbed by crows (BY, candidate) |
| Buzzard mew | 828438, 648430 (CC0); 91467, 355743 (BY) |
| Kestrel "kee-kee" | 516286, 352263 (BY) |
| White stork bill clatter | 705861 (CC0); 153500, 269223 (BY) |
| Swift screaming | 478455 (CC0, 140 s isolated calls); 395629 (CC0, fly-by with wingbeats); 512467, 71710 (BY) |
| Barn swallow | 865746, 640200 (CC0, reverberant spaces) |
| Black-headed gull | 554806, 848876 (CC0); Commons "Mouette rieuse" (BY 4.0); herring/lesser black-backed gull stand in for yellow-legged |
| Jackdaw, crow, raven, rook | 556235, 430052, 736975, 676040, 274439, 675958, 556221 (CC0); 361385, 381567 (BY); Commons Yellowstone raven (public domain) |
| Pigeon coo | 778143 (CC0); 45922 (BY) |
| Pigeon take-off, wing flutter | 689998, 616623, 138029, 207387, 528250 (CC0); 24639, 242405 (BY) |
| Starling murmuration rush, roost | 545942, 523896 (CC0); 167496, 114621, 254983 (BY) |
| Grey heron croak | 65264, 645157, 725824 (BY) |
| Skylark / meadow bed | 635912, 244357, 852837 (CC0) |
| Large-bird wing flap | 568810 (CC0, real bald-eagle wingbeats); 392404 (CC0, raven whoosh); 263483 (CC0, crow take-off) |
| Small-bird flutter, flock take-off | 843855, 485464, 616623 (CC0); 104934 (BY) |

**Still missing:** griffon vulture (one CC BY-SA recording only; use eagle/raven wing sounds or synthesis), yellow-legged gull (herring gull stands in), a clean isolated pigeon wing clap. The 12 bird recordings in [02 §4](../02-flora-and-ambience.md#4--ambient-sound) are still CC0.

## 4 · Numbers per species

Sources and exact rows are in each manifest entry's `extracted` field. **[calc]** = our extraction from the open CC0 track data (full circles ≤ 25 s, drift removed); **pred** = Pennycuick's 1996 wingbeat formula `f = m^0.375 g^0.5 b^(-23/24) S^(-1/3) ρ^(-3/8)` at ρ = 1.2 (from the Apache-licensed CRAN `flying` package).

| Species | Span m / area m² / mass kg | Wingbeat Hz | Speeds m/s | Thermal circling |
| --- | --- | --- | --- | --- |
| Griffon vulture | No open span/area; Rüppell's vulture proxy 2.50 / 0.892; mass 7.44 (AVONET) | pred 2.7 | circle 10.4 [calc]; inter-thermal 13–14 (Williams 2018) | **578 turns [calc]:** radius 22 m (16–30), period 12.9 s (10–19.5), bank 28° (16–34), climb 0.81 m/s (p90 2.08); bouts median 5 turns, max 20; gain median 57 m, max 508 m |
| White stork | 1.91 / 0.533 / 3.43 (Alerstam 2007 S1) | **3.14 measured** (2.98–3.32, 59 birds, accelerometer) | circle 9.37; straight glide 14.5 ground, sink 1.21 [calc] | **Weinzierl 2016 Table 1 (24,495 events):** radius 20.3 m (15.7–25.5), period 13.65 s, bank 23.8°, climb 0.92 m/s; our 53,349 circles agree (21.1 m, 15 s) |
| Red kite | 1.66 / 0.325 / 1.01 | pred 2.6 | flapping 12.0; local ground speed 7.5 [calc] | **2,169 circles [calc]:** radius 11.2 m, period 11 s, speed 6.4, bank 21°, climb 0.92 m/s; "staircase" and "spiral" soaring (Škrábal 2023) |
| Black kite | 1.52 / 0.281 / 0.815 | pred 2.8 | 11.7 | — |
| Kestrel | 0.73 / 0.071 / 0.20 | pred 5.3 | 10.1 | hover: Videler figures only (survey B6) |
| Golden eagle / booted eagle | 2.03 / 0.597 / 4.07; 1.11 / 0.200 / 0.83 | pred 3.0 / 4.2 | 11.9 / 11.3 | — |
| Common buzzard | 1.24 / 0.269 / 0.885 | pred 3.5 | 11.6–13.3 | — |
| Barn swallow | 0.32 / 0.0136 / 0.016 | **6.6 ± 3.2 measured** (downwind 7.1, upwind 6.2) | 9.5 ± 2.7 air (3.7–19.4) | **Height 0.43 ± 0.78 m, max 4.1 m**; turn radius 5.1 ± 3.0 m; peak 4.4 g; wind 0.67 ln(h) + 2.07 (Warrick 2016) |
| Common swift | 0.40 / 0.0168 / 0.038 | pred 8.1 | 9.71 ± 1.36 (straight 10.9, circling 7.7; dives 22.9) | 23 % flapping / 74 % gliding; flap bouts 0.68 s; curvature radius 19.8 m (Hedrick 2018) |
| Gulls (black-headed / lesser black-backed / herring) | 0.97 / 0.098 / 0.283; 1.34 / 0.193 / 0.719; 1.34 / 0.197 / 1.14 | pred 4.1 / 3.4 / 4.0 | 11.9 / 13.1 / 12.8; slope soaring 13.5 (10.5–17.2) [calc] | — |
| Feral pigeon | mass 0.354 (AVONET) | **5.48 ± 0.19 measured** solo, +1.0 Hz in pairs (Taylor 2019) | flock ground speed 16.7–19 [calc] | nearest neighbour 0.8–1.2 m |
| Jackdaw | 0.65 / 0.068 / 0.245 | **4.4 measured** (3.2–5.3, 3D flocks); pred 6.4 | 12.5 | nearest neighbour 1.7 m (Ling 2019) |
| Carrion crow / raven | 0.91 / 0.138 / 0.566; 1.21 / 0.247 / 1.15 | pred 5.0 | 13.5 / 14.3 | — |
| Grey heron | 1.73 / 0.372 / 1.44 | pred 2.8 | 12.5 | — |
| Starling | 0.38 / 0.0244 / 0.083 | pred 10.0 | 12.4–16.2 | murmuration: nearest neighbour 0.68–1.51 m, topological range 6.5 ± 0.9 (Ballerini 2008) |

**Caveat:** the formula overestimates corvids, pigeons and gulls (jackdaw 6.4 predicted vs 4.4 measured). Use measured values where they exist and the formula only for raptors and storks (it matches the stork measurement). Still unknown: measured griffon span/area; measured wingbeats for vulture, kite, kestrel, swift and gulls; pipistrelle numbers; starling trajectories (no public dataset).

## 5 · Datasets (all CC0 unless noted)

| Dataset | What it offers |
| --- | --- |
| AVONET (Tobias et al. 2022, CC BY 4.0) | Wing length, hand-wing index, tail and mass for every species (no span or area) |
| Alerstam et al. 2007 Protocol S1 (CC BY) | Span, wing area, mass and airspeed for 17 of our species |
| Williams et al. 2018 vultures (Movebank) | 4 Hz GPS + barometer + magnetometer near a French cliff: replayable kettles |
| Weinzierl/Flack storks (Movebank) | 1 Hz GPS of ~60 storks: the reference distribution for kettle tests |
| Škrábal 2023 red kites (Movebank); Aschwanden red kites (5 s fixes, too coarse for circles) | Kite circling and flight heights |
| Ling 2019 jackdaw 3D flocks | 60 Hz trajectories with per-bird wingbeat: corvid flock validation |
| Warrick 2016 swallows | 100 Hz 3D trajectories and a near-ground wind profile |
| Hedrick 2018 swifts | 73 tracks with flap/glide coding (MATLAB v7.3; needs `h5py`) |
| Papadopoulou 2022 pigeons; Taylor 2019 pigeons | Escape from a robotic falcon; measured wingbeats |
| Shepard 2016 gulls | Urban slope-soaring airspeeds and glide-polar inputs |

These tracks give SC-BIRD-05 a measurable acceptance test: the analytic kettle's radius, period, bank and climb distributions should fall inside the measured ranges.

## 6 · Code

| Code | Licence | Use |
| --- | --- | --- |
| three.js `webgl_gpgpu_birds` | MIT | 3-triangle bird; flap phase `+= dt + |v_xz|·dt·3 + max(v_y,0)·dt·6`, wrapped at 62.83; tip `y = sin(phase)·5` |
| **antzGames Godot VAT plugin** | MIT | Godot **4.7, GL Compatibility and HTML builds**; meshes < 8192 vertices; per-instance track via `INSTANCE_CUSTOM`; samples with `texture()` and nearest filtering. Evidence that vertex-stage texture sampling works in Compatibility on the web (plan risk 4); the T2 path |
| antzGames OpenVAT-for-Godot | MIT | Godot 4.5+ OpenVAT reader; the OpenVAT Blender baker is GPL-3.0 (tool only, engine shaders MIT) |
| 90-008/godot_boids | MIT | Rust GDExtension, f32, threaded, not timestep-based: reference only |
| Shmupo/GodotBoids | none | Reference only |
| securas particle birds, viniciusgerevini boids, gd-vat | MIT | Reference (2D, Godot 3, Forward+) |
| CRAN `flying` | Apache | Pennycuick presets and the wingbeat formula |

## 7 · Dead ends

- **Papers behind walls:** Bruderer et al. 2010 and Bruderer & Boldt 2001 (Ibis, closed); Pennycuick 1990/1996 and Videler 1991 (Cloudflare challenge); Dryad (token and proof-of-work wall; Zenodo mirrors with matching checksums used instead).
- **Audio:** xeno-canto (API v3 needs a key; bot wall; mostly NC/ND); Sonniss GDC bundle (forbids supplying the sounds as sound effects, so raw files in a public repo are excluded); Pixabay (no standalone distribution); BBC RemArc (non-commercial); Mixkit (licence text did not load); OpenGameArt seagull pack (cut from a YouTube video).
- **Models:** the Quaternius site has no bird packs; Kenney has only 2D birds; the Godot Asset Library has no bird models; the Smithsonian Open Access API returned no bird 3D models; free3d.com returned 403; an OGA "Black Bird" file is an aircraft.
- **Too large, not stored:** Harel & Nathan 2018 griffons (684 MB), a stork accelerometer file (357 MB, streamed once), a kestrel robot replica (421 MB), Taylor 2019 raw logs (606 MB), chimney swift flocks (14.3 GB), pigeon simulations (4.6 GB). URLs and sizes are in the manifest.

## 8 · Owner actions

1. **D10 Quaternius:** accept or reject the CC0 page claim against the QAL for the eagle and bat.
2. **D11 Sketchfab:** a free Sketchfab login would unlock the animated CC-BY stork, gulls, vulture and the OSU "in Flight" series for T2.
3. **D12 Audio originals:** a free Freesound login gets the lossless originals of the chosen previews before they are adopted.
4. **Listening pass:** every chosen sound needs to be heard for speech, traffic and aircraft before adoption (02 risk 6).
