# G3b audio qualification tools

**Status:** software qualification tools; no acoustic calibration or hardware acceptance.

Use the project's pinned Godot 4.7.2. Python 3.10+ standard library is sufficient.

```
python research/audio/g3b/verify.py --godot /absolute/godot --app app --out /absolute/fresh/g3b-checks
godot --headless --path app --script /absolute/research/audio/g3b/voice_bench.gd -- --out=/absolute/bench.json
godot --headless --path app --script /absolute/research/audio/g3b/observer_bench.gd -- --out=/absolute/observer.json
godot --display-driver headless --audio-driver WASAPI --path app --script /absolute/research/audio/g3b/audio_probe.gd -- --driver=WASAPI --fps=60 --out=/absolute/mixer.json
```

`verify.py` copies the app to a fresh output folder, imports resources, runs the four focused programs, injects five real defects in that disposable copy, and restores the source between mutations. It rejects engine errors even with an exit code of zero. Never run deliberate defects in the live working tree.

`voice_bench.gd` reports seven-run warm synthesis/render medians and separate one-time table initialization. `observer_bench.gd` alternates five pairs per aircraft and verifies exact complete simulation checkpoints; refill is excluded from those tick timings. Both measure elapsed wall time, not CPU counters. Run timing jobs alone when qualifying a performance budget.

`audio_probe.gd` captures a dedicated Godot mixer bus before muted Master. Repeat at 30/60/144 FPS. On Windows use `--display-driver headless --audio-driver WASAPI`; `--headless` selects Dummy. Echo the requested driver with the user argument `--driver=WASAPI`: Godot can strip recognized engine flags from its argument query. The checker requires that label to match the actual runtime driver. Other platforms need their native driver name. No latency override was used for the retained Windows runs. Reports distinguish request-to-refill delay, spectral capture response and the driver's reported latency estimate. The 1024-frame Goertzel window and 256-frame hop limit temporal resolution. `status=ok` means the probe completed; inspect the queue, skips, capture validity and response fields to decide acceptance.

Dummy mixes 4096 output frames in a burst. It tests fallback stability, not the native 70 ms response gate. A microphone/loopback trial, multiple phase-aligned repetitions, other native drivers and real pilot evaluation remain separate evidence. Retained results and scope: [G3b report](../../../docs/research/audio/G3b/README.md).
