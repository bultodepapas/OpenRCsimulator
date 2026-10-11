# AUD-04 — Gameplay audio qualification

2026-10-11 · **Status: final PCM gameplay, speaker checks and frozen full regression passed.** Dedicated mixer-thread CPU and target-platform acceptance remain unqualified.

The default soundscape delivers aircraft motor/propeller/airframe layers, two wind beds, four foliage sources and spatial bird phrases. It reads accepted simulation state, uses actual field coordinates and listener position, and owns no simulation state. [Implementation](../AUD-03/README.md), [sources and licenses](../AUD-01/sources.md), [reproduction commands](../../../../tools/audio/README.md).

## Listening and real gameplay

The user listened on **stereo speakers** to a rendered 35-second Windows/OpenGL gameplay run with WASAPI output. The tape used the real flight scene and keyboard-rate throttle commands, then pause/resume, close camera and restart. After the final PCM-import correction, the user answered **“Aircraft clear, ambience natural”** to the balance/obvious-loop/transition question. This is user-reported perceptual acceptance, not an assistant audition or calibrated acoustic measurement.

The final [stereo mixer capture](speaker-review.wav), [rendered frame](speaker-review.png) and [event/timing report](runs/audio-pcm-rendered-60.json) are retained. The capture is 35.019 seconds at 48 kHz, stereo 16-bit. Its PCM SHA-256 is recorded in [capture checks](captures.json). Looping source WAVs are 22.05 kHz mono; the engine resamples/mixes to the output device rate.

Nine native WASAPI captures cover default combustion, Extra 300S, P-51 four-blade propeller, Avanti turbine, electric battery route, gusts, optional scenery and 23:00 lighting. All complete throttle rise/fall, pause, resume, camera change and restart; capture samples reach exact silence during the settled pause. No PCM full-scale rail, ceiling violation or capture-frame discard was found. These are output samples and capture-queue checks, not a hardware xrun or analog true-peak measurement.

| Case | Requested FPS | Peak dBFS | Adapter p95 / maximum, ms |
| --- | ---: | ---: | ---: |
| Rendered Stik, 35 s | 60 | -1.06 | 0.136 / 0.325 |
| Gusty Stik | 30 | -5.48 | 0.186 / 0.682 |
| Gusty Stik | 144 | -4.19 | 0.173 / 1.195 |
| Avanti turbine | 60 | -5.40 | 0.183 / 0.820 |
| Electric Stik, 4s battery | 60 | -12.80 | 0.159 / 0.378 |
| Gusty + scenery | 60 | -5.82 | 0.193 / 1.735 |
| Night, 23:00 | 60 | -6.11 | 0.182 / 1.349 |
| P-51D | 60 | -5.80 | 0.151 / 0.819 |
| Extra 300S | 60 | -5.63 | 0.154 / 0.581 |

[Machine-readable checks](captures.json) and [per-run reports](runs/) retain timestamps, physics ticks, RPM, driver, source hashes and distances. All nine use the final PCM imports and runtime code. Earlier QOA captures were superseded and are not acceptance evidence. The requested FPS values are frame caps, not a guarantee that every frame hit that interval. Runs shared the host with other development suites.

## Spatial and environmental checks

- The final [native profile](native-profile.json) observed pilot-view Doppler **0.93583–1.04389** across the real physical pass, with a closest pilot distance of **66.45 m**. The close-camera stage reaches **2.5 m**. Numeric tests check the expected approach/recede ratios, both moving endpoints and co-motion; camera cuts reset the observer.
- [Environment/route integration](environment-routes.log) reads the actual flight adapter at 23:00/gusty: sun elevation **-73.17°**, wind **3.0 m/s** at the sampled instant. With scenery on, exactly one old ambience bed exists and is stopped/disabled by the new mix. The off route disables it too; legacy engine remains available.
- [76 soundscape checks](soundscape-tests.log) pass: source kind, full-duration PCM loops, six usable phrases, 120 simulated scheduler seconds per propulsion kind, no adjacent phrase repeat, day/night/wind activity, windmilling, four-blade frequency, canopy screening, fade/reset, dedicated buses, private RNG and teardown.
- Generator verification passes for all 14 original sources, including hashes, seam-step bounds and pitch-aware bandlimits. Seam metrics and adjacent sample steps are useful diagnostics, not automatic proof of perceptual seamlessness. The speaker pass is short; long-session repetition fatigue remains untested.

## Performance budget and proof

| Budget | Result |
| --- | --- |
| At most 14 voices | **12 bounded players**; inactive bird/turbine-prop layers cannot grow the count |
| At most 8 MiB source PCM | **4.695 MiB**, entire 14-file source library; not total process memory |
| Adapter update p95 below 0.5 ms | **0.136–0.193 ms** across final nine captures; includes accepted-state snapshot and soundscape update |
| Mixer under 1 ms | **Unqualified**: Windows identifies worker threads but does not name either active main/audio candidate; no mixer-specific result is inferred |
| Output peak at most -1 dBFS | Final captures pass the -0.9 dBFS numerical tolerance; highest measured sample peak **-1.059 dBFS** |
| No capture drops | **0 in all nine captures and final native profile** |

The Windows profiler was corrected to target the actual `Godot_v4.7.2-stable_win64.exe` child instead of its idle console launcher, and to interpret HRESULT success by its sign bit. The final 16.329-second window measures **5312.5 ms total engine-process CPU** (32.53% of one core). That includes simulation, rendering infrastructure, capture and audio. It is **not audio CPU cost**. Thread-counter averages cannot establish per-block p95, deadline misses or device latency. Raw counter endpoints, target identity, worker names, host information and limitations remain in [native-profile.json](native-profile.json). Main-thread maxima up to 1.735 ms reflect this shared-host run; the budget is a p95 target, not a worst-case guarantee.

## Simulation, lifecycle and packaging

Final live-app [fleet parity](parity.json) and [electric parity](parity-electric.json) pass **5/5 paired routes**, each 1200 ticks per on/off run at 240 Hz with turbulent weather and a fixed accepted input tape. Every full `FlightSession.checkpoint()` is compared byte-for-byte, including turbulence RNG; 24 pause snapshots and post-reset checkpoints also match. This is exact simulation evidence, not an acoustic calibration.

The [pause/menu lifecycle check](pause-lifecycle.log), [electric input check](electric-input.log) and [time-of-day cleanup check](time-of-day-edit.log) pass. A regression initially exposed a helper that freed the legacy motor alias while the new adapter still processed it. The helper now disposes the whole adapter; an independent Luna/max review found no other asynchronous alias-free site. These regressions also pass in the final frozen full suite below.

The [exported-pack check](pack-check.log) mounts the Windows resource pack from an empty project and loads **14/14** sources with the expected 16-bit mono PCM sample counts, manifest and MIT notice. All three export presets include the provenance/notice. This verifies resource packaging; no new installer or native Linux/macOS audio acceptance is claimed.

Full regression: **`app/test.sh` exited 0**, including **185 `test_*.gd` scripts**, the 76 audio checks, all-script parsing, float64 guard, integration/golden flight, CLI/input, 30/60/144 FPS state hashes and final E5a/E5b ground-contact checks. The [complete log](full-suite.log) contains no engine/script/shader errors. The candidate is a fresh local clone at `f83204d`, overlaid with the complete app/tools/research/assets working tree, with text normalized to LF and an isolated `XDG_DATA_HOME`. [Hashes of all 886 frozen app files](regression-snapshot.json) identify the tested state. Runtime audio and PCM import settings were frozen before this run.

During the run, another track committed shared work as `d486ec2` (including audio files), then added an uncommitted CrashDirector hook and crash/session changes. Those later crash changes are **excluded from this full-suite result**. This audio team did not stage, commit, revert or overwrite them.

A subsequent read-only compatibility review of the live CrashDirector tree passed the 76 audio checks and the scenery/off/night/gusty route probe. Crash holds fade the soundscape, aftermath audio follows user holds, reset signals reach both systems, and wreck-camera updates precede the audio observer. No lifecycle/API incompatibility was found. The crash and soundscape buses independently limit before sending to Master; **their combined peak during the crash fade has not been captured**. The -1 dBFS acceptance above applies to the measured soundscape output, not that later composite mix.

## Review, ownership and limits

The lead reviewed all Luna/max contributions: original asset generator and bandlimits, primary-source/license research and focused tests, independent integration/parity/lifecycle review, and native profiler. Shared edits are limited to the main hook, three export include filters, one test cleanup helper and additive registry/tool/lesson documentation. Concurrent UI, electric propulsion, shadow and landscape work is preserved. G3b files and experiments remain available in legacy mode; the user confirmed no other audio developer was active.

The sources are original synthesized material under the repository's MIT notice, not field recordings. CC0 field/RC recording candidates were researched but not downloaded, incorporated or auditioned. Acoustic timbre calibration, propagation travel delay, building/terrain diffraction, species-specific birds, headphones, hardware latency, long-session fatigue and other native platforms remain outside the verified result. Canopy screening and source gains are explicitly authored approximations.

Suggested audio change description: `AUD-01..04: dynamic field/aircraft soundscape; proof: frozen full app suite, 76 audio checks, five exact simulation parity pairs, nine final WASAPI captures, stereo-speaker acceptance, PCM export verification; mixer-thread budget remains unqualified`. Select only audio-owned hunks in shared files; parts of this work were already included by another track's shared commit.
