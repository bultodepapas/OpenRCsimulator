# TOD-09b static-cell diagnostic

2026-10-10 · Status: diagnostic evidence; the exact scenery-on pixel gate remains open.

[TOD-09b report](../README.md) · [Time-of-day plan](../../../../TIME-OF-DAY-PLAN.md)

The Compatibility capture compares an in-place legacy field with a fresh `FieldBuilder` field at 960×540. The legacy call reports `field_changed=false`, yet the pair differs at `(121,311)`, `(121,312)` and `(576,312)` by at most 4 channel values. Two independently rebuilt fresh fields match exactly. The false pixel-match results and their PNGs are retained under [`runs/`](runs/).

Visibility controls isolate the rendered source to the merged opaque `cell_*` scenery meshes: hiding flowers and motion or hiding `shadows_*` preserves the three-pixel difference; hiding `cell_*` or all scenery makes the pair exact. The static-cell geometry comparison checks serialized surface arrays for all 48 matching meshes. It compares 12,488,904 bytes, reports no mismatches, and produces the same SHA-256 for each side (`6fb5d5dddc97084fbbbece7e3097d4152ead6fc3b0f220d8c78dd9a84f62383a`). See the [JSON result](runs/static-cell-hash/report.json) and [captured console output](runs/static-cell-hash/console.log).

| Control | Result |
| --- | --- |
| Fresh A versus fresh B | Exact match; see [report and captures](runs/fresh-pair-on/) |
| Hide `flowers_*` and `Motion` | 3 pixels remain; [report and captures](runs/hide-flowers-motion/) |
| Hide `shadows_*` | 3 pixels remain; [report and captures](runs/hide-shadow/) |
| Hide `cell_*` | Exact match; [report and captures](runs/hide-cell/) |
| Hide all scenery | Exact match; [report and captures](runs/hide-all-scenery/) |
| Lift every cell by 0.05 m | 3 pixels remain; [report and captures](runs/cell-lift-005/) |
| Lift every cell by 1 m | 2 pixels remain and move to a different image bound; [report and captures](runs/cell-lift-1m/) |

The cell arrays are identical, but their render result is not under this comparison. The visibility and lift controls do not identify whether depth ordering, a cell edge, or another renderer interaction is responsible. The exact scenery-on gate is therefore still open. The legacy Apply pair is byte-identical with [scenery on](../apply-on/legacy-before.png) ([after](../apply-on/legacy-applied.png)) and [scenery off](../apply-off/legacy-before.png) ([after](../apply-off/legacy-applied.png)).

## Reproduction

The probes use the pinned Godot 4.7.2 binary, OpenGL Compatibility under Xvfb, and one llvmpipe thread. From the repository root, run the geometry and no-op legacy comparison with:

```sh
GODOT_BIN="$(app/get-godot.sh)"
OUT=/tmp/tod09b-static-cell-repro
mkdir -p "$OUT/static-cell-hash"
TOD09B_DIAG_ONLY=1 LP_NUM_THREADS=1 OPENRC_CODE_REVISION=diagnostic \
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path app \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/docs/research/time-of-day-investigations/TOD-09b/static-cell-diagnostic/static_cell_probe.gd" -- \
  --scenery=on --probe-case=00-legacy --probe-out="$OUT/static-cell-hash"
```

For a visibility control, use a new output directory and add one of `--probe-hide-scenery=flowers-motion`, `--probe-hide-scenery=shadow`, `--probe-hide-scenery=cell`, or `--probe-hide-scenery=all`. The cell-lift control instead uses `--probe-cell-lift=0.05` or `--probe-cell-lift=1.0`.

The separate fresh-versus-fresh control uses [`fresh_pair_probe.gd`](fresh_pair_probe.gd). It runs the same single legacy case, writes both fresh captures and their comparison into the requested output directory, then completes the existing exploratory frame-cost samples.

```sh
mkdir -p "$OUT/fresh-pair-on"
LP_NUM_THREADS=1 OPENRC_CODE_REVISION=diagnostic \
xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT_BIN" --path app \
  --rendering-driver opengl3 --audio-driver Dummy \
  --script "$PWD/docs/research/time-of-day-investigations/TOD-09b/static-cell-diagnostic/fresh_pair_probe.gd" -- \
  --scenery=on --probe-case=00-legacy --probe-out="$OUT/fresh-pair-on"
```
