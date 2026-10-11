# TOD-08a restoration probe

Status: source-build rendered checks pass, 2026-10-10. Contract and broader verification: [TOD-08a](../../../docs/research/time-of-day-investigations/TOD-08a/README.md).

`capture_restore.gd` exercises the real production Main at a fixed physical state and camera. It captures legacy → restored night → restored legacy → repeated night, checks first/second post-draw frames, requires exact repeated pixels and unchanged native physics, and keeps the simulation paused throughout. This is a restoration probe, not a trace player or a performance benchmark.

```sh
LP_NUM_THREADS=2 xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-08a/capture_restore.gd" -- \
  --probe-out=/tmp/openrc-tod08-default
OPENRC_SCENERY=on LP_NUM_THREADS=2 xvfb-run -a "$(app/get-godot.sh)" --path app --audio-driver Dummy \
  --script "$PWD/research/time-of-day/tod-08a/capture_restore.gd" -- \
  --probe-out=/tmp/openrc-tod08-scenery
```

The pinned Compatibility/llvmpipe evidence is preserved in [default](evidence/default/report.json) and [scenery](evidence/scenery/report.json), with four PNGs, an engine log and `SHA256SUMS` per directory. Both runs pass every recorded condition. Renderer logs retain the existing V-Sync capability warning and aircraft inertia advisory. They contain no engine/script errors. GPU performance, display calibration and pilot visibility acceptance remain separate.
