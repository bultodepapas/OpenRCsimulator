# AUD-11 — Propagation delay (retarded-time source)

2026-10-17 · **Status: retarded position, Doppler, directivity and engine state delivered; distance-dependent air absorption and owner listening (AUD-13) open.** Plan: [audio realism](../../../plans/audio-realism.md) (finding F8b, decision D6).

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

**Simulation parity (soundscape on/off, `check_parity.gd`) is not established for this change.** The bench flights above ran before commit 459af53f; at HEAD a1fc607f `main.gd` fails to compile because `app/economy/incident.gd` calls the missing `_contact_components()` and `_mark_contact_inspection()` (crash-economics track). A copy with the pre-AUD-11a audio files stops on the same compile errors, so the failure is that breakage, not audio. The change adds no simulation writes: the adapter only reads `sim.time()`. Rerun parity once HEAD compiles.

Source identities (SHA-256 prefixes): `flight_audio.gd` 7af24f813ad9098f, `soundscape.gd` b8e98ac5b76652e9, `soundscape_model.gd` ff8bed099cc69475.

## Open

- Distance-dependent high-frequency loss (ISO 9613-1 trend), the second half of AUD-11.
- Owner listening of the A/B pair (AUD-13).
