# AUD-11 — Propagation: delay and air absorption

2026-10-17 · **Status: AUD-11a propagation delay and AUD-11b ISO 9613-1 air absorption delivered; owner listening (AUD-13) open.** Plan: [audio realism](../../../plans/audio-realism.md) (finding F8b, decision D6).

## What changed

Sound left the aircraft and arrived instantly at every distance. Now aircraft voices play the source as it was at the retarded time t<sub>e</sub>, the root of t − t<sub>e</sub> = |x(t<sub>e</sub>) − x<sub>listener</sub>(t)| / c.

- [`flight_audio.gd`](../../../../app/audio/flight_audio.gd) adds the accepted simulation clock (`time = sim.time()`) to its read-only snapshot. `--audio-delay=off` disables the delay for comparison and tests.
- [`soundscape.gd`](../../../../app/audio/soundscape.gd) `heard_snapshot()` keeps a bounded pose history (5.5 s: the 1 500 m voice range at the 300 m/s minimum sound speed). It returns the snapshot with source-side fields at t<sub>e</sub>: position, velocity, exhaust direction, rpm, load, throttle, airspeed and jet velocity are interpolated; `running`, blade count and maximum rpm take the nearest sample. Listener, wind, light and pause stay current. Doppler, canopy screening, ducking and turbine directivity therefore use the emission point, so position, delay and Doppler agree by construction. Wildlife disturbance still uses the actual aircraft position.
- [`soundscape_model.gd`](../../../../app/audio/soundscape_model.gd) `retarded_emission()` is the pure solver: walk the history back to the bracketing samples, then bisect, linear in time and position between samples.
- The history restarts on observer reset, a clock rewind or a forward jump above 0.5 s. A snapshot without `time` plays undelayed, as before.

Limit: the explicit glow-cycle voice (`glow_2t`/`glow_4t` profiles) keeps its accepted, phase-anchored telemetry; only its position is delayed. Delaying its firing counters needs a separate change to the generator's phase anchoring. The sample-based voices used by the stock fleet are fully delayed.

## Evidence

**Unit checks** (`test_soundscape.gd`, 136/136): a source 343 m away is heard 1.000 000 s late; a 60 m/s straight pass matches the closed-form root within 1 µs (presentation `Vector3` is single precision); short and empty histories; a level pass 40 m overhead drops pitch below 1 at 3.450 s against 3.333 + 40/343 = 3.450 s, and at 3.350 s with the delay off (visual pass 3.333 s); an rpm step 343 m away is heard after 1 s and not at 0.9 s; wind stays current; rewind restarts the history; the history stays bounded; snapshots without a clock are unchanged.

Deliberate mutations on disposable copies, each detected: delay disabled (3 failures), 1 ms bisection bias, no rewind reset, listener-side wind delayed, no history trimming, runtime ignoring the heard snapshot (1 failure each).

**Real flight** (`tools/audio/bench.sh … flyby --audio-seed=4102026`, Movie Maker at 60 FPS; the bench now records `delay_s`):

| Run | Closest approach | r/c | Doppler crosses 1 | Lag |
| --- | --- | ---: | ---: | ---: |
| Stik, delay on | 4.750 s, 179.1 m | 0.522 s | 5.283 s | 0.533 s |
| Stik, `--audio-delay=off` | 4.750 s, 179.1 m | — | 4.750 s | 0.000 s |
| Ventage Jet, delay on | 5.667 s, 101.0 m | 0.294 s | 5.967 s | 0.300 s |

Each lag is within one frame (16.7 ms) of r/c; the simulator's sound speed follows air temperature, so c is slightly below 343 m/s. Before the pass the delay exceeds the current r/c and after it falls below, as the emission point trails the aircraft (Stik: 0.560 s at 183 m approaching, 0.537 s at 190 m receding). The Ventage Jet roar still peaks after the pass at θ = 30.1° (8.13 s). Doppler range is unchanged (Stik 0.929–1.068) and no new jumps appear after the first second. `bench_analyze.py` finds the same click times with and without the delay (6.09, 6.72, 7.41, 7.55 s: seeded ambience events) and none on the jet ([summary](summary.json)).

Listen: [Stik flyby with delay](stik-flyby-delay.wav), [without delay](stik-flyby-nodelay.wav) (11 s, 48 kHz stereo, same seed). A mixer capture, not speaker listening or acoustic validation.

**Simulation parity** (`check_parity.gd`, soundscape on/off, 1 200 ticks of turbulent flight per pair, full checkpoint bytes compared every tick): 8/8 fixed-wing configurations identical with exactly these AUD-11a files (Stik and its three glow variants, Extra, P-51, Ventage Jet, Timber). The first attempts on 2026-10-17 did not measure audio: `main.gd` failed to compile at a1fc607f (crash-economics `incident.gd`, since repaired upstream), then the harness itself failed. Two harness defects were repaired: its 4-channel input tape replaced the 7-channel P-51/Ventage Jet input vector, so the simulation rejected the step as malformed; and each pair's verdict required the global failure list to be empty, which failed the Timber for the P-51's error. Rotorcraft use another route; the X-Cell is now listed under `skipped` instead of ending the process. The same five failures appeared with the pre-AUD-11a audio files, so none came from this change.

Source identities (SHA-256 prefixes): `flight_audio.gd` 7af24f813ad9098f, `soundscape.gd` b8e98ac5b76652e9, `soundscape_model.gd` ff8bed099cc69475.

## AUD-11b — air absorption (ISO 9613-1)

**What changed.** Air absorbs high frequencies roughly in proportion to distance. Aircraft voices now pass a 12 dB/octave Butterworth low-pass on the aircraft bus whose cutoff is where the ISO 9613-1 path loss over the heard (retarded) path reaches 3 dB. The coarse trend matches the plan: at twice the cutoff the filter removes 12.3 dB against roughly 10 dB of ISO loss; at four times, 24 dB against roughly 33 dB.

- [`soundscape_model.gd`](../../../../app/audio/soundscape_model.gd): `absorption_db_per_m()` (ISO 9613-1:1993), `humidity_molar_pct()` (Annex B) and `absorption_cutoff_hz()` (bracketed Illinois regula falsi in log frequency, clamped to 20 Hz–16 kHz).
- [`flight_audio.gd`](../../../../app/audio/flight_audio.gd) passes temperature, pressure and molar humidity from the accepted atmosphere. The reference atmosphere is dry ISA air by construction, not an observation, so it takes 50 % relative humidity; dry air absorbs about 7× less at 8 kHz. A configured atmosphere keeps its own humidity, including the explicit "Standard dry ISA column".
- [`soundscape.gd`](../../../../app/audio/soundscape.gd): the absorption low-pass and the canopy-screening shelf sit on the aircraft bus, always enabled. The target refreshes at 10 Hz and glides in log frequency (0.15 s). Aircraft voices no longer use `AudioStreamPlayer3D`'s distance shelf. `--audio-absorption=off` holds the filter at its ceiling for source-level calibration.

**Why the old filter went.** The [filter probe](../../../../research/audio/air-absorption-2026-10-17/README.md) measured Godot 4.7.2 on the real mixer. The 3D distance shelf configured at −12 dB above 6.5 kHz applied −13.5 dB at 8 kHz already at 30 m and −24 dB at 200 m, nearly independent of distance; full canopy screening reached −47 dB. Godot applies a shelf's gain squared. The near field was therefore too dull and the far field too bright. Screening now applies its authored depth: −24 dB above 1.5 kHz when fully screened, plus the unchanged −7 dB broadband term. Ambience voices keep their previous 3D shelf (accepted in AUD-05).

**Checks** (`test_soundscape.gd` 150/150). The model reproduces the 10 °C / 70 % octave table printed in earlier ISO 9613-2 editions (0.1 … 117 dB/km, [EMD windPRO Appendix A](https://help.emd.dk/knowledgebase/content/windPRO4.1/Appendix_A_DECIBEL.pdf)) within half its last printed digit (worst 0.87 of that tolerance). Its saturation humidity agrees with the simulator's Buck-based atmosphere within 0.2 % from 0 to 40 °C. The cutoff solves the 3 dB loss within 1e-6 dB, falls monotonically with distance (357 Hz at 1 500 m, 20 °C, 50 %), and holds the 16 kHz ceiling at 5 m; dry air gives a higher cutoff than humid air. Wiring checks: two enabled `FILTER_6DB` Butterworth filters on the aircraft bus; the aircraft 3D shelf is off while ambience keeps it; the first update and an observer reset place the cutoff at once; a 300 → 20 m path jump glides, never stepping more than a fifth of the jump in one frame, and settles within 1 %; snapshot humidity drives the cutoff; screening reaches −24 dB and is flat when clear; `--audio-absorption=off` holds the ceiling. Nine deliberate mutations, each detected: oxygen/nitrogen term −10 %, humidity +1 %, 6 dB knee, filter not driven, no glide, unhalved shelf gain, 3D shelf kept, 24 dB/octave cascade, reset keeping the glide. The 6 dB knee first survived because the check compared the loss with the constant itself; it now compares with the literal 3 dB that the measured Butterworth response defines.

The cutoff solve costs about 12 µs on the dev VM (bisection took 29 µs), so it runs at 10 Hz. Over a 50 s synthetic pass, `update_sound` measured 126–135 µs mean against 158–166 µs before, in alternating order on a busy VM: the per-frame writes to four players' 3D filter properties are gone.

**Real flight** (Movie Maker, seed 4102026; `base` = AUD-11a files at a1fc607f, `cand` = these files, both frozen copies; [summary](summary-aud11b.json)). Stage K level, spectral centroid and 95 % bandwidth:

| Capture | Stage, distance | AUD-11a | AUD-11b |
| --- | --- | --- | --- |
| Stik sweep, engine only | full, 177 m | −45.6 dB, 370 Hz, 721 Hz | −45.7 dB, 362 Hz, 715 Hz |
| Stik flyby | passing, 188 m | −46.0 dB, 412 Hz, 973 Hz | −46.1 dB, 405 Hz, 914 Hz |
| Ventage Jet sweep, engine only | trim, 70 m | −41.0 dB, 1 953 Hz, 3 457 Hz | −41.8 dB, 2 013 Hz, 4 523 Hz |
| Ventage Jet sweep, engine only | full, 283 m | −45.4 dB, 1 563 Hz, 3 369 Hz | −48.2 dB, 1 065 Hz, 2 455 Hz |
| Ventage Jet sweep, engine only | idle, 348 m | −59.0 dB, 1 269 Hz, 3 018 Hz | −61.3 dB, 917 Hz, 1 535 Hz |
| Ventage Jet flyby | passing, 109 m | −39.6 dB, 2 131 Hz, 3 328 Hz | −41.5 dB, 1 902 Hz, 3 240 Hz |

The Stik is unchanged within 0.1 dB: its energy lies below 1 kHz, where 200 m of air removes little. The jet is brighter near the pilot and darker and quieter far away, as air absorption predicts. Click times are unchanged; the one new mark at 10.986 s on the jet flyby is the final frame, where other captures also mark the end of the scene.

**D4 calibration is preserved.** Source level under the AUD-10a conditions (`--audio-absorption=off --audio-delay=off`, engine only, inverse-distance normalisation to 100 m): Stik full −41.3 dB (AUD-10a −41.3), jet full −37.2 (−37.4) = Stik +4.1 dB, jet idle −47.8 (−47.4) = Stik −6.5 dB; targets +4 and −6. No gain changed. With the delay on, the same normalisation reads +4.5 / −7.7 dB because it uses the current distance while the sound comes from the retarded emission point; that is a measurement limit, not a source change.

**Parity**: 8/8 fixed-wing configurations identical with audio on and off, with the same checkpoint hashes as AUD-11a; the X-Cell is listed as skipped.

Listen: [jet flyby, AUD-11a](jet-flyby-aud11a.wav), [AUD-11b](jet-flyby-aud11b.wav) (11 s, 48 kHz stereo, same seed). Mixer captures, not speaker listening or acoustic validation; the filter shape is a coarse fit to ISO 9613-1, which describes pure tones in still, homogeneous air without ground or turbulence effects.

Source identities (SHA-256 prefixes): `flight_audio.gd` 5f0f2fb17350a42d, `soundscape.gd` 49e042a0b038c5e3, `soundscape_model.gd` cb2fe28e64c86abc (bench and parity); the `--audio-absorption=off` switch was added afterwards and changes no default path.

## Open

- Owner listening of both A/B pairs (AUD-13).
- Ambience voices still use the doubled 3D shelf; any change needs the AUD-05 listening acceptance repeated.
- The explicit glow-cycle voice reaches 2.8–3.5 ms peak `update_sound` in parity runs, before and after this change (likely its generator's first buffer fill); owner: NITRO/audio.
