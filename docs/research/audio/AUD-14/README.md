# AUD-14: recorded wind and windsock fabric

2026-10-19. User scope: wind and windsock sounds. Engine and wildlife sources are unchanged. Current behavior is owned by [the audio guide](../../../AUDIO-PLAN.md).

## Sources and editing

Two primary recording pages explicitly mark their sounds **CC0**:

- SamuelGremaud, [WIND - 1](https://freesound.org/people/SamuelGremaud/sounds/547472/): wind in trees in southern France, recorded with a Zoom H4N Pro and Rycote windscreen. Used for the two wind layers.
- bmacphail, [Tent Fabric Flapping in Wind Ambient](https://freesound.org/people/bmacphail/sounds/569537/): shell fabric flapping in light wind. Used as a quiet material proxy for windsock fabric.

The downloaded sources are the public HQ MP3 previews, not the original WAV uploads. Downloads, author metadata, original-upload specifications, candidate recordings and SHA-256 identities are retained in [the source record](../../../../research/audio/AUD-14/recordings/environment/README.md). Two other CC0 candidates were retained as references and are not played. The recordings' CC0 notice is separate from the adjacent MIT generated pack.

[`import_wind_recordings.py`](../../../../tools/audio/import_wind_recordings.py) regenerates the three assets using NumPy 2.4.6 and miniaudio 1.71. Each edit removes DC, uses a one-second circular overlap, applies a smooth frequency filter, and normalizes with a 0.42 peak cap. `--check` verifies source identities, exact output bytes/manifest and unmodified PCM imports. The manifest records every edit and measured seam step.

| Runtime loop | Length | Filtering | Purpose |
| --- | ---: | --- | --- |
| `recorded/wind_low.wav` | 19 s | 40–3,200 Hz | Wind body |
| `recorded/wind_high.wav` | 18 s | 950–8,500 Hz | Stronger-wind hiss |
| `recorded/windsock_fabric.wav` | 21 s | 150–8,500 Hz | Local fabric rustle/flap |

All are mono 22.05 kHz PCM16. Source PCM totals 2,557,800 bytes, 88,200 fewer than the previous two generated wind loops together, before the tiny runtime wrap guards. The original generated files remain reproducible historical assets. Runtime selects the recorded wind files. The longest new loop repeats every 21 s; no per-sample synthesis or decoding runs in GDScript.

Review rejected an earlier fabric selection from 6–28 s: sparse sharp transients forced the peak-capped RMS down to 0.00935. The accepted 24–46 s section reaches 0.018 RMS at 0.419 peak, about 5.7 dB more sustained rustle while keeping the same peak limit. This is an objective balance adjustment; it does not substitute for listening.

## Runtime behavior

`FlightAudio` reads `FlightSession.wind_at(sim.time())`, including gusts and turbulence. The existing direction-dependent wind-bed positions and strength envelopes now play the recordings. Removing the low-wind baseline permits calm-air silence for those two layers. Existing foliage/wildlife behavior is retained.

One optional `WindsockAudio` player belongs to the field's windsock, outside the existing 14-voice pool. Its source follows the unsupported sleeve centre from the visual centreline; it reads inflation without changing the visual or flight simulation. Wind gates its level smoothly from 1.2 to 12 m/s, with a 0.22 linear cap and a modest 12% reduction as cloth becomes taut. These are authored estimates. The 0.15 s exponential envelope uses elapsed frame time, and the exact shared scene gain preserves pause/resume and engine ducking. The player is positioned before starting, stops on reset/detach, rebinds after retained-scene reattachment, uses 2 m distance scale and a 55 m cutoff, and disables Doppler for this anchored source.

## Verification

- Pinned Godot 4.7.2 import and focused script execution; no script errors in the final import.
- Existing soundscape **150/150** and wildlife **26/26** checks pass.
- Windsock-motion regression checks **35/35** pass.
- Recorded-audio checks **47/47** pass: exact asset hashes, PCM imports, full durations and 64-frame wrap guards; calm/strong response; actual snapshot position; equal settled gain at 30/60/144 updates/s; pause/reset, detach/rebind and bus cleanup; no source on a field without a windsock.
- Actual `main.tscn` environment checks pass for calm, steady and gusty weather; the adapter's speed equals the accepted wind sample, and source/inflation equal the current visual sock. Audio-off and legacy routes pass.
- Windows resource-pack export loads **33/33** imported WAVs with matching sample counts, all three manifests and MIT/CC0 notices from an empty project. This is not an installer qualification.

- [Exact simulation parity](parity.json): **8/8** fixed-wing aircraft pairs, 1,200 accepted ticks each, 24 paused samples each, and reset; audio snapshot/update preserve full checkpoints and simulation RNG state. Rotorcraft are explicitly outside this fixed-wing harness. This is software equivalence, not physical validation.

Windows WASAPI captures at [30](wind-30.json), [60](wind-60.json) and [144](wind-144.json) FPS passed finite-sample, clipping, pause, distance-cutoff and bus-cleanup checks. All reported zero discarded capture frames; measured update rates were 30.09, 60.10 and 144.10 Hz. Peaks were about -19 dBFS. Wind-only `Soundscape.update_sound` p95 was 174/229/187 microseconds respectively, with maximum 471 microseconds across these runs. These timings exclude the flight adapter, renderer and mixer thread.

The [60 FPS listening capture](../../../../research/audio/AUD-14/captures/wind-60.wav) contains seven three-second stages: calm; 3 m/s; 12 m/s; gust and reversal; pause; resume near the sock; move beyond the fabric hearing limit. The capture taps Master after its limiter. An isolated fabric capture bus measures the sock before the environment sum; it is a harness-only routing change. Steady-stage measurements ignore the first 0.5 s for transitions. Paused settled output and far isolated fabric are digital zero, represented by a finite -240 dBFS report floor. Native `stream_paused` is true after the pause fade. Source identities are embedded in the reports.

An [earlier capture](wind-60-clock-shortfall.json) produced only 20.17 s of samples over 21.00 s of wall time, despite zero capture-buffer discards. Its cause is unqualified; do not use the discard counter as proof of device deadline compliance. One 30 FPS harness exit also warned about 24 ObjectDB instances at teardown. The harness now allows 0.25 s after stopping/removing playback for the mixer to drain; the final three runs have no script errors, resource warnings or clock shortfall beyond normal buffer granularity. These measurements still do not qualify target-device audio deadlines.

## Limits

These are lossy-source field recordings edited for an interactive mix. The fabric is a material proxy, not a calibrated recording of this windsock; individual recorded flaps do not synchronize with each visible wrinkle. Gains and distance limits are presentation estimates, not measured SPL. Native mixer measurements cannot establish speaker/headphone sound quality. Owner listening, target-device mixer cost and Linux/macOS device qualification remain open. The overall soundscape's earlier speaker acceptance does not imply acceptance of these new recordings.
