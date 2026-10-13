# HUD-01…10 flight overlays: evidence

Date: 2026-10-13. Base revision 69a7b5e plus uncommitted overlay changes. Machine: development VM, Godot 4.7.2, headless (no GPU). Scope: software behaviour and cost on this VM; no pilot reading and no target-hardware timing. Plan and current behaviour: [flight overlays plan](../../../plans/flight-overlays.md).

## Tests

| Test | Checks | What it proves |
| --- | --- | --- |
| `app/tests/test_overlay_units.gd` | 23 | Exact mph/ft factors, ft/min, language rule, rounding, no "−0.0", unknown value shown as "–" |
| `app/tests/test_overlay_telemetry.gd` | 36 | Level flight; 30° climb (vertical speed V·sin 30°, from world vertical); 60° level turn n = 2.0 from body loads; AGL over terrain; wind bearing and arrow per view heading; FAR distance (Stik ≈ 348.9 m); one fixture per warning, order, no STALL without a stall angle or on the wheels |
| `app/tests/test_overlay_manager.gd` | 61 | Settings validation and presets; Mode 1/2 stick and trim layout; contrast ≥ 4.5:1 over white and black sky; `[hud]` round trip and per-key fallback; a real mouse click on an × hides only that overlay, takes no focus, and a flight key still arrives; H/F3 cycles; warnings hide when closed or empty; no overlap at 1280×720 and 1920×1080 (Pilot, Full; Spanish with three warnings); the Pause dialog drives the manager and closes on Esc; a real flight scene (Home route) shows live values, H and F3 work, a menu hides the overlays |
| `app/tests/test_controls_reference.gd` | existing | H and F3 listed for the handled keys |

Shared UI consequences: the pause menu gains **Flight overlays** after Help (Home route only), so `test_ui_pause` and `test_ui_runway` reach End with five Down presses instead of four. H and F3 share one Help row ("Overlay preset · developer overlays") so the English and Spanish Help pages keep fitting 600 px (`test_ui_help`, `test_ui_atmosphere`); two separate rows measured 616 px.

## Trace identity

3 s headless traces, `--hud=legacy` versus `--hud=overlays`, Ugly Stik and Extra 300S: identical except the `# created_utc` header line (722 data rows each). Command, from `app/`:

```
"$(./get-godot.sh)" --headless --path . --audio-driver Dummy -- [--aircraft=gp-extra-300s-60] --hud=<mode> --trace=<file> --t=3
cmp <(grep -v '^# created_utc' legacy.csv) <(grep -v '^# created_utc' overlays.csv)
```

`--hud=fancy` is refused with exit code 31 (ERR_INVALID_PARAMETER).

## Cost

[`research/flight-overlays/bench_overlays.gd`](../../../../research/flight-overlays/bench_overlays.gd), 1200 frames per preset, live flight scene:

| Preset | Mean per frame | p95 | 10 Hz refresh frames (median / max) |
| --- | --- | --- | --- |
| Pilot | 63 µs | 275 µs | 256 µs / 1517 µs |
| Full | 60 µs | 278 µs | 260 µs / 1060 µs |

Building the snapshot every frame cost 209 µs mean (373 µs p95); refreshing numbers at 10 Hz and only sticks per frame brought it to ≈ 60 µs. In isolation the snapshot costs ≈ 50 µs (terrain sample ≈ 10 µs) and an unchanged-text refresh ≈ 23 µs; the rest of a refresh frame is relayout of labels whose text changed. Wall-clock numbers are VM-specific.

## Not covered

Rendered captures at 720p/1080p, readability on a pilot's monitor, and validation of warning thresholds in real flight.
