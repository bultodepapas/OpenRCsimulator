# AUD-15 fleet lifecycle validation

Evidence date: 2026-10-20. The bench covers the eight active fixed-wing catalog entries and the active XCell helicopter. It captures PCM from the production audio adapter with native WASAPI `AudioEffectCapture`; it does not render Movie Maker video or claim speaker-level or human-listening validation.

## Baseline capture and limits

The first native run produced eight WAV/report pairs under ignored `tmp/audio-aud15/fleet/`; the 55AX run timed out before writing a pair. This batch predates the corrected accepted-tick schedule, runway pilot, helicopter pickup input, and final asset/mix updates. Preserve it as a baseline only. The checker classed four of the eight available pairs as passing its then-current capture gates; later strict gates require pre-master finite-sample and glow-generator skip-counter evidence, which this batch did not fully record.

| Aircraft | WAV duration | PCM peak | Observed route result |
| --- | ---: | ---: | --- |
| Jensen Ugly Stik | 41.973 s | −9.72 dBFS | No runway liftoff; staged landing contact and rollout; route crash observed |
| Stik 61FX | 41.237 s | −19.20 dBFS | No liftoff or landing contact; route crash; 33,792 master and 33,280 pre-master frames discarded |
| Stik 55AX | — | — | Capture pair missing after wrapper timeout |
| Stik FS64V | 41.131 s | −24.28 dBFS | No liftoff; staged landing contact and rollout; route crash observed |
| GP Extra 300S | 41.995 s | −21.86 dBFS | Liftoff, contact, and rollout observed; route crash observed |
| P-51D Mustang | 41.995 s | −30.29 dBFS | No liftoff/contact; no route failure. The takeoff phase advanced only 492 accepted ticks (2.05 simulated seconds) in 12 wall seconds, so it did not receive enough simulated runway time |
| Sebart Avanti S | 41.995 s | −31.59 dBFS | No liftoff/contact; route crash observed |
| Turbo Lumber Evolution | 41.813 s | −11.89 dBFS | Liftoff, contact, and rollout observed; route crash; 9,728 master and 7,168 pre-master frames discarded |
| XCell-60 helicopter | 36.992 s | −36.61 dBFS | Motor-arm request refused; RPM stayed at zero, so the WAV did not qualify as engine audio; contact/settle alone is not a flight cycle |

No fixed-wing aircraft passed a continuous takeoff-to-landing gate. Even where contacts were observed, the landing approach was reset to a descending `FlightSession` fixture; therefore those runs do not qualify as continuous flights. The helicopter baseline also failed its engine-start gate. All eight WAVs were unclipped, but this alone does not establish a useful engine signal, loop quality, or listening quality. Several captures were short or overran their `AudioEffectCapture` buffers. Generator underrun counters and pre-master finite-sample checks were unmeasured on parts of this baseline.

The current frozen source-loop screen reads six uncompressed PCM16 loops. `wrap gap` is the last-to-first sample delta; `p99/max step` are adjacent interior frame deltas, normalized to full scale. These are numerical screens, not perceptual seam verdicts.

| Family / role | Duration | Wrap gap | Interior p99 / max step |
| --- | ---: | ---: | ---: |
| Gasoline low / engine | 1.35 s | 0.0127 | 0.0290 / 0.0810 |
| Gasoline high / engine | 1.00 s | 0.0210 | 0.0330 / 0.0654 |
| Electric / prop | 8.25 s | 0.0139 | 0.0262 / 0.1121 |
| Turbine / engine | 11.00 s | 0.0447 | 0.1595 / 0.2393 |
| Rotor low / main rotor | 3.50 s | 0.0262 | 0.1143 / 0.2213 |
| Rotor high / main rotor | 4.00 s | 0.0337 | 0.1309 / 0.2647 |

The source pipeline check passes all six powertrain loops. These values do not establish that any loop is inaudible at its join.

## Corrected repeatable sequence

`tools/audio/fleet_sequence.gd` advances phase boundaries using accepted `FlightSession` ticks and records both monotonic wall time and accepted simulation time. A wall timeout bounds stalled runs, and telemetry keeps separate session epochs across fixture resets. It fixes the global random seed at 15015 and disables scenery. Fixed-wing takeoff uses the existing Stik-tuned `TakeoffPilot`; target throttle positions are converted to the keyboard-style rate command expected by `read_raw`. The current harness holds the initial runway heading with yaw/roll feedback during taxi and takeoff. The v3 captures below predate that taxi-heading correction and show the earlier pilot hitting the airfield barrier before liftoff. If runway liftoff is not observed, the harness labels and stages an airborne presentation segment; that fixture cannot satisfy the runway takeoff gate. Landing starts from an explicitly reported descending fixture. The four Stik-family captures use the existing Stik landing maneuver; other fixed-wing captures use the simpler bench input. Contact and rollout are still read from live session state. Helicopter startup retains the accepted ground-start zero-pitch pickup through motor arming and rotor spool-up. The separate `--continuous` mode now holds full power with the existing Stik-tuned `TakeoffPilot` until gear separation is observed for 0.1 accepted seconds, then hands off to the experimental E3c2a circuit pilot's `initial_climb` phase in the same session. Its direct per-tick `session.commands`/`sim.inputs` assignment matches the existing `CircuitDriver`; it does not reset to presentation fixtures.

The repeat uses a new output directory to preserve the baseline:

```powershell
python tools/audio/check_fleet_sequence.py --out-dir tmp/audio-aud15/fleet-final --wall-timeout 360 --timeout 420
```

The current wrapper hashes the audio runtime, pump, ground mixer, bank/gear manifests, harness, checker, input/session/simulation code, and the referenced pilot sources before and after each capture. Reports retain exact aircraft file and semantic data hashes, the accepted weather configuration, and field/runway identity. It uses observed event wall times for PCM stage boundaries, reports accepted tick and simulation spans by session epoch, rejects silent/no-RPM captures, and checks pre-master finite/over-unity samples, logs, clipping, capture overruns, source identity, and glow-generator skip counters. It stores WAVs, native logs, raw reports, and compact analyses in the ignored output directory. A null measurement is listed as unmeasured and does not count as a passing gate. Engine and wheel levels are runtime model diagnostics; their shared aircraft bus prevents this bench from claiming isolated wheel PCM energy. During capture the harness stores complete AudioEffectCapture chunks; it concatenates and scans them after the run to reduce work in the live audio path.

## Final fleet capture before the source-pump fix

The first hashed nine-aircraft repeat completed all catalog entries. All nine source identities stayed unchanged through their native runs. No WAV had PCM clipping or capture-buffer drops. Five aircraft used the glow generator; four exceeded its skip-counter gate. Those four are invalid audio captures and are not counted as clean engine evidence. The recorded-bank gasoline, turbine, electric, and rotor captures passed the PCM and source-health gates. Several WAVs are longer than the 42-second accepted-time sequence because the host advanced physics slowly; wall-clock stage boundaries and accepted simulation spans are both recorded. The dedicated-thread source pump has since been integrated. The detailed pre-pump v3 artifacts are in `tmp/audio-aud15/fleet-final/`.

| Aircraft | WAV | Audio capture | Observed live route outcome |
| --- | ---: | --- | --- |
| Jensen Ugly Stik | 35.45 s | Pass; glow skips 0 | No runway liftoff; staged landing contact and rollout. Runway fence impact at takeoff tick 3720: post 10, 8.6 m/s normal speed. |
| Stik 61FX | 101.48 s | Fail; +12,090 glow skip deltas | No runway liftoff; staged landing contact and rollout. Barrier rail impact at takeoff tick 2879, 2.0 m/s normal speed. |
| Stik 55AX | 104.80 s | Fail; +12,598 glow skip deltas | No runway liftoff; staged landing contact and rollout. Barrier post 10 impact at takeoff tick 2995, 2.2 m/s normal speed. |
| Stik FS64V | 96.61 s | Fail; +11,550 glow skip deltas | No runway liftoff; staged landing contact and rollout. Barrier post 07 impact at takeoff tick 2502, 1.8 m/s normal speed. |
| GP Extra 300S | 74.66 s | Fail; +7,093 glow skip deltas and incomplete schedule | Runway liftoff and landing contact observed; `main_right` gear travel limit at tick 1568, 20.57 m/s, before rollout. |
| P-51D Mustang | 69.82 s | Fail; incomplete schedule | Barrier rail impact during taxi at tick 2173, 6.9 m/s normal speed; no runway takeoff or landing contact. |
| Sebart Avanti S | 110.51 s | Pass | Staged approach ended in hull contact at shutdown tick 3456, 27.6 m/s; no liftoff, touchdown, or rollout. |
| Turbo Lumber Evolution | 44.46 s | Pass | Runway liftoff, staged landing contact, and rollout observed with no crash. The fixture reset excludes continuous-flight qualification. |
| XCell-60 helicopter | 36.92 s | Pass | Motor arm and drive release accepted; rotor liftoff and full stage schedule observed; no landing contact or settle. |

The suite reports `all_audio_captures_valid=false`, `all_live_contact_sequences_complete_without_route_failure=false`, and `all_continuous_flights_qualified=false`. Audio validity and route outcomes are separate: a successful WAV does not certify the pilot or flight route. Fixed-wing approach fixtures reset `FlightSession`, so the contact and rollout evidence is staged. The v3 Stik takeoff collisions exposed a limitation in the prior harness pilot: heading feedback began at takeoff, and its target was sampled late. The current taxi heading hold uses the initial runway heading; Jensen, 55AX, and FS64V post-pump captures subsequently observed takeoff and staged landing contacts without a route crash. These runs still reset for landing, so they do not qualify as continuous flights. The route failures do not establish faults in the production flight model.

## Post-pump targeted recaptures

`fleet-postpump/` contains five glow-profile recaptures, plus Extra and P-51 follow-ups. All five glow counters stayed clean. Three of six captures passed the full capture gates; all were staged fixed-wing sequences, not continuous flights.

| Aircraft | Capture gate | WAV / report wall time | Route observation |
| --- | --- | ---: | --- |
| Jensen Ugly Stik | Pass; glow skips 0 | 41.920 / 41.920 s | Liftoff observed; staged landing contact and rollout; no route crash. |
| Stik 61FX | Fail; glow skips 0; no dropped capture frames | 132.5867 / 132.7449 s (158.2 ms short) | Liftoff and staged landing contact/rollout observed; no route crash. |
| Stik 55AX | Pass; glow skips 0 | 132.544 / 132.545 s | Liftoff and staged landing contact/rollout observed; no route crash. |
| Stik FS64V | Pass; glow skips 0 | 125.440 / 125.442 s | Liftoff and staged landing contact/rollout observed; no route crash. |
| GP Extra 300S | Fail; clean glow counter; incomplete timeline | 76.736 / 76.736 s | Live landing ended early on `main_right` gear travel limit at tick 1568; rollout was not observed. |
| P-51D Mustang | Fail; no glow generator; no dropped capture frames | 122.848 / 123.2797 s (431.7 ms short) | Liftoff observed, but no landing contact or rollout. |

The 61FX and P-51 runs fail the strict 120 ms WAV-versus-wall gate. The Extra produced useful unclipped PCM with clean source status, but the live crash ended its timeline early. These fixed-wing captures use staged landing fixtures and do not establish continuous flight.

The isolated native pump stress probe is a separate presentation test, not full-scene qualification. It used a real 3D generator player with five 25 s near/far/quiet phases and a 600 ms busy-script stall in each. It passed with zero skips, zero worker errors, and zero discarded PCM frames; it captured 124.928 s against 125.000 s wall time (72.1 ms short). This rules out those distance/quiet/stall cases by themselves. It does not reproduce the full-scene physics and main-thread workload of the 61FX long capture.

## Continuous route follow-up

The retained `continuous-v1` and `continuous-v2` Jensen trials used the existing E3c2a pilot without a mid-route reset but crashed during flight at tick 18,247: hull point 3, 15.66 m/s point speed and 13.25 m/s sink. A review found that the pilot's stick deltas were being sent through the keyboard-rate `read_raw` interface, while the original `CircuitDriver` assigns them directly to `session.commands`. The v3 harness now matches that direct per-step contract and records the controller/session/source hashes plus aircraft input and semantic data identities.

The current direct-command retry is preserved in `tmp/audio-aud15/continuous-v3/`. On the calm default field, with Jensen input SHA-256 `5ef239c6…bd2007` and semantic SHA-256 `6d468e26…4611`, it advanced to the configured 180.008 accepted-second cap without a crash or simulation fault, but never observed liftoff. Its last telemetry row had all three gear contacts grounded, 12.64 m/s speed, 0.229 m height, and 12.64 m/s contact speed. This is an incomplete route, not evidence that the Stik pilot passes on current aircraft data; the existing reference driver permits up to 240 seconds, so the 180-second capture cap also limits that conclusion. No landing or rollout was observed.

This WAV is not a clean source-health qualification: it peaks at −28.54 dBFS with no PCM clipping or capture-buffer drops, but the glow source counter increased by 714 skips and the captured 187.691 seconds trail 192.208 seconds of wall time by 4.517 seconds. The strict 120 ms duration check therefore fails. The frame-lag series reached about 4.53 seconds behind wall time over the run. Three unrelated headless Godot probes were also active on the host; this is context, not a proven cause of the timing or skips. The capture demonstrates a useful unclipped signal while leaving both the continuous route and long-run source/timing gates unqualified.

## Other checks and open limitations

The production powertrain test reports 43/43 checks, including the four bank families, pause/reset behavior, and helicopter checkpoint immutability. A 100 ms real-time mixer drain after helicopter teardown removed intermittent audio-resource warnings there; one existing maple-material warning remains. The fixed-wing audio/gear parity check reports 8/8 aircraft; the latest ground-audio suite reports 27/27 checks. Soundscape and glow suites previously reported 168/168 and 42/42. Full parity logs still show two ObjectDB-at-exit warnings for the existing `AudioStreamMP3`/`AudioStreamPlaybackMP3` water ambience (`water/randommind-vistula-short.mp3`); no pump/thread object is implicated, and water audio is outside AUD-15. The final post-pump native mix stress probe used a 3 m, 30-degree turbine exhaust position at rated RPM and full load: 68 checks passed, none failed, six skid/roll checks were not applicable, peak was −2.934472 dBFS, both glow generator skip counters stayed at zero, and no native audio warnings were recorded. `mix-near.json` is the current gain record; the earlier 8 m `mix.json` predates the turbine headroom trim and pause-resume refill fix. A fresh isolated project loaded and exported all 43 audio resources and their notices successfully.

The legacy `test_engine_audio.gd` remains an unrelated open failure: four queue-target assertions fail among 146 checks because its refill target changes while queued samples are draining; the legacy adapter and test were not changed for AUD-15.

These checks establish software behavior and captured PCM properties only. They do not establish real-aircraft acoustic fidelity, physical flight validity, or a complete uninterrupted flight. The corrected fleet recapture is stored under ignored `tmp/audio-aud15/fleet-final/`; per-aircraft JSON reports contain WAV metrics, stage epochs, capture source hashes, and route failure detail. A clean audio capture is not a successful flight gate, and fixture resets are never counted as continuous flight.
