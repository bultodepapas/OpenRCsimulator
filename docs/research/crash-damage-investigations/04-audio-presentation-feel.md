# 04 — Crash audio, presentation and honest game feel

**Status:** research, 2026-10-06. **Serves:** CRASH-DAMAGE-PLAN (CR- steps), G3, PERC, UI. **Read with:** [05 architecture and impact model](05-architecture-impact-model.md) (the impact event extended here), [10 audio, perception, presentation](../roadmap-investigations/10-audio-perception-presentation.md) (G3a snapshot, own propagation), [research 19: audio and pause](../menu-investigations/19-audio-ajustes-pausa.md), [audio sources note](../asset-audio-animation-sources-2026-10-06.md).

Sources are numbered [n]. "Derived" = computed here from cited inputs.

## Summary

1. **The crash is heard late.** Delay r/c (c = 343 m/s, doc 10): 87 ms at 30 m, 292 ms at 100 m, 437 ms at 150 m (derived). Lagging audio is detectable from 125 ms [1], i.e. beyond ~43 m (derived). The lag is a real field cue; syncing sound to the hit would be wrong.
2. **Distance removes the crack.** ISO 9613-1 (15 °C, 70 % RH): 8 kHz loses 9.5 dB at 100 m, 14.2 dB at 150 m; 1 kHz only 0.4–0.6 dB (derived, doc 10's formula). Spreading from 7 m adds −23 to −27 dB. A distant crash is a dull thud and a short rattle.
3. **Layer, vary, limit.** Impact = transient (material) + body (surface) + debris tail, 3 variations each, random pitch/volume, chosen by energy class [2][3]. Godot has `AudioStreamRandomizer` [4] and `AudioStreamPolyphonic` (32 voices default) [5].
4. **Map energy.** At fixed mass, amplitude ∝ Δv gives 20·log₁₀ v = 10·log₁₀ E (derived). Fleet crash energies span 79 J (Stik, 7.4 m/s) to ~17 kJ (P-51, 40 m/s): 23 dB (derived from inventory masses). Energy also picks the sample class.
5. **Samples first, modal synthesis later.** Modal synthesis is physically sound and cheap in native code (800 modes real-time on a 900 MHz Pentium III [6]); in GDScript it costs ~2.5 ms CPU per partial per second of audio (derived from doc 10's benchmark).
6. **The engine tells the story after impact.** Prop broken → over-rev; prop stopped → stall; turbine → spool-down whine of ~5–15 s (forum figures [7]). From the G2/AV-05 models, never scripted. PicaSim just fades the engine and has no crash sound [8].
7. **Silence is part of the crash.** Today the buzz is cut mid-sample (`stream_paused`) and the flight restarts after 1.5 s ([flight_session.gd](../../../app/sim/flight_session.gd), [main.gd](../../../app/main.gd)): the "oh no" moment is lost.
8. **Licences.** Kenney (CC0) [9] and Freesound filtered to CC0 [10][11] fit the MIT repo. Sonniss [12], Pixabay [13] and BBC RemArc [14] do not. Our own recordings are best.
9. **No shake in the pilot view.** A pilot 80 m away does not shake. Trauma shake [15] only in the close-up view for near impacts; hit-stop and slow motion [16][17] only in replay.
10. **Replay is nearly free and teaches.** The 240 Hz sim is deterministic and the trace holds every tick ([recorder.gd](../../../app/sim/recorder.gd)). Replay with four cameras plus a crash report ("left wingtip, 7.4 m/s, 32° bank, 0.8 s after stall, 79 J") follows RealFlight's "learn from each one" [18] and aerofly's rewind/replay [19].
11. **Haptics.** A radio in USB joystick mode is input-only; gamepad rumble (`Input.start_joy_vibration` [20]) is optional, off by default.

## Where the code stands

- Crash: any hull point at or below ground, or a gear leg past travel → `_crash()`: sim paused 1.5 s, then auto-restart. No component, surface or energy.
- Engine sound: placeholder buzz in an `AudioStreamPlayer3D`, frozen with the sim, so it stops at the visual moment (0.29 s before it would at 100 m).
- Cameras: pilot (fixed station, auto-zoom) and close-up fixed to the airplane (`C`) ([pilot_camera.gd](../../../app/render/pilot_camera.gd)). No replay cameras.
- Trace: state, loads, inputs, aux per tick; no event rows yet (doc 05 proposes them).

## 1. Impact sound design

### Layers

| Layer | Carries | Driven by | Length (estimated) |
| --- | --- | --- | --- |
| Transient (crack) | balsa crack, foam crunch, composite shatter, metal clank, prop snap | material, energy class | 20–150 ms |
| Body (thud) | grass thud, dirt thump, asphalt slap, branch whip | surface, m_eff, v_n | 100–400 ms |
| Debris tail | tumbling parts, linkage rattle | energy class, broken sections | 0.5–2 s |
| Scrape loop | sliding | v_t, normal load | while sliding |

Layering (transient, body, tail) and small timing offsets between layers set perceived size [2]. Hardness lives in contact duration: FoleyAutomatic found the force shape (1 − cos 2πt/τ) "relatively unimportant" and "hardness is conveyed well by the duration" τ [6]. Grass (soft, long τ) gets duller transients than asphalt.

### Energy → level and sample

- **Level:** gain_dB = 10·log₁₀(e_normal / E_ref), clamped to a 30 dB window, then own propagation (G3d: delay, spreading, absorption).
- **Threshold:** below a minimum energy, no impact sound (Wwise tutorials gate on minimum collision velocity [3]).
- **Classes, like velocity layers:** light / medium / heavy per material; a tap played loud sounds wrong. Boundaries (estimated, tune by ear): < 20 J, 20–300 J, > 300 J. Kinetic energy ½mv² with inventory-sum masses (derived): Stik 2.89 kg → 79 J at 7.4 m/s, 577 J at 20 m/s; Extra 3.36 kg → 672 J at 20 m/s; Avanti 11.8 kg → 21 kJ at 60 m/s; P-51 21.5 kg → 17 kJ at 40 m/s.
- **Brightness:** raise a low-pass cutoff with the class (hard hits excite higher modes); distance absorption then removes it again.

### Material × surface matrix

| Material ↓ / surface → | Grass | Dirt | Asphalt | Tree |
| --- | --- | --- | --- | --- |
| Balsa/ply (Stik, Extra) | dull crack, thud, turf tear | crack, thump, dust | sharp crack, scrape | branch whip, leaves, crack |
| Foam | soft crunch | crunch, dust | crunch, scuff | rustle |
| Composite (Avanti, P-51 cowl) | hollow thud, crack | hollow thump | shatter, gritty scrape | hollow knock |
| Metal (engine, gear) | clunk | clunk | clank, scrape | knock |
| Propeller | chop, snap | chop, snap | snap, clatter | chop |

Cells are composed at runtime from 4 transient materials × 4 surface bodies (asset budget below).

### Variation, voices, cooldown

| Need | Godot 4.7 | Setting (estimated unless cited) |
| --- | --- | --- |
| Random variation | `AudioStreamRandomizer`: `random_pitch` r → range 1/r…r; `random_volume_offset_db` → ±dB [4] | r = 1.06, ±2 dB. For replay-identical audio, pick in our code seeded by event id |
| Many one-shots | `AudioStreamPolyphonic` (32) [5]; `play_stream(stream, from_offset, volume_db, pitch_scale, playback_type, bus)` → id or −1 [21] | one player per listener |
| Voice cap | `AudioStreamPlayer3D.max_polyphony` default 1, cuts the oldest [22] | own cap ≤ 6 impact voices, steal the quietest |
| No machine-gun | — | per component: ignore hits within 60 ms unless 2× the energy; never the same variation twice in a row |
| Scrape | one looping stream per sliding body | gain ∝ v_t·√N, pitch 0.8–1.2 with v_t, 50 ms fade |

Godot's 3D attenuation and 5 kHz distance filter [22] stay off (doc 10 decision).

### Procedural or samples?

| Option | Fits | Verdict |
| --- | --- | --- |
| Layered samples | everything; ~4 MB, trivial CPU | **First** |
| Modal synthesis y(t) = Σ aₙ e^(−dₙt) sin 2πfₙt [6] | resonant parts (metal, hollow composite); weak for crushing balsa/foam. A 20-mode, 1 s ring ≈ 50 ms CPU in GDScript (derived) | Later, maybe in GDExtension (Gate P) |
| Stochastic particles (PhISEM) [23] | debris tail, gravel, foam crunch | Candidate |

A trick worth taking now: hard impacts are bursts of micro-collisions within ~15 ms; impulses at the first 4 modal frequencies sound convincing, where a single sample sounds "too clean" [6].

## 2. A crash heard from 30–150 m

| Distance | Delay | Spreading vs 7 m | Absorption 4 / 8 kHz |
| --- | --- | --- | --- |
| 30 m | 87 ms | −12.6 dB | −0.8 / −2.8 dB |
| 50 m | 146 ms | −17.1 dB | −1.3 / −4.8 dB |
| 100 m | 292 ms | −23.1 dB | −2.7 / −9.5 dB |
| 150 m | 437 ms | −26.6 dB | −4.0 / −14.2 dB |

All derived (c = 343 m/s; ISO 9613-1, 15 °C, 70 % RH; spherical spreading).

| t at 100 m | Pilot sees | Pilot hears |
| --- | --- | --- |
| 0 s | wingtip touches, cartwheel | engine at flying rpm |
| 0.29 s | parts tumbling | thud + crack; engine note changes |
| 0.3–2 s | wreck settles | rattle, scrape; engine screaming, dead or spooling down |
| 2–15 s | still wreck, dust drifting downwind | silence and wind (or the turbine winding down) |

**Engine after impact** (from the shaft/turbine models):

| Type | Prop broken | Prop stopped by ground | Evidence |
| --- | --- | --- | --- |
| Glow/gas | load gone → rpm rises until throttle/failsafe cuts | engine stalls, silence | prop strike = prop "forcibly stopped or slowed", may keep turning [24]; RC detail: owner to confirm |
| Electric | over-rev, ESC tone | ESC stall cut (estimated) | estimated |
| Turbine | — | fuel cut → spool-down whine | 5–6 s (Wren MW54), ~15 s (JetCat P-160SX, ≤ 10 s with worn bearings) [7]; JetCat ECUs run an automatic cool-down after shutdown [25] |

PicaSim (read only, PolyForm Noncommercial): a prop crash sets ω = 0 and fades the engine volume to 0 at rate 20 (≈ 50 ms, inferred); an airframe crash zeroes jet demand so it spools down at its throttle-rate limit. Its audio folder has no crash sound [8].

**Silence.** Game audio uses contrast ("to have loud, you must also have quiet"; Burnout used dynamic range as a design tool [26]). Here it is physics: the airplane stops making sound. No music sting and no UI sound for 2 s after the last debris sound; the wind bed keeps running.

**Other RC sims.** RealFlight: whole-airframe collision points, "damage ranging from minor handling problems to spectacular crashes complete with realistic sound effects", one-button reset, hold to rewind [18]. aerofly: replay slider with speed, back 10 s after a crash [19]. PicaSim: no crash sound [8]. CRRCSim: reset [27]. No user opinions on crash sounds were found.

## 3. Sound sources for an MIT repository

| Source | Licence | In the public repo? |
| --- | --- | --- |
| Kenney | CC0 [9] | Yes |
| Freesound, filter `license:"Creative Commons 0"` [11] | CC0 / CC BY / CC BY-NC per sound [10] | CC0 yes; CC BY yes with attribution; BY-NC, Sampling+ no |
| OpenGameArt | CC0, CC BY, OGA-BY, GPL per asset [28] | CC0/BY/OGA-BY yes with records; GPL avoid |
| Sonniss #GameAudioGDC | royalty-free, but may not "supply the sound effects as sound effects to any other person"; no AI training [12] | **No**: a repo distributes raw files |
| Pixabay | no attribution, no "standalone" distribution [13] | **No** |
| BBC RemArc | personal, educational, research only [14] | **No** |
| Own recordings | CC0 by choice | **Best** |

**Recording our own:** snap 3/6/10 mm balsa and 3 mm ply; crush EPO/EPP foam; crack fibreglass offcuts; break a wooden and a nylon prop; drop a metal block and a wheel leg. Drop each on short grass, long grass, dirt and asphalt from 2–3 heights; drag pieces for scrapes. Mic at 30–80 cm for impacts [29] plus a take at 2–3 m for a natural body [30]. Record 48 kHz/24-bit, deliver 48 kHz/16-bit mono: Godot sees no audible benefit above 48 kHz or 24-bit, and mono halves size [31]. Log every take in `sources.json` (who, date, object, surface, mic, distance, licence).

**Format:** WAV for short effects ("hundreds of simultaneous voices… are fine"); Ogg Vorbis for long sounds, at higher CPU cost [31].

## 4. Camera and presentation

### Shake, hit-stop, slow motion

| Effect | Pilot view | Close-up view | Replay |
| --- | --- | --- | --- |
| Shake (trauma 0–1, decaying, smooth noise [15]) | **Never** | only within ~5 m of the impact (estimated), rotational only (translation clips in 3D [15]), ≤ 0.5° | ground camera near impact |
| Hit-stop (freeze on impact [16][17]) | Never: distorts sim time | Never | optional freeze-frame on first contact |
| Slow motion | Never | Never | 0.25×/0.5×, labelled; one-shots at normal pitch at their event times |
| Auto-zoom | follows the wreck until it settles | — | free |

### Replay from the deterministic trace

- **Playback** of recorded states for viewing: exact and cheap to scrub. **Re-simulation** from a checkpoint and recorded inputs for "rewind and fly on" (RealFlight [18], aerofly [19]) and determinism checks.
- **Ring buffer:** the last 30 s = 7,200 rows; at ~40 float64 per row ≈ 2.3 MB (estimated).
- **The wreck is not deterministic:** doc 05 hands it to Godot physics. Record wreck and debris transforms and their impact events while they move; replay plays them back and never re-simulates them.
- **Cameras:** pilot, chase, ground (fixed, 1 m high, 15–20 m from the impact) and orbit. Forza-style TV auto-switching [32] can come later.
- **Audio** is re-rendered from the event list with the replay camera as listener, so delay and level follow the new position.

### Crash report (teaching tool)

On request after the wreck settles. Tacview/ACMI debriefs pair event logs with replay [33].

| Field | Example | From |
| --- | --- | --- |
| First contact | left wingtip, short grass | `component`, `surface` |
| Speed total / normal / tangential | 7.4 / 5.1 / 5.4 m/s | `v_point`, `v_n`, `v_t` |
| Attitude | bank 32° L, pitch −8°, α 14° | `attitude` |
| Energy: struck part / airplane | 6 J / 79 J | `e_normal`, `e_total` |
| Lead-up | stall 0.8 s before, throttle 20 %, full left aileron | trace, last 3 s |
| Likely cause (labelled "likely") | stall at low height in a turn | rules, evidence always shown |
| Damage | left wing panel, prop | doc 05 broken sections |
| Distance from pilot | 84 m | geometry |

Plus a 5 s strip chart (height, airspeed, α, throttle, elevator, aileron). The cause rules are tested on scripted crashes with known causes.

### Reset and repair

The session already says "continue" is never automatic; apply that to crashes. Let the wreck settle and the silence play, then offer **Reset (R)**, **Replay**, **Rewind 10 s and take over**, **Report**. A "quick reset" setting serves training. RealFlight lists the field costs of a crash ("cost you money… time to rebuild") [18]; we show such numbers only if they are real and labelled.

## 5. Honest feedback

**Convincing:** late sound; ballistic debris from the post-impact state; parts that stay where they fell; dust drifting with the wind field; the wreck settling; engine behaviour from physics; silence. **Fake:** explosions or fireballs on sport planes; sparks from wood; vanishing debris; particle fountains; live slow motion; shake at the pilot station; one identical "crash" sample; perfect sync at 150 m.

| Type | Do | Don't |
| --- | --- | --- |
| Glow/gas sport (Stik, Extra) | balsa crack, covering tear, prop snap, splinters, little dust on grass, over-rev or stall | fire, smoke, explosion, metal showers |
| Giant gas (P-51 120 cc) | heavier, lower thud, longer rattle, engine stall, a wing panel detaching whole | fireball; fire only as a modelled rare outcome (not researched, off) |
| Turbine (Avanti) | spool-down with the engine's decay, composite shatter, gear torn out; kerosene mist optional | instant turbine silence; airliner explosion |
| Electric (future) | ESC cut; delayed LiPo smoke as a data-driven option | fire on every crash |

## 6. Haptics and the radio

- EdgeTX USB joystick mode is an HID input [34]; no documented way to drive the radio's vibration from the PC was found.
- Gamepads: `Input.start_joy_vibration(device, weak 0–1, strong 0–1, duration)`; macOS needs 11+ and excludes Xbox pads over USB [20]. Strong = clamp(e_normal / E_heavy), 150–300 ms, first contact only, setting off by default. No rumble in flight: a real radio never shakes.

## Rules for this repo

**Do**
- Make impact sounds from simulation events (doc 05), emitted at source time and heard at retarded time (G3d); never from Godot collision callbacks for the flown airplane.
- Seed variation choice with `event.id`, so replays sound the same.
- Take post-impact engine behaviour from G2/AV-05 state.
- Use an `Impacts` bus under the G3i limiter, with a UI-08 volume.
- Keep a provenance record per sound file; CC0 or CC BY only.
- Prove onset at t_emit + r/c ± 1 ms, +10 dB per 10× energy, no repeated variation.

**Don't**
- Shake, freeze or slow the pilot view.
- Commit Sonniss, Pixabay, BBC or non-commercial sounds.
- Use Godot's 3D attenuation, distance filter or Doppler for impacts.
- Add fire, explosions or sparks by default.
- Auto-restart over the aftermath.

## Sound event schema

Extends doc 05's impact event. Appended to the trace event rows and to the G3a queue that audio reads.

| Field | Unit | Notes |
| --- | --- | --- |
| `id` | int | monotonic per flight; seeds variations |
| `kind` | enum | `impact`, `scrape_start/update/end`, `break`, `prop_strike`, `engine_state`, `settle` |
| `tick`, `fraction` | —, 0…1 | source time (tick + fraction)·dt; audio adds r/c |
| `point`, `v_point` | m, m/s (NED) | position; velocity for scrape Doppler |
| `normal` | unit vector | flat ground: up |
| `v_n`, `v_t` | m/s | closing and sliding speed |
| `m_eff`, `e_normal`, `e_total` | kg, J, J | doc 05 |
| `component` | id | `wing_tip_left`, `spinner`, `gear_main_left`, `prop`… |
| `material` | enum | `balsa_ply`, `foam`, `composite`, `metal`, `prop_wood/nylon/carbon`, `rubber`; per component in aircraft data |
| `surface` | id | E3a id; later `tree`, `obstacle`, `airframe` |
| `contact_time` | s | hardness τ from surface compliance [6] |
| `energy_class` | enum | `light/medium/heavy`; thresholds in data, labelled estimated |
| `broken` | section ids | triggers the debris tail |
| `engine` | rpm, state, throttle | `running`, `stalled`, `overrev`, `spooldown`, `off` |
| `origin` | enum | `sim` (deterministic) or `wreck` (Godot, recorded for replay) |

## Asset budget

WAV 16-bit mono 48 kHz = 96 kB/s (exact); Ogg Vorbis roughly 8–10× smaller (estimated).

| Set | Count | Each | Seconds | WAV |
| --- | --- | --- | --- | --- |
| Transients: 4 materials × 3 classes × 3 | 36 | 0.15 s | 5.4 | 0.52 MB |
| Bodies: 4 surfaces × 3 classes × 3 | 36 | 0.4 s | 14.4 | 1.38 MB |
| Debris tails | 6 | 1.5 s | 9 | 0.86 MB |
| Scrape loops (grass, dirt, asphalt) | 3 | 2 s | 6 | 0.58 MB |
| Prop snaps: 3 materials × 3 | 9 | 0.3 s | 2.7 | 0.26 MB |
| Tree branches and leaves | 4 | 1.5 s | 6 | 0.58 MB |
| Turbine spool-down | 0 | — | — | synthesized (G3) |
| **Total** | 94 | | 43.5 | **≈ 4.2 MB** (≈ 0.5 MB Ogg) |

## Proposed steps and where the plan put them

This research proposed eight steps under provisional IDs; [CRASH-DAMAGE-PLAN](../../CRASH-DAMAGE-PLAN.md) owns the numbering, and the mapping is:

| Proposed | Step | Proof proposed here | Plan step |
| --- | --- | --- | --- |
| CR-S1 | Sound events in trace and G3a queue | scripted wingtip crash → one `impact` with expected fields; goldens unchanged without impact | CR-01 (events), CR-25 (G3a queue) |
| CR-S2 | Impact player: layers, seeded variations, cap, cooldown, retarded time | offline render: onset ± 1 ms at 30/100/150 m; +10 ± 1 dB per 10× energy | CR-02 (v1: delay, energy classes), CR-10 (layers, materials), CR-25 (G3d propagation) |
| CR-S3 | CC0 set + `sources.json`, then own recordings | licence check fails on any non-CC0/BY entry | CR-02, CR-10 |
| CR-S4 | Post-impact engine from shaft/turbine; remove the `stream_paused` cut | trace: prop broken → rpm rises; stopped → 0; turbine follows AV-05 decay | CR-02 (no cut; v1 run-down), CR-12, CR-20 |
| CR-P1 | No auto-restart; Reset/Replay/Rewind/Report | UI test drives each; `--trace` unchanged | CR-04 (settle, then a key), CR-05 |
| CR-P2 | Replay viewer, wreck recording, 4 cameras, slow motion | replayed states and wreck transforms equal recorded | CR-24 |
| CR-P3 | Crash report, strip chart, cause rules | scripted stall, CFIT, gear-collapse crashes classified right | CR-05 |
| CR-P4 | Optional gamepad rumble | fake joypad: one call per first contact, none in flight | CR-27 |

## Sources

1. ITU-R BT.1359-1 thresholds (detectability +45/−125 ms, acceptability +90/−190 ms), summarised by Fora Soft. https://www.forasoft.com/learn/audio-for-video/articles-audio/lip-sync-itu-r-bt-1359-tolerance-windows — search result only.
2. Violet Recording, *How to make impact and hit sounds*. https://violetrecording.com/how-to-make-impact-sounds/ — search result only.
3. Audiokinetic, *Impacter and Unreal: controlling the Impacter plug-in using game physics*. https://audiokinetic.com/impacter-and-unreal-controlling-the-impacter-plug-in-using-game-physics — search result only.
4. Godot docs, `AudioStreamRandomizer`. https://docs.godotengine.org/en/4.2/classes/class_audiostreamrandomizer.html — search result only.
5. Godot docs (4.7), `AudioStreamPolyphonic`. https://docs.godotengine.org/en/stable/classes/class_audiostreampolyphonic.html — fetched.
6. K. van den Doel, P. Kry, D. Pai, *FoleyAutomatic*, SIGGRAPH 2001. https://www.cs.mcgill.ca/~kry/pubs/foleyautomatic/foleyautomatic.pdf — fetched (text extracted).
7. RCUniverse, *Spool up times on turbines?* https://www.rcuniverse.com/forum/rc-jets-120/1263498-spool-up-times-turbines.html — search result only (page 403).
8. PicaSim source (`AeroplanePhysics.cpp`, `PropellerEngine.cpp`, `JetEngine.cpp`, `data/SystemData/Audio/`). https://github.com/Rowlhouse/PicaSim — fetched via GitHub API; read only.
9. Kenney support (CC0). https://kenney.nl/support — fetched.
10. Freesound FAQ. https://freesound.org/help/faq/ — fetched.
11. Freesound API v2 filters. https://freesound.org/docs/api/resources_apiv2.html — fetched.
12. Sonniss archive and licence. https://sonniss.com/gameaudiogdc, https://sonniss.com/gdc-bundle-license/ — fetched.
13. Pixabay licence summary. https://pixabay.com/service/license-summary/ — fetched.
14. BBC Sound Effects, RemArc licence. https://sound-effects.bbcrewind.co.uk/licensing — search result only (fetch blocked).
15. S. Eiserloh, *Juicing Your Cameras With Math*, GDC 2016; summary https://www.gamedeveloper.com/programming/video-sprucing-up-cameras-with-math — fetched (summary only).
16. M. Sakurai on hit-stop (Source Gaming). https://sourcegaming.info/2015/11/11/thoughts-on-hitstop-sakurais-famitsu-column-vol-490-1/ — search result only.
17. Critical Points, *Hitstop/Hitfreeze/Hitlag*. https://critpoints.net/2017/05/17/hitstophitfreezehitlaghitpausehitshit/ — fetched.
18. Horizon Hobby, *RealFlight Help Guide* (2024). https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/1314820/manuals/RealFlight_Help_Guide.pdf — fetched (text extracted). Model Airplane News on RealFlight 6 reset/rewind, https://www.modelairplanenews.com/?p=206320 — fetched.
19. aerofly, *Instant replay, back in time and time skip*. https://www.aerofly.com/tutorials/instant-replay-back-in-time-and-time-skip/ — fetched.
20. Godot docs (4.7), `Input`. https://docs.godotengine.org/en/stable/classes/class_input.html — fetched.
21. Godot docs (4.7), `AudioStreamPlaybackPolyphonic`. https://docs.godotengine.org/en/stable/classes/class_audiostreamplaybackpolyphonic.html — fetched.
22. Godot docs (4.7), `AudioStreamPlayer3D`. https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html — fetched.
23. P. Cook, *Real Sound Synthesis for Interactive Applications* (2002). https://www.cs.princeton.edu/~prc/AKPetersBook.htm — search result only.
24. Wikipedia, *Propeller strike*. https://en.wikipedia.org/wiki/Propeller_strike — search result only.
25. JetCat P250-Pro-S product page (automatic cool-down). https://www.jetcat.de/en/productdetails/produkte/jetcat/produkte/Eingestellte%20Produkte%20Zubehoer/p250%20pro%20s/p250%20pro%20s%20rc — search result only.
26. Game Developer, *Dynamics of Narrative*. https://www.gamedeveloper.com/audio/dynamics-of-narrative — search result only.
27. Debian, `crrcsim(1)`. https://dyn.manpages.debian.org/buster/crrcsim/crrcsim.1.en.html — search result only.
28. OpenGameArt, OGA-BY 3.0 FAQ. https://opengameart.org/content/oga-by-30-faq — search result only.
29. Krotos, *Foley recording techniques*. https://krotos.studio/blog/foley-recording — search result only.
30. PremiumBeat, *Recording Foley and sound effects: the fundamentals*. https://www.premiumbeat.com/blog/recording-foley-and-sound-effects-the-fundamentals/ — search result only.
31. Godot docs, *Importing audio samples*. https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_audio_samples.html — fetched.
32. Forza support, *Replays and video clips (FM7)*. https://support.forza.net/hc/en-us/articles/360005365674-Replays-and-Video-Clips-FM7 — search result only.
33. Tacview wiki. https://tacview.fandom.com/wiki/Tacview_Wiki — search result only.
34. EdgeTX manual, advanced joystick. https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx — search result only.

Repo inputs: [doc 05](05-architecture-impact-model.md), [doc 10](../roadmap-investigations/10-audio-perception-presentation.md), [flight_session.gd](../../../app/sim/flight_session.gd), [recorder.gd](../../../app/sim/recorder.gd), [engine_sound.gd](../../../app/render/engine_sound.gd), [main.gd](../../../app/main.gd), [pilot_camera.gd](../../../app/render/pilot_camera.gd), `app/data/aircraft/*.json` (inventory masses). Scratch calculations (not in the repo): delays, spreading, ISO 9613-1 absorption, energies, asset sizes.

## Limits of this research

- No user opinions on RealFlight, aerofly or Phoenix crash sounds were found; RealFlight's text is marketing. Phoenix was not researched.
- Post-crash RC engine behaviour (over-rev vs stall, ESC cut timing) has no RC source; the owner should confirm it.
- Turbine spool-down times are forum figures seen only in a search result; AV-05's schedule wins.
- BT.1359 comes from lip-sync tests; distant impacts may tolerate more lag, which only strengthens the case for physical delay.
- Energy classes, shake limit, cooldown, voice cap and asset counts are estimates to tune by ear.
- Eiserloh's talk was not watched and Cook's book was not read; the GDScript modal cost is extrapolated, not measured.
- Fire and smoke after real crashes (kerosene, LiPo) were not researched; they stay off.
