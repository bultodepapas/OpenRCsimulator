# VQ-01c — runtime efficiency audit, 2026-10-23

Two small CPU changes were retained. No FPS, input-latency, loading-time or GPU speedup is established. The production changes are in `app/audio/ground_audio_model.gd`, `app/main.gd` and the audio regression test. Concurrent work included these paths in commit `49484460`; this audit did not create that commit or its unrelated flight-dynamics changes.

- Ground audio now copies the outer landing-gear dictionary rather than recursively copying data that `Ground.loads` only reads. The active contact was already shared by the previous implementation. This removes repeated copying in the airborne fallback.
- The HUD's 240-frame history removes its oldest element in place instead of allocating a replacement slice. Sample order, precision, window size and displayed statistics are unchanged. [Godot's packed-array contract](https://docs.godotengine.org/en/4.7/classes/class_packedfloat64array.html) describes the operations.

## Measurements

Native Windows source/editor, Godot 4.7.2, Ryzen 9 5900X, RTX 3090/NVIDIA 617.42, Compatibility, 1920×1080 fullscreen on the virtual 60 Hz output, VSync on, FPS cap 0, Dummy audio. Each accepted flight used 10 seconds warmup and 60 seconds sampling. Background desktop activity was not controlled; these are two run-level pairs, not a hardware qualification or pooled-frame confidence claim.

| Stik / Club flight pair | Audio callback median, µs, before → after | Audio callback p95, µs, before → after | Frame p95 / p99, ms, before → after |
| --- | --- | --- | --- |
| A then B | 581 → 509 | 694 → 607 | 17.471 / 18.274 → 17.547 / 18.289 |
| B then A | 657 → 555 | 1164 → 941 | 18.231 / 21.305 → 17.810 / 19.606 |

The measured timer is the existing **whole `FlightAudio` callback**, not just the edited line. Median-of-run-medians is 619 → 532 µs (14% lower). This supports reduced callback work, not smoother frame pacing. All four accepted samples advanced about 14,400 measured physics ticks with no pause, fault, hold or crash; pause/focus event logs stayed stable. A separate untimed native counter verified 340 snapshots and 1,020 fallback contacts and the cached script binding.

Isolated snapshot repeats measured 172.719 → 107.929 µs initially and 144.816 → 87.320 µs in a later process (30 alternating batches each). These component timings do not establish whole-game speed. Frame-history maintenance measured 0.37305 → 0.105275 µs/update across 30 alternating batches; the absolute saving is tiny. Every window and HUD string matched across a retained 3,600-frame gameplay tape.

## Verification and rejected work

- 13 focused native-Windows test scripts passed, including 31 ground-audio assertions, four golden flights, checkpoints, wheel/ground/lake contacts, audio and frame collection. A separate 42-case Stik/P-51/Avanti comparison covered diagnostic/fallback, terrain/lake and retractable gear, with byte-identical contact output and unchanged state/gear data. Physics formulas, data and golden recordings were not changed.
- The final production Avanti / Green Paradise run completed 60 seconds with active physics: frame p50/p95/p99 16.640/19.871/21.983 ms, maximum 34.426 ms; no engine diagnostic warnings. It is a stability observation, not a matched speed comparison. Its Club-specific grass diagnostic could not verify a `NearGrass` node on this landscape.
- The final native Club/Stik inspection capture is 1920×1080 with aircraft and scenery visible. It is a paused technical capture, not manual pilot acceptance or a matched visual-difference test. Render sources/assets are unchanged. Images stay in ignored `tmp/perf-20261023/final-native/`, outside retained evidence.
- Rejected: skipping zero-weight ground parcel shading (small offscreen gain did not repeat in full-flight GPU measurements); removing a windsock mesh conversion (normal/tangent arrays changed); aerodynamic flow arithmetic reuse (noise-level result); an extra aircraft cache (ordinary resource loading was mistaken for repeated cached work). No rendering/physics candidate was adopted.
- Corrected visual analysis: four shader-trial image pairs matched exactly; flightline had 27 changed RGB pixels, lake 1,013. An initial RGBA/alpha-only bounding-box comparison missed those differences. The source shader remains unchanged.
- Excluded audio campaign 01: overlapping unauthorized headless diagnostic processes and a paused candidate. Campaign 02's third process exited before producing measurements; its first valid A/B pair and separate campaign 03 B/A pair are retained. Failures were not treated as passes. One overwritten scratch coverage report is unrecoverable; the exclusive repeat is retained.
- Existing shutdown warnings remain: 19 ObjectDB instances in the B/A **baseline** flight, and two in `test_powertrain_audio`. Their cause is not established. No full `app/test.sh` or `app/capture.sh` success is claimed: WSL failed to start. Linux, Apple Silicon, Forward+, physical-display latency, release packages and audible playback are unqualified here.

Raw results, commands, frozen candidates, probes, checked logs and per-file identities are in `evidence.zip` / `manifest.json`. No PNGs are included.

## Final adversarial review

Good Enemy completed a read-only review after independent regression, measurement and gameplay checks: no must-fix findings. It confirmed the read-only ground/lake call path and the frame-history invariant. It withdrew a test-coverage objection after tracing the airborne wheel evaluator's empty-diagnostics early-out, which does reach the changed fallback. Its main constraint is retained: two Dummy-audio pairs support a callback-cost reduction, not an FPS, latency or audible-playback improvement. The auditor's mistaken windsock zero-mismatch summary was corrected against the raw eight-mismatch result before rebuilding this archive. No additional production changes were required.
