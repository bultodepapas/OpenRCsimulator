# AUD-12a — Master safety limiter and crash in the bench

2026-10-18 · **Status: Master limiter, soundscape clipper removal, bench crash scenario and true-peak metric delivered; volume sliders (with the menu track) and the crash-bus limiter (crash track) open.** Plan: [audio realism](../../../plans/audio-realism.md) (F10, F15). Probes: [master-limiter-2026-10-18](../../../../research/audio/master-limiter-2026-10-18/README.md).

## What changed

- [`tools/audio/make_bus_layout.gd`](../../../../tools/audio/make_bus_layout.gd) generates [`app/default_bus_layout.tres`](../../../../app/default_bus_layout.tres), which Godot loads at startup: Master ends in one `AudioEffectHardLimiter`, ceiling −1 dBFS, release 2 s, after every per-scene bus (soundscape, crash, storm, UI). The subresource id is fixed, so `-- --check` compares exact bytes; `app/test.sh` runs it. Scene buses stay dynamic and per-instance.
- [`soundscape.gd`](../../../../app/audio/soundscape.gd) no longer puts `AudioEffectLimiter` on its output bus. The probe showed that effect is a stateless clipper whose knee sits at −2 dBFS: a −1.9 dBFS tone comes out at the −1 dBFS ceiling with −26 dB distortion.
- [`crash_audio.gd`](../../../../app/render/crash/crash_audio.gd) (crash track, one line, coordinated in the plan): crash playback stays off on the Dummy driver only when Movie Maker is not recording. `--write-movie` reports Dummy while mixing, so every capture used to lose its crash sound.
- Bench: a `crash` scenario (full-power dive into the ground), `--view=<camera view>`, and per-frame `absorption_hz` and `update_usec` columns. `bench_analyze.py` adds a 4× oversampled true peak (BS.1770-4 Annex 2 style; −0.07 dB at fs/4, exact at 997 Hz) and counts full-scale samples, since the integer capture clips above 0 dBFS.

## Why this limiter

Four effects measured through the real mixer ([table](../../../../research/audio/master-limiter-2026-10-18/README.md#measured-llvmpipe-48-khz-mixer)): `AudioEffectHardLimiter` is the only one that limits cleanly (−84 dB distortion at +3 dB overload) and is transparent below its ceiling. Its Godot 4.7.2 defect, a constant level offset after any overload, does not accumulate over five bursts and is 0.07 dB at release 2 s (1.2–1.3 dB at 0.12 s). The compressor reduces far more than its ratio implies and has no ceiling.

## Evidence

**Is a limiter needed?** Crash runs, seed 4102026, true peak of the whole mix:

| Aircraft | Pilot view (impact distance) | Chase view (impact distance) | Loudest moment in chase view |
| --- | --- | --- | --- |
| Stik | −18.3 dBTP (30 m) | −5.0 dBTP (5.2 m) | impact |
| Ventage Jet | −26.4 dBTP (83 m) | −2.8 dBTP (7.5 m) | **engine in flight**, before the crash |
| P-51 | −23.9 dBTP (64 m) | −7.1 dBTP (10.5 m) | impact |

No run reached full scale, but the jet's chase view came within 0.8 dB of the old soundscape clipper's knee. Inside the 8 m `unit_size` each voice is already clamped at `max_db`, so this is close to its worst case. The Master limiter now catches the rare excursion without distortion.

**Transparency.** With the limiter in place, the chase-view crashes and the jet flyby keep every stage level and peak (for example jet chase −22.9 dB K and −2.77 dBTP, flyby −41.5 dB K passing). After a constant shift of 90 samples, the captures are **bit-identical** to those without it: the limiter adds 1.88 ms of lookahead latency and nothing else below its ceiling.

**Crash sound in captures.** Before the `crash_audio.gd` fix, all three crashes were silent after impact (−240 dB K over 7–10 s). After it: Stik −69.8 dB K and jet −57.0 dB K in the pilot view, −58.0 and −36.3 dB K in chase view. The P-51 aftermath remains silent in both views; its impact sounds at 3.1 s. Two clicks follow the Stik impact (6.91 and 7.01 s), consistent with the crash-track items F11/F14 in the plan.

**Checks.** `test_soundscape.gd` 150/150: the soundscape output bus carries no effect, and Master's first effect is the enabled −1 dBFS / 2 s `AudioEffectHardLimiter` loaded from the generated layout. `test_wildlife` 26/26, `test_crash_audio` 12/12, `test_crash_presentation_ladder` 43/43, `test_glow_audio` 42/42. `make_bus_layout.gd --check` passes on the generated file and fails (exit 1) on a hand edit. Simulation parity 8/8 fixed-wing configurations with audio on and off, with the same checkpoint hashes as AUD-11 (`soundscape.gd` 04a44c16e504c7dc, `flight_audio.gd` b19424aa3e892f49). [Summary](summary.json); listen to the [Stik chase-view crash](stik-crash-chase.wav).

## Limits and open work

- Not verified by an export on this VM (disk nearly full); `export_filter="all_resources"` includes the layout. Check the next exported pack.
- Volume sliders per bus belong with the menu track (AUD-12b).
- The crash bus keeps its own 0.12 s `AudioEffectHardLimiter` and its 1.2–1.3 dB offset after a loud hit; with Master protecting the sum, the crash track can remove it.
- **Glow-cycle voice cost (finding for NITRO/audio).** The new `update_usec` bench column, flyby under real Movie Maker mixing: stock Stik 336 µs mean per frame (median 306, p95 550, p99 755); `stik-glow-61fx-2t` 2 043 µs (median 2 008, p95 3 038, p99 3 716, max 5 573). The explicit glow voice renders its PCM in GDScript on the main thread every frame, about 6× the stock cost. Absolute values include llvmpipe rendering contention on this VM; the ratio is the reliable part. The 2.8–3.5 ms maxima in the parity runs are this voice's initial buffer fill: on the Dummy driver the generator never drains, so headless timing hides the steady cost.
- Mixer captures on llvmpipe, one seed; not speaker listening.
