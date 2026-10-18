# AUD-12 — Master safety limiter, crash in the bench and game volume

2026-10-18 · **Status: AUD-12a (Master limiter, soundscape clipper removal, bench crash scenario, true peak), AUD-12b game volume and the fleet loudness table delivered; glow-voice level calibration (AUD-12c, proposed) and the crash-bus limiter (crash track) open.** Plan: [audio realism](../../../plans/audio-realism.md) (F10, F15). Probes: [master-limiter-2026-10-18](../../../../research/audio/master-limiter-2026-10-18/README.md).

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

## AUD-12b — game volume

Players could set only the menu cue volume; flight audio had no in-game control. **Settings → Sound → Game volume** now scales the Master bus: everything heard, after every per-scene bus. It uses the menu volume's linear-amplitude curve (50 % = −6.02 dB), and 0 mutes the bus. The value is an optional extension of display settings schema 1 (`[audio] master_volume`, default 1.0), so older files keep full volume, and it follows the existing preview, Keep, Revert and Close contract, also from Pause during a flight.

- [`display_preferences.gd`](../../../../app/app_state/display_preferences.gd), [`settings_screen.gd`](../../../../app/ui/settings_screen.gd) (one shared slider builder; existing node names kept), [`app_root.gd`](../../../../app/app_root.gd) `apply_master_volume()`, EN/ES strings in [`es.po`](../../../../app/i18n/es.po).
- Checks: `test_settings_ui` (validation of out-of-range, NaN, ∞ and string values; older files default to 1.0; preview, Keep, Revert and Close; 50 % → −6.02 dB, 0 mutes, 100 % → 0 dB) and `test_ui_settings_integration` (real keyboard on the slider in the running app mutes Master without saving; Revert restores 0 dB) pass, including the existing "every category fits without scrolling" check. Five deliberate mutations, each detected: app never applying the value, squared curve, value not saved, slider not resynchronised on Revert, range not enforced. `test_menu_audio` and `test_soundscape` 150/150 pass. The full unit partition of `app/test.sh` (`OPENRC_TEST_PART=units`) passed 524/524 scripts on 2026-10-18, with its one pre-existing R02 aerodynamic gate still reported as pending.
- Rendered with [`capture_sound_settings.gd`](../../../../research/audio/game-volume-2026-10-18/capture_sound_settings.gd): [English 720p](settings-sound-en-720p.png), [Spanish 720p](settings-sound-es-720p.png), [Spanish 1080p](settings-sound-es-1080p.png). No overlap; keyboard focus shows on the new slider. Software rendering, not a monitor review.

## Fleet loudness table (AUD-12)

Source level, as the D4 calibration measures it: sweep scenario, engine only, `--audio-delay=off --audio-absorption=off`, ungated K level normalised to 100 m by inverse distance ([`fleet_loudness.py`](../../../../tools/audio/fleet_loudness.py), [data](fleet-loudness.json); seed 4102026; no stage crashed or paused).

| Aircraft | Voice | Full @ 100 m | vs Stik | Idle @ 100 m | Idle vs Stik full | rpm full / idle stage |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Das Ugly Stik .60 (reference) | sample loops | −41.3 dB | 0.0 | −55.5 dB | −14.2 | 11 149 / 2 800 |
| Stik, 61FX 2-stroke | glow cycle | −45.9 dB | −4.6 | −48.6 dB | −7.3 | 16 738 / 12 544 |
| Stik, 55AX 2-stroke | glow cycle | −45.9 dB | −4.6 | −49.3 dB | −8.0 | 14 423 / 10 227 |
| Stik, FS-64V 4-stroke | glow cycle | −47.6 dB | −6.3 | −50.3 dB | −9.0 | 11 505 / 8 942 |
| Extra 300S .60 | sample loops | −41.0 dB | +0.3 | −56.1 dB | −14.8 | 11 149 / 2 800 |
| P-51D, DA-120 | sample loops, 4 blades | −44.8 dB | −3.5 | −56.8 dB | −15.5 | 6 738 / 2 174 |
| Ventage Jet, P100-RX | turbine layers | −37.2 dB | +4.1 | −47.7 dB | −6.4 | 154 000 / 44 011 |
| Turbo Timber | electric | −47.0 dB | −5.7 | −65.9 dB | −24.6 | 9 433 / 701 |

Findings (no stage targets exist except D4; these are consistency checks, not acoustic validation):

- The jet meets D4 (+4.1 / −6.4 dB against +4 / −6). The electric Timber is the quietest at full power and nearly silent at idle, in the expected order. The Extra matches the Stik, as two .60-class glow airplanes with the same sample voice should.
- **The glow-cycle variants are 4.6–6.3 dB quieter than the stock Stik at full power, and only 2.7–3.4 dB quieter at closed throttle than at full.** Throttle reached 0 in every run. Their accepted physics keeps 9–12.5 k rpm in the descending idle stage, which is plausible: a windmilling propeller turns at roughly airspeed over pitch, about 12 k rpm at 30 m/s for a 6 in pitch. The stock model instead holds a fixed 2 800 rpm idle in flight. The glow voice's level, however, follows rpm almost alone (`0.12 + 0.28·√(rpm/max)` in `soundscape.gd`, documented as uncalibrated), with only a −3.7 dB load term inside the voice. A windmilling engine delivers little power, so it should be markedly quieter at the same rpm. Proposed next step (AUD-12c, a decision under D4's method): calibrate the glow voice so the 61FX at full power matches the stock Stik, and make its level follow accepted shaft power or load rather than rpm alone; then rerun this table and listen. Separately, the stock voice's fixed in-flight idle rpm under-represents windmilling (propulsion owner).
- The P-51's 120 cc gasoline twin reads 3.5 dB below a .61 glow at full power. No reference fixes this relation; recorded for the AUD-13 listening review rather than changed.

## Limits and open work

- Not verified by an export on this VM (disk nearly full); `export_filter="all_resources"` includes the layout. Check the next exported pack.
- Separate aircraft/environment sliders were not added: the scene buses are per-instance, and one game volume covers the reported need. Add them only if players ask.
- AUD-12c (proposed): glow-cycle voice level calibration from the fleet table above.
- The crash bus keeps its own 0.12 s `AudioEffectHardLimiter` and its 1.2–1.3 dB offset after a loud hit; with Master protecting the sum, the crash track can remove it.
- **Glow-cycle voice cost (finding for NITRO/audio).** The new `update_usec` bench column, flyby under real Movie Maker mixing: stock Stik 336 µs mean per frame (median 306, p95 550, p99 755); `stik-glow-61fx-2t` 2 043 µs (median 2 008, p95 3 038, p99 3 716, max 5 573). The explicit glow voice renders its PCM in GDScript on the main thread every frame, about 6× the stock cost. Absolute values include llvmpipe rendering contention on this VM; the ratio is the reliable part. The 2.8–3.5 ms maxima in the parity runs are this voice's initial buffer fill: on the Dummy driver the generator never drains, so headless timing hides the steady cost.
- Mixer captures on llvmpipe, one seed; not speaker listening.
