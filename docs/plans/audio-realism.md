# Audio realism plan: glitches, engine voices and the jet

**Date:** 2026-10-13. **Status:** decisions D1–D6 taken (delegated); AUD-06 bench, AUD-07a–e and the first turbine slice AUD-10a delivered ([evidence](../research/audio/AUD-06/README.md)); next AUD-09 (engine banks) and AUD-10b. **Prefix:** AUD- (continues AUD-01…05). **Parent:** [AUDIO-PLAN](../AUDIO-PLAN.md). When this plan is complete, consolidate it into the parent guide and delete this file.
**Owner:** audio track. **Owns:** `app/audio/`, `app/assets/audio/soundscape/`, `tools/audio/`, `app/tests/test_soundscape.gd`, `app/tests/test_wildlife.gd`, `research/audio/`, `docs/research/audio/`.
**Coordinated, not owned:** engine RPM after shutdown in `app/sim/flight_session.gd` and `app/physics/turbine.gd` (propulsion/Avanti owners); the `_engine_audio` alias and camera-cut seam in `app/main.gd` (main line); listener rules for new cameras (CAM track, [camera views](camera-views.md)); crash one-shots and the crash bus in `app/render/crash/` (crash track); volume sliders (menu track). The legacy G3b engine (`app/render/engine_*.gd`) stays as is.

Goal: the aircraft sounds like its engine. RPM and load are audible and believable at every distance. A jet sounds like a jet: a piercing intake whine, a heavy exhaust roar that is loudest behind it, and a spool-down when it stops. Nothing clicks, chirps or loops audibly. The field ambience and wildlife stay as they are; the owner accepted them as "natural and nicely spaced" ([AUD-05](../research/audio/AUD-05/README.md)).

## 1. Reported symptoms

The owner reports four things: the jet turbine does not sound good, it "goes away too fast", a real turbine is very loud, and there are glitches and odd cycles. The findings below map to those symptoms. "Goes away too fast" has three candidate causes: the jet is quieter and duller than a glow engine and fades with distance (F1, F3); no propagation delay (F8b); and the abrupt crash fade (F4). The AUD-06 bench decides which one dominates.

| Symptom | Findings |
| --- | --- |
| The jet sounds poor | F1, F2, F3, F9 |
| The jet "goes away too fast" | F1 and F3 (dull and quiet, no aft roar after the pass), F8b (no propagation delay), F4 (abrupt crash fade) |
| Odd cycles | **F14 (a click at every loop wrap, fixed in AUD-07a)**, F5 (short loops repeat at 1/pitch), F8a (Doppler chirps) |
| Glitches | F14, F16 (start pop), F15 (stuck limiter), F8a, F7 (flat level up close), F10, F11 |

## 2. What the code does today

All values were read from the working tree on 2026-10-13 or measured with the probes in [research/audio/review-2026-10-13](../../research/audio/review-2026-10-13/README.md).

### Every looped voice and the mix bus

| # | Finding | Where | Effect |
| --- | --- | --- | --- |
| F14 | **Every loop clicks at its wrap point.** *Fixed in AUD-07a.* Godot 4.7.2 interpolates past `loop_end` into the stream's silent padding. A seamless source still clicks: at the seam the second difference is 0.12–0.43 against a median of 0.0003–0.0004 (hundreds of times larger), at pitch 1.0 and 0.87, also on a plain `AudioStreamPlayer`; with the guard it falls to 0.002 ([loop probe](../../research/audio/review-2026-10-13/README.md)). In flight the [bench](../research/audio/AUD-06/README.md) finds a click every 1/pitch s on the engine. Fixed in AUD-07a by copying the loop's first 64 frames after `loop_end`. | [soundscape.gd `seamless_loop`](../../app/audio/soundscape.gd), crash `fire_loop` in [crash_audio.gd](../../app/render/crash/crash_audio.gd) (crash track) | A tick every 0.5–2 s on the engine, steady with RPM: the main "odd cycle" and glitch. Wind, foliage, airframe, crickets and the crash fire also wrapped with a click, every 4–31 s. |
| F15 | **The bus limiter never fully releases.** *Fixed for the soundscape in AUD-07d.* Godot 4.7.2's `AudioEffectHardLimiter` stays low after any overshoot for the rest of the session: about 0.15 dB·s / `release` (−1.31 dB at the 0.12 s used here, for a +12 dB burst; −0.30 dB even for a burst that only touches the ceiling). Found because the AUD-07 bench showed the whole mix 1.1 dB low after the start pop touched the ceiling. Fixed for the soundscape in AUD-07d with the stateless `AudioEffectLimiter`, which returns to 0.00 dB and holds −1.00 dBFS ([limiter probe](../../research/audio/review-2026-10-13/README.md)). | [soundscape.gd `_setup_buses`](../../app/audio/soundscape.gd), crash bus in [crash_audio.gd](../../app/render/crash/crash_audio.gd) (crash track, release 0.12 s) | One loud moment ducks everything after it. A hard crash impact leaves the crash bus ≈1.3 dB low until the scene is freed. |
| F16 | **A pop at every flight start.** *Fixed in AUD-07e.* Loops started playing in `configure`, before the first update moved them off the origin, next to the listener. At distance ≈0 the `max_db` clamp lets one mix block through at full level whatever `volume_db` says: about 30 ms at −10 dB RMS (peak −1.9 dBFS) on every bench run. Fixed in AUD-07e: loops start on the first positioned update. | [soundscape.gd `_start_offsets`](../../app/audio/soundscape.gd) | A click or thump when each flight begins. |

### Turbine (Avanti S, JetCat P100-RX, 44 000–154 000 rpm)

| # | Finding | Where | Effect |
| --- | --- | --- | --- |
| F1 | **The jet source is band-limited to 4 kHz.** *Fixed in AUD-10a.* 99.9 % of `motor_turbine.wav` energy lies below 4 009 Hz (generator limit 4 300 Hz). All sources are 22.05 kHz mono. At the runtime pitch of 0.76–1.30 the content ends at about 3.0–5.2 kHz. The distance filter (6.5 kHz) and canopy screening (down to 1.5 kHz) remove more. | [generate.py:57](../../tools/audio/generate.py#L57), [soundscape.gd:205](../../app/audio/soundscape.gd#L205) | A model turbine's defining sounds are a high whine and broadband hiss. Without them it sounds like a muffled fan or vacuum cleaner. |
| F2 | **The turbine pitch range is compressed.** *Fixed in AUD-10a.* `motor_pitch = 0.55 + 0.75·N/N_max`: 0.76 at idle and 1.30 at full, a ×1.7 range. The shaft speed changes ×3.5. The 760 Hz whistle spans 578–988 Hz; the shaft order N/60 spans 733–2 567 Hz. | [soundscape_model.gd:36](../../app/audio/soundscape_model.gd#L36) | The spool-up barely rises in pitch. The ear misses the turbine's signature sweep. |
| F3 | **The turbine is no louder than a .61 glow engine and has no directivity.** *Fixed in AUD-10a.* At full throttle `motor_gain` is 0.52 (turbine) against 0.54 (glow, full load). The turbine asset's RMS is 2.5 dB below the combustion asset (−16.4 vs −13.9 dBFS at equal peak). Every aircraft voice is omnidirectional. | [soundscape_model.gd:23](../../app/audio/soundscape_model.gd#L23), [:37](../../app/audio/soundscape_model.gd#L37) | A jet at full power is about 2–3 dB *quieter* than a Stik. Real jet mixing noise peaks 15–45° from the exhaust axis and is weakest on the axis ([Morris et al.](https://auditory.org/asamtgs/asa93ott/2pNS/2pNS3.html), [Lighthill-based LES](https://supersonic.eng.uci.edu/download/AIAA-2017-0001.pdf)). That aft roar after a pass is missing. |
| F4 | **The engine sound has no stop or run-down path.** Gameplay has no in-flight engine stop: `engine_running` changes only at start, ground start and start failure, and throttle 0 holds idle (44 000 rpm on the turbine). If it ever becomes false, `_pre_step` sets rpm to 0 in the same tick. On a crash the hold pauses the simulation and the whole soundscape fades in 80 ms. The 6 s `turbine_spool.wav` plays only for crash class ≥ C2. | [flight_session.gd:1528-1542](../../app/sim/flight_session.gd#L1528-L1542), [:955](../../app/sim/flight_session.gd#L955), [soundscape.gd:188](../../app/audio/soundscape.gd#L188) | A minor crash silences a running jet abruptly. A future throttle-cut or flameout would cut instantly. Running engines spool correctly: the data gives ≈3.1 s idle→full and ≈2.1 s full→idle ([Avanti data](../../app/data/aircraft/sebart_avanti_s_a200.json), accel 0.4·N/s, decel 0.6·N/s). |

### All engines

| # | Finding | Where | Effect |
| --- | --- | --- | --- |
| F5 | **Motor loops are 1 s long and carry fixed modulation.** Combustion: amplitude and phase wander (0.6–24 Hz noise). Propeller: an explicit 8 % 1 Hz sine. Electric: a 2.5 % 3 Hz sine. At `pitch_scale` p the whole pattern repeats every 1/p s: 1.86 Hz for the Stik at 11 149 rpm, 1.65 Hz for the P-51's four-blade layer at 4 951 rpm. Motor and propeller both start at offset 0. The turbine loop is 5 s, so its hiss envelope repeats every 3.8–6.6 s. | [generate.py:192](../../tools/audio/generate.py#L192), [:209](../../tools/audio/generate.py#L209), [:227](../../tools/audio/generate.py#L227), [:244](../../tools/audio/generate.py#L244), [soundscape.gd:123](../../app/audio/soundscape.gd#L123) | A steady, periodic throb ("wah-wah") at constant throttle: the "odd cycles". The seams themselves are clean. The generator builds integer-bin spectra and the [seam probe](../../research/audio/review-2026-10-13/seam.py) scores every motor/bed seam within the file's own p99. |
| F6 | **Low RPM is muffled.** Motor sources are band-limited to 2.4 kHz (99.9 % of combustion energy < 1.8 kHz, propeller < 0.8 kHz) because they were designed for pitch up to ×4. Most flying is below ×2. At idle the Stik plays at ×0.47 (content < 0.85 kHz) and the P-51 at ×0.23 (1 400 rpm, < 0.42 kHz). | [generate.py:54-56](../../tools/audio/generate.py#L54-L56), [soundscape_model.gd:25](../../app/audio/soundscape_model.gd#L25) | A real glow or gasoline idle has exhaust bark and mechanical clatter well into the kHz range. One sample pitched over a ×8 range cannot keep its character. |
| F7 | **Up close, throttle changes go flat.** *Fixed in AUD-07c.* In Godot 4.7.2 `AudioStreamPlayer3D` adds `volume_db` to the distance gain and *then* clamps the sum to `max_db`. All voices use `max_db = 0` and `unit_size` 8–10 m. Measured with a 1 kHz probe: at 2 m, `volume_db` −6 dB and 0 dB play at the same level. At 8 m and beyond the law is exact inverse distance (−6.0 dB per doubling). | [soundscape.gd:104](../../app/audio/soundscape.gd#L104), [measurement](#a-near-field-clamp-measurement) | The inspect camera sits 2.5 m from the aircraft ([spec.gd:61](../../app/spec.gd#L61)). There, any engine gain above −10 dB (linear 0.32) clamps, so full and half throttle sound alike. This also affects taxiing near the pilot and the planned chase and cockpit cameras. |
| F8a | **Doppler comes from finite-differenced positions with a 10 m listener gate.** *Fixed in AUD-07b.* The observer resets on pause, tick rewind and session reset, but not on camera cuts, although AUD-03 says it does. Toggling the inspect view (key C) with the aircraft within ~10 m of the pilot moves the listener up to 10 m in one frame. That reads as up to 600 m/s and clamps the ratio to 0.65 or 1.5. | [soundscape.gd:180](../../app/audio/soundscape.gd#L180), [main.gd:622](../../app/main.gd#L622), [AUD-03](../research/audio/AUD-03/README.md) | A one-frame pitch chirp on the engine (40 ms smoothing). Derived from the code and not yet reproduced. AUD-06 reproduces it. |
| F8b | **No propagation delay.** Sound arrives instantly at every distance: about 0.3 s early at 100 m and 0.9 s early at 300 m. | [soundscape_model.gd:5-9](../../app/audio/soundscape_model.gd#L5-L9) | A real flyby is heard after it is seen: the pitch drop lags the visual pass and the roar trails the aircraft. Its absence makes fast passes feel abrupt. |
| F9 | **One sample per source, pitch-shifted as a whole.** Tone, exhaust noise and mechanical texture shift together. Broadband noise should change level and colour, not transpose. | [soundscape.gd:50-51](../../app/audio/soundscape.gd#L50-L51) | The usual cause of a "synthetic" engine. Games layer several loops recorded across the RPM range and crossfade them. |

### Mix and integration

| # | Finding | Where | Effect |
| --- | --- | --- | --- |
| F10 | **Two independent limiters, none on Master.** The soundscape limits at −1 dBFS and the crash bus at −1.25 dBFS. Both send to Master, which has no effect and no bus layout. | [soundscape.gd:93-96](../../app/audio/soundscape.gd#L93-L96), [crash_audio.gd:65-75](../../app/render/crash/crash_audio.gd#L65-L75) | The two buses can sum above 0 dBFS during a crash. AUD-04 already lists this combined peak as unqualified. |
| F11 | **Crash body thuds are truncated.** `impact_dirt`, `impact_hard` and `impact_grass` end with their last 5 ms only 24–29 dB below peak. Every other one-shot fades out (−38 to −82 dB). | [crash assets](../../app/assets/audio/crash/), generator [cr-02a](../../research/crash-damage/cr-02a/generate_assets.py) | An audible cut at the end of the thud. Crash track. |
| F12 | **Cross-owner write.** `main.gd` aliases the soundscape motor voice as `_engine_audio`. A checkpoint restore sets its `stream_paused`. The next soundscape frame overrides it, so this is harmless today but fragile. | [main.gd:410](../../app/main.gd#L410), [:709-710](../../app/main.gd#L709-L710) | One voice has two writers. |
| F13 | **Blade count is hard-coded.** It is 4 when the aircraft id is the P-51 and 2 otherwise. Firing events per revolution are implicit (one, correct for the current single-cylinder glow and the DA-120 boxer twin). A four-stroke or an alternate-firing twin would be an octave off. | [flight_audio.gd:42](../../app/audio/flight_audio.gd#L42), [soundscape_model.gd:25-26](../../app/audio/soundscape_model.gd#L25-L26) | New aircraft would sound wrong without anyone noticing. |

What works and stays: the read-only adapter (no simulation writes, private RNG, parity with audio off), bounded voices, pause and reset fades, canopy screening, wind and foliage beds, and the whole wildlife layer. The inverse-distance law beyond `unit_size` is physically right for spherical spreading.

## 3. Options and recommendation

**Engine shutdown (F4).** (A) Audio-only presentation envelope that keeps a voice running after rpm reaches 0. Quick, but sound and physics then disagree. (B) Physics run-down: with the engine off, the turbine follows its existing deceleration schedule to zero, and a glow shaft stops on its own inertia and drag. Audio needs no special case. **Recommend B** (realism first, one source of truth). The owners are propulsion/Avanti; audio only reads rpm. Ship A only if B is far off, and remove it when B lands.

**Engine sources (F1, F5, F6, F9).** (A) Offline-generated multi-RPM banks: 3–5 loops per engine kind, each authored near its playback RPM so `pitch_scale` stays within about 0.8–1.25, crossfaded by RPM. Separate layers: tonal (pitch follows RPM), broadband exhaust (level and filter follow load, little transposition) and mechanical. Loops of 8–12 s whose modulation is non-periodic, at 44.1 kHz for aircraft layers. (B) Runtime synthesis in `AudioStreamGenerator`. G3b showed that per-sample GDScript costs main-thread time. (C) Licensed real recordings ([AUD-01 sources](../research/audio/AUD-01/sources.md)). Licensing and provenance burden; best used as a reference. **Recommend A now, C as a listening and calibration reference.** It fits the existing generator, provenance and memory checks.

**Near-field level (F7).** (A) Trim: lower every aircraft voice by 12 dB and raise the aircraft bus by 12 dB. The far field is unchanged; the clamp moves 4× closer. `max_db` can rise only to +6 dB. (B) Own the distance law: set `attenuation_model` to disabled and compute distance gain in the adapter with a 1 m minimum, keeping Godot panning. Fully testable, but distance filtering must also be replaced. **Recommend A first** (one-line, measurable) and B only if CAM-track cameras need per-view rules.

**Doppler and arrival (F8).** Use the simulation's velocity (read-only) for the source. Reset the observer on any camera-mode change through a small main-line seam, and gate on implied speed (> 150 m/s) instead of distance. For F8b, keep a short pose history and place each aircraft voice where the aircraft was at the retarded time t − r/c. Position, delay and Doppler then agree by construction. **Recommend both;** delay as an option (D6).

**Mix (F10).** One final Master limiter and a declared bus layout: Aircraft, Environment and Crash into Master, and later UI. Loudness targets per bus, measured on the bench.

## 4. Steps

| ID | Work | Proof |
| --- | --- | --- |
| AUD-06 | **Linux audio bench.** Done: [`tools/audio/bench.sh`](../../tools/audio/bench.sh) renders the real flight under Movie Maker at fixed 60 FPS with per-frame telemetry; [`bench_analyze.py`](../../tools/audio/bench_analyze.py) reports K-weighted level, centroid, 95 % bandwidth, dominant line, envelope periodicity, clicks and Doppler jumps. Baselines for Stik, Avanti, P-51, electric and the runway inspect case. Still to add: flyby, crash and engine-cut scenarios. | [AUD-06 evidence](../research/audio/AUD-06/README.md): reproduced F1, F3, F6, F8a and F14 in real flight. |
| AUD-07 | **Low-risk fixes.** Done: (a) loop wrap guard (F14); (b) Doppler from the accepted simulation velocity, with listener jumps above 150 m/s treated as camera cuts (F8a); (c) −12 dB voice / +12 dB aircraft-bus trim (F7), level-neutral beyond the clamp (probe: −44.38 dB both ways at 60 m); (d) recovering limiter (F15); (e) loops start after positioning (F16). Rejected: random motor/propeller start offsets; the two loops are harmonically related at one pitch, so their phase set the engine level (±5 dB by seed). Open: remove the F12 alias write (main line). | Bench: Stik sweep clicks 21 → 3 (onset, end and one seeded ambience event); runway Doppler maximum 1.43 → 1.06; 97/97 soundscape checks with deliberate mutations failing; parity pairs pass. |
| AUD-08 | **Engine stop and crash fade** (D1). Coordinate a physics run-down for any future engine stop (throttle cut, flameout) with the propulsion and Avanti owners; audio only reads rpm. On a crash hold, let a turbine voice decay over its deceleration time instead of the 80 ms pause fade; a propeller engine that strikes the ground may stop at once. Low priority until gameplay has an engine stop. | Trace: turbine rpm decays on the decel schedule to zero; bench crash run shows the decay; golden flights untouched unless the owner approves an explained change. |
| AUD-09 | **Engine banks for glow, gasoline and electric** (D2, D3). Multi-RPM layered loops, 8–12 s, non-periodic modulation, 44.1 kHz, per-asset provenance; data-driven blades and firing events per revolution (F13) through the aircraft contract. Harmonically related layers (firing and blade pass) must stay phase-locked: author them in one source or start them together. |  Generator `--check`; bench periodicity peak below threshold at every RPM; centroid at idle within a target band; memory budget recorded; owner listening A/B. |
| AUD-10 | **Turbine voice.** (a) Done: two generated layers replace the single loop. `turbine_whine.wav` carries shaft orders 1–7 of 1 372 Hz (82 320 rpm) plus compressor hiss to 10 kHz; its pitch is N / 82 320, so 0.53–1.87, the true ×3.5. `turbine_roar.wav` is jet mixing noise peaking near 1.6 kHz; its pitch follows jet velocity (Strouhal) and its amplitude V_j⁴ (Lighthill V⁸ power), plus a small core-noise term. V_j comes read-only from `turbine.gd`. Directivity: roar peaks 30° off the exhaust axis (−4 dB on it, −12 dB ahead); whine 0 dB ahead, −8 dB aft. The roar uses the turbine's unused propeller voice, so the budget stays at 14 voices. Levels are calibrated to D4. (b) Open: start-up and shutdown sequences (needs a physics engine-off path, D1), a blade-pass tone (needs the P100-RX compressor blade count), and a measured reference recording. | Bench: full −37.4 dB and idle −47.4 dB at 100 m against the Stik's −41.3 (D4 targets −37.3 and −47.3); flyby: whine leads the approach (θ ≈ 165°, Doppler 1.10), roar peaks after the pass (θ ≈ 35°); 106/106 soundscape checks; parity 5/5 including the Avanti. Owner listening is pending (AUD-13). |
| AUD-11 | **Propagation.** Retarded-time source position and Doppler; distance-dependent high-frequency loss (ISO 9613-1 trend, coarse). | Bench flyby: pitch drop lags the visual pass by r/c within one frame; tests on the retarded-time solver. |
| AUD-12 | **Mix and loudness.** Bus layout, Master limiter, per-bus loudness targets; combined crash and soundscape peak; volume sliders with the menu track. | Bench crash run stays ≤ −1 dBFS true peak; per-aircraft loudness table recorded. |
| AUD-13 | **Listening qualification.** Owner A/B tapes per aircraft (before and after), stereo speakers; Windows WASAPI spot check. | Owner answers recorded verbatim, as in AUD-04/05. |

**Crash track, for coordination** (their files, measured here):
1. F15: the crash bus uses `AudioEffectHardLimiter` with release 0.12 s, so it stays about 1.3 dB low after any loud hit. With E3d1 soft contacts the flight continues after a touch, which makes this audible. Swap to `AudioEffectLimiter` (ceiling −1.25 dB) as the soundscape did, and check with the [limiter probe](../../research/audio/review-2026-10-13/README.md).
2. F14: `fire_loop` loops with the same recipe that clicks at every wrap. Use `Soundscape.seamless_loop()` or copy its 64-frame guard.
3. F11: fade the three truncated impact tails (`impact_dirt`, `impact_hard`, `impact_grass`) through their generator.

## 5. Decisions (taken 2026-10-13, delegated by the owner)

Recorded in [DECISIONS](../../DECISIONS.md). Each one can be revisited when its trigger appears.

| ID | Decision | Revisit when |
| --- | --- | --- |
| D1 | Engine shutdown is a **physics run-down**: with the engine off, rpm keeps following the propulsion model to zero. No audio-only envelope. | — |
| D2 | Engine sources are **offline-generated multi-RPM layered banks**. Real recordings serve only as listening references. | A licensed recording set with clean provenance appears. |
| D3 | Aircraft layers move to **44.1 kHz**; beds stay at 22.05 kHz. Only the active aircraft's bank is loaded, so the per-flight decoded budget stays at 8 MiB. **Refined 2026-10-13 (AUD-10a):** the dullness came from the generator's rule that band limit × pitch stay below the *source* Nyquist (11 kHz). Measured against the output Nyquist (20 kHz margin), 22.05 kHz layers authored at a central reference reach 14–19 kHz after pitch. Use 44.1 kHz only where a layer needs content above 10 kHz before pitch shifting. | The per-flight budget is exceeded. |
| D4 | Interim turbine loudness against a .61 glow at full power (K-weighted, 30 m, bench): **turbine full +4 dB, turbine idle −6 dB.** This is an authored target, not a measurement. | Measured model-turbine levels or recordings exist ([gaps](#b-research-gaps)). |
| D5 | Keep Godot's distance law with a **−12 dB voice / +12 dB aircraft-bus trim.** | CAM-track cameras need per-view distance rules. |
| D6 | **Propagation delay on by default** (retarded-time position and Doppler), with `--audio-delay=off` for tests and comparison. | Players find it disorienting. |

## Appendix

### A. Near-field clamp measurement

One 1 kHz `AudioStreamPlayer3D`, `unit_size` 8, `max_db` 0, filter off, Godot 4.7.2, Movie Maker capture at 48 kHz. Levels include a constant −3.0 dB centre-pan offset. Reproduce with [the probe](../../research/audio/review-2026-10-13/README.md).

| Distance | `volume_db` | Measured | Expected without clamp | Expected with clamp |
| ---: | ---: | ---: | ---: | ---: |
| 2 m | −6 | −3.0 | +6.0 | 0.0 |
| 2 m | −16 | −7.0 | −4.0 | −4.0 |
| 2 m | −26 | −17.0 | −14.0 | −14.0 |
| 8 m | −6 | −9.0 | −6.0 | −6.0 |
| 16 m | −16 | −25.0 | −22.0 | −22.0 |
| 32 m | −16 | −31.1 | −28.0 | −28.0 |
| 100 m | −6 / −16 / −26 | −30.9 / −40.9 / −51.0 | −27.9 / −37.9 / −47.9 | same |

Every row matches the clamped prediction minus 3.0 dB.

### B. Research gaps

- **Model-turbine sound level and spectrum.** No manufacturer or peer-reviewed dB figure for JetCat-class engines was found. A mid-1990s report of an FAI jet-scale noise limit (90 dBA at a stated stand distance) is second-hand and dated. A university micro-turbine noise project uses a JetCat P250 but publishes no levels ([ERAU](https://commons.erau.edu/exhibit/discovery-day/discovery-day-2021/microturbine-jet-engine-afterburner-noise-reduction/)). AUD-10 needs measured recordings with stated distance and weighting, or a field measurement by the owner.
- **Compressor blade count** of the P100-RX for the blade-pass tone: not in the aircraft data.
- **Glow and gasoline idle spectra** at the pilot's distance: reference recordings with provenance.
