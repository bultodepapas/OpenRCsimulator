# AUD-06/07/10a — Linux audio bench, first fixes and the turbine voice

2026-10-13 · **Status: AUD-06 bench, AUD-07a–e and AUD-10a delivered; owner listening pending.** Plan: [audio realism](../../../plans/audio-realism.md). Probes: [review-2026-10-13](../../../../research/audio/review-2026-10-13/README.md).

## Bench

[`tools/audio/bench.sh`](../../../../tools/audio/bench.sh) flies the real flight scene with [`bench.gd`](../../../../tools/audio/bench.gd) under Godot Movie Maker (`--write-movie`, `--fixed-fps 60`, Xvfb, llvmpipe). Movie Maker mixes the Master bus in step with the frames, so frame *i* covers samples [800 *i*, 800 (*i*+1)) at 48 kHz; the JSON holds per-frame RPM, throttle, distance, Doppler ratio and the motor voice's targets, volume and pitch. Inputs go through the session's `read_raw`, like a player. [`bench_analyze.py`](../../../../tools/audio/bench_analyze.py) reports, per steady stage (last 3 s), BS.1770 K-weighted RMS (ungated), centroid, 95 % bandwidth, the dominant 40–4000 Hz line and envelope periodicity, plus clicks (1 ms second-difference peaks over 8× the local median) and Doppler jumps over 0.03 per frame.

```sh
tools/audio/bench.sh /tmp/bench stik-sweep sweep --audio-seed=4102026
tools/audio/bench.sh /tmp/bench avanti-sweep sweep --audio-seed=4102026 --aircraft=sebart-avanti-s-a200-p100rx
tools/audio/bench.sh /tmp/bench stik-runway runway --audio-seed=4102026
python3 tools/audio/bench_analyze.py /tmp/bench/stik-sweep /tmp/bench/avanti-sweep --out=/tmp/bench/summary.json
OPENRC_APP=/path/to/disposable/app tools/audio/bench.sh …   # render a baseline copy
```

Scenarios: **sweep** starts trimmed in the air; it then holds trim for 3 s, throttles up for 3 s, holds full for 5 s, throttles down for 3 s and holds idle for 5 s. **runway** starts on the runway threshold at idle, toggles the inspect view (key C) four times, then rolls at full throttle. One run takes about 4 minutes on this VM. Movie Maker ignores `--resolution` and records at 1280×720.

## Results

All values come from [summary.json](summary.json). *base* is the tree before AUD-07, rendered from a disposable copy; *fix* has 07a only; *after* has 07a–e. Telemetry (RPM, distance, Doppler) is identical frame by frame across base, fix and after, so the audio changes leave the simulation untouched; the parity pairs below confirm it.

| Capture | Loop clicks | Start (first 30 ms) | Doppler max | K level up / full / down / idle (dB) |
| --- | ---: | --- | ---: | --- |
| Stik sweep, base | 21 (every 1/pitch s) | burst −10 dB RMS, peak −1.91 dBFS | 1.116 | −39.5 / −43.7 / −45.9 / −53.4 |
| Stik sweep, after | 0 (two non-loop events remain) | silent, then fade-in; capture peak −29.4 dBFS | 1.116 | −39.5 / −43.7 / −45.9 / −53.3 |
| Stik runway, base | 4 (2.10, 4.24, 6.72, 7.73 s) | burst | **1.427** (jump at 4.0 s, inspect toggle 5.6 → 2.5 m) | inspect 2.5 m: −17.4 |
| Stik runway, after | 0 | silent | 1.058 | inspect 2.5 m: −17.4 |
| Avanti sweep, base → after | detector masked by hiss → 0 | burst → silent | 1.059 | −48.7 / −53.2 / −55.6 / −57.4, unchanged |

The two remaining Stik events are at 7.414 s, also present in the electric run with the same audio seed (a seeded ambience transient, not a loop), and at the last captured block. The runway events at 6.08–6.50 s occur in every runway run during the takeoff roll and are not loop wraps.

Listen: [before](before-stik-0-4.5s.wav) and [after](after-stik-0-4.5s.wav), the first 4.5 s of the Stik sweep (48 kHz stereo): start pop, then a click every 1.14 s at trim RPM.

### Baseline facts for the plan

| Aircraft (stage) | RPM | Distance | Centroid | 95 % bandwidth | K level |
| --- | ---: | ---: | ---: | ---: | ---: |
| Stik full | 11 149 | 136 m | 394 Hz | 826 Hz | −43.7 dB |
| Avanti full | 154 000 | 282 m | 592 Hz | 1 887 Hz | −53.2 dB |
| Avanti idle | 44 011 | 349 m | 286 Hz | 1 143 Hz | −57.4 dB |
| P-51 trim | 3 543 | 69 m | 296 Hz | 756 Hz | −34.1 dB |
| Electric full | 9 218 | 143 m | 536 Hz | 1 740 Hz | −49.0 dB |

The Avanti covers 70 → 353 m in 14 s, while the Stik reaches 136 m. Normalized to 100 m by inverse distance, the jet at full power is about 3 dB quieter than the Stik (−44.2 against −41.0 dB). That matches F3. With a 95 % bandwidth under 1.9 kHz, the jet is quiet, dull and far away within seconds: the owner's "goes away too fast". The P-51 rolled into the ground at 6.5 s in the sweep (full power, neutral sticks), so only its trim stage is usable; crash audio and the engine-off path need their own scenario.

## Fixes (AUD-07)

| Step | Change | Proof |
| --- | --- | --- |
| 07a | Loop wrap guard: 64 frames of the loop start copied after `loop_end` (F14). | Loop probe: seam second difference 0.12–0.43 → 0.002; bench clicks 21 → 0. |
| 07b | Doppler source velocity from the accepted simulation state; listener motion above 150 m/s is a camera cut (F8a). | Runway Doppler max 1.427 → 1.058; unit check fails with ratio 1.50 when the gate is mutated. |
| 07c | Aircraft voices −12 dB into a +12 dB aircraft bus (F7). | Probe: −44.38 dB both ways at 60 m; bench levels unchanged within 0.1 dB. |
| 07d | `AudioEffectLimiter` replaces `AudioEffectHardLimiter` on the mix bus (F15). | Limiter probe: HardLimiter stays −1.31 dB low after a +12 dB burst (release 0.12 s); Limiter returns to 0.00 dB. The intermediate run with the HardLimiter shows the whole mix 1.1 dB low after the start pop touched the ceiling. |
| 07e | Loops start on the first positioned update (F16). | First 30 ms: −10 dB RMS burst → silence; Stik capture peak −1.91 → −29.4 dBFS. |

Rejected: random start offsets for the motor and propeller loops. The blade-pass loop is a harmonic of the firing loop at the same pitch. With independent offsets their phase changed the engine level by −4 to +3 dB and halved the dominant line (`offsets-*` in summary.json). Both loops start together again.

Checks: `test_soundscape.gd` **103/103** (deliberate mutations of 07a, b, c, d and e each fail their checks); `test_wildlife.gd` 26/26; `test_crash_audio` 12/12, `test_crash_integration` 95/95, `test_engine_audio` 146/146, `test_engine_sound` 12/12, `test_ui_pause`, `test_scenery_ambience`, `test_time_of_day_edit` 57/57, `test_time_of_day_checkpoint` 48/48, `test_electric_input` 6/6, `test_ui_weather`, `test_ui_time_of_day`, all rerun on the final code. `check_parity.gd` fleet and electric: **pass** (audio on/off, `--audio-seed=4102026`). Full `app/test.sh` on a clean worktree of `ca8c305` (AUD-07a–e, before AUD-10a): 113 scripts passed, including `test_crash_audio`, `test_engine_audio`, `test_engine_sound` and `test_e2e_input`, before the run stopped at `test_landscape_gravel.gd` (47 → 63 scenery cells). Bisection puts that failure at `c5a00d0` (scenery damage, another track): its parent passes and it fails. It is not audio. The scripts after it in the alphabet, including `test_soundscape` and `test_wildlife`, ran separately (above). An earlier attempt stopped at `test_e2e_input.gd` with "1 resources still in use at exit" while all its checks passed. That leak is intermittent: 0/5 repeats with these audio changes and 1/5 with the previous audio files.

## Turbine voice (AUD-10a)

The single 5 s turbine loop (content under 4 kHz, pitch 0.76–1.30) is replaced by two layers generated by [`generate.py`](../../../../tools/audio/generate.py) and checked byte-exact with NumPy 2.4.6:

| Layer | Source | Runtime control |
| --- | --- | --- |
| `turbine_whine.wav` (voice 0) | 8 s; shaft orders 1–7 of 1 372 Hz (82 320 rpm) and compressor hiss to 10 kHz; centroid 2.5 kHz | pitch N / 82 320 (0.53–1.87); amplitude ∝ (N/N_max)^0.46; forward directivity |
| `turbine_roar.wav` (voice 1, the turbine's unused propeller slot) | 10 s; jet mixing noise, 1/3-octave peak 1.6 kHz, turbulent modulation and rumble | pitch 1.40 · V_j/V_j,max (Strouhal); amplitude ∝ (V_j/V_j,max)^4 + 0.05 N/N_max; aft directivity peaking 30° off the jet |

V_j is gross thrust over mass flow from `turbine.gd` at the accepted RPM, airspeed and density: 30.5 m/s at idle and 435 m/s at full, statically. The generator's pitch-aware limit now compares band limit × pitch with a 20 kHz output margin instead of the 11 kHz source Nyquist, so the layers keep 14–19 kHz of shifted bandwidth. The other 13 sources are unchanged byte for byte.

**Loudness (D4)**, engine only (`--engine-only` mutes the environment bus), K level normalized to 100 m by inverse distance, sweep geometry with the listener behind:

| Capture | Full | Idle |
| --- | ---: | ---: |
| Stik (reference) | −41.3 | −54.5 |
| Avanti before AUD-10a (with ambience, `after-avanti-sweep`) | −44.2 | not comparable |
| Avanti AUD-10a, first gains (whine 0.60, roar 1.20) | −42.7 | −51.6 |
| Avanti AUD-10a, calibrated (whine 0.98, roar 2.28) | **−37.4** | **−47.4** |
| D4 target | −37.3 (Stik +4) | −47.3 (Stik −6) |

The pre-AUD-10a voice was not captured engine-only. Its idle stage at 349 m sits near the ambience floor, so only its full-power value is comparable.

**Flyby** (`flyby` scenario: the pilot station moves 250 m ahead of the start and 30 m to the side; full throttle). On the approach (θ ≈ 165°) the whine leads at gain 0.98 against roar 0.05–0.7, with Doppler up to 1.10. The pass is at about 100 m and 5.5 s. After it (θ ≈ 35°, 7.5 s) the roar peaks at 2.37 and the whine falls to 0.5. At 133 m the receding jet reads about 2.5 dB louder than at the same distance ahead, and it still measures −44 dB at 200 m. The same flyby with the pre-AUD-07 tree (disposable copy) and with AUD-10a, K level over 0.5 s windows (ambience included):

| t (s) | Distance | Before: K / centroid / 95 % bw | After: K / centroid / 95 % bw |
| ---: | ---: | --- | --- |
| 1.5 (approach) | 210 m | −50.4 dB / 566 Hz / 2.1 kHz | −45.2 dB / 1 794 Hz / 2.7 kHz |
| 5.5 (pass) | 102 m | −45.7 / 1 158 / 3.0 | −38.9 / 2 042 / 3.3 |
| 7.5 (receding) | 133 m | −48.7 / 1 087 / 3.1 | −39.3 / 1 562 / 3.4 |
| 10.5 (receding) | 217 m | −51.9 / 722 / 2.4 | −44.4 / 1 425 / 3.4 |

Listen: [flyby before](before-avanti-flyby.wav), [flyby after](after-avanti-flyby.wav) (11 s each, 48 kHz stereo).

Checks: `test_soundscape.gd` 106/106 with new turbine contracts (true ×3.5 whine pitch, V_j-driven roar, 12 dB aft/ahead roar ratio, 6 dB ahead/aft whine ratio, silent when stopped); `generate.py --check` passes; parity 5/5 including the Avanti (identical checkpoint hashes with audio on and off). `check_pack.gd` now expects 30 sources; the export pack was not rebuilt on this VM.

## Limits

These are mixer samples from Movie Maker's software mix on llvmpipe, not speaker listening, device output or calibrated acoustics. K level is ungated and relative. The click detector is relative to the local level; loud broadband beds (the turbine hiss) can mask a click. One seed and one VM. The turbine laws follow published trends (Lighthill V⁸, Strouhal peak, 15–45° directivity peak), but the levels are authored to D4, not measured from a P100-RX. `generate_wildlife.py --check` reports only the recorded Python version (3.11.9 in its manifest, 3.12.3 here); its WAV bytes match. The owner's listening review (AUD-13) is still pending.
