# 10 — Engine sound, pilot perception and presentation of an RC flight from the field

**Status:** research knowledge base, 2026-10-06. **Serves:** ROADMAP G3 (engine sound driven by simulated rpm), PT4 (owner judges throttle response and sound), D7 findings (shadow, auto-zoom, readability at 100 m), Gate 2 readability ("orientation read correctly at 100 m with and without auto-zoom"), M5 camera options (VQ-03), MENU-PLAN UI-08 (HUD and volume). **Read with:** [ROADMAP](../../../ROADMAP.md), [MENU-PLAN research 19: audio, pause, volume](../menu-investigations/19-audio-ajustes-pausa.md), [screen readability (10)](../ugly-stik-investigations/10-screen-readability.md), [Stik v3 readability kit](../ugly-stik-model-v3-readability.md), [L6c readability numbers](../visual-quality-implementation/L6c/README.md), [audio sources and licences](../asset-audio-animation-sources-2026-10-06.md), [VISUAL-QUALITY-PLAN](../../VISUAL-QUALITY-PLAN.md) and [LANDSCAPE-PLAN](../../LANDSCAPE-PLAN.md) (they own sky, trees, terrain, AA presets; not repeated here), [RESEARCH.md: "Motor sound could provide feedback" and "Accessible flying"](../../../RESEARCH.md).

## Summary

- **Tones are fixed by the shaft.** 2-stroke single: f_fire = rpm/60; 4-stroke: rpm/120. Propeller blade-passing frequency BPF = B·rpm/60 (measured: 2-blade rotor, 5400 rpm → 180 Hz [4]). Stik (.61 2-stroke, 2-blade 12×6): BPF = 2·f_fire, i.e. 47/93 Hz at idle, 186/372 Hz at static full throttle.
- **Real loudness is regulated, so known:** BMFA 82 dB(A) at 7 m [2]; FAI F3A 2026 94 dB(A) at 3 m, full power, mic 30 cm high, 90° right [1]; AMA sample club rule 96/98 dB at 20 ft over sod/pavement [3]. Spreading from 82 dB(A)/7 m: ~65 dB at 50 m, 59 dB at 100 m, 53 dB at 200 m (derived).
- **Sound arrives late, physically:** 146 ms at 50 m, 292 ms at 100 m, 583 ms at 200 m. Godot 4.7.2 Doppler is a pitch scale c/(c + v·approach), clamped 1/8…8, **without propagation delay** [18]. The placeholder adds its own ~186 ms by filling the whole 4095-frame generator queue ([research 19](../menu-investigations/19-audio-ajustes-pausa.md)).
- **Recommended G3 architecture:** a per-tick read-only `SoundState` snapshot (rpm, cumulative crank angle, throttle/load, prop load, position, velocity, engine state) and a pure synthesis function rendering at **retarded time**, so delay, Doppler and spreading follow from geometry. Godot's 3D attenuation, Doppler and filter off.
- **Godot's default 3D distance filter is unphysical for us:** a 5 kHz high-shelf of (1 − gain)·(−24 dB) [17][18] gives −16 dB at 25 m with today's `unit_size` 8; ISO 9613-1 absorption at 4 kHz is −0.7 dB at 25 m, −2.7 dB at 100 m (15 °C, 70 % RH; derived [27]).
- **GDScript synthesis cost (measured, dev VM):** placeholder 14.8 ms CPU per second of audio at 22.05 kHz; wavetable 3.1 ms. Physics already uses ~120 ms/s on the same main thread, so L2 at 48 kHz needs wavetables/grains or a GDExtension.
- **G3 realism depends on G2:** the Stik's rpm follows the throttle with a lag; a dive "scream" and a windmilling dead stick need the shaft balance, which exists in `propulsion.gd` (optional) but no aircraft file declares it.
- **The display, not the eye, limits readability.** At 100 m the Stik's span subtends 52 arcmin (~52 acuity elements); on screen 11.8 px (720p/50°) or 17.6 px (1080p/50°). A 27″ monitor at 60 cm subtends ~31°, so the 50° camera shows the airplane at **0.63× real angular size**. SeligSIM's default natural view is 30° [28].
- **Auto-zoom with a pixel floor removes the looming cue:** on-screen size is constant from 39 m to 349 m at 720p (59–523 m at 1080p), so approach/recede cannot be read from size change. Compare partial zoom (size ∝ d^−0.5) and "keep ground in view" [28] at Gate 2.
- **Tiny-airplane rendering:** Compatibility has MSAA (4× today), alpha-to-coverage, SSAA; no TAA/FXAA/SMAA [23]. An edge-on wing at 100 m is <0.5 px (flicker); the prop turns 3.1 rev per 60 Hz frame (strobing). Presentation fixes, not physics.
- **Validation:** offline Goertzel checks of tones, delay, Doppler ratio and level; the owner's own .61 + 12×6 recordings (tach, 3 m/7 m/flyby) and blind ABX; the L6c blinded kit extended to **moving** clips to measure orientation-error rates per camera mode.

## Where the code stands

| Fact (2026-10-06) | File | Consequence |
| --- | --- | --- |
| Placeholder engine sound: six fixed-amplitude harmonics of rpm/60, amplitude 0.15 + 0.45·rpm/max_rpm, phase-continuous; `MIX_RATE` 22050, `buffer_length` 0.15 → real queue 4095 frames (~0.186 s) | [engine_sound.gd](../../../app/render/engine_sound.gd), [research 19](../menu-investigations/19-audio-ajustes-pausa.md) | No propeller, load, noise, air or ground effects. Pitch is stair-stepped once per render frame |
| `update()` called from `main.gd._process()` with `sim.aux[0]` (latest tick rpm), fills **all** free frames | [main.gd](../../../app/main.gd) | Latency ≈ queue length (~186 ms) plus output latency; rpm changes inside a frame are lost |
| `AudioStreamPlayer3D` child of the airplane root, `unit_size` 8, `max_db` 0; default `ATTENUATION_INVERSE_DISTANCE`, filter 5 kHz/−24 dB, Doppler off | engine_sound.gd, Godot defaults [17][18] | Spreading is physically right (−20 log₁₀(r/8)); the shelf filter is not; no delay |
| Pause: `stream_paused` every frame; `stop()+play()` on state change; engine bus not yet separate | main.gd, [DECISIONS 2026-10-06](../../../DECISIONS.md) | UI-08 plan: Master volume as linear 0–100 with a 60 dB curve, `Engine` bus prepared ([MENU-PLAN](../../MENU-PLAN.md)) |
| Tests: fundamental at rpm/60 (Goertzel), 2× rpm → 2× pitch, click-free block joins, \|x\| ≤ amp | [test_engine_sound.gd](../../../app/tests/test_engine_sound.gd) | The pure-function pattern is right; extend it |
| Propulsion: D5 lag (idle 2800, static max 11149 rpm, τ 0.25 s) for the Stik. Optional shaft balance `J·dω/dt = Q_engine − Q_prop` exists ("G2 first slice, P51-06") but no aircraft file declares `propulsion.engine.shaft` (grep) | [propulsion.gd](../../../app/physics/propulsion.gd), [aircraft_data.gd](../../../app/physics/aircraft_data.gd) | No dive "scream", no windmilling sound, no load signal yet |
| Data has no `cycle` (2/4-stroke), `cylinders` or propeller `blades` fields | [jensen_ugly_stik_60.json](../../../app/data/aircraft/jensen_ugly_stik_60.json) | Sound cannot derive its tone structure from data |
| Pilot camera: eye 1.7 m, vertical FOV 50°, `KEEP_HEIGHT`, `look_at` the airplane every frame. Auto-zoom FOV = 2·atan(span·H/(2·d·30 px)), clamped to 6°…50° | [pilot_camera.gd](../../../app/render/pilot_camera.gd), [spec.gd](../../../app/spec.gd) | Constant 30 px span between ~39 m and ~349 m at 720p (see Theory §B) |
| HUD: airspeed, altitude, AoA, throttle; F3 perf line (fps, p95, µs/tick) | [hud.gd](../../../app/render/hud.gd) | UI-08 decides visibility; the real pilot has none of these numbers |
| Shadow: planar silhouette, straight-down aid or sun direction; alpha fades 0.6 → 0.18 by 80 m | [shadow.gd](../../../app/render/shadow.gd), [test_pilot_aids.gd](../../../app/tests/test_pilot_aids.gd) | D7 finding: at 77 m from a 1.7 m eye the ground is seen at 1.3°, so the shadow is a close-pass and landing cue only |
| Renderer Compatibility, `msaa_3d=2` (= 4×), 240 Hz physics, own render interpolation, bit-identical at 30/60/144 fps | [project.godot](../../../app/project.godot) | AA options limited (Theory §D) |

Missing: propeller and airframe noise, load dependence, propagation (delay, absorption, ground reflection), engine states (start, dead stick, windmill), sound data schema, mixer buses, and a natural-FOV setting tied to the display. There is also no measurement yet of human orientation errors in motion (L6c is static and pending the owner).

## Theory and models

### A. Sound sources (RC piston, electric, turbine)

**Tone structure (exact kinematics):**

| Source | Fundamental | Harmonics | Stik numbers (derived) |
| --- | --- | --- | --- |
| Exhaust, 2-stroke, N_c cylinders evenly fired | N_c·rpm/60 | k·f, rich (pulse train) | idle 46.7 Hz, trim 5139 rpm 85.7 Hz, static max 185.8 Hz |
| Exhaust, 4-stroke | N_c·rpm/120 [7] | half orders present for N_c = 1 | Saito-type .91 at 9500 rpm: 79.2 Hz (example) |
| Propeller tones (thickness + loading) | B·rpm/60 [4][5] | m·BPF; higher orders rise with in-flow distortion [6] | 2-blade: 93 Hz idle → 372 Hz static max |
| Propeller broadband (turbulence, trailing edge) | none | band noise, rises with tip speed and loading | tip speed π·D·n = 178 m/s (M 0.52) at 11149 rpm; 199 m/s (M 0.58) at an estimated 12500 rpm in flight |
| Electric BLDC | electrical f = p_pairs·rpm/60; ESC PWM switching tones (tens of kHz in one study, 12–28 kHz range tested) [8] | slot/pole orders | 14-pole motor (7 pairs) at 10000 rpm: 1167 Hz (example) |
| Turbine (Avanti, AV-05) | shaft and compressor/turbine blade passing, mostly above several kHz | — | **unverified**, research when AV-05 starts |
| Airframe (wind) noise | broadband | — | textbook trailing-edge scaling ∝ U⁵ (+15 dB per speed doubling); **estimated**, calibrate |

Order analysis separates engine (multiples of f_fire) from prop (multiples of BPF) [5][7]; for the Stik both series interleave (BPF/f_fire = 2). P-51 120 cc, 4 blades, ~6500 rpm, 0.81 m prop (all estimated): BPF/f_fire = 4 and tip Mach ~0.80, i.e. prop-dominated; wait for P51-06 data.

**Levels and directivity.** Club and contest limits (A-weighted, near field, ground run, full throttle) are the only RC-specific calibrated numbers found:

| Rule | Limit | Geometry | Source |
| --- | --- | --- | --- |
| BMFA / UK DoE code | 82 dB(A) | 7 m, over grass, no reflectors | [2] |
| FAI F3A 2026 (5.1.x d–f) | 94 dB(A) | 3 m from centre line, mic 30 cm high at 90° right, full power, IEC 61672 class 2 meter | [1] |
| AMA sample club standard | 96 dB / 98 dB | 20 ft over sod / pavement, meter ~2 ft high in line with the prop | [3] |

These are legal bounds, not measurements of our engine. Directivity (exhaust sideways/down, prop tones near the rotor plane) is an L3 parameter.

**Load.** At constant rpm, exhaust pulse strength follows charge per cycle (≈ admitted power); prop loading noise follows thrust/torque; broadband rises with tip speed. Car games record on-load and off-load sets for this reason [14]. The shaft model's `admitted = P_idle + θ·(P_peak − P_idle)` ([propulsion.gd](../../../app/physics/propulsion.gd)) is the natural load parameter once G2 is active.

### B. Propagation from the airplane to the pilot's ears

The listener is fixed at the pilot station; the source moves at up to ~40 m/s.

1. **Retarded time.** The sound heard at time t left the source at τ with t − τ = |x_s(τ) − x_L|/c, c ≈ 343 m/s (20 °C). Because |v|/c ≤ 0.13, a fixed-point solve τ ← t − |x_s(τ) − x_L|/c converges in 2–3 iterations. Rendering the waveform at the source's crank phase θ(τ) yields delay and exact Doppler together. Straight pass, approach/recede ratio c/(c∓v): 25 m/s → ×1.079/×0.932 (2.5 semitones), 35 m/s → 3.6 semitones (derived). Godot's Doppler has no delay [18]: fine at L1, inconsistent with the 0.3–0.6 s lag heard at 100–200 m.
2. **Spreading.** Point source, free field: L(r) = L(r₀) − 20 log₁₀(r/r₀), −6 dB per doubling [3]. Godot's inverse-distance model is exactly this, referenced to `unit_size` [18].
3. **Air absorption (ISO 9613-1 [27]).** The pure-tone coefficient α(f, T, RH, p) comes from the standard's O₂/N₂ relaxation formula (implemented in the scratch calculation; valid 50 Hz–10 kHz, −20…50 °C, 10–100 % RH).

| f (Hz) | α at 15 °C, 70 % RH (dB/km) | Loss at 100 m | Loss at 200 m | α at 30 °C, 30 % RH |
| --- | --- | --- | --- | --- |
| 250 | 1.1 | 0.1 dB | 0.2 dB | 1.7 |
| 1000 | 4.1 | 0.4 dB | 0.8 dB | 6.2 |
| 2000 | 8.8 | 0.9 dB | 1.8 dB | 11.9 |
| 4000 | 26.6 | 2.7 dB | 5.3 dB | 33.0 |
| 8000 | 95.0 | 9.5 dB | 19.0 dB | 114.0 |

Only >4 kHz content (prop hiss, rattle) dulls noticeably at RC distances; a distance-dependent first-order low-pass should match within ~1 dB below 8 kHz (estimated; verify in G3d).

4. **Ground reflection.** With source height h_s and ear height h_r = 1.7 m at horizontal range d, the reflected path is longer by Δ = √(d² + (h_s+h_r)²) − √(d² + (h_s−h_r)²). Over rigid ground the first notch is at c/(2Δ), with notches spaced c/Δ. Examples: 3 m high at 30 m → Δ 0.34 m, notch 508 Hz; 30 m high at 100 m → 176 Hz; landing at 1 m, 30 m → 1.5 kHz (derived). The sweeping notches are the "phasing" heard on low passes. Grass is porous (finite impedance; Delany–Bazley flow-resistivity model is the usual start, search results only): L3 uses an image source with a frequency-dependent reflection coefficient.
5. **Pause and time scale.** The audio clock follows simulation time, so pitch scales with time scale (PicaSim multiplies frequency by its time scale [29]) and the sound freezes on pause (already done, UI-02).

**Loudness:** a game cannot reproduce absolute SPL; keep the **relative** range (≈30 dB from a 7 m taxi to 200 m) under the user's volume, with a Master limiter.

**Fidelity levels for sound:**

| Level | Content | Driven by |
| --- | --- | --- |
| L0 (today) | 6 fixed harmonics of rpm/60; Godot 3D spreading | rpm, throttle-free amplitude |
| L1 | Separate exhaust series (f_fire) and prop series (BPF) with level tables vs rpm and load; noise band; band-limited; low-latency queue; rpm interpolated per sample | `SoundState` per tick |
| L2 | Retarded-time delay + Doppler, spreading, ISO 9613-1 low-pass, airframe noise ∝ U⁵, dead-stick and windmill states, stereo panning from the azimuth to the pilot | + position, velocity, airspeed, engine state |
| L3 | Ground reflection (image source, grass impedance), source directivity, exhaust resonator/pulse model (Farnell-style procedural [9], waveguide pipes as in [11][12]) or pitch-synchronous grains from the owner's recordings (AudioMotors/REV practice [14][15]) | + calibration data |

### C. Pilot perception

**Angular size.** Visual angle θ = 2·atan(L/2d). Normal (20/20) acuity resolves about 1 arcmin of detail (textbook Snellen definition).

| Distance | Stik span 1.524 m | P-51 span 2.82 m | 720p/50° | 1080p/50° | 1080p/30° | 2160p/30° |
| --- | --- | --- | --- | --- | --- | --- |
| 50 m | 104.8′ | 193.8′ | 23.5 px | 35.3 px | 61.4 px | 122.9 px |
| 100 m | 52.4′ | 96.9′ | 11.8 px | 17.6 px | 30.7 px | 61.4 px |
| 200 m | 26.2′ | 48.5′ | 5.9 px | 8.8 px | 15.4 px | 30.7 px |

(Derived. The 720p/50° values reproduce [investigation 10](../ugly-stik-investigations/10-screen-readability.md) exactly.)

**Screen geometry.** A 16:9 monitor of diagonal D_m at viewing distance v subtends Θ_v = 2·atan(h/2v) vertically. Examples: 24″ at 0.6 m → 28.0°; 27″ at 0.6 m → 31.3°; 27″ at 0.8 m → 23.7°; 15.6″ laptop at 0.5 m → 22.0°. The **orthoscopic ("natural") FOV** equals Θ_v; then on-screen angular size equals real angular size. With the 50° camera the image is 0.44–0.63× real (minified). The pixel pitch is 1.55′ (24″ 1080p, 60 cm) to 0.87′ (27″ 2160p): only a 4K screen near 60 cm approaches eye resolution. **Two separate deficits:** minification (fixable by FOV) and resolution (fixable only by magnification, i.e. zoom). The current 50° default is wider than SeligSIM's 30° "natural view meant to emulate the real flying field" [28].

**Auto-zoom side effect (derived from `auto_fov`).** The current law sets FOV so the span is exactly 30 px whenever that is narrower than 50°. Projected size is then constant between d₀ = span·f₅₀/30 (39 m at 720p, 59 m at 1080p) and the 6° floor (349 m / 523 m). Inside that band:
- **Looming is gone.** Real time-to-contact τ = d/ḋ (e.g. 3.3 s at 100 m, 30 m/s inbound) is read from relative size change; with constant size only perspective foreshortening and background slip remain.
- **Background scale changes.** Trees and the horizon magnify up to 8× (50°/6°), so the size-distance relation to ground objects is broken, and the ground leaves the frame at altitude (D7 finding 2).

RC sims treat this as a preference: SeligSIM offers autozoom types "1" and "2" (more zoom with distance) and a manual toggle, and notes that "different simulators will use different amounts of zoom" [28] (RealFlight's autozoom options were not verified in this pass). SeligSIM 2026 makes **Keep Ground In View** (lagged, shifted pilot view whose FOV widens as the airplane climbs) its default F3 view [28]. A forum report quoted in [RESEARCH.md](../../../RESEARCH.md) notes that zoom can create a misleading perspective. A **partial** law keeps a looming signal: on-screen size s ∝ d^(−k), with k = 1 natural, k = 0 today's floor and k ≈ 0.5 a compromise. FOV = 2·atan(span·H/(2·d^(1−k)·C)), clamped. Gate 2 should rate k ∈ {1, 0.5, 0}.

**Orientation cues at small size** (ranked by the pixels they need):
1. **Colour contrast top/bottom** (one large patch each): survives at 10–15 px. L6c measured ΔE ≥ 31 everywhere, but the red wing over green grass has little luminance contrast, so 25 % of pixels in the level pose over grass are nearly invisible ([LANDSCAPE-PLAN L6c](../../LANDSCAPE-PLAN.md)). Colour alone fails colour-blind users; asymmetric **patterns** (stripes on one surface, dark underside) are better (Xbox AG 103, via [RESEARCH.md §6](../../../RESEARCH.md)).
2. **Silhouette and aspect:** span vs fuselage length and tail position. At 100 m, 1080p/50°, the fuselage depth (~0.2 m, estimated) is ~2 px.
3. **Sun shading and glints:** the lit/shaded wing flips with bank. Sun direction belongs to the landscape track (L3).
4. **Motion:** direction of travel, background slip, size change (looming), roll rate. Static kits (readability36, L6c) cannot measure these.
5. **Height cues:** shadow (close range only: at 20 m from a 1.7 m eye a 0.3 m chord shadow is 1.5 px thick at 1080p/50°; at 77 m, 0.1 px), elevation angle against the horizon, and occlusion by the treeline.
6. **Stereo depth** (real field, VR only): with an assumed stereoacuity of 20″ (textbook range, not verified here) and a 65 mm IPD, depth resolution is Δd ≈ d²·η/IPD ≈ 3.7 m at 50 m and 15 m at 100 m (derived). That is coarse but real, and a flat monitor cannot provide it.

**Literature.** Small-UAS field studies measure detection, not orientation: mean 327 m for a ScanEagle approach [33]; ~307 m and 0.065° at 50 % detection for a Mavic Air, with sun glare hurting and sound irrelevant [31][32]. No controlled RC orientation-error study was found in this pass; the project's blinded kits fill that gap.

### D. Display and motion

- **Ticks per frame:** at 240 Hz physics, 60 Hz shows 4 ticks per frame and 144 Hz shows 1.67 (derived). Render interpolation between the last two ticks adds 1–2 ticks of delay (4–8 ms) [25]. That is small next to one 60 Hz VSync frame (16.7 ms) and very small next to today's audio queue (186 ms).
- **Motion on screen:** a 30 m/s crossing at 100 m is 17.2°/s. While the camera tracks the airplane the background slips 6.2 px per frame at 60 Hz and 2.6 px at 144 Hz (1080p, 50°). Higher refresh mainly smooths the treeline and horizon, which are the speed and attitude references.
- **VSync and pacing:** Godot advises exclusive fullscreen on Windows, a VRR cap `refresh − refresh²/3600` and two swapchain images for lower latency [24]; measure on the owner's machine (VQ frame logger).
- **AA in Compatibility (4.7):** MSAA (2/4/8×), alpha antialiasing (alpha-to-coverage) and SSAA only. TAA, FSR2, FXAA and SMAA are not available [23]. MSAA handles thin geometry edges well but not sub-sample features. TAA ghosts behind moving objects [23], which is the worst case for a small, fast target (relevant only if VQ-07 Forward+ is ever adopted).
- **Sub-pixel parts:** an edge-on wing (thickness ~12 % of chord, estimated 3–4 cm) at 100 m is ~0.4 px at 1080p/50°. With 4× MSAA it shows as 0–2 samples per pixel, so it crawls and flickers in rolls. Options: (a) a minimum-thickness vertex expansion along the silhouette normal, below 1 px of projected width; (b) a dark 1 px outline pass at distance; (c) supersampling only the airplane (an off-screen narrow-FOV SubViewport composited with depth). Trees can occlude the airplane, which makes (c) the hardest.
- **Propeller:** 11149 rpm / 60 fps = 3.1 rev per frame (6.2 blade passes), so blade rendering aliases (wagon-wheel). The eye sees a translucent disc. Draw a disc with alpha-to-coverage above a blade-rate threshold; owned by the model track ([airplane.gd](../../../app/render/airplane.gd)).
- **Motion blur, depth of field, auto-exposure:** keep them off in flight ([VISUAL-QUALITY-PLAN](../../VISUAL-QUALITY-PLAN.md) already says so).

### E. Optional immersion

| Option | What it gives | Notes |
| --- | --- | --- |
| VR (OpenXR) | 1:1 angular size, stereo depth, natural head pursuit | Godot recommends the **Mobile** renderer for desktop VR [26], which conflicts with our Compatibility base. Physics must stay at 240 Hz (≥ the headset's 72–120 Hz; our interpolation already decouples) [26]. Headset resolution (~20–25 px/deg, unverified) gives about the same pixels as a 1080p/30° desktop at 100 m. Spike only |
| Head tracking (OpenTrack, ISC [30]) | Look around the field with the airplane centered, or lean | UDP output to another process. Packet format to verify in source; camera only, never sim input |
| Stereo/HRTF | Azimuth cue for where the airplane is (useful when it is out of frame) | Godot 4.7 has panning only (`panning_strength`), no built-in HRTF (inferred from [17]; unverified). Stereo panning from azimuth is enough at L2 |
| Multi-monitor | Wider peripheral field | Low value: RC is foveal tracking of one object |

## Implementation options and trade-offs

| Option | Realism | Cost | Data needs | Testability | Verdict |
| --- | --- | --- | --- | --- | --- |
| A. Keep L0 placeholder | Low | none | none | yes | Not enough for G3 |
| B. One loop pitch-shifted by rpm (PicaSim: frequency and volume linear in ω/ω_max, OpenAL Doppler, c = 330 m/s [29]) | Medium near one rpm, "chipmunk" elsewhere | very low | 1 licensed loop | weak | Fallback only |
| C. Crossfaded multi-rpm loops, on/off-load sets (car-game standard: >100 files and 3–4 days per car [14]) | High if well recorded | low CPU, high authoring | many clean recordings of our engine class | weak | No: data we don't have |
| D. Pitch-synchronous grains, one per firing cycle (AudioMotors, REV [14][15]) | High, exact timbre | medium, needs analysis tooling | 1–3 min of owner recordings with tach | medium | L3 candidate |
| E. Procedural, physically informed (harmonics + noise + resonators: Farnell [9], Baldan et al. [12], enginesound [11], engine-sim [10]) | Medium → high, parameterised by rpm/load/geometry | low (wavetable) to medium | harmonic envelope fitted to recordings | **strong** | **Spine for L1–L2** |
| F. Godot `AudioStreamPlayer3D` propagation | Spreading OK; Doppler without delay; unphysical shelf | free | — | weak | Output only, attenuation off |
| G. Own retarded-time propagation in the synth | Delay, Doppler, spreading, absorption consistent | a few sqrt per block | pilot station, trajectory history | strong | **L2** |

**Recommendation.**
1. **Contract first:** after each tick, append a `SoundState` (sim time, rpm, cumulative crank angle in revolutions, throttle, load proxy, thrust, airspeed, position and velocity NED, engine state) to a ~1 s ring buffer (240 entries). Audio never reads the live sim.
2. **Synth = pure function** `render(history, listener, t0, n, rate) → samples` (E + G), unit-tested offline; a thin realtime adapter keeps the generator queue at a target fill of ~40–60 ms (estimated) and slews its clock ≤ 0.5 % (estimated) against device drift.
3. **Tones from data:** `propulsion.engine.cycle` (2|4), `cylinders`, `propeller.blades` in the physics JSON with provenance; timbre in a separate `app/data/sound/<engine>.json` (`openrc-sound v1`).
4. **Calibrate** to the owner's recordings (option D can reuse them later).
5. **Presentation:** natural FOV from the display, auto-zoom exponent k, moving-clip orientation kit, prop disc, min-thickness/outline — one step each, each measured.

## Godot / GDScript notes

- **Determinism:** audio is output-only; `SoundState` is written after the tick and never read by physics. Golden traces and 30/60/144 fps hashes must be identical with sound on/off (cheap regression test).
- **float64:** at 11149 rpm the crank angle reaches 6.7e5 rev in 1 h; float32 (24-bit mantissa) would leave ~0.04 rev resolution. Keep it in GDScript `float`, wrap to [0, 1) only after differencing.
- **Generator (4.7.2):** `AudioStreamGeneratorPlayback` is an `AudioStreamPlaybackResampled` (source), so `pitch_scale`/Doppler changes the drain rate; queue length rounds to a power of two; underrun → zeros + `skips`; `clear_buffer()` fails while playing ([research 19](../menu-investigations/19-audio-ajustes-pausa.md)). Docs advise C#/GDExtension, or 11–22 kHz from GDScript [19].
- **Measured cost (Godot 4.7.2, scratch project, dev VM):** placeholder `synthesize` 14.8 / 27.2 ms CPU per second of audio at 22.05 / 44.1 kHz; 2048-entry wavetable with linear interpolation 3.1 / 6.3 ms. Physics ≈ 510 µs × 240 ≈ 122 ms/s on the same thread. Budget ≤ 10 ms/s in GDScript, else move the inner loop to the planned C++ GDExtension (ROADMAP rule 7).
- **Band-limiting:** drop partials above Nyquist (11 kHz at 22.05 kHz); pulse trains need BLIT/BLEP or per-octave band-limited wavetables.
- **If the 3D player stays:** `attenuation_model = ATTENUATION_DISABLED`, `attenuation_filter_cutoff_hz = 20500` (disables the shelf [17]), `doppler_tracking = DISABLED`; or a plain `AudioStreamPlayer` with our own azimuth panning.
- **Headless end-to-end test:** the Dummy driver mixes in real time (research 19); `AudioEffectCapture` on a bus copies mixed frames into a ring buffer (`get_buffer`, `get_discarded_frames`, 0.1 s default) [20], so the real output spectrum is checkable without a sound card, with loose timing. Exact checks stay offline.
- **Buses:** `default_bus_layout.tres` with `Engine`, `Airframe`, `UI` → Master (UI-08 plan) and a Master limiter (verify the 4.7 class names in ClassDB first).
- **Camera:** `keep_aspect` default `KEEP_HEIGHT` [22], so all FOVs here are vertical; recompute the natural FOV on resize/fullscreen.

## Reusable libraries, tools, code and datasets

| Name | What it gives us | License | Link | How to use here |
| --- | --- | --- | --- | --- |
| Godot AudioStreamGenerator / AudioEffectCapture / AudioStreamPlayer3D | Output, analysis tap, positional fallback | MIT (engine) | [19][20][17] | Output and headless spectrum checks |
| engine-sim (ange-yaghi) | Real-time ICE gas-dynamics → audio; reference for exhaust/pulse modelling | MIT [10] | github.com/ange-yaghi/engine-sim | Read for ideas; Windows-only C++ app, not a library; "not a scientific tool" |
| enginesound (DasEtwas) | Procedural engine synth with pipe/chamber waveguides, WAV + seamless loop export | MIT [11] | github.com/DasEtwas/enginesound | Offline generator of reference loops; port the waveguide idea; 2-stroke support not documented |
| Baldan et al. 2015, physically informed engine synthesis | Model behind [11] | paper | [12] | L3 exhaust model design |
| Farnell, *Designing Sound* (MIT Press 2010) | Procedural audio method (Pure Data), engine practicals | book | [9] | L1–L3 design patterns |
| PicaSim | Single-loop pitch/volume vs ω/ω_max, OpenAL Doppler | **PolyForm Noncommercial**: read only [29] | github.com/Rowlhouse/PicaSim @5b2c5871 | Behaviour reference; never copy code or WAVs |
| Freesound | Recordings | per file: CC0 / CC BY / CC BY-NC | [audio sources note](../asset-audio-animation-sources-2026-10-06.md) | Only CC0/CC BY, attribution kept; engine size not inferable from tags |
| Owner's recordings | Ground truth for *our* .61 + 12×6 | owner decides (CC0 recommended) | — | G3g calibration, D-option grains |
| ISO 9613-1 formula | Air absorption α(f,T,RH,p) | standard (formula widely reproduced) | [27] | Offline table → filter coefficients |
| OpenTrack | Head-tracking UDP output | ISC [30] | github.com/opentrack/opentrack | Optional camera input |
| Godot OpenXR | VR | MIT | [26] | Spike only (renderer mismatch) |
| SeligSIM camera manual | Autozoom 1/2, KGIV, 30° natural default | product docs [28] | seligsim.com | Design reference for VQ-03 / X-PERC |

## Parameters and data

| Quantity | Typical RC value | Unit | Kind | Source |
| --- | --- | --- | --- | --- |
| Stik idle / static max rpm | 2800 / 11149 | rpm | estimated / derived | aircraft JSON |
| Stik in-flight rpm (prop unloaded) | ~12000–13000 | rpm | estimated (needs G2) | this note |
| 2-stroke firing frequency | rpm/60 per cylinder | Hz | exact (kinematics) | [7] |
| BPF | B·rpm/60 | Hz | exact; measured 180 Hz at 5400 rpm, B=2 | [4] |
| 12″ tip speed at 11149 rpm | 178 (M 0.52) | m/s | derived | this note |
| Noise limit, BMFA | 82 at 7 m | dB(A) | regulatory | [2] |
| Noise limit, FAI F3A 2026 | 94 at 3 m, mic 0.3 m high | dB(A) | regulatory | [1] |
| Level at 100 m from 82 dB(A)/7 m | 59 | dB(A) | derived (spherical spreading) | [3] |
| Air absorption 4 kHz, 15 °C 70 % | 26.6 | dB/km | derived (ISO 9613-1) | [27] |
| Godot 3D shelf default | 5000 Hz, −24 dB × (1 − gain) | — | source | [18] |
| Generator queue today | 4095 frames ≈ 186 | ms | measured | research 19 |
| Synth cost (placeholder) | 14.8 per s of audio at 22.05 kHz | ms CPU | measured (dev VM) | this note |
| Electric motor tone | pole_pairs·rpm/60 | Hz | exact | [8] |
| ESC PWM tones | ~8–32 kHz (study tested 12–28) | kHz | search result, unverified range | [8] |
| Natural FOV (27″, 60 cm) | 31 | ° vertical | derived | this note |
| SeligSIM default natural FOV | 30 | ° | manual | [28] |
| Our base FOV / auto-zoom target / floor | 50 / 30 px / 6 | ° / px / ° | estimated | spec.gd |
| Stereo depth resolution at 100 m | ~15 | m | derived (assumed 20″) | this note |

## Validation

**Verification (known answers, offline, deterministic):**
1. Tones: for rpm ∈ {2800, 5139, 11149}, Goertzel power at k·f_fire (k = 1…8) and m·BPF ≥ 40 dB above (k+½)·f_fire (extends today's test).
2. Band-limit: a 22.05 kHz render matches a 96 kHz render low-passed and downsampled (no folded partials).
3. Control latency: an rpm step changes the dominant frequency within target fill + 1 block (Dummy driver); `skips == 0` over 10 s at 30/60/144 fps.
4. Retarded time: synthetic pass at 30 m/s, closest 20 m: frequency ratio c/(c∓v) ± 0.5 %; a click emitted at t₀ from 100 m starts at t₀ + 291.5 ± 1 ms; level 100 m vs 7 m = −23.1 ± 0.5 dB.
5. Absorption: 4 kHz at 200 m within 1 dB of the ISO table. 6. Ground reflection: first notch (3 m, 30 m) at 508 Hz ± 3 %.
7. Dead stick: firing harmonics ≤ −60 dB vs running; airframe noise +15.05 dB per speed doubling (50 log₁₀ 2).
8. Physics isolation: golden flights and `--trace` hashes identical with sound on/off.

**Mutations that must fail:** rpm/120 for a 2-stroke (test 1); no `/c` delay (4); flipped Doppler sign (4); fill-all queue (3); float32 crank angle (1 h phase-drift check); reading `sim.aux` live instead of the snapshot (3, stale data).

**Independent validation (real RC):**
- **Owner static recordings:** .61 + APC 12×6, 3 m (FAI geometry) and 7 m (BMFA), 90° right, 0.3 m high, over grass; idle/mid/full with an optical tach; WAV 48 kHz plus an uncalibrated A-weighted meter reading. Fit exhaust orders 1–8 and BPF orders 1–4; accept within 3 dB at 3 rpm points.
- **Owner flyby:** low pass at known speed; compare Doppler swing, level drop with distance and the notch sweep in the spectrogram.
- **Public recordings:** CC0/CC BY only, and most lack engine/prop/rpm ([audio sources note](../asset-audio-animation-sources-2026-10-06.md)): qualitative listening only.
- **Listening:** blind ABX (recording vs synth vs placeholder), 10 trials per pair, in the PT4 notes — PT4's protocol.

**Perception validation:**
- **Pixel truth:** projected span measured from rendered masks (L6c method) per camera mode at 50/100/200 m.
- **Moving-clip orientation kit:** L6c blinded design with 2 s clips; Stik at 100/150 m; bank left/right × inbound/outbound × upright/inverted; modes 50° fixed, natural FOV, auto-zoom k = 0 and 0.5. Record **error rate and response time per mode**: the Gate 2 number for "orientation read correctly at 100 m".
- **Flicker metric:** frame-to-frame variance of airplane coverage in a 2 s roll at 150 m.

## Pitfalls and risks

1. **Unphysical Godot defaults** (5 kHz shelf, Doppler without delay). *Mitigation:* disable, own propagation (G3d), tests 4–5.
2. **Audio latency hides throttle response** (186 ms queue), exactly what PT4 judges. *Mitigation:* target-fill queue, test 3.
3. **GDScript audio steals the physics budget** (same main thread). *Mitigation:* wavetables, ≤ 10 ms/s budget with a bench, GDExtension beyond.
4. **Blocked by G2:** without the shaft balance, rpm cannot rise in a dive. *Mitigation:* G3f after G2 is declared for the Stik; until then label the sound "rpm follows throttle".
5. **Sample artefacts** (formant shift, loop seams, comb filtering in crossfades of different pitch). *Mitigation:* procedural spine; later pitch-synchronous grains [15], equal-power crossfades.
6. **Licences:** CC BY-NC recordings can't ship in sellable builds; GPL code can't enter the MIT tree; PicaSim is non-commercial. *Mitigation:* CC0/CC BY, owner recordings, MIT references [10][11].
7. **Small speakers** can't play a 47 Hz idle fundamental; pitch is still heard from harmonics (missing fundamental, textbook). *Mitigation:* keep harmonics 2–8 strong; test on the owner's laptop.
8. **Clipping on near passes.** *Mitigation:* headroom, Master limiter, UI-08's 60 dB curve.
9. **Auto-zoom removes looming and rescales the scene.** *Mitigation:* exponent k, KGIV-like option, Gate 2 ratings per mode.
10. **Natural FOV depends on unknown hardware.** *Mitigation:* ask screen size and distance once, store them, show the resulting FOV.
11. **Sub-pixel wing and strobing prop** read as broken or wrong attitude. *Mitigation:* X-PERC-4/5, measured.
12. **Realtime-mixer tests flaky in CI.** *Mitigation:* exact checks offline; end-to-end checks with wide tolerances.
13. **Renderer lock-in:** VR prefers Mobile [26], TAA needs Forward+. *Mitigation:* VR as a spike; never rely on TAA for the airplane.
14. **HUD numbers build non-transferable habits** (real pilots have none). *Mitigation:* UI-08 "field" and "training" presets; owner picks the default.

## Proposed roadmap steps

| Proposed ID | Step | Proof | Depends on |
| --- | --- | --- | --- |
| G3a | `SoundState` per-tick snapshot ring buffer (rpm, cumulative crank angle float64, throttle, load proxy, thrust, airspeed, pos/vel NED, engine state); add `engine.cycle`, `cylinders`, `propeller.blades` to the data with provenance | Test: snapshot equals sim state; golden + 30/60/144 fps hashes identical with sound on/off | — |
| G3b | Low-latency adapter: queue target fill ~50 ms, rpm interpolated from the crank angle per sample, wavetable core | Dummy-driver test: rpm step → new fundamental within ≤ 70 ms of audio; `skips == 0` over 10 s at 30/60/144 fps; cost ≤ 10 ms CPU per s of audio | G3a |
| G3c | L1 spectrum: exhaust series (f_fire), prop series (BPF), noise band; level tables vs rpm/load in `openrc-sound v1` | Offline Goertzel: peaks at k·f_fire and m·BPF ≥ 40 dB above inter-harmonic; band-limit check | G3b |
| G3d | Own propagation: retarded time (delay + Doppler), spherical spreading, ISO 9613-1 low-pass, stereo pan; Godot 3D attenuation, filter and Doppler off | Synthetic pass: ratio c/(c∓v) ± 0.5 %, onset r/c ± 1 ms, −23.1 ± 0.5 dB 7→100 m, 4 kHz/200 m within 1 dB of ISO | G3c |
| G3e | Engine states: dead stick (silence + airframe noise ∝ U⁵), idle, windmill (with shaft model) | Offline: firing harmonics ≤ −60 dB when stopped; +15 dB per speed doubling | G3d, G2 for windmill |
| G3f | Load-dependent timbre from the shaft model (admitted power, prop torque) | Trace-driven render: at equal rpm, full throttle vs dive-unloaded differ by the table's dB at orders 1–4 | G2 declared for the Stik, G3c |
| G3g | Calibrate to the owner's static recordings (.61 + 12×6, 3 m and 7 m, tach) | Fitted orders 1–8 within 3 dB at 3 rpm points; recordings + licence in `research/` | G3c, owner session |
| G3h | Ground reflection (image source, grass reflection coefficient) | First notch 508 Hz ± 3 % for (3 m, 30 m); flyby spectrogram sweep matches the owner's flyby recording qualitatively | G3d |
| G3i | Buses `Engine`/`Airframe`/`UI`, limiter, UI-08 volume hooks | `AudioEffectCapture` test: bus mute → ≤ −150 dB; limiter keeps peak ≤ −1 dBFS on a 7 m pass | UI-08 |
| G3j | Owner blind ABX (synth vs recording vs placeholder) = PT4 sound protocol | ABX results recorded in PT4 notes | G3g |
| X-PERC-1 | Natural FOV: settings for screen diagonal + viewing distance → orthoscopic vertical FOV; option "natural" vs 50° | Pure-function test vs the table above; capture span px matches prediction ± 1 px | UI-07 |
| X-PERC-2 | Auto-zoom exponent k (1, 0.5, 0) and a KGIV-like "keep ground in view" variant (VQ-03 scope) | Test: on-screen size ∝ d^(−k) within 5 % from 20–300 m; ground row stays in frame for the KGIV variant | X-PERC-1, VQ-03 |
| X-PERC-3 | Moving-clip blinded orientation kit (L6c design, 2 s clips, 4 camera modes) | Owner session: error rate and response time per mode recorded (Gate 2 number) | X-PERC-2, L6c |
| X-PERC-4 | Distance aid for sub-pixel parts: min-thickness or 1 px outline beyond a distance | Flicker metric in a 150 m roll reduced ≥ 50 %; mean size change ≤ 1 px | VQ-01b |
| X-PERC-5 | Prop disc above a blade-rate threshold (with the model track) | Captures at 30/60/144 fps show no stroboscopic blade pattern; disc alpha documented | model track |
| X-PERC-6 | Accessibility: optional orientation glyph near the airplane and pattern-based top/bottom livery variant | UI test toggles it; `--trace` identical; X-PERC-3 error rate with/without | X-PERC-3 |
| X-PERC-7 | Frame pacing on the owner's machine: 60/144 Hz, VSync modes, swapchain 2/3 | frametimes v2 logs: p95 and judder recorded per mode | VQ-01b |
| X-PERC-8 | Head-tracking spike (OpenTrack UDP → camera only) | Recorded UDP stream replays to the same camera path; sim trace unchanged | X-PERC-1 |
| X-PERC-9 | VR spike (OpenXR, pilot station, world scale 1) in a scratch branch | Runs at headset refresh with 240 Hz physics; owner rating; renderer decision recorded | X-PERC-3 |

## Decisions to take now

1. **Audio reads snapshots, never the live sim** (G3a contract). Deciding later would mean refactoring `main.gd` again and risking determinism. *Recommended: adopt now.*
2. **We own propagation** (delay, Doppler, spreading, absorption) and turn Godot's 3D attenuation, filter and Doppler off. *Recommended.* Mixing both models produces double attenuation or double Doppler.
3. **Tone structure lives in physics data** (`cycle`, `cylinders`, `blades`), timbre in a separate `openrc-sound v1` file with provenance. *Recommended:* the blade count also matters for the P-51 visual and prop-disc work.
4. **Sample rate:** 22.05 kHz while in GDScript (L1), 48 kHz when the inner loop moves to GDExtension (L2+). Decide now that the synth API takes `rate` as a parameter (it already does).
5. **Base FOV:** keep 50° as default until Gate 2, but add "natural FOV" (X-PERC-1) and let Gate 2 choose. **Owner decision.**
6. **Keep the airplane at physical size** (no mesh up-scaling at distance), as investigation 10 recommended. Only outline/min-thickness aids, labelled. **Owner decision.**
7. **Recordings policy:** the owner's own recordings, licence CC0 (or CC BY), stored with engine, prop, rpm, mic geometry and date. **Owner decision.**
8. **HUD default for "field" realism** (UI-08): off or minimal. **Owner decision.**

## Sources

1. FAI CIAM, *Sporting Code Section 4, Volume F3 Aerobatics (F3A), 2026 edition, V1 effective 1 Jan 2026*, §5.1 noise rules, 2026. https://cia.fai.org/sites/default/files/document/file/SC4_volume_CIAM_F3A_2026.pdf — fetched (PDF text read).
2. BMFA Members' Handbook, "An introduction to the Department of the Environment noise code" (82 dB(A) at 7 m). https://handbook.bmfa.org/?p=4547 — fetched.
3. Academy of Model Aeronautics, *AMA Sound/Noise Abatement Recommendations* (doc 927). https://Modelaircraft.Org/sites/default/files/927.pdf — fetched (PDF text read).
4. Zawodny N.S., Boyd D.D., Cabell R.H. (NASA LaRC), *Combined Experimental and Computational Aeroacoustic Analysis of an Isolated UAV-Scale Propeller*, Acoustics TWG 2015 (posted 2016). https://ntrs.nasa.gov/api/citations/20160007024/downloads/20160007024.pdf — fetched.
5. Zawodny N.S., Boyd D.D., *Acoustic Characterization and Prediction of Representative, Small-Scale Rotary-Wing UAS Components*, NASA, 2016. https://ntrs.nasa.gov/citations/20160009054 — search result only.
6. *An experimental investigation on the effect of in-flow distortions of propeller noise*, Applied Acoustics, 2023. https://www.sciencedirect.com/science/article/pii/S0003682X23004802 — search result only.
7. US Patent 10253716, *Engine analysis and diagnostic system* (2-stroke firing once per revolution, 4-stroke every second; engine orders). https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/10253716 — search result only.
8. *Analysis of the Effect of Switching Frequency on Acoustic Noise in External Rotor Brushless DC Motors*, Bursa Technical University repository. https://acikerisim.btu.edu.tr/items/cbe3e6ca-6be0-4bb1-9aaf-73a0bc1f7f5e — search result only. Also Gieras J.F., electrical machine noise sources: https://yadda.icm.edu.pl/baztech/element/bwmeta1.element.baztech-article-BAT1-0035-0064/c/Gieras.pdf — search result only.
9. Farnell A., *Designing Sound*, MIT Press, 2010. https://mitpressbookstore.mit.edu/book/9780262014410 — search result only.
10. Yaghi A. (AngeTheGreat), *engine-sim*, MIT licence. https://github.com/ange-yaghi/engine-sim — fetched.
11. DasEtwas, *enginesound* (Rust, MIT). https://github.com/DasEtwas/enginesound/ — fetched.
12. Baldan S., Lachambre H., Delle Monache S., Boussard P., *Physically informed car engine sound synthesis for virtual and augmented environments*, 2015. https://www.researchgate.net/publication/280086598_Physically_informed_car_engine_sound_synthesis_for_virtual_and_augmented_environments — cited by [11], not fetched.
13. Audiokinetic, *Engine Sound Modeling: From Sampling to Granular Synthesis in Wwise*. https://www.audiokinetic.com/engine-sound-modeling-from-sampling-to-granular-synthesis-in-wwise — search result only (HTTP 403).
14. Designing Sound, *Vehicle Engine Design: Project CARS, Forza Motorsport 5 and REV*, 2014. https://designingsound.org/2014/08/11/vehicle-engine-design-project-cars-forza-motorsport-5-and-rev/ — fetched.
15. MCV/Develop, *How to make racing car engines roar using AudioMotors FMOD*. https://www.mcvuk.com/development/how-to-make-racing-car-engines-roar-using-audiomotors-fmod — fetched.
16. Imphenzia, *That's Racing devlog: Engine Audio*. https://imphenzia.itch.io/thats-racing/devlog/37275/engine-audio — fetched.
17. Godot Engine docs 4.7, *AudioStreamPlayer3D*. https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html — fetched.
18. Godot Engine source, `scene/3d/audio_stream_player_3d.cpp` and `.h`, tag 4.7.2-stable (attenuation formulas, shelf filter, Doppler c = 343, clamp 1/8–8); `servers/audio/effects/audio_stream_generator.h` (resampled playback). https://github.com/godotengine/godot/blob/4.7.2-stable/scene/3d/audio_stream_player_3d.cpp — fetched (raw).
19. Godot Engine docs 4.7, *AudioStreamGenerator*. https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html — fetched.
20. Godot Engine docs 4.7, *AudioEffectCapture*. https://docs.godotengine.org/en/4.7/classes/class_audioeffectcapture.html — fetched.
21. Godot Engine docs, *Audio streams* (Doppler setup). https://docs.godotengine.org/en/stable/tutorials/audio/audio_streams.html — fetched (page marked not yet updated for 4.7).
22. Godot Engine docs 4.7, *Camera3D*. https://docs.godotengine.org/en/4.7/classes/class_camera3d.html — fetched.
23. Godot Engine docs 4.7, *3D antialiasing*. https://docs.godotengine.org/en/4.7/tutorials/3d/3d_antialiasing.html — fetched.
24. Godot Engine docs 4.7, *Jitter, stutter and input lag*. https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html — fetched.
25. Godot Engine docs 4.7, *Physics interpolation: introduction*. https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/physics_interpolation_introduction.html — fetched.
26. Godot Engine docs 4.7, *XR* index and *Setting up XR*. https://docs.godotengine.org/en/4.7/tutorials/xr/setting_up_xr.html — fetched.
27. ISO 9613-1:1993, *Acoustics — Attenuation of sound during propagation outdoors — Part 1: Calculation of the absorption of sound by the atmosphere*. https://www.iso.org/standard/17426.html — search result only (formula applied from the standard's published equations; not purchased).
28. Selig M. et al., *SeligSIM manual, ch. 19 Camera Views* (autozoom 1/2, Keep Ground In View, 30° natural default). https://www.seligsim.com/manual/cameras.html — fetched.
29. Rowlhouse D., *PicaSim* source, commit 5b2c5871 (`PropellerEngine.cpp`, `AudioManager.cpp`), PolyForm Noncommercial 1.0.0. https://github.com/Rowlhouse/PicaSim — fetched (cloned, read only).
30. opentrack project, *opentrack* (ISC licence; output protocols). https://github.com/opentrack/opentrack — fetched.
31. *Distance and Visual Angle of Line-of-Sight of a Small Drone*, Applied Sciences 10(16):5501, 2020. https://doi.org/10.3390/app10165501 — search result only (HTTP 403 on fetch).
32. FAA CAMI, *A Review of Research Related to Unmanned Aircraft System Visual Observers*, 2014. https://www.faa.gov/sites/faa.gov/files/data_research/research/med_humanfacs/oamtechreports/201409.pdf — search result only.
33. *Visual observer effectiveness* (ScanEagle approaches, mean detection 327 m), International Journal of Aviation Sciences 1(1), 2016. https://www.faasafety.gov/files/gslac/library/documents/2022/Mar/339469/visual%20observer%20effectiveness%20igdor.pdf — search result only; the attribution of the 327 m figure to this paper is from the search snippet, unverified.
34. *Line-of-sight in operating a small unmanned aerial vehicle: How far can a quadcopter fly in line-of-sight?*, Applied Ergonomics, 2018. https://www.sciencedirect.com/science/article/abs/pii/S0003687018305039 — search result only.
35. *Measurement of noise and its correlation to performance and geometry of small aircraft propellers*, EPJ Web of Conferences (EFM 2016). https://www.epj-conferences.org/articles/epjconf/pdf/2016/09/epjconf_efm2016_02112.pdf — search result only (HTTP 403).

Repo sources: [research 19 (audio, pause)](../menu-investigations/19-audio-ajustes-pausa.md), [investigation 10 (screen readability)](../ugly-stik-investigations/10-screen-readability.md), [Stik v3 readability](../ugly-stik-model-v3-readability.md), [L6c](../visual-quality-implementation/L6c/README.md), [audio sources note](../asset-audio-animation-sources-2026-10-06.md), [RESEARCH.md](../../../RESEARCH.md). Scratch calculations (not in the repo): ISO 9613-1 absorption, spreading, Doppler, ground-reflection notches, visual angles and pixels, auto-zoom plateau, and a GDScript synthesis benchmark on Godot 4.7.2 (dev VM, load average ~2.7 on 12 cores).
